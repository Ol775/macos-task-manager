import AppKit
import Darwin
import IOKit
import SystemConfiguration

struct Proc: Identifiable {
    let id: Int32
    let name: String
    let isApp: Bool
    var cpu: Double      // percent of total CPU capacity, like Windows
    var mem: UInt64      // resident bytes
    var started: UInt64  // process start time (µs since epoch), to tell a pid from a later process that reuses it
    var icon: NSImage?
    var ppid: Int32 = 0
    var user = ""
    var threads: Int32 = 0
    var state = ""
    var disk: Double = 0 // read + write bytes per second
}

struct NetInterface: Identifiable {
    let id: String       // BSD name, e.g. en0
    let name: String     // "Wi-Fi"
    var rx: Double = 0   // bytes per second
    var tx: Double = 0
}

/// Pure helpers, kept apart from the sampling code so `--selftest` can check them.
enum Rates {
    /// Difference of two readings of a counter that wraps at 2^32 (the `if_data` byte counters do).
    static func delta32(_ old: UInt32, _ new: UInt32) -> UInt64 { UInt64(new &- old) }
    static func perSecond(_ bytes: UInt64, over ns: UInt64) -> Double { ns == 0 ? 0 : Double(bytes) / (Double(ns) / 1e9) }
    /// A rate that is finite and not negative; anything else (a zero interval gives infinity) counts as 0.
    static func sane(_ v: Double) -> Double { v.isFinite && v > 0 ? v : 0 }
    static func format(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 1 else { return "0 B/s" }      // NaN or infinity must never reach Int64(_:), which traps
        return ByteCountFormatter.string(fromByteCount: Int64(min(bytesPerSecond, 9e18)), countStyle: .decimal) + "/s"
    }
    /// A round axis maximum at least 20% above `peak`, never below `floor`.
    static func niceMax(_ peak: Double, floor: Double) -> Double {
        let target = max(peak * 1.2, floor)
        let mag = pow(10, (log10(target)).rounded(.down))
        for m in [1.0, 2, 5, 10] where m * mag >= target { return m * mag }
        return 10 * mag
    }
    static func stateName(_ status: UInt32) -> String {
        switch status { case 1: "Starting"; case 2: "Running"; case 3: "Sleeping"; case 4: "Stopped"; case 5: "Zombie"; default: "–" }
    }
}

@MainActor
final class Monitor: ObservableObject {
    static let shared = Monitor()
    static let samples = 60
    var procs: [Proc] = []
    var cpuHistory = [Double](repeating: 0, count: samples)
    var memHistory = [Double](repeating: 0, count: samples)
    var gpuHistory = [Double](repeating: 0, count: samples)
    var diskRead = [Double](repeating: 0, count: samples)    // bytes per second
    var diskWrite = [Double](repeating: 0, count: samples)
    var diskAvailable = true
    var interfaces: [NetInterface] = []
    var netRx: [String: [Double]] = [:]     // per BSD name, plus "all"
    var netTx: [String: [Double]] = [:]
    var memUsed: UInt64 = 0
    var memWired: UInt64 = 0
    var memCompressed: UInt64 = 0
    var gpuMemUsed: UInt64 = 0
    var gpuName = "GPU"
    var gpuCores: Int?
    var gpuAvailable = true
    var interval = 1.0
    var pidTotal = 0
    var pidReadable = 0
    let memTotal = ProcessInfo.processInfo.physicalMemory
    let cores = ProcessInfo.processInfo.activeProcessorCount
    let cpuName: String = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(cString: buf)
    }()

    private var lastCPUTicks: (busy: Double, total: Double)?
    private var lastProcNs: [Int32: UInt64] = [:]
    private var lastProcDisk: [Int32: UInt64] = [:]
    private struct Identity { let started: UInt64; let isApp: Bool; let icon: NSImage?; let name: String }
    private var identities: [Int32: Identity] = [:]
    private var gpuInfoRead = false
    private var lastProcSample: UInt64 = 0
    private var lastDisk: (r: UInt64, w: UInt64)?
    private var lastNet: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var lastSystemTime = DispatchTime.now().uptimeNanoseconds
    private var userNames: [uid_t: String] = [:]
    private lazy var friendlyNames: [String: String] = {
        var out: [String: String] = [:]
        for i in (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? [] {
            if let bsd = SCNetworkInterfaceGetBSDName(i) as String?, let n = SCNetworkInterfaceGetLocalizedDisplayName(i) as String? { out[bsd] = n }
        }
        return out
    }()
    private var lastTime = DispatchTime.now().uptimeNanoseconds
    private var timer: Timer?
    private let timebase: mach_timebase_info_data_t = {
        var t = mach_timebase_info_data_t(); mach_timebase_info(&t); return t
    }()

    private func refreshAppPIDs() {
        appPIDs = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
    }

    func start(interval: Double) {
        guard timer == nil else { return }
        refreshAppPIDs()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            appObservers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refreshAppPIDs() } })
        }
        self.interval = interval
        tick()
        schedule()
    }

    func setInterval(_ seconds: Double) {
        interval = seconds
        objectWillChange.send()
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// How many things currently show process data (the Processes page, the menu bar popover). Sampling every process is the
    /// expensive part of a tick, so it only runs while somebody is looking; the cheap system graphs always run.
    /// True while a window of this app is actually on screen (not minimized, hidden or fully covered).
    private var windowVisible: Bool { NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) && $0.level == .normal } }
    var processWatchers = 0
    var popoverOpen = false
    /// Apps mode only needs the dozen or so GUI apps, so only those are sampled; All Processes samples everything.
    var allProcessesWanted = false
    private var appPIDs = Set<Int32>()
    private var appObservers: [NSObjectProtocol] = []

    /// Called after every sample (the menu bar item refreshes its text from this).
    var onTick: (() -> Void)?

    /// The values below are plain properties rather than `@Published`: SwiftUI is told once per tick, and only while the
    /// window is visible or the popover is open, so a minimized or hidden app costs almost nothing.
    func tick(force: Bool = false) {
        sampleSystemIO()
        push(&cpuHistory, totalCPU())
        memUsed = usedMemory()
        push(&memHistory, Double(memUsed) / Double(memTotal) * 100)
        push(&gpuHistory, sampleGPU())
        let sinceProcs = Double(DispatchTime.now().uptimeNanoseconds - lastProcSample) / 1e9
        // All Processes is a few hundred rows that re-sort on every sample, so it refreshes every 2 s at most; Apps keeps the chosen rate.
        let procsDue = !allProcessesWanted || sinceProcs >= 1.9
        if force || popoverOpen || (processWatchers > 0 && windowVisible && procsDue) { lastProcSample = DispatchTime.now().uptimeNanoseconds; procs = sampleProcesses(force: force) }
        else { pidTotal = Int(max(proc_listallpids(nil, 0), 0)) }
        if force || popoverOpen || windowVisible { objectWillChange.send() }
        onTick?()
    }

    /// Samples the process list right now (used when a page that shows it appears, so it never starts out stale).
    func refreshProcesses() { procs = sampleProcesses() }

    /// Whole-disk throughput (IOBlockStorageDriver counters) and per-interface network throughput (getifaddrs counters).
    private func sampleSystemIO() {
        let now = DispatchTime.now().uptimeNanoseconds
        let dt = now - lastSystemTime
        lastSystemTime = now

        let d = diskTotals()
        diskAvailable = d != nil
        if let d {
            if let l = lastDisk, d.r >= l.r, d.w >= l.w {
                push(&diskRead, Rates.perSecond(d.r - l.r, over: dt)); push(&diskWrite, Rates.perSecond(d.w - l.w, over: dt))
            } else { push(&diskRead, 0); push(&diskWrite, 0) }
            lastDisk = d
        }

        var list: [NetInterface] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&head) == 0 {
            var p = head
            while let a = p?.pointee {
                defer { p = a.ifa_next }
                guard let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = a.ifa_data else { continue }
                let name = String(cString: a.ifa_name)
                guard let nice = friendlyNames[name], a.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING),
                      a.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
                let ifd = data.assumingMemoryBound(to: if_data.self).pointee
                var row = NetInterface(id: name, name: nice)
                if let l = lastNet[name] {
                    row.rx = Rates.perSecond(Rates.delta32(l.rx, ifd.ifi_ibytes), over: dt)
                    row.tx = Rates.perSecond(Rates.delta32(l.tx, ifd.ifi_obytes), over: dt)
                }
                lastNet[name] = (ifd.ifi_ibytes, ifd.ifi_obytes)
                list.append(row)
            }
            freeifaddrs(head)
        }
        list.sort { $0.id < $1.id }
        interfaces = list
        let all = ("all", list.reduce(0) { $0 + $1.rx }, list.reduce(0) { $0 + $1.tx })
        for (id, rx, tx) in list.map({ ($0.id, $0.rx, $0.tx) }) + [all] {
            var r = netRx[id] ?? [Double](repeating: 0, count: Self.samples), t = netTx[id] ?? r
            push(&r, rx); push(&t, tx); netRx[id] = r; netTx[id] = t
        }
        for id in netRx.keys where id != "all" && !list.contains(where: { $0.id == id }) { netRx[id] = nil; netTx[id] = nil }
    }

    private func diskTotals() -> (r: UInt64, w: UInt64)? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var r: UInt64 = 0, w: UInt64 = 0, found = false
        var service = IOIteratorNext(it)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(it) }
            guard let st = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { continue }
            r += (st["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            w += (st["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            found = true
        }
        return found ? (r, w) : nil
    }

    /// Reads utilisation from the IOAccelerator registry entry (Apple silicon and Intel/AMD). Only the statistics are fetched
    /// each time; the model name and core count are read once, since copying every property of the entry was the slowest part of a tick.
    private func sampleGPU() -> Double {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else {
            gpuAvailable = false; return 0
        }
        defer { IOObjectRelease(it) }
        var usage = 0.0
        var service = IOIteratorNext(it)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(it) }
            if !gpuInfoRead { readGPUInfo(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            let u = (stats["Device Utilization %"] as? NSNumber) ?? (stats["GPU Activity(%)"] as? NSNumber)
            usage = max(usage, u?.doubleValue ?? 0)
            if let m = stats["In use system memory"] as? NSNumber { gpuMemUsed = m.uint64Value }
        }
        gpuInfoRead = true
        return usage
    }

    private func readGPUInfo(_ service: io_object_t) {
        if let model = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
            if let m = model as? String { gpuName = m }
            else if let data = model as? Data, let m = String(data: data, encoding: .utf8) { gpuName = m.trimmingCharacters(in: CharacterSet(["\0"])) }
        }
        if let c = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int { gpuCores = c }
    }

    private func push(_ a: inout [Double], _ v: Double) { a.removeFirst(); a.append(v) }

    private func totalCPU() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return 0 }
        let t = info.cpu_ticks   // user, system, idle, nice
        let busy = Double(t.0) + Double(t.1) + Double(t.3)
        let total = busy + Double(t.2)
        defer { lastCPUTicks = (busy, total) }
        guard let last = lastCPUTicks, total > last.total else { return 0 }
        return (busy - last.busy) / (total - last.total) * 100
    }

    private func usedMemory() -> UInt64 {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return 0 }
        let page = UInt64(vm_kernel_page_size)
        memWired = UInt64(vm.wire_count) * page
        memCompressed = UInt64(vm.compressor_page_count) * page
        // Matches Activity Monitor's "Memory Used": app + wired + compressed
        return (UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * UInt64(vm_kernel_page_size)
    }

    /// How many processes macOS lets this app inspect (used by the Permissions card when only apps are being sampled).
    func countReadable() {
        var pids = [Int32](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 64)
        let n = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size)))
        var ti = proc_taskinfo(); let size = Int32(MemoryLayout<proc_taskinfo>.size)
        pidTotal = max(n, 0)
        pidReadable = pids.prefix(max(n, 0)).filter { $0 > 0 && proc_pidinfo($0, PROC_PIDTASKINFO, 0, &ti, size) == size }.count
    }

    private func sampleProcesses(force: Bool = false) -> [Proc] {
        let now = DispatchTime.now().uptimeNanoseconds
        let wall = Double(now - lastTime)
        lastTime = now

        var seen = Set<Int32>()
        var pids = [Int32](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 64)
        let n = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size)))
        let everything = allProcessesWanted || force
        if !everything { pids = Array(appPIDs); }
        var ns: [Int32: UInt64] = [:]
        var diskBytes: [Int32: UInt64] = [:]
        var out: [Proc] = []
        var nameBuf = [CChar](repeating: 0, count: 256)

        for pid in (everything ? Array(pids.prefix(max(n, 0))) : pids) where pid > 0 {
            var ti = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            // Fails for other users' processes unless root; those are skipped.
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, size) == size else { continue }
            var bsd = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            let started = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize ? bsd.pbi_start_tvsec * 1_000_000 + bsd.pbi_start_tvusec : 0
            let abs = ti.pti_total_user + ti.pti_total_system
            let cpuNs = abs * UInt64(timebase.numer) / UInt64(timebase.denom)
            ns[pid] = cpuNs
            let cpu = Rates.sane(lastProcNs[pid].map { cpuNs >= $0 ? Double(cpuNs - $0) / wall * 100 / Double(cores) : 0 } ?? 0)
            var ri = rusage_info_v4()
            let rok = withUnsafeMutablePointer(to: &ri) { p in
                p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            } == 0
            let io = rok ? ri.ri_diskio_bytesread + ri.ri_diskio_byteswritten : 0
            diskBytes[pid] = io
            let diskRate = Rates.sane(lastProcDisk[pid].map { io >= $0 ? Double(io - $0) / (wall / 1e9) : 0 } ?? 0)
            // Name, icon and app-ness never change for a running process, and asking AppKit for them is the costly part of a
            // sample, so look them up once per process (a reused pid has a different start time and is looked up again).
            let info: Identity
            if let c = identities[pid], c.started == started { info = c } else {
                let app = NSRunningApplication(processIdentifier: pid).flatMap { $0.activationPolicy == .regular ? $0 : nil }
                info = Identity(started: started, isApp: app != nil, icon: app?.icon,
                                name: app?.localizedName ?? (proc_name(pid, &nameBuf, 256) > 0 ? String(cString: nameBuf) : "pid \(pid)"))
                identities[pid] = info
            }
            seen.insert(pid)
            out.append(Proc(id: pid, name: info.name, isApp: info.isApp, cpu: cpu, mem: ti.pti_resident_size, started: started, icon: info.icon,
                            ppid: Int32(bitPattern: bsd.pbi_ppid), user: userName(bsd.pbi_uid), threads: ti.pti_threadnum,
                            state: Rates.stateName(bsd.pbi_status), disk: diskRate))
        }
        lastProcNs = ns
        lastProcDisk = diskBytes
        if identities.count > seen.count { identities = identities.filter { seen.contains($0.key) } }
        pidTotal = max(n, 0)
        if everything { pidReadable = out.count }
        return out
    }

    private func userName(_ uid: uid_t) -> String {
        if let n = userNames[uid] { return n }
        let n = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? String(uid)
        userNames[uid] = n
        return n
    }
}

import AppKit
import Darwin
import IOKit

struct Proc: Identifiable {
    let id: Int32
    let name: String
    let isApp: Bool
    var cpu: Double      // percent of total CPU capacity, like Windows
    var mem: UInt64      // resident bytes
    var started: UInt64  // process start time (µs since epoch), to tell a pid from a later process that reuses it
    var icon: NSImage?
}

@MainActor
final class Monitor: ObservableObject {
    static let samples = 60
    @Published var procs: [Proc] = []
    @Published var cpuHistory = [Double](repeating: 0, count: samples)
    @Published var memHistory = [Double](repeating: 0, count: samples)
    @Published var gpuHistory = [Double](repeating: 0, count: samples)
    @Published var memUsed: UInt64 = 0
    @Published var memWired: UInt64 = 0
    @Published var memCompressed: UInt64 = 0
    @Published var gpuMemUsed: UInt64 = 0
    @Published var gpuName = "GPU"
    @Published var gpuCores: Int?
    @Published var gpuAvailable = true
    @Published var interval = 1.0
    @Published var pidTotal = 0
    @Published var pidReadable = 0
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
    private var lastTime = DispatchTime.now().uptimeNanoseconds
    private var timer: Timer?
    private let timebase: mach_timebase_info_data_t = {
        var t = mach_timebase_info_data_t(); mach_timebase_info(&t); return t
    }()

    func start(interval: Double) {
        guard timer == nil else { return }
        self.interval = interval
        tick()
        schedule()
    }

    func setInterval(_ seconds: Double) {
        interval = seconds
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        push(&cpuHistory, totalCPU())
        memUsed = usedMemory()
        push(&memHistory, Double(memUsed) / Double(memTotal) * 100)
        push(&gpuHistory, sampleGPU())
        procs = sampleProcesses()
    }

    /// Reads utilisation from the IOAccelerator registry entry (Apple silicon and Intel/AMD).
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
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else { continue }
            if let model = dict["model"] as? String { gpuName = model }
            else if let data = dict["model"] as? Data, let m = String(data: data, encoding: .utf8) {
                gpuName = m.trimmingCharacters(in: CharacterSet(["\0"]))
            }
            if let c = dict["gpu-core-count"] as? Int { gpuCores = c }
            guard let stats = dict["PerformanceStatistics"] as? [String: Any] else { continue }
            let u = (stats["Device Utilization %"] as? NSNumber) ?? (stats["GPU Activity(%)"] as? NSNumber)
            usage = max(usage, u?.doubleValue ?? 0)
            if let m = stats["In use system memory"] as? NSNumber { gpuMemUsed = m.uint64Value }
        }
        return usage
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

    private func sampleProcesses() -> [Proc] {
        let now = DispatchTime.now().uptimeNanoseconds
        let wall = Double(now - lastTime)
        lastTime = now

        var apps: [Int32: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            apps[app.processIdentifier] = app
        }

        var pids = [Int32](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 64)
        let n = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size)))
        var ns: [Int32: UInt64] = [:]
        var out: [Proc] = []
        var nameBuf = [CChar](repeating: 0, count: 256)

        for pid in pids.prefix(max(n, 0)) where pid > 0 {
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
            let cpu = lastProcNs[pid].map { cpuNs >= $0 ? Double(cpuNs - $0) / wall * 100 / Double(cores) : 0 } ?? 0
            let name = apps[pid]?.localizedName ?? (proc_name(pid, &nameBuf, 256) > 0 ? String(cString: nameBuf) : "pid \(pid)")
            out.append(Proc(id: pid, name: name, isApp: apps[pid] != nil, cpu: cpu, mem: ti.pti_resident_size, started: started, icon: apps[pid]?.icon))
        }
        lastProcNs = ns
        pidTotal = max(n, 0)
        pidReadable = out.count
        return out
    }
}

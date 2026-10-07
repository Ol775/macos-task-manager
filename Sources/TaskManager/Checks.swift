import AppKit
import Darwin

/// `TaskManager --selftest`: pure-logic checks plus a live sample of this very process.
enum Checks {
    @MainActor static func run() -> Bool {
        var ok = true
        func check(_ c: Bool, _ m: String) { if !c { print("FAIL: \(m)"); ok = false } }

        // Counters and formatting
        check(Rates.delta32(UInt32.max - 5, 10) == 16, "32-bit counter wrap")
        check(Rates.delta32(100, 150) == 50, "counter delta")
        check(Rates.perSecond(1_000_000, over: 500_000_000) == 2_000_000, "bytes per second")
        check(Rates.perSecond(5, over: 0) == 0, "zero interval")
        check(Rates.niceMax(0, floor: 1_000_000) == 1_000_000, "axis floor")
        check(Rates.niceMax(3_000_000, floor: 1_000_000) == 5_000_000, "axis rounds up to 1/2/5")
        check(Rates.niceMax(9_000_000, floor: 1_000_000) == 20_000_000, "axis headroom")
        check(Rates.format(0) == "0 B/s" && Rates.format(2_500_000) == "2.5 MB/s", "rate format: \(Rates.format(0)) / \(Rates.format(2_500_000))")
        check(Rates.stateName(2) == "Running" && Rates.stateName(99) == "–", "process state names")

        check(Rates.format(.nan) == "0 B/s" && Rates.format(.infinity) == "0 B/s" && Rates.format(-5) == "0 B/s", "rate format survives NaN and infinity")
        check(Rates.sane(.infinity) == 0 && Rates.sane(.nan) == 0 && Rates.sane(-1) == 0 && Rates.sane(3) == 3, "sane rates")
        check(MenuBarLabel.rate(.nan) == "0 B/s" && MenuBarLabel.rate(.infinity) == "0 B/s", "menu bar rate survives NaN and infinity")

        // Columns
        check(ProcColumn.decode(nil) == ProcColumn.defaults, "default columns")
        check(ProcColumn.decode("pid,cpu,bogus,cpu") == [.cpu, .pid], "columns: unknown dropped, order canonical")
        check(ProcColumn.decode("") == [], "columns: empty means none")
        check(ProcColumn.decode(ProcColumn.encode(ProcColumn.optional)) == ProcColumn.optional, "columns round trip")
        check(ProcInspector.port(Int32(bitPattern: 0x5000)) == 80 && ProcInspector.port(Int32(0x901F)) == 8080, "port byte order")

        // Menu bar
        check(MenuMetric.decode(nil) == [.cpu, .memory], "default menu bar items")
        check(MenuMetric.decode("network,cpu,bogus,cpu") == [.cpu, .network], "menu bar items: unknown dropped, order canonical")
        check(MenuMetric.decode(MenuMetric.encode(MenuMetric.allCases)) == MenuMetric.allCases, "menu bar items round trip")
        let v = MenuBarLabel.Values(cpu: 34.4, memory: 71.6, gpu: 0, disk: 2_500_000, network: 12_345)
        check(MenuBarLabel.text([.cpu, .memory], labels: true, v) == "CPU 34%  MEM 72%", "menu bar text: \(MenuBarLabel.text([.cpu, .memory], labels: true, v))")
        check(MenuBarLabel.text([.cpu], labels: false, v) == "34%", "menu bar text without labels")
        check(MenuBarLabel.text([.disk, .network], labels: true, v) == "DSK 2.5 MB/s  NET 12.3 KB/s", "menu bar rates: \(MenuBarLabel.text([.disk, .network], labels: true, v))")
        check(MenuBarLabel.text([], labels: true, v).isEmpty && MenuBarLabel.rate(0) == "0 B/s" && MenuBarLabel.rate(999) == "999 B/s", "menu bar edge cases")

        // Contrast in every theme (WCAG: 4.5:1 for text and fills that carry white text, 3:1 for chart lines)
        let whiteCard = NSColor.white, darkCard = NSColor(white: 0.118, alpha: 1)
        for t in AccentTheme.allCases where t != .custom {
            let (dark, light) = t.colors(custom: "")
            check(light.contrast(on: whiteCard) >= 4.5, "\(t.rawValue): light accent on white is \(String(format: "%.2f", light.contrast(on: whiteCard)))")
            check(dark.contrast(on: darkCard) >= 4.5, "\(t.rawValue): dark accent on dark card is \(String(format: "%.2f", dark.contrast(on: darkCard)))")
        }
        for (name, hex) in [("cpu", AppSettings.defaultColors.cpu), ("memory", AppSettings.defaultColors.memory), ("gpu", AppSettings.defaultColors.gpu),
                            ("disk", AppSettings.defaultColors.disk), ("network", AppSettings.defaultColors.network)] {
            let base = NSColor(hexString: hex)!
            let deep = base.blended(withFraction: 0.28, of: .black) ?? base
            check(deep.contrast(on: whiteCard) >= 3, "\(name) chart colour on white is \(String(format: "%.2f", deep.contrast(on: whiteCard)))")
            check(base.contrast(on: darkCard) >= 3, "\(name) chart colour on dark card is \(String(format: "%.2f", base.contrast(on: darkCard)))")
        }

        // Live sampling of this process
        let m = Monitor()
        m.tick()
        Thread.sleep(forTimeInterval: 0.3)
        m.tick()
        let me = getpid()
        if let p = m.procs.first(where: { $0.id == me }) {
            check(p.threads > 0, "own thread count")
            check(p.state == "Running", "own state is \(p.state)")
            check(!p.user.isEmpty && p.ppid > 0, "own user and parent")
            check(p.started != 0, "own start time")
        } else { check(false, "own process listed") }
        check(m.procs.count > 5, "process list has entries")
        check(m.netRx["all"]?.count == Monitor.samples, "network history length")

        // Details of this process
        let d = ProcInspector.load(pid: me, ppid: getppid())
        check(!d.path.isEmpty, "own executable path")
        check(d.fdCount > 0, "own open files")
        check(d.signing.kind != "Unknown", "own signing status: \(d.signing.kind)")

        // Code-signature labels come from the certificate chain
        let terminal = ProcInspector.signing(path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")
        check(terminal.kind == "Apple" && terminal.valid, "Terminal is labelled Apple: \(terminal.kind)")
        let mine = ProcInspector.signing(path: Bundle.main.executablePath ?? "")
        check(mine.kind == "Ad hoc" || mine.kind == "Developer ID", "own signature label: \(mine.kind)")
        check(ProcInspector.signing(path: "/usr/bin/true").kind != "Unverified certificate", "system tools are not unverified")

        // Listening socket shows up as an open port
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in(); addr.sin_family = sa_family_t(AF_INET); addr.sin_addr.s_addr = UInt32(INADDR_LOOPBACK).bigEndian
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } == 0
        if bound, listen(sock, 1) == 0 {
            var out = sockaddr_in(), len = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &out) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &len) } }
            let port = Int(UInt16(bigEndian: out.sin_port))
            check(ProcInspector.ports(me).0.contains { $0.proto == "TCP" && $0.local == port && $0.state == "Listening" }, "listening port \(port) reported")
        } else { check(false, "could not open a test socket") }
        close(sock)
        return ok
    }
}

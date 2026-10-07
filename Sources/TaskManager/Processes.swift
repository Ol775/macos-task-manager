import SwiftUI
import AppKit
import Darwin
import Security


// MARK: - Columns

enum ProcColumn: String, CaseIterable, Identifiable {
    case name, cpu, mem, disk, pid, user, threads, state, started
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: "Name"; case .cpu: "CPU"; case .mem: "Memory"; case .disk: "Disk"; case .pid: "PID"
        case .user: "User"; case .threads: "Threads"; case .state: "State"; case .started: "Started"
        }
    }
    var width: CGFloat {
        switch self {
        case .name: 0; case .cpu: 76; case .mem: 98; case .disk: 98; case .pid: 70
        case .user: 100; case .threads: 76; case .state: 86; case .started: 150
        }
    }
    /// Text columns read left to right; numbers line up on the right.
    var leading: Bool { self == .name || self == .user || self == .state }
    static let optional = allCases.filter { $0 != .name }
    static let defaults: [ProcColumn] = [.cpu, .mem, .disk, .pid]

    static func encode(_ cols: [ProcColumn]) -> String { cols.map(\.rawValue).joined(separator: ",") }
    /// Unknown names are dropped, duplicates removed and the canonical order kept; nil (never saved) gives the defaults.
    static func decode(_ s: String?) -> [ProcColumn] {
        guard let s else { return defaults }
        let want = Set(s.split(separator: ",").compactMap { ProcColumn(rawValue: String($0)) })
        return optional.filter(want.contains)
    }
}

// MARK: - Details of one process

struct PortInfo: Identifiable {
    let id = UUID()
    let proto: String
    let local: Int
    let state: String
    let remote: Int?
}

struct SigningInfo {
    var kind = "Unknown"      // Apple, Developer ID, App Store, Ad hoc, Unsigned, Invalid
    var detail = ""           // signer / team
    var valid = false
}

struct ProcDetails {
    var path = ""
    var parent = ""
    var ports: [PortInfo] = []
    var signing = SigningInfo()
    var fdCount = 0
}

enum ProcInspector {
    static func load(pid: Int32, ppid: Int32) -> ProcDetails {
        var d = ProcDetails()
        d.path = path(pid) ?? ""
        d.parent = ppid > 0 ? ((ppid == 1 ? "launchd" : name(ppid)).map { "\($0) (\(ppid))" } ?? "pid \(ppid)") : "–"
        (d.ports, d.fdCount) = ports(pid)
        if !d.path.isEmpty { d.signing = signing(path: d.path) }
        return d
    }

    static func path(_ pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
    }

    static func name(_ pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        return proc_name(pid, &buf, 256) > 0 ? String(cString: buf) : nil
    }

    /// Network byte order → host.
    static func port(_ raw: Int32) -> Int { Int(UInt16(truncatingIfNeeded: raw).byteSwapped) }

    static func tcpState(_ s: Int32) -> String {
        switch s {
        case 1: "Listening"; case 2, 3: "Connecting"; case 4: "Established"
        case 5, 6, 7, 8, 9, 10, 11: "Closing"; default: "Closed"
        }
    }

    /// Open TCP/UDP sockets of the process (local ports only; remote addresses are not shown).
    static func ports(_ pid: Int32) -> ([PortInfo], Int) {
        let need = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard need > 0 else { return ([], 0) }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(need) / MemoryLayout<proc_fdinfo>.size + 8)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * MemoryLayout<proc_fdinfo>.size))
        guard got > 0 else { return ([], 0) }
        let list = fds.prefix(Int(got) / MemoryLayout<proc_fdinfo>.size)
        var out: [PortInfo] = []
        for fd in list where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var si = socket_fdinfo()
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &si, Int32(MemoryLayout<socket_fdinfo>.size)) == Int32(MemoryLayout<socket_fdinfo>.size),
                  si.psi.soi_family == AF_INET || si.psi.soi_family == AF_INET6 else { continue }
            if si.psi.soi_kind == Int32(SOCKINFO_TCP) {
                let t = si.psi.soi_proto.pri_tcp
                let remote = port(t.tcpsi_ini.insi_fport)
                out.append(PortInfo(proto: "TCP", local: port(t.tcpsi_ini.insi_lport), state: tcpState(t.tcpsi_state), remote: remote > 0 ? remote : nil))
            } else if si.psi.soi_kind == Int32(SOCKINFO_IN) {
                out.append(PortInfo(proto: "UDP", local: port(si.psi.soi_proto.pri_in.insi_lport), state: "Open", remote: nil))
            }
        }
        out.sort { ($0.state == "Listening" ? 0 : 1, $0.local) < ($1.state == "Listening" ? 0 : 1, $1.local) }
        return (out, list.count)
    }

    /// Signature of the enclosing .app (or the executable itself).
    static func signing(path: String) -> SigningInfo {
        var target = path
        if let r = path.range(of: ".app/") { target = String(path[..<r.lowerBound]) + ".app" }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: target) as CFURL, [], &code) == errSecSuccess, let code else { return SigningInfo() }
        let check = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: 0), nil)
        if check == errSecCSUnsigned { return SigningInfo(kind: "Unsigned", detail: "", valid: false) }
        var cf: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &cf) == errSecSuccess,
              let info = cf as? [String: Any] else { return SigningInfo(kind: "Unknown") }
        let valid = check == errSecSuccess
        let flags = (info[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        let leaf = (info[kSecCodeInfoCertificates as String] as? [SecCertificate])?.first.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? ""
        var s = SigningInfo(valid: valid)
        if !valid { s.kind = "Invalid signature" }
        else if flags & 0x2 != 0 { s.kind = "Ad hoc" }
        else if info[kSecCodeInfoPlatformIdentifier as String] != nil || leaf.hasPrefix("Software Signing") { s.kind = "Apple" }
        else if leaf.hasPrefix("Developer ID") { s.kind = "Developer ID" }
        else if leaf.contains("Mac App Store") || leaf.hasPrefix("Apple Mac OS Application Signing") { s.kind = "Mac App Store" }
        else { s.kind = "Signed" }
        s.detail = [leaf.isEmpty || leaf.hasPrefix("Software Signing") ? nil : leaf, team.map { "Team \($0)" }].compactMap { $0 }.joined(separator: " · ")
        return s
    }
}

// MARK: - End Task

/// Asks first, then signals only if `pid` is still the process that was listed (a pid can be reused by a different
/// program after the original exits).
@MainActor func endTask(_ p: Proc) {
    guard p.id > 1 else { return }
    let confirm = NSAlert()
    confirm.messageText = "End “\(p.name)”?"
    confirm.informativeText = "It will be asked to quit. Unsaved work in it may be lost."
    confirm.addButton(withTitle: "End Task").hasDestructiveAction = true
    confirm.addButton(withTitle: "Cancel")
    guard confirm.runModal() == .alertFirstButtonReturn else { return }

    var bsd = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    let now = proc_pidinfo(p.id, PROC_PIDTBSDINFO, 0, &bsd, size) == size ? bsd.pbi_start_tvsec * 1_000_000 + bsd.pbi_start_tvusec : 0
    guard now != 0, now == p.started else { return report("Already closed", "“\(p.name)” is no longer running.") }
    guard kill(p.id, SIGTERM) != 0 else { return }
    let e = errno
    report(e == EPERM ? "Not permitted" : "Couldn’t end task", e == EPERM ? "macOS only lets you end your own processes." : String(cString: strerror(e)))
}

@MainActor private func report(_ title: String, _ text: String) {
    let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
}

// MARK: - List

/// A plain scrolling list instead of SwiftUI's Table: Table is an NSTableView underneath, and re-sorting it every second
/// (by CPU, say) makes macOS log "reentrant operation in its NSTableView delegate", a warning Apple says will become an assert.
struct ProcessesView: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var settings: AppSettings
    @State private var search = ""
    @State private var selection: Int32?
    @State private var key = ProcColumn.cpu
    @State private var ascending = false
    @AppStorage("showDetails") private var showDetails = false

    private var rows: [Proc] {
        m.procs
            .filter { (!settings.appsOnly || $0.isApp) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || String($0.id) == search) }
            .sorted {
                let r: Bool
                switch key {
                case .name: r = $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                case .cpu: r = $0.cpu < $1.cpu
                case .mem: r = $0.mem < $1.mem
                case .disk: r = $0.disk < $1.disk
                case .pid: r = $0.id < $1.id
                case .user: r = $0.user.localizedCaseInsensitiveCompare($1.user) == .orderedAscending
                case .threads: r = $0.threads < $1.threads
                case .state: r = $0.state < $1.state
                case .started: r = $0.started < $1.started
                }
                return ascending ? r : !r
            }
    }

    private var columns: [ProcColumn] { settings.columns }
    private var selected: Proc? { selection.flatMap { id in m.procs.first { $0.id == id } } }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Processes", subtitle: "\(rows.count) \(settings.appsOnly ? "apps" : "processes")") { EmptyView() }
            HStack(spacing: 10) {
                PillPicker(selection: $settings.appsOnly, options: [(true, "Apps"), (false, "All Processes")])
                Spacer(minLength: 8)
                searchField
                columnMenu
                Button { showDetails.toggle() } label: { Label("Details", systemImage: "sidebar.right") }
                    .help("Show details for the selected process").disabled(selection == nil && !showDetails)
                Button { if let p = selected { endTask(p) } } label: { Label("End Task", systemImage: "xmark.circle") }
                    .help("End the selected task").disabled(selection == nil)
            }
            .labelStyle(.iconOnly).controlSize(.large)
            GeometryReader { g in
                // Scrolls sideways when the chosen columns don't fit the window.
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                        Divider()
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { i, p in row(p, striped: i % 2 == 1) }
                            }
                        }
                    }
                    .frame(width: max(g.size.width, 160 + columns.reduce(0) { $0 + $1.width }), height: g.size.height)
                }
            }
            .card().clipShape(RoundedRectangle(cornerRadius: settings.corners.radius, style: .continuous))
        }
        .padding(24).frame(maxHeight: .infinity, alignment: .top)
        .inspector(isPresented: Binding(get: { showDetails && selection != nil }, set: { showDetails = $0 })) {
            if let p = selected { ProcessDetailsView(proc: p, close: { showDetails = false }).inspectorColumnWidth(min: 280, ideal: 320, max: 440) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $search).textFieldStyle(.plain).frame(minWidth: 90, maxWidth: 150)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    private var columnMenu: some View {
        Menu {
            ForEach(ProcColumn.optional) { c in
                Toggle(c.title, isOn: columnBinding(c))
            }
            Divider()
            Button("Reset to Defaults") { settings.columns = ProcColumn.defaults }
        } label: { Label("Columns", systemImage: "tablecells") }
        .menuIndicator(.hidden).fixedSize().help("Choose columns")
    }

    private func columnBinding(_ c: ProcColumn) -> Binding<Bool> {
        Binding(get: { settings.columns.contains(c) },
                set: { on in settings.columns = ProcColumn.optional.filter { $0 == c ? on : settings.columns.contains($0) } })
    }

    private var header: some View {
        HStack(spacing: 0) {
            headerCell(.name).frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            ForEach(columns) { c in headerCell(c).frame(width: c.width) }
        }
        .frame(height: 32)
        .contextMenu { ForEach(ProcColumn.optional) { c in Toggle(c.title, isOn: columnBinding(c)) } }
    }

    private func headerCell(_ c: ProcColumn) -> some View {
        Button {
            if key == c { ascending.toggle() } else { key = c; ascending = c.leading || c == .pid }
        } label: {
            HStack(spacing: 3) {
                if !c.leading, key == c { chevron }
                Text(c.title).font(.system(size: 12, weight: .semibold))
                if c.leading, key == c { chevron }
            }
            .foregroundStyle(key == c ? Color.primary : Color.secondary)
            .padding(.horizontal, 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: c.leading ? .leading : .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(c.title)")
    }

    private var chevron: some View {
        Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
    }

    private func row(_ p: Proc, striped: Bool) -> some View {
        let on = selection == p.id
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                if let icon = p.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                else { Image(systemName: "gearshape.fill").frame(width: 20, height: 20).foregroundStyle(.secondary) }
                Text(p.name).lineLimit(1)
            }
            .padding(.leading, 12).frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            ForEach(columns) { c in cell(c, p) }
        }
        .font(.system(size: 13)).frame(height: 28)
        .background(on ? settings.accent.opacity(0.20) : (striped ? Color.primary.opacity(0.04) : .clear))
        .overlay(alignment: .leading) { if on { Rectangle().fill(settings.accent).frame(width: 3) } }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { selection = p.id; showDetails = true }
        .onTapGesture { selection = p.id }
        .contextMenu {
            Button("Show Details") { selection = p.id; showDetails = true }
            Button("Reveal in Finder") { if let path = ProcInspector.path(p.id) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } }
            Divider()
            Button("End Task", role: .destructive) { endTask(p) }
        }
        .accessibilityElement(children: .combine).accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private func cell(_ c: ProcColumn, _ p: Proc) -> some View {
        switch c {
        case .cpu: heat(String(format: "%.1f%%", p.cpu), c, share: p.cpu / 100, color: settings.cpuColor, dim: p.cpu < 1)
        case .mem: heat(bytes(p.mem), c, share: Double(p.mem) / Double(m.memTotal) * 4, color: settings.memoryColor)
        case .disk: heat(p.disk < 1 ? "0 B/s" : Rates.format(p.disk), c, share: p.disk / 50_000_000, color: settings.diskColor, dim: p.disk < 1)
        case .pid: plain(String(p.id), c, dim: true)
        case .user: plain(p.user, c, dim: true)
        case .threads: plain(String(p.threads), c)
        case .state: plain(p.state, c, dim: p.state == "Sleeping")
        case .started: plain(p.started == 0 ? "–" : startFormat(p.started), c, dim: true)
        case .name: EmptyView()
        }
    }

    private func plain(_ text: String, _ c: ProcColumn, dim: Bool = false) -> some View {
        Text(text).monospacedDigit().lineLimit(1).opacity(dim ? 0.6 : 1)
            .padding(.horizontal, 12).frame(width: c.width, alignment: c.leading ? .leading : .trailing)
    }

    /// Cells for load columns get a faint tint that deepens with the value, like the heat map in Windows Task Manager.
    private func heat(_ text: String, _ c: ProcColumn, share: Double, color: Color, dim: Bool = false) -> some View {
        plain(text, c, dim: dim).frame(maxHeight: .infinity)
            .background(color.opacity(min(max(share, 0), 1) * 0.30))
    }

    private func startFormat(_ micros: UInt64) -> String {
        let d = Date(timeIntervalSince1970: Double(micros) / 1e6)
        return Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened) : d.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Details panel

struct ProcessDetailsView: View {
    @EnvironmentObject var settings: AppSettings
    let proc: Proc
    let close: () -> Void
    @State private var details: ProcDetails?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    if let icon = proc.icon { Image(nsImage: icon).resizable().frame(width: 44, height: 44) }
                    else { Image(systemName: "gearshape.fill").font(.system(size: 28)).frame(width: 44, height: 44).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(proc.name).font(.system(size: 18, weight: .bold, design: .rounded)).lineLimit(2)
                        Text("PID " + String(proc.id)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Hide details")
                }
                group("Process") {
                    row("State", proc.state)
                    row("Threads", String(proc.threads))
                    row("CPU", String(format: "%.1f%%", proc.cpu))
                    row("Memory", bytes(proc.mem))
                    row("Disk", Rates.format(proc.disk))
                    if let d = details { row("Parent", d.parent); row("Open files", String(d.fdCount)) }
                }
                if let d = details {
                    group("Location") {
                        Text(d.path.isEmpty ? "macOS doesn’t share this path." : d.path).font(.system(size: 12)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        if !d.path.isEmpty {
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: d.path)]) }
                                .padding(.bottom, 8)
                        }
                    }
                    group("Code signature") {
                        HStack(spacing: 8) {
                            Image(systemName: d.signing.valid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(d.signing.valid ? Color.green : Color.orange)
                            Text(d.signing.kind).fontWeight(.medium)
                        }.padding(.vertical, 6)
                        if !d.signing.detail.isEmpty {
                            Text(d.signing.detail).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled).padding(.bottom, 8)
                        }
                    }
                    group("Open ports") {
                        if d.ports.isEmpty { Text("No open TCP or UDP sockets.").foregroundStyle(.secondary).padding(.vertical, 6) }
                        ForEach(d.ports.prefix(40)) { p in
                            HStack {
                                Text(p.proto).fontWeight(.medium).frame(width: 36, alignment: .leading)
                                Text(String(p.local)).monospacedDigit()
                                if let r = p.remote { Text("→ \(r)").monospacedDigit().foregroundStyle(.secondary) }
                                Spacer(minLength: 8)
                                Text(p.state).foregroundStyle(.secondary)
                            }.font(.system(size: 12.5)).padding(.vertical, 3)
                        }
                        if d.ports.count > 40 { Text("and \(d.ports.count - 40) more").font(.caption).foregroundStyle(.secondary) }
                    }
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                }
            }
            .padding(18)
        }
        .task(id: "\(proc.id)-\(proc.started)") {
            details = nil
            let pid = proc.id, ppid = proc.ppid
            details = await Task.detached(priority: .userInitiated) { ProcInspector.load(pid: pid, ppid: ppid) }.value
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 0) { content() }.padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.system(size: 13)).padding(.vertical, 6)
    }
}

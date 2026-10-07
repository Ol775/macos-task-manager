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
        let base: CGFloat
        switch self {
        case .name: base = 0; case .cpu: base = 76; case .mem: base = 98; case .disk: base = 98; case .pid: base = 70
        case .user: base = 100; case .threads: base = 76; case .state: base = 86; case .started: base = 150
        }
        return ts(base)
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
    /// A green seal only for code whose signer Apple vouches for. Ad hoc code is intact but anyone could have made it.
    var vouched: Bool { valid && ["Apple", "Mac App Store", "Developer ID", "Apple-issued certificate"].contains(kind) }
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

    /// True when the code satisfies a code-signing requirement (checks the signature's certificate chain, not just its text).
    private static func satisfies(_ code: SecStaticCode, _ requirement: String) -> Bool {
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: UInt32(kSecCSBasicValidateOnly)), req) == errSecSuccess
    }

    /// Who signed the enclosing .app (or the executable itself). The label comes from the certificate chain: a certificate that
    /// merely has a familiar-looking name (anyone can create one) is reported as unverified, never as Apple or Developer ID.
    /// Only the signature itself is checked (kSecCSBasicValidateOnly), not every resource, so a large app doesn't take minutes.
    static func signing(path: String) -> SigningInfo {
        var target = path
        if let r = path.range(of: ".app/") { target = String(path[..<r.lowerBound]) + ".app" }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: target) as CFURL, [], &code) == errSecSuccess, let code else { return SigningInfo() }
        let check = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: UInt32(kSecCSBasicValidateOnly)), nil)
        if check == errSecCSUnsigned { return SigningInfo(kind: "Unsigned", detail: "", valid: false) }
        var cf: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &cf) == errSecSuccess,
              let info = cf as? [String: Any] else { return SigningInfo(kind: "Unknown") }
        guard check == errSecSuccess else { return SigningInfo(kind: "Invalid signature", detail: "The code no longer matches its signature.", valid: false) }
        let flags = (info[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        let leaf = (info[kSecCodeInfoCertificates as String] as? [SecCertificate])?.first.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? ""
        var s = SigningInfo(valid: true)
        if flags & 0x2 != 0 { s.kind = "Ad hoc"; s.detail = "Signed without a developer certificate."; return s }
        let name = [leaf.isEmpty ? nil : leaf, team.map { "Team \($0)" }].compactMap { $0 }.joined(separator: " · ")
        if satisfies(code, "anchor apple") { s.kind = "Apple"; s.detail = "macOS Software Signing" }
        else if satisfies(code, "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9]") { s.kind = "Mac App Store"; s.detail = name }
        else if satisfies(code, "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]") {
            s.kind = "Developer ID"; s.detail = name
        } else if satisfies(code, "anchor apple generic") { s.kind = "Apple-issued certificate"; s.detail = name }
        else { s.kind = "Unverified certificate"; s.detail = "Signed with a certificate Apple did not issue" + (name.isEmpty ? "." : ": \(name)"); s.valid = false }
        return s
    }
}

// MARK: - End Task

/// Asks first, then signals only if `pid` is still the process that was listed (a pid can be reused by a different
/// program after the original exits).
@MainActor func endTask(_ p: Proc) {
    guard p.id > 1 else { return }
    let confirm = NSAlert()
    confirm.messageText = "End “\(p.name)” (PID \(p.id))?"
    confirm.informativeText = (ProcInspector.path(p.id).map { "\($0)\n\n" } ?? "") + "It will be asked to quit. Unsaved work in it may be lost."
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
    @FocusState private var listFocused: Bool

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

    private func subtitle(_ n: Int) -> String {
        if settings.appsOnly { return n == 1 ? "1 app" : "\(n) apps" }
        let hidden = max(m.pidTotal - m.pidReadable, 0)
        let base = n == 1 ? "1 process" : "\(n) processes"
        return search.isEmpty && hidden > 0 ? base + " · \(hidden) more are protected by macOS" : base
    }

    private func move(_ delta: Int, in rows: [Proc], _ proxy: ScrollViewProxy) {
        guard !rows.isEmpty else { return }
        let i = selection.flatMap { id in rows.firstIndex { $0.id == id } }
        let next = rows[min(max((i ?? (delta > 0 ? -1 : rows.count)) + delta, 0), rows.count - 1)].id
        selection = next
        proxy.scrollTo(next)
    }
    private var selected: Proc? { selection.flatMap { id in m.procs.first { $0.id == id } } }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Processes", subtitle: subtitle(rows.count)) { EmptyView() }
            HStack(spacing: 10) {
                PillPicker(selection: $settings.appsOnly, options: [(true, "Apps"), (false, "All Processes")])
                Spacer(minLength: 8)
                searchField
                columnMenu
                Button { showDetails.toggle() } label: { Label("Details", systemImage: "sidebar.right") }
                    .help("Show details for the selected process (⌘I)").disabled(selected == nil && !showDetails)
                    .keyboardShortcut("i", modifiers: .command)
                Button { if let p = selected { endTask(p) } } label: { Label("End Task", systemImage: "xmark.circle") }
                    .help("End the selected task (⌘⌫)").disabled(selected == nil)
                    .keyboardShortcut(.delete, modifiers: .command)
            }
            .labelStyle(.iconOnly).controlSize(.large)
            GeometryReader { g in
                // Scrolls sideways when the chosen columns don't fit the window.
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                        Divider()
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, p in
                                        ProcRow(p: p, striped: i % 2 == 1, on: selection == p.id, columns: columns, memTotal: m.memTotal, settings: settings,
                                                select: { selection = p.id }, showDetails: { selection = p.id; showDetails = true },
                                                end: { selection = p.id; endTask(p) })
                                            .equatable().id(p.id)
                                    }
                                }
                            }
                            // Keyboard: ↑ ↓ move the selection, Return shows details, Esc closes them.
                            .focusable().focused($listFocused).focusEffectDisabled()
                            .onKeyPress(.upArrow) { move(-1, in: rows, proxy); return .handled }
                            .onKeyPress(.downArrow) { move(1, in: rows, proxy); return .handled }
                            .onKeyPress(.return) { if selection != nil { showDetails = true; return .handled }; return .ignored }
                            .onKeyPress(.escape) { if showDetails { showDetails = false; return .handled }; return .ignored }
                            .accessibilityLabel("Process list").accessibilityHint("Use the up and down arrow keys to choose a process, Return for details.")
                        }
                    }
                    .frame(width: max(g.size.width, ts(160) + columns.reduce(0) { $0 + $1.width }), height: g.size.height)
                }
                .overlay { if rows.isEmpty { emptyState } }
            }
            .card()
            .overlay { RoundedRectangle(cornerRadius: settings.corners.radius, style: .continuous).stroke(settings.accent, lineWidth: 2).opacity(listFocused ? 1 : 0).allowsHitTesting(false) }.clipShape(RoundedRectangle(cornerRadius: settings.corners.radius, style: .continuous))
        }
        .padding(24).frame(maxHeight: .infinity, alignment: .top)
        .onAppear { m.processWatchers += 1; m.allProcessesWanted = !settings.appsOnly; m.refreshProcesses() }
        .onDisappear { m.processWatchers -= 1; m.allProcessesWanted = false }
        .onChange(of: settings.appsOnly) { _, apps in m.allProcessesWanted = !apps; m.refreshProcesses() }
        .onChange(of: selected == nil) { _, gone in if gone { selection = nil } }      // the process ended: nothing is selected any more
        .inspector(isPresented: Binding(get: { showDetails && selected != nil }, set: { showDetails = $0 })) {
            if let p = selected { ProcessDetailsView(proc: p, close: { showDetails = false }).inspectorColumnWidth(min: 280, ideal: 320, max: 440) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: ts(28))).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(search.isEmpty ? "Nothing to show yet" : "No \(settings.appsOnly ? "apps" : "processes") match “\(search)”").font(.system(size: ts(15), weight: .semibold))
            if settings.appsOnly && !search.isEmpty { Text("Switch to All Processes to search system processes too.").font(.system(size: ts(12))).foregroundStyle(.secondary) }
        }
        .padding(.top, ts(60)).frame(maxHeight: .infinity, alignment: .top).accessibilityElement(children: .combine)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $search).textFieldStyle(.plain).frame(minWidth: 90, maxWidth: 150)
                .accessibilityLabel("Search processes").onKeyPress(.escape) { if search.isEmpty { return .ignored }; search = ""; return .handled }
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("Clear search")
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
            headerCell(.name).frame(minWidth: ts(160), maxWidth: .infinity, alignment: .leading)
            ForEach(columns) { c in headerCell(c).frame(width: c.width) }
        }
        .frame(height: ts(32))
        .contextMenu { ForEach(ProcColumn.optional) { c in Toggle(c.title, isOn: columnBinding(c)) } }
    }

    private func headerCell(_ c: ProcColumn) -> some View {
        Button {
            if key == c { ascending.toggle() } else { key = c; ascending = c.leading || c == .pid }
        } label: {
            HStack(spacing: 3) {
                if !c.leading, key == c { chevron }
                Text(c.title).font(.system(size: ts(12), weight: .semibold))
                if c.leading, key == c { chevron }
            }
            .foregroundStyle(key == c ? Color.primary : Color.secondary)
            .padding(.horizontal, 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: c.leading ? .leading : .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(c.title)")
        .accessibilityValue(key == c ? (ascending ? "sorted ascending" : "sorted descending") : "")
    }

    private var chevron: some View {
        Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: ts(8), weight: .bold))
    }
}

/// One line of the process list. It is Equatable on what it displays, so SwiftUI skips rebuilding rows whose numbers didn't
/// change since the last sample (most processes sit at 0.0 % almost all the time), which is most of the list's per-second cost.
struct ProcRow: View, Equatable {
    let p: Proc
    let striped: Bool
    let on: Bool
    let columns: [ProcColumn]
    let memTotal: UInt64
    let accent: Color, cpuColor: Color, memoryColor: Color, diskColor: Color
    let select: () -> Void
    let showDetails: () -> Void
    let end: () -> Void
    private let stamp: String

    init(p: Proc, striped: Bool, on: Bool, columns: [ProcColumn], memTotal: UInt64, settings: AppSettings,
         select: @escaping () -> Void, showDetails: @escaping () -> Void, end: @escaping () -> Void) {
        self.p = p; self.striped = striped; self.on = on; self.columns = columns; self.memTotal = memTotal
        accent = settings.accent; cpuColor = settings.cpuColor; memoryColor = settings.memoryColor; diskColor = settings.diskColor
        self.select = select; self.showDetails = showDetails; self.end = end
        // Everything the row shows, as rounded as it is displayed.
        stamp = "\(p.id)|\(p.name)|\(Int(p.cpu * 10))|\(p.mem / 1024)|\(Int(p.disk / 1000))|\(p.threads)|\(p.state)|\(striped)|\(on)|\(columns.map(\.rawValue))|\(settings.themeKey)|\(settings.cpuColor.hex)\(settings.memoryColor.hex)\(settings.diskColor.hex)"
    }

    static func == (a: ProcRow, b: ProcRow) -> Bool { a.stamp == b.stamp }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                if let icon = p.icon { Image(nsImage: icon).resizable().frame(width: ts(20), height: ts(20)) }
                else { Image(systemName: "gearshape.fill").frame(width: ts(20), height: ts(20)).foregroundStyle(.secondary) }
                Text(p.name).lineLimit(1)
            }
            .padding(.leading, 12).frame(minWidth: ts(160), maxWidth: .infinity, alignment: .leading)
            ForEach(columns) { c in cell(c) }
        }
        .font(.system(size: ts(13))).frame(height: ts(28))
        .background(on ? accent.opacity(0.20) : (striped ? Color.primary.opacity(0.04) : .clear))
        .overlay(alignment: .leading) { if on { Rectangle().fill(accent).frame(width: 3) } }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { showDetails() }
        .onTapGesture { select() }
        .contextMenu {
            Button("Show Details") { showDetails() }
            Button("Reveal in Finder") { if let path = ProcInspector.path(p.id) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } }
            Divider()
            Button("End Task", role: .destructive) { end() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowDescription)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select() }
        .accessibilityAction(named: "Show details") { showDetails() }
        .accessibilityAction(named: "End task") { end() }
    }

    /// What VoiceOver reads for a row: the name, then each visible column with its label and unit.
    private var rowDescription: String {
        var parts = [p.name]
        for c in columns {
            switch c {
            case .cpu: parts.append(String(format: "CPU %.1f percent", p.cpu))
            case .mem: parts.append("Memory " + bytes(p.mem))
            case .disk: parts.append("Disk " + Rates.format(p.disk))
            case .pid: parts.append("PID \(p.id)")
            case .user: parts.append("User " + p.user)
            case .threads: parts.append("\(p.threads) threads")
            case .state: parts.append(p.state)
            case .started: if p.started != 0 { parts.append("Started " + startFormat(p.started)) }
            case .name: break
            }
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private func cell(_ c: ProcColumn) -> some View {
        switch c {
        case .cpu: heat(String(format: "%.1f%%", p.cpu), c, share: p.cpu / 100, color: cpuColor, dim: p.cpu < 1)
        case .mem: heat(bytes(p.mem), c, share: Double(p.mem) / Double(memTotal) * 4, color: memoryColor)
        case .disk: heat(p.disk < 1 ? "0 B/s" : Rates.format(p.disk), c, share: p.disk / 50_000_000, color: diskColor, dim: p.disk < 1)
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
}

private func startFormat(_ micros: UInt64) -> String {
    let d = Date(timeIntervalSince1970: Double(micros) / 1e6)
    return Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened) : d.formatted(date: .abbreviated, time: .shortened)
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
                    else { Image(systemName: "gearshape.fill").font(.system(size: ts(28))).frame(width: 44, height: 44).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(proc.name).font(.system(size: ts(18), weight: .bold, design: .rounded)).lineLimit(2)
                        Text("PID " + String(proc.id)).font(.system(size: ts(11))).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Hide details").accessibilityLabel("Hide details")
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
                        Text(d.path.isEmpty ? "macOS doesn’t share this path." : d.path).font(.system(size: ts(12))).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        if !d.path.isEmpty {
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: d.path)]) }
                                .padding(.bottom, 8)
                        }
                    }
                    group("Code signature") {
                        HStack(spacing: 8) {
                            Image(systemName: d.signing.vouched ? "checkmark.seal.fill" : (d.signing.valid ? "seal" : "exclamationmark.triangle.fill"))
                                .foregroundStyle(d.signing.vouched ? Color.green : (d.signing.valid ? Color.secondary : Color.orange)).accessibilityHidden(true)
                            Text(d.signing.kind).fontWeight(.medium)
                        }.padding(.vertical, 6)
                        if !d.signing.detail.isEmpty {
                            Text(d.signing.detail).font(.system(size: ts(12))).foregroundStyle(.secondary).textSelection(.enabled).padding(.bottom, 8)
                        }
                    }
                    group("Open ports") {
                        if d.ports.isEmpty { Text("No open TCP or UDP sockets.").foregroundStyle(.secondary).padding(.vertical, 6) }
                        ForEach(d.ports.prefix(40)) { p in
                            HStack {
                                Text(p.proto).fontWeight(.medium).frame(width: ts(36), alignment: .leading)
                                Text(String(p.local)).monospacedDigit()
                                if let r = p.remote { Text("→ \(r)").monospacedDigit().foregroundStyle(.secondary) }
                                Spacer(minLength: 8)
                                Text(p.state).foregroundStyle(.secondary)
                            }.font(.system(size: ts(12.5))).padding(.vertical, 3)
                        }
                        if d.ports.count > 40 { Text("and \(d.ports.count - 40) more").font(.system(size: ts(11))).foregroundStyle(.secondary) }
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
            Text(title).font(.system(size: ts(12), weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) { content() }.padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.system(size: ts(13))).padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}

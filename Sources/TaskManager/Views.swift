import SwiftUI
import Charts

private func bytes(_ b: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory) }

// MARK: Processes

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

enum SortKey { case name, cpu, mem, pid }

/// A plain scrolling list instead of SwiftUI's Table: Table is an NSTableView underneath, and re-sorting it every second
/// (by CPU, say) makes macOS log "reentrant operation in its NSTableView delegate", a warning Apple says will become an assert.
struct ProcessesView: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var settings: AppSettings
    @State private var search = ""
    @State private var selection: Int32?
    @State private var key = SortKey.cpu
    @State private var ascending = false

    private let cpuW: CGFloat = 84, memW: CGFloat = 104, pidW: CGFloat = 76

    private var rows: [Proc] {
        m.procs
            .filter { (!settings.appsOnly || $0.isApp) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
            .sorted {
                let r: Bool
                switch key {
                case .name: r = $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                case .cpu: r = $0.cpu < $1.cpu
                case .mem: r = $0.mem < $1.mem
                case .pid: r = $0.id < $1.id
                }
                return ascending ? r : !r
            }
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, p in row(p, striped: i % 2 == 1) }
                }
            }
        }
        .navigationTitle("Processes")
        .navigationSubtitle("\(rows.count) \(settings.appsOnly ? "apps" : "processes")")
        .searchable(text: $search, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $settings.appsOnly) {
                    Text("Apps").tag(true); Text("All Processes").tag(false)
                }.pickerStyle(.segmented)
            }
            ToolbarItem {
                Button { if let pid = selection, let p = m.procs.first(where: { $0.id == pid }) { endTask(p) } } label: {
                    Label("End Task", systemImage: "xmark.circle")
                }
                .help("End the selected task").disabled(selection == nil)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            headerCell("Name", .name, .leading).frame(maxWidth: .infinity, alignment: .leading)
            headerCell("CPU", .cpu, .trailing).frame(width: cpuW)
            headerCell("Memory", .mem, .trailing).frame(width: memW)
            headerCell("PID", .pid, .trailing).frame(width: pidW)
        }
        .frame(height: 30)
    }

    private func headerCell(_ title: String, _ k: SortKey, _ align: Alignment) -> some View {
        Button {
            if key == k { ascending.toggle() } else { key = k; ascending = (k == .name || k == .pid) }
        } label: {
            HStack(spacing: 3) {
                if align == .trailing, key == k { chevron }
                Text(title).font(.system(size: 12, weight: .medium))
                if align == .leading, key == k { chevron }
            }
            .foregroundStyle(key == k ? .primary : .secondary)
            .padding(.horizontal, 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chevron: some View {
        Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
    }

    private func row(_ p: Proc, striped: Bool) -> some View {
        let selected = selection == p.id
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                if let icon = p.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                else { Image(systemName: "gearshape.fill").frame(width: 20, height: 20).foregroundStyle(selected ? .white : .secondary) }
                Text(p.name).lineLimit(1)
            }
            .padding(.leading, 12).frame(maxWidth: .infinity, alignment: .leading)
            cell(String(format: "%.1f%%", p.cpu), cpuW, dim: p.cpu < 1)
            cell(bytes(p.mem), memW)
            cell(String(p.id), pidW, dim: true)
        }
        .font(.system(size: 13)).frame(height: 28)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? Color.accentColor : (striped ? Color.primary.opacity(0.04) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { selection = p.id }
        .contextMenu { Button("End Task", role: .destructive) { endTask(p) } }
    }

    private func cell(_ text: String, _ width: CGFloat, dim: Bool = false) -> some View {
        Text(text).monospacedDigit().opacity(dim ? 0.6 : 1)
            .padding(.horizontal, 12).frame(width: width, alignment: .trailing)
    }
}

// MARK: Performance

struct Stat: Identifiable {
    let label, value: String
    var id: String { label }
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
}

struct Sparkline: View {
    let data: [Double]
    let color: Color
    var body: some View {
        Chart(Array(data.enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("t", i), y: .value("v", v)).interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.45), color.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("t", i), y: .value("v", v)).interpolationMethod(.monotone)
                .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
        .chartYScale(domain: 0...100).chartXScale(domain: 0...(Monitor.samples - 1))
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct ResourceDetail: View {
    @EnvironmentObject var monitor: Monitor
    @EnvironmentObject var settings: AppSettings
    let title, subtitle: String
    let color: Color
    let data: [Double]
    let stats: [Stat]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: "%.0f%%", data.last ?? 0))
                        .font(.system(size: 54, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(color)
                    Text("Utilization").font(.system(size: 13)).foregroundStyle(.secondary)
                }

                Chart(Array(data.enumerated()), id: \.offset) { i, v in
                    AreaMark(x: .value("t", i), y: .value("v", v)).interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.45), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("t", i), y: .value("v", v)).interpolationMethod(.monotone)
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                }
                .chartYScale(domain: 0...100).chartXScale(domain: 0...(Monitor.samples - 1))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, 50, 100]) { v in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(.tertiary)
                        AxisValueLabel { if let n = v.as(Int.self) { Text("\(n)%").font(.system(size: 10)) } }
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 260)
                .padding(18)
                .background(settings.cardColor, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(nsColor: .separatorColor).opacity(0.6)))
                .overlay(alignment: .bottomLeading) {
                    Text("Last \(Int(Double(Monitor.samples) * monitor.interval)) seconds").font(.system(size: 10)).foregroundStyle(.tertiary)
                        .padding(.leading, 18).padding(.bottom, 6)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                    ForEach(stats) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.label).font(.system(size: 12)).foregroundStyle(.secondary)
                            Text(s.value).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(settings.cardColor, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.6)))
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
    }
}

struct CPUDetail: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var s: AppSettings
    var body: some View {
        ResourceDetail(title: "CPU", subtitle: m.cpuName, color: s.cpuColor, data: m.cpuHistory, stats: [
            Stat("Cores", "\(m.cores)"),
            Stat("Performance Cores", SystemInfo.performanceCores.map(String.init) ?? "–"),
            Stat("Efficiency Cores", SystemInfo.efficiencyCores.map(String.init) ?? "–"),
            Stat("Processes", "\(m.procs.count)"),
            Stat("Thermal State", SystemInfo.thermal),
            Stat("Up Time", SystemInfo.uptime()),
        ])
    }
}

struct MemoryDetail: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var s: AppSettings
    var body: some View {
        ResourceDetail(title: "Memory", subtitle: bytes(m.memTotal) + " installed", color: s.memoryColor, data: m.memHistory, stats: [
            Stat("In Use", bytes(m.memUsed)),
            Stat("Available", bytes(m.memTotal - min(m.memUsed, m.memTotal))),
            Stat("Wired", bytes(m.memWired)),
            Stat("Compressed", bytes(m.memCompressed)),
            Stat("Installed", bytes(m.memTotal)),
        ])
    }
}

struct GPUDetail: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var s: AppSettings
    var body: some View {
        ResourceDetail(title: "GPU", subtitle: m.gpuName, color: s.gpuColor, data: m.gpuHistory, stats: [
            Stat("Cores", m.gpuCores.map(String.init) ?? "–"),
            Stat("Memory In Use", bytes(m.gpuMemUsed)),
            Stat("Thermal State", SystemInfo.thermal),
        ])
    }
}

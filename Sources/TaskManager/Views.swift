import SwiftUI
import Charts

private func bytes(_ b: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory) }

// MARK: Processes

enum SortKey { case name, pid, cpu, mem }

struct ProcessesView: View {
    @EnvironmentObject var m: Monitor
    @State private var search = ""
    @State private var selection: Int32?
    @State private var key = SortKey.name
    @State private var ascending = true
    @State private var collapsed: Set<String> = []

    private let pidW: CGFloat = 80, cpuW: CGFloat = 100, memW: CGFloat = 120

    private func list(apps: Bool) -> [Proc] {
        m.procs
            .filter { $0.isApp == apps && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
            .sorted {
                let r: Bool
                switch key {
                case .name: r = $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                case .pid: r = $0.id < $1.id
                case .cpu: r = $0.cpu < $1.cpu
                case .mem: r = $0.mem < $1.mem
                }
                return ascending ? r : !r
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    group("Apps", list(apps: true))
                    group("Background processes", list(apps: false))
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Processes").font(.system(size: 20, weight: .semibold))
            Spacer()
            TextField("Type a name to search", text: $search)
                .textFieldStyle(.roundedBorder).frame(width: 240)
            Button { if let pid = selection { kill(pid, SIGTERM) } } label: {
                Label("End task", systemImage: "xmark.circle")
            }
            .disabled(selection == nil)
        }
        .padding(.horizontal, 20).frame(height: 56)
    }

    private var header: some View {
        HStack(spacing: 0) {
            headerCell("Name", nil, .name, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            headerCell("PID", nil, .pid, alignment: .trailing).frame(width: pidW)
            headerCell("CPU", String(format: "%.0f%%", m.cpuHistory.last ?? 0), .cpu, alignment: .trailing)
                .frame(width: cpuW).background(Palette.heat((m.cpuHistory.last ?? 0) / 60))
            headerCell("Memory", String(format: "%.0f%%", m.memHistory.last ?? 0), .mem, alignment: .trailing)
                .frame(width: memW).background(Palette.heat((m.memHistory.last ?? 0) / 100))
        }
        .frame(height: 54)
    }

    private func headerCell(_ title: String, _ total: String?, _ k: SortKey, alignment: HorizontalAlignment) -> some View {
        Button {
            if key == k { ascending.toggle() } else { key = k; ascending = (k == .name || k == .pid) }
        } label: {
            VStack(alignment: alignment, spacing: 2) {
                if let total { Text(total).font(.system(size: 18, weight: .regular)) }
                HStack(spacing: 3) {
                    Text(title).font(.system(size: 12)).foregroundStyle(total == nil ? .primary : .secondary)
                    if key == k { Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)) }
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment == .leading ? .leading : .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func group(_ title: String, _ procs: [Proc]) -> some View {
        let open = !collapsed.contains(title)
        Button {
            if open { collapsed.insert(title) } else { collapsed.remove(title) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                Text("\(title) (\(procs.count))").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14).frame(height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if open { ForEach(procs) { row($0) } }
    }

    private func row(_ p: Proc) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                if let icon = p.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                else { Image(systemName: "gearshape").frame(width: 18, height: 18).foregroundStyle(.secondary) }
                Text(p.name).lineLimit(1)
            }
            .padding(.leading, 30).frame(maxWidth: .infinity, alignment: .leading)
            cell(String(p.id), width: pidW, tint: .clear).foregroundStyle(.secondary)
            cell(String(format: "%.1f%%", p.cpu), width: cpuW, tint: Palette.heat(p.cpu / 60))
            cell(bytes(p.mem), width: memW, tint: Palette.heat(Double(p.mem) / Double(m.memTotal) * 12))
        }
        .font(.system(size: 12.5)).frame(height: 32)
        .background(selection == p.id ? Color.accentColor.opacity(0.22) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { selection = p.id }
        .contextMenu { Button("End task") { kill(p.id, SIGTERM) } }
    }

    private func cell(_ text: String, width: CGFloat, tint: Color) -> some View {
        Text(text).monospacedDigit().padding(.horizontal, 12)
            .frame(width: width, alignment: .trailing).frame(maxHeight: .infinity)
            .background(tint)
    }
}

// MARK: Performance

struct PerformanceView: View {
    @EnvironmentObject var m: Monitor
    @State private var resource = Resource.cpu

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("Performance").font(.system(size: 20, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).frame(height: 56)
                tile(.cpu, "CPU", Palette.cpu, m.cpuHistory, "")
                tile(.memory, "Memory", Palette.memory, m.memHistory, "\(bytes(m.memUsed))/\(bytes(m.memTotal))")
                if m.gpuAvailable { tile(.gpu, "GPU", Palette.gpu, m.gpuHistory, "") }
                Spacer()
            }
            .padding(.horizontal, 8).frame(width: 260)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tile(_ r: Resource, _ title: String, _ color: Color, _ data: [Double], _ extra: String) -> some View {
        Button { resource = r } label: {
            HStack(spacing: 12) {
                Sparkline(data: data, color: color).frame(width: 64, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(extra.isEmpty ? String(format: "%.0f%%", data.last ?? 0)
                                       : extra + String(format: " (%.0f%%)", data.last ?? 0))
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(resource == r ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var detail: some View {
        switch resource {
        case .cpu:
            ResourceDetail(title: "CPU", subtitle: m.cpuName, color: Palette.cpu, data: m.cpuHistory, stats: [
                Stat("Utilization", String(format: "%.0f%%", m.cpuHistory.last ?? 0), big: true),
                Stat("Processes", "\(m.procs.count)", big: true),
                Stat("Cores", "\(m.cores)"),
                Stat("Up time", uptime()),
            ])
        case .memory:
            ResourceDetail(title: "Memory", subtitle: bytes(m.memTotal), color: Palette.memory, data: m.memHistory, stats: [
                Stat("In use", bytes(m.memUsed), big: true),
                Stat("Available", bytes(m.memTotal - min(m.memUsed, m.memTotal)), big: true),
                Stat("Installed", bytes(m.memTotal)),
            ])
        case .gpu:
            ResourceDetail(title: "GPU", subtitle: m.gpuName, color: Palette.gpu, data: m.gpuHistory, stats: [
                Stat("Utilization", String(format: "%.0f%%", m.gpuHistory.last ?? 0), big: true),
                Stat("Memory in use", bytes(m.gpuMemUsed), big: true),
                Stat("Cores", m.gpuCores.map(String.init) ?? "–"),
            ])
        }
    }

    private func uptime() -> String {
        let s = Int(ProcessInfo.processInfo.systemUptime)
        return String(format: "%d:%02d:%02d:%02d", s / 86400, s % 86400 / 3600, s % 3600 / 60, s % 60)
    }
}

struct Stat: Identifiable {
    let label, value: String
    var big = false
    var id: String { label }
    init(_ label: String, _ value: String, big: Bool = false) { self.label = label; self.value = value; self.big = big }
}

private func grid(_ color: Color) -> some AxisMark {
    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(color.opacity(0.28))
}

/// Windows-style graph: boxed plot, tinted fill, square grid.
struct UtilGraph: View {
    let data: [Double]
    let color: Color
    var body: some View {
        Chart(Array(data.enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("t", i), y: .value("v", v)).foregroundStyle(color.opacity(0.25))
            LineMark(x: .value("t", i), y: .value("v", v)).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartYScale(domain: 0...100).chartXScale(domain: 0...(Monitor.samples - 1))
        .chartXAxis { AxisMarks(values: .stride(by: 6)) { _ in grid(color) } }
        .chartYAxis { AxisMarks(values: Array(stride(from: 0, through: 100, by: 10))) { _ in grid(color) } }
        .chartPlotStyle { $0.background(color.opacity(0.07)).overlay(Rectangle().stroke(color, lineWidth: 1)) }
    }
}

struct Sparkline: View {
    let data: [Double]
    let color: Color
    var body: some View {
        Chart(Array(data.enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("t", i), y: .value("v", v)).foregroundStyle(color.opacity(0.25))
            LineMark(x: .value("t", i), y: .value("v", v)).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartYScale(domain: 0...100).chartXScale(domain: 0...(Monitor.samples - 1))
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .chartPlotStyle { $0.background(color.opacity(0.07)).overlay(Rectangle().stroke(color, lineWidth: 1)) }
    }
}

struct ResourceDetail: View {
    let title, subtitle: String
    let color: Color
    let data: [Double]
    let stats: [Stat]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 22, weight: .semibold))
                Spacer()
                Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            .frame(height: 40)
            HStack {
                Text("% Utilization"); Spacer(); Text("100%")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            UtilGraph(data: data, color: color).frame(minHeight: 240)
            HStack {
                Text("\(Monitor.samples) seconds"); Spacer(); Text("0")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 48) {
                ForEach(stats.filter(\.big)) { stat in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(stat.label).font(.system(size: 12)).foregroundStyle(.secondary)
                        Text(stat.value).font(.system(size: 30, weight: .light)).monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            HStack(alignment: .top, spacing: 48) {
                ForEach(stats.filter { !$0.big }) { stat in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(stat.label).font(.system(size: 12)).foregroundStyle(.secondary)
                        Text(stat.value).font(.system(size: 16)).monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24).padding(.bottom, 20)
    }
}

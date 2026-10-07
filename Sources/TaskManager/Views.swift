import SwiftUI

func bytes(_ b: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory) }

// MARK: - Charts

struct Stat: Identifiable {
    let label, value: String
    var id: String { label }
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
}

struct Series: Identifiable {
    let name: String
    let data: [Double]
    let color: Color
    var dashed = false
    var id: String { name }
}

/// What the y axis measures: a 0–100 percentage, or a throughput that scales to the busiest recent sample.
enum Scale {
    case percent
    case rate(floor: Double)

    func top(_ series: [Series]) -> Double {
        switch self {
        case .percent: 100
        case .rate(let floor): Rates.niceMax(series.flatMap(\.data).max() ?? 0, floor: floor)
        }
    }
}

/// A series as a path: the line itself, or (area) the line closed down to the baseline. Plain SwiftUI shapes, because a Canvas
/// (and Swift Charts before it) pulled in the GPU renderer, which alone cost about 45 MB of graphics memory.
struct SeriesShape: Shape {
    let data: [Double]
    let top: Double
    var inset: CGFloat = 0
    var area = false
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard data.count > 1 else { return p }
        let h = rect.height - inset * 2, step = rect.width / CGFloat(data.count - 1)
        func y(_ v: Double) -> CGFloat { rect.minY + inset + h * (1 - CGFloat(min(max(v / max(top, 1), 0), 1))) }
        for (i, v) in data.enumerated() {
            let pt = CGPoint(x: rect.minX + CGFloat(i) * step, y: y(v))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        if area {
            p.addLine(to: CGPoint(x: rect.maxX, y: y(0))); p.addLine(to: CGPoint(x: rect.minX, y: y(0))); p.closeSubpath()
        }
        return p
    }
}

/// Small graph for the sidebar and popover.
struct Sparkline: View {
    let series: [Series]
    let scale: Scale
    var body: some View {
        let top = max(scale.top(series), 1)
        ZStack {
            ForEach(Array(series.enumerated()), id: \.offset) { n, s in
                if n == 0 {
                    SeriesShape(data: s.data, top: top, area: true)
                        .fill(LinearGradient(colors: [s.color.opacity(0.40), s.color.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                }
                SeriesShape(data: s.data, top: top)
                    .stroke(s.color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round, dash: s.dashed ? [2, 2] : []))
            }
        }
        .background(series.first?.color.opacity(0.10) ?? .clear, in: RoundedRectangle(cornerRadius: 7))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .accessibilityHidden(true)      // the page announces the numbers; a thumbnail graph adds nothing for VoiceOver
    }
}

struct ResourceDetail: View {
    @EnvironmentObject var monitor: Monitor
    @EnvironmentObject var settings: AppSettings
    let title, subtitle: String
    let series: [Series]
    let scale: Scale
    let stats: [Stat]
    var trailing: AnyView = AnyView(EmptyView())

    var body: some View {
        let top = scale.top(series)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: title, subtitle: subtitle) { trailing }

                HStack(alignment: .top, spacing: 16) {
                    headline.padding(18).frame(width: 210, height: 330, alignment: .top).card()
                    chart(top: top).padding(18).frame(height: 330).card()
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                    ForEach(stats) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.label).font(.system(size: ts(12))).foregroundStyle(.secondary)
                            Text(s.value).font(.system(size: ts(21), weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(24)
        }
    }

    /// Ring for percentages; for throughputs, each series' current value in its own colour.
    @ViewBuilder private var headline: some View {
        switch scale {
        case .percent:
            VStack(spacing: 14) {
                RingGauge(value: series.first?.data.last ?? 0, color: series.first.map { Color.metric($0.color) } ?? .accentColor, size: 150, line: 14)
                Text("Utilization").font(.system(size: ts(13))).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        case .rate:
            VStack(alignment: .leading, spacing: 18) {
                ForEach(series) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            legendSwatch(s)
                            Text(s.name).font(.system(size: ts(13))).foregroundStyle(.secondary)
                        }
                        Text(Rates.format(s.data.last ?? 0))
                            .font(.system(size: ts(26), weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Color.metric(s.color))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("peak \(Rates.format(s.data.max() ?? 0))").font(.system(size: ts(11.5))).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func legendSwatch(_ s: Series) -> some View {
        RoundedRectangle(cornerRadius: 1).fill(Color.metric(s.color)).frame(width: s.dashed ? 10 : 14, height: 3)
            .overlay { if s.dashed { Rectangle().fill(settings.cardColor).frame(width: 2, height: 4) } }
            .accessibilityHidden(true)
    }

    private var windowSeconds: Int { Int(Double(Monitor.samples) * monitor.interval) }

    /// The graph in words, for VoiceOver.
    private var summary: String {
        series.map { s in
            let now = s.data.last ?? 0, peak = s.data.max() ?? 0
            if case .percent = scale { return "\(s.name) now \(Int(now.rounded())) percent, highest \(Int(peak.rounded())) percent" }
            return "\(s.name) now \(Rates.format(now)), highest \(Rates.format(peak))"
        }.joined(separator: ". ")
    }

    private func chart(top: Double) -> some View {
        VStack(spacing: 6) {
            plot(top: top)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title) over the last \(windowSeconds) seconds")
                .accessibilityValue(summary)
            HStack {
                Text("\(windowSeconds) seconds ago"); Spacer(); Text("Now")
            }
            .font(.system(size: ts(11))).foregroundStyle(Color.secondary).padding(.trailing, ts(66)).accessibilityHidden(true)
        }
    }

    private func plot(top: Double) -> some View {
        ResourceChart(series: series, top: top, label: { v in
            if case .percent = scale { return "\(Int(v.rounded()))%" }
            return v == 0 ? "0" : Rates.format(v)
        })
    }
}

/// The big graph: dashed grid at 0, 50 and 100 % of the axis, the series, and axis labels on the right.
struct ResourceChart: View {
    let series: [Series]
    let top: Double
    let label: (Double) -> String
    private let inset: CGFloat = 8

    private struct Grid: Shape {
        let inset: CGFloat
        func path(in rect: CGRect) -> Path {
            var p = Path()
            for f in [0.0, 0.5, 1.0] {
                let y = rect.minY + inset + (rect.height - inset * 2) * (1 - f)
                p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            return p
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Grid(inset: inset).stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                ForEach(Array(series.enumerated()), id: \.offset) { n, s in
                    let c = Color.metric(s.color)
                    if n == 0 {
                        SeriesShape(data: s.data, top: top, inset: inset, area: true)
                            .fill(LinearGradient(colors: [c.opacity(0.40), c.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    }
                    SeriesShape(data: s.data, top: top, inset: inset)
                        .stroke(c, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round, dash: s.dashed ? [5, 4] : []))
                }
            }
            GeometryReader { g in
                ForEach([0.0, 0.5, 1.0], id: \.self) { f in
                    Text(label(top * f)).font(.system(size: ts(10))).foregroundStyle(Color.secondary)
                        .position(x: g.size.width / 2, y: inset + (g.size.height - inset * 2) * (1 - f))
                }
            }
            .frame(width: ts(58))
        }
    }
}

// MARK: - Pages

struct CPUDetail: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var s: AppSettings
    var body: some View {
        ResourceDetail(title: "CPU", subtitle: m.cpuName, series: [Series(name: "CPU", data: m.cpuHistory, color: s.cpuColor)], scale: .percent, stats: [
            Stat("Cores", "\(m.cores)"),
            Stat("Performance Cores", SystemInfo.performanceCores.map(String.init) ?? "–"),
            Stat("Efficiency Cores", SystemInfo.efficiencyCores.map(String.init) ?? "–"),
            Stat("Processes", "\(m.pidTotal)"),
            Stat("Thermal State", SystemInfo.thermal),
            Stat("Up Time", SystemInfo.uptime()),
        ])
    }
}

struct MemoryDetail: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var s: AppSettings
    var body: some View {
        ResourceDetail(title: "Memory", subtitle: bytes(m.memTotal) + " installed", series: [Series(name: "Memory", data: m.memHistory, color: s.memoryColor)], scale: .percent, stats: [
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
        ResourceDetail(title: "GPU", subtitle: m.gpuName, series: [Series(name: "GPU", data: m.gpuHistory, color: s.gpuColor)], scale: .percent, stats: [
            Stat("Cores", m.gpuCores.map(String.init) ?? "–"),
            Stat("Memory In Use", bytes(m.gpuMemUsed)),
            Stat("Thermal State", SystemInfo.thermal),
        ])
    }
}

struct DiskDetail: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var s: AppSettings
    var body: some View {
        let storage = SystemInfo.storage
        ResourceDetail(title: "Disk", subtitle: "Transfer rate across all drives", series: [
            Series(name: "Read", data: m.diskRead, color: s.diskColor),
            Series(name: "Write", data: m.diskWrite, color: s.diskColor, dashed: true),
        ], scale: .rate(floor: 1_000_000), stats: [
            Stat("Read", Rates.format(m.diskRead.last ?? 0)),
            Stat("Write", Rates.format(m.diskWrite.last ?? 0)),
            Stat("Capacity", storage.map { ByteCountFormatter.string(fromByteCount: $0.total, countStyle: .file) } ?? "–"),
            Stat("Available", storage.map { ByteCountFormatter.string(fromByteCount: $0.available, countStyle: .file) } ?? "–"),
        ])
    }
}

struct NetworkDetail: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var s: AppSettings
    @State private var choice = "all"

    var body: some View {
        let id = choice == "all" || m.interfaces.contains(where: { $0.id == choice }) ? choice : "all"
        let rx = m.netRx[id] ?? [Double](repeating: 0, count: Monitor.samples), tx = m.netTx[id] ?? rx
        let iface = m.interfaces.first { $0.id == id }
        ResourceDetail(title: "Network", subtitle: iface.map { "\($0.name) (\($0.id))" } ?? "All connections", series: [
            Series(name: "Receive", data: rx, color: s.networkColor),
            Series(name: "Send", data: tx, color: s.networkColor, dashed: true),
        ], scale: .rate(floor: 100_000), stats: [
            Stat("Receive", Rates.format(rx.last ?? 0)),
            Stat("Send", Rates.format(tx.last ?? 0)),
            Stat("Peak Receive", Rates.format(rx.max() ?? 0)),
            Stat("Peak Send", Rates.format(tx.max() ?? 0)),
            Stat("Interfaces", "\(m.interfaces.count)"),
        ], trailing: AnyView(
            m.interfaces.count > 1
                ? AnyView(Picker("Interface", selection: Binding(get: { id }, set: { choice = $0 })) {
                    Text("All connections").tag("all")
                    ForEach(m.interfaces) { Text("\($0.name) (\($0.id))").tag($0.id) }
                }.labelsHidden().fixedSize().controlSize(.large))
                : AnyView(EmptyView())
        ))
    }
}

import SwiftUI
import Charts

struct Sparkline: View {
    let data: [Double]
    let color: Color
    var body: some View {
        Chart(Array(data.enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("t", i), y: .value("v", v)).interpolationMethod(.monotone)
                .foregroundStyle(color.opacity(0.22))
            LineMark(x: .value("t", i), y: .value("v", v)).interpolationMethod(.monotone)
                .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.4))
        }
        .chartYScale(domain: 0...100).chartXScale(domain: 0...(Monitor.samples - 1))
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .background(RoundedRectangle(cornerRadius: 5).stroke(color.opacity(0.35), lineWidth: 0.5))
    }
}

struct Stat: Identifiable {
    let label, value: String
    var id: String { label }
}

struct ResourceDetail: View {
    let title, subtitle: String
    let color: Color
    let data: [Double]
    let stats: [Stat]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Utilization · last \(Monitor.samples) seconds")
                    Spacer()
                    Text(String(format: "%.0f%%", data.last ?? 0))
                        .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(color)
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                Chart(Array(data.enumerated()), id: \.offset) { i, v in
                    AreaMark(x: .value("t", i), y: .value("v", v)).interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.40), color.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("t", i), y: .value("v", v)).interpolationMethod(.monotone)
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
                .chartYScale(domain: 0...100).chartXScale(domain: 0...(Monitor.samples - 1))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { v in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel { if let n = v.as(Int.self) { Text("\(n)%").font(.system(size: 10)) } }
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 220)
            }
            .padding(16)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 16) {
                ForEach(stats) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.label).font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(s.value).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28).padding(.top, 34).padding(.bottom, 20)
    }
}

private func bytes(_ b: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory) }

struct CPUDetail: View {
    @EnvironmentObject var m: Monitor
    var body: some View {
        ResourceDetail(title: "CPU", subtitle: m.cpuName, color: Palette.cpu, data: m.cpuHistory, stats: [
            Stat(label: "Utilization", value: String(format: "%.0f%%", m.cpuHistory.last ?? 0)),
            Stat(label: "Cores", value: "\(m.cores)"),
            Stat(label: "Processes", value: "\(m.procs.count)"),
        ])
    }
}

struct MemoryDetail: View {
    @EnvironmentObject var m: Monitor
    var body: some View {
        ResourceDetail(title: "Memory", subtitle: bytes(m.memTotal) + " installed", color: Palette.memory, data: m.memHistory, stats: [
            Stat(label: "In use", value: bytes(m.memUsed)),
            Stat(label: "Available", value: bytes(m.memTotal - min(m.memUsed, m.memTotal))),
            Stat(label: "Total", value: bytes(m.memTotal)),
        ])
    }
}

struct GPUDetail: View {
    @EnvironmentObject var m: Monitor
    var body: some View {
        ResourceDetail(title: "GPU", subtitle: m.gpuName, color: Palette.gpu, data: m.gpuHistory, stats: [
            Stat(label: "Utilization", value: String(format: "%.0f%%", m.gpuHistory.last ?? 0)),
            Stat(label: "Cores", value: m.gpuCores.map(String.init) ?? "–"),
            Stat(label: "Memory in use", value: bytes(m.gpuMemUsed)),
        ])
    }
}

struct ProcessesView: View {
    @EnvironmentObject var monitor: Monitor
    @State private var appsOnly = true
    @State private var search = ""
    @State private var selection: Int32?
    @State private var order = [KeyPathComparator(\Proc.cpu, order: .reverse)]

    private var rows: [Proc] {
        monitor.procs
            .filter { (!appsOnly || $0.isApp) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
            .sorted(using: order)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Processes").font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("\(rows.count)").font(.system(size: 15)).foregroundStyle(.secondary)
                Spacer()
                Button("End Task", role: .destructive) { if let pid = selection { kill(pid, SIGTERM) } }
                    .disabled(selection == nil)
            }
            HStack {
                Picker("", selection: $appsOnly) {
                    Text("Apps").tag(true); Text("All processes").tag(false)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
                Spacer()
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            Table(rows, selection: $selection, sortOrder: $order) {
                TableColumn("Name", value: \.name) { p in
                    HStack(spacing: 8) {
                        if let icon = p.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                        else { Image(systemName: "gearshape").frame(width: 18, height: 18).foregroundStyle(.secondary) }
                        Text(p.name)
                    }
                }
                TableColumn("PID", value: \.id) { Text(String($0.id)).monospacedDigit().foregroundStyle(.secondary) }.width(64)
                TableColumn("CPU", value: \.cpu) { p in
                    Text(String(format: "%.1f%%", p.cpu)).monospacedDigit()
                        .foregroundStyle(p.cpu >= 1 ? Palette.cpu : .secondary)
                }.width(70)
                TableColumn("Memory", value: \.mem) {
                    Text(ByteCountFormatter.string(fromByteCount: Int64($0.mem), countStyle: .memory)).monospacedDigit()
                }.width(90)
            }
            .scrollContentBackground(.hidden)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 28).padding(.top, 34).padding(.bottom, 20)
    }
}

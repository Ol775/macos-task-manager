import SwiftUI
import Charts

private func bytes(_ b: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory) }

// MARK: Processes

@MainActor func endTask(_ pid: Int32) {
    guard kill(pid, SIGTERM) != 0 else { return }
    let e = errno
    let a = NSAlert()
    a.messageText = e == EPERM ? "Not permitted" : "Couldn't end task"
    a.informativeText = e == EPERM ? "macOS only lets you end your own processes." : String(cString: strerror(e))
    a.runModal()
}

struct ProcessesView: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var settings: AppSettings
        @State private var search = ""
    @State private var selection: Int32?
    @State private var order = [KeyPathComparator(\Proc.cpu, order: .reverse)]

    private var rows: [Proc] {
        m.procs
            .filter { (!settings.appsOnly || $0.isApp) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
            .sorted(using: order)
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $order) {
            TableColumn("Name", value: \.name) { p in
                HStack(spacing: 8) {
                    if let icon = p.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                    else { Image(systemName: "gearshape.fill").frame(width: 20, height: 20).foregroundStyle(.tertiary) }
                    Text(p.name)
                }
            }
            TableColumn("CPU", value: \.cpu) { p in
                Text(String(format: "%.1f%%", p.cpu)).monospacedDigit()
                    .foregroundStyle(p.cpu >= 1 ? Color.primary : .secondary)
            }.width(min: 60, ideal: 80, max: 100)
            TableColumn("Memory", value: \.mem) { Text(bytes($0.mem)).monospacedDigit() }
                .width(min: 70, ideal: 100, max: 130)
            TableColumn("PID", value: \.id) { Text(String($0.id)).monospacedDigit().foregroundStyle(.secondary) }
                .width(min: 50, ideal: 70, max: 90)
        }
        .contextMenu(forSelectionType: Int32.self) { ids in
            Button("End Task", role: .destructive) { ids.forEach(endTask) }
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
                Button { if let pid = selection { endTask(pid) } } label: {
                    Label("End Task", systemImage: "xmark.circle")
                }
                .help("End the selected task").disabled(selection == nil)
            }
        }
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
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
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
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
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
            Stat("Processes", "\(m.procs.count)"),
            Stat("Up Time", uptime()),
        ])
    }
    private func uptime() -> String {
        let s = Int(ProcessInfo.processInfo.systemUptime)
        return String(format: "%dd %02d:%02d:%02d", s / 86400, s % 86400 / 3600, s % 3600 / 60, s % 60)
    }
}

struct MemoryDetail: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var s: AppSettings
    var body: some View {
        ResourceDetail(title: "Memory", subtitle: bytes(m.memTotal) + " installed", color: s.memoryColor, data: m.memHistory, stats: [
            Stat("In Use", bytes(m.memUsed)),
            Stat("Available", bytes(m.memTotal - min(m.memUsed, m.memTotal))),
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
        ])
    }
}

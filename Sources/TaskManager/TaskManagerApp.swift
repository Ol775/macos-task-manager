import SwiftUI
import Charts

@main
struct TaskManagerApp: App {
    @StateObject private var monitor = Monitor()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .onAppear { monitor.start() }
        }
        .defaultSize(width: 760, height: 560)
    }
}

struct ContentView: View {
    @State private var tab = Tab.processes
    enum Tab: String, CaseIterable { case processes = "Processes", performance = "Performance" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 260).padding(12)
            switch tab {
            case .processes: ProcessesView()
            case .performance: PerformanceView()
            }
        }
        .frame(minWidth: 560, minHeight: 400)
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
        VStack(spacing: 8) {
            HStack {
                Picker("", selection: $appsOnly) {
                    Text("Apps").tag(true); Text("All processes").tag(false)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                Spacer()
                Button("End Task") { if let pid = selection { kill(pid, SIGTERM) } }
                    .disabled(selection == nil)
            }
            .padding(.horizontal, 12)
            Table(rows, selection: $selection, sortOrder: $order) {
                TableColumn("Name", value: \.name)
                TableColumn("PID", value: \.id) { Text(String($0.id)).monospacedDigit() }.width(60)
                TableColumn("CPU", value: \.cpu) { Text(String(format: "%.1f%%", $0.cpu)).monospacedDigit() }.width(70)
                TableColumn("Memory", value: \.mem) {
                    Text(ByteCountFormatter.string(fromByteCount: Int64($0.mem), countStyle: .memory)).monospacedDigit()
                }.width(90)
            }
        }
    }
}

struct PerformanceView: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GraphCard(title: "CPU", value: String(format: "%.0f%%", monitor.cpuHistory.last ?? 0),
                          detail: "\(monitor.cores) cores", data: monitor.cpuHistory, color: .blue)
                GraphCard(title: "Memory",
                          value: ByteCountFormatter.string(fromByteCount: Int64(monitor.memUsed), countStyle: .memory),
                          detail: "of " + ByteCountFormatter.string(fromByteCount: Int64(monitor.memTotal), countStyle: .memory),
                          data: monitor.memHistory, color: .purple)
            }
            .padding(16)
        }
    }
}

struct GraphCard: View {
    let title, value, detail: String
    let data: [Double]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(detail).foregroundStyle(.secondary)
            }
            Chart(Array(data.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("t", i), y: .value("%", v)).foregroundStyle(color.opacity(0.25))
                LineMark(x: .value("t", i), y: .value("%", v)).foregroundStyle(color)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .frame(height: 140)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

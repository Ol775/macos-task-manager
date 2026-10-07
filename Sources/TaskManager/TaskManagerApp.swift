import SwiftUI

@main
struct TaskManagerApp: App {
    init() {
        if CommandLine.arguments.contains("--selftest") { let ok = Updater.selfTest(); print(ok ? "selftest ok" : "selftest FAILED"); exit(ok ? 0 : 1) }
    }

    @StateObject private var monitor = Monitor()
    @StateObject private var settings = AppSettings()
    @StateObject private var updates = UpdateModel()
    var body: some Scene {
        WindowGroup("Task Manager") {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(settings)
                .environmentObject(updates)
                .onAppear { settings.apply(); monitor.start(interval: settings.interval) }
                .onChange(of: settings.interval) { _, v in monitor.setInterval(v) }
        }
        .defaultSize(width: 1020, height: 680)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(updates: updates) }

        Window("About Task Manager", id: "about") {
            AboutView().environmentObject(updates)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView().environmentObject(monitor).environmentObject(settings)
        }
    }
}

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let updates: UpdateModel
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Task Manager") { openWindow(id: "about") }
            Button("Check for Updates…") { updates.check(); openWindow(id: "about") }
        }
    }
}

enum Item: Hashable { case processes, cpu, memory, gpu }

struct ContentView: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var s: AppSettings
    @EnvironmentObject var updates: UpdateModel
    @Environment(\.openWindow) private var openWindow
    @State private var item: Item? = .processes

    var body: some View {
        NavigationSplitView {
            List(selection: $item) {
                Label("Processes", systemImage: "list.bullet.rectangle")
                    .tag(Item.processes)
                Section("Performance") {
                    tile(.cpu, "CPU", s.cpuColor, m.cpuHistory)
                    tile(.memory, "Memory", s.memoryColor, m.memHistory)
                    if m.gpuAvailable { tile(.gpu, "GPU", s.gpuColor, m.gpuHistory) }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
            .safeAreaInset(edge: .bottom) {
                if let info = updates.available {
                    Button { openWindow(id: "about") } label: {
                        Label("Update available: \(info.version)", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderless).padding(10)
                }
            }
        } detail: {
            switch item ?? .processes {
            case .processes: ProcessesView()
            case .cpu: CPUDetail()
            case .memory: MemoryDetail()
            case .gpu: GPUDetail()
            }
        }
        .frame(minWidth: 780, minHeight: 500)
        .oledSurfaces(s.oled)
        .background(OLEDWindow(on: s.oled))
        .onAppear { if s.autoUpdate { updates.check() } }
    }

    private func tile(_ i: Item, _ title: String, _ color: Color, _ data: [Double]) -> some View {
        HStack(spacing: 10) {
            Sparkline(data: data, color: color).frame(width: 52, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(String(format: "%.0f%%", data.last ?? 0))
                    .font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .tag(i)
    }
}

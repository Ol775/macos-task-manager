import SwiftUI

@main
struct TaskManagerApp: App {
    init() {
        if CommandLine.arguments.contains("--selftest") { let ok = Updater.selfTest() && Checks.run(); print(ok ? "selftest ok" : "selftest FAILED"); exit(ok ? 0 : 1) }
    }

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var monitor = Monitor.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var nav = Nav.shared
    @StateObject private var updates = UpdateModel()
    var body: some Scene {
        Window("Task Manager", id: "main") {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(settings)
                .environmentObject(updates)
                .environmentObject(nav)
                .onAppear { settings.apply(); monitor.start(interval: settings.interval) }
                .onChange(of: settings.interval) { _, v in monitor.setInterval(v) }
        }
        .defaultSize(width: 1120, height: 720)
        .commands { AppCommands(updates: updates, nav: nav) }

        Window("About Task Manager", id: "about") {
            AboutView().environmentObject(updates)
        }
        .windowResizability(.contentSize)

    }
}

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let updates: UpdateModel
    let nav: Nav
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Task Manager") { openWindow(id: "about") }
            Button("Check for Updates…") { updates.check(); openWindow(id: "about") }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { nav.item = .settings }.keyboardShortcut(",")
        }
    }
}

/// Which page is showing; shared so ⌘, can jump to Settings from the menu.
@MainActor final class Nav: ObservableObject {
    static let shared = Nav()
    @Published var item: Item = .processes
}

/// Starts the menu bar item (when enabled) and brings the window back when the Dock icon is clicked with no window open.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { MenuBarController.shared.start() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { MenuBarController.shared.showMainWindow() } }
        return true
    }
}

enum Item: Hashable, CaseIterable {
    case processes, system, cpu, memory, gpu, disk, network, settings
    var title: String {
        switch self {
        case .processes: "Processes"; case .system: "System"; case .cpu: "CPU"; case .memory: "Memory"
        case .gpu: "GPU"; case .disk: "Disk"; case .network: "Network"; case .settings: "Settings"
        }
    }
    var icon: String { switch self { case .processes: "list.bullet.rectangle"; case .settings: "gearshape"; default: "desktopcomputer" } }
}

struct ContentView: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var s: AppSettings
    @EnvironmentObject var updates: UpdateModel
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var nav: Nav
    private var item: Item { nav.item }

    private var pages: [Item] {
        Item.allCases.filter { $0 != .settings && ($0 != .gpu || m.gpuAvailable) && ($0 != .disk || m.diskAvailable) }
    }

    var body: some View {
        let narrow = s.sidebarCollapsed
        HStack(spacing: 0) {
            sidebar(narrow: narrow)
                .frame(width: narrow ? 68 : 232).frame(maxHeight: .infinity)
                .background(s.oled ? Color.black : Color(nsColor: .controlBackgroundColor).opacity(0.6))
            Divider()
            Group {
                switch item {
                case .processes: ProcessesView()
                case .system: SystemView()
                case .cpu: CPUDetail()
                case .memory: MemoryDetail()
                case .gpu: GPUDetail()
                case .disk: DiskDetail()
                case .network: NetworkDetail()
                case .settings: SettingsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(s.oled ? Color.black : Color(nsColor: .windowBackgroundColor))
        }
        .tint(s.accent)
        .id(s.themeKey)
        .frame(minWidth: 1040, minHeight: 560)
        .background(OLEDWindow(on: s.oled))
        .onAppear {
            if s.autoUpdate { updates.check() }
            MenuBarController.shared.showMainWindow = { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }
        }
    }

    private func sidebar(narrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { s.sidebarCollapsed.toggle() } } label: {
                Image(systemName: "sidebar.left").font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 28, height: 28)
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .buttonStyle(.plain).help(narrow ? "Show sidebar labels" : "Collapse to icons").padding(.bottom, 4)

            ForEach(Array(pages.enumerated()), id: \.element) { index, page in
                if page == .cpu && !narrow {
                    Text("PERFORMANCE").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 2)
                } else if page == .cpu { Divider().padding(.vertical, 6) }
                navButton(page, index: index, narrow: narrow)
            }
            Spacer()
            footer(narrow: narrow)
        }
        .padding(10)
    }

    @ViewBuilder private func navButton(_ page: Item, index: Int, narrow: Bool) -> some View {
        let on = item == page
        Button { nav.item = page } label: {
            HStack(spacing: 10) {
                if let t = tile(page) {
                    Sparkline(series: t.series, scale: t.scale).frame(width: narrow ? 40 : 46, height: 28)
                    if !narrow {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(page.title).font(.system(size: 13, weight: on ? .semibold : .regular))
                            Text(t.value).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                } else {
                    Image(systemName: page.icon).font(.system(size: 16)).foregroundStyle(s.accent).frame(width: narrow ? 40 : 46)
                    if !narrow { Text(page.title).font(.system(size: 13, weight: on ? .semibold : .regular)) }
                }
                if !narrow { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? (s.oled ? Color(white: 0.16) : s.accent.opacity(0.18)) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("\(page.title) (⌘\(index + 1))")
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        .accessibilityLabel(page.title).accessibilityAddTraits(on ? .isSelected : [])
    }

    private func tile(_ page: Item) -> (series: [Series], scale: Scale, value: String)? {
        func pct(_ d: [Double]) -> String { String(format: "%.0f%%", d.last ?? 0) }
        switch page {
        case .cpu: return ([Series(name: "CPU", data: m.cpuHistory, color: Color.metric(s.cpuColor))], .percent, pct(m.cpuHistory))
        case .memory: return ([Series(name: "Memory", data: m.memHistory, color: Color.metric(s.memoryColor))], .percent, pct(m.memHistory))
        case .gpu: return ([Series(name: "GPU", data: m.gpuHistory, color: Color.metric(s.gpuColor))], .percent, pct(m.gpuHistory))
        case .disk:
            let sum = zip(m.diskRead, m.diskWrite).map(+)
            return ([Series(name: "Disk", data: sum, color: Color.metric(s.diskColor))], .rate(floor: 1_000_000), Rates.format(sum.last ?? 0))
        case .network:
            let sum = zip(m.netRx["all"] ?? [], m.netTx["all"] ?? []).map(+)
            let data = sum.isEmpty ? [Double](repeating: 0, count: Monitor.samples) : sum
            return ([Series(name: "Network", data: data, color: Color.metric(s.networkColor))], .rate(floor: 100_000), Rates.format(data.last ?? 0))
        default: return nil
        }
    }

    private func footer(narrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info = updates.available {
                Button { openWindow(id: "about") } label: {
                    Label(narrow ? "" : "Update available: \(info.version)", systemImage: "arrow.down.circle.fill").font(.system(size: 12, weight: .medium))
                }.buttonStyle(.borderless).help("Update available: \(info.version)")
            }
            Button { nav.item = .settings } label: {
                Label(narrow ? "" : "Settings", systemImage: "gearshape").font(.system(size: 13, weight: item == .settings ? .semibold : .regular))
                    .foregroundStyle(item == .settings ? s.accent : Color.secondary)
            }
            .buttonStyle(.borderless).help("Settings (⌘,)")
            if !narrow {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Task Manager").font(.system(size: 11, weight: .semibold))
                    Text("v\(AppInfo.version) · build \(AppInfo.build)").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.top, 4)
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 4).frame(maxWidth: .infinity, alignment: narrow ? .center : .leading)
    }
}

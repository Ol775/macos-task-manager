import SwiftUI
import AppKit
import Combine

// MARK: - What the menu bar shows

enum MenuMetric: String, CaseIterable, Identifiable {
    case cpu, memory, gpu, disk, network
    var id: String { rawValue }
    var title: String {
        switch self { case .cpu: "CPU"; case .memory: "Memory"; case .gpu: "GPU"; case .disk: "Disk"; case .network: "Network" }
    }
    var short: String {
        switch self { case .cpu: "CPU"; case .memory: "MEM"; case .gpu: "GPU"; case .disk: "DSK"; case .network: "NET" }
    }
    static let defaults: [MenuMetric] = [.cpu, .memory]

    static func encode(_ items: [MenuMetric]) -> String { items.map(\.rawValue).joined(separator: ",") }
    /// Unknown names are dropped and the canonical order kept; nil (never saved) gives the defaults.
    static func decode(_ s: String?) -> [MenuMetric] {
        guard let s else { return defaults }
        let want = Set(s.split(separator: ",").compactMap { MenuMetric(rawValue: String($0)) })
        return allCases.filter(want.contains)
    }
}

/// The text next to the menu bar icon, e.g. "CPU 34%  MEM 72%".
enum MenuBarLabel {
    struct Values { var cpu = 0.0, memory = 0.0, gpu = 0.0, disk = 0.0, network = 0.0 }   // percentages; disk and network in bytes per second

    static func rate(_ v: Double) -> String {
        guard v.isFinite, v >= 1 else { return "0 B/s" }
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var x = v, i = 0
        while x >= 1000, i < units.count - 1 { x /= 1000; i += 1 }
        return (x >= 100 || i == 0 ? String(format: "%.0f", x) : String(format: "%.1f", x)) + " " + units[i]
    }

    static func text(_ items: [MenuMetric], labels: Bool, _ v: Values) -> String {
        items.map { m in
            let value: String
            switch m {
            case .cpu: value = String(format: "%.0f%%", v.cpu)
            case .memory: value = String(format: "%.0f%%", v.memory)
            case .gpu: value = String(format: "%.0f%%", v.gpu)
            case .disk: value = rate(v.disk)
            case .network: value = rate(v.network)
            }
            return labels ? "\(m.short) \(value)" : value
        }.joined(separator: "  ")
    }
}

// MARK: - Status item and popover

/// Owns the menu bar item, its popover and the Dock-icon choice. Everything follows `AppSettings`.
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()
    /// Set by the main window; brings the window to the front (opening it if it was closed).
    var showMainWindow: () -> Void = {}

    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var bag = Set<AnyCancellable>()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let s = AppSettings.shared, m = Monitor.shared
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView:
            MenuBarPopover().environmentObject(m).environmentObject(s).environmentObject(Nav.shared))
        s.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in DispatchQueue.main.async { self?.sync() } }.store(in: &bag)
        m.objectWillChange.debounce(for: .milliseconds(150), scheduler: RunLoop.main).sink { [weak self] _ in self?.refreshTitle() }.store(in: &bag)
        sync()
        // For screenshots: `--popover` opens the popover shortly after launch (the item can sit behind a menu bar manager).
        if CommandLine.arguments.contains("--popover") { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.toggle() } }
    }

    /// Creates or removes the item and applies the Dock setting to match the settings.
    func sync() {
        let s = AppSettings.shared
        if s.menuBarEnabled {
            if item == nil {
                item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item?.button?.target = self
                item?.button?.action = #selector(toggle)
                Monitor.shared.start(interval: s.interval)
            }
            refreshTitle()
        } else if let i = item {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(i)
            item = nil
        }
        let wantAccessory = s.menuBarEnabled && s.hideDock
        let policy: NSApplication.ActivationPolicy = wantAccessory ? .accessory : .regular
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy); if !wantAccessory { NSApp.activate(ignoringOtherApps: true) } }
    }

    private func refreshTitle() {
        guard let button = item?.button else { return }
        let s = AppSettings.shared, m = Monitor.shared
        let net = (m.netRx["all"]?.last ?? 0) + (m.netTx["all"]?.last ?? 0)
        let v = MenuBarLabel.Values(cpu: m.cpuHistory.last ?? 0, memory: m.memHistory.last ?? 0, gpu: m.gpuHistory.last ?? 0,
                                    disk: (m.diskRead.last ?? 0) + (m.diskWrite.last ?? 0), network: net)
        let text = MenuBarLabel.text(s.menuItems, labels: s.menuLabels, v)
        let icon = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Task Manager")
        icon?.isTemplate = true
        button.image = s.menuShowIcon || text.isEmpty ? icon : nil
        button.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
        button.attributedTitle = NSAttributedString(string: text.isEmpty ? "" : " " + text,
                                                    attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
        button.setAccessibilityLabel("Task Manager: " + (text.isEmpty ? "open" : text))
    }

    @objc private func toggle() {
        guard let button = item?.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closePopover() { popover.performClose(nil) }
}

// MARK: - Popover

struct MenuBarPopover: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var s: AppSettings
    @EnvironmentObject var nav: Nav

    private var top: [Proc] { Array(m.procs.filter { $0.isApp || $0.cpu > 0.5 }.sorted { $0.cpu > $1.cpu }.prefix(5)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Task Manager").font(.system(size: ts(15), weight: .bold, design: .rounded))
                Spacer()
                Text(SystemInfo.thermal == "Nominal" ? "" : "Thermal: \(SystemInfo.thermal)").font(.system(size: ts(11))).foregroundStyle(.orange)
            }
            VStack(spacing: 0) {
                metric(.cpu, value: String(format: "%.0f%%", m.cpuHistory.last ?? 0), series: Series(name: "CPU", data: m.cpuHistory, color: Color.metric(s.cpuColor)), scale: .percent)
                metric(.memory, value: String(format: "%.0f%%", m.memHistory.last ?? 0), series: Series(name: "Memory", data: m.memHistory, color: Color.metric(s.memoryColor)), scale: .percent)
                if m.gpuAvailable {
                    metric(.gpu, value: String(format: "%.0f%%", m.gpuHistory.last ?? 0), series: Series(name: "GPU", data: m.gpuHistory, color: Color.metric(s.gpuColor)), scale: .percent)
                }
                if m.diskAvailable {
                    let sum = zip(m.diskRead, m.diskWrite).map(+)
                    metric(.disk, value: Rates.format(sum.last ?? 0), series: Series(name: "Disk", data: sum, color: Color.metric(s.diskColor)), scale: .rate(floor: 1_000_000))
                }
                let net = zip(m.netRx["all"] ?? [], m.netTx["all"] ?? []).map(+)
                metric(.network, value: Rates.format(net.last ?? 0),
                       series: Series(name: "Network", data: net.isEmpty ? [Double](repeating: 0, count: Monitor.samples) : net, color: Color.metric(s.networkColor)),
                       scale: .rate(floor: 100_000), last: true)
            }
            .padding(.horizontal, 12).card()

            VStack(alignment: .leading, spacing: 6) {
                Text("Busiest apps").font(.system(size: ts(12), weight: .semibold)).foregroundStyle(.secondary)
                ForEach(top) { p in
                    HStack(spacing: 8) {
                        if let icon = p.icon { Image(nsImage: icon).resizable().frame(width: ts(18), height: ts(18)) }
                        else { Image(systemName: "gearshape.fill").frame(width: ts(18), height: ts(18)).foregroundStyle(.secondary) }
                        Text(p.name).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(String(format: "%.1f%%", p.cpu)).monospacedDigit().foregroundStyle(.secondary)
                    }.font(.system(size: ts(12.5)))
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(p.name), \(String(format: "%.1f", p.cpu)) percent CPU")
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).card()

            HStack(spacing: 8) {
                Button { open(.processes) } label: { Label("Open Task Manager", systemImage: "macwindow") }
                Spacer()
                Button { open(.settings) } label: { Image(systemName: "gearshape") }.help("Settings").accessibilityLabel("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quit Task Manager").accessibilityLabel("Quit Task Manager")
            }
            .controlSize(.regular)
        }
        .padding(14).frame(width: ts(330)).font(.system(size: ts(13)))
        .tint(s.accent)
    }

    private func metric(_ kind: MenuMetric, value: String, series: Series, scale: Scale, last: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(kind.title).font(.system(size: ts(13), weight: .medium)).frame(width: ts(64), alignment: .leading)
            Sparkline(series: [series], scale: scale).frame(height: 24)
            Text(value).font(.system(size: ts(13), weight: .semibold)).monospacedDigit().frame(width: ts(78), alignment: .trailing)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { if !last { Divider().opacity(0.5) } }
        .accessibilityElement(children: .ignore).accessibilityLabel(kind.title).accessibilityValue(value)
    }

    private func open(_ page: Item) {
        nav.item = page
        MenuBarController.shared.closePopover()
        MenuBarController.shared.showMainWindow()
    }
}

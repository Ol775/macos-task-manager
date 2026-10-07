import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self.init(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255,
                  blue: Double(v & 255) / 255, opacity: 1)
    }
    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "%02X%02X%02X", Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    enum Appearance: String, CaseIterable, Identifiable {
        case system = "System", light = "Light", dark = "Dark", oled = "OLED Black"
        var id: String { rawValue }
    }
    static let defaultColors = (cpu: "0A84FF", memory: "BF5AF2", gpu: "FF9F0A", disk: "30D158", network: "32ADE6")
    private static let d = UserDefaults.standard

    @Published var appearance: Appearance { didSet { Self.d.set(appearance.rawValue, forKey: "appearance"); apply() } }
    @Published var interval: Double { didSet { Self.d.set(interval, forKey: "interval") } }
    @Published var autoUpdate: Bool { didSet { Self.d.set(autoUpdate, forKey: "autoUpdate") } }
    @Published var appsOnly: Bool { didSet { Self.d.set(appsOnly, forKey: "appsOnly") } }
    @Published var cpuColor: Color { didSet { Self.d.set(cpuColor.hex, forKey: "cpuColor") } }
    @Published var memoryColor: Color { didSet { Self.d.set(memoryColor.hex, forKey: "memoryColor") } }
    @Published var gpuColor: Color { didSet { Self.d.set(gpuColor.hex, forKey: "gpuColor") } }
    @Published var diskColor: Color { didSet { Self.d.set(diskColor.hex, forKey: "diskColor") } }
    @Published var networkColor: Color { didSet { Self.d.set(networkColor.hex, forKey: "networkColor") } }
    @Published var theme: AccentTheme { didSet { Self.d.set(theme.rawValue, forKey: "theme") } }
    @Published var customAccent: Color { didSet { Self.d.set(customAccent.hex, forKey: "customAccent") } }
    @Published var corners: CardCorners { didSet { Self.d.set(corners.rawValue, forKey: "corners") } }
    @Published var columns: [ProcColumn] { didSet { Self.d.set(ProcColumn.encode(columns), forKey: "columns") } }
    @Published var sidebarCollapsed: Bool { didSet { Self.d.set(sidebarCollapsed, forKey: "sidebarCollapsed") } }
    @Published var menuBarEnabled: Bool { didSet { Self.d.set(menuBarEnabled, forKey: "menuBarEnabled") } }
    @Published var hideDock: Bool { didSet { Self.d.set(hideDock, forKey: "hideDock") } }
    @Published var menuShowIcon: Bool { didSet { Self.d.set(menuShowIcon, forKey: "menuShowIcon") } }
    @Published var menuLabels: Bool { didSet { Self.d.set(menuLabels, forKey: "menuLabels") } }
    @Published var menuItems: [MenuMetric] { didSet { Self.d.set(MenuMetric.encode(menuItems), forKey: "menuItems") } }

    init() {
        let d = Self.d
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        let i = d.double(forKey: "interval")
        interval = i > 0 ? i : 1
        appsOnly = d.object(forKey: "appsOnly") as? Bool ?? true
        autoUpdate = d.object(forKey: "autoUpdate") as? Bool ?? true
        cpuColor = Color(hex: d.string(forKey: "cpuColor") ?? Self.defaultColors.cpu)
        memoryColor = Color(hex: d.string(forKey: "memoryColor") ?? Self.defaultColors.memory)
        gpuColor = Color(hex: d.string(forKey: "gpuColor") ?? Self.defaultColors.gpu)
        diskColor = Color(hex: d.string(forKey: "diskColor") ?? Self.defaultColors.disk)
        networkColor = Color(hex: d.string(forKey: "networkColor") ?? Self.defaultColors.network)
        theme = AccentTheme(rawValue: d.string(forKey: "theme") ?? "") ?? .ocean
        customAccent = Color(hex: d.string(forKey: "customAccent") ?? "5E5CE6")
        corners = CardCorners(rawValue: d.string(forKey: "corners") ?? "") ?? .standard
        columns = ProcColumn.decode(d.string(forKey: "columns"))
        sidebarCollapsed = d.bool(forKey: "sidebarCollapsed")
        menuBarEnabled = d.bool(forKey: "menuBarEnabled")
        hideDock = d.bool(forKey: "hideDock")
        menuShowIcon = d.object(forKey: "menuShowIcon") as? Bool ?? true
        menuLabels = d.object(forKey: "menuLabels") as? Bool ?? true
        menuItems = MenuMetric.decode(d.string(forKey: "menuItems"))
    }

    /// Accent for icons and text: brighter in dark mode, deeper in light mode.
    var accent: Color {
        let (dark, light) = theme.colors(custom: customAccent.hex)
        return Color(nsColor: .dynamic(dark: dark, light: light))
    }
    /// Accent for fills that carry white text; always the deep variant so the text stays readable.
    var accentFill: Color { Color(nsColor: theme.colors(custom: customAccent.hex).1) }
    /// Re-renders everything that caches dynamic colours when the theme changes.
    var themeKey: String { theme.rawValue + (theme == .custom ? customAccent.hex : "") + corners.rawValue }

    var oled: Bool { appearance == .oled }

    func apply() {
        switch appearance {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark, .oled: NSApp?.appearance = NSAppearance(named: .darkAqua)     // OLED is dark with pure-black surfaces
        }
    }

    /// Surface colour for cards: pure-black theme uses a barely-lifted grey so cards still read on #000.
    var cardColor: Color { oled ? Color(white: 0.07) : Color(nsColor: .controlBackgroundColor) }

    func resetColors() {
        cpuColor = Color(hex: Self.defaultColors.cpu)
        memoryColor = Color(hex: Self.defaultColors.memory)
        gpuColor = Color(hex: Self.defaultColors.gpu)
        diskColor = Color(hex: Self.defaultColors.disk)
        networkColor = Color(hex: Self.defaultColors.network)
    }
}

extension View {
    /// Pure-black surfaces for the OLED theme (sidebar, detail and tables).
    @ViewBuilder func oledSurfaces(_ on: Bool) -> some View {
        if on { self.scrollContentBackground(.hidden).containerBackground(Color.black, for: .window) } else { self }
    }
}

/// The OLED theme needs the sidebar/toolbar blur to read as true #000. Each NSVisualEffectView gets a black shim behind
/// its content (the blur is the view's own layer, so the shim covers it); the shims are removed when the theme is off.
struct OLEDWindow: NSViewRepresentable {
    let on: Bool
    private static let shimID = NSUserInterfaceItemIdentifier("oled-shim")

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let on = self.on
        DispatchQueue.main.async {
            guard let root = view.window?.contentView?.superview else { return }
            func walk(_ v: NSView) {
                if v is NSVisualEffectView {
                    let shim = v.subviews.first { $0.identifier == Self.shimID }
                    if on, shim == nil {
                        let s = NSView(frame: v.bounds)
                        s.identifier = Self.shimID; s.autoresizingMask = [.width, .height]
                        s.wantsLayer = true; s.layer?.backgroundColor = NSColor.black.cgColor
                        v.addSubview(s, positioned: .below, relativeTo: v.subviews.first)
                    } else if !on { shim?.removeFromSuperview() }
                }
                v.subviews.forEach(walk)
            }
            walk(root)
            view.window?.backgroundColor = on ? .black : .windowBackgroundColor
        }
    }
}

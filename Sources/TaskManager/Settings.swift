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
    enum Appearance: String, CaseIterable, Identifiable {
        case system = "System", light = "Light", dark = "Dark"
        var id: String { rawValue }
    }
    static let defaultColors = (cpu: "0A84FF", memory: "BF5AF2", gpu: "FF9F0A")
    private static let d = UserDefaults.standard

    @Published var appearance: Appearance { didSet { Self.d.set(appearance.rawValue, forKey: "appearance"); apply() } }
    @Published var interval: Double { didSet { Self.d.set(interval, forKey: "interval") } }
    @Published var appsOnly: Bool { didSet { Self.d.set(appsOnly, forKey: "appsOnly") } }
    @Published var cpuColor: Color { didSet { Self.d.set(cpuColor.hex, forKey: "cpuColor") } }
    @Published var memoryColor: Color { didSet { Self.d.set(memoryColor.hex, forKey: "memoryColor") } }
    @Published var gpuColor: Color { didSet { Self.d.set(gpuColor.hex, forKey: "gpuColor") } }

    init() {
        let d = Self.d
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        let i = d.double(forKey: "interval")
        interval = i > 0 ? i : 1
        appsOnly = d.object(forKey: "appsOnly") as? Bool ?? true
        cpuColor = Color(hex: d.string(forKey: "cpuColor") ?? Self.defaultColors.cpu)
        memoryColor = Color(hex: d.string(forKey: "memoryColor") ?? Self.defaultColors.memory)
        gpuColor = Color(hex: d.string(forKey: "gpuColor") ?? Self.defaultColors.gpu)
    }

    func apply() {
        NSApp?.appearance = appearance == .system ? nil : NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
    }

    func resetColors() {
        cpuColor = Color(hex: Self.defaultColors.cpu)
        memoryColor = Color(hex: Self.defaultColors.memory)
        gpuColor = Color(hex: Self.defaultColors.gpu)
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ColourSettings().tabItem { Label("Colours", systemImage: "paintpalette") }
            PermissionsSettings().tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 500, height: 360)
    }
}

struct GeneralSettings: View {
    @EnvironmentObject var s: AppSettings
    var body: some View {
        Form {
            Picker("Appearance", selection: $s.appearance) {
                ForEach(AppSettings.Appearance.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Picker("Update every", selection: $s.interval) {
                Text("0.5 seconds").tag(0.5)
                Text("1 second").tag(1.0)
                Text("2 seconds").tag(2.0)
                Text("5 seconds").tag(5.0)
            }
            Toggle("Show apps only in Processes", isOn: $s.appsOnly)
        }
        .formStyle(.grouped)
    }
}

struct ColourSettings: View {
    @EnvironmentObject var s: AppSettings
    var body: some View {
        Form {
            ColorPicker("CPU", selection: $s.cpuColor, supportsOpacity: false)
            ColorPicker("Memory", selection: $s.memoryColor, supportsOpacity: false)
            ColorPicker("GPU", selection: $s.gpuColor, supportsOpacity: false)
            Button("Reset to Defaults") { s.resetColors() }
        }
        .formStyle(.grouped)
    }
}

struct PermissionsSettings: View {
    @EnvironmentObject var m: Monitor
    var body: some View {
        let hidden = max(m.pidTotal - m.pidReadable, 0)
        Form {
            Section {
                StatusRow(ok: true, title: "Your apps and processes",
                          detail: "Full access: CPU, memory and End Task all work.")
                StatusRow(ok: hidden == 0, title: "System and other users' processes",
                          detail: "Showing \(m.pidReadable) of \(m.pidTotal). \(hidden) are hidden because macOS only lets administrators inspect them. Not needed for everyday use.")
                StatusRow(ok: m.gpuAvailable, title: "GPU statistics",
                          detail: m.gpuAvailable ? "Reading utilisation from the graphics driver." : "No GPU statistics are available on this Mac.")
            } footer: {
                Text("TaskManager needs no special macOS permissions: no Full Disk Access, Accessibility or Screen Recording.")
            }
        }
        .formStyle(.grouped)
    }
}

struct StatusRow: View {
    let ok: Bool
    let title, detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

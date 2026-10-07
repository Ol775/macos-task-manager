import SwiftUI

/// Settings live inside the main window (sidebar → Settings, or ⌘,) rather than in a separate window.
struct SettingsPage: View {
    @EnvironmentObject var s: AppSettings
    @EnvironmentObject var m: Monitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Settings", subtitle: "Appearance, graph colours, process columns and permissions") { EmptyView() }

                section("Appearance") {
                    row("Theme") { PillPicker(selection: $s.appearance, options: AppSettings.Appearance.allCases.map { ($0, $0.rawValue) }) }
                    row("Accent colour") { swatches }
                    row("Card corners") { PillPicker(selection: $s.corners, options: CardCorners.allCases.map { ($0, $0.label) }) }
                }

                section("General") {
                    row("Update graphs every") {
                        Picker("", selection: $s.interval) {
                            Text("0.5 seconds").tag(0.5); Text("1 second").tag(1.0); Text("2 seconds").tag(2.0); Text("5 seconds").tag(5.0)
                        }.labelsHidden().fixedSize()
                    }
                    row("Show apps only in Processes") { Toggle("", isOn: $s.appsOnly).labelsHidden().toggleStyle(.switch) }
                    row("Check for updates automatically") { Toggle("", isOn: $s.autoUpdate).labelsHidden().toggleStyle(.switch) }
                }

                section("Process columns", footer: "Name is always shown. You can also right-click the column headings in Processes.") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 10) {
                        ForEach(ProcColumn.optional) { c in
                            Toggle(c.title, isOn: Binding(
                                get: { s.columns.contains(c) },
                                set: { on in s.columns = ProcColumn.optional.filter { $0 == c ? on : s.columns.contains($0) } }))
                        }
                    }.padding(.vertical, 10)
                    Divider().opacity(0.5)
                    HStack { Spacer(); Button("Reset Columns") { s.columns = ProcColumn.defaults } }.padding(.vertical, 8)
                }

                section("Graph colours") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 10) {
                        ColorPicker("CPU", selection: $s.cpuColor, supportsOpacity: false)
                        ColorPicker("Memory", selection: $s.memoryColor, supportsOpacity: false)
                        ColorPicker("GPU", selection: $s.gpuColor, supportsOpacity: false)
                        ColorPicker("Disk", selection: $s.diskColor, supportsOpacity: false)
                        ColorPicker("Network", selection: $s.networkColor, supportsOpacity: false)
                    }.padding(.vertical, 10)
                    Divider().opacity(0.5)
                    HStack { Spacer(); Button("Reset Colours") { s.resetColors() } }.padding(.vertical, 8)
                }

                permissions
            }
            .padding(24).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private var swatches: some View {
        HStack(spacing: 8) {
            ForEach(AccentTheme.allCases.filter { $0 != .custom }) { t in
                let on = s.theme == t
                Button { s.theme = t } label: {
                    Circle().fill(Color(nsColor: t.colors(custom: "").1)).frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Color.primary, lineWidth: on ? 2 : 0).padding(-3))
                }
                .buttonStyle(.plain).help(t.label).accessibilityLabel(t.label).accessibilityAddTraits(on ? .isSelected : [])
            }
            Button { s.theme = .custom } label: {
                Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center)).frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.primary, lineWidth: s.theme == .custom ? 2 : 0).padding(-3))
            }
            .buttonStyle(.plain).help("Custom").accessibilityLabel("Custom accent")
            if s.theme == .custom { ColorPicker("", selection: $s.customAccent, supportsOpacity: false).labelsHidden() }
        }
        .padding(.leading, 3)
    }

    private var permissions: some View {
        let hidden = max(m.pidTotal - m.pidReadable, 0)
        return section("Permissions", footer: "Task Manager needs no special macOS permissions: no Full Disk Access, Accessibility or Screen Recording.") {
            StatusRow(ok: true, title: "Your apps and processes", detail: "Full access: CPU, memory, disk, details and End Task all work.").padding(.vertical, 8)
            Divider().opacity(0.5)
            StatusRow(ok: hidden == 0, title: "System and other users’ processes",
                      detail: "Showing \(m.pidReadable) of \(m.pidTotal). \(hidden) are hidden because macOS only lets administrators inspect them. Not needed for everyday use.").padding(.vertical, 8)
            Divider().opacity(0.5)
            StatusRow(ok: m.gpuAvailable, title: "GPU statistics",
                      detail: m.gpuAvailable ? "Reading utilisation from the graphics driver." : "No GPU statistics are available on this Mac.").padding(.vertical, 8)
            Divider().opacity(0.5)
            StatusRow(ok: m.diskAvailable, title: "Disk statistics",
                      detail: m.diskAvailable ? "Reading transfer counters from the storage drivers." : "No disk statistics are available on this Mac.").padding(.vertical, 8)
        }
    }

    private func section<C: View>(_ title: String, footer: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 16).frame(maxWidth: .infinity, alignment: .leading).card()
            if let footer { Text(footer).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4) }
        }
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 16)
            control()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
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

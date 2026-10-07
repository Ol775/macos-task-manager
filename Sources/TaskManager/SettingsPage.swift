import SwiftUI

/// Settings live inside the main window (sidebar → Settings, or ⌘,) rather than in a separate window.
struct SettingsPage: View {
    @EnvironmentObject var s: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Settings", subtitle: "Appearance, graph colours, process columns and permissions") { EmptyView() }

                section("Appearance") {
                    row("Theme") { PillPicker(selection: $s.appearance, options: AppSettings.Appearance.allCases.map { ($0, $0.rawValue) }, label: "Theme") }
                    row("Accent colour") { swatches }
                    row("Text size") { PillPicker(selection: $s.textSize, options: TextSize.allCases.map { ($0, $0.label) }, label: "Text size") }
                    row("Card corners") { PillPicker(selection: $s.corners, options: CardCorners.allCases.map { ($0, $0.label) }, label: "Card corners") }
                }

                section("General") {
                    row("Update graphs every") {
                        Picker("Update graphs every", selection: $s.interval) {
                            Text("0.5 seconds").tag(0.5); Text("1 second").tag(1.0); Text("2 seconds").tag(2.0); Text("5 seconds").tag(5.0)
                        }.labelsHidden().fixedSize()
                    }
                    row("Show apps only in Processes") { Toggle("Show apps only in Processes", isOn: $s.appsOnly).labelsHidden().toggleStyle(.switch) }
                    row("Check for updates automatically") { Toggle("Check for updates automatically", isOn: $s.autoUpdate).labelsHidden().toggleStyle(.switch) }
                }

                section("Menu bar", footer: "A compact readout in the menu bar, and a popover with graphs and your busiest apps. Hiding the Dock icon needs the menu bar item, so the app is always reachable.") {
                    row("Show in menu bar") { Toggle("Show in menu bar", isOn: $s.menuBarEnabled).labelsHidden().toggleStyle(.switch) }
                    row("Hide Dock icon") { Toggle("Hide Dock icon", isOn: $s.hideDock).labelsHidden().toggleStyle(.switch).disabled(!s.menuBarEnabled) }
                    row("Show icon") { Toggle("Show icon", isOn: $s.menuShowIcon).labelsHidden().toggleStyle(.switch).disabled(!s.menuBarEnabled) }
                    row("Show labels (CPU 34%)") { Toggle("Show labels", isOn: $s.menuLabels).labelsHidden().toggleStyle(.switch).disabled(!s.menuBarEnabled) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 10) {
                        ForEach(MenuMetric.allCases) { k in
                            Toggle(k.title, isOn: Binding(
                                get: { s.menuItems.contains(k) },
                                set: { on in s.menuItems = MenuMetric.allCases.filter { $0 == k ? on : s.menuItems.contains($0) } }))
                        }
                    }.padding(.vertical, 10).disabled(!s.menuBarEnabled)
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

                PermissionsSection()
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
            .buttonStyle(.plain).help("Custom").accessibilityLabel("Custom accent").accessibilityAddTraits(s.theme == .custom ? .isSelected : [])
            if s.theme == .custom { ColorPicker("Custom accent colour", selection: $s.customAccent, supportsOpacity: false).labelsHidden() }
        }
        .padding(.leading, 3)
    }

    private func section<C: View>(_ title: String, footer: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: ts(13), weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 16).frame(maxWidth: .infinity, alignment: .leading).card()
            if let footer { Text(footer).font(.system(size: ts(11))).foregroundStyle(.secondary).padding(.horizontal, 4) }
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
                .foregroundStyle(ok ? .green : .orange).font(.system(size: ts(16))).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.system(size: ts(11))).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ok ? "OK" : "Needs attention"): \(title). \(detail)")
    }
}

/// The permissions card is the only part of Settings that shows live data, so it alone watches the monitor.
struct PermissionsSection: View {
    @EnvironmentObject var m: Monitor
    var body: some View {
        let hidden = max(m.pidTotal - m.pidReadable, 0)
        VStack(alignment: .leading, spacing: 6) {
            Text("Permissions").font(.system(size: ts(13), weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
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
            .padding(.horizontal, 16).frame(maxWidth: .infinity, alignment: .leading).card()
            Text("Task Manager needs no special macOS permissions: no Full Disk Access, Accessibility or Screen Recording.")
                .font(.system(size: ts(11))).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }
}

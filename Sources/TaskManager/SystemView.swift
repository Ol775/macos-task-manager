import SwiftUI

struct SystemView: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: SystemInfo.modelName, subtitle: "\(m.cpuName) · \(SystemInfo.macOS)") { EmptyView() }
                card("Hardware", [
                    ("Model", SystemInfo.modelName),
                    ("Identifier", SystemInfo.modelIdentifier),
                    ("Chip", m.cpuName),
                    ("Cores", SystemInfo.cores),
                    ("Memory", bytes(m.memTotal)),
                    ("Graphics", m.gpuAvailable ? m.gpuName + (m.gpuCores.map { ", \($0) cores" } ?? "") : "Not available"),
                ])
                card("Software", [
                    ("System", SystemInfo.macOS),
                    ("Build", SystemInfo.build),
                    ("Up time", SystemInfo.uptime()),
                    ("Thermal state", SystemInfo.thermal),
                ])
                if let s = SystemInfo.storage {
                    let used = Double(s.total - s.available) / Double(max(s.total, 1))
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Storage").font(.system(size: ts(13), weight: .semibold))
                        CapsuleBar(value: used, color: Color.metric(settings.diskColor), height: 8)
                        HStack {
                            Text("\(ByteCountFormatter.string(fromByteCount: s.total - s.available, countStyle: .file)) used")
                            Spacer()
                            Text("\(ByteCountFormatter.string(fromByteCount: s.available, countStyle: .file)) available of \(ByteCountFormatter.string(fromByteCount: s.total, countStyle: .file))")
                                .foregroundStyle(.secondary)
                        }.font(.system(size: ts(12.5))).monospacedDigit()
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
                }
                if let b = SystemInfo.battery {
                    card("Battery", [("Charge", "\(b.percent)%"), ("Power", b.state)])
                }
            }
            .padding(24)
        }
    }

    private func card(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: ts(13), weight: .semibold)).padding(.bottom, 8)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                if i > 0 { Divider().opacity(0.5) }
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer(minLength: 16)
                    Text(row.1).multilineTextAlignment(.trailing).textSelection(.enabled)
                }
                .font(.system(size: ts(13))).padding(.vertical, 7).accessibilityElement(children: .combine)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

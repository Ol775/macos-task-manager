import SwiftUI

private func bytes(_ b: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory) }

struct SystemView: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SystemInfo.modelName).font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("\(m.cpuName) · \(SystemInfo.macOS)").foregroundStyle(.secondary)
                }
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
                        Text("Storage").font(.headline)
                        ProgressView(value: used).tint(settings.cpuColor)
                        HStack {
                            Text("\(ByteCountFormatter.string(fromByteCount: s.total - s.available, countStyle: .file)) used")
                            Spacer()
                            Text("\(ByteCountFormatter.string(fromByteCount: s.available, countStyle: .file)) available of \(ByteCountFormatter.string(fromByteCount: s.total, countStyle: .file))")
                                .foregroundStyle(.secondary)
                        }.font(.system(size: 12.5)).monospacedDigit()
                    }
                    .padding(16).background(settings.cardColor, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.6)))
                }
                if let b = SystemInfo.battery {
                    card("Battery", [("Charge", "\(b.percent)%"), ("Power", b.state)])
                }
            }
            .padding(24)
        }
        .navigationTitle("System")
        .navigationSubtitle(SystemInfo.modelIdentifier)
    }

    private func card(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding(.bottom, 8)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                if i > 0 { Divider().opacity(0.5) }
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer(minLength: 16)
                    Text(row.1).multilineTextAlignment(.trailing).textSelection(.enabled)
                }
                .font(.system(size: 13)).padding(.vertical, 7)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(settings.cardColor, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.6)))
    }
}

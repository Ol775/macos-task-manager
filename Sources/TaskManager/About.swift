import SwiftUI

struct AboutView: View {
    @EnvironmentObject var updates: UpdateModel

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Task Manager").font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("Version \(AppInfo.version) (\(AppInfo.build))").foregroundStyle(.secondary)
            updateSection.padding(.top, 10)
            Link("GitHub", destination: URL(string: "https://github.com/\(Updater.repo)")!).padding(.top, 6)
            Text("© 2026 Ol775 · MIT License").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(28).frame(width: 340)
    }

    @ViewBuilder private var updateSection: some View {
        switch updates.status {
        case .idle:
            Button("Check for Updates") { updates.check() }
        case .checking:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
        case .upToDate:
            VStack(spacing: 6) {
                Label("You’re up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Check Again") { updates.check() }.controlSize(.small)
            }
        case .available(let info):
            VStack(spacing: 8) {
                Text("Version \(info.version) is available").fontWeight(.medium)
                if !info.notes.isEmpty {
                    Text(info.notes.prefix(4).joined(separator: "\n")).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("Update Now") { updates.install(info) }.buttonStyle(.borderedProminent)
            }
        case .installing(let msg, let f):
            VStack(spacing: 6) {
                ProgressView(value: f).frame(width: 220)
                Text(msg).font(.caption).foregroundStyle(.secondary)
            }
        case .failed(let msg):
            VStack(spacing: 6) {
                Text(msg).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("Try Again") { updates.check() }.controlSize(.small)
            }
        }
    }
}

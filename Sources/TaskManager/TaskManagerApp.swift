import SwiftUI

@main
struct TaskManagerApp: App {
    @StateObject private var monitor = Monitor()
    var body: some Scene {
        WindowGroup("Task Manager") {
            ContentView()
                .environmentObject(monitor)
                .onAppear { monitor.start() }
        }
        .defaultSize(width: 1000, height: 660)
    }
}

enum Page { case processes, performance }
enum Resource { case cpu, memory, gpu }

enum Palette {
    static let cpu = Color(red: 0.07, green: 0.49, blue: 0.73)
    static let memory = Color(red: 0.55, green: 0.07, blue: 0.68)
    static let gpu = Color(red: 0.00, green: 0.62, blue: 0.62)

    /// Windows-style usage heat: pale yellow to deep orange.
    static func heat(_ v: Double) -> Color {
        let v = min(max(v, 0), 1)
        return Color(red: 1, green: 0.80 - 0.42 * v, blue: 0.20 - 0.10 * v).opacity(0.10 + 0.60 * v)
    }
}

struct ContentView: View {
    @State private var page = Page.processes

    var body: some View {
        HStack(spacing: 0) {
            NavRail(page: $page)
            Divider()
            switch page {
            case .processes: ProcessesView()
            case .performance: PerformanceView()
            }
        }
        .frame(minWidth: 860, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct NavRail: View {
    @Binding var page: Page
    var body: some View {
        VStack(spacing: 4) {
            item(.processes, "list.bullet", "Processes")
            item(.performance, "chart.xyaxis.line", "Performance")
            Spacer()
        }
        .padding(.top, 10).padding(.horizontal, 6)
        .frame(width: 54)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func item(_ p: Page, _ icon: String, _ help: String) -> some View {
        Button { page = p } label: {
            Image(systemName: icon).font(.system(size: 16))
                .frame(width: 42, height: 40)
                .background(page == p ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .leading) {
                    if page == p {
                        Capsule().fill(Color.accentColor).frame(width: 3, height: 16).offset(x: -2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }
}

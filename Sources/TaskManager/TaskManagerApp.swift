import SwiftUI

@main
struct TaskManagerApp: App {
    @StateObject private var monitor = Monitor()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .onAppear { monitor.start() }
                .containerBackground(.regularMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 640)
    }
}

enum Section: Hashable { case processes, cpu, memory, gpu }

enum Palette {
    static let cpu = Color(red: 0.30, green: 0.58, blue: 1.00)
    static let memory = Color(red: 0.36, green: 0.82, blue: 0.62)
    static let gpu = Color(red: 1.00, green: 0.60, blue: 0.30)
}

struct ContentView: View {
    @State private var section = Section.processes

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(section: $section).frame(width: 232)
            Divider().opacity(0.4)
            Group {
                switch section {
                case .processes: ProcessesView()
                case .cpu: CPUDetail()
                case .memory: MemoryDetail()
                case .gpu: GPUDetail()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 540)
    }
}

// MARK: Sidebar

struct Sidebar: View {
    @EnvironmentObject var m: Monitor
    @Binding var section: Section

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Task Manager")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.leading, 12).padding(.top, 38).padding(.bottom, 8)
            row(.processes) {
                Label("Processes", systemImage: "list.bullet.rectangle").font(.system(size: 13, weight: .medium))
                    .padding(.vertical, 4)
            }
            Text("PERFORMANCE")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                .padding(.leading, 12).padding(.top, 14).padding(.bottom, 2)
            tile(.cpu, "CPU", Palette.cpu, m.cpuHistory)
            tile(.memory, "Memory", Palette.memory, m.memHistory)
            if m.gpuAvailable { tile(.gpu, "GPU", Palette.gpu, m.gpuHistory) }
            Spacer()
        }
        .padding(.horizontal, 10)
    }

    private func tile(_ s: Section, _ title: String, _ color: Color, _ data: [Double]) -> some View {
        row(s) {
            HStack(spacing: 10) {
                Sparkline(data: data, color: color).frame(width: 54, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(String(format: "%.0f%%", data.last ?? 0))
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func row<C: View>(_ s: Section, @ViewBuilder _ content: () -> C) -> some View {
        Button { section = s } label: {
            content().padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(section == s ? Color.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

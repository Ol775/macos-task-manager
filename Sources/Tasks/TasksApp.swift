import SwiftUI
import SwiftData

@Model
final class TaskItem {
    var title: String
    var isDone = false
    var created = Date()
    init(title: String) { self.title = title }
}

@main
struct TasksApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(for: TaskItem.self)
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 420, height: 560)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.created) private var tasks: [TaskItem]
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tasks").font(.system(size: 28, weight: .semibold, design: .rounded))
            TextField("Add a task", text: $draft)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .onSubmit(add)
            List {
                ForEach(tasks) { task in
                    @Bindable var task = task
                    HStack(spacing: 10) {
                        Toggle("", isOn: $task.isDone).toggleStyle(.checkbox).labelsHidden()
                        Text(task.title)
                            .strikethrough(task.isDone)
                            .foregroundStyle(task.isDone ? .secondary : .primary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { $0.map { tasks[$0] }.forEach(context.delete) }
            }
            .scrollContentBackground(.hidden)
            .overlay { if tasks.isEmpty { Text("Nothing to do").foregroundStyle(.tertiary) } }
        }
        .padding(20)
        .frame(minWidth: 320, minHeight: 360)
        .background(.regularMaterial)
    }

    private func add() {
        let title = draft.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        context.insert(TaskItem(title: title))
        draft = ""
    }
}

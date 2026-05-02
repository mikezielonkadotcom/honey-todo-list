import SwiftUI
import AppKit

struct TasksView: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 460, minHeight: 520)
        .background(VisualEffectBackground())
    }

    private var orderedEnabledTabs: [TaskTab] {
        TaskTab.allCases.filter { store.enabledTabs.contains($0) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if orderedEnabledTabs.count > 1 {
                Picker("", selection: $store.selectedTab) {
                    ForEach(orderedEnabledTabs) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
            } else if let only = orderedEnabledTabs.first {
                Text(only.title)
                    .font(.headline)
            }
            Spacer()
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            .disabled(store.loading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        let tasks = currentTasks
        if let err = store.lastError {
            errorState(err)
        } else if tasks.isEmpty && !store.loading {
            emptyState
        } else {
            List {
                ForEach(tasks) { t in
                    TaskRow(
                        task: t,
                        isCompleting: store.completingIds.contains(t.id),
                        onComplete: { store.complete(t) }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .animation(.easeInOut(duration: 0.25), value: tasks.map(\.id))
            .animation(.easeInOut(duration: 0.25), value: store.completingIds)
        }
    }

    private var currentTasks: [ClickUpTask] {
        switch store.selectedTab {
        case .today: return store.todayTasks
        case .tomorrow: return store.tomorrowTasks
        case .all: return store.allTasks
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(store.loading ? "Loading…" : "Nothing due")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Button("Open Preferences") {
                globalStatusBarController?.openPreferencesFromMenu()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if store.loading {
                ProgressView().controlSize(.small)
                Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
            } else if let r = store.lastRefreshed {
                Text("Updated \(Self.relativeFormatter.localizedString(for: r, relativeTo: Date()))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(currentTasks.count) task\(currentTasks.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}

struct TaskRow: View {
    let task: ClickUpTask
    let isCompleting: Bool
    let onComplete: () -> Void
    @State private var hovering = false

    private var isChecked: Bool { isCompleting || isDone }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: { if !isCompleting { onComplete() } }) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                    .symbolEffect(.bounce, value: isCompleting)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(isCompleting)
            .help("Mark complete")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .font(.system(size: 13))
                    .strikethrough(isChecked)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let due = task.dueDate {
                        Text(Self.dueLabel(due))
                            .font(.caption)
                            .foregroundStyle(isOverdue ? .red : .secondary)
                    }
                    if let list = task.listName {
                        Text("·").foregroundStyle(.tertiary).font(.caption)
                        Text(list).font(.caption).foregroundStyle(.secondary)
                    }
                    if let p = task.priority, p <= 2 {
                        Text("·").foregroundStyle(.tertiary).font(.caption)
                        Text(priorityLabel(p))
                            .font(.caption)
                            .foregroundStyle(p == 1 ? .red : .orange)
                    }
                }
            }
            Spacer(minLength: 0)
            if hovering {
                Button {
                    if let url = URL(string: task.url) { NSWorkspace.shared.open(url) }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open in ClickUp")
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .opacity(isCompleting ? 0.45 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isCompleting)
        .onTapGesture(count: 2) {
            if let url = URL(string: task.url) { NSWorkspace.shared.open(url) }
        }
    }

    private var isDone: Bool { task.status.lowercased().contains("complete") || task.status.lowercased() == "closed" }
    private var isOverdue: Bool {
        guard let d = task.dueDate else { return false }
        return d < Date()
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    private static func dueLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today \(timeFormatter.string(from: date))" }
        if cal.isDateInTomorrow(date) { return "Tomorrow \(timeFormatter.string(from: date))" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return dayFormatter.string(from: date)
    }

    private func priorityLabel(_ p: Int) -> String {
        switch p {
        case 1: return "Urgent"
        case 2: return "High"
        case 3: return "Normal"
        case 4: return "Low"
        default: return "P\(p)"
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

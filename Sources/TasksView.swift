import SwiftUI
import AppKit

struct TasksView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .frame(minWidth: 480, minHeight: 540)
        .background(VisualEffectBackground())
        .tint(.honey)
    }

    private var orderedEnabledTabs: [TaskTab] {
        TaskTab.allCases.filter { store.enabledTabs.contains($0) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerTitle)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(headerSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                refreshButton
            }
            if orderedEnabledTabs.count > 1 {
                PillTabBar(tabs: orderedEnabledTabs, selection: $store.selectedTab)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 38)
        .padding(.bottom, 10)
    }

    private var headerTitle: String {
        switch store.selectedTab {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .all: return "All Due"
        }
    }

    private var headerSubtitle: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        switch store.selectedTab {
        case .today: return f.string(from: Date())
        case .tomorrow:
            let tmr = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            return f.string(from: tmr)
        case .all:
            return "\(store.allTasks.count) task\(store.allTasks.count == 1 ? "" : "s") with a due date"
        }
    }

    private var refreshButton: some View {
        Button {
            store.refresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(7)
                .background(
                    Circle().fill(Color.primary.opacity(0.06))
                )
                .rotationEffect(.degrees(store.loading ? 360 : 0))
                .animation(store.loading ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: store.loading)
        }
        .buttonStyle(.plain)
        .help("Refresh")
        .disabled(store.loading)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let tasks = currentTasks
        if let err = store.lastError {
            errorState(err)
        } else if tasks.isEmpty && !store.loading {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(tasks) { t in
                        TaskRow(
                            task: t,
                            isCompleting: store.completingIds.contains(t.id),
                            onComplete: { store.complete(t) },
                            onReschedule: { date, hasTime in store.reschedule(t, to: date, hasTime: hasTime) }
                        )
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .offset(x: -20))
                        ))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .animation(.easeInOut(duration: 0.25), value: tasks.map(\.id))
                .animation(.easeInOut(duration: 0.25), value: store.completingIds)
            }
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
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.honey.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: store.loading ? "hourglass" : "checkmark")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.honey)
            }
            Text(store.loading ? "Loading…" : "All clear")
                .font(.system(size: 16, weight: .semibold))
            if !store.loading {
                Text("Nothing due. Go enjoy your day.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
            Button("Open Preferences") {
                globalStatusBarController?.openPreferencesFromMenu()
            }
            .buttonStyle(.borderedProminent)
            .tint(.honey)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if store.loading {
                ProgressView().controlSize(.small)
                Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
            } else if let r = store.lastRefreshed {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Updated \(Self.relativeFormatter.localizedString(for: r, relativeTo: Date()))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(currentTasks.count) task\(currentTasks.count == 1 ? "" : "s")")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}

// MARK: - Pill Tab Bar

struct PillTabBar: View {
    let tabs: [TaskTab]
    @Binding var selection: TaskTab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selection = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .foregroundStyle(selection == tab ? Color.white : Color.primary.opacity(0.75))
                        .background(
                            ZStack {
                                if selection == tab {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.honey)
                                        .matchedGeometryEffect(id: "pill", in: ns)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

// MARK: - Task Row

struct TaskRow: View {
    let task: ClickUpTask
    let isCompleting: Bool
    let onComplete: () -> Void
    let onReschedule: (Date?, Bool) -> Void
    @State private var hovering = false
    @State private var showingReschedule = false

    private var isChecked: Bool { isCompleting || isDone }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: { if !isCompleting { onComplete() } }) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(isChecked ? Color.honey : Color.secondary.opacity(0.55))
                    .symbolEffect(.bounce, value: isCompleting)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(isCompleting)
            .help("Mark complete")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.name)
                    .font(.system(size: 13.5, weight: .medium))
                    .strikethrough(isChecked)
                    .lineLimit(2)
                    .foregroundStyle(isChecked ? Color.secondary : Color.primary)
                HStack(spacing: 6) {
                    if let due = task.dueDate {
                        Label {
                            Text(Self.dueLabel(due))
                        } icon: {
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                        }
                        .labelStyle(InlineLabelStyle())
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(isOverdue ? Color.red : Color.honeyDark)
                    }
                    if let list = task.listName {
                        Text("·").foregroundStyle(.tertiary).font(.caption)
                        Text(list)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let p = task.priority, p <= 2 {
                        priorityChip(p)
                    }
                }
            }
            Spacer(minLength: 0)
            if hovering && !isCompleting {
                HStack(spacing: 8) {
                    Button {
                        showingReschedule = true
                    } label: {
                        Image(systemName: "calendar")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reschedule")
                    .popover(isPresented: $showingReschedule, arrowEdge: .trailing) {
                        ReschedulePopover(currentDate: task.dueDate) { date, hasTime in
                            onReschedule(date, hasTime)
                            showingReschedule = false
                        } onClear: {
                            onReschedule(nil, false)
                            showingReschedule = false
                        }
                    }

                    Button {
                        if let url = URL(string: task.url) { NSWorkspace.shared.open(url) }
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open in ClickUp")
                }
                .transition(.opacity)
            }
        }
        .contextMenu {
            Button("Mark Complete") { onComplete() }
            Divider()
            Section("Reschedule") {
                Button("Today (end of day)") { onReschedule(Self.endOfToday(), true) }
                Button("Tomorrow morning") { onReschedule(Self.tomorrowMorning(), true) }
                Button("This Weekend") { onReschedule(Self.thisWeekend(), true) }
                Button("Next Week") { onReschedule(Self.nextWeekMonday(), true) }
                Divider()
                Button("Pick Date…") { showingReschedule = true }
                if task.dueDate != nil {
                    Divider()
                    Button("Clear Due Date") { onReschedule(nil, false) }
                }
            }
            Divider()
            Button("Open in ClickUp") {
                if let url = URL(string: task.url) { NSWorkspace.shared.open(url) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .opacity(isCompleting ? 0.42 : 1.0)
        .animation(.easeInOut(duration: 0.18), value: hovering)
        .animation(.easeInOut(duration: 0.2), value: isCompleting)
        .onTapGesture(count: 2) {
            if let url = URL(string: task.url) { NSWorkspace.shared.open(url) }
        }
    }

    private func priorityChip(_ p: Int) -> some View {
        let label = p == 1 ? "Urgent" : "High"
        let color: Color = p == 1 ? .red : .orange
        return HStack(spacing: 3) {
            Image(systemName: "flag.fill").font(.system(size: 8))
            Text(label).font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.opacity(0.12))
        )
    }

    private var isDone: Bool {
        let s = task.status.lowercased()
        return s.contains("complete") || s == "closed" || s == "done" || s == "resolved"
    }
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

    static func endOfToday() -> Date {
        Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    }
    static func tomorrowMorning() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
    static func thisWeekend() -> Date {
        let cal = Calendar.current
        var d = Date()
        for _ in 0..<8 {
            if cal.component(.weekday, from: d) == 7 { break } // Saturday
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
    }
    static func nextWeekMonday() -> Date {
        let cal = Calendar.current
        var d = Date()
        for _ in 0..<8 {
            d = cal.date(byAdding: .day, value: 1, to: d)!
            if cal.component(.weekday, from: d) == 2 { break } // Monday
        }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
    }

    private static func dueLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today \(timeFormatter.string(from: date))" }
        if cal.isDateInTomorrow(date) { return "Tomorrow \(timeFormatter.string(from: date))" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return dayFormatter.string(from: date)
    }
}

// MARK: - Reschedule Popover

struct ReschedulePopover: View {
    let currentDate: Date?
    let onPick: (Date, Bool) -> Void
    let onClear: () -> Void

    @State private var date: Date
    @State private var includeTime: Bool

    init(currentDate: Date?, onPick: @escaping (Date, Bool) -> Void, onClear: @escaping () -> Void) {
        self.currentDate = currentDate
        self.onPick = onPick
        self.onClear = onClear
        _date = State(initialValue: currentDate ?? TaskRow.tomorrowMorning())
        _includeTime = State(initialValue: currentDate != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reschedule")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.top, 12)

            VStack(spacing: 4) {
                quickRow("Today", icon: "sun.max", date: TaskRow.endOfToday())
                quickRow("Tomorrow", icon: "sunrise", date: TaskRow.tomorrowMorning())
                quickRow("This Weekend", icon: "beach.umbrella", date: TaskRow.thisWeekend())
                quickRow("Next Week", icon: "calendar.badge.clock", date: TaskRow.nextWeekMonday())
            }
            .padding(.horizontal, 8)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Pick a date")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                DatePicker(
                    "",
                    selection: $date,
                    displayedComponents: includeTime ? [.date, .hourAndMinute] : [.date]
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                Toggle("Include time", isOn: $includeTime)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 14)

            HStack {
                if currentDate != nil {
                    Button("Clear", role: .destructive) { onClear() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Set") { onPick(date, includeTime) }
                    .buttonStyle(.borderedProminent)
                    .tint(.honey)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 280)
    }

    private func quickRow(_ title: String, icon: String, date: Date) -> some View {
        Button {
            onPick(date, true)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.honey)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12.5))
                Spacer()
                Text(Self.formatter.string(from: date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.clear)
        )
        .onHover { _ in } // kicks SwiftUI to allow hover styling via the button
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f
    }()
}

private struct InlineLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
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

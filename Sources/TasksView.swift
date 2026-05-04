import SwiftUI
import AppKit

struct TasksView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            ZStack(alignment: .bottom) {
                content
                if let banner = store.undoBanner {
                    UndoToast(banner: banner,
                              onUndo: { store.reopen(banner.task) },
                              onDismiss: { store.dismissUndo() })
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.undoBanner)
            Divider().opacity(0.4)
            footer
        }
        .frame(minWidth: 480, minHeight: 540)
        .background(
            ZStack {
                VisualEffectBackground()
                Color.appBackground.opacity(0.88)
            }
            .ignoresSafeArea()
        )
        .tint(.honey)
    }

    private var orderedEnabledTabs: [TaskTab] {
        TaskTab.allCases.filter { store.enabledTabs.contains($0) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(headerTitle)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(headerSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                showCompletedToggle
                refreshButton
                preferencesButton
            }
            if orderedEnabledTabs.count > 1 {
                PillTabBar(tabs: orderedEnabledTabs, selection: $store.selectedTab)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 44)
        .padding(.bottom, 14)
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

    private var preferencesButton: some View {
        Button {
            globalStatusBarController?.openPreferencesFromMenu()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(7)
                .background(Circle().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help("Preferences (⌘,)")
        .keyboardShortcut(",", modifiers: .command)
    }

    private var showCompletedToggle: some View {
        Button {
            store.showCompleted.toggle()
        } label: {
            Image(systemName: store.showCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(store.showCompleted ? Color.honey : Color.secondary)
                .padding(7)
                .background(
                    Circle().fill(store.showCompleted ? Color.honey.opacity(0.15) : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .help(store.showCompleted ? "Hide completed" : "Show completed")
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
        let completed = currentCompletedTasks
        if let err = store.lastError {
            errorState(err)
        } else if tasks.isEmpty && completed.isEmpty && !store.loading {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
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

                    if store.showCompleted && !completed.isEmpty {
                        completedSectionHeader(count: completed.count)
                        ForEach(completed) { t in
                            CompletedTaskRow(
                                task: t,
                                isReopening: store.completingIds.contains(t.id),
                                onReopen: { store.reopen(t) }
                            )
                            .transition(.opacity)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(.easeInOut(duration: 0.25), value: tasks.map(\.id))
                .animation(.easeInOut(duration: 0.25), value: completed.map(\.id))
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

    private var currentCompletedTasks: [ClickUpTask] {
        switch store.selectedTab {
        case .today: return store.completedTodayTasks
        case .tomorrow: return store.completedTomorrowTasks
        case .all: return store.completedAllTasks
        }
    }

    private func completedSectionHeader(count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("Completed")
                .font(.system(size: 11, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 4)
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

    // Only show the checked/strikethrough state for tasks the user just completed.
    // The server already excludes closed tasks via include_closed=false; status name
    // strings (e.g. "Done", "Resolved") in custom statuses do NOT mean done.
    private var isChecked: Bool { isCompleting }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left accent stripe colored by list
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.forList(task.listName))
                .frame(width: 3)
                .padding(.vertical, 4)

            HStack(alignment: .top, spacing: 13) {
                Button(action: { if !isCompleting { onComplete() } }) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21))
                        .foregroundStyle(isChecked ? Color.honey : Color.secondary.opacity(0.45))
                        .symbolEffect(.bounce, value: isCompleting)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .disabled(isCompleting)
                .help("Mark complete")
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text(task.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .strikethrough(isChecked)
                        .lineLimit(2)
                        .foregroundStyle(isChecked ? Color.secondary : Color.primary)
                    HStack(spacing: 7) {
                        if let due = task.dueDate {
                            duePill(due)
                        }
                        if let list = task.listName {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.forList(list))
                                    .frame(width: 6, height: 6)
                                Text(list)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if let p = task.priority, p <= 2 {
                            priorityChip(p)
                        }
                    }
                }
                Spacer(minLength: 0)
                if (hovering || showingReschedule) && !isCompleting {
                    HStack(spacing: 10) {
                        Button {
                            showingReschedule = true
                        } label: {
                            Image(systemName: "calendar")
                                .font(.system(size: 14))
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
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Open in ClickUp")
                    }
                    .padding(.top, 2)
                    .transition(.opacity)
                }
            }
            .padding(.leading, 13)
            .padding(.trailing, 14)
            .padding(.vertical, 13)
        }
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hovering ? Color.cardHover : Color.cardBackground)
                .shadow(color: .black.opacity(hovering ? 0.06 : 0.04), radius: hovering ? 6 : 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
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
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .opacity(isCompleting ? 0.42 : 1.0)
        .animation(.easeInOut(duration: 0.18), value: hovering)
        .animation(.easeInOut(duration: 0.2), value: isCompleting)
        .onTapGesture(count: 2) {
            if let url = URL(string: task.url) { NSWorkspace.shared.open(url) }
        }
    }

    private func duePill(_ due: Date) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 9, weight: .semibold))
            Text(Self.dueLabel(due))
                .font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(isOverdue ? Color.overdueFg : Color.honeyDark)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isOverdue ? Color.overdueBg : Color.honey.opacity(0.13))
        )
    }

    private func priorityChip(_ p: Int) -> some View {
        let label = p == 1 ? "Urgent" : "High"
        let color: Color = p == 1 ? Color(red: 0.85, green: 0.30, blue: 0.30) : Color(red: 0.93, green: 0.55, blue: 0.20)
        return HStack(spacing: 3) {
            Image(systemName: "flag.fill").font(.system(size: 9))
            Text(label).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color.opacity(0.13))
        )
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

// MARK: - Completed Task Row

struct CompletedTaskRow: View {
    let task: ClickUpTask
    let isReopening: Bool
    let onReopen: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.forList(task.listName).opacity(0.45))
                .frame(width: 3)
                .padding(.vertical, 4)

            HStack(alignment: .top, spacing: 13) {
                Button(action: { if !isReopening { onReopen() } }) {
                    Image(systemName: hovering ? "arrow.uturn.left.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 21))
                        .foregroundStyle(hovering ? Color.honeyDark : Color.honey.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .disabled(isReopening)
                .help("Reopen task")
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 5) {
                    Text(task.name)
                        .font(.system(size: 14, weight: .medium))
                        .strikethrough()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 7) {
                        if let closed = task.dateClosed {
                            Text("Done \(Self.relativeFormatter.localizedString(for: closed, relativeTo: Date()))")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        if let list = task.listName {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.forList(list).opacity(0.55))
                                    .frame(width: 5, height: 5)
                                Text(list)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                if hovering && !isReopening {
                    Button {
                        if let url = URL(string: task.url) { NSWorkspace.shared.open(url) }
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Open in ClickUp")
                    .transition(.opacity)
                }
            }
            .padding(.leading, 13)
            .padding(.trailing, 14)
            .padding(.vertical, 11)
        }
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.cardBackground.opacity(0.6))
        )
        .opacity(isReopening ? 0.42 : 1.0)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.18), value: hovering)
        .animation(.easeInOut(duration: 0.2), value: isReopening)
        .contextMenu {
            Button("Reopen") { onReopen() }
            Button("Open in ClickUp") {
                if let url = URL(string: task.url) { NSWorkspace.shared.open(url) }
            }
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

// MARK: - Undo Toast

struct UndoToast: View {
    let banner: UndoBanner
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.honey)
                .font(.system(size: 14))
            Text("Marked complete")
                .font(.system(size: 12.5, weight: .medium))
            Text(banner.task.name)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)
            Spacer(minLength: 8)
            Button("Undo") { onUndo() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.honey)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 16)
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

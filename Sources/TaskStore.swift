import Foundation
import SwiftUI

enum TaskTab: String, CaseIterable, Identifiable {
    case today, tomorrow, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .all: return "All Due"
        }
    }
    var defaultsKey: String { "tab.\(rawValue).enabled" }
}

@MainActor
final class TaskStore: ObservableObject {
    @Published var todayTasks: [ClickUpTask] = []
    @Published var tomorrowTasks: [ClickUpTask] = []
    @Published var allTasks: [ClickUpTask] = []
    @Published var completedTodayTasks: [ClickUpTask] = []
    @Published var completedTomorrowTasks: [ClickUpTask] = []
    @Published var completedAllTasks: [ClickUpTask] = []
    @Published var loading: Bool = false
    @Published var lastError: String? = nil
    @Published var lastRefreshed: Date? = nil

    @Published var enabledTabs: Set<TaskTab> = TaskStore.loadEnabledTabs()
    @Published var selectedTab: TaskTab = .today
    @Published var completingIds: Set<String> = []
    @Published var showCompleted: Bool = UserDefaults.standard.bool(forKey: "showCompleted") {
        didSet {
            UserDefaults.standard.set(showCompleted, forKey: "showCompleted")
            refresh()
        }
    }
    @Published var undoBanner: UndoBanner? = nil
    private var undoClearTask: Task<Void, Never>? = nil

    static func loadEnabledTabs() -> Set<TaskTab> {
        var s: Set<TaskTab> = []
        for t in TaskTab.allCases {
            if UserDefaults.standard.object(forKey: t.defaultsKey) == nil {
                UserDefaults.standard.set(true, forKey: t.defaultsKey)
            }
            if UserDefaults.standard.bool(forKey: t.defaultsKey) { s.insert(t) }
        }
        if s.isEmpty { s.insert(.today) }
        return s
    }

    func setTabEnabled(_ tab: TaskTab, _ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: tab.defaultsKey)
        if enabled { enabledTabs.insert(tab) } else { enabledTabs.remove(tab) }
        if enabledTabs.isEmpty {
            enabledTabs.insert(.today)
            UserDefaults.standard.set(true, forKey: TaskTab.today.defaultsKey)
        }
        if !enabledTabs.contains(selectedTab) {
            selectedTab = enabledTabs.sorted(by: { $0.rawValue < $1.rawValue }).first ?? .today
        }
    }

    func refresh() {
        Task { await self.refreshAsync() }
    }

    func refreshAsync() async {
        loading = true
        lastError = nil
        defer { loading = false }
        do {
            let cal = Calendar.current
            let startOfToday = cal.startOfDay(for: Date())
            let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: Date())!
            let endOfTomorrow = cal.date(byAdding: .day, value: 1, to: endOfToday)!
            let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: startOfToday)!

            let all = try await ClickUpAPI.shared.tasks(dueBefore: nil, includeNoDueDate: false)
            let today = all.filter { ($0.dueDate ?? .distantFuture) <= endOfToday }
            let tomorrow = all.filter { ($0.dueDate ?? .distantFuture) <= endOfTomorrow }

            self.allTasks = all.sorted(by: Self.sortTasks)
            self.todayTasks = today.sorted(by: Self.sortTasks)
            self.tomorrowTasks = tomorrow.sorted(by: Self.sortTasks)

            if showCompleted {
                let done = try await ClickUpAPI.shared.completedTasks(doneAfter: sevenDaysAgo)
                let sortedByClosed = done.sorted { ($0.dateClosed ?? .distantPast) > ($1.dateClosed ?? .distantPast) }
                self.completedTodayTasks = sortedByClosed.filter { ($0.dateClosed ?? .distantPast) >= startOfToday }
                self.completedTomorrowTasks = self.completedTodayTasks  // same window
                self.completedAllTasks = sortedByClosed
            } else {
                self.completedTodayTasks = []
                self.completedTomorrowTasks = []
                self.completedAllTasks = []
            }

            self.lastRefreshed = Date()
        } catch {
            self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    static func sortTasks(_ a: ClickUpTask, _ b: ClickUpTask) -> Bool {
        let ad = a.dueDate ?? .distantFuture
        let bd = b.dueDate ?? .distantFuture
        if ad != bd { return ad < bd }
        let ap = a.priority ?? 5
        let bp = b.priority ?? 5
        if ap != bp { return ap < bp }
        return a.name < b.name
    }

    func reschedule(_ task: ClickUpTask, to newDate: Date?, hasTime: Bool = true) {
        guard !completingIds.contains(task.id) else { return }
        completingIds.insert(task.id)
        Task {
            do {
                try await ClickUpAPI.shared.setDueDate(taskId: task.id, dueDate: newDate, hasTime: hasTime)
                try? await Task.sleep(nanoseconds: 250_000_000)
                await self.refreshAsync()
            } catch {
                self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self.completingIds.remove(task.id)
        }
    }

    func complete(_ task: ClickUpTask) {
        guard !completingIds.contains(task.id) else { return }
        completingIds.insert(task.id)
        Task {
            do {
                try await ClickUpAPI.shared.completeTask(task)
                try? await Task.sleep(nanoseconds: 350_000_000)
                await self.refreshAsync()
                self.showUndoBanner(for: task, action: .completed)
            } catch {
                self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self.completingIds.remove(task.id)
        }
    }

    func reopen(_ task: ClickUpTask) {
        guard !completingIds.contains(task.id) else { return }
        completingIds.insert(task.id)
        Task {
            do {
                try await ClickUpAPI.shared.reopenTask(task)
                try? await Task.sleep(nanoseconds: 250_000_000)
                await self.refreshAsync()
            } catch {
                self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self.completingIds.remove(task.id)
            self.undoBanner = nil
        }
    }

    private func showUndoBanner(for task: ClickUpTask, action: UndoBanner.Action) {
        undoClearTask?.cancel()
        undoBanner = UndoBanner(task: task, action: action)
        undoClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            await MainActor.run {
                if self?.undoBanner?.task.id == task.id {
                    self?.undoBanner = nil
                }
            }
        }
    }

    func dismissUndo() {
        undoClearTask?.cancel()
        undoBanner = nil
    }
}

struct UndoBanner: Equatable {
    enum Action { case completed }
    let task: ClickUpTask
    let action: Action
}

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
    @Published var loading: Bool = false
    @Published var lastError: String? = nil
    @Published var lastRefreshed: Date? = nil

    @Published var enabledTabs: Set<TaskTab> = TaskStore.loadEnabledTabs()
    @Published var selectedTab: TaskTab = .today
    @Published var completingIds: Set<String> = []

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
            let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: Date())!
            let endOfTomorrow = cal.date(byAdding: .day, value: 1, to: endOfToday)!

            async let allFuture = ClickUpAPI.shared.tasks(dueBefore: nil, includeNoDueDate: false)
            let all = try await allFuture
            let today = all.filter { ($0.dueDate ?? .distantFuture) <= endOfToday }
            let tomorrow = all.filter { ($0.dueDate ?? .distantFuture) <= endOfTomorrow }

            self.allTasks = all.sorted(by: Self.sortTasks)
            self.todayTasks = today.sorted(by: Self.sortTasks)
            self.tomorrowTasks = tomorrow.sorted(by: Self.sortTasks)
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
                // Hold the checked-and-faded state briefly so the user sees it land.
                try? await Task.sleep(nanoseconds: 350_000_000)
                await self.refreshAsync()
            } catch {
                self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self.completingIds.remove(task.id)
        }
    }
}

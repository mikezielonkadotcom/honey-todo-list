import Foundation

struct ClickUpTask: Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let url: String
    let dueDate: Date?
    let priority: Int?
    let listId: String?
    let listName: String?
    let folderName: String?
}

enum ClickUpError: Error, LocalizedError {
    case missingToken
    case http(Int, String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .missingToken: return "No ClickUp API token configured. Open Preferences and add one."
        case .http(let code, let msg): return "ClickUp API error \(code): \(msg)"
        case .decode(let msg): return "Failed to parse ClickUp response: \(msg)"
        }
    }
}

actor ClickUpAPI {
    static let shared = ClickUpAPI()
    private let base = URL(string: "https://api.clickup.com/api/v2")!

    private func request(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        guard let token = KeychainStore.shared.token else { throw ClickUpError.missingToken }
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ClickUpError.http(0, "no response") }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClickUpError.http(http.statusCode, body)
        }
        return data
    }

    func currentUserId() async throws -> String {
        let data = try await request("user")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = json["user"] as? [String: Any],
              let id = user["id"] else { throw ClickUpError.decode("user payload") }
        return "\(id)"
    }

    func teamIds() async throws -> [String] {
        let data = try await request("team")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let teams = json["teams"] as? [[String: Any]] else { throw ClickUpError.decode("teams payload") }
        return teams.compactMap { $0["id"] as? String ?? ($0["id"]).map { "\($0)" } }
    }

    /// Fetch tasks assigned to the user across all workspaces, due strictly before `dueBefore`.
    /// Pass nil for no upper bound (returns all open assigned tasks with a due date).
    func tasks(dueBefore: Date?, includeNoDueDate: Bool = false) async throws -> [ClickUpTask] {
        let userId = try await currentUserId()
        let teams = try await teamIds()
        var all: [ClickUpTask] = []
        for team in teams {
            var page = 0
            while true {
                var q: [URLQueryItem] = [
                    URLQueryItem(name: "page", value: "\(page)"),
                    URLQueryItem(name: "assignees[]", value: userId),
                    URLQueryItem(name: "subtasks", value: "true"),
                    URLQueryItem(name: "include_closed", value: "false"),
                    URLQueryItem(name: "order_by", value: "due_date"),
                    URLQueryItem(name: "reverse", value: "false")
                ]
                if let due = dueBefore {
                    let ms = Int64(due.timeIntervalSince1970 * 1000)
                    q.append(URLQueryItem(name: "due_date_lt", value: "\(ms)"))
                }
                let data = try await request("team/\(team)/task", query: q)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tasks = json["tasks"] as? [[String: Any]] else { break }
                let parsed = tasks.compactMap { parseTask($0, includeNoDueDate: includeNoDueDate, requireAssignee: userId) }
                all.append(contentsOf: parsed)
                if tasks.count < 100 { break }
                page += 1
                if page > 20 { break }
            }
        }
        // De-dupe by id (in case of multi-team overlap).
        var seen = Set<String>()
        return all.filter { seen.insert($0.id).inserted }
    }

    private func parseTask(_ d: [String: Any], includeNoDueDate: Bool, requireAssignee: String) -> ClickUpTask? {
        guard let id = d["id"] as? String,
              let name = d["name"] as? String else { return nil }
        // Strict: drop tasks not assigned to the current user (subtasks=true can leak in others).
        let assignees = d["assignees"] as? [[String: Any]] ?? []
        let assigneeIds: [String] = assignees.compactMap {
            if let s = $0["id"] as? String { return s }
            if let n = $0["id"] as? Int { return "\(n)" }
            return nil
        }
        guard assigneeIds.contains(requireAssignee) else { return nil }
        let status = (d["status"] as? [String: Any])?["status"] as? String ?? "open"
        let url = d["url"] as? String ?? ""
        var due: Date? = nil
        if let dueStr = d["due_date"] as? String, let ms = Int64(dueStr) {
            due = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        }
        if !includeNoDueDate && due == nil { return nil }
        let priority = (d["priority"] as? [String: Any]).flatMap { p -> Int? in
            if let s = p["priority"] as? String, let n = Int(s) { return n }
            if let n = p["priority"] as? Int { return n }
            return nil
        }
        let listObj = d["list"] as? [String: Any]
        let listId = listObj?["id"] as? String ?? (listObj?["id"] as? Int).map { "\($0)" }
        let listName = listObj?["name"] as? String
        let folderName = (d["folder"] as? [String: Any])?["name"] as? String
        return ClickUpTask(id: id, name: name, status: status, url: url, dueDate: due, priority: priority, listId: listId, listName: listName, folderName: folderName)
    }

    private var closedStatusCache: [String: String] = [:]

    /// Resolve the "closed"-type status name for a given ClickUp list.
    /// Each list defines its own status set ("Complete", "Done", "Resolved", etc.) — pick the one whose type is "closed", falling back to "done".
    func closedStatusName(forListId listId: String) async throws -> String {
        if let cached = closedStatusCache[listId] { return cached }
        let data = try await request("list/\(listId)")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statuses = json["statuses"] as? [[String: Any]] else {
            throw ClickUpError.decode("list payload")
        }
        let closed = statuses.first { ($0["type"] as? String) == "closed" }
        let done = statuses.first { ($0["type"] as? String) == "done" }
        guard let pick = (closed ?? done ?? statuses.last)?["status"] as? String else {
            throw ClickUpError.decode("no closed/done status on list")
        }
        closedStatusCache[listId] = pick
        return pick
    }

    func completeTask(_ task: ClickUpTask) async throws {
        guard let listId = task.listId else {
            throw ClickUpError.decode("task missing list id")
        }
        let name = try await closedStatusName(forListId: listId)
        try await setStatus(taskId: task.id, status: name)
    }

    /// Update a task's due date. Pass nil to clear it. `hasTime` controls whether the time component is shown in ClickUp.
    func setDueDate(taskId: String, dueDate: Date?, hasTime: Bool) async throws {
        guard let token = KeychainStore.shared.token else { throw ClickUpError.missingToken }
        var req = URLRequest(url: base.appendingPathComponent("task/\(taskId)"))
        req.httpMethod = "PUT"
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [:]
        if let d = dueDate {
            body["due_date"] = Int64(d.timeIntervalSince1970 * 1000)
            body["due_date_time"] = hasTime
        } else {
            body["due_date"] = NSNull()
            body["due_date_time"] = false
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw ClickUpError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func setStatus(taskId: String, status: String) async throws {
        guard let token = KeychainStore.shared.token else { throw ClickUpError.missingToken }
        var req = URLRequest(url: base.appendingPathComponent("task/\(taskId)"))
        req.httpMethod = "PUT"
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["status": status])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw ClickUpError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
    }
}

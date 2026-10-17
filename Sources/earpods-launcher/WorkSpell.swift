import EarPodsCore
import CoreGraphics
import Foundation

enum WorkSpellBindingKey: String, Codable {
    case addTask = "add_task"
    case completeTask = "complete_task"

    var title: String {
        switch self {
        case .addTask:
            return "Add Gesture"
        case .completeTask:
            return "Done Gesture"
        }
    }

    var helperDetail: String {
        switch self {
        case .addTask:
            return "Focus the task field so you can append a new task."
        case .completeTask:
            return "Mark the selected task as done."
        }
    }
}

enum WorkSpellMode: String, Codable {
    case ordered
    case unordered

    var title: String {
        switch self {
        case .ordered:
            return "Ordered"
        case .unordered:
            return "Unordered"
        }
    }

    var helperDetail: String {
        switch self {
        case .ordered:
            return "Tasks can lock each other with branches and prerequisites."
        case .unordered:
            return "Tasks stay unlocked even if they are grouped visually."
        }
    }
}

enum WorkSpellBranchRole: String, Codable {
    case prerequisite
    case successor
}

struct WorkSpellTask: Codable, Hashable {
    let id: String
    let title: String
    let createdAt: Date
    var completedAt: Date?
    var prerequisiteTaskIDs: [String]
    var parentTaskID: String?
    var branchRole: WorkSpellBranchRole?

    init(
        id: String,
        title: String,
        createdAt: Date,
        completedAt: Date?,
        prerequisiteTaskIDs: [String] = [],
        parentTaskID: String? = nil,
        branchRole: WorkSpellBranchRole? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.prerequisiteTaskIDs = prerequisiteTaskIDs
        self.parentTaskID = parentTaskID
        self.branchRole = branchRole
    }

    var isCompleted: Bool {
        completedAt != nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case completedAt
        case prerequisiteTaskIDs
        case parentTaskID
        case branchRole
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        prerequisiteTaskIDs = try container.decodeIfPresent([String].self, forKey: .prerequisiteTaskIDs) ?? []
        parentTaskID = try container.decodeIfPresent(String.self, forKey: .parentTaskID)
        branchRole = try container.decodeIfPresent(WorkSpellBranchRole.self, forKey: .branchRole)
    }
}

enum WorkSpellRowKind: Equatable {
    case task(String)
    case newTask
    case shapeByVoice
    case openLauncher
    case deactivateSpell
}

enum WorkSpellRowStyle {
    case focus
    case task
    case blocked
    case utility
    case empty
}

struct WorkSpellRow {
    let kind: WorkSpellRowKind
    let eyebrow: String?
    let title: String
    let detail: String
    let symbol: String
    let isEnabled: Bool
    let style: WorkSpellRowStyle
    let indentLevel: Int

    var minimumHeight: CGFloat {
        switch style {
        case .focus:
            return 78
        case .task, .blocked:
            return 62
        case .utility:
            return 54
        case .empty:
            return 72
        }
    }
}

struct WorkSpellCardModel {
    let title: String
    let subtitle: String
    let metadataText: String
    let footer: String
    let inputPlaceholder: String
    let rows: [WorkSpellRow]
}

struct WorkSpellResolvedDependency: Hashable {
    let prerequisiteTaskID: String
    let dependentTaskID: String
}

struct WorkSpellRelationshipAssignment {
    let taskID: String
    let parentTaskID: String?
    let branchRole: WorkSpellBranchRole?
    let prerequisiteTaskIDs: [String]
}

struct WorkSpellStructuredPlan {
    let rootTitle: String
    let prerequisiteTitles: [String]
    let successorTitles: [String]
}

struct WorkSpellOracleDecision {
    let nextTaskID: String?
    let headline: String
    let detail: String
}

enum WorkSpellSettingsRowKind {
    case toggleActive
    case openNow
    case cycleMode
    case cycleAddGesture
    case cycleCompleteGesture
    case clearCompleted
    case back
}

struct WorkSpellSettingsRow {
    let kind: WorkSpellSettingsRowKind
    let title: String
    let detail: String
    let symbol: String
    let isEnabled: Bool
}

struct WorkSpellSettingsModel {
    let title: String
    let subtitle: String
    let metadataText: String
    let footer: String
    let rows: [WorkSpellSettingsRow]
}

private struct WorkSpellStoredState: Codable {
    var isActive: Bool
    var mode: WorkSpellMode
    var addTaskGesture: GestureKind
    var completeTaskGesture: GestureKind
    var tasks: [WorkSpellTask]

    init(
        isActive: Bool,
        mode: WorkSpellMode,
        addTaskGesture: GestureKind,
        completeTaskGesture: GestureKind,
        tasks: [WorkSpellTask]
    ) {
        self.isActive = isActive
        self.mode = mode
        self.addTaskGesture = addTaskGesture
        self.completeTaskGesture = completeTaskGesture
        self.tasks = tasks
    }

    private enum CodingKeys: String, CodingKey {
        case isActive
        case mode
        case addTaskGesture
        case completeTaskGesture
        case tasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        mode = try container.decodeIfPresent(WorkSpellMode.self, forKey: .mode) ?? .ordered
        addTaskGesture = try container.decode(GestureKind.self, forKey: .addTaskGesture)
        completeTaskGesture = try container.decode(GestureKind.self, forKey: .completeTaskGesture)
        tasks = try container.decodeIfPresent([WorkSpellTask].self, forKey: .tasks) ?? []
    }
}

final class WorkSpellStore {
    static let assignableGestures: [GestureKind] = [
        .centerDouble,
        .volumeUpDouble,
        .volumeDownDouble,
        .volumeUpHold,
        .volumeDownHold,
    ]

    private let path: String
    private var state: WorkSpellStoredState

    init(path: String) throws {
        self.path = normalizePath(path)
        self.state = WorkSpellStoredState(
            isActive: false,
            mode: .ordered,
            addTaskGesture: .volumeUpHold,
            completeTaskGesture: .centerDouble,
            tasks: []
        )
        try load()
    }

    var isActive: Bool {
        state.isActive
    }

    var mode: WorkSpellMode {
        state.mode
    }

    func binding(for key: WorkSpellBindingKey) -> GestureKind {
        switch key {
        case .addTask:
            return state.addTaskGesture
        case .completeTask:
            return state.completeTaskGesture
        }
    }

    @discardableResult
    func cycleBinding(for key: WorkSpellBindingKey) throws -> GestureKind {
        let current = binding(for: key)
        let other = binding(for: key == .addTask ? .completeTask : .addTask)
        let gestures = Self.assignableGestures
        guard let currentIndex = gestures.firstIndex(of: current) else {
            return current
        }

        var nextIndex = currentIndex
        for _ in 0..<gestures.count {
            nextIndex = (nextIndex + 1) % gestures.count
            let candidate = gestures[nextIndex]
            if candidate != other {
                switch key {
                case .addTask:
                    state.addTaskGesture = candidate
                case .completeTask:
                    state.completeTaskGesture = candidate
                }
                try save()
                return candidate
            }
        }

        return current
    }

    func setActive(_ isActive: Bool) throws {
        state.isActive = isActive
        try save()
    }

    func setMode(_ mode: WorkSpellMode) throws {
        state.mode = mode
        try save()
    }

    @discardableResult
    func cycleMode() throws -> WorkSpellMode {
        state.mode = state.mode == .ordered ? .unordered : .ordered
        try save()
        return state.mode
    }

    func activeTasks() -> [WorkSpellTask] {
        state.tasks
            .filter { !$0.isCompleted }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func task(withID taskID: String) -> WorkSpellTask? {
        state.tasks.first(where: { $0.id == taskID })
    }

    func completedTaskCount() -> Int {
        state.tasks.filter(\.isCompleted).count
    }

    func readyTaskCount() -> Int {
        activeTasks().filter { unmetPrerequisiteTitles(for: $0).isEmpty }.count
    }

    func unmetPrerequisiteTitles(for task: WorkSpellTask) -> [String] {
        let taskByID = Dictionary(uniqueKeysWithValues: state.tasks.map { ($0.id, $0) })
        return task.prerequisiteTaskIDs.compactMap { prerequisiteID in
            guard let prerequisite = taskByID[prerequisiteID], !prerequisite.isCompleted else {
                return nil
            }
            return prerequisite.title
        }
    }

    func oracleDecision() -> WorkSpellOracleDecision {
        let pendingTasks = activeTasks()
        guard !pendingTasks.isEmpty else {
            return WorkSpellOracleDecision(
                nextTaskID: nil,
                headline: "Your spell is empty.",
                detail: "Add a few tasks and I’ll suggest the best next move."
            )
        }

        let readyTasks = pendingTasks.filter { unmetPrerequisiteTitles(for: $0).isEmpty }
        if let nextTask = readyTasks.first {
            let detail: String
            if readyTasks.count == 1 {
                detail = "Everything else waits on this or comes later."
            } else {
                detail = "\(readyTasks.count) tasks are unlocked right now. Start here."
            }
            return WorkSpellOracleDecision(
                nextTaskID: nextTask.id,
                headline: "Next logical step: \(nextTask.title)",
                detail: detail
            )
        }

        let blockedTask = pendingTasks.min {
            let lhsUnmet = unmetPrerequisiteTitles(for: $0).count
            let rhsUnmet = unmetPrerequisiteTitles(for: $1).count
            if lhsUnmet == rhsUnmet {
                return $0.createdAt < $1.createdAt
            }
            return lhsUnmet < rhsUnmet
        }

        let unmet = blockedTask.map(unmetPrerequisiteTitles(for:)) ?? []
        let detail = unmet.isEmpty
            ? "Everything is blocked right now."
            : "Unblock \(unmet.joined(separator: ", ")) first."
        return WorkSpellOracleDecision(
            nextTaskID: blockedTask?.id,
            headline: "Nothing is unlocked yet.",
            detail: detail
        )
    }

    @discardableResult
    func addTask(title: String, now: Date = Date()) throws -> WorkSpellTask? {
        let cleaned = WorkSpellTaskParser.cleanTaskTitle(title)
        guard !cleaned.isEmpty else {
            return nil
        }

        let task = WorkSpellTask(
            id: UUID().uuidString,
            title: cleaned,
            createdAt: now,
            completedAt: nil
        )
        state.tasks.append(task)
        try save()
        return task
    }

    @discardableResult
    func addTasks(titles: [String], now: Date = Date()) throws -> [WorkSpellTask] {
        var added: [WorkSpellTask] = []
        for title in titles {
            if let task = try addTask(title: title, now: now) {
                added.append(task)
            }
        }
        return added
    }

    @discardableResult
    func removeTask(id taskID: String) throws -> WorkSpellTask? {
        guard let index = state.tasks.firstIndex(where: { $0.id == taskID }) else {
            return nil
        }
        let removed = state.tasks.remove(at: index)
        try save()
        return removed
    }

    @discardableResult
    func removeTasks(matchingTitles titles: [String]) throws -> [WorkSpellTask] {
        let queries = titles
            .map(WorkSpellTaskParser.cleanTaskTitle)
            .filter { !$0.isEmpty }
        guard !queries.isEmpty else {
            return []
        }

        var removedTaskIDs: Set<String> = []
        var removedTasks: [WorkSpellTask] = []
        for query in queries {
            guard let match = bestMatchingActiveTask(for: query, excluding: removedTaskIDs) else {
                continue
            }
            removedTaskIDs.insert(match.id)
            removedTasks.append(match)
        }

        guard !removedTaskIDs.isEmpty else {
            return []
        }

        state.tasks.removeAll { removedTaskIDs.contains($0.id) }
        try save()
        return removedTasks.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    @discardableResult
    func restoreTasks(_ tasks: [WorkSpellTask]) throws -> [WorkSpellTask] {
        guard !tasks.isEmpty else {
            return []
        }

        let existingIDs = Set(state.tasks.map(\.id))
        let restored = tasks.filter { !existingIDs.contains($0.id) }
        guard !restored.isEmpty else {
            return []
        }

        state.tasks.append(contentsOf: restored)
        try save()
        return restored
    }

    @discardableResult
    func completeTask(id taskID: String, now: Date = Date()) throws -> WorkSpellTask? {
        guard let index = state.tasks.firstIndex(where: { $0.id == taskID && !$0.isCompleted }) else {
            return nil
        }
        state.tasks[index].completedAt = now
        try save()
        return state.tasks[index]
    }

    @discardableResult
    func clearCompleted() throws -> Int {
        let before = state.tasks.count
        state.tasks.removeAll(where: \.isCompleted)
        let removed = before - state.tasks.count
        if removed > 0 {
            try save()
        }
        return removed
    }

    @discardableResult
    func addDependencies(_ dependencies: [WorkSpellResolvedDependency]) throws -> Int {
        guard !dependencies.isEmpty else {
            return 0
        }

        let deduped = Array(Set(dependencies)).filter { $0.prerequisiteTaskID != $0.dependentTaskID }
        guard !deduped.isEmpty else {
            return 0
        }

        var changedCount = 0
        for dependency in deduped {
            guard let index = state.tasks.firstIndex(where: { $0.id == dependency.dependentTaskID }) else {
                continue
            }
            if !state.tasks[index].prerequisiteTaskIDs.contains(dependency.prerequisiteTaskID) {
                state.tasks[index].prerequisiteTaskIDs.append(dependency.prerequisiteTaskID)
                changedCount += 1
            }
        }

        if changedCount > 0 {
            try save()
        }
        return changedCount
    }

    @discardableResult
    func applyRelationships(_ assignments: [WorkSpellRelationshipAssignment]) throws -> Int {
        guard !assignments.isEmpty else {
            return 0
        }

        var changedCount = 0
        for assignment in assignments {
            guard let index = state.tasks.firstIndex(where: { $0.id == assignment.taskID }) else {
                continue
            }

            if state.tasks[index].parentTaskID != assignment.parentTaskID {
                state.tasks[index].parentTaskID = assignment.parentTaskID
                changedCount += 1
            }
            if state.tasks[index].branchRole != assignment.branchRole {
                state.tasks[index].branchRole = assignment.branchRole
                changedCount += 1
            }

            let prerequisiteIDs = assignment.prerequisiteTaskIDs.filter { $0 != assignment.taskID }
            if Set(state.tasks[index].prerequisiteTaskIDs) != Set(prerequisiteIDs) {
                state.tasks[index].prerequisiteTaskIDs = prerequisiteIDs
                changedCount += 1
            }
        }

        if changedCount > 0 {
            try save()
        }
        return changedCount
    }

    private func load() throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        guard FileManager.default.fileExists(atPath: url.path) else {
            try save()
            return
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            try save()
            return
        }

        let decoded = try JSONDecoder().decode(WorkSpellStoredState.self, from: data)
        state = decoded
        if !Self.assignableGestures.contains(state.addTaskGesture) {
            state.addTaskGesture = .volumeUpHold
        }
        if !Self.assignableGestures.contains(state.completeTaskGesture) || state.completeTaskGesture == state.addTaskGesture {
            state.completeTaskGesture = Self.assignableGestures.first(where: { $0 != state.addTaskGesture }) ?? .centerDouble
        }
    }

    private func save() throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    private func bestMatchingActiveTask(for query: String, excluding excludedIDs: Set<String>) -> WorkSpellTask? {
        let normalizedQuery = normalizedTaskLookupKey(query)
        guard !normalizedQuery.isEmpty else {
            return nil
        }

        return activeTasks()
            .filter { !excludedIDs.contains($0.id) }
            .map { task in
                (task: task, score: taskMatchScore(query: normalizedQuery, taskTitle: task.title))
            }
            .filter { $0.score < Int.max }
            .min { lhs, rhs in
                if lhs.score == rhs.score {
                    if lhs.task.createdAt == rhs.task.createdAt {
                        return lhs.task.title.localizedCaseInsensitiveCompare(rhs.task.title) == .orderedAscending
                    }
                    return lhs.task.createdAt < rhs.task.createdAt
                }
                return lhs.score < rhs.score
            }?
            .task
    }

    private func taskMatchScore(query: String, taskTitle: String) -> Int {
        let normalizedTitle = normalizedTaskLookupKey(taskTitle)
        guard !normalizedTitle.isEmpty else {
            return Int.max
        }

        if normalizedTitle == query {
            return 0
        }
        if normalizedTitle.hasPrefix(query) || normalizedTitle.hasSuffix(query) {
            return 1
        }
        if normalizedTitle.contains(query) || query.contains(normalizedTitle) {
            return 2
        }

        let queryTokens = Set(query.split(separator: " ").map(String.init))
        let titleTokens = Set(normalizedTitle.split(separator: " ").map(String.init))
        let overlap = queryTokens.intersection(titleTokens).count
        guard overlap > 0 else {
            return Int.max
        }

        return 10 - min(overlap, 9)
    }

    private func normalizedTaskLookupKey(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WorkSpellTaskParser {
    static func requestedMode(from transcript: String) -> WorkSpellMode? {
        let normalized = transcript.lowercased()
        if normalized.contains("unordered") || normalized.contains("unlocked web") || normalized.contains("unlock the web") {
            return .unordered
        }
        if normalized.contains("ordered") || normalized.contains("ordered web") || normalized.contains("make it a web") {
            return .ordered
        }
        return nil
    }

    static func isModeOnlyCommand(_ transcript: String) -> Bool {
        guard requestedMode(from: transcript) != nil else {
            return false
        }

        let normalized = transcript
            .lowercased()
            .replacingOccurrences(of: "[^a-z\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let patterns = [
            "^(?:work\\s+spell\\s+|spell\\s+)?(?:please\\s+)?(?:i\\s+want\\s+it(?:\\s+to\\s+be)?\\s+|make\\s+it\\s+|switch\\s+to\\s+|set\\s+it\\s+to\\s+|keep\\s+it\\s+)?(?:an?\\s+)?(?:ordered|unordered)(?:\\s+web|\\s+mode)?$",
            "^(?:work\\s+spell\\s+|spell\\s+)?(?:please\\s+)?(?:unlock\\s+the\\s+web|make\\s+it\\s+a\\s+web|make\\s+it\\s+an\\s+ordered\\s+web|make\\s+it\\s+an\\s+unordered\\s+web)$"
        ]

        for pattern in patterns {
            if normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return true
            }
        }

        return false
    }

    static func taskTitles(fromListText text: String) -> [String] {
        let cleanedText = trimLeadingPrompt(from: text)
        guard !cleanedText.isEmpty else {
            return []
        }

        return splitTaskList(cleanedText)
    }

    static func taskTitles(from transcript: String) -> [String] {
        guard let workSpellRange = transcript.range(of: "work spell", options: [.caseInsensitive]) else {
            return []
        }

        var remainder = String(transcript[workSpellRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if remainder.isEmpty {
            return []
        }

        remainder = trimLeadingPrompt(from: remainder)
        guard !remainder.isEmpty else {
            return []
        }

        return splitTaskList(remainder)
    }

    static func taskTitlesForAddCommand(from transcript: String) -> [String] {
        guard let body = commandBody(
            from: transcript,
            verbs: ["add", "append", "include", "put", "make", "create"],
            trailingTargets: ["todo", "to do", "list", "task list", "work spell", "spell", "checklist"]
        ) else {
            return []
        }

        return splitTaskList(body)
    }

    static func taskTitlesForRemovalCommand(from transcript: String) -> [String] {
        guard let body = commandBody(
            from: transcript,
            verbs: ["remove", "delete", "drop", "cut", "take off"],
            trailingTargets: ["todo", "to do", "list", "task list", "work spell", "spell", "checklist"]
        ) else {
            return []
        }

        return splitTaskList(
            body
                .replacingOccurrences(of: "\\btask\\b", with: "", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "\\bitem\\b", with: "", options: [.regularExpression, .caseInsensitive])
        )
    }

    static func structuredPlan(from transcript: String) -> WorkSpellStructuredPlan? {
        let scrubbed = transcript
            .replacingOccurrences(of: "\\bordered\\b", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\bunordered\\b", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\bunlocked web\\b", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lowered = scrubbed.lowercased()
        let markers = [" i have to do ", " have to do "]
        guard let marker = markers.first(where: { lowered.contains($0) }),
              let markerRange = lowered.range(of: marker) else {
            return nil
        }

        let rootSegment = String(scrubbed[..<markerRange.lowerBound])
        let remainder = String(scrubbed[markerRange.upperBound...])
        let rootTitle = cleanTaskTitle(trimLeadingPrompt(from: rootSegment))
        guard !rootTitle.isEmpty else {
            return nil
        }

        let successorSplitter = remainder.replacingOccurrences(
            of: "\\s*,?\\s*then\\s+i\\s+have\\s+to\\s+do\\s+",
            with: "|||",
            options: [.regularExpression, .caseInsensitive]
        )
        let segments = successorSplitter
            .components(separatedBy: "|||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let prerequisiteSegment = segments.first else {
            return nil
        }

        let prerequisiteTitles = splitTaskList(prerequisiteSegment)
        let successorTitles = segments.dropFirst().flatMap(splitTaskList)
        guard !prerequisiteTitles.isEmpty || !successorTitles.isEmpty else {
            return nil
        }

        return WorkSpellStructuredPlan(
            rootTitle: rootTitle,
            prerequisiteTitles: prerequisiteTitles,
            successorTitles: successorTitles
        )
    }

    static func cleanTaskTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: "^(?:a|an|the)\\s+", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "^do\\s+", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func splitTaskList(_ text: String) -> [String] {
        let normalizedSeparators = text
            .replacingOccurrences(of: ", and ", with: ", ", options: [.caseInsensitive])
            .replacingOccurrences(of: " and then ", with: ", ", options: [.caseInsensitive])
            .replacingOccurrences(of: ";", with: ",")

        let parts = normalizedSeparators
            .components(separatedBy: ",")
            .flatMap { fragment -> [String] in
                let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return []
                }
                if trimmed.range(of: "\\band\\b", options: [.regularExpression, .caseInsensitive]) != nil,
                   !trimmed.contains("\"") {
                    return trimmed
                        .components(separatedBy: .init(charactersIn: "\n"))
                        .flatMap { line in
                            line
                                .replacingOccurrences(
                                    of: "\\s+and\\s+",
                                    with: ",",
                                    options: [.regularExpression, .caseInsensitive]
                                )
                                .components(separatedBy: ",")
                        }
                }
                return [trimmed]
            }
            .map(cleanTaskTitle)
            .filter { !$0.isEmpty }

        var unique: [String] = []
        var seen: Set<String> = []
        for part in parts {
            let key = part.lowercased()
            if seen.insert(key).inserted {
                unique.append(part)
            }
        }
        return unique
    }

    private static func commandBody(from transcript: String, verbs: [String], trailingTargets: [String]) -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let escapedVerbs = verbs
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let escapedTargets = trailingTargets
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")

        let patterns = [
            "^(?:please\\s+)?(?:can\\s+you\\s+|could\\s+you\\s+|will\\s+you\\s+)?(?:\(escapedVerbs))\\s+(.+?)(?:\\s+(?:to|into|onto|on|from|off)\\s+(?:my\\s+|the\\s+)?(?:\(escapedTargets)))?[.!?]*$",
            "^(?:please\\s+)?(.+?)\\s+(?:to|into|onto|on|from|off)\\s+(?:my\\s+|the\\s+)?(?:\(escapedTargets))[.!?]*$"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: trimmed) else {
                continue
            }

            let body = String(trimmed[captureRange])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !body.isEmpty {
                return body
            }
        }

        return nil
    }

    private static func trimLeadingPrompt(from text: String) -> String {
        let prefixes = [
            "work spell",
            "spell",
            "please",
            "i want it to be",
            "i want to do",
            "i want to",
            "i want it",
            "i have to do",
            "i have to",
            "i need to do",
            "i need to",
            "i need",
            "i've got to",
            "i gotta",
            "my tasks are",
            "the tasks are",
            "tasks are",
            "todo is",
            "to do is",
            "todo",
            "to do",
            "for",
            ":",
            "-"
        ]

        var remainder = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var didTrim = true
        while didTrim {
            didTrim = false
            let lowered = remainder.lowercased()
            for prefix in prefixes {
                if lowered.hasPrefix(prefix) {
                    remainder = String(remainder.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    didTrim = true
                    break
                }
            }
        }
        return remainder
    }
}

enum WorkSpellDependencyParser {
    static func isNegativeResponse(_ transcript: String) -> Bool {
        let normalized = normalize(transcript)
        let negativePhrases = [
            "no",
            "nope",
            "none",
            "nothing",
            "no dependencies",
            "no prereqs",
            "independent",
            "they are independent",
            "keep them independent",
            "separate"
        ]
        return negativePhrases.contains { normalized == $0 || normalized.contains($0) }
    }

    static func resolvedDependencies(from transcript: String, tasks: [WorkSpellTask]) -> [WorkSpellResolvedDependency] {
        let normalizedTranscript = normalize(transcript)
        let activeTasks = tasks.filter { !$0.isCompleted }
        guard activeTasks.count >= 2 else {
            return []
        }

        var resolved: Set<WorkSpellResolvedDependency> = []
        for prerequisite in activeTasks {
            for dependent in activeTasks where dependent.id != prerequisite.id {
                let prerequisitePattern = escapedPhrasePattern(for: prerequisite.title)
                let dependentPattern = escapedPhrasePattern(for: dependent.title)

                let patterns = [
                    "\\b\(prerequisitePattern)\\b\\s+before\\s+\\b\(dependentPattern)\\b",
                    "\\b\(dependentPattern)\\b\\s+after\\s+\\b\(prerequisitePattern)\\b",
                    "\\b\(dependentPattern)\\b\\s+depends\\s+on\\s+\\b\(prerequisitePattern)\\b",
                    "\\b\(dependentPattern)\\b\\s+needs\\s+\\b\(prerequisitePattern)\\b\\s+first\\b",
                    "\\b\(prerequisitePattern)\\b\\s+first\\b.{0,20}\\bthen\\s+\\b\(dependentPattern)\\b"
                ]

                if patterns.contains(where: { normalizedTranscript.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) {
                    resolved.insert(
                        WorkSpellResolvedDependency(
                            prerequisiteTaskID: prerequisite.id,
                            dependentTaskID: dependent.id
                        )
                    )
                }
            }
        }

        return Array(resolved)
    }

    private static func escapedPhrasePattern(for title: String) -> String {
        let normalizedTitle = normalize(title)
        let escaped = NSRegularExpression.escapedPattern(for: normalizedTitle)
        return escaped.replacingOccurrences(of: "\\ ", with: "\\\\s+")
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func workSpellGestureDisplayTitle(_ gesture: GestureKind) -> String {
    switch gesture {
    case .centerDouble:
        return "Center Double"
    case .centerTriple:
        return "Center Triple"
    case .volumeUpDouble:
        return "Plus Double"
    case .volumeDownDouble:
        return "Minus Double"
    case .volumeUpHold:
        return "Plus Hold"
    case .volumeDownHold:
        return "Minus Hold"
    case .centerSingle:
        return "Center Tap"
    case .centerHold:
        return "Center Hold"
    case .volumeUp:
        return "Plus"
    case .volumeDown:
        return "Minus"
    case .volumeUpTriple:
        return "Plus Triple"
    case .volumeDownTriple:
        return "Minus Triple"
    }
}

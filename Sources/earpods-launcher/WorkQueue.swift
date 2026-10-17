import AppKit
import EarPodsCore
import Foundation

struct WorkQueueItem: Codable, Hashable {
    let id: String
    let title: String
    let applicationName: String
    let bundleIdentifier: String?
    let contextLine: String?
    let windowTitle: String?
    let musicSummary: String?
    let createdAt: Date
    var sortDate: Date
    var isArchived: Bool
    var label: WorkQueueLabel?
}

enum WorkQueueLabel: String, Codable, CaseIterable, Hashable {
    case important
    case followUp = "follow_up"
    case later
    case blocked

    var title: String {
        switch self {
        case .important:
            return "Important"
        case .followUp:
            return "Follow Up"
        case .later:
            return "Later"
        case .blocked:
            return "Blocked"
        }
    }

    var symbol: String {
        switch self {
        case .important:
            return "exclamationmark.circle"
        case .followUp:
            return "arrow.uturn.forward.circle"
        case .later:
            return "clock"
        case .blocked:
            return "pause.circle"
        }
    }

    var tintColor: NSColor {
        switch self {
        case .important:
            return .systemRed
        case .followUp:
            return .systemOrange
        case .later:
            return .systemBlue
        case .blocked:
            return .systemGray
        }
    }

    var pickerDetail: String {
        switch self {
        case .important:
            return "Put extra weight on this thread."
        case .followUp:
            return "Keep this thread flagged for a return pass."
        case .later:
            return "Keep it staged without needing it right now."
        case .blocked:
            return "Mark that this thread can’t move yet."
        }
    }
}

struct WorkQueueAppContext {
    let applicationName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let semanticTitle: String?
    let semanticDetail: String?
}

enum WorkQueueListRowKind: Equatable {
    case item(String)
    case captureCurrentContext
    case back
}

enum WorkQueueListRowStyle {
    case featured
    case queued
    case utility
}

struct WorkQueueListRow {
    let kind: WorkQueueListRowKind
    let title: String
    let detail: String
    let symbol: String
    let isEnabled: Bool
    let style: WorkQueueListRowStyle
    let label: WorkQueueLabel?
}

struct WorkQueueListModel {
    let title: String
    let subtitle: String
    let metadataText: String
    let footer: String
    let rows: [WorkQueueListRow]
}

enum WorkQueueActionKind: String {
    case resumeApp
    case editLabel
    case setLabelImportant = "set_label_important"
    case setLabelFollowUp = "set_label_follow_up"
    case setLabelLater = "set_label_later"
    case setLabelBlocked = "set_label_blocked"
    case clearLabel = "clear_label"
    case bumpToTop
    case archive
    case delete
    case backToActions = "back_to_actions"
    case back
}

extension WorkQueueActionKind {
    var isLabelMutation: Bool {
        switch self {
        case .setLabelImportant, .setLabelFollowUp, .setLabelLater, .setLabelBlocked, .clearLabel:
            return true
        default:
            return false
        }
    }
}

struct WorkQueueAction {
    let kind: WorkQueueActionKind
    let title: String
    let detail: String
    let symbol: String
    let isEnabled: Bool
}

enum WorkQueueDetailMode {
    case actions
    case labelPicker
}

struct WorkQueueDetailModel {
    let mode: WorkQueueDetailMode
    let itemID: String
    let title: String
    let subtitle: String
    let metadataText: String
    let footer: String
    let actions: [WorkQueueAction]
}

struct WorkQueueCaptureOutcome {
    let item: WorkQueueItem
    let logNote: String
    let notificationBody: String
}

struct WorkQueueActionOutcome {
    let logNote: String
    let notificationBody: String?
    let closeQueueToHidden: Bool
    let reopenListSelectionItemID: String?
}

struct WorkQueueActionError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

final class WorkQueueStore {
    private struct StoredState: Codable {
        var items: [WorkQueueItem]
    }

    private let path: String
    private var items: [WorkQueueItem] = []

    init(path: String) throws {
        self.path = normalizePath(path)
        try load()
    }

    func activeItems() -> [WorkQueueItem] {
        items
            .filter { !$0.isArchived }
            .sorted {
                if $0.sortDate == $1.sortDate {
                    return $0.createdAt > $1.createdAt
                }
                return $0.sortDate > $1.sortDate
            }
    }

    func item(withID itemID: String) -> WorkQueueItem? {
        items.first(where: { $0.id == itemID })
    }

    @discardableResult
    func captureCurrentContext(frontmostApp: WorkQueueAppContext?, nowPlayingSnapshot: NowPlayingSnapshot?, now: Date = Date()) throws -> WorkQueueItem {
        let description = CurrentThreadNamingEngine.describe(
            frontmostApp: frontmostApp,
            nowPlayingSnapshot: nowPlayingSnapshot
        )

        let item = WorkQueueItem(
            id: UUID().uuidString,
            title: description.title,
            applicationName: description.applicationName,
            bundleIdentifier: description.bundleIdentifier,
            contextLine: description.subtitle,
            windowTitle: description.windowTitle,
            musicSummary: description.musicSummary,
            createdAt: now,
            sortDate: now,
            isArchived: false,
            label: nil
        )

        items.insert(item, at: 0)
        try persist()
        return item
    }

    @discardableResult
    func bumpItem(withID itemID: String, now: Date = Date()) throws -> WorkQueueItem? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }

        items[index].sortDate = now
        try persist()
        return items[index]
    }

    @discardableResult
    func archiveItem(withID itemID: String) throws -> WorkQueueItem? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }

        items[index].isArchived = true
        try persist()
        return items[index]
    }

    @discardableResult
    func deleteItem(withID itemID: String) throws -> WorkQueueItem? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }

        let item = items.remove(at: index)
        try persist()
        return item
    }

    @discardableResult
    func setLabel(_ label: WorkQueueLabel?, forItemWithID itemID: String) throws -> WorkQueueItem? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }

        items[index].label = label
        try persist()
        return items[index]
    }

    private func load() throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        guard FileManager.default.fileExists(atPath: url.path) else {
            items = []
            return
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            items = []
            return
        }

        let decoded = try JSONDecoder().decode(StoredState.self, from: data)
        items = decoded.items
    }

    private func persist() throws {
        let url = URL(fileURLWithPath: path)
        let data = try JSONEncoder().encode(StoredState(items: items))
        try data.write(to: url, options: .atomic)
    }

}

@MainActor
final class WorkQueueCoordinator {
    private let store: WorkQueueStore
    private let relativeFormatter: RelativeDateTimeFormatter
    private let absoluteFormatter: DateFormatter

    init(store: WorkQueueStore) {
        self.store = store

        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .short
        self.relativeFormatter = relativeFormatter

        let absoluteFormatter = DateFormatter()
        absoluteFormatter.dateStyle = .medium
        absoluteFormatter.timeStyle = .short
        self.absoluteFormatter = absoluteFormatter
    }

    func listModel() -> WorkQueueListModel {
        let items = store.activeItems()
        let subtitle: String
        var metadataText: String
        let labeledCount = items.filter { $0.label != nil }.count

        if items.isEmpty {
            subtitle = "Capture the thread you’re in now, then come back here to continue it without hunting for it."
            metadataText = "Nothing staged yet"
        } else {
            let currentThread = items[0].title
            let backlogCount = max(items.count - 1, 0)
            subtitle = "Your current thread stays on top. Everything else waits underneath."
            metadataText = backlogCount == 0
                ? "Current thread: \(currentThread)"
                : "Current thread: \(currentThread) • \(backlogCount) queued next"
            if labeledCount > 0 {
                metadataText += " • \(labeledCount) labeled"
            }
        }

        let itemRows = items.enumerated().map(makeListRow(index:item:))
        let rows = itemRows + [
            WorkQueueListRow(
                kind: .captureCurrentContext,
                title: "Capture Current Thread",
                detail: "Stage what you’re in right now and put it on top.",
                symbol: "plus.circle",
                isEnabled: true,
                style: .utility,
                label: nil
            ),
            WorkQueueListRow(
                kind: .back,
                title: "Back",
                detail: "Return to the launcher.",
                symbol: "chevron.backward",
                isEnabled: true,
                style: .utility,
                label: nil
            ),
        ]

        return WorkQueueListModel(
            title: "Work Queue",
            subtitle: subtitle,
            metadataText: metadataText,
            footer: "Tap an item for actions. Double-tap center to remove the selected item. Hold center to go back.",
            rows: rows
        )
    }

    func detailModel(for itemID: String) -> WorkQueueDetailModel? {
        guard let item = store.item(withID: itemID), !item.isArchived else {
            return nil
        }

        let capturedText = "Captured \(absoluteFormatter.string(from: item.createdAt))"
        let metadataParts = [
            item.label.map { "Label: \($0.title)" },
            "App: \(item.applicationName)",
            item.windowTitle.flatMap { windowTitle in
                guard windowTitle.caseInsensitiveCompare(item.title) != .orderedSame else {
                    return nil
                }
                return "Window: \(windowTitle)"
            },
            item.musicSummary.map { "Soundtrack: \($0)" }
        ].compactMap { $0 }

        let metadataText = metadataParts.isEmpty
            ? "Resume the app, bump it to the top, archive it, or remove it."
            : metadataParts.joined(separator: "\n")

        let actions = [
            WorkQueueAction(
                kind: .resumeApp,
                title: "Resume App",
                detail: "Bring \(item.applicationName) back to the front.",
                symbol: "arrow.turn.up.right",
                isEnabled: item.bundleIdentifier != nil
            ),
            WorkQueueAction(
                kind: .editLabel,
                title: "Label Thread",
                detail: item.label.map { "Current: \($0.title). Choose a queue label." } ?? "Tag this thread as Important, Follow Up, Later, or Blocked.",
                symbol: item.label?.symbol ?? "tag",
                isEnabled: true
            ),
            WorkQueueAction(
                kind: .bumpToTop,
                title: "Bump to Top",
                detail: "Move this checkpoint to the top of the queue.",
                symbol: "arrow.up.to.line.compact",
                isEnabled: true
            ),
            WorkQueueAction(
                kind: .archive,
                title: "Archive",
                detail: "Hide it from the active queue but keep the record.",
                symbol: "archivebox",
                isEnabled: true
            ),
            WorkQueueAction(
                kind: .delete,
                title: "Delete",
                detail: "Remove this checkpoint completely.",
                symbol: "trash",
                isEnabled: true
            ),
            WorkQueueAction(
                kind: .back,
                title: "Back",
                detail: "Return to the queue.",
                symbol: "chevron.backward",
                isEnabled: true
            ),
        ]

        return WorkQueueDetailModel(
            mode: .actions,
            itemID: item.id,
            title: item.title,
            subtitle: capturedText,
            metadataText: metadataText,
            footer: "Tap Label Thread to tag this thread. Double-tap center for back. Hold center to leave Work Queue.",
            actions: actions
        )
    }

    func labelPickerModel(for itemID: String) -> WorkQueueDetailModel? {
        guard let item = store.item(withID: itemID), !item.isArchived else {
            return nil
        }

        let subtitle = item.label.map { "Current label: \($0.title)" } ?? "Choose a label for this thread."
        let metadataParts = [
            "App: \(item.applicationName)",
            item.windowTitle.flatMap { windowTitle in
                guard windowTitle.caseInsensitiveCompare(item.title) != .orderedSame else {
                    return nil
                }
                return "Window: \(windowTitle)"
            },
            item.musicSummary.map { "Soundtrack: \($0)" }
        ].compactMap { $0 }

        let actions = [
            makeLabelAction(.important, currentLabel: item.label),
            makeLabelAction(.followUp, currentLabel: item.label),
            makeLabelAction(.later, currentLabel: item.label),
            makeLabelAction(.blocked, currentLabel: item.label),
        ] + {
            guard item.label != nil else {
                return []
            }
            return [
                WorkQueueAction(
                    kind: .clearLabel,
                    title: "Clear Label",
                    detail: "Remove the current queue label.",
                    symbol: "xmark.circle",
                    isEnabled: true
                )
            ]
        }() + [
            WorkQueueAction(
                kind: .backToActions,
                title: "Back to Thread",
                detail: "Return to this thread’s actions.",
                symbol: "chevron.backward",
                isEnabled: true
            )
        ]

        return WorkQueueDetailModel(
            mode: .labelPicker,
            itemID: item.id,
            title: item.title,
            subtitle: subtitle,
            metadataText: metadataParts.isEmpty ? "Pick the label that best fits this thread." : metadataParts.joined(separator: "\n"),
            footer: "Tap a label to apply it. Double-tap center for thread actions. Hold center to leave Work Queue.",
            actions: actions
        )
    }

    var activeItemCount: Int {
        store.activeItems().count
    }

    func topActiveItem() -> WorkQueueItem? {
        store.activeItems().first
    }

    func listSelectionIndex(for itemID: String?) -> Int? {
        guard let itemID else {
            return nil
        }

        return listModel().rows.firstIndex {
            if case .item(let candidateID) = $0.kind {
                return candidateID == itemID
            }
            return false
        }
    }

    func captureCurrentContext(frontmostApp: WorkQueueAppContext?, nowPlayingSnapshot: NowPlayingSnapshot?) -> Result<WorkQueueCaptureOutcome, WorkQueueActionError> {
        do {
            let item = try store.captureCurrentContext(frontmostApp: frontmostApp, nowPlayingSnapshot: nowPlayingSnapshot)
            return .success(
                WorkQueueCaptureOutcome(
                    item: item,
                    logNote: "captured \(item.title) into work queue",
                    notificationBody: "Saved \(item.title) to Work Queue"
                )
            )
        } catch {
            return .failure(WorkQueueActionError(message: "Work Queue could not save the current context. \(error.localizedDescription)"))
        }
    }

    func perform(_ action: WorkQueueActionKind, itemID: String) -> Result<WorkQueueActionOutcome, WorkQueueActionError> {
        guard let item = store.item(withID: itemID), !item.isArchived else {
            return .failure(WorkQueueActionError(message: "That queue item is no longer available."))
        }

        switch action {
        case .resumeApp:
            guard let bundleIdentifier = item.bundleIdentifier else {
                return .failure(WorkQueueActionError(message: "This checkpoint does not have an app bundle to resume."))
            }

            let launched = openApplication(bundleIdentifier: bundleIdentifier)

            guard launched else {
                return .failure(WorkQueueActionError(message: "\(item.applicationName) could not be resumed from Work Queue."))
            }

            let movedToTop = (try? store.bumpItem(withID: item.id)) != nil

            return .success(
                WorkQueueActionOutcome(
                    logNote: movedToTop
                        ? "resumed \(item.applicationName) and moved it to the top of work queue"
                        : "resumed \(item.applicationName) from work queue",
                    notificationBody: movedToTop
                        ? "Resumed \(item.applicationName) and moved it to the top"
                        : "Resumed \(item.applicationName)",
                    closeQueueToHidden: true,
                    reopenListSelectionItemID: item.id
                )
            )
        case .bumpToTop:
            do {
                _ = try store.bumpItem(withID: item.id)
                return .success(
                    WorkQueueActionOutcome(
                        logNote: "bumped \(item.title) to the top of work queue",
                        notificationBody: "Bumped \(item.title)",
                        closeQueueToHidden: false,
                        reopenListSelectionItemID: item.id
                    )
                )
            } catch {
                return .failure(WorkQueueActionError(message: "Work Queue could not move that checkpoint. \(error.localizedDescription)"))
            }
        case .editLabel:
            return .success(
                WorkQueueActionOutcome(
                    logNote: "opened label picker for \(item.title) in work queue",
                    notificationBody: nil,
                    closeQueueToHidden: false,
                    reopenListSelectionItemID: item.id
                )
            )
        case .setLabelImportant, .setLabelFollowUp, .setLabelLater, .setLabelBlocked, .clearLabel:
            do {
                let label = label(for: action)
                _ = try store.setLabel(label, forItemWithID: item.id)
                let notificationBody = label.map { "Marked \(item.title) as \($0.title)" } ?? "Cleared label on \(item.title)"
                let logNote = label.map { "labeled \(item.title) as \($0.title.lowercased()) in work queue" } ?? "cleared label on \(item.title) in work queue"
                return .success(
                    WorkQueueActionOutcome(
                        logNote: logNote,
                        notificationBody: notificationBody,
                        closeQueueToHidden: false,
                        reopenListSelectionItemID: item.id
                    )
                )
            } catch {
                return .failure(WorkQueueActionError(message: "Work Queue could not update that label. \(error.localizedDescription)"))
            }
        case .archive:
            do {
                _ = try store.archiveItem(withID: item.id)
                return .success(
                    WorkQueueActionOutcome(
                        logNote: "archived \(item.title) from work queue",
                        notificationBody: "Archived \(item.title)",
                        closeQueueToHidden: false,
                        reopenListSelectionItemID: nil
                    )
                )
            } catch {
                return .failure(WorkQueueActionError(message: "Work Queue could not archive that checkpoint. \(error.localizedDescription)"))
            }
        case .delete:
            do {
                _ = try store.deleteItem(withID: item.id)
                return .success(
                    WorkQueueActionOutcome(
                        logNote: "deleted \(item.title) from work queue",
                        notificationBody: "Deleted \(item.title)",
                        closeQueueToHidden: false,
                        reopenListSelectionItemID: nil
                    )
                )
            } catch {
                return .failure(WorkQueueActionError(message: "Work Queue could not delete that checkpoint. \(error.localizedDescription)"))
            }
        case .backToActions:
            return .success(
                WorkQueueActionOutcome(
                    logNote: "returned from work queue label picker to thread actions",
                    notificationBody: nil,
                    closeQueueToHidden: false,
                    reopenListSelectionItemID: item.id
                )
            )
        case .back:
            return .success(
                WorkQueueActionOutcome(
                    logNote: "returned from work queue item detail to the list",
                    notificationBody: nil,
                    closeQueueToHidden: false,
                    reopenListSelectionItemID: item.id
                )
            )
        }
    }

    private func makeListRow(index: Int, item: WorkQueueItem) -> WorkQueueListRow {
        let relativeText = relativeFormatter.localizedString(for: item.createdAt, relativeTo: Date())
        let leadingStatus = index == 0 ? "Current thread" : "Queued \(relativeText)"
        let detailParts = [leadingStatus, item.contextLine, item.musicSummary].compactMap { value -> String? in
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        }

        return WorkQueueListRow(
            kind: .item(item.id),
            title: item.title,
            detail: detailParts.joined(separator: " • "),
            symbol: index == 0 ? "briefcase.fill" : "briefcase",
            isEnabled: true,
            style: index == 0 ? .featured : .queued,
            label: item.label
        )
    }

    func labelPickerSelectionIndex(for itemID: String) -> Int? {
        guard let item = store.item(withID: itemID), !item.isArchived else {
            return nil
        }

        let actions = labelPickerModel(for: itemID)?.actions ?? []
        if let currentLabel = item.label {
            return actions.firstIndex { label(for: $0.kind) == currentLabel }
        }
        return 0
    }

    private func openApplication(bundleIdentifier: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", bundleIdentifier]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func makeLabelAction(_ label: WorkQueueLabel, currentLabel: WorkQueueLabel?) -> WorkQueueAction {
        WorkQueueAction(
            kind: actionKind(for: label),
            title: label.title,
            detail: currentLabel == label ? "Already labeled \(label.title)." : label.pickerDetail,
            symbol: label.symbol,
            isEnabled: currentLabel != label
        )
    }

    private func actionKind(for label: WorkQueueLabel) -> WorkQueueActionKind {
        switch label {
        case .important:
            return .setLabelImportant
        case .followUp:
            return .setLabelFollowUp
        case .later:
            return .setLabelLater
        case .blocked:
            return .setLabelBlocked
        }
    }

    private func label(for action: WorkQueueActionKind) -> WorkQueueLabel? {
        switch action {
        case .setLabelImportant:
            return .important
        case .setLabelFollowUp:
            return .followUp
        case .setLabelLater:
            return .later
        case .setLabelBlocked:
            return .blocked
        default:
            return nil
        }
    }
}

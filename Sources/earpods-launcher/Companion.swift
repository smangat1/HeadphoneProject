import AVFoundation
import AppKit
import EarPodsCore
import Foundation
import NaturalLanguage
import Speech

enum CompanionIntentAction: String, Codable, CaseIterable {
    case continuePortal = "continue_portal"
    case openWorkQueue = "open_work_queue"
    case captureCheckpoint = "capture_checkpoint"
    case openCurrentThread = "open_current_thread"
    case activateWorkSpell = "activate_work_spell"
    case removeWorkSpellTasks = "remove_work_spell_tasks"
    case deactivateWorkSpell = "deactivate_work_spell"
    case openTimer = "open_timer"
    case setTimer = "set_timer"
    case cancelTimer = "cancel_timer"
    case openNowPlaying = "open_now_playing"
    case togglePlayback = "toggle_playback"
    case openEntity = "open_entity"
    case undoLastAction = "undo_last_action"
    case runMacro = "run_macro"
    case none
}

enum CompanionCommandDomain: String {
    case spells
    case timer
    case search
    case apps
    case workQueue = "work_queue"
    case currentThread = "current_thread"
    case media
    case capture
    case navigation
    case management
    case macro
    case teaching
    case unknown

    var title: String {
        switch self {
        case .spells:
            return "Spells"
        case .timer:
            return "Timer"
        case .search:
            return "Search"
        case .apps:
            return "Apps"
        case .workQueue:
            return "Work Queue"
        case .currentThread:
            return "Current Thread"
        case .media:
            return "Media"
        case .capture:
            return "Capture"
        case .navigation:
            return "Continue"
        case .management:
            return "Manage"
        case .macro:
            return "Macro"
        case .teaching:
            return "Teach"
        case .unknown:
            return "Companion"
        }
    }

    var symbol: String {
        switch self {
        case .spells:
            return "wand.and.stars"
        case .timer:
            return "timer"
        case .search:
            return "magnifyingglass"
        case .apps:
            return "macwindow"
        case .workQueue:
            return "list.bullet.clipboard"
        case .currentThread:
            return "sparkles"
        case .media:
            return "music.note"
        case .capture:
            return "tray.and.arrow.down"
        case .navigation:
            return "arrowshape.turn.up.forward"
        case .management:
            return "arrow.uturn.backward.circle"
        case .macro:
            return "wand.and.stars"
        case .teaching:
            return "brain"
        case .unknown:
            return "ellipsis.bubble"
        }
    }

    var hint: String {
        switch self {
        case .spells:
            return "Spell commands activate private modes like Work Spell."
        case .timer:
            return "Timer commands work best with a clear duration."
        case .search:
            return "Search commands open a fresh browser search."
        case .apps:
            return "App commands work best with the exact app name."
        case .workQueue:
            return "Queue commands can open or stage work."
        case .currentThread:
            return "Thread commands focus on what you’re doing now."
        case .media:
            return "Media commands open Now Playing or change playback."
        case .capture:
            return "Capture commands save the current thread."
        case .navigation:
            return "Continue commands resume the most relevant live thing."
        case .management:
            return "Management commands cancel or undo recent changes."
        case .macro:
            return "Macro commands run a taught sequence."
        case .teaching:
            return "Teaching commands update your personal language layer."
        case .unknown:
            return "Keep it short and direct."
        }
    }

    var helpSummary: String {
        switch self {
        case .spells:
            return "Spells activate or dismiss a private control mode."
        case .timer:
            return "Timer works best when you include a clear length."
        case .search:
            return "Search opens a fresh browser search, not an existing tab."
        case .apps:
            return "App commands work best with a short, specific app name."
        case .workQueue:
            return "Work Queue can open the queue or capture the current thread."
        case .currentThread:
            return "Current Thread reads the app and context you are in right now."
        case .media:
            return "Media handles Now Playing and playback control."
        case .capture:
            return "Capture saves the current thread into Work Queue."
        case .navigation:
            return "Continue resumes the most relevant live thing."
        case .management:
            return "Management can cancel the timer or undo the last Companion change."
        case .macro:
            return "Macros run a taught sequence from your Lexicon."
        case .teaching:
            return "Teach updates your private language so Companion understands you better and remembers your corrections."
        case .unknown:
            return "Companion is strongest with short commands across a few clear domains."
        }
    }

    var helpExamples: [String] {
        switch self {
        case .spells:
            return ["work spell", "stop work spell"]
        case .timer:
            return ["start a five minute timer", "open timer"]
        case .search:
            return ["search figma docs", "look up linear issue tracker"]
        case .apps:
            return ["open chrome", "launch messages"]
        case .workQueue:
            return ["open work queue", "queue this"]
        case .currentThread:
            return ["open current thread", "what am i doing"]
        case .media:
            return ["what's playing", "pause music"]
        case .capture:
            return ["capture this", "save this for later"]
        case .navigation:
            return ["continue", "take me back to what matters"]
        case .management:
            return ["cancel the timer", "undo that"]
        case .macro:
            return ["focus sprint", "queue sweep"]
        case .teaching:
            return ["teach this as timer", "teach this as search", "teach this as chrome"]
        case .unknown:
            return ["start a five minute timer", "open chrome", "search figma docs", "capture this"]
        }
    }

    static func infer(from transcript: String) -> CompanionCommandDomain {
        let normalized = transcript.lowercased()

        if ["spell", "work spell", "focus mode", "mode"].contains(where: normalized.contains) {
            return .spells
        }
        if ["timer", "countdown", "minutes", "minute", "hours", "hour"].contains(where: normalized.contains) {
            return .timer
        }
        if ["search", "look up", "google", "tab", "docs", "website", "site", "browser"].contains(where: normalized.contains) {
            return .search
        }
        if ["work queue", "queue", "staged work"].contains(where: normalized.contains) {
            return .workQueue
        }
        if ["current thread", "what am i doing", "what am i working on", "thread"].contains(where: normalized.contains) {
            return .currentThread
        }
        if ["music", "song", "playing", "playback", "spotify", "pause", "play"].contains(where: normalized.contains) {
            return .media
        }
        if ["capture", "save this", "remember this", "checkpoint", "queue this"].contains(where: normalized.contains) {
            return .capture
        }
        if ["continue", "resume", "pick up", "back to what i was doing"].contains(where: normalized.contains) {
            return .navigation
        }
        if ["cancel", "stop timer", "clear timer", "undo", "that wasn't right", "not right"].contains(where: normalized.contains) {
            return .management
        }
        if ["teach", "remember this phrase", "when i say"].contains(where: normalized.contains) {
            return .teaching
        }
        if ["open ", "launch ", "switch to ", "bring up ", "pull up "].contains(where: normalized.contains) {
            return .apps
        }
        return .unknown
    }
}

indirect enum CompanionQuickActionKind {
    case chooseSuggestion(originalTranscript: String, suggestedTranscript: String)
    case openSearch(query: String, teachPhrase: String?)
    case openApp(appName: String, teachPhrase: String?)
    case teachIntent(phrase: String, target: CompanionIntentMeaningTarget)
    case showHelp(domain: CompanionCommandDomain)
    case runIntent(intent: CompanionIntent, teachPhrase: String?)
    case noOp
}

struct CompanionQuickAction {
    let title: String
    let detail: String
    let symbol: String
    let kind: CompanionQuickActionKind
    let isEnabled: Bool

    var signature: String {
        "\(title)|\(detail)|\(symbol)|\(isEnabled)"
    }

    var teachesCompanion: Bool {
        switch kind {
        case .chooseSuggestion:
            return true
        case .openSearch(_, let teachPhrase), .openApp(_, let teachPhrase), .runIntent(_, let teachPhrase):
            return teachPhrase?.isEmpty == false
        case .teachIntent:
            return true
        case .showHelp:
            return false
        case .noOp:
            return false
        }
    }
}

extension CompanionIntentAction {
    var defaultDomain: CompanionCommandDomain {
        switch self {
        case .continuePortal:
            return .navigation
        case .openWorkQueue:
            return .workQueue
        case .captureCheckpoint:
            return .capture
        case .openCurrentThread:
            return .currentThread
        case .activateWorkSpell, .removeWorkSpellTasks, .deactivateWorkSpell:
            return .spells
        case .openTimer, .setTimer, .cancelTimer:
            return .timer
        case .openNowPlaying, .togglePlayback:
            return .media
        case .openEntity:
            return .apps
        case .undoLastAction:
            return .management
        case .runMacro:
            return .macro
        case .none:
            return .unknown
        }
    }
}

enum CompanionRitualTarget: String, Codable, CaseIterable {
    case continuePortal = "continue_portal"
    case openWorkQueue = "open_work_queue"
    case captureCheckpoint = "capture_checkpoint"
    case openCurrentThread = "open_current_thread"
    case activateWorkSpell = "activate_work_spell"
    case openTimer = "open_timer"
    case openNowPlaying = "open_now_playing"

    var title: String {
        switch self {
        case .continuePortal:
            return "Teach Continue Phrase"
        case .openWorkQueue:
            return "Teach Work Queue Phrase"
        case .captureCheckpoint:
            return "Teach Capture Phrase"
        case .openCurrentThread:
            return "Teach Current Thread Phrase"
        case .activateWorkSpell:
            return "Teach Work Spell Phrase"
        case .openTimer:
            return "Teach Timer Phrase"
        case .openNowPlaying:
            return "Teach Now Playing Phrase"
        }
    }

    var symbol: String {
        switch self {
        case .continuePortal:
            return "sparkles"
        case .openWorkQueue:
            return "list.bullet.clipboard"
        case .captureCheckpoint:
            return "square.and.arrow.down"
        case .openCurrentThread:
            return "app.badge"
        case .activateWorkSpell:
            return "wand.and.stars"
        case .openTimer:
            return "timer"
        case .openNowPlaying:
            return "music.note"
        }
    }

    var helperDetail: String {
        switch self {
        case .continuePortal:
            return "Give Companion a private shortcut for your smart resume action."
        case .openWorkQueue:
            return "Teach a phrase that always opens Work Queue."
        case .captureCheckpoint:
            return "Teach a phrase that quickly stages the current thread."
        case .openCurrentThread:
            return "Teach a phrase that opens Current Thread."
        case .activateWorkSpell:
            return "Teach a phrase that activates Work Spell."
        case .openTimer:
            return "Teach a phrase that opens Timer."
        case .openNowPlaying:
            return "Teach a phrase that opens Now Playing."
        }
    }

    var action: CompanionIntentAction {
        switch self {
        case .continuePortal:
            return .continuePortal
        case .openWorkQueue:
            return .openWorkQueue
        case .captureCheckpoint:
            return .captureCheckpoint
        case .openCurrentThread:
            return .openCurrentThread
        case .activateWorkSpell:
            return .activateWorkSpell
        case .openTimer:
            return .openTimer
        case .openNowPlaying:
            return .openNowPlaying
        }
    }

    var spokenResponse: String {
        switch self {
        case .continuePortal:
            return "Picking up your thread."
        case .openWorkQueue:
            return "Opening Work Queue."
        case .captureCheckpoint:
            return "Capturing this thread."
        case .openCurrentThread:
            return "Opening Current Thread."
        case .activateWorkSpell:
            return "Opening Work Spell."
        case .openTimer:
            return "Opening Timer."
        case .openNowPlaying:
            return "Opening Now Playing."
        }
    }
}

enum CompanionIntentMeaningTarget: String, Codable, CaseIterable {
    case continuePortal = "continue_portal"
    case openWorkQueue = "open_work_queue"
    case captureCheckpoint = "capture_checkpoint"
    case openCurrentThread = "open_current_thread"
    case activateWorkSpell = "activate_work_spell"
    case openTimer = "open_timer"
    case cancelTimer = "cancel_timer"
    case openNowPlaying = "open_now_playing"
    case togglePlayback = "toggle_playback"
    case undoLastAction = "undo_last_action"

    var title: String {
        switch self {
        case .continuePortal:
            return "Continue"
        case .openWorkQueue:
            return "Work Queue"
        case .captureCheckpoint:
            return "Capture"
        case .openCurrentThread:
            return "Current Thread"
        case .activateWorkSpell:
            return "Work Spell"
        case .openTimer:
            return "Timer"
        case .cancelTimer:
            return "Cancel Timer"
        case .openNowPlaying:
            return "Now Playing"
        case .togglePlayback:
            return "Playback"
        case .undoLastAction:
            return "Undo"
        }
    }

    var helperDetail: String {
        switch self {
        case .continuePortal:
            return "Routes to the portal’s smart resume action."
        case .openWorkQueue:
            return "Always opens Work Queue."
        case .captureCheckpoint:
            return "Captures the current thread into Work Queue."
        case .openCurrentThread:
            return "Opens Current Thread."
        case .activateWorkSpell:
            return "Activates Work Spell and opens the task list."
        case .openTimer:
            return "Opens Timer."
        case .cancelTimer:
            return "Cancels the current timer and clears it."
        case .openNowPlaying:
            return "Opens Now Playing."
        case .togglePlayback:
            return "Toggles playback without opening a page."
        case .undoLastAction:
            return "Reverses the last Companion action when it can."
        }
    }

    var action: CompanionIntentAction {
        switch self {
        case .continuePortal:
            return .continuePortal
        case .openWorkQueue:
            return .openWorkQueue
        case .captureCheckpoint:
            return .captureCheckpoint
        case .openCurrentThread:
            return .openCurrentThread
        case .activateWorkSpell:
            return .activateWorkSpell
        case .openTimer:
            return .openTimer
        case .cancelTimer:
            return .cancelTimer
        case .openNowPlaying:
            return .openNowPlaying
        case .togglePlayback:
            return .togglePlayback
        case .undoLastAction:
            return .undoLastAction
        }
    }

    var spokenResponse: String {
        switch self {
        case .continuePortal:
            return "Picking up your thread."
        case .openWorkQueue:
            return "Opening Work Queue."
        case .captureCheckpoint:
            return "Capturing this thread."
        case .openCurrentThread:
            return "Opening Current Thread."
        case .activateWorkSpell:
            return "Opening Work Spell."
        case .openTimer:
            return "Opening Timer."
        case .cancelTimer:
            return "Canceling the timer."
        case .openNowPlaying:
            return "Opening Now Playing."
        case .togglePlayback:
            return "Toggling playback."
        case .undoLastAction:
            return "Undoing that."
        }
    }

    var acceptedInputExamples: [String] {
        switch self {
        case .continuePortal:
            return ["continue", "resume", "pick up"]
        case .openWorkQueue:
            return ["work queue", "queue", "staged work"]
        case .captureCheckpoint:
            return ["capture", "save this", "remember this"]
        case .openCurrentThread:
            return ["current thread", "thread", "what i'm doing"]
        case .activateWorkSpell:
            return ["work spell", "start work spell", "enter work spell"]
        case .openTimer:
            return ["timer", "countdown"]
        case .cancelTimer:
            return ["cancel timer", "cancel timers", "stop timer", "stop all timers", "clear timer", "cancel all timers"]
        case .openNowPlaying:
            return ["now playing", "music", "song"]
        case .togglePlayback:
            return ["pause", "play", "resume playback"]
        case .undoLastAction:
            return ["undo that", "undo", "that wasn't right", "take that back"]
        }
    }

    static func parse(from text: String) -> CompanionIntentMeaningTarget? {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        for target in allCases {
            if normalized == target.rawValue || normalized == target.title.lowercased() {
                return target
            }
            if target.acceptedInputExamples.contains(where: { normalized == $0 || normalized.contains($0) }) {
                return target
            }
        }

        return nil
    }
}

enum CompanionSemanticOpenBias: String, Codable, CaseIterable {
    case automatic
    case preferApps = "prefer_apps"
    case preferSearch = "prefer_search"

    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .preferApps:
            return "Prefer Apps"
        case .preferSearch:
            return "Prefer Search"
        }
    }
}

enum CompanionPreferredBrowser: String, Codable, CaseIterable {
    case automatic
    case arc
    case chrome
    case safari
    case brave

    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .arc:
            return "Arc"
        case .chrome:
            return "Chrome"
        case .safari:
            return "Safari"
        case .brave:
            return "Brave"
        }
    }

    var appName: String? {
        switch self {
        case .automatic:
            return nil
        case .arc:
            return "Arc"
        case .chrome:
            return "Google Chrome"
        case .safari:
            return "Safari"
        case .brave:
            return "Brave Browser"
        }
    }
}

struct CompanionSemanticPreferences: Codable {
    var openBias: CompanionSemanticOpenBias
    var preferredBrowser: CompanionPreferredBrowser

    static let `default` = CompanionSemanticPreferences(openBias: .automatic, preferredBrowser: .automatic)
}

enum CompanionEntityKind: String, Codable {
    case currentThread = "current_thread"
    case workQueue = "work_queue"
    case timer
    case nowPlaying = "now_playing"
    case app
    case browserTab = "browser_tab"
}

struct CompanionEntityTarget: Codable {
    let kind: CompanionEntityKind
    let displayName: String
    let rawQuery: String?

    init(kind: CompanionEntityKind, displayName: String, rawQuery: String? = nil) {
        self.kind = kind
        self.displayName = displayName
        self.rawQuery = rawQuery
    }
}

struct CompanionIntent {
    let action: CompanionIntentAction
    let durationMinutes: Int?
    let durationSeconds: Int?
    let spokenResponse: String
    let reason: String
    let suggestions: [String]?
    let continueTarget: CompanionContinueTarget?
    let entityTarget: CompanionEntityTarget?
    let macroSteps: [String]?
    let spellTaskSeeds: [String]?
    let domain: CompanionCommandDomain
    let confidence: Double
    let fallbackActions: [CompanionQuickAction]

    init(
        action: CompanionIntentAction,
        durationMinutes: Int?,
        durationSeconds: Int? = nil,
        spokenResponse: String,
        reason: String,
        suggestions: [String]? = nil,
        continueTarget: CompanionContinueTarget? = nil,
        entityTarget: CompanionEntityTarget? = nil,
        macroSteps: [String]? = nil,
        spellTaskSeeds: [String]? = nil,
        domain: CompanionCommandDomain? = nil,
        confidence: Double = 1.0,
        fallbackActions: [CompanionQuickAction] = []
    ) {
        self.action = action
        self.durationMinutes = durationMinutes
        if let durationSeconds {
            self.durationSeconds = durationSeconds
        } else if let durationMinutes {
            self.durationSeconds = durationMinutes * 60
        } else {
            self.durationSeconds = nil
        }
        self.spokenResponse = spokenResponse
        self.reason = reason
        self.suggestions = suggestions
        self.continueTarget = continueTarget
        self.entityTarget = entityTarget
        self.macroSteps = macroSteps
        self.spellTaskSeeds = spellTaskSeeds
        self.domain = domain ?? action.defaultDomain
        self.confidence = confidence
        self.fallbackActions = fallbackActions
    }
}

struct CompanionStateSnapshot: Encodable {
    let timerStage: String
    let timerVisible: Bool
    let queueCount: Int
    let topQueueTitle: String?
    let nowPlayingTitle: String?
    let nowPlayingSource: String
    let nowPlayingState: String
    let hasUndoableAction: Bool
}

enum CompanionConversationRole {
    case user
    case companion

    var prefix: String {
        switch self {
        case .user:
            return "You"
        case .companion:
            return "Companion"
        }
    }
}

struct CompanionConversationTurn {
    let role: CompanionConversationRole
    let text: String

    var renderedLine: String {
        "\(role.prefix): \(text)"
    }
}

enum CompanionContinueTarget: String, Codable {
    case timer
    case workQueue = "work_queue"
    case nowPlaying = "now_playing"

    var displayName: String {
        switch self {
        case .timer:
            return "Timer"
        case .workQueue:
            return "Work Queue"
        case .nowPlaying:
            return "Now Playing"
        }
    }
}

enum CompanionPendingFollowUp {
    case timerDuration
    case continueChoice([CompanionContinueTarget])
    case quickActionChoice([CompanionQuickAction])
    case workSpellDependencyPrompt([String])
}

struct CompanionConversationState {
    private(set) var turns: [CompanionConversationTurn] = []
    var pendingFollowUp: CompanionPendingFollowUp?

    mutating func reset() {
        turns = []
        pendingFollowUp = nil
    }

    mutating func append(role: CompanionConversationRole, text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return
        }

        turns.append(CompanionConversationTurn(role: role, text: cleaned))
        if turns.count > 8 {
            turns = Array(turns.suffix(8))
        }
    }

    var renderedTranscript: String {
        turns.map(\.renderedLine).joined(separator: "\n\n")
    }
}

struct CompanionIntentContext {
    let lastResolvedAction: CompanionIntentAction?
    let lastContinueTarget: CompanionContinueTarget?
    let lastEntityTarget: CompanionEntityTarget?

    var inferredTarget: CompanionContinueTarget? {
        if let lastEntityTarget {
            switch lastEntityTarget.kind {
            case .currentThread:
                return .workQueue
            case .workQueue:
                return .workQueue
            case .timer:
                return .timer
            case .nowPlaying, .browserTab:
                return .nowPlaying
            case .app:
                return nil
            }
        }

        if let lastContinueTarget {
            return lastContinueTarget
        }

        switch lastResolvedAction {
        case .openTimer, .setTimer, .cancelTimer:
            return .timer
        case .openWorkQueue, .captureCheckpoint:
            return .workQueue
        case .openNowPlaying, .togglePlayback:
            return .nowPlaying
        default:
            return nil
        }
    }
}

enum CompanionDurationParser {
    static func parseDurationSeconds(from transcript: String) -> Int? {
        let normalized = transcript
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
        let nsTranscript = normalized as NSString
        let pattern = "(\\d+)\\s*(hour|hours|hr|hrs|minute|minutes|min|mins|second|seconds|sec|secs)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        var totalSeconds = 0
        let matches = regex.matches(in: normalized, options: [], range: NSRange(location: 0, length: nsTranscript.length))
        for match in matches {
            guard match.numberOfRanges == 3 else { continue }
            let valueString = nsTranscript.substring(with: match.range(at: 1))
            let unitString = nsTranscript.substring(with: match.range(at: 2))
            guard let value = Int(valueString) else { continue }
            if unitString.hasPrefix("hour") || unitString.hasPrefix("hr") {
                totalSeconds += value * 3600
            } else if unitString.hasPrefix("second") || unitString.hasPrefix("sec") {
                totalSeconds += value
            } else {
                totalSeconds += value * 60
            }
        }

        if totalSeconds > 0 {
            return min(totalSeconds, (24 * 3600) - 1)
        }

        let tokens = normalized
            .replacingOccurrences(of: "[^a-z0-9\\s]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)

        var index = 0
        while index < tokens.count {
            if let (quantity, consumed) = spokenQuantity(from: tokens, start: index) {
                let unitIndex = index + consumed
                if unitIndex < tokens.count, let multiplier = unitMultiplier(for: tokens[unitIndex]) {
                    totalSeconds += Int((quantity * Double(multiplier)).rounded())
                    index = unitIndex + 1
                    continue
                }
            }
            index += 1
        }

        if totalSeconds > 0 {
            return min(totalSeconds, (24 * 3600) - 1)
        }

        if let (quantity, consumed) = spokenQuantity(from: tokens, start: 0), consumed == tokens.count {
            return min(max(Int(quantity.rounded() * 60), 1), (24 * 3600) - 1)
        }

        if let integerMatch = normalized.range(of: "\\b\\d+\\b", options: .regularExpression),
           let value = Int(normalized[integerMatch]) {
            return min(max(value * 60, 1), (24 * 3600) - 1)
        }

        return nil
    }

    static func parseMinutes(from transcript: String) -> Int? {
        guard let totalSeconds = parseDurationSeconds(from: transcript) else {
            return nil
        }
        return max(Int(ceil(Double(totalSeconds) / 60.0)), 1)
    }

    static func spokenDurationText(totalSeconds: Int) -> String {
        let clamped = max(1, totalSeconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let seconds = clamped % 60
        var parts: [String] = []
        if hours > 0 {
            parts.append("\(hours) hour" + (hours == 1 ? "" : "s"))
        }
        if minutes > 0 {
            parts.append("\(minutes) minute" + (minutes == 1 ? "" : "s"))
        }
        if seconds > 0 {
            parts.append("\(seconds) second" + (seconds == 1 ? "" : "s"))
        }
        if parts.isEmpty {
            return "1 second"
        }
        if parts.count == 1 {
            return parts[0]
        }
        if parts.count == 2 {
            return "\(parts[0]) \(parts[1])"
        }
        return "\(parts[0]) \(parts[1]) \(parts[2])"
    }

    private static func unitMultiplier(for token: String) -> Int? {
        switch token {
        case "hour", "hours", "hr", "hrs":
            return 3600
        case "minute", "minutes", "min", "mins":
            return 60
        case "second", "seconds", "sec", "secs":
            return 1
        default:
            return nil
        }
    }

    private static func spokenQuantity(from tokens: [String], start: Int) -> (Double, Int)? {
        guard start < tokens.count else {
            return nil
        }

        let token = tokens[start]

        if let numeric = Double(token) {
            return (numeric, 1)
        }

        if token == "half" {
            if start + 1 < tokens.count, tokens[start + 1] == "an" {
                return (0.5, 2)
            }
            return (0.5, 1)
        }

        if token == "a" || token == "an" {
            if start + 1 < tokens.count, tokens[start + 1] == "half" {
                return (0.5, 2)
            }
            return (1, 1)
        }

        let ones: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9
        ]
        let teens: [String: Int] = [
            "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
            "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19
        ]
        let tens: [String: Int] = [
            "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
            "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
        ]

        if let teen = teens[token] {
            return (Double(teen), 1)
        }

        if let ten = tens[token] {
            if start + 1 < tokens.count, let one = ones[tokens[start + 1]] {
                return (Double(ten + one), 2)
            }
            return (Double(ten), 1)
        }

        if let one = ones[token] {
            if start + 3 < tokens.count,
               tokens[start + 1] == "and",
               (tokens[start + 2] == "a" || tokens[start + 2] == "an"),
               tokens[start + 3] == "half" {
                return (Double(one) + 0.5, 4)
            }
            if start + 2 < tokens.count,
               tokens[start + 1] == "and",
               tokens[start + 2] == "half" {
                return (Double(one) + 0.5, 3)
            }
            return (Double(one), 1)
        }

        return nil
    }
}

struct CompanionConfiguration: Codable {
    var openAIAPIKey: String?
    var model: String?
    var ollamaBaseURL: String?
    var ollamaModel: String?
    var phraseMemory: [String: [String]]?
    var rituals: [String: String]?
    var appMeanings: [String: String]?
    var ritualFamilies: [String: [String]]?
    var intentMeanings: [String: String]?
    var macros: [String: [String]]?
    var corrections: [String: String]?
    var semanticPreferences: CompanionSemanticPreferences?

    static let empty = CompanionConfiguration(
        openAIAPIKey: nil,
        model: nil,
        ollamaBaseURL: nil,
        ollamaModel: nil,
        phraseMemory: [:],
        rituals: [:],
        appMeanings: [:],
        ritualFamilies: [:],
        intentMeanings: [:],
        macros: [:],
        corrections: [:],
        semanticPreferences: .default
    )
}

enum CompanionSpeechError: LocalizedError {
    case recognizerUnavailable
    case speechNotAuthorized
    case microphoneNotAuthorized
    case noSpeechDetected
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is unavailable on this Mac right now."
        case .speechNotAuthorized:
            return "Companion needs Speech Recognition access in System Settings."
        case .microphoneNotAuthorized:
            return "Companion needs microphone access in System Settings."
        case .noSpeechDetected:
            return "I didn’t catch anything. Try again with a short phrase."
        case .recognitionFailed(let message):
            return message
        }
    }
}

final class CompanionConfigStore {
    private let path: String
    private(set) var current: CompanionConfiguration?

    init(path: String) throws {
        self.path = normalizePath(path)
        try load()
    }

    var effectiveOllamaBaseURL: URL? {
        let environmentURL = ProcessInfo.processInfo.environment["OLLAMA_HOST"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentURL, !environmentURL.isEmpty {
            return URL(string: environmentURL)
        }

        let configuredURL = current?.ollamaBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let configuredURL, !configuredURL.isEmpty {
            return URL(string: configuredURL)
        }

        return URL(string: "http://127.0.0.1:11434")
    }

    var effectiveOllamaModel: String? {
        let environmentModel = ProcessInfo.processInfo.environment["OLLAMA_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentModel, !environmentModel.isEmpty {
            return environmentModel
        }

        let configuredOllamaModel = current?.ollamaModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let configuredOllamaModel, !configuredOllamaModel.isEmpty {
            return configuredOllamaModel
        }

        let legacyModel = current?.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let legacyModel, !legacyModel.isEmpty {
            return legacyModel
        }

        return nil
    }

    func ritualPhrase(for target: CompanionRitualTarget) -> String? {
        ritualPhraseFamilies()[target]?.first
    }

    func ritualPhrases() -> [CompanionRitualTarget: String] {
        var result: [CompanionRitualTarget: String] = [:]
        for (target, phrases) in ritualPhraseFamilies() {
            if let first = phrases.first {
                result[target] = first
            }
        }
        return result
    }

    func ritualPhraseFamilies() -> [CompanionRitualTarget: [String]] {
        var result: [CompanionRitualTarget: [String]] = [:]

        if let legacyRituals = current?.rituals {
            for (rawTarget, phrase) in legacyRituals {
                guard let target = CompanionRitualTarget(rawValue: rawTarget) else {
                    continue
                }
                let cleaned = normalizeLexiconPhrase(phrase)
                if !cleaned.isEmpty {
                    result[target, default: []].append(cleaned)
                }
            }
        }

        if let ritualFamilies = current?.ritualFamilies {
            for (rawTarget, phrases) in ritualFamilies {
                guard let target = CompanionRitualTarget(rawValue: rawTarget) else {
                    continue
                }
                let cleaned = phrases.map(normalizeLexiconPhrase).filter { !$0.isEmpty }
                if !cleaned.isEmpty {
                    result[target, default: []].append(contentsOf: cleaned)
                }
            }
        }

        return result.mapValues { phrases in
            Array(NSOrderedSet(array: phrases).array as? [String] ?? phrases)
        }
    }

    func ritualIntent(for transcript: String) -> CompanionIntent? {
        let normalizedTranscript = normalizeLexiconPhrase(transcript)
        guard !normalizedTranscript.isEmpty else {
            return nil
        }

        for (target, phrases) in ritualPhraseFamilies() where phrases.contains(normalizedTranscript) {
            return CompanionIntent(
                action: target.action,
                durationMinutes: nil,
                spokenResponse: target.spokenResponse,
                reason: "Matched a private Cipher ritual phrase family.",
                confidence: 0.99
            )
        }

        return nil
    }

    func saveRitualPhrase(_ phrase: String, for target: CompanionRitualTarget) throws {
        let normalizedPhrase = normalizeLexiconPhrase(phrase)
        guard normalizedPhrase.count >= 2 else {
            return
        }

        var updated = current ?? .empty
        var ritualFamilies = updated.ritualFamilies ?? [:]
        var phrases = ritualFamilies[target.rawValue] ?? []
        if !phrases.contains(normalizedPhrase) {
            phrases.append(normalizedPhrase)
        }
        ritualFamilies[target.rawValue] = phrases
        updated.ritualFamilies = ritualFamilies

        var rituals = updated.rituals ?? [:]
        if rituals[target.rawValue]?.isEmpty != false {
            rituals[target.rawValue] = normalizedPhrase
        }
        updated.rituals = rituals
        current = updated
        try save()
    }

    func clearAllRitualPhrases() throws {
        guard current?.rituals?.isEmpty == false || current?.ritualFamilies?.isEmpty == false else {
            return
        }
        var updated = current ?? .empty
        updated.rituals = [:]
        updated.ritualFamilies = [:]
        current = updated
        try save()
    }

    func intentMeaningEntries() -> [(phrase: String, target: CompanionIntentMeaningTarget)] {
        guard let intentMeanings = current?.intentMeanings else {
            return []
        }

        return intentMeanings.compactMap { phrase, rawTarget in
            let cleanedPhrase = normalizeLexiconPhrase(phrase)
            guard let target = CompanionIntentMeaningTarget(rawValue: rawTarget), !cleanedPhrase.isEmpty else {
                return nil
            }
            return (cleanedPhrase, target)
        }.sorted { lhs, rhs in
            lhs.phrase < rhs.phrase
        }
    }

    func intentMeaningIntent(for transcript: String) -> CompanionIntent? {
        let normalizedTranscript = normalizeLexiconPhrase(transcript)
        guard !normalizedTranscript.isEmpty else {
            return nil
        }

        let matches = intentMeaningEntries()
            .filter { normalizedTranscript == $0.phrase || normalizedTranscript.contains($0.phrase) }
            .sorted { $0.phrase.count > $1.phrase.count }

        guard let match = matches.first else {
            return nil
        }

        return CompanionIntent(
            action: match.target.action,
            durationMinutes: nil,
            spokenResponse: match.target.spokenResponse,
            reason: "Matched a taught intent meaning for “\(match.phrase)”.",
            confidence: 0.98
        )
    }

    func saveIntentMeaning(phrase: String, target: CompanionIntentMeaningTarget) throws {
        let normalizedPhrase = normalizeLexiconPhrase(phrase)
        guard normalizedPhrase.count >= 2 else {
            return
        }

        var updated = current ?? .empty
        var intentMeanings = updated.intentMeanings ?? [:]
        intentMeanings[normalizedPhrase] = target.rawValue
        updated.intentMeanings = intentMeanings
        current = updated
        try save()
    }

    func clearAllIntentMeanings() throws {
        guard current?.intentMeanings?.isEmpty == false else {
            return
        }
        var updated = current ?? .empty
        updated.intentMeanings = [:]
        current = updated
        try save()
    }

    func macroEntries() -> [(phrase: String, steps: [String])] {
        guard let macros = current?.macros else {
            return []
        }

        return macros.compactMap { phrase, steps in
            let normalizedPhrase = normalizeLexiconPhrase(phrase)
            let normalizedSteps = steps
                .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
                .filter { !$0.isEmpty }
            guard !normalizedPhrase.isEmpty, !normalizedSteps.isEmpty else {
                return nil
            }
            return (normalizedPhrase, normalizedSteps)
        }.sorted { lhs, rhs in
            lhs.phrase < rhs.phrase
        }
    }

    func macroSteps(for transcript: String) -> [String]? {
        let normalizedTranscript = normalizeLexiconPhrase(transcript)
        guard !normalizedTranscript.isEmpty else {
            return nil
        }

        let matches = macroEntries()
            .filter { normalizedTranscript == $0.phrase || normalizedTranscript.contains($0.phrase) }
            .sorted { $0.phrase.count > $1.phrase.count }

        return matches.first?.steps
    }

    func saveMacro(phrase: String, steps: [String]) throws {
        let normalizedPhrase = normalizeLexiconPhrase(phrase)
        let normalizedSteps = steps
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }
        guard normalizedPhrase.count >= 2, !normalizedSteps.isEmpty else {
            return
        }

        var updated = current ?? .empty
        var macros = updated.macros ?? [:]
        macros[normalizedPhrase] = normalizedSteps
        updated.macros = macros
        current = updated
        try save()
    }

    func clearAllMacros() throws {
        guard current?.macros?.isEmpty == false else {
            return
        }
        var updated = current ?? .empty
        updated.macros = [:]
        current = updated
        try save()
    }

    func appMeaningOverrides() -> [String: String] {
        guard let appMeanings = current?.appMeanings else {
            return [:]
        }

        var result: [String: String] = [:]
        for (rawPhrase, appName) in appMeanings {
            let phrase = normalizeLexiconPhrase(rawPhrase)
            let cleanedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !phrase.isEmpty, !cleanedAppName.isEmpty {
                result[phrase] = cleanedAppName
            }
        }
        return result
    }

    func appMeaningOverride(for phrase: String) -> String? {
        appMeaningOverrides()[normalizeLexiconPhrase(phrase)]
    }

    func saveAppMeaning(phrase: String, appName: String) throws {
        let normalizedPhrase = normalizeLexiconPhrase(phrase)
        let cleanedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedPhrase.count >= 2, !cleanedAppName.isEmpty else {
            return
        }

        var updated = current ?? .empty
        var appMeanings = updated.appMeanings ?? [:]
        appMeanings[normalizedPhrase] = cleanedAppName
        updated.appMeanings = appMeanings
        current = updated
        try save()
    }

    func clearAllAppMeanings() throws {
        guard current?.appMeanings?.isEmpty == false else {
            return
        }
        var updated = current ?? .empty
        updated.appMeanings = [:]
        current = updated
        try save()
    }

    func correctionEntries() -> [(phrase: String, replacement: String)] {
        guard let corrections = current?.corrections else {
            return []
        }

        return corrections.compactMap { phrase, replacement in
            let cleanedPhrase = normalizeLexiconPhrase(phrase)
            let cleanedReplacement = normalizeLexiconPhrase(replacement)
            guard !cleanedPhrase.isEmpty, !cleanedReplacement.isEmpty else {
                return nil
            }
            return (cleanedPhrase, cleanedReplacement)
        }.sorted { lhs, rhs in
            lhs.phrase < rhs.phrase
        }
    }

    func applyCorrections(to transcript: String) -> String {
        var corrected = normalizeLexiconPhrase(transcript)
        let corrections = correctionEntries().sorted { $0.phrase.count > $1.phrase.count }
        for correction in corrections where corrected.contains(correction.phrase) {
            corrected = corrected.replacingOccurrences(of: correction.phrase, with: correction.replacement)
        }
        return corrected
    }

    func saveCorrection(phrase: String, replacement: String) throws {
        let normalizedPhrase = normalizeLexiconPhrase(phrase)
        let normalizedReplacement = normalizeLexiconPhrase(replacement)
        guard normalizedPhrase.count >= 2, normalizedReplacement.count >= 2 else {
            return
        }

        var updated = current ?? .empty
        var corrections = updated.corrections ?? [:]
        corrections[normalizedPhrase] = normalizedReplacement
        updated.corrections = corrections
        current = updated
        try save()
    }

    func clearAllCorrections() throws {
        guard current?.corrections?.isEmpty == false else {
            return
        }
        var updated = current ?? .empty
        updated.corrections = [:]
        current = updated
        try save()
    }

    func semanticPreferences() -> CompanionSemanticPreferences {
        current?.semanticPreferences ?? .default
    }

    @discardableResult
    func cycleOpenBiasPreference() throws -> CompanionSemanticPreferences {
        var updated = current ?? .empty
        let currentPreferences = updated.semanticPreferences ?? .default
        let allCases = CompanionSemanticOpenBias.allCases
        let currentIndex = allCases.firstIndex(of: currentPreferences.openBias) ?? 0
        let nextBias = allCases[(currentIndex + 1) % allCases.count]
        updated.semanticPreferences = CompanionSemanticPreferences(
            openBias: nextBias,
            preferredBrowser: currentPreferences.preferredBrowser
        )
        current = updated
        try save()
        return updated.semanticPreferences ?? .default
    }

    @discardableResult
    func cyclePreferredBrowserPreference() throws -> CompanionSemanticPreferences {
        var updated = current ?? .empty
        let currentPreferences = updated.semanticPreferences ?? .default
        let allCases = CompanionPreferredBrowser.allCases
        let currentIndex = allCases.firstIndex(of: currentPreferences.preferredBrowser) ?? 0
        let nextBrowser = allCases[(currentIndex + 1) % allCases.count]
        updated.semanticPreferences = CompanionSemanticPreferences(
            openBias: currentPreferences.openBias,
            preferredBrowser: nextBrowser
        )
        current = updated
        try save()
        return updated.semanticPreferences ?? .default
    }

    func learnedPhrases() -> [CompanionIntentAction: [String]] {
        guard let phraseMemory = current?.phraseMemory else {
            return [:]
        }

        var result: [CompanionIntentAction: [String]] = [:]
        for (rawAction, phrases) in phraseMemory {
            guard let action = CompanionIntentAction(rawValue: rawAction) else {
                continue
            }

            let cleaned = phrases
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }

            if !cleaned.isEmpty {
                result[action] = cleaned
            }
        }
        return result
    }

    func rememberPhrase(_ phrase: String, for action: CompanionIntentAction) {
        guard action != .none else {
            return
        }

        let normalizedPhrase = phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard normalizedPhrase.count >= 3 else {
            return
        }

        var updated = current ?? .empty
        var phraseMemory = updated.phraseMemory ?? [:]
        var phrases = phraseMemory[action.rawValue] ?? []
        guard !phrases.contains(normalizedPhrase) else {
            return
        }

        phrases.insert(normalizedPhrase, at: 0)
        phraseMemory[action.rawValue] = Array(phrases.prefix(12))
        updated.phraseMemory = phraseMemory
        current = updated

        do {
            try save()
        } catch {
            fputs("Companion phrase memory save failed: \(error.localizedDescription)\n", stderr)
        }
    }

    private func load() throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        guard FileManager.default.fileExists(atPath: url.path) else {
            current = nil
            return
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            current = nil
            return
        }

        current = try JSONDecoder().decode(CompanionConfiguration.self, from: data)
    }

    private func save() throws {
        let url = URL(fileURLWithPath: path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(current)
        try data.write(to: url, options: [.atomic])
    }

    private func normalizeLexiconPhrase(_ phrase: String) -> String {
        phrase
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

final class CompanionSpeechRecognizer: NSObject, @unchecked Sendable {
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var forceFinalizeRecognition: (() -> Void)?
    private static let contextualPhrases = [
        "Inlay",
        "Companion",
        "Current Thread",
        "Work Queue",
        "Now Playing",
        "continue",
        "capture this",
        "save this",
        "open work queue",
        "open current thread",
        "open now playing",
        "set a timer",
        "five minute timer",
        "ten minute timer",
        "twenty minute timer",
        "one hour timer",
        "open timer",
        "open chrome",
        "open safari",
        "open figma",
        "open spotify",
        "open music",
        "search figma docs",
        "search github",
        "search canva docs",
        "search linear docs",
        "start a five minute timer",
        "start a one minute thirty second timer",
        "timer for ninety seconds",
        "cancel timer",
        "undo that",
        "teach this as timer",
        "teach this as search",
        "help",
        "companion help",
        "open companion help",
        "open current thread",
        "open work queue",
        "what's playing",
        "pause music",
        "play music"
    ]

    var needsAuthorizationPrompt: Bool {
        SFSpeechRecognizer.authorizationStatus() == .notDetermined
            || AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
    }

    var isCapturing: Bool {
        recognitionRequest != nil || recognitionTask != nil
    }

    func requestAuthorizationIfNeeded() async throws {
        guard recognizer != nil else {
            throw CompanionSpeechError.recognizerUnavailable
        }

        let speechAuthorized = await requestSpeechAuthorization()
        guard speechAuthorized else {
            throw CompanionSpeechError.speechNotAuthorized
        }

        let microphoneAuthorized = await requestMicrophoneAuthorization()
        guard microphoneAuthorized else {
            throw CompanionSpeechError.microphoneNotAuthorized
        }
    }

    func captureSingleUtterance(onPartialResult: (@Sendable (String) -> Void)? = nil) async throws -> String {
        try await requestAuthorizationIfNeeded()
        return try await withCheckedThrowingContinuation { continuation in
            startRecognition(continuation: continuation, onPartialResult: onPartialResult)
        }
    }

    func captureAuthorizedUtterance(onPartialResult: (@Sendable (String) -> Void)? = nil) async throws -> String {
        guard recognizer != nil else {
            throw CompanionSpeechError.recognizerUnavailable
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw CompanionSpeechError.speechNotAuthorized
        }

        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw CompanionSpeechError.microphoneNotAuthorized
        }

        return try await withCheckedThrowingContinuation { continuation in
            startRecognition(continuation: continuation, onPartialResult: onPartialResult)
        }
    }

    func cancel() {
        cleanupRecognition()
    }

    func finishCurrentUtterance() {
        forceFinalizeRecognition?()
    }

    private func requestSpeechAuthorization() async -> Bool {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        switch currentStatus {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch currentStatus {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func startRecognition(
        continuation: CheckedContinuation<String, Error>,
        onPartialResult: (@Sendable (String) -> Void)?
    ) {
        cleanupRecognition()

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        recognitionRequest.contextualStrings = Self.contextualPhrases
        self.recognitionRequest = recognitionRequest

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        var hasCompleted = false
        var bestTranscript = ""
        var silenceWorkItem: DispatchWorkItem?
        var timeoutWorkItem: DispatchWorkItem?
        var finalizeWorkItem: DispatchWorkItem?
        var hasRequestedFinalResult = false
        var firstTranscriptDate: Date?
        var lastReportedTranscript = ""
        var lastPartialResultAt: Date?
        let captureStartedAt = Date()

        let complete: (Result<String, Error>) -> Void = { [weak self] result in
            guard !hasCompleted else { return }
            hasCompleted = true
            silenceWorkItem?.cancel()
            timeoutWorkItem?.cancel()
            finalizeWorkItem?.cancel()
            self?.forceFinalizeRecognition = nil
            self?.cleanupRecognition()
            continuation.resume(with: result)
        }

        let finishWithBestTranscript = {
            let transcript = self.bestSpeechTranscriptCandidate(from: bestTranscript).trimmingCharacters(in: .whitespacesAndNewlines)
            if transcript.isEmpty {
                complete(.failure(CompanionSpeechError.noSpeechDetected))
            } else {
                complete(.success(transcript))
            }
        }

        let requestFinalResult: (TimeInterval) -> Void = { settleFloor in
            guard !hasCompleted, !hasRequestedFinalResult else { return }
            hasRequestedFinalResult = true

            let now = Date()
            let timeSinceLastPartial = lastPartialResultAt.map { now.timeIntervalSince($0) } ?? now.timeIntervalSince(captureStartedAt)
            let settleDelay = max(0, settleFloor - timeSinceLastPartial)

            finalizeWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                finishWithBestTranscript()
            }
            finalizeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24 + settleDelay, execute: workItem)

            self.recognitionRequest?.endAudio()
            if self.audioEngine.isRunning {
                self.audioEngine.stop()
            }
            self.audioEngine.inputNode.removeTap(onBus: 0)
        }

        forceFinalizeRecognition = {
            requestFinalResult(0.18)
        }

        let rescheduleSilenceTimeout = {
            silenceWorkItem?.cancel()
            let now = Date()
            let elapsedSinceFirstTranscript = firstTranscriptDate.map { now.timeIntervalSince($0) } ?? 0
            let delay = max(1.45, 2.2 - min(elapsedSinceFirstTranscript, 0.9))
            let workItem = DispatchWorkItem {
                requestFinalResult(0.05)
            }
            silenceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        timeoutWorkItem = DispatchWorkItem {
            requestFinalResult(0.0)
        }
        if let timeoutWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.5, execute: timeoutWorkItem)
        }

        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result {
                let candidateTranscript = self.bestSpeechTranscriptCandidate(from: result.bestTranscription.formattedString)
                if self.shouldReplaceSpeechTranscriptCandidate(current: bestTranscript, with: candidateTranscript) {
                    bestTranscript = candidateTranscript
                }
                let cleanedPartial = candidateTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                if firstTranscriptDate == nil, !cleanedPartial.isEmpty {
                    firstTranscriptDate = Date()
                }
                if !cleanedPartial.isEmpty {
                    lastPartialResultAt = Date()
                }
                if let onPartialResult, !cleanedPartial.isEmpty, cleanedPartial != lastReportedTranscript {
                    lastReportedTranscript = cleanedPartial
                    onPartialResult(cleanedPartial)
                }
                rescheduleSilenceTimeout()
                if result.isFinal {
                    finishWithBestTranscript()
                    return
                }
            }

            if let error {
                let transcript = self.bestSpeechTranscriptCandidate(from: bestTranscript).trimmingCharacters(in: .whitespacesAndNewlines)
                if transcript.isEmpty {
                    complete(.failure(CompanionSpeechError.recognitionFailed(error.localizedDescription)))
                } else {
                    complete(.success(transcript))
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            complete(.failure(CompanionSpeechError.recognitionFailed(error.localizedDescription)))
        }
    }

    private func cleanupRecognition() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        forceFinalizeRecognition = nil
    }

    private func shouldReplaceSpeechTranscriptCandidate(current: String, with candidate: String) -> Bool {
        let cleanedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedCandidate.isEmpty else {
            return false
        }
        guard !cleanedCurrent.isEmpty else {
            return true
        }

        let currentScore = speechTranscriptConfidenceScore(cleanedCurrent)
        let candidateScore = speechTranscriptConfidenceScore(cleanedCandidate)
        if candidateScore > currentScore + 0.08 {
            return true
        }
        if abs(candidateScore - currentScore) <= 0.08, cleanedCandidate.count > cleanedCurrent.count {
            return true
        }
        return false
    }

    private func bestSpeechTranscriptCandidate(from transcript: String) -> String {
        transcript
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "\\bin lay\\b", with: "inlay", options: .regularExpression)
            .replacingOccurrences(of: "\\bwork cue\\b", with: "work queue", options: .regularExpression)
            .replacingOccurrences(of: "\\bcurrent threat\\b", with: "current thread", options: .regularExpression)
            .replacingOccurrences(of: "\\bwhat's\\b", with: "what is", options: .regularExpression)
            .replacingOccurrences(of: "\\b(um|uh|erm|hmm)\\b", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func speechTranscriptConfidenceScore(_ transcript: String) -> Double {
        let normalized = transcript.lowercased()
        let tokens = normalized.split(separator: " ")
        var score = Double(tokens.count) * 0.12

        let verbs = ["open", "search", "look", "start", "set", "cancel", "pause", "play", "capture", "save", "continue", "resume", "undo", "help", "teach"]
        if verbs.contains(where: normalized.contains) {
            score += 0.6
        }

        let domainTerms = ["timer", "work queue", "current thread", "now playing", "music", "spotify", "chrome", "safari", "figma", "support", "search"]
        if domainTerms.contains(where: normalized.contains) {
            score += 0.7
        }

        if CompanionDurationParser.parseDurationSeconds(from: normalized) != nil {
            score += 0.8
        }

        if normalized.hasSuffix(" for") || normalized.hasSuffix(" to") || normalized.hasSuffix(" as") || normalized.hasSuffix(" on") {
            score -= 0.35
        }

        return score
    }
}

@MainActor
final class CompanionVoiceResponder: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        completion?.resume()
        completion = nil
    }

    func speak(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return
        }

        stop()
        let utterance = makeUtterance(for: cleaned)
        synthesizer.speak(utterance)
    }

    func speakAndWait(_ text: String) async {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return
        }

        stop()
        let utterance = makeUtterance(for: cleaned)

        await withCheckedContinuation { continuation in
            completion = continuation
            synthesizer.speak(utterance)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.completion?.resume()
            self?.completion = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.completion?.resume()
            self?.completion = nil
        }
    }

    private func makeUtterance(for text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.46
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.voice = preferredVoice()
        return utterance
    }

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let englishVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en")
        }

        let preferredNames = [
            "Samantha",
            "Allison",
            "Ava",
            "Karen",
            "Moira",
            "Daniel"
        ]

        for preferredName in preferredNames {
            if let voice = englishVoices
                .filter({ $0.name == preferredName })
                .max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
                return voice
            }
        }

        if let highestQualityEnglishVoice = englishVoices.max(by: {
            if $0.quality.rawValue == $1.quality.rawValue {
                return $0.name > $1.name
            }
            return $0.quality.rawValue < $1.quality.rawValue
        }) {
            return highestQualityEnglishVoice
        }

        return AVSpeechSynthesisVoice(language: "en-US")
    }
}

enum CompanionIntentParserError: LocalizedError {
    case invalidResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Companion returned an unreadable response."
        case .transport(let message):
            return message
        }
    }
}

private struct OllamaTagsResponse: Decodable {
    struct ModelEntry: Decodable {
        let name: String
    }

    let models: [ModelEntry]
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}

private struct OllamaCompanionIntentPayload: Decodable {
    let action: String
    let durationMinutes: Int?
    let durationSeconds: Int?
    let spokenResponse: String?
    let reason: String?
    let continueTarget: String?
    let entityKind: String?
    let entityDisplayName: String?
    let entityRawQuery: String?
}

@MainActor
final class CompanionIntentParser {
    private let configStore: CompanionConfigStore
    private let session: URLSession
    private let localIntentModel = CompanionLocalIntentModel()
    private let entityEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
    private var cachedOllamaModelName: String?
    private var didAttemptOllamaDiscovery = false

    init(configStore: CompanionConfigStore, session: URLSession = .shared) {
        self.configStore = configStore
        self.session = session
    }

    func parseIntent(transcript: String, snapshot: CompanionStateSnapshot, context: CompanionIntentContext?) async -> CompanionIntent {
        let normalizedTranscript = normalizeTranscript(transcript)
        let correctedTranscript = configStore.applyCorrections(to: normalizedTranscript)
        let learnedExamples = makeLearnedExamples()

        if let ritualIntent = configStore.ritualIntent(for: correctedTranscript) {
            configStore.rememberPhrase(correctedTranscript, for: ritualIntent.action)
            return ritualIntent
        }

        if let macroIntent = parseMacroIntent(transcript: correctedTranscript) {
            return macroIntent
        }

        if let taughtIntent = configStore.intentMeaningIntent(for: correctedTranscript) {
            configStore.rememberPhrase(correctedTranscript, for: taughtIntent.action)
            return taughtIntent
        }

        if let entityIntent = parseExplicitEntityIntent(transcript: correctedTranscript) {
            if entityIntent.action != .none {
                configStore.rememberPhrase(correctedTranscript, for: entityIntent.action)
            }
            return entityIntent
        }

        if let contextual = parseContextually(transcript: correctedTranscript, snapshot: snapshot, context: context) {
            if contextual.action != .none {
                configStore.rememberPhrase(correctedTranscript, for: contextual.action)
            }
            return contextual
        }

        let earlyHeuristic = refineConfidence(
            for: parseHeuristically(transcript: correctedTranscript, snapshot: snapshot),
            transcript: correctedTranscript
        )
        if earlyHeuristic.action == .activateWorkSpell
            || earlyHeuristic.action == .removeWorkSpellTasks
            || earlyHeuristic.action == .deactivateWorkSpell {
            configStore.rememberPhrase(correctedTranscript, for: earlyHeuristic.action)
            return earlyHeuristic
        }

        if let ollamaIntent = await parseWithOllama(transcript: correctedTranscript, snapshot: snapshot, context: context) {
            return refineConfidence(for: ollamaIntent, transcript: correctedTranscript)
        }

        if let parsed = localIntentModel.parse(transcript: correctedTranscript, snapshot: snapshot, learnedExamples: learnedExamples) {
            return refineConfidence(for: parsed, transcript: correctedTranscript)
        }

        let heuristic = earlyHeuristic.action == .none
            ? refineConfidence(for: parseHeuristically(transcript: correctedTranscript, snapshot: snapshot), transcript: correctedTranscript)
            : earlyHeuristic
        if heuristic.action != .none {
            return heuristic
        }

        let suggestions = localIntentModel.suggestions(transcript: correctedTranscript, snapshot: snapshot, learnedExamples: learnedExamples, limit: 2)
        let inferredDomain = inferDomain(for: correctedTranscript)
        let spokenResponse: String
        if suggestions.count >= 2 {
            spokenResponse = "Maybe try “\(suggestions[0])” or “\(suggestions[1])”."
        } else if let suggestion = suggestions.first {
            spokenResponse = "Maybe try “\(suggestion)”."
        } else {
            spokenResponse = "Try “continue”, “open work queue”, or “set a timer for 20 minutes.”"
        }

        return CompanionIntent(
            action: .none,
            durationMinutes: nil,
            spokenResponse: spokenResponse,
            reason: "No supported action matched.",
            suggestions: suggestions,
            domain: inferredDomain,
            confidence: 0.18,
            fallbackActions: fallbackActionsForUnknownTranscript(
                transcript: correctedTranscript,
                suggestions: suggestions,
                domain: inferredDomain,
                snapshot: snapshot
            )
        )
    }

    private func refineConfidence(for intent: CompanionIntent, transcript: String) -> CompanionIntent {
        guard intent.action != .none else {
            return intent
        }

        let threshold: Double
        switch intent.action {
        case .setTimer, .cancelTimer, .undoLastAction:
            threshold = 0.76
        case .openEntity:
            threshold = 0.86
        case .togglePlayback, .continuePortal:
            threshold = 0.8
        default:
            threshold = 0.78
        }

        guard intent.confidence < threshold else {
            return intent
        }

        let fallbacks = lowConfidenceFallbackActions(for: intent, transcript: transcript)
        guard !fallbacks.isEmpty else {
            return intent
        }

        return CompanionIntent(
            action: intent.action,
            durationMinutes: intent.durationMinutes,
            spokenResponse: "I’m not fully confident. Pick the closest match.",
            reason: intent.reason,
            suggestions: intent.suggestions,
            continueTarget: intent.continueTarget,
            entityTarget: intent.entityTarget,
            macroSteps: intent.macroSteps,
            spellTaskSeeds: intent.spellTaskSeeds,
            domain: intent.domain,
            confidence: intent.confidence,
            fallbackActions: fallbacks
        )
    }

    private func inferDomain(for transcript: String) -> CompanionCommandDomain {
        CompanionCommandDomain.infer(from: transcript)
    }

    private func fallbackActionsForUnknownTranscript(
        transcript: String,
        suggestions: [String],
        domain: CompanionCommandDomain,
        snapshot: CompanionStateSnapshot
    ) -> [CompanionQuickAction] {
        let normalized = normalizeTranscript(transcript)
        var actions: [CompanionQuickAction] = []

        switch domain {
        case .timer:
            actions.append(makeTeachIntentAction(
                phrase: normalized,
                target: .openTimer,
                title: "Open Timer",
                detail: "Use Timer for requests like this next time.",
                symbol: "timer"
            ))
        case .workQueue:
            actions.append(makeTeachIntentAction(
                phrase: normalized,
                target: .openWorkQueue,
                title: "Open Work Queue",
                detail: "Treat this like a Work Queue request.",
                symbol: "list.bullet.clipboard"
            ))
            actions.append(makeTeachIntentAction(
                phrase: normalized,
                target: .captureCheckpoint,
                title: "Capture This",
                detail: "Treat this like a capture request next time.",
                symbol: "tray.and.arrow.down"
            ))
        case .currentThread:
            actions.append(makeTeachIntentAction(
                phrase: normalized,
                target: .openCurrentThread,
                title: "Open Current Thread",
                detail: "Treat this like a Current Thread request.",
                symbol: "sparkles"
            ))
        case .media:
            actions.append(makeTeachIntentAction(
                phrase: normalized,
                target: .openNowPlaying,
                title: "Open Now Playing",
                detail: "Treat this like a media request.",
                symbol: "music.note"
            ))
            actions.append(makeTeachIntentAction(
                phrase: normalized,
                target: .togglePlayback,
                title: "Toggle Playback",
                detail: "Treat this like a playback command.",
                symbol: "playpause"
            ))
        case .spells:
            actions.append(makeTeachIntentAction(
                phrase: normalized,
                target: .activateWorkSpell,
                title: "Open Work Spell",
                detail: "Treat this like a Work Spell request.",
                symbol: "wand.and.stars"
            ))
        case .capture:
            actions.append(makeTeachIntentAction(
                phrase: normalized,
                target: .captureCheckpoint,
                title: "Capture This",
                detail: "Save the current thread and remember that meaning.",
                symbol: "tray.and.arrow.down"
            ))
        case .management:
            if snapshot.timerStage != "setting" {
                actions.append(
                    CompanionQuickAction(
                        title: "Cancel Timer",
                        detail: "Stop the current timer and clear it.",
                        symbol: "xmark.circle",
                        kind: .runIntent(
                            intent: CompanionIntent(
                                action: .cancelTimer,
                                durationMinutes: nil,
                                spokenResponse: "Canceling the timer.",
                                reason: "Used a management fallback to cancel the timer.",
                                domain: .management,
                                confidence: 0.96
                            ),
                            teachPhrase: normalized
                        ),
                        isEnabled: true
                    )
                )
            }
            if snapshot.hasUndoableAction {
                actions.append(
                    CompanionQuickAction(
                        title: "Undo Last Action",
                        detail: "Reverse the last Companion change if it can be undone.",
                        symbol: "arrow.uturn.backward.circle",
                        kind: .runIntent(
                            intent: CompanionIntent(
                                action: .undoLastAction,
                                durationMinutes: nil,
                                spokenResponse: "Undoing that.",
                                reason: "Used a management fallback to undo the last action.",
                                domain: .management,
                                confidence: 0.96
                            ),
                            teachPhrase: normalized
                        ),
                        isEnabled: true
                    )
                )
            }
        case .navigation:
            actions.append(makeTeachIntentAction(
                phrase: normalized,
                target: .continuePortal,
                title: "Continue",
                detail: "Resume the most relevant live thing and remember it.",
                symbol: "arrowshape.turn.up.forward"
            ))
        case .apps, .search, .unknown, .macro, .teaching:
            break
        }

        if let targetPhrase = extractOpenTargetPhrase(from: normalized) ?? (domain == .search ? cleanedBrowserQuery(normalized) : nil) {
            actions.append(contentsOf: ambiguousOpenFallbackActions(for: targetPhrase))
        }

        if actions.isEmpty {
            actions.append(contentsOf: suggestionFallbackActions(originalTranscript: normalized, suggestions: suggestions))
        }

        if actions.isEmpty, !normalized.isEmpty {
            actions.append(
                CompanionQuickAction(
                    title: "Search “\(normalized)”",
                    detail: "Open a fresh browser search and remember that choice.",
                    symbol: "magnifyingglass",
                    kind: .openSearch(query: normalized, teachPhrase: normalized),
                    isEnabled: true
                )
            )
        }

        return Array(actions.prefix(3))
    }

    private func lowConfidenceFallbackActions(for intent: CompanionIntent, transcript: String) -> [CompanionQuickAction] {
        let normalized = normalizeTranscript(transcript)
        var actions: [CompanionQuickAction] = []

        switch intent.action {
        case .setTimer:
            if let durationSeconds = intent.durationSeconds, durationSeconds > 0 {
                let spokenDuration = CompanionDurationParser.spokenDurationText(totalSeconds: durationSeconds)
                actions.append(
                    CompanionQuickAction(
                        title: "Start \(spokenDuration) timer",
                        detail: "Run the timer and remember this pattern if helpful.",
                        symbol: "timer",
                        kind: .runIntent(intent: intent, teachPhrase: nil),
                        isEnabled: true
                    )
                )
                actions.append(makeTeachIntentAction(
                    phrase: normalized,
                    target: .openTimer,
                    title: "Open Timer Instead",
                    detail: "Treat this more like a timer-view request.",
                    symbol: "clock.arrow.circlepath"
                ))
            }
        case .openTimer:
            actions.append(
                CompanionQuickAction(
                    title: "Open Timer",
                    detail: "Use Timer for this request now.",
                    symbol: "timer",
                    kind: .runIntent(intent: intent, teachPhrase: normalized),
                    isEnabled: true
                )
            )
        case .activateWorkSpell:
            actions.append(
                CompanionQuickAction(
                    title: "Open Work Spell",
                    detail: "Open the task spell and remember this phrasing.",
                    symbol: "wand.and.stars",
                    kind: .runIntent(intent: intent, teachPhrase: normalized),
                    isEnabled: true
                )
            )
        case .removeWorkSpellTasks:
            actions.append(
                CompanionQuickAction(
                    title: "Remove From Work Spell",
                    detail: "Delete the matching task from the spell now.",
                    symbol: "minus.circle",
                    kind: .runIntent(intent: intent, teachPhrase: nil),
                    isEnabled: true
                )
            )
        case .deactivateWorkSpell:
            actions.append(
                CompanionQuickAction(
                    title: "Stop Work Spell",
                    detail: "Turn off the hidden Work Spell routing.",
                    symbol: "moon.zzz",
                    kind: .runIntent(intent: intent, teachPhrase: nil),
                    isEnabled: true
                )
            )
        case .openWorkQueue:
            actions.append(
                CompanionQuickAction(
                    title: "Open Work Queue",
                    detail: "Show the queue now and remember that meaning.",
                    symbol: "list.bullet.clipboard",
                    kind: .runIntent(intent: intent, teachPhrase: normalized),
                    isEnabled: true
                )
            )
            actions.append(makeTeachIntentAction(
                phrase: normalized,
                target: .captureCheckpoint,
                title: "Capture This",
                detail: "Save the current thread instead.",
                symbol: "tray.and.arrow.down"
            ))
        case .captureCheckpoint:
            actions.append(
                CompanionQuickAction(
                    title: "Capture This",
                    detail: "Save the current thread to Work Queue now.",
                    symbol: "tray.and.arrow.down",
                    kind: .runIntent(intent: intent, teachPhrase: normalized),
                    isEnabled: true
                )
            )
            actions.append(makeTeachIntentAction(
                phrase: normalized,
                target: .openWorkQueue,
                title: "Open Work Queue",
                detail: "Show the queue instead of capturing.",
                symbol: "list.bullet.clipboard"
            ))
        case .openCurrentThread:
            actions.append(
                CompanionQuickAction(
                    title: "Open Current Thread",
                    detail: "Show what you’re doing now and remember it.",
                    symbol: "sparkles",
                    kind: .runIntent(intent: intent, teachPhrase: normalized),
                    isEnabled: true
                )
            )
            actions.append(makeTeachIntentAction(
                phrase: normalized,
                target: .captureCheckpoint,
                title: "Capture This",
                detail: "Save the thread instead.",
                symbol: "tray.and.arrow.down"
            ))
        case .openNowPlaying:
            actions.append(
                CompanionQuickAction(
                    title: "Open Now Playing",
                    detail: "Show media now and remember it.",
                    symbol: "music.note",
                    kind: .runIntent(intent: intent, teachPhrase: normalized),
                    isEnabled: true
                )
            )
            actions.append(makeTeachIntentAction(
                phrase: normalized,
                target: .togglePlayback,
                title: "Toggle Playback",
                detail: "Treat this like a play/pause command instead.",
                symbol: "playpause"
            ))
        case .togglePlayback:
            actions.append(
                CompanionQuickAction(
                    title: "Toggle Playback",
                    detail: "Update playback now and remember it.",
                    symbol: "playpause",
                    kind: .runIntent(intent: intent, teachPhrase: normalized),
                    isEnabled: true
                )
            )
            actions.append(makeTeachIntentAction(
                phrase: normalized,
                target: .openNowPlaying,
                title: "Open Now Playing",
                detail: "Show the media card instead.",
                symbol: "music.note"
            ))
        case .cancelTimer:
            actions.append(
                CompanionQuickAction(
                    title: "Cancel Timer",
                    detail: "Stop the current timer and clear it now.",
                    symbol: "xmark.circle",
                    kind: .runIntent(intent: intent, teachPhrase: normalized),
                    isEnabled: true
                )
            )
            actions.append(
                CompanionQuickAction(
                    title: "Open Timer Instead",
                    detail: "Show Timer without canceling it.",
                    symbol: "timer",
                    kind: .runIntent(
                        intent: CompanionIntent(
                            action: .openTimer,
                            durationMinutes: nil,
                            spokenResponse: "Opening Timer.",
                            reason: "Used a management fallback to open Timer instead.",
                            domain: .timer,
                            confidence: 0.95
                        ),
                        teachPhrase: nil
                    ),
                    isEnabled: true
                )
            )
        case .undoLastAction:
            actions.append(
                CompanionQuickAction(
                    title: "Undo Last Action",
                    detail: "Reverse the most recent Companion change.",
                    symbol: "arrow.uturn.backward.circle",
                    kind: .runIntent(intent: intent, teachPhrase: normalized),
                    isEnabled: true
                )
            )
        case .continuePortal:
            actions.append(
                CompanionQuickAction(
                    title: "Continue",
                    detail: "Resume the most relevant live thing now.",
                    symbol: "arrowshape.turn.up.forward",
                    kind: .runIntent(intent: intent, teachPhrase: normalized),
                    isEnabled: true
                )
            )
        case .openEntity:
            if let target = intent.entityTarget {
                switch target.kind {
                case .app:
                    actions.append(
                        CompanionQuickAction(
                            title: "Open \(target.displayName)",
                            detail: "Open the app and remember that meaning.",
                            symbol: "macwindow",
                            kind: .openApp(appName: target.displayName, teachPhrase: normalized),
                            isEnabled: true
                        )
                    )
                    let query = target.rawQuery ?? target.displayName
                    actions.append(
                        CompanionQuickAction(
                            title: "Search “\(query)”",
                            detail: "Open a browser search instead.",
                            symbol: "magnifyingglass",
                            kind: .openSearch(query: query, teachPhrase: normalized),
                            isEnabled: true
                        )
                    )
                case .browserTab:
                    let query = target.rawQuery ?? target.displayName
                    actions.append(
                        CompanionQuickAction(
                            title: "Search “\(query)”",
                            detail: "Open a fresh browser search and remember it.",
                            symbol: "magnifyingglass",
                            kind: .openSearch(query: query, teachPhrase: normalized),
                            isEnabled: true
                        )
                    )
                case .currentThread, .workQueue, .timer, .nowPlaying:
                    actions.append(
                        CompanionQuickAction(
                            title: "Open \(target.displayName)",
                            detail: "Use that surface now and remember it.",
                            symbol: intent.domain.symbol,
                            kind: .runIntent(intent: intent, teachPhrase: normalized),
                            isEnabled: true
                        )
                    )
                }
            }
        case .runMacro, .none:
            break
        }

        if actions.isEmpty, let firstSuggestion = intent.suggestions?.first {
            actions.append(
                CompanionQuickAction(
                    title: "Use “\(firstSuggestion)”",
                    detail: "Route it that way and remember it.",
                    symbol: "arrow.turn.down.right",
                    kind: .chooseSuggestion(originalTranscript: normalized, suggestedTranscript: firstSuggestion),
                    isEnabled: true
                )
            )
        }

        return Array(actions.prefix(3))
    }

    private func suggestionFallbackActions(originalTranscript: String, suggestions: [String]) -> [CompanionQuickAction] {
        suggestions.prefix(2).map { suggestion in
            CompanionQuickAction(
                title: "Use “\(suggestion)”",
                detail: "Route this request that way and remember it.",
                symbol: "arrow.turn.down.right",
                kind: .chooseSuggestion(
                    originalTranscript: originalTranscript,
                    suggestedTranscript: suggestion
                ),
                isEnabled: true
            )
        }
    }

    private func makeTeachIntentAction(
        phrase: String,
        target: CompanionIntentMeaningTarget,
        title: String,
        detail: String,
        symbol: String
    ) -> CompanionQuickAction {
        CompanionQuickAction(
            title: title,
            detail: detail,
            symbol: symbol,
            kind: .teachIntent(phrase: phrase, target: target),
            isEnabled: true
        )
    }

    private func parseMacroIntent(transcript: String) -> CompanionIntent? {
        guard let macroSteps = configStore.macroSteps(for: transcript), !macroSteps.isEmpty else {
            return nil
        }

        return CompanionIntent(
            action: .runMacro,
            durationMinutes: nil,
            spokenResponse: "Running your macro.",
            reason: "Matched a taught macro phrase.",
            macroSteps: macroSteps,
            domain: .macro,
            confidence: 0.99
        )
    }

    private func parseWithOllama(
        transcript: String,
        snapshot: CompanionStateSnapshot,
        context: CompanionIntentContext?
    ) async -> CompanionIntent? {
        guard let baseURL = configStore.effectiveOllamaBaseURL,
              let modelName = await resolvedOllamaModelName(baseURL: baseURL) else {
            return nil
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 2.5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = makeOllamaPrompt(transcript: transcript, snapshot: snapshot, context: context)
        let body: [String: Any] = [
            "model": modelName,
            "prompt": prompt,
            "stream": false,
            "format": "json"
        ]

        guard JSONSerialization.isValidJSONObject(body) else {
            return nil
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            let ollamaResponse = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            let payloadData = Data(ollamaResponse.response.utf8)
            let payload = try JSONDecoder().decode(OllamaCompanionIntentPayload.self, from: payloadData)
            return makeCompanionIntent(from: payload, transcript: transcript)
        } catch {
            return nil
        }
    }

    private func resolvedOllamaModelName(baseURL: URL) async -> String? {
        if let cachedOllamaModelName, !cachedOllamaModelName.isEmpty {
            return cachedOllamaModelName
        }

        if let configuredModel = configStore.effectiveOllamaModel {
            cachedOllamaModelName = configuredModel
            return configuredModel
        }

        guard !didAttemptOllamaDiscovery else {
            return nil
        }

        didAttemptOllamaDiscovery = true
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 1.5

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }
            let tags = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            let firstModel = tags.models.first?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let firstModel, !firstModel.isEmpty {
                cachedOllamaModelName = firstModel
                return firstModel
            }
        } catch {
            return nil
        }

        return nil
    }

    private func makeOllamaPrompt(
        transcript: String,
        snapshot: CompanionStateSnapshot,
        context: CompanionIntentContext?
    ) -> String {
        let lastAction = context?.lastResolvedAction?.rawValue ?? "none"
        let lastContinueTarget = context?.lastContinueTarget?.rawValue ?? "none"
        let lastEntity = context?.lastEntityTarget?.displayName ?? "none"
        let runningApps = NSWorkspace.shared.runningApplications
            .compactMap(\.localizedName)
            .filter { !$0.isEmpty }
            .sorted()
        let appList = runningApps.prefix(24).joined(separator: ", ")

        return """
        You are a local intent router for a macOS headphone-control app.
        Return ONLY valid JSON with these keys:
        action, durationMinutes, durationSeconds, spokenResponse, reason, continueTarget, entityKind, entityDisplayName, entityRawQuery

        Allowed action values:
        continue_portal, open_work_queue, capture_checkpoint, open_current_thread, open_timer, set_timer, cancel_timer, open_now_playing, toggle_playback, open_entity, undo_last_action, none

        Allowed continueTarget values:
        timer, work_queue, now_playing, null

        Allowed entityKind values:
        app, browser_tab, current_thread, work_queue, timer, now_playing, null

        Rules:
        - Prefer opening an app when the user clearly names an app like chrome, safari, spotify, messages, figma, xcode, finder.
        - Prefer browser_tab when the user mentions tab, docs, github, issue, repo, page, site, search, browser context, or gives a multi-word web-style target.
        - Ignore filler words like the, to, for, me, please, on chrome, in safari, using brave.
        - If the user says "open chrome", output open_entity with entityKind app and entityDisplayName Google Chrome.
        - If the user says "open the canvas tab on chrome", output open_entity with entityKind browser_tab and entityRawQuery canvas.
        - If the user says "open a new tab for figma docs", output open_entity with entityKind browser_tab and entityRawQuery figma docs.
        - If the user says "cancel timer" or "stop the timer", output cancel_timer.
        - If the user says "undo that" or "that wasn't right", output undo_last_action.
        - If the user gives seconds, preserve them in durationSeconds.
        - If unsure, choose the single best action instead of explaining.

        Current portal state:
        timerStage: \(snapshot.timerStage)
        queueCount: \(snapshot.queueCount)
        topQueueTitle: \(snapshot.topQueueTitle ?? "none")
        nowPlayingTitle: \(snapshot.nowPlayingTitle ?? "none")
        nowPlayingSource: \(snapshot.nowPlayingSource)
        nowPlayingState: \(snapshot.nowPlayingState)
        hasUndoableAction: \(snapshot.hasUndoableAction)

        Recent context:
        lastAction: \(lastAction)
        lastContinueTarget: \(lastContinueTarget)
        lastEntity: \(lastEntity)

        Running apps:
        \(appList)

        User request:
        \(transcript)
        """
    }

    private func makeCompanionIntent(from payload: OllamaCompanionIntentPayload, transcript: String) -> CompanionIntent? {
        let normalizedAction = payload.action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let action = CompanionIntentAction(rawValue: normalizedAction) else {
            return nil
        }

        let continueTarget = payload.continueTarget.flatMap { CompanionContinueTarget(rawValue: $0) }
        var entityTarget: CompanionEntityTarget?
        if let rawKind = payload.entityKind?.trimmingCharacters(in: .whitespacesAndNewlines),
           let entityKind = CompanionEntityKind(rawValue: rawKind) {
            let displayName = payload.entityDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawQuery = payload.entityRawQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
            entityTarget = CompanionEntityTarget(
                kind: entityKind,
                displayName: (displayName?.isEmpty == false ? displayName! : rawQuery) ?? prettifyEntityName(transcript),
                rawQuery: rawQuery
            )
        }

        let spokenResponse = payload.spokenResponse?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = payload.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain: CompanionCommandDomain
        if entityTarget?.kind == .browserTab {
            domain = .search
        } else {
            domain = action.defaultDomain
        }

        return CompanionIntent(
            action: action,
            durationMinutes: payload.durationMinutes,
            durationSeconds: payload.durationSeconds,
            spokenResponse: (spokenResponse?.isEmpty == false ? spokenResponse! : CompanionLocalIntentModel.defaultSpokenResponse(for: action)),
            reason: (reason?.isEmpty == false ? reason! : "Resolved by local Ollama model."),
            suggestions: nil,
            continueTarget: continueTarget,
            entityTarget: entityTarget,
            domain: domain,
            confidence: 0.78
        )
    }

    private func parseHeuristically(transcript: String, snapshot: CompanionStateSnapshot) -> CompanionIntent {
        let normalized = transcript.lowercased()
        let mentionsSpellList = containsAny(normalized, ["todo", "to do", "task list", "checklist", "work spell", "spell list"])

        let tasksToRemove = mentionsSpellList ? WorkSpellTaskParser.taskTitlesForRemovalCommand(from: transcript) : []
        if !tasksToRemove.isEmpty {
            let spokenResponse = tasksToRemove.count == 1
                ? "Removing that from Work Spell."
                : "Removing those from Work Spell."
            return CompanionIntent(
                action: .removeWorkSpellTasks,
                durationMinutes: nil,
                spokenResponse: spokenResponse,
                reason: "Asked to remove task text from Work Spell.",
                suggestions: nil,
                spellTaskSeeds: tasksToRemove,
                domain: .spells,
                confidence: 0.94
            )
        }

        let tasksToAdd = mentionsSpellList ? WorkSpellTaskParser.taskTitlesForAddCommand(from: transcript) : []
        if !tasksToAdd.isEmpty {
            let spokenResponse = tasksToAdd.count == 1
                ? "Adding that to Work Spell."
                : "Adding those to Work Spell."
            return CompanionIntent(
                action: .activateWorkSpell,
                durationMinutes: nil,
                spokenResponse: spokenResponse,
                reason: "Asked to add task text into Work Spell.",
                suggestions: nil,
                spellTaskSeeds: tasksToAdd,
                domain: .spells,
                confidence: 0.94
            )
        }

        if containsAny(normalized, ["stop work spell", "end work spell", "leave work spell", "exit work spell", "turn off work spell", "deactivate work spell"]) {
            return CompanionIntent(
                action: .deactivateWorkSpell,
                durationMinutes: nil,
                spokenResponse: "Turning off Work Spell.",
                reason: "Asked to deactivate Work Spell.",
                suggestions: nil,
                domain: .spells,
                confidence: 0.94
            )
        }

        if normalized.contains("work spell") {
            let seedTasks = WorkSpellTaskParser.taskTitles(from: transcript)
            let spokenResponse: String
            if seedTasks.isEmpty {
                spokenResponse = "Setting up Work Spell."
            } else if seedTasks.count == 1 {
                spokenResponse = "Setting up Work Spell with 1 task."
            } else {
                spokenResponse = "Setting up Work Spell with \(seedTasks.count) tasks."
            }
            return CompanionIntent(
                action: .activateWorkSpell,
                durationMinutes: nil,
                spokenResponse: spokenResponse,
                reason: "Asked to activate Work Spell.",
                suggestions: nil,
                spellTaskSeeds: seedTasks,
                domain: .spells,
                confidence: 0.94
            )
        }

        if containsAny(normalized, ["undo that", "undo", "that wasn't right", "that was not right", "take that back", "revert that"]) {
            return CompanionIntent(
                action: .undoLastAction,
                durationMinutes: nil,
                spokenResponse: "Undoing that.",
                reason: "Asked to undo the last Companion action.",
                suggestions: nil,
                domain: .management,
                confidence: 0.9
            )
        }

        if containsAny(normalized, ["cancel timer", "cancel timers", "stop timer", "stop all timers", "clear timer", "cancel all timers", "clear all timers", "cancel countdown", "stop countdown"]) {
            return CompanionIntent(
                action: .cancelTimer,
                durationMinutes: nil,
                spokenResponse: normalized.contains("all")
                    ? "Inlay only keeps one timer, so I’m canceling it."
                    : "Canceling the timer.",
                reason: "Asked to cancel the timer.",
                suggestions: nil,
                domain: .management,
                confidence: 0.92
            )
        }

        if normalized.contains("how much time") || normalized.contains("time left") || normalized.contains("time remaining") {
            return CompanionIntent(action: .openTimer, durationMinutes: nil, spokenResponse: "Opening Timer.", reason: "Asked about remaining time.", suggestions: nil, domain: .timer, confidence: 0.88)
        }

        if normalized.contains("what's playing") || normalized.contains("what is playing") || normalized.contains("now playing") {
            return CompanionIntent(action: .openNowPlaying, durationMinutes: nil, spokenResponse: "Opening Now Playing.", reason: "Asked about current music.", suggestions: nil, domain: .media, confidence: 0.9)
        }

        if normalized.contains("current thread") || normalized.contains("what am i doing") || normalized.contains("what am i working on") {
            return CompanionIntent(action: .openCurrentThread, durationMinutes: nil, spokenResponse: "Opening Current Thread.", reason: "Asked for the current thread.", suggestions: nil, domain: .currentThread, confidence: 0.9)
        }

        if normalized.contains("pause") || normalized.contains("resume music") || normalized.contains("play music") || normalized.contains("pause music") {
            return CompanionIntent(action: .togglePlayback, durationMinutes: nil, spokenResponse: "Toggling playback.", reason: "Asked to control playback.", suggestions: nil, domain: .media, confidence: 0.86)
        }

        if let totalSeconds = CompanionDurationParser.parseDurationSeconds(from: normalized),
           normalized.contains("timer") {
            let spokenDuration = CompanionDurationParser.spokenDurationText(totalSeconds: totalSeconds)
            return CompanionIntent(action: .setTimer, durationMinutes: CompanionDurationParser.parseMinutes(from: normalized), durationSeconds: totalSeconds, spokenResponse: "Starting a \(spokenDuration) timer.", reason: "Asked to set a timer.", suggestions: nil, domain: .timer, confidence: 0.9)
        }

        if normalized.contains("timer") {
            return CompanionIntent(action: .openTimer, durationMinutes: nil, spokenResponse: "Opening Timer.", reason: "Asked for the timer.", suggestions: nil, domain: .timer, confidence: 0.82)
        }

        if normalized.contains("work queue") || normalized == "queue" || normalized.contains("open queue") {
            return CompanionIntent(action: .openWorkQueue, durationMinutes: nil, spokenResponse: "Opening Work Queue.", reason: "Asked for Work Queue.", suggestions: nil, domain: .workQueue, confidence: 0.86)
        }

        if normalized.contains("checkpoint") || normalized.contains("capture this") || normalized.contains("save this") || normalized.contains("remember this") {
            return CompanionIntent(action: .captureCheckpoint, durationMinutes: nil, spokenResponse: "Capturing this thread.", reason: "Asked to save the current thread.", suggestions: nil, domain: .capture, confidence: 0.84)
        }

        if normalized.contains("continue") || normalized.contains("resume") || normalized.contains("back to what i was doing") || normalized.contains("pick up where i left off") {
            let spokenResponse: String
            if snapshot.timerStage == "running" || snapshot.timerStage == "paused" || snapshot.timerStage == "finished" {
                spokenResponse = "Taking you back to Timer."
            } else if snapshot.queueCount > 0 {
                spokenResponse = "Picking up your top thread."
            } else if snapshot.nowPlayingSource != "None" {
                spokenResponse = "Taking you to Now Playing."
            } else {
                spokenResponse = "I’ll try your next best option."
            }
            return CompanionIntent(action: .continuePortal, durationMinutes: nil, spokenResponse: spokenResponse, reason: "Asked to continue.", suggestions: nil, domain: .navigation, confidence: 0.82)
        }

        let domain = inferDomain(for: normalized)
        return CompanionIntent(
            action: .none,
            durationMinutes: nil,
            spokenResponse: "I didn’t map that to a portal action yet.",
            reason: "No supported action matched.",
            suggestions: nil,
            domain: domain,
            confidence: 0.18,
            fallbackActions: fallbackActionsForUnknownTranscript(
                transcript: normalized,
                suggestions: [],
                domain: domain,
                snapshot: snapshot
            )
        )
    }

    private func parseExplicitEntityIntent(transcript: String) -> CompanionIntent? {
        let normalized = transcript.lowercased()

        if let tabQuery = extractBrowserTabQuery(from: normalized) {
            return CompanionIntent(
                action: .openEntity,
                durationMinutes: nil,
                spokenResponse: "Searching for that.",
                reason: "Detected a browser-search request.",
                entityTarget: CompanionEntityTarget(kind: .browserTab, displayName: tabQuery, rawQuery: tabQuery),
                domain: .search,
                confidence: 0.96
            )
        }

        guard let targetPhrase = extractOpenTargetPhrase(from: normalized) else {
            return nil
        }

        if let surfaceTarget = resolveSurfaceTarget(from: targetPhrase) {
            let action: CompanionIntentAction
            switch surfaceTarget.kind {
            case .currentThread:
                action = .openCurrentThread
            case .workQueue:
                action = .openWorkQueue
            case .timer:
                action = .openTimer
            case .nowPlaying:
                action = .openNowPlaying
            case .app, .browserTab:
                action = .openEntity
            }

            return CompanionIntent(
                action: action,
                durationMinutes: nil,
                spokenResponse: "Opening \(surfaceTarget.displayName).",
                reason: "Detected an explicit portal-surface target.",
                entityTarget: surfaceTarget,
                confidence: 0.95
            )
        }

        let cleanedTarget = cleanedMeaningfulTargetPhrase(targetPhrase)
        guard cleanedTarget.count >= 2 else {
            return nil
        }

        if let exactAppTarget = exactAppTarget(for: cleanedTarget) {
            return CompanionIntent(
                action: .openEntity,
                durationMinutes: nil,
                spokenResponse: "Opening \(exactAppTarget.displayName).",
                reason: "Detected an explicit app target.",
                entityTarget: exactAppTarget,
                domain: .apps,
                confidence: 0.97
            )
        }

        if cleanedTarget.split(separator: " ").count == 1 {
            let appName = prettifyEntityName(cleanedTarget)
            return CompanionIntent(
                action: .none,
                durationMinutes: nil,
                spokenResponse: "I’m not sure whether you mean the app or a search.",
                reason: "Single-word open requests are ambiguous without a taught meaning.",
                domain: .apps,
                confidence: 0.24,
                fallbackActions: ambiguousOpenFallbackActions(for: cleanedTarget, preferredAppName: appName)
            )
        }

        if let resolvedTarget = resolveDynamicEntityTarget(from: cleanedTarget) {
            let action: CompanionIntentAction
            switch resolvedTarget.kind {
            case .currentThread:
                action = .openCurrentThread
            case .workQueue:
                action = .openWorkQueue
            case .timer:
                action = .openTimer
            case .nowPlaying:
                action = .openNowPlaying
            case .app, .browserTab:
                action = .openEntity
            }

            let spokenResponse = resolvedTarget.kind == .browserTab
                ? "Searching for that."
                : "Opening \(resolvedTarget.displayName)."
            let resolvedDomain: CompanionCommandDomain = resolvedTarget.kind == .browserTab ? .search : .apps

            return CompanionIntent(
                action: action,
                durationMinutes: nil,
                spokenResponse: spokenResponse,
                reason: "Resolved the target with on-device semantic matching.",
                entityTarget: resolvedTarget,
                domain: resolvedDomain,
                confidence: resolvedTarget.kind == .browserTab ? 0.88 : 0.84
            )
        }

        let appName = prettifyEntityName(cleanedTarget)
        return CompanionIntent(
            action: .none,
            durationMinutes: nil,
            spokenResponse: "I need a cleaner guess there.",
            reason: "Could not confidently resolve an explicit open target.",
            domain: .apps,
            confidence: 0.22,
            fallbackActions: ambiguousOpenFallbackActions(for: cleanedTarget, preferredAppName: appName)
        )
    }

    private func ambiguousOpenFallbackActions(
        for phrase: String,
        preferredAppName: String? = nil
    ) -> [CompanionQuickAction] {
        let cleanedPhrase = cleanedMeaningfulTargetPhrase(phrase)
        guard !cleanedPhrase.isEmpty else {
            return []
        }

        let appName = preferredAppName ?? prettifyEntityName(cleanedPhrase)
        let searchAction = CompanionQuickAction(
            title: "Search “\(cleanedPhrase)”",
            detail: "Open a fresh search tab and remember that choice.",
            symbol: "magnifyingglass",
            kind: .openSearch(query: cleanedPhrase, teachPhrase: cleanedPhrase),
            isEnabled: true
        )
        let appAction = CompanionQuickAction(
            title: "Open \(appName)",
            detail: "Open the app and remember that meaning.",
            symbol: "macwindow",
            kind: .openApp(appName: appName, teachPhrase: cleanedPhrase),
            isEnabled: true
        )

        let preferences = configStore.semanticPreferences()
        switch preferences.openBias {
        case .preferApps:
            return [appAction, searchAction]
        case .preferSearch:
            return [searchAction, appAction]
        case .automatic:
            return cleanedPhrase.split(separator: " ").count >= 2
                ? [searchAction, appAction]
                : [appAction, searchAction]
        }
    }

    private func exactAppTarget(for phrase: String) -> CompanionEntityTarget? {
        let cleanedPhrase = cleanedMeaningfulTargetPhrase(phrase)
        guard !cleanedPhrase.isEmpty else {
            return nil
        }

        if let preferredAppName = configStore.appMeaningOverride(for: cleanedPhrase) {
            return CompanionEntityTarget(kind: .app, displayName: preferredAppName, rawQuery: preferredAppName)
        }

        let normalizedPhrase = normalizeSemanticPhrase(cleanedPhrase)
        for (target, candidatePhrase) in dynamicEntityCandidates() {
            guard target.kind == .app else {
                continue
            }
            if normalizeSemanticPhrase(candidatePhrase) == normalizedPhrase {
                return target
            }
        }

        return nil
    }

    private func parseContextually(
        transcript: String,
        snapshot: CompanionStateSnapshot,
        context: CompanionIntentContext?
    ) -> CompanionIntent? {
        guard let context else {
            return nil
        }

        let normalized = transcript.lowercased()
        let inferredTarget = context.inferredTarget
        let hasSpellContext: Bool = {
            switch context.lastResolvedAction {
            case .activateWorkSpell, .removeWorkSpellTasks, .deactivateWorkSpell:
                return true
            default:
                return false
            }
        }()

        if hasSpellContext {
            if let requestedMode = WorkSpellTaskParser.requestedMode(from: transcript) {
                return CompanionIntent(
                    action: .activateWorkSpell,
                    durationMinutes: nil,
                    spokenResponse: requestedMode == .ordered
                        ? "Switching Work Spell to ordered."
                        : "Switching Work Spell to unordered.",
                    reason: "Used recent Work Spell context to change structure mode.",
                    suggestions: nil,
                    domain: .spells,
                    confidence: 0.92
                )
            }

            let tasksToRemove = WorkSpellTaskParser.taskTitlesForRemovalCommand(from: transcript)
            if !tasksToRemove.isEmpty {
                return CompanionIntent(
                    action: .removeWorkSpellTasks,
                    durationMinutes: nil,
                    spokenResponse: tasksToRemove.count == 1
                        ? "Removing that from Work Spell."
                        : "Removing those from Work Spell.",
                    reason: "Used recent Work Spell context to remove task text.",
                    suggestions: nil,
                    spellTaskSeeds: tasksToRemove,
                    domain: .spells,
                    confidence: 0.92
                )
            }

            let tasksToAdd = WorkSpellTaskParser.taskTitlesForAddCommand(from: transcript)
            if !tasksToAdd.isEmpty {
                return CompanionIntent(
                    action: .activateWorkSpell,
                    durationMinutes: nil,
                    spokenResponse: tasksToAdd.count == 1
                        ? "Adding that to Work Spell."
                        : "Adding those to Work Spell.",
                    reason: "Used recent Work Spell context to append task text.",
                    suggestions: nil,
                    spellTaskSeeds: tasksToAdd,
                    domain: .spells,
                    confidence: 0.92
                )
            }
        }

        if contextualContainsAny(normalized, ["undo that", "undo", "that wasn't right", "that was not right", "take that back", "revert that"]) {
            return CompanionIntent(
                action: .undoLastAction,
                durationMinutes: nil,
                spokenResponse: "Undoing that.",
                reason: "Used recent action context to undo the last Companion change.",
                suggestions: nil,
                domain: .management,
                confidence: 0.9
            )
        }

        if contextualContainsAny(normalized, ["cancel it", "stop it", "clear it", "cancel that", "stop that", "clear that"]),
           inferredTarget == .timer || snapshot.timerStage == "running" || snapshot.timerStage == "paused" || snapshot.timerStage == "finished" {
            return CompanionIntent(
                action: .cancelTimer,
                durationMinutes: nil,
                spokenResponse: "Canceling the timer.",
                reason: "Used recent timer context to cancel the timer.",
                suggestions: nil,
                domain: .management,
                confidence: 0.86
            )
        }

        if contextualContainsAny(normalized, ["open it", "show it", "bring it up", "pull it up", "take me there", "open that", "show that"]),
           let lastEntityTarget = context.lastEntityTarget {
            let action: CompanionIntentAction
            switch lastEntityTarget.kind {
            case .currentThread:
                action = .openCurrentThread
            case .workQueue:
                action = .openWorkQueue
            case .timer:
                action = .openTimer
            case .nowPlaying:
                action = .openNowPlaying
            case .app, .browserTab:
                action = .openEntity
            }

            return CompanionIntent(
                action: action,
                durationMinutes: nil,
                spokenResponse: "Opening \(lastEntityTarget.displayName).",
                reason: "Used recent entity context.",
                entityTarget: lastEntityTarget,
                domain: lastEntityTarget.kind == .browserTab ? .search : action.defaultDomain,
                confidence: 0.88
            )
        }

        if contextualContainsAny(normalized, ["open it", "show it", "bring it up", "pull it up", "take me there", "open that", "show that"]) {
            switch inferredTarget {
            case .timer:
                return CompanionIntent(action: .openTimer, durationMinutes: nil, spokenResponse: "Opening Timer.", reason: "Used recent timer context.", suggestions: nil, domain: .timer, confidence: 0.82)
            case .workQueue:
                return CompanionIntent(action: .openWorkQueue, durationMinutes: nil, spokenResponse: "Opening Work Queue.", reason: "Used recent work queue context.", suggestions: nil, domain: .workQueue, confidence: 0.82)
            case .nowPlaying:
                return CompanionIntent(action: .openNowPlaying, durationMinutes: nil, spokenResponse: "Opening Now Playing.", reason: "Used recent music context.", suggestions: nil, domain: .media, confidence: 0.82)
            case .none:
                break
            }
        }

        if contextualContainsAny(normalized, ["pause it", "play it", "resume it", "stop it"]) {
            if inferredTarget == .nowPlaying || snapshot.nowPlayingSource != "None" {
                return CompanionIntent(action: .togglePlayback, durationMinutes: nil, spokenResponse: "Toggling playback.", reason: "Used recent playback context.", suggestions: nil, domain: .media, confidence: 0.84)
            }
        }

        if contextualContainsAny(normalized, ["queue it", "save it", "remember it", "capture it", "save that", "remember that"]) {
            return CompanionIntent(action: .captureCheckpoint, durationMinutes: nil, spokenResponse: "Capturing this thread.", reason: "Used recent capture context.", suggestions: nil, domain: .capture, confidence: 0.84)
        }

        return nil
    }

    private func contextualContainsAny(_ transcript: String, _ needles: [String]) -> Bool {
        needles.contains { transcript.contains($0) }
    }

    private func makeLearnedExamples() -> [CompanionIntentTrainingExample] {
        let learned = configStore.learnedPhrases().flatMap { action, phrases in
            phrases.map { phrase in
                CompanionIntentTrainingExample(
                    action: action,
                    phrase: phrase,
                    spokenResponse: CompanionLocalIntentModel.defaultSpokenResponse(for: action),
                    reason: "Matched a phrase you taught Companion."
                )
            }
        }

        let taughtIntentMeanings = configStore.intentMeaningEntries().map { entry in
            CompanionIntentTrainingExample(
                action: entry.target.action,
                phrase: entry.phrase,
                spokenResponse: entry.target.spokenResponse,
                reason: "Matched a taught intent meaning."
            )
        }

        return learned + taughtIntentMeanings
    }

    private func normalizeTranscript(_ transcript: String) -> String {
        transcript
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "\\bin lay\\b", with: "inlay", options: .regularExpression)
            .replacingOccurrences(of: "\\bwork cue\\b", with: "work queue", options: .regularExpression)
            .replacingOccurrences(of: "\\bcurrent threat\\b", with: "current thread", options: .regularExpression)
            .replacingOccurrences(of: "\\bwhat's\\b", with: "what is", options: .regularExpression)
            .replacingOccurrences(of: "\\b(um|uh|erm|hmm)\\b", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractOpenTargetPhrase(from transcript: String) -> String? {
        let prefixes = [
            "can you open ",
            "could you open ",
            "please open ",
            "can you launch ",
            "could you launch ",
            "please launch ",
            "can you resume ",
            "could you resume ",
            "please resume ",
            "can you switch to ",
            "could you switch to ",
            "please switch to ",
            "can you go to ",
            "could you go to ",
            "please go to ",
            "can you show ",
            "could you show ",
            "please show ",
            "can you bring up ",
            "could you bring up ",
            "please bring up ",
            "can you pull up ",
            "could you pull up ",
            "please pull up ",
            "can you take me to ",
            "could you take me to ",
            "please take me to ",
            "open ",
            "launch ",
            "resume ",
            "switch to ",
            "go to ",
            "show ",
            "bring up ",
            "pull up ",
            "take me to "
        ]

        guard let prefix = prefixes.first(where: { transcript.hasPrefix($0) }) else {
            return nil
        }

        var candidate = String(transcript.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for filler in ["me ", "the ", "my ", "app ", "page ", "feature "] {
            if candidate.hasPrefix(filler) {
                candidate.removeFirst(filler.count)
                candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if candidate.hasSuffix(" for me") {
            candidate = String(candidate.dropLast(" for me".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if candidate.hasPrefix("tab ") {
            return nil
        }

        let cleanedCandidate = cleanedMeaningfulTargetPhrase(candidate)
        return cleanedCandidate.isEmpty ? nil : cleanedCandidate
    }

    private func extractBrowserTabQuery(from transcript: String) -> String? {
        let capturePatterns = [
            #"^(?:can you |could you |please )?(?:open|show|find|bring up|pull up|go to|take me to) (?:me )?(?:a |an |the )?(?:new )?tab(?: for)? (.+)$"#,
            #"^(?:can you |could you |please )?(?:open|show|find|bring up|pull up|go to|take me to) (.+?) tab$"#,
            #"^(?:new tab|tab) (.+)$"#,
            #"^(?:search for|search|look up) (.+)$"#
        ]

        for pattern in capturePatterns {
            if let query = firstRegexCapture(in: transcript, pattern: pattern) {
                let cleaned = cleanedBrowserQuery(query)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }

        return nil
    }

    private func firstRegexCapture(in transcript: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(transcript.startIndex..., in: transcript)
        guard let match = regex.firstMatch(in: transcript, options: [], range: range),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: transcript) else {
            return nil
        }

        return String(transcript[captureRange])
    }

    private func cleanedBrowserQuery(_ rawQuery: String) -> String {
        var cleaned = rawQuery
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let wrappers = [
            "a new tab for ",
            "an new tab for ",
            "the new tab for ",
            "new tab for ",
            "a tab for ",
            "the tab for ",
            "tab for ",
            "a new tab ",
            "new tab ",
            "a tab ",
            "the tab ",
            "tab "
        ]

        for wrapper in wrappers {
            if cleaned.hasPrefix(wrapper) {
                cleaned.removeFirst(wrapper.count)
                cleaned = cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                break
            }
        }

        cleaned = stripBrowserContextSuffixes(from: cleaned)
        return cleanedMeaningfulTargetPhrase(cleaned)
    }

    private func cleanedMeaningfulTargetPhrase(_ rawPhrase: String) -> String {
        let normalized = stripBrowserContextSuffixes(from: rawPhrase)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        guard !normalized.isEmpty else {
            return ""
        }

        let stopWords: Set<String> = [
            "a", "an", "the", "to", "for", "me", "my", "please", "that", "this", "up"
        ]

        let tokens = normalized
            .split(separator: " ")
            .map(String.init)

        let meaningfulTokens = tokens.filter { token in
            !stopWords.contains(token.lowercased())
        }

        if meaningfulTokens.isEmpty {
            return normalized
        }

        return meaningfulTokens.joined(separator: " ")
    }

    private func stripBrowserContextSuffixes(from phrase: String) -> String {
        var cleaned = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixPatterns = [
            #"\s+(?:on|in|using)\s+(?:google\s+chrome|chrome|safari|arc|brave(?:\s+browser)?)$"#,
            #"\s+inside\s+(?:google\s+chrome|chrome|safari|arc|brave(?:\s+browser)?)$"#
        ]

        for pattern in suffixPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveDynamicEntityTarget(from phrase: String) -> CompanionEntityTarget? {
        let cleanedPhrase = cleanedMeaningfulTargetPhrase(phrase)
        guard !cleanedPhrase.isEmpty else {
            return nil
        }

        if let preferredAppName = configStore.appMeaningOverride(for: cleanedPhrase) {
            return CompanionEntityTarget(kind: .app, displayName: preferredAppName, rawQuery: preferredAppName)
        }

        if shouldPreferBrowserQuery(for: cleanedPhrase) {
            return CompanionEntityTarget(kind: .browserTab, displayName: cleanedPhrase, rawQuery: cleanedPhrase)
        }

        let normalizedPhrase = normalizeSemanticPhrase(cleanedPhrase)
        let phraseTokens = Set(normalizedPhrase.split(separator: " ").map(String.init))
        var bestMatch: (target: CompanionEntityTarget, score: Double)?

        for (target, candidatePhrase) in dynamicEntityCandidates() {
            let normalizedCandidate = normalizeSemanticPhrase(candidatePhrase)
            let candidateTokens = Set(normalizedCandidate.split(separator: " ").map(String.init))

            var score = 0.0
            if normalizedCandidate == normalizedPhrase {
                score += 1.2
            } else if normalizedCandidate.contains(normalizedPhrase) || normalizedPhrase.contains(normalizedCandidate) {
                score += 0.72
            }

            if !phraseTokens.isEmpty {
                let overlap = Double(phraseTokens.intersection(candidateTokens).count)
                score += overlap / Double(max(phraseTokens.count, 1)) * 0.65
            }

            if let entityEmbedding {
                let distance = entityEmbedding.distance(between: normalizedPhrase, and: normalizedCandidate, distanceType: .cosine)
                score += max(0, 1.0 - (distance / 2.0)) * 0.75
            }

            if let currentBest = bestMatch {
                if score > currentBest.score {
                    bestMatch = (target, score)
                }
            } else {
                bestMatch = (target, score)
            }
        }

        if let bestMatch, bestMatch.score >= 0.92 {
            return bestMatch.target
        }

        if configStore.semanticPreferences().openBias == .preferApps,
           cleanedPhrase.split(separator: " ").count == 1 {
            return CompanionEntityTarget(kind: .app, displayName: prettifyEntityName(cleanedPhrase), rawQuery: cleanedPhrase)
        }

        if cleanedPhrase.split(separator: " ").count >= 2 {
            return CompanionEntityTarget(kind: .browserTab, displayName: cleanedPhrase, rawQuery: cleanedPhrase)
        }

        return nil
    }

    private func dynamicEntityCandidates() -> [(CompanionEntityTarget, String)] {
        var candidates: [(CompanionEntityTarget, String)] = []
        let appAliases: [String: [String]] = [
            "Google Chrome": ["chrome", "google chrome"],
            "Brave Browser": ["brave", "brave browser"],
            "Safari": ["safari"],
            "Arc": ["arc"],
            "Spotify": ["spotify"],
            "Messages": ["messages", "message"],
            "Finder": ["finder"],
            "Figma": ["figma"],
            "Xcode": ["xcode"],
            "Cursor": ["cursor"],
            "Terminal": ["terminal"],
            "Notes": ["notes"],
            "Calculator": ["calculator"]
        ]

        for (displayName, aliases) in appAliases {
            let target = CompanionEntityTarget(kind: .app, displayName: displayName, rawQuery: displayName)
            candidates.append((target, displayName))
            aliases.forEach { alias in
                candidates.append((target, alias))
            }
        }

        for (phrase, appName) in configStore.appMeaningOverrides() {
            let target = CompanionEntityTarget(kind: .app, displayName: appName, rawQuery: appName)
            candidates.append((target, phrase))
            candidates.append((target, appName))
        }

        for runningApp in NSWorkspace.shared.runningApplications.compactMap(\.localizedName) {
            let target = CompanionEntityTarget(kind: .app, displayName: runningApp, rawQuery: runningApp)
            candidates.append((target, runningApp))
        }

        return candidates
    }

    private func shouldPreferBrowserQuery(for phrase: String) -> Bool {
        let preferences = configStore.semanticPreferences()
        switch preferences.openBias {
        case .preferApps:
            return false
        case .preferSearch:
            return phrase.split(separator: " ").count >= 2
        case .automatic:
            break
        }

        let lowered = phrase.lowercased()
        let browserHints = [
            "docs", "documentation", "github", "issue", "issues", "tab", "site", "search",
            "page", "repo", "repository", "article", "guide", "help", "reference", "manual"
        ]
        return browserHints.contains { lowered.contains($0) }
    }

    private func normalizeSemanticPhrase(_ phrase: String) -> String {
        phrase
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveSurfaceTarget(from phrase: String) -> CompanionEntityTarget? {
        if phrase.contains("current thread") || phrase.contains("thread") {
            return CompanionEntityTarget(kind: .currentThread, displayName: "Current Thread")
        }
        if phrase.contains("work queue") || phrase == "queue" || phrase.contains("queue") {
            return CompanionEntityTarget(kind: .workQueue, displayName: "Work Queue")
        }
        if phrase.contains("timer") || phrase.contains("countdown") {
            return CompanionEntityTarget(kind: .timer, displayName: "Timer")
        }
        if phrase.contains("now playing") || phrase.contains("music") || phrase.contains("song") {
            return CompanionEntityTarget(kind: .nowPlaying, displayName: "Now Playing")
        }
        return nil
    }

    private func prettifyEntityName(_ phrase: String) -> String {
        phrase
            .split(separator: " ")
            .map { word in
                let lowercased = word.lowercased()
                if ["figma", "arc", "xcode", "spotify"].contains(lowercased) {
                    return lowercased.capitalized
                }
                return lowercased.capitalized
            }
            .joined(separator: " ")
    }

    private func containsAny(_ transcript: String, _ needles: [String]) -> Bool {
        needles.contains { transcript.contains($0) }
    }
}

private struct CompanionIntentTrainingExample {
    let action: CompanionIntentAction
    let phrase: String
    let spokenResponse: String
    let reason: String
}

private final class CompanionLocalIntentModel {
    private let embedding: NLEmbedding?
    private let baseExamples: [CompanionIntentTrainingExample] = [
        .init(action: .continuePortal, phrase: "continue what I was doing", spokenResponse: "Picking up your thread.", reason: "Closest local match for continue."),
        .init(action: .continuePortal, phrase: "take me back to what matters", spokenResponse: "Picking up your thread.", reason: "Closest local match for continue."),
        .init(action: .continuePortal, phrase: "resume where I left off", spokenResponse: "Picking up your thread.", reason: "Closest local match for continue."),
        .init(action: .openWorkQueue, phrase: "open work queue", spokenResponse: "Opening Work Queue.", reason: "Closest local match for Work Queue."),
        .init(action: .openCurrentThread, phrase: "open current thread", spokenResponse: "Opening Current Thread.", reason: "Closest local match for Current Thread."),
        .init(action: .openCurrentThread, phrase: "show me what i'm doing", spokenResponse: "Opening Current Thread.", reason: "Closest local match for Current Thread."),
        .init(action: .openWorkQueue, phrase: "show my queue", spokenResponse: "Opening Work Queue.", reason: "Closest local match for Work Queue."),
        .init(action: .openWorkQueue, phrase: "take me to my staged work", spokenResponse: "Opening Work Queue.", reason: "Closest local match for Work Queue."),
        .init(action: .openWorkQueue, phrase: "open it", spokenResponse: "Opening Work Queue.", reason: "Closest local match for contextual open."),
        .init(action: .captureCheckpoint, phrase: "capture this", spokenResponse: "Capturing this thread.", reason: "Closest local match for checkpoint capture."),
        .init(action: .captureCheckpoint, phrase: "save this for later", spokenResponse: "Capturing this thread.", reason: "Closest local match for checkpoint capture."),
        .init(action: .captureCheckpoint, phrase: "remember this", spokenResponse: "Capturing this thread.", reason: "Closest local match for checkpoint capture."),
        .init(action: .captureCheckpoint, phrase: "save it", spokenResponse: "Capturing this thread.", reason: "Closest local match for contextual capture."),
        .init(action: .activateWorkSpell, phrase: "work spell", spokenResponse: "Opening Work Spell.", reason: "Closest local match for activating Work Spell."),
        .init(action: .activateWorkSpell, phrase: "start work spell", spokenResponse: "Opening Work Spell.", reason: "Closest local match for activating Work Spell."),
        .init(action: .activateWorkSpell, phrase: "add research to the todo", spokenResponse: "Adding that to Work Spell.", reason: "Closest local match for adding to Work Spell."),
        .init(action: .activateWorkSpell, phrase: "append export and ship to my list", spokenResponse: "Adding that to Work Spell.", reason: "Closest local match for adding multiple Work Spell tasks."),
        .init(action: .removeWorkSpellTasks, phrase: "remove design from the todo", spokenResponse: "Removing that from Work Spell.", reason: "Closest local match for removing a Work Spell task."),
        .init(action: .removeWorkSpellTasks, phrase: "delete research and export from my list", spokenResponse: "Removing those from Work Spell.", reason: "Closest local match for removing multiple Work Spell tasks."),
        .init(action: .deactivateWorkSpell, phrase: "stop work spell", spokenResponse: "Turning off Work Spell.", reason: "Closest local match for deactivating Work Spell."),
        .init(action: .openTimer, phrase: "open timer", spokenResponse: "Opening Timer.", reason: "Closest local match for timer."),
        .init(action: .openTimer, phrase: "show the timer", spokenResponse: "Opening Timer.", reason: "Closest local match for timer."),
        .init(action: .openTimer, phrase: "take me to timer", spokenResponse: "Opening Timer.", reason: "Closest local match for timer."),
        .init(action: .openTimer, phrase: "show me the timer", spokenResponse: "Opening Timer.", reason: "Closest local match for timer."),
        .init(action: .setTimer, phrase: "set a timer for twenty minutes", spokenResponse: "Starting your timer.", reason: "Closest local match for setting a timer."),
        .init(action: .setTimer, phrase: "start a fifteen minute timer", spokenResponse: "Starting your timer.", reason: "Closest local match for setting a timer."),
        .init(action: .setTimer, phrase: "timer for thirty minutes", spokenResponse: "Starting your timer.", reason: "Closest local match for setting a timer."),
        .init(action: .setTimer, phrase: "set one for ten minutes", spokenResponse: "Starting your timer.", reason: "Closest local match for conversational timer setup."),
        .init(action: .cancelTimer, phrase: "cancel the timer", spokenResponse: "Canceling the timer.", reason: "Closest local match for canceling a timer."),
        .init(action: .cancelTimer, phrase: "cancel timers", spokenResponse: "Canceling the timer.", reason: "Closest local match for canceling a timer."),
        .init(action: .cancelTimer, phrase: "stop the timer", spokenResponse: "Canceling the timer.", reason: "Closest local match for canceling a timer."),
        .init(action: .cancelTimer, phrase: "stop all timers", spokenResponse: "Canceling the timer.", reason: "Closest local match for canceling a timer."),
        .init(action: .cancelTimer, phrase: "clear the timer", spokenResponse: "Canceling the timer.", reason: "Closest local match for canceling a timer."),
        .init(action: .openNowPlaying, phrase: "what's playing right now", spokenResponse: "Opening Now Playing.", reason: "Closest local match for now playing."),
        .init(action: .openNowPlaying, phrase: "show me now playing", spokenResponse: "Opening Now Playing.", reason: "Closest local match for now playing."),
        .init(action: .openNowPlaying, phrase: "what song is this", spokenResponse: "Opening Now Playing.", reason: "Closest local match for now playing."),
        .init(action: .openNowPlaying, phrase: "open it", spokenResponse: "Opening Now Playing.", reason: "Closest local match for contextual now-playing open."),
        .init(action: .togglePlayback, phrase: "pause the music", spokenResponse: "Toggling playback.", reason: "Closest local match for playback control."),
        .init(action: .togglePlayback, phrase: "play the music", spokenResponse: "Toggling playback.", reason: "Closest local match for playback control."),
        .init(action: .togglePlayback, phrase: "resume playback", spokenResponse: "Toggling playback.", reason: "Closest local match for playback control."),
        .init(action: .togglePlayback, phrase: "pause it", spokenResponse: "Toggling playback.", reason: "Closest local match for contextual playback control."),
        .init(action: .undoLastAction, phrase: "undo that", spokenResponse: "Undoing that.", reason: "Closest local match for undoing the last action."),
        .init(action: .undoLastAction, phrase: "that wasn't right", spokenResponse: "Undoing that.", reason: "Closest local match for undoing the last action."),
        .init(action: .undoLastAction, phrase: "take that back", spokenResponse: "Undoing that.", reason: "Closest local match for undoing the last action."),
        .init(action: .openEntity, phrase: "open safari", spokenResponse: "Opening Safari.", reason: "Closest local match for opening an app."),
        .init(action: .openEntity, phrase: "launch figma", spokenResponse: "Opening Figma.", reason: "Closest local match for opening an app."),
        .init(action: .openEntity, phrase: "pull up the github tab", spokenResponse: "Searching for that.", reason: "Closest local match for a browser search."),
        .init(action: .openEntity, phrase: "open a new tab for github", spokenResponse: "Opening a new search tab.", reason: "Closest local match for opening a new search tab."),
        .init(action: .openEntity, phrase: "search figma docs", spokenResponse: "Searching for that.", reason: "Closest local match for a browser search.")
    ]

    init() {
        embedding = NLEmbedding.sentenceEmbedding(for: .english)
    }

    static func defaultSpokenResponse(for action: CompanionIntentAction) -> String {
        switch action {
        case .continuePortal:
            return "Picking up your thread."
        case .openWorkQueue:
            return "Opening Work Queue."
        case .openCurrentThread:
            return "Opening Current Thread."
        case .captureCheckpoint:
            return "Capturing this thread."
        case .activateWorkSpell:
            return "Setting up Work Spell."
        case .removeWorkSpellTasks:
            return "Removing that from Work Spell."
        case .deactivateWorkSpell:
            return "Turning off Work Spell."
        case .openTimer:
            return "Opening Timer."
        case .setTimer:
            return "Starting your timer."
        case .cancelTimer:
            return "Canceling the timer."
        case .openNowPlaying:
            return "Opening Now Playing."
        case .togglePlayback:
            return "Toggling playback."
        case .openEntity:
            return "Opening it."
        case .undoLastAction:
            return "Undoing that."
        case .runMacro:
            return "Running your macro."
        case .none:
            return "I didn’t map that yet."
        }
    }

    func parse(transcript: String, snapshot: CompanionStateSnapshot, learnedExamples: [CompanionIntentTrainingExample]) -> CompanionIntent? {
        let normalizedTranscript = normalize(transcript)
        guard !normalizedTranscript.isEmpty else {
            return nil
        }

        if let durationSeconds = explicitDurationSeconds(in: normalizedTranscript) {
            let spokenDuration = CompanionDurationParser.spokenDurationText(totalSeconds: durationSeconds)
            return CompanionIntent(
                action: .setTimer,
                durationMinutes: CompanionDurationParser.parseMinutes(from: normalizedTranscript),
                durationSeconds: durationSeconds,
                spokenResponse: "Starting a \(spokenDuration) timer.",
                reason: "Detected an explicit duration in the spoken request.",
                suggestions: nil
            )
        }

        guard let bestMatch = bestExample(for: normalizedTranscript, snapshot: snapshot, learnedExamples: learnedExamples) else {
            return nil
        }

        let matchedAction = bestMatch.example.action
        let matchedDurationMinutes: Int?
        let matchedDurationSeconds: Int?
        if matchedAction == .setTimer {
            matchedDurationSeconds = explicitDurationSeconds(in: normalizedTranscript)
            matchedDurationMinutes = matchedDurationSeconds.flatMap { CompanionDurationParser.parseMinutes(from: normalizedTranscript) ?? Int(ceil(Double($0) / 60.0)) }
        } else {
            matchedDurationSeconds = nil
            matchedDurationMinutes = nil
        }

        return CompanionIntent(
            action: matchedAction,
            durationMinutes: matchedDurationMinutes,
            durationSeconds: matchedDurationSeconds,
            spokenResponse: matchedDurationSeconds != nil && matchedAction == .setTimer
                ? "Starting a \(CompanionDurationParser.spokenDurationText(totalSeconds: matchedDurationSeconds!)) timer."
                : bestMatch.example.spokenResponse,
            reason: "\(bestMatch.example.reason) score \(String(format: "%.2f", bestMatch.score)).",
            suggestions: nil,
            domain: matchedAction == .openEntity ? .apps : matchedAction.defaultDomain,
            confidence: min(max(bestMatch.score, 0.0), 0.98)
        )
    }

    func suggestions(transcript: String, snapshot: CompanionStateSnapshot, learnedExamples: [CompanionIntentTrainingExample], limit: Int) -> [String] {
        let ranked = rankedExamples(for: normalize(transcript), snapshot: snapshot, learnedExamples: learnedExamples)
        var seenActions: Set<CompanionIntentAction> = []
        var suggestions: [String] = []

        for candidate in ranked where candidate.score >= 0.48 {
            guard seenActions.insert(candidate.example.action).inserted else {
                continue
            }
            suggestions.append(candidate.example.phrase)
            if suggestions.count == limit {
                break
            }
        }

        return suggestions
    }

    private func bestExample(for transcript: String, snapshot: CompanionStateSnapshot, learnedExamples: [CompanionIntentTrainingExample]) -> (example: CompanionIntentTrainingExample, score: Double)? {
        let ranked = rankedExamples(for: transcript, snapshot: snapshot, learnedExamples: learnedExamples)
        guard let best = ranked.first else {
            return nil
        }

        return best.score >= 0.62 ? best : nil
    }

    private func rankedExamples(for transcript: String, snapshot: CompanionStateSnapshot, learnedExamples: [CompanionIntentTrainingExample]) -> [(example: CompanionIntentTrainingExample, score: Double)] {
        guard let embedding else {
            return []
        }

        let examples = learnedExamples + baseExamples
        var ranked: [(example: CompanionIntentTrainingExample, score: Double)] = []
        for example in examples {
            let distance = embedding.distance(between: transcript, and: example.phrase, distanceType: .cosine)
            let baseScore = 1.0 - (distance / 2.0)
            let keywordBonus = keywordBonus(for: transcript, action: example.action, snapshot: snapshot)
            let score = baseScore + keywordBonus
            ranked.append((example, score))
        }

        return ranked.sorted { lhs, rhs in
            if abs(lhs.score - rhs.score) < 0.0001 {
                return lhs.example.phrase.count < rhs.example.phrase.count
            }
            return lhs.score > rhs.score
        }
    }

    private func keywordBonus(for transcript: String, action: CompanionIntentAction, snapshot: CompanionStateSnapshot) -> Double {
        switch action {
        case .continuePortal:
            return containsAny(transcript, ["continue", "resume", "back to", "left off"]) ? 0.18 : 0
        case .activateWorkSpell:
            return containsAny(transcript, ["work spell", "spell", "todo", "checklist", "tasks"]) ? 0.26 : 0
        case .removeWorkSpellTasks:
            return containsAny(transcript, ["remove", "delete", "drop", "take off", "todo", "to do", "list", "work spell"]) ? 0.26 : 0
        case .deactivateWorkSpell:
            return containsAny(transcript, ["stop work spell", "end work spell", "deactivate work spell", "leave work spell"]) ? 0.30 : 0
        case .openWorkQueue:
            return containsAny(transcript, ["queue", "staged", "thread list", "work queue"]) ? 0.22 : 0
        case .openCurrentThread:
            return containsAny(transcript, ["current thread", "what am i doing", "what am i working on", "thread"]) ? 0.24 : 0
        case .captureCheckpoint:
            return containsAny(transcript, ["capture", "save this", "remember", "checkpoint", "mark this"]) ? 0.22 : 0
        case .openTimer:
            return containsAny(transcript, ["timer", "countdown"]) ? 0.18 : 0
        case .setTimer:
            return containsAny(transcript, ["timer", "minutes", "minute", "hours", "hour"]) ? 0.26 : 0
        case .cancelTimer:
            return containsAny(transcript, ["cancel", "stop", "clear", "timer", "countdown"]) ? 0.28 : 0
        case .openNowPlaying:
            return containsAny(transcript, ["what's playing", "what is playing", "song", "music", "now playing"]) ? 0.24 : 0
        case .togglePlayback:
            return containsAny(transcript, ["pause", "play", "resume playback", "music"]) ? 0.24 : 0
        case .openEntity:
            return containsAny(transcript, ["open", "launch", "switch to", "resume", "show", "tab", "search", "look up", "pull up", "bring up"]) ? 0.28 : 0
        case .undoLastAction:
            return containsAny(transcript, ["undo", "not right", "take that back", "revert"]) ? 0.32 : 0
        case .runMacro:
            return 0
        case .none:
            return 0
        }
    }

    private func explicitDurationSeconds(in transcript: String) -> Int? {
        guard containsAny(transcript, ["timer", "countdown"]) else {
            return nil
        }

        return CompanionDurationParser.parseDurationSeconds(from: transcript)
    }

    private func normalize(_ transcript: String) -> String {
        transcript
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsAny(_ transcript: String, _ needles: [String]) -> Bool {
        needles.contains { transcript.contains($0) }
    }
}

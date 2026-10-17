import Foundation

enum TimerStage {
    case setting
    case running
    case paused
    case finished
}

enum TimerField: Int, CaseIterable {
    case hours
    case minutes
    case seconds

    var title: String {
        switch self {
        case .hours:
            return "Hours"
        case .minutes:
            return "Minutes"
        case .seconds:
            return "Seconds"
        }
    }

    var maxValue: Int {
        switch self {
        case .hours:
            return 23
        case .minutes, .seconds:
            return 59
        }
    }
}

struct TimerFieldDisplay {
    let field: TimerField
    let title: String
    let valueText: String
    let isSelected: Bool
}

struct TimerRelatedTimerDisplay {
    let title: String
    let detail: String
    let valueText: String
    let symbol: String
}

struct TimerCardModel {
    let stage: TimerStage
    let title: String
    let subtitle: String
    let footer: String
    let primaryTimeText: String
    let digitalTimeText: String
    let ringProgress: Double
    let handProgress: Double
    let fields: [TimerFieldDisplay]
    let relatedTimersTitle: String?
    let relatedTimers: [TimerRelatedTimerDisplay]
}

struct TimerTrackedEntrySnapshot {
    let id: UUID
    let createdAt: Date
    let stage: TimerStage
    let totalDurationSeconds: Int
    let remainingSeconds: Int
    let lastStartedTotalSeconds: Int
}

struct TimerCompanionSnapshot {
    let stage: TimerStage
    let selectedField: TimerField
    let configuredHours: Int
    let configuredMinutes: Int
    let configuredSeconds: Int
    let lastStartedTotalSeconds: Int
    let totalDurationSeconds: Int
    let remainingSeconds: Int
    let focusedTimerID: UUID?
    let focusedTimerCreatedAt: Date?
    let additionalTimers: [TimerTrackedEntrySnapshot]
}

enum TimerAdvanceResult {
    case movedForward
    case started
    case blockedZero
    case toggledPauseResume
    case resetAfterFinish
}

@MainActor
final class TimerCoordinator {
    private struct TrackedTimer {
        let id: UUID
        let createdAt: Date
        var stage: TimerStage
        var totalDurationSeconds: Int
        var remainingSeconds: Int
        var lastStartedTotalSeconds: Int
        var endDate: Date?
    }

    var onUpdate: ((TimerCardModel) -> Void)?
    var onCompletion: (() -> Void)?

    private var stage: TimerStage = .setting
    private var selectedField: TimerField = .hours
    private var configuredHours = 0
    private var configuredMinutes = 5
    private var configuredSeconds = 0
    private var lastStartedTotalSeconds = 5 * 60
    private var totalDurationSeconds = 5 * 60
    private var remainingSeconds = 5 * 60
    private var endDate: Date?
    private var ticker: Timer?
    private var focusedTimerID: UUID?
    private var focusedTimerCreatedAt: Date?
    private var additionalTimers: [TrackedTimer] = []

    init() {}

    func stop() {
        ticker?.invalidate()
        ticker = nil
    }

    func currentModel() -> TimerCardModel {
        makeModel()
    }

    var companionStageName: String {
        if stage == .setting {
            if additionalTimers.contains(where: { $0.stage == .running }) {
                return "running"
            }
            if additionalTimers.contains(where: { $0.stage == .paused }) {
                return "paused"
            }
            if additionalTimers.contains(where: { $0.stage == .finished }) {
                return "finished"
            }
        }

        switch stage {
        case .setting:
            return "setting"
        case .running:
            return "running"
        case .paused:
            return "paused"
        case .finished:
            return "finished"
        }
    }

    var hasLiveCompanionTarget: Bool {
        stage != .setting || !additionalTimers.isEmpty
    }

    var hasAnyCompanionTimerState: Bool {
        stage != .setting || configuredTotalSeconds > 0 || !additionalTimers.isEmpty
    }

    @discardableResult
    func startCompanionTimer(totalSeconds: Int) -> Bool {
        let clampedSeconds = max(1, min(24 * 3600 - 1, totalSeconds))
        selectedField = .hours
        promoteFocusedTimerToAdditionalIfNeeded()
        startTimer(with: clampedSeconds)
        return true
    }

    @discardableResult
    func cancelCompanionTimer() -> Bool {
        guard hasAnyCompanionTimerState else {
            return false
        }

        if stage != .setting {
            discardFocusedTimer(promoteReplacement: true)
        } else if !additionalTimers.isEmpty {
            _ = promoteNextAdditionalTimerToFocused()
            publish()
        } else {
            clearToZero()
        }
        return true
    }

    func companionSnapshot() -> TimerCompanionSnapshot {
        TimerCompanionSnapshot(
            stage: stage,
            selectedField: selectedField,
            configuredHours: configuredHours,
            configuredMinutes: configuredMinutes,
            configuredSeconds: configuredSeconds,
            lastStartedTotalSeconds: lastStartedTotalSeconds,
            totalDurationSeconds: totalDurationSeconds,
            remainingSeconds: remainingSeconds,
            focusedTimerID: focusedTimerID,
            focusedTimerCreatedAt: focusedTimerCreatedAt,
            additionalTimers: additionalTimers.map {
                TimerTrackedEntrySnapshot(
                    id: $0.id,
                    createdAt: $0.createdAt,
                    stage: $0.stage,
                    totalDurationSeconds: $0.totalDurationSeconds,
                    remainingSeconds: $0.remainingSeconds,
                    lastStartedTotalSeconds: $0.lastStartedTotalSeconds
                )
            }
        )
    }

    @discardableResult
    func restoreCompanionSnapshot(_ snapshot: TimerCompanionSnapshot) -> Bool {
        stop()
        stage = snapshot.stage
        selectedField = snapshot.selectedField
        configuredHours = snapshot.configuredHours
        configuredMinutes = snapshot.configuredMinutes
        configuredSeconds = snapshot.configuredSeconds
        lastStartedTotalSeconds = snapshot.lastStartedTotalSeconds
        totalDurationSeconds = snapshot.totalDurationSeconds
        remainingSeconds = snapshot.remainingSeconds
        focusedTimerID = snapshot.focusedTimerID
        focusedTimerCreatedAt = snapshot.focusedTimerCreatedAt
        additionalTimers = snapshot.additionalTimers.map { snapshot in
            TrackedTimer(
                id: snapshot.id,
                createdAt: snapshot.createdAt,
                stage: snapshot.stage,
                totalDurationSeconds: snapshot.totalDurationSeconds,
                remainingSeconds: snapshot.remainingSeconds,
                lastStartedTotalSeconds: snapshot.lastStartedTotalSeconds,
                endDate: snapshot.stage == .running ? Date().addingTimeInterval(TimeInterval(max(snapshot.remainingSeconds, 1))) : nil
            )
        }

        switch snapshot.stage {
        case .running:
            endDate = Date().addingTimeInterval(TimeInterval(max(snapshot.remainingSeconds, 1)))
        case .paused, .finished, .setting:
            endDate = nil
        }

        ensureTickerIfNeeded()
        publish()
        return true
    }

    func incrementCurrentValue() {
        switch stage {
        case .setting:
            mutateSelectedField(by: 1)
        case .running, .paused:
            adjustRunningTime(by: 60)
        case .finished:
            break
        }
    }

    func decrementCurrentValue() {
        switch stage {
        case .setting:
            mutateSelectedField(by: -1)
        case .running, .paused:
            adjustRunningTime(by: -60)
        case .finished:
            break
        }
    }

    @discardableResult
    func advanceOrPrimaryAction() -> TimerAdvanceResult {
        switch stage {
        case .setting:
            if selectedField != .seconds {
                selectedField = TimerField(rawValue: selectedField.rawValue + 1) ?? .seconds
                publish()
                return .movedForward
            }

            guard configuredTotalSeconds > 0 else {
                publish()
                return .blockedZero
            }

            startTimer(with: configuredTotalSeconds)
            return .started
        case .running:
            pause()
            return .toggledPauseResume
        case .paused:
            resume()
            return .toggledPauseResume
        case .finished:
            resetToLastStartedDuration()
            return .resetAfterFinish
        }
    }

    func moveBack() {
        switch stage {
        case .setting:
            if let previousField = TimerField(rawValue: max(selectedField.rawValue - 1, 0)) {
                selectedField = previousField
                publish()
            }
        case .running, .paused:
            cancelToSetting()
        case .finished:
            if !additionalTimers.isEmpty {
                discardFocusedTimer(promoteReplacement: true)
            } else {
                clearToZero()
            }
        }
    }

    func hideToLauncher() {
        publish()
    }

    private var configuredTotalSeconds: Int {
        (configuredHours * 3600) + (configuredMinutes * 60) + configuredSeconds
    }

    private var hasRunningTimers: Bool {
        stage == .running || additionalTimers.contains(where: { $0.stage == .running })
    }

    private func startTimer(with seconds: Int) {
        stop()
        focusedTimerID = focusedTimerID ?? UUID()
        focusedTimerCreatedAt = Date()
        lastStartedTotalSeconds = seconds
        totalDurationSeconds = seconds
        remainingSeconds = seconds
        stage = .running
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        ensureTickerIfNeeded()
        publish()
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func ensureTickerIfNeeded() {
        if hasRunningTimers {
            if ticker == nil {
                startTicker()
            }
        } else {
            stop()
        }
    }

    private func tick() {
        var didChange = false

        if stage == .running, let endDate {
            let secondsLeft = max(Int(ceil(endDate.timeIntervalSinceNow)), 0)
            if secondsLeft != remainingSeconds {
                remainingSeconds = secondsLeft
                didChange = true
            }

            if secondsLeft <= 0 {
                stage = .finished
                remainingSeconds = 0
                configuredHours = 0
                configuredMinutes = 0
                configuredSeconds = 0
                self.endDate = nil
                didChange = true
                onCompletion?()
            }
        }

        for index in additionalTimers.indices {
            guard additionalTimers[index].stage == .running,
                  let endDate = additionalTimers[index].endDate else {
                continue
            }

            let secondsLeft = max(Int(ceil(endDate.timeIntervalSinceNow)), 0)
            if secondsLeft != additionalTimers[index].remainingSeconds {
                additionalTimers[index].remainingSeconds = secondsLeft
                didChange = true
            }

            if secondsLeft <= 0 {
                additionalTimers[index].stage = .finished
                additionalTimers[index].remainingSeconds = 0
                additionalTimers[index].endDate = nil
                didChange = true
            }
        }

        ensureTickerIfNeeded()

        if didChange {
            publish()
        }
    }

    private func pause() {
        guard stage == .running else {
            return
        }

        if let endDate {
            remainingSeconds = max(Int(ceil(endDate.timeIntervalSinceNow)), 0)
        }
        endDate = nil
        stage = .paused
        ensureTickerIfNeeded()
        publish()
    }

    private func resume() {
        guard stage == .paused, remainingSeconds > 0 else {
            return
        }

        stage = .running
        totalDurationSeconds = max(totalDurationSeconds, remainingSeconds)
        endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        ensureTickerIfNeeded()
        publish()
    }

    private func cancelToSetting() {
        stop()
        endDate = nil
        if !additionalTimers.isEmpty {
            discardFocusedTimer(promoteReplacement: true)
            return
        }

        stage = .setting
        applyConfiguredTime(from: remainingSeconds > 0 ? remainingSeconds : lastStartedTotalSeconds)
        focusedTimerID = nil
        focusedTimerCreatedAt = nil
        selectedField = .hours
        ensureTickerIfNeeded()
        publish()
    }

    private func resetToLastStartedDuration() {
        stop()
        endDate = nil
        stage = .setting
        applyConfiguredTime(from: lastStartedTotalSeconds)
        focusedTimerID = nil
        focusedTimerCreatedAt = nil
        selectedField = .hours
        ensureTickerIfNeeded()
        publish()
    }

    private func clearToZero() {
        stop()
        endDate = nil
        stage = .setting
        configuredHours = 0
        configuredMinutes = 0
        configuredSeconds = 0
        totalDurationSeconds = 0
        remainingSeconds = 0
        focusedTimerID = nil
        focusedTimerCreatedAt = nil
        additionalTimers = []
        selectedField = .hours
        publish()
    }

    private func adjustRunningTime(by deltaSeconds: Int) {
        let updatedRemaining = max(1, min(24 * 3600 - 1, remainingSeconds + deltaSeconds))
        remainingSeconds = updatedRemaining
        totalDurationSeconds = max(updatedRemaining, totalDurationSeconds + deltaSeconds)
        totalDurationSeconds = max(1, min(24 * 3600 - 1, totalDurationSeconds))

        switch stage {
        case .running:
            endDate = Date().addingTimeInterval(TimeInterval(updatedRemaining))
        case .paused:
            break
        case .setting, .finished:
            return
        }

        publish()
    }

    private func mutateSelectedField(by delta: Int) {
        switch selectedField {
        case .hours:
            configuredHours = wrapped(configuredHours + delta, max: TimerField.hours.maxValue)
        case .minutes:
            configuredMinutes = wrapped(configuredMinutes + delta, max: TimerField.minutes.maxValue)
        case .seconds:
            configuredSeconds = wrapped(configuredSeconds + delta, max: TimerField.seconds.maxValue)
        }
        publish()
    }

    private func applyConfiguredTime(from totalSeconds: Int) {
        let safeTotal = max(totalSeconds, 0)
        configuredHours = safeTotal / 3600
        configuredMinutes = (safeTotal % 3600) / 60
        configuredSeconds = safeTotal % 60
        totalDurationSeconds = safeTotal
        remainingSeconds = safeTotal
    }

    private func promoteFocusedTimerToAdditionalIfNeeded() {
        guard let tracked = makeTrackedTimerIfNeeded() else {
            return
        }

        additionalTimers.insert(tracked, at: 0)
    }

    private func makeTrackedTimerIfNeeded() -> TrackedTimer? {
        guard stage != .setting, let focusedTimerID else {
            return nil
        }

        return TrackedTimer(
            id: focusedTimerID,
            createdAt: focusedTimerCreatedAt ?? Date(),
            stage: stage,
            totalDurationSeconds: totalDurationSeconds,
            remainingSeconds: remainingSeconds,
            lastStartedTotalSeconds: lastStartedTotalSeconds,
            endDate: stage == .running ? endDate : nil
        )
    }

    private func discardFocusedTimer(promoteReplacement: Bool) {
        stop()
        endDate = nil
        focusedTimerID = nil
        focusedTimerCreatedAt = nil

        if promoteReplacement, promoteNextAdditionalTimerToFocused() {
            publish()
            return
        }

        stage = .setting
        configuredHours = 0
        configuredMinutes = 0
        configuredSeconds = 0
        totalDurationSeconds = 0
        remainingSeconds = 0
        selectedField = .hours
        publish()
    }

    @discardableResult
    private func promoteNextAdditionalTimerToFocused() -> Bool {
        guard !additionalTimers.isEmpty else {
            return false
        }

        let nextIndex = additionalTimers.enumerated().min { lhs, rhs in
            if lhs.element.stage == .running && rhs.element.stage != .running {
                return true
            }
            if lhs.element.stage != .running && rhs.element.stage == .running {
                return false
            }
            if lhs.element.remainingSeconds == rhs.element.remainingSeconds {
                return lhs.element.createdAt > rhs.element.createdAt
            }
            return lhs.element.remainingSeconds < rhs.element.remainingSeconds
        }?.offset ?? 0

        let next = additionalTimers.remove(at: nextIndex)
        focusedTimerID = next.id
        focusedTimerCreatedAt = next.createdAt
        stage = next.stage
        totalDurationSeconds = next.totalDurationSeconds
        remainingSeconds = next.remainingSeconds
        lastStartedTotalSeconds = next.lastStartedTotalSeconds
        endDate = next.stage == .running ? Date().addingTimeInterval(TimeInterval(max(next.remainingSeconds, 1))) : nil
        ensureTickerIfNeeded()
        return true
    }

    private func publish() {
        onUpdate?(makeModel())
    }

    private func makeModel() -> TimerCardModel {
        let totalSecondsForDisplay: Int
        let title: String
        let subtitle: String
        let footer: String
        let displaySeconds: Int
        let ringProgress: Double

        switch stage {
        case .setting:
            totalSecondsForDisplay = configuredTotalSeconds
            displaySeconds = totalSecondsForDisplay
            title = "Set Timer"
            subtitle = additionalTimers.isEmpty
                ? "Tap center to move forward. Double-tap center to move back."
                : "Set a new timer while your other timers keep running."
            footer = "On seconds, tap center to start. Hold center to leave Timer."
            ringProgress = 0
        case .running:
            totalSecondsForDisplay = max(totalDurationSeconds, 1)
            displaySeconds = remainingSeconds
            title = "Running"
            subtitle = "+ adds 1 minute. - subtracts 1 minute."
            footer = additionalTimers.isEmpty
                ? "Tap center pauses. Double-tap cancels. Hold center hides Timer."
                : "Tap center pauses. Double-tap cancels the focused timer. Hold center hides Timer."
            ringProgress = Double(remainingSeconds) / Double(max(totalDurationSeconds, 1))
        case .paused:
            totalSecondsForDisplay = max(totalDurationSeconds, 1)
            displaySeconds = remainingSeconds
            title = "Paused"
            subtitle = "+/- adjust remaining time by 1 minute."
            footer = additionalTimers.isEmpty
                ? "Tap center resumes. Double-tap cancels. Hold center hides Timer."
                : "Tap center resumes. Double-tap cancels the focused timer. Hold center hides Timer."
            ringProgress = Double(remainingSeconds) / Double(max(totalDurationSeconds, 1))
        case .finished:
            totalSecondsForDisplay = max(lastStartedTotalSeconds, 1)
            displaySeconds = 0
            title = "Time's Up"
            subtitle = "Tap center to reset. Double-tap to clear."
            footer = additionalTimers.isEmpty
                ? "Hold center hides Timer and returns to the launcher."
                : "Double-tap clears this timer and moves to the next one. Hold center hides Timer."
            ringProgress = 0
        }

        let handProgress = totalSecondsForDisplay > 0
            ? Double(displaySeconds) / Double(totalSecondsForDisplay)
            : 0.0

        let fields = TimerField.allCases.map { field in
            let value: Int
            switch field {
            case .hours:
                value = configuredHours
            case .minutes:
                value = configuredMinutes
            case .seconds:
                value = configuredSeconds
            }
            return TimerFieldDisplay(
                field: field,
                title: field.title,
                valueText: String(format: "%02d", value),
                isSelected: stage == .setting && field == selectedField
            )
        }

        let relatedTimers = makeRelatedTimerDisplays()
        let relatedTimersTitle = relatedTimers.isEmpty ? nil : (relatedTimers.count == 1 ? "Other Timer" : "Other Timers")

        return TimerCardModel(
            stage: stage,
            title: title,
            subtitle: subtitle,
            footer: footer,
            primaryTimeText: shortTimeText(for: displaySeconds),
            digitalTimeText: fullTimeText(for: displaySeconds),
            ringProgress: ringProgress,
            handProgress: handProgress,
            fields: fields,
            relatedTimersTitle: relatedTimersTitle,
            relatedTimers: relatedTimers
        )
    }

    private func makeRelatedTimerDisplays() -> [TimerRelatedTimerDisplay] {
        let sorted = additionalTimers.sorted { lhs, rhs in
            if lhs.stage == .running && rhs.stage != .running {
                return true
            }
            if lhs.stage != .running && rhs.stage == .running {
                return false
            }
            if lhs.remainingSeconds == rhs.remainingSeconds {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.remainingSeconds < rhs.remainingSeconds
        }

        var displays = sorted.prefix(3).map { timer in
            TimerRelatedTimerDisplay(
                title: relatedTimerTitle(for: timer),
                detail: relatedTimerDetail(for: timer),
                valueText: shortTimeText(for: timer.remainingSeconds),
                symbol: relatedTimerSymbol(for: timer)
            )
        }

        if sorted.count > 3 {
            displays.append(
                TimerRelatedTimerDisplay(
                    title: "+\(sorted.count - 3) more timers",
                    detail: "Keep using Companion or reopen Timer later.",
                    valueText: "",
                    symbol: "ellipsis"
                )
            )
        }

        return displays
    }

    private func relatedTimerTitle(for timer: TrackedTimer) -> String {
        switch timer.stage {
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .finished:
            return "Finished"
        case .setting:
            return "Queued"
        }
    }

    private func relatedTimerDetail(for timer: TrackedTimer) -> String {
        switch timer.stage {
        case .running:
            return "Ends in \(spokenDurationText(for: timer.remainingSeconds))."
        case .paused:
            return "Paused with \(spokenDurationText(for: timer.remainingSeconds)) left."
        case .finished:
            return "Completed."
        case .setting:
            return "Ready for \(spokenDurationText(for: timer.totalDurationSeconds))."
        }
    }

    private func relatedTimerSymbol(for timer: TrackedTimer) -> String {
        switch timer.stage {
        case .running:
            return "timer"
        case .paused:
            return "pause.circle"
        case .finished:
            return "checkmark.circle"
        case .setting:
            return "clock"
        }
    }

    private func shortTimeText(for totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func fullTimeText(for totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func spokenDurationText(for totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        var parts: [String] = []
        if hours > 0 {
            parts.append(hours == 1 ? "1 hour" : "\(hours) hours")
        }
        if minutes > 0 {
            parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes")
        }
        if seconds > 0 || parts.isEmpty {
            parts.append(seconds == 1 ? "1 second" : "\(seconds) seconds")
        }
        return parts.joined(separator: " ")
    }

    private func wrapped(_ value: Int, max: Int) -> Int {
        if value < 0 {
            return max
        }
        if value > max {
            return 0
        }
        return value
    }
}

import AppKit
import ApplicationServices
import Darwin
import Dispatch
import EarPodsCore
import Foundation
import NaturalLanguage

private let browserSemanticEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
private let launcherDisplayName = "Inlay"
private let legacyLauncherDisplayName = "EarPods Launcher"

private enum LauncherRuntimeMode: Equatable {
    case commandLine
    case bundledApp

    static func detect(bundle: Bundle = .main) -> LauncherRuntimeMode {
        bundle.bundleURL.pathExtension == "app" ? .bundledApp : .commandLine
    }

    var diagnosticsEnabled: Bool {
        self == .commandLine
    }

    var rawBeepsEnabled: Bool {
        self == .commandLine
    }

    var successBeepsEnabled: Bool {
        self == .commandLine
    }

    var selectionNotificationsEnabled: Bool {
        self == .bundledApp
    }
}

enum LauncherItemAction {
    case placeholder
    case quitApp
}

struct LauncherItem: Decodable {
    let id: String
    let title: String
    let symbol: String
    let action: LauncherItemAction

    init(id: String, title: String, symbol: String, action: LauncherItemAction = .placeholder) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.symbol = try container.decode(String.self, forKey: .symbol)
        self.action = .placeholder
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case symbol
    }

    static let quitItem = LauncherItem(
        id: "quit-earpods-launcher",
        title: "Quit Inlay",
        symbol: "power",
        action: .quitApp
    )

    static let workQueueItem = LauncherItem(
        id: "work-queue",
        title: "Work Queue",
        symbol: "list.bullet.clipboard",
        action: .placeholder
    )

    static let currentThreadItem = LauncherItem(
        id: "current-thread",
        title: "Current Thread",
        symbol: "sparkles",
        action: .placeholder
    )

    static let companionItem = LauncherItem(
        id: "companion",
        title: "Companion",
        symbol: "waveform.badge.mic",
        action: .placeholder
    )

    static let supportItem = LauncherItem(
        id: "support",
        title: "Support",
        symbol: "lifepreserver",
        action: .placeholder
    )

    static let supportedVisibleIDs: Set<String> = [
        companionItem.id,
        supportItem.id,
        currentThreadItem.id,
        workQueueItem.id,
        "timer",
        "now-playing",
    ]
}

private struct AppRuntimePaths {
    let applicationSupportDirectory: URL
    let logsDirectory: URL
    let configURL: URL
    let logURL: URL
    let lockURL: URL
    let onboardingStateURL: URL
    let cipherConfigURL: URL
    let workQueueURL: URL
    let workSpellURL: URL
    let companionConfigURL: URL

    static func prepare(bundle: Bundle = .main) throws -> AppRuntimePaths {
        let fileManager = FileManager.default
        let appSupportRoot = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("EarPodsLauncher", isDirectory: true)
        let logsRoot = try fileManager
            .url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("EarPodsLauncher", isDirectory: true)

        try fileManager.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsRoot, withIntermediateDirectories: true)

        let configURL = appSupportRoot.appendingPathComponent("launcher.json")
        let logURL = logsRoot.appendingPathComponent("launcher-events.ndjson")
        let lockURL = appSupportRoot.appendingPathComponent("singleton.lock")
        let onboardingStateURL = appSupportRoot.appendingPathComponent("onboarding-state.json")
        let cipherConfigURL = appSupportRoot.appendingPathComponent("cipher-config.json")
        let workQueueURL = appSupportRoot.appendingPathComponent("work-queue.json")
        let workSpellURL = appSupportRoot.appendingPathComponent("work-spell.json")
        let companionConfigURL = appSupportRoot.appendingPathComponent("companion-config.json")

        if !fileManager.fileExists(atPath: configURL.path) {
            guard let bundledConfigURL = bundle.url(forResource: "launcher.example", withExtension: "json") else {
                throw CLIError("Bundled launcher config resource `launcher.example.json` is missing.")
            }
            try fileManager.copyItem(at: bundledConfigURL, to: configURL)
        }

        if !fileManager.fileExists(atPath: companionConfigURL.path) {
            let companionTemplate = """
            {
              "phraseMemory": {}
            }
            """
            try companionTemplate.write(to: companionConfigURL, atomically: true, encoding: .utf8)
        }

        return AppRuntimePaths(
            applicationSupportDirectory: appSupportRoot,
            logsDirectory: logsRoot,
            configURL: configURL,
            logURL: logURL,
            lockURL: lockURL,
            onboardingStateURL: onboardingStateURL,
            cipherConfigURL: cipherConfigURL,
            workQueueURL: workQueueURL,
            workSpellURL: workSpellURL,
            companionConfigURL: companionConfigURL
        )
    }
}

private struct LauncherConfig {
    let configPath: String
    let logPath: String
    let onboardingStatePath: String
    let cipherConfigPath: String
    let workQueuePath: String
    let workSpellPath: String
    let companionConfigPath: String
    let idleTimeout: TimeInterval
    let runtimeMode: LauncherRuntimeMode
    let singletonLockPath: String?

    static func parse(arguments: [String]) throws -> LauncherConfig {
        let runtimeMode = LauncherRuntimeMode.detect()
        let filteredArguments = arguments.filter { !$0.hasPrefix("-psn_") }

        if filteredArguments.contains("--help") || filteredArguments.contains("-h") {
            throw CLIHelp()
        }

        let appPaths = runtimeMode == .bundledApp ? try AppRuntimePaths.prepare() : nil
        var configPath = appPaths?.configURL.path ?? "./config/launcher.example.json"
        var logPath = appPaths?.logURL.path ?? "./logs/launcher-events.ndjson"
        let onboardingStatePath = appPaths?.onboardingStateURL.path ?? "./logs/onboarding-state.json"
        let cipherConfigPath = appPaths?.cipherConfigURL.path ?? "./logs/cipher-config.json"
        let workQueuePath = appPaths?.workQueueURL.path ?? "./logs/work-queue.json"
        let workSpellPath = appPaths?.workSpellURL.path ?? "./logs/work-spell.json"
        let companionConfigPath = appPaths?.companionConfigURL.path ?? "./logs/companion-config.json"
        var idleTimeout: TimeInterval = 5.0

        var index = 0
        while index < filteredArguments.count {
            let argument = filteredArguments[index]

            switch argument {
            case "--config":
                index += 1
                guard index < filteredArguments.count else {
                    throw CLIError("Expected a file path after `--config`.")
                }
                configPath = filteredArguments[index]
            case "--log-path":
                index += 1
                guard index < filteredArguments.count else {
                    throw CLIError("Expected a file path after `--log-path`.")
                }
                logPath = filteredArguments[index]
            case "--idle-timeout-ms":
                index += 1
                guard index < filteredArguments.count else {
                    throw CLIError("Expected a number after `--idle-timeout-ms`.")
                }
                idleTimeout = try parseMillisecondsArgument(filteredArguments[index], flag: "--idle-timeout-ms")
            default:
                throw CLIError("Unknown argument: \(argument)")
            }

            index += 1
        }

        return LauncherConfig(
            configPath: normalizePath(configPath),
            logPath: normalizePath(logPath),
            onboardingStatePath: normalizePath(onboardingStatePath),
            cipherConfigPath: normalizePath(cipherConfigPath),
            workQueuePath: normalizePath(workQueuePath),
            workSpellPath: normalizePath(workSpellPath),
            companionConfigPath: normalizePath(companionConfigPath),
            idleTimeout: idleTimeout,
            runtimeMode: runtimeMode,
            singletonLockPath: appPaths?.lockURL.path
        )
    }

    private static func parseMillisecondsArgument(_ value: String, flag: String) throws -> TimeInterval {
        guard let milliseconds = Double(value), milliseconds > 0 else {
            throw CLIError("Expected a positive millisecond value after `\(flag)`.")
        }
        return milliseconds / 1000
    }
}

private struct CLIError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private struct CLIHelp: Error {}

private final class SingleInstanceCoordinator {
    private static let openRequestName = Notification.Name("com.samyanmangat.EarPodsLauncher.OpenHUD")

    private let notificationCenter = DistributedNotificationCenter.default()
    private let lockFileDescriptor: Int32
    private var observer: NSObjectProtocol?

    private init(lockFileDescriptor: Int32) {
        self.lockFileDescriptor = lockFileDescriptor
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        if lockFileDescriptor >= 0 {
            close(lockFileDescriptor)
        }
    }

    static func acquire(lockPath: String) throws -> SingleInstanceCoordinator? {
        let fileDescriptor = open(lockPath, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            let message = String(cString: strerror(errno))
            throw CLIError("Failed to open launcher lock file at \(lockPath): \(message)")
        }

        if flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
            return SingleInstanceCoordinator(lockFileDescriptor: fileDescriptor)
        }

        let errorCode = errno
        close(fileDescriptor)
        if errorCode == EWOULDBLOCK {
            return nil
        }

        let message = String(cString: strerror(errorCode))
        throw CLIError("Failed to lock launcher instance file at \(lockPath): \(message)")
    }

    static func signalOpenRequest() {
        DistributedNotificationCenter.default().postNotificationName(
            Self.openRequestName,
            object: nil,
            userInfo: ["requesterPID": Int(getpid())],
            deliverImmediately: true
        )
    }

    func startObservingOpenRequests(handler: @escaping @MainActor () -> Void) {
        observer = notificationCenter.addObserver(
            forName: Self.openRequestName,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                handler()
            }
        }
    }
}

@MainActor
private final class LauncherApplicationDelegate: NSObject, NSApplicationDelegate {
    private enum HIDUsage {
        static let volumeUp: UInt32 = 0x00E9
        static let volumeDown: UInt32 = 0x00EA
        static let center: UInt32 = 0x00CD
    }

    private enum PendingOnboardingAction {
        case confirmSelection(LauncherItem, Int)
    }

    private enum CipherSetupFlow {
        case initialSetup
        case rekey
    }

    private enum CipherLexiconEntryFlow {
        case ritual(CompanionRitualTarget)
        case intentMeaningPhrase
        case intentMeaningTarget(phrase: String)
        case macroPhrase
        case macroSteps(phrase: String)
        case appMeaningPhrase
        case appMeaningTarget(phrase: String)
        case correctionPhrase
        case correctionReplacement(phrase: String)
    }

    private enum CompanionUndoAction {
        case restoreTimer(snapshot: TimerCompanionSnapshot)
        case deleteCapturedQueueItem(itemID: String, title: String)
        case removeWorkSpellTasks(taskIDs: [String], summary: String)
        case restoreWorkSpellTasks(tasks: [WorkSpellTask], summary: String)
        case togglePlayback

        var label: String {
            switch self {
            case .restoreTimer:
                return "last timer change"
            case .deleteCapturedQueueItem(_, let title):
                return "capturing \(title)"
            case .removeWorkSpellTasks(_, let summary):
                return "adding \(summary) to Work Spell"
            case .restoreWorkSpellTasks(_, let summary):
                return "removing \(summary) from Work Spell"
            case .togglePlayback:
                return "the playback change"
            }
        }
    }

    private let config: LauncherConfig
    private let logger: NDJSONLogger
    private let items: [LauncherItem]
    private let singleInstanceCoordinator: SingleInstanceCoordinator?
    private let onboardingStateStore: OnboardingStateStore
    private let cipherConfigStore: CipherConfigStore
    private let workQueueStore: WorkQueueStore
    private let workSpellStore: WorkSpellStore
    private let companionConfigStore: CompanionConfigStore
    private let launcherBundleIdentifier = Bundle.main.bundleIdentifier

    private var listener: EarPodsHIDListener?
    private var hudController: LauncherHUDController?
    private var companionCardController: CompanionCardController?
    private var companionSpeechRecognizer = CompanionSpeechRecognizer()
    private let companionVoiceResponder = CompanionVoiceResponder()
    private var companionIntentParser: CompanionIntentParser?
    private var companionTask: Task<Void, Never>?
    private var companionTaskGeneration = 0
    private var companionVoiceTask: Task<Void, Never>?
    private var companionPermissionTask: Task<Void, Never>?
    private var companionPermissionGeneration = 0
    private var companionHoldToSpeakTask: Task<Void, Never>?
    private var companionPushToTalkActive = false
    private var companionConversationState = CompanionConversationState()
    private var companionLastIntentContext: CompanionIntentContext?
    private var companionLastTeachablePhrase: String?
    private var companionLiveTranscriptPreview: String?
    private var companionLastUndoAction: CompanionUndoAction?
    private var companionReopenLauncherOnClose = true
    private var supportCardController: SupportCardController?
    private var workSpellCardController: WorkSpellCardController?
    private var workSpellSettingsCardController: WorkSpellSettingsCardController?
    private var currentThreadCoordinator: CurrentThreadCoordinator?
    private var currentThreadCardController: CurrentThreadCardController?
    private var timerCoordinator: TimerCoordinator?
    private var timerCardController: TimerCardController?
    private var nowPlayingCoordinator: NowPlayingCoordinator?
    private var nowPlayingCardController: NowPlayingCardController?
    private var workQueueCoordinator: WorkQueueCoordinator?
    private var workQueueCardController: WorkQueueCardController?
    private var cipherCardController: CipherCardController?
    private var cipherLexiconCardController: CipherLexiconCardController?
    private var cipherLexiconEntryController: CipherLexiconEntryController?
    private var cipherUnlockFeedbackController: CipherUnlockFeedbackController?
    private var companionActionFeedbackController: PortalActionFeedbackController?
    private var cipherSetupController: CipherSetupController?
    private var activeCipherLexiconEntryFlow: CipherLexiconEntryFlow?
    private var activeCipherSetupFlow: CipherSetupFlow?
    private var pageOnboardingController: PageOnboardingController?
    private var activeOnboardingPage: OnboardingPageModel?
    private var pendingOnboardingAction: PendingOnboardingAction?
    private var portalRuntimeState = PortalRuntimeState()
    private let cipherSequenceRecognizer = CipherSequenceRecognizer()
    private var suppressedGestures: [GestureKind: Date] = [:]
    private var hudCenterPressStartedAt: Date?
    private var companionCenterPressStartedAt: Date?
    private var nowPlayingCenterPressStartedAt: Date?
    private var cipherCenterPressStartedAt: Date?
    private var cipherLexiconCenterPressStartedAt: Date?
    private var supportCenterPressStartedAt: Date?
    private var workSpellCenterPressStartedAt: Date?
    private var workSpellSettingsCenterPressStartedAt: Date?
    private var onboardingCenterPressStartedAt: Date?
    private var workQueueCenterPressStartedAt: Date?
    private var currentThreadCenterPressStartedAt: Date?
    private var hiddenCipherVolumeUpPressStartedAt: Date?
    private var hiddenCipherVolumeDownPressStartedAt: Date?
    private var timerAdjustmentRepeatGeneration = UUID()
    private var activeTimerAdjustmentUsage: UInt32?
    private var timerCompletionAlertGeneration = UUID()
    private var activeTimerCompletionSound: NSSound?
    private var cipherUnlockOpenTask: Task<Void, Never>?
    private var companionActionPulseTask: Task<Void, Never>?
    private var launcherReturnIndexFromTimer: Int?
    private var launcherReturnIndexFromNowPlaying: Int?
    private var launcherReturnIndexFromWorkQueue: Int?
    private var launcherReturnIndexFromCompanion: Int?
    private var launcherReturnIndexFromSupport: Int?
    private var launcherReturnIndexFromCurrentThread: Int?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var lastNonLauncherAppContext: WorkQueueAppContext?
    private var hasStopped = false

    private struct AppSemanticContext {
        let semanticTitle: String?
        let semanticDetail: String?
    }

    init(
        config: LauncherConfig,
        logger: NDJSONLogger,
        items: [LauncherItem],
        singleInstanceCoordinator: SingleInstanceCoordinator?,
        onboardingStateStore: OnboardingStateStore,
        cipherConfigStore: CipherConfigStore,
        workQueueStore: WorkQueueStore,
        workSpellStore: WorkSpellStore,
        companionConfigStore: CompanionConfigStore
    ) {
        self.config = config
        self.logger = logger
        self.items = items
        self.singleInstanceCoordinator = singleInstanceCoordinator
        self.onboardingStateStore = onboardingStateStore
        self.cipherConfigStore = cipherConfigStore
        self.workQueueStore = workQueueStore
        self.workSpellStore = workSpellStore
        self.companionConfigStore = companionConfigStore
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try start()
        } catch {
            emitFailureToUser(error.localizedDescription)
            stop()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stop()
    }

    func stop() {
        guard !hasStopped else {
            return
        }

        hasStopped = true
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
            self.workspaceActivationObserver = nil
        }
        portalHUDDebugSink = nil
        portalShouldActivateAppOnShow = false
        pageOnboardingController?.close()
        cipherUnlockOpenTask?.cancel()
        cipherUnlockOpenTask = nil
        cipherUnlockFeedbackController?.close()
        companionActionPulseTask?.cancel()
        companionActionPulseTask = nil
        companionActionFeedbackController?.close()
        _ = cipherSetupController?.close()
        activeCipherSetupFlow = nil
        _ = cipherLexiconEntryController?.close()
        activeCipherLexiconEntryFlow = nil
        _ = cipherLexiconCardController?.close()
        _ = timerCardController?.close()
        _ = nowPlayingCardController?.close()
        _ = workQueueCardController?.close()
        _ = workSpellCardController?.close()
        _ = workSpellSettingsCardController?.close()
        _ = supportCardController?.close()
        _ = currentThreadCardController?.close()
        _ = cipherCardController?.close()
        _ = companionCardController?.close()
        companionTask?.cancel()
        companionTask = nil
        companionSpeechRecognizer.cancel()
        hudController?.close()
        cancelTimerAdjustmentRepeat()
        cancelTimerCompletionAlert()
        timerCoordinator?.stop()
        nowPlayingCoordinator?.stop()
        listener?.stop()
        logger.close()
    }

    private func start() throws {
        if config.runtimeMode.diagnosticsEnabled {
            printHeader(title: launcherDisplayName)
            emitStdout("Background accessory app with Mac-style HUD.")
        }

        portalShouldActivateAppOnShow = config.runtimeMode == .bundledApp
        portalHUDDebugSink = { [weak self] message in
            self?.logStatus(name: "HUD_TRACE", note: message)
        }
        startTrackingFrontmostApplications()

        logStatus(name: "APP_START", note: "starting launcher runtime in \(config.runtimeMode == .bundledApp ? "bundled-app" : "command-line") mode")

        cipherSequenceRecognizer.updateSequence(cipherConfigStore.currentSequence ?? [])

        singleInstanceCoordinator?.startObservingOpenRequests { [weak self] in
            self?.handleExternalOpenRequest()
        }

        let listener = EarPodsHIDListener(
            configuration: HIDListenerConfiguration(
                seizeHIDDevice: true,
                multiClickWindow: 0.65,
                holdThreshold: 0.60
            )
        )
        self.listener = listener

        listener.onDeviceMatched = { [weak self] snapshot in
            self?.emitStdout("Device matched: \(snapshot.displayLine)")
        }
        listener.onDeviceRemoved = { [weak self] snapshot in
            self?.emitStdout("Device removed: \(snapshot.displayLine)")
        }
        listener.onRawEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleRawEvent(event)
            }
        }
        listener.onGesture = { [weak self] event in
            Task { @MainActor in
                self?.handleGesture(event)
            }
        }

        try listener.start()
        emitStdout("Exclusive HID listener acquired.")

        let timerCoordinator = TimerCoordinator()
        timerCoordinator.onUpdate = { [weak self] model in
            guard let self else {
                return
            }
            if let timerCardController = self.timerCardController, timerCardController.isVisible {
                timerCardController.update(model: model)
            }
        }
        timerCoordinator.onCompletion = { [weak self] in
            guard let self else {
                return
            }
            self.handleTimerCompletion()
        }
        self.timerCoordinator = timerCoordinator

        let nowPlayingCoordinator = NowPlayingCoordinator()
        nowPlayingCoordinator.onUpdate = { [weak self] model in
            guard let self else {
                return
            }
            if let nowPlayingCardController = self.nowPlayingCardController, nowPlayingCardController.isVisible {
                nowPlayingCardController.update(model: model)
            }
        }
        nowPlayingCoordinator.start()
        self.nowPlayingCoordinator = nowPlayingCoordinator
        self.currentThreadCoordinator = CurrentThreadCoordinator()
        self.workQueueCoordinator = WorkQueueCoordinator(store: workQueueStore)
        self.companionIntentParser = CompanionIntentParser(configStore: companionConfigStore)

        if config.runtimeMode.diagnosticsEnabled {
            emitStdout("Config: \(config.configPath)")
            emitStdout("Log file: \(logger.path)")
            emitStdout("Onboarding state: \(config.onboardingStatePath)")
            emitStdout("Cipher config: \(config.cipherConfigPath)")
            emitStdout("Work queue: \(config.workQueuePath)")
            emitStdout("Work spell: \(config.workSpellPath)")
            emitStdout("Companion config: \(config.companionConfigPath)")
            emitStdout("Exclusive seize: enabled")
            emitStdout("Idle timeout: \(Int(config.idleTimeout * 1000))ms")
            emitStdout("Launcher hidden. Hold center button to open. Press Control-C to stop.")
            emitStdout("HUD will be created lazily on first open.\n")

            let devices = listener.enumerateCurrentDevices()
            if devices.isEmpty {
                emitStdout("No consumer-control HID devices are currently visible.\n")
            } else {
                emitStdout("Currently matched devices:")
                for snapshot in devices {
                    emitStdout(snapshot.displayLine)
                }
                emitStdout("")
            }
        }

        if config.runtimeMode == .bundledApp {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
                Task { @MainActor in
                    self?.runBundledAppStartupFlow()
                }
            }
        }
    }

    private func handleRawEvent(_ event: HIDRawEvent) {
        logger.write(event.makeLogRecord(mode: "launcher"))

        if config.runtimeMode.diagnosticsEnabled {
            emitStdout("[\(event.timestamp)] RAW product=\(event.snapshot.product ?? "(unknown)") usagePage=\(event.usagePage) usage=\(event.usage) value=\(event.integerValue) phase=\(event.phase) event=\(event.eventName ?? "unknown")")
        }

        if event.phase == "down", config.runtimeMode.rawBeepsEnabled {
            playBeeps(1)
        }

        if handlePageOnboardingRawEvent(event) {
            return
        }

        if handleCipherSetupRawEvent(event) {
            return
        }

        if handleCipherLexiconRawEvent(event) {
            return
        }

        if handleCompanionRawEvent(event) {
            return
        }

        if handleWorkSpellSettingsRawEvent(event) {
            return
        }

        if handleWorkSpellRawEvent(event) {
            return
        }

        if handleSupportRawEvent(event) {
            return
        }

        if handleCurrentThreadRawEvent(event) {
            return
        }

        if handleTimerRawEvent(event) {
            return
        }

        if handleWorkQueueRawEvent(event) {
            return
        }

        if handleNowPlayingRawEvent(event) {
            return
        }

        if handleCipherUnlockFeedbackRawEvent(event) {
            return
        }

        if handleHiddenCipherRawEvent(event) {
            return
        }

        if handleCipherRawEvent(event) {
            return
        }

        _ = handleImmediateHUDRawEvent(event)
    }

    private func handleGesture(_ event: GestureEvent) {
        logger.write(event.makeLogRecord(mode: "launcher"))

        if config.runtimeMode.diagnosticsEnabled {
            emitStdout("[\(event.timestamp)] GESTURE gesture=\(event.gesture.rawValue) product=\(event.snapshot?.product ?? "(unknown)") sourceUsage=\(event.usage?.description ?? "n/a") note=\(event.note) hudVisible=\(hudController?.isVisible == true)")
        }

        if handleGlobalCompanionSummonGesture(event) {
            return
        }

        if handlePageOnboardingGesture(event) {
            return
        }

        if handleCipherSetupGesture(event) {
            return
        }

        if handleCipherLexiconEntryGesture(event) {
            return
        }

        if handleCipherLexiconGesture(event) {
            return
        }

        if handleCompanionGesture(event) {
            return
        }

        if handleWorkSpellSettingsGesture(event) {
            return
        }

        if handleWorkSpellGesture(event) {
            return
        }

        if handleSupportGesture(event) {
            return
        }

        if handleCurrentThreadGesture(event) {
            return
        }

        if handleTimerGesture(event) {
            return
        }

        if handleWorkQueueGesture(event) {
            return
        }

        if handleNowPlayingGesture(event) {
            return
        }

        if handleCipherUnlockFeedbackGesture(event) {
            return
        }

        if handleCipherGesture(event) {
            return
        }

        if shouldSuppressGesture(event.gesture) {
            logStatus(name: "HUD_SUPPRESSED_GESTURE", note: "suppressed delayed \(event.gesture.rawValue) after immediate HUD handling")
            return
        }

        if let hudController, hudController.isVisible {
            switch event.gesture {
            case .volumeUp:
                if let selection = hudController.moveSelection(by: -1) {
                    recordLastVisibleSurface(.launcher(selectedIndex: selection.index))
                    logStatus(name: "HUD_NAV", note: "moved up to \(selection.index): \(selection.item.title)")
                } else {
                    loudFailure(name: "HUD_NAV_FAILED", note: "volume_up arrived but no selection was available")
                }
            case .volumeDown:
                if let selection = hudController.moveSelection(by: 1) {
                    recordLastVisibleSurface(.launcher(selectedIndex: selection.index))
                    logStatus(name: "HUD_NAV", note: "moved down to \(selection.index): \(selection.item.title)")
                } else {
                    loudFailure(name: "HUD_NAV_FAILED", note: "volume_down arrived but no selection was available")
                }
            case .centerSingle:
                if let selection = hudController.confirmSelection() {
                    clearHUDInteractionState()
                    handleConfirmedSelection(item: selection.item, index: selection.index)
                } else {
                    loudFailure(name: "HUD_CONFIRM_FAILED", note: "center_single arrived but nothing was selected")
                }
            case .centerHold:
                let closed = hudController.close()
                if closed {
                    clearHUDInteractionState()
                    logStatus(name: "HUD_CLOSE", note: "closed by center_hold")
                } else {
                    loudFailure(name: "HUD_CLOSE_FAILED", note: "center_hold requested close but panel still appears visible")
                }
            default:
                logStatus(name: "HUD_IGNORED_GESTURE", note: "ignored \(event.gesture.rawValue) while HUD was open")
            }
            return
        }

        if handleHiddenCipherGesture(event) {
            return
        }

        cipherSequenceRecognizer.reset()
        if event.gesture == .centerHold {
            if workSpellStore.isActive {
                openWorkSpellCard(source: "center_hold")
            } else if portalRuntimeState.isSealed {
                logStatus(name: "CIPHER_SEAL_BLOCK", note: "ignored hidden center_hold because seal was enabled")
            } else {
                showMainHUD(source: "center_hold", selectedIndex: nil)
            }
        } else {
            loudFailure(name: "HIDDEN_IGNORED_GESTURE", note: "received \(event.gesture.rawValue) while HUD was hidden")
        }
    }

    private func handleGlobalCompanionSummonGesture(_ event: GestureEvent) -> Bool {
        guard event.gesture == .centerTriple else {
            return false
        }
        guard pageOnboardingController?.isVisible != true,
              cipherSetupController?.isVisible != true,
              cipherLexiconEntryController?.isVisible != true else {
            return false
        }

        if companionCardController?.isVisible == true {
            closeCompanionCard(source: "center_triple", reopenLauncher: false)
        } else {
            openCompactCompanion(source: "center_triple")
        }
        return true
    }

    private func handleImmediateHUDRawEvent(_ event: HIDRawEvent) -> Bool {
        guard event.usagePage == 12 else {
            return false
        }
        guard let hudController, hudController.isVisible else {
            return false
        }

        switch event.usage {
        case HIDUsage.volumeUp where event.phase == "down":
            if let selection = hudController.moveSelection(by: -1) {
                suppressGesture(.volumeUp)
                recordLastVisibleSurface(.launcher(selectedIndex: selection.index))
                logStatus(name: "HUD_NAV_RAW", note: "moved up immediately to \(selection.index): \(selection.item.title)")
                return true
            }
        case HIDUsage.volumeDown where event.phase == "down":
            if let selection = hudController.moveSelection(by: 1) {
                suppressGesture(.volumeDown)
                recordLastVisibleSurface(.launcher(selectedIndex: selection.index))
                logStatus(name: "HUD_NAV_RAW", note: "moved down immediately to \(selection.index): \(selection.item.title)")
                return true
            }
        case HIDUsage.center where event.phase == "down":
            hudCenterPressStartedAt = Date()
            logStatus(name: "HUD_CENTER_RAW", note: "center press began")
            return true
        case HIDUsage.center where event.phase == "up":
            guard let startedAt = hudCenterPressStartedAt else {
                return false
            }

            hudCenterPressStartedAt = nil
            let duration = Date().timeIntervalSince(startedAt)
            if duration < 0.55, let selection = hudController.confirmSelection() {
                suppressGesture(.centerSingle)
                logStatus(name: "HUD_CONFIRM_RAW", note: "confirmed immediately after \(Int(duration * 1000))ms press")
                clearHUDInteractionState()
                handleConfirmedSelection(item: selection.item, index: selection.index)
                return true
            }

            logStatus(name: "HUD_CENTER_RAW", note: "center released after \(Int(duration * 1000))ms without immediate confirm")
            return true
        default:
            break
        }

        return false
    }

    private func handleCipherRawEvent(_ event: HIDRawEvent) -> Bool {
        guard event.usagePage == 12 else {
            return false
        }
        guard let cipherCardController, cipherCardController.isVisible else {
            return false
        }

        switch event.usage {
        case HIDUsage.volumeUp where event.phase == "down":
            if let selection = cipherCardController.moveSelection(by: -1) {
                suppressGesture(.volumeUp)
                logStatus(name: "CIPHER_NAV_RAW", note: "moved up immediately to \(selection.index): \(selection.spell.title)")
                return true
            }
        case HIDUsage.volumeDown where event.phase == "down":
            if let selection = cipherCardController.moveSelection(by: 1) {
                suppressGesture(.volumeDown)
                logStatus(name: "CIPHER_NAV_RAW", note: "moved down immediately to \(selection.index): \(selection.spell.title)")
                return true
            }
        case HIDUsage.center where event.phase == "down":
            cipherCenterPressStartedAt = Date()
            logStatus(name: "CIPHER_CENTER_RAW", note: "center press began")
            return true
        case HIDUsage.center where event.phase == "up":
            guard let startedAt = cipherCenterPressStartedAt else {
                return false
            }

            cipherCenterPressStartedAt = nil
            let duration = Date().timeIntervalSince(startedAt)
            if duration < 0.55, let selection = cipherCardController.confirmSelection() {
                suppressGesture(.centerSingle)
                logStatus(name: "CIPHER_CONFIRM_RAW", note: "confirmed immediately after \(Int(duration * 1000))ms press")
                handleCipherSelection(spell: selection.spell, index: selection.index)
                return true
            }

            logStatus(name: "CIPHER_CENTER_RAW", note: "center released after \(Int(duration * 1000))ms without immediate confirm")
            return true
        default:
            break
        }

        return false
    }

    private func handleCipherLexiconRawEvent(_ event: HIDRawEvent) -> Bool {
        guard event.usagePage == 12 else {
            return false
        }
        guard let cipherLexiconCardController, cipherLexiconCardController.isVisible else {
            return false
        }

        switch event.usage {
        case HIDUsage.volumeUp where event.phase == "down":
            if let selection = cipherLexiconCardController.moveSelection(by: -1) {
                suppressGesture(.volumeUp)
                if case .row(let row, let index) = selection {
                    logStatus(name: "CIPHER_LEXICON_NAV_RAW", note: "moved up immediately to \(index): \(row.title)")
                }
                return true
            }
        case HIDUsage.volumeDown where event.phase == "down":
            if let selection = cipherLexiconCardController.moveSelection(by: 1) {
                suppressGesture(.volumeDown)
                if case .row(let row, let index) = selection {
                    logStatus(name: "CIPHER_LEXICON_NAV_RAW", note: "moved down immediately to \(index): \(row.title)")
                }
                return true
            }
        case HIDUsage.center where event.phase == "down":
            cipherLexiconCenterPressStartedAt = Date()
            logStatus(name: "CIPHER_LEXICON_CENTER_RAW", note: "center press began")
            return true
        case HIDUsage.center where event.phase == "up":
            guard let startedAt = cipherLexiconCenterPressStartedAt else {
                return false
            }

            cipherLexiconCenterPressStartedAt = nil
            let duration = Date().timeIntervalSince(startedAt)
            if duration < 0.55, let selection = cipherLexiconCardController.confirmSelection() {
                suppressGesture(.centerSingle)
                logStatus(name: "CIPHER_LEXICON_CONFIRM_RAW", note: "confirmed immediately after \(Int(duration * 1000))ms press")
                handleCipherLexiconSelection(selection)
                return true
            }

            logStatus(name: "CIPHER_LEXICON_CENTER_RAW", note: "center released after \(Int(duration * 1000))ms without immediate confirm")
            return true
        default:
            break
        }

        return false
    }

    private func handleCipherUnlockFeedbackRawEvent(_ event: HIDRawEvent) -> Bool {
        guard event.usagePage == 12 else {
            return false
        }
        guard let cipherUnlockFeedbackController, cipherUnlockFeedbackController.isVisible else {
            return false
        }
        return true
    }

    private func handleHiddenCipherRawEvent(_ event: HIDRawEvent) -> Bool {
        guard isPortalFullyHidden else {
            return false
        }
        guard event.usagePage == 12 else {
            return false
        }

        switch event.usage {
        case HIDUsage.volumeUp where event.phase == "down":
            hiddenCipherVolumeUpPressStartedAt = Date()
            return false
        case HIDUsage.volumeUp where event.phase == "up":
            defer { hiddenCipherVolumeUpPressStartedAt = nil }
            guard let startedAt = hiddenCipherVolumeUpPressStartedAt else {
                return false
            }

            let duration = Date().timeIntervalSince(startedAt)
            guard duration < 0.55 else {
                return false
            }

            suppressHiddenCipherVolumeFamily(.volumeUp)
            return handleHiddenCipherOutcome(
                cipherSequenceRecognizer.consume(.volumeUp),
                trigger: "raw volume_up"
            )
        case HIDUsage.volumeDown where event.phase == "down":
            hiddenCipherVolumeDownPressStartedAt = Date()
            return false
        case HIDUsage.volumeDown where event.phase == "up":
            defer { hiddenCipherVolumeDownPressStartedAt = nil }
            guard let startedAt = hiddenCipherVolumeDownPressStartedAt else {
                return false
            }

            let duration = Date().timeIntervalSince(startedAt)
            guard duration < 0.55 else {
                return false
            }

            suppressHiddenCipherVolumeFamily(.volumeDown)
            return handleHiddenCipherOutcome(
                cipherSequenceRecognizer.consume(.volumeDown),
                trigger: "raw volume_down"
            )
        default:
            return false
        }
    }

    private func handleNowPlayingRawEvent(_ event: HIDRawEvent) -> Bool {
        guard event.usagePage == 12 else {
            return false
        }
        guard let nowPlayingCardController, nowPlayingCardController.isVisible else {
            return false
        }

        switch event.usage {
        case HIDUsage.volumeUp where event.phase == "down":
            if let selection = nowPlayingCardController.moveSelection(by: -1) {
                suppressGesture(.volumeUp)
                logStatus(name: "NOW_PLAYING_NAV_RAW", note: "moved up immediately to \(selection.index): \(selection.action.title)")
                return true
            }
        case HIDUsage.volumeDown where event.phase == "down":
            if let selection = nowPlayingCardController.moveSelection(by: 1) {
                suppressGesture(.volumeDown)
                logStatus(name: "NOW_PLAYING_NAV_RAW", note: "moved down immediately to \(selection.index): \(selection.action.title)")
                return true
            }
        case HIDUsage.center where event.phase == "down":
            nowPlayingCenterPressStartedAt = Date()
            logStatus(name: "NOW_PLAYING_CENTER_RAW", note: "center press began")
            return true
        case HIDUsage.center where event.phase == "up":
            guard let startedAt = nowPlayingCenterPressStartedAt else {
                return false
            }

            nowPlayingCenterPressStartedAt = nil
            let duration = Date().timeIntervalSince(startedAt)
            if duration < 0.55, let selection = nowPlayingCardController.confirmSelection() {
                suppressGesture(.centerSingle)
                logStatus(name: "NOW_PLAYING_CONFIRM_RAW", note: "confirmed immediately after \(Int(duration * 1000))ms press")
                handleNowPlayingSelection(action: selection.action, index: selection.index)
                return true
            }

            logStatus(name: "NOW_PLAYING_CENTER_RAW", note: "center released after \(Int(duration * 1000))ms without immediate confirm")
            return true
        default:
            break
        }

        return false
    }

    private func handleWorkQueueRawEvent(_ event: HIDRawEvent) -> Bool {
        guard event.usagePage == 12 else {
            return false
        }
        guard let workQueueCardController, workQueueCardController.isVisible else {
            return false
        }

        switch event.usage {
        case HIDUsage.volumeUp where event.phase == "down":
            if let selection = workQueueCardController.moveSelection(by: -1) {
                suppressGesture(.volumeUp)
                if case .listRow(_, let index) = selection {
                    recordLastVisibleSurface(.workQueue(selectedIndex: index))
                }
                logStatus(name: "WORK_QUEUE_NAV_RAW", note: "moved up immediately in work queue")
                return true
            }
        case HIDUsage.volumeDown where event.phase == "down":
            if let selection = workQueueCardController.moveSelection(by: 1) {
                suppressGesture(.volumeDown)
                if case .listRow(_, let index) = selection {
                    recordLastVisibleSurface(.workQueue(selectedIndex: index))
                }
                logStatus(name: "WORK_QUEUE_NAV_RAW", note: "moved down immediately in work queue")
                return true
            }
        case HIDUsage.center where event.phase == "down":
            workQueueCenterPressStartedAt = Date()
            logStatus(name: "WORK_QUEUE_CENTER_RAW", note: "center press began")
            return true
        case HIDUsage.center where event.phase == "up":
            guard let startedAt = workQueueCenterPressStartedAt else {
                return false
            }

            workQueueCenterPressStartedAt = nil
            let duration = Date().timeIntervalSince(startedAt)
            if duration < 0.55, let selection = workQueueCardController.confirmSelection() {
                suppressGesture(.centerSingle)
                logStatus(name: "WORK_QUEUE_CONFIRM_RAW", note: "confirmed immediately after \(Int(duration * 1000))ms press")
                handleWorkQueueSelection(selection)
                return true
            }

            logStatus(name: "WORK_QUEUE_CENTER_RAW", note: "center released after \(Int(duration * 1000))ms without immediate confirm")
            return true
        default:
            break
        }

        return false
    }

    private func handleTimerRawEvent(_ event: HIDRawEvent) -> Bool {
        guard event.usagePage == 12 else {
            return false
        }
        guard let timerCardController, timerCardController.isVisible, let timerCoordinator else {
            return false
        }

        cancelTimerCompletionAlert()

        switch event.usage {
        case HIDUsage.volumeUp where event.phase == "down":
            adjustTimer(direction: 1)
            beginTimerAdjustmentRepeat(direction: 1, usage: HIDUsage.volumeUp)
            suppressGesture(.volumeUp)
            return true
        case HIDUsage.volumeUp where event.phase == "up":
            cancelTimerAdjustmentRepeat(for: HIDUsage.volumeUp)
            return true
        case HIDUsage.volumeDown where event.phase == "down":
            adjustTimer(direction: -1)
            beginTimerAdjustmentRepeat(direction: -1, usage: HIDUsage.volumeDown)
            suppressGesture(.volumeDown)
            return true
        case HIDUsage.volumeDown where event.phase == "up":
            cancelTimerAdjustmentRepeat(for: HIDUsage.volumeDown)
            return true
        case HIDUsage.center where event.phase == "down":
            cancelTimerAdjustmentRepeat()
            _ = timerCoordinator
            return false
        case HIDUsage.center where event.phase == "up":
            cancelTimerAdjustmentRepeat()
            _ = timerCoordinator
            return false
        default:
            _ = timerCardController
            return false
        }
    }

    private func handlePageOnboardingRawEvent(_ event: HIDRawEvent) -> Bool {
        guard let pageOnboardingController, pageOnboardingController.isVisible, let activeOnboardingPage else {
            return false
        }
        guard event.usagePage == 12 else {
            return false
        }

        switch event.usage {
        case HIDUsage.volumeUp where event.phase == "down":
            let completedNow = pageOnboardingController.markCompleted(.volumeUp)
            suppressGesture(.volumeUp)
            if completedNow {
                logStatus(name: "ONBOARDING_STEP", note: "completed volume_up step for \(activeOnboardingPage.id.rawValue)")
            }
            return true
        case HIDUsage.volumeDown where event.phase == "down":
            let completedNow = pageOnboardingController.markCompleted(.volumeDown)
            suppressGesture(.volumeDown)
            if completedNow {
                logStatus(name: "ONBOARDING_STEP", note: "completed volume_down step for \(activeOnboardingPage.id.rawValue)")
            }
            return true
        case HIDUsage.center where event.phase == "down":
            onboardingCenterPressStartedAt = Date()
            return true
        case HIDUsage.center where event.phase == "up":
            guard let startedAt = onboardingCenterPressStartedAt else {
                return true
            }

            onboardingCenterPressStartedAt = nil
            let duration = Date().timeIntervalSince(startedAt)
            if duration < 0.55 {
                let completedNow = pageOnboardingController.markCompleted(.centerTap)
                suppressGesture(.centerSingle)
                if completedNow {
                    logStatus(name: "ONBOARDING_STEP", note: "completed center_tap step for \(activeOnboardingPage.id.rawValue)")
                }
            }
            return true
        default:
            return true
        }

    }

    private func handleCipherSetupRawEvent(_ event: HIDRawEvent) -> Bool {
        guard let cipherSetupController, cipherSetupController.isVisible else {
            return false
        }
        return event.usagePage == 12
    }

    private func handleCipherUnlockFeedbackGesture(_ event: GestureEvent) -> Bool {
        guard let cipherUnlockFeedbackController, cipherUnlockFeedbackController.isVisible else {
            return false
        }

        logStatus(name: "CIPHER_REVEAL_SUPPRESSED_GESTURE", note: "suppressed \(event.gesture.rawValue) during cipher unlock reveal")
        return true
    }

    private func handleHiddenCipherOutcome(_ outcome: CipherSequenceOutcome, trigger: String) -> Bool {
        switch outcome {
        case .ignored:
            return false
        case .progressed(let step, let total):
            logStatus(name: "CIPHER_STEP", note: "accepted \(trigger) as step \(step)/\(total)")
            return true
        case .reset(let reason):
            logStatus(name: "CIPHER_RESET", note: "\(reason) after \(trigger)")
            return true
        case .unlocked:
            if portalRuntimeState.isSealed {
                portalRuntimeState.isSealed = false
                logStatus(name: "CIPHER_SEAL_CLEAR", note: "cleared seal after successful cipher unlock")
            }
            logStatus(name: "CIPHER_UNLOCK", note: "unlocked with hidden sequence")
            presentCipherUnlockReveal()
            return true
        }
    }

    private func handlePageOnboardingGesture(_ event: GestureEvent) -> Bool {
        guard let pageOnboardingController, pageOnboardingController.isVisible, let activeOnboardingPage else {
            return false
        }

        if shouldSuppressGesture(event.gesture) {
            logStatus(name: "ONBOARDING_SUPPRESSED_GESTURE", note: "suppressed delayed \(event.gesture.rawValue) during \(activeOnboardingPage.id.rawValue) onboarding")
            return true
        }

        switch event.gesture {
        case .centerDouble:
            if pageOnboardingController.markCompleted(.centerDouble) {
                logStatus(name: "ONBOARDING_STEP", note: "completed center_double step for \(activeOnboardingPage.id.rawValue)")
            }
            return true
        case activeOnboardingPage.dismissalGesture:
            if pageOnboardingController.canDismissNow {
                if let dismissalStepID = activeOnboardingPage.dismissalStepID {
                    _ = pageOnboardingController.markCompleted(dismissalStepID)
                }
                finishActiveOnboarding(source: event.gesture.rawValue)
            } else {
                pageOnboardingController.showBlockedDismissalHint()
                logStatus(name: "ONBOARDING_BLOCKED_CLOSE", note: "attempted to leave \(activeOnboardingPage.id.rawValue) onboarding before required steps were complete")
            }
            return true
        default:
            logStatus(name: "ONBOARDING_IGNORED_GESTURE", note: "ignored \(event.gesture.rawValue) while \(activeOnboardingPage.id.rawValue) onboarding was active")
            return true
        }
    }

    private func handleCipherSetupGesture(_ event: GestureEvent) -> Bool {
        guard let cipherSetupController, cipherSetupController.isVisible else {
            return false
        }

        switch event.gesture {
        case .volumeUp, .volumeDown, .centerSingle, .centerDouble:
            switch cipherSetupController.appendStep(event.gesture) {
            case .ignored:
                break
            case .recorded(let step, let total):
                logStatus(name: "CIPHER_SETUP_STEP", note: "recorded \(event.gesture.rawValue) as step \(step)/\(total)")
            case .movedToConfirmation:
                logStatus(name: "CIPHER_SETUP_CONFIRM", note: "recorded initial cipher code and moved to confirmation")
            case .confirmationProgress(let step, let total):
                logStatus(name: "CIPHER_SETUP_MATCH", note: "confirmed step \(step)/\(total) with \(event.gesture.rawValue)")
            case .mismatch:
                logStatus(name: "CIPHER_SETUP_MISMATCH", note: "confirmation gesture did not match the recorded code")
            case .ready:
                logStatus(name: "CIPHER_SETUP_READY", note: "cipher code confirmed and ready to save")
            }
            return true
        case .volumeDownHold:
            cipherSetupController.resetSequence()
            logStatus(name: "CIPHER_SETUP_RESET", note: "reset cipher setup with volume_down_hold")
            return true
        case .centerHold:
            if cipherSetupController.canSave, let sequence = cipherSetupController.configuredSequence {
                do {
                    try cipherConfigStore.save(sequence: sequence)
                    cipherSequenceRecognizer.updateSequence(sequence)
                    let sequenceText = sequence.map { $0.rawValue }.joined(separator: ",")
                    let flow = activeCipherSetupFlow ?? .initialSetup
                    if closeActiveCipherSetup() {
                        clearHUDInteractionState()
                        switch flow {
                        case .initialSetup:
                            logStatus(name: "CIPHER_SETUP_SAVED", note: "saved custom cipher code with \(sequenceText)")
                        case .rekey:
                            logStatus(name: "CIPHER_REKEY_SAVED", note: "saved new cipher code with \(sequenceText)")
                            openCipherCard(
                                source: "cipher-rekey-saved",
                                selectedIndex: cipherSpellIndex(for: .rekey)
                            )
                        }
                    } else {
                        loudFailure(name: "CIPHER_SETUP_CLOSE_FAILED", note: "cipher setup saved but the setup overlay did not close")
                    }
                } catch {
                    loudFailure(name: "CIPHER_SETUP_SAVE_FAILED", note: error.localizedDescription)
                }
                return true
            }

            if activeCipherSetupFlow == .rekey {
                if closeActiveCipherSetup() {
                    clearHUDInteractionState()
                    logStatus(name: "CIPHER_REKEY_CANCEL", note: "canceled rekey and kept the existing cipher code")
                    openCipherCard(
                        source: "cipher-rekey-cancel",
                        selectedIndex: cipherSpellIndex(for: .rekey)
                    )
                } else {
                    loudFailure(name: "CIPHER_REKEY_CANCEL_FAILED", note: "attempted to cancel rekey but the setup overlay did not close")
                }
                return true
            }

            cipherSetupController.showBlockedSaveHint()
            logStatus(name: "CIPHER_SETUP_BLOCKED_SAVE", note: "attempted to save cipher before confirmation was complete")
            return true
        default:
            return true
        }

    }

    private func handleCipherLexiconEntryGesture(_ event: GestureEvent) -> Bool {
        guard let cipherLexiconEntryController, cipherLexiconEntryController.isVisible else {
            return false
        }

        switch event.gesture {
        case .centerHold:
            closeCipherLexiconEntry(source: "center_hold", reopenLexicon: true)
        default:
            logStatus(name: "CIPHER_LEXICON_ENTRY_IGNORED_GESTURE", note: "ignored \(event.gesture.rawValue) while lexicon entry was open")
        }

        return true
    }

    private func handleCipherLexiconGesture(_ event: GestureEvent) -> Bool {
        guard let cipherLexiconCardController, cipherLexiconCardController.isVisible else {
            return false
        }

        if shouldSuppressGesture(event.gesture) {
            logStatus(name: "CIPHER_LEXICON_SUPPRESSED_GESTURE", note: "suppressed delayed \(event.gesture.rawValue) while cipher lexicon was open")
            return true
        }

        switch event.gesture {
        case .volumeUp:
            if let selection = cipherLexiconCardController.moveSelection(by: -1) {
                if case .row(let row, let index) = selection {
                    logStatus(name: "CIPHER_LEXICON_NAV", note: "moved up to \(index): \(row.title)")
                }
            } else {
                loudFailure(name: "CIPHER_LEXICON_NAV_FAILED", note: "volume_up arrived but no lexicon row was selectable")
            }
        case .volumeDown:
            if let selection = cipherLexiconCardController.moveSelection(by: 1) {
                if case .row(let row, let index) = selection {
                    logStatus(name: "CIPHER_LEXICON_NAV", note: "moved down to \(index): \(row.title)")
                }
            } else {
                loudFailure(name: "CIPHER_LEXICON_NAV_FAILED", note: "volume_down arrived but no lexicon row was selectable")
            }
        case .centerSingle:
            if let selection = cipherLexiconCardController.confirmSelection() {
                handleCipherLexiconSelection(selection)
            } else {
                loudFailure(name: "CIPHER_LEXICON_CONFIRM_FAILED", note: "center_single arrived but nothing in the lexicon was selectable")
            }
        case .centerHold:
            closeCipherLexiconCard(source: "center_hold", reopenCipher: true)
        default:
            logStatus(name: "CIPHER_LEXICON_IGNORED_GESTURE", note: "ignored \(event.gesture.rawValue) while cipher lexicon was open")
        }

        return true
    }

    private func handleNowPlayingGesture(_ event: GestureEvent) -> Bool {
        guard let nowPlayingCardController, nowPlayingCardController.isVisible else {
            return false
        }

        if shouldSuppressGesture(event.gesture) {
            logStatus(name: "NOW_PLAYING_SUPPRESSED_GESTURE", note: "suppressed delayed \(event.gesture.rawValue) while now-playing card was open")
            return true
        }

        switch event.gesture {
        case .volumeUp:
            if let selection = nowPlayingCardController.moveSelection(by: -1) {
                logStatus(name: "NOW_PLAYING_NAV", note: "moved up to \(selection.index): \(selection.action.title)")
            } else {
                loudFailure(name: "NOW_PLAYING_NAV_FAILED", note: "volume_up arrived but the now-playing action list was empty")
            }
        case .volumeDown:
            if let selection = nowPlayingCardController.moveSelection(by: 1) {
                logStatus(name: "NOW_PLAYING_NAV", note: "moved down to \(selection.index): \(selection.action.title)")
            } else {
                loudFailure(name: "NOW_PLAYING_NAV_FAILED", note: "volume_down arrived but the now-playing action list was empty")
            }
        case .centerSingle:
            if let selection = nowPlayingCardController.confirmSelection() {
                handleNowPlayingSelection(action: selection.action, index: selection.index)
            } else {
                loudFailure(name: "NOW_PLAYING_CONFIRM_FAILED", note: "center_single arrived but nothing was selected in the now-playing card")
            }
        case .centerHold:
            closeNowPlayingCard(source: "center_hold", reopenLauncher: true)
        default:
            logStatus(name: "NOW_PLAYING_IGNORED_GESTURE", note: "ignored \(event.gesture.rawValue) while now-playing card was open")
        }

        return true
    }

    private func handleWorkQueueGesture(_ event: GestureEvent) -> Bool {
        guard let workQueueCardController, workQueueCardController.isVisible else {
            return false
        }

        if shouldSuppressGesture(event.gesture) {
            logStatus(name: "WORK_QUEUE_SUPPRESSED_GESTURE", note: "suppressed delayed \(event.gesture.rawValue) while work queue was open")
            return true
        }

        switch event.gesture {
        case .volumeUp:
            if let selection = workQueueCardController.moveSelection(by: -1) {
                if case .listRow(_, let index) = selection {
                    recordLastVisibleSurface(.workQueue(selectedIndex: index))
                }
                logStatus(name: "WORK_QUEUE_NAV", note: "moved up in work queue")
            } else {
                loudFailure(name: "WORK_QUEUE_NAV_FAILED", note: "volume_up arrived but there was no selectable work queue row")
            }
        case .volumeDown:
            if let selection = workQueueCardController.moveSelection(by: 1) {
                if case .listRow(_, let index) = selection {
                    recordLastVisibleSurface(.workQueue(selectedIndex: index))
                }
                logStatus(name: "WORK_QUEUE_NAV", note: "moved down in work queue")
            } else {
                loudFailure(name: "WORK_QUEUE_NAV_FAILED", note: "volume_down arrived but there was no selectable work queue row")
            }
        case .centerSingle:
            if let selection = workQueueCardController.confirmSelection() {
                handleWorkQueueSelection(selection)
            } else {
                loudFailure(name: "WORK_QUEUE_CONFIRM_FAILED", note: "center_single arrived but nothing in work queue was selectable")
            }
        case .centerDouble:
            if workQueueCardController.isShowingDetail {
                if workQueueCardController.currentDetailMode == .labelPicker,
                   let itemID = workQueueCardController.currentDetailItemID {
                    showWorkQueueDetail(itemID: itemID, source: "center_double-label-picker", selectedIndex: 1)
                } else {
                    showWorkQueueList(source: "center_double", selectedItemID: workQueueCardController.currentDetailItemID)
                }
            } else {
                handleWorkQueueQuickRemove()
            }
        case .centerHold:
            closeWorkQueueCard(source: "center_hold", reopenLauncher: true)
        default:
            logStatus(name: "WORK_QUEUE_IGNORED_GESTURE", note: "ignored \(event.gesture.rawValue) while work queue was open")
        }

        return true
    }

    private func handleTimerGesture(_ event: GestureEvent) -> Bool {
        guard let timerCardController, timerCardController.isVisible, let timerCoordinator else {
            return false
        }

        cancelTimerAdjustmentRepeat()
        cancelTimerCompletionAlert()

        if shouldSuppressGesture(event.gesture) {
            logStatus(name: "TIMER_SUPPRESSED_GESTURE", note: "suppressed delayed \(event.gesture.rawValue) while timer was open")
            return true
        }

        switch event.gesture {
        case .centerSingle:
            switch timerCoordinator.advanceOrPrimaryAction() {
            case .movedForward:
                logStatus(name: "TIMER_NAV", note: "advanced to the next timer row")
            case .started:
                logStatus(name: "TIMER_START", note: "started timer from the seconds row")
            case .blockedZero:
                loudFailure(name: "TIMER_START_BLOCKED", note: "cannot start a timer with zero duration")
            case .toggledPauseResume:
                logStatus(name: "TIMER_TOGGLE", note: "toggled timer pause/resume")
            case .resetAfterFinish:
                logStatus(name: "TIMER_RESET", note: "reset finished timer back to its last duration")
            }
        case .centerDouble:
            timerCoordinator.moveBack()
            logStatus(name: "TIMER_BACK", note: "moved backward in the timer flow")
        case .centerHold:
            timerCoordinator.hideToLauncher()
            closeTimerCard(source: "center_hold", reopenLauncher: true)
        case .volumeUp, .volumeDown:
            return true
        default:
            logStatus(name: "TIMER_IGNORED_GESTURE", note: "ignored \(event.gesture.rawValue) while timer was open")
        }

        return true
    }

    private func handleCipherGesture(_ event: GestureEvent) -> Bool {
        guard let cipherCardController, cipherCardController.isVisible else {
            return false
        }

        if shouldSuppressGesture(event.gesture) {
            logStatus(name: "CIPHER_SUPPRESSED_GESTURE", note: "suppressed delayed \(event.gesture.rawValue) while cipher was open")
            return true
        }

        switch event.gesture {
        case .volumeUp:
            if let selection = cipherCardController.moveSelection(by: -1) {
                logStatus(name: "CIPHER_NAV", note: "moved up to \(selection.index): \(selection.spell.title)")
            } else {
                loudFailure(name: "CIPHER_NAV_FAILED", note: "volume_up arrived but no cipher spell was selectable")
            }
        case .volumeDown:
            if let selection = cipherCardController.moveSelection(by: 1) {
                logStatus(name: "CIPHER_NAV", note: "moved down to \(selection.index): \(selection.spell.title)")
            } else {
                loudFailure(name: "CIPHER_NAV_FAILED", note: "volume_down arrived but no cipher spell was selectable")
            }
        case .centerSingle:
            if let selection = cipherCardController.confirmSelection() {
                handleCipherSelection(spell: selection.spell, index: selection.index)
            } else {
                loudFailure(name: "CIPHER_CONFIRM_FAILED", note: "center_single arrived but no enabled cipher spell was selected")
            }
        case .centerHold:
            closeCipherCard(source: "center_hold")
        default:
            logStatus(name: "CIPHER_IGNORED_GESTURE", note: "ignored \(event.gesture.rawValue) while cipher was open")
        }

        return true
    }

    private func handleConfirmedSelection(item: LauncherItem, index: Int) {
        if item.id == "companion" {
            openCompanionCard(fromLauncherIndex: index, source: "launcher-selection")
            return
        }

        if item.id == LauncherItem.supportItem.id {
            openSupportCard(fromLauncherIndex: index, source: "launcher-selection")
            return
        }

        if item.id == "current-thread" {
            openCurrentThreadCard(fromLauncherIndex: index, source: "launcher-selection")
            return
        }

        if item.id == "work-queue" {
            openWorkQueueCard(fromLauncherIndex: index, source: "launcher-selection")
            return
        }

        if item.id == "timer" {
            if onboardingStateStore.isCompleted(.timer) {
                openTimerCard(fromLauncherIndex: index, source: "launcher-selection")
            } else {
                pendingOnboardingAction = .confirmSelection(item, index)
                presentPageOnboarding(.timer, source: "timer-selection")
            }
            return
        }

        if item.id == "now-playing" {
            openNowPlayingCard(fromLauncherIndex: index, source: "launcher-selection")
            return
        }

        switch item.action {
        case .placeholder:
            logLaunch(item: item, index: index)
            if config.runtimeMode.selectionNotificationsEnabled {
                displayPortalNotification(title: launcherDisplayName, body: "Selected \(item.title)")
            }
        case .quitApp:
            logStatus(name: "APP_QUIT", note: "selected quit row from HUD")
            stop()
            NSApp.terminate(nil)
        }
    }

    private func handleExternalOpenRequest() {
        if let cipherSetupController, cipherSetupController.isVisible {
            let _ = cipherSetupController.show()
            logStatus(name: "CIPHER_SETUP_ACTIVE", note: "received external open request while cipher setup was still active")
            return
        }

        if let cipherUnlockFeedbackController, cipherUnlockFeedbackController.isVisible {
            logStatus(name: "CIPHER_REVEAL_ACTIVE", note: "received external open request while cipher unlock reveal was still active")
            return
        }

        if let pageOnboardingController, pageOnboardingController.isVisible, let activeOnboardingPage {
            let _ = pageOnboardingController.show()
            logStatus(name: "ONBOARDING_ACTIVE", note: "received external open request while \(activeOnboardingPage.id.rawValue) onboarding was still active")
            return
        }

        if let cipherCardController, cipherCardController.isVisible {
            let _ = cipherCardController.show(model: makeCipherCardModel())
            logStatus(name: "CIPHER_ACTIVE", note: "received external open request while cipher was already visible")
            return
        }

        if let currentThreadCardController, currentThreadCardController.isVisible {
            if currentThreadCardController.reshowCurrentState() {
                recordLastVisibleSurface(.currentThread)
                logStatus(name: "CURRENT_THREAD_ACTIVE", note: "received external open request while current-thread was already visible")
            }
            return
        }

        if let timerCardController, timerCardController.isVisible, let timerCoordinator {
            _ = timerCardController.show(model: timerCoordinator.currentModel())
            recordLastVisibleSurface(.timer)
            logStatus(name: "TIMER_ACTIVE", note: "received external open request while timer was already visible")
            return
        }

        if let nowPlayingCardController, nowPlayingCardController.isVisible {
            if let nowPlayingCoordinator {
                _ = nowPlayingCardController.show(model: nowPlayingCoordinator.currentModel)
                recordLastVisibleSurface(.nowPlaying)
                logStatus(name: "NOW_PLAYING_ACTIVE", note: "received external open request while now-playing card was already visible")
            }
            return
        }

        if let workQueueCardController, workQueueCardController.isVisible {
            if workQueueCardController.reshowCurrentState() {
                if case .listRow(_, let selectedIndex)? = workQueueCardController.currentSelection() {
                    recordLastVisibleSurface(.workQueue(selectedIndex: selectedIndex))
                }
                logStatus(name: "WORK_QUEUE_ACTIVE", note: "received external open request while work queue was already visible")
            }
            return
        }

        if let workSpellSettingsCardController, workSpellSettingsCardController.isVisible {
            _ = workSpellSettingsCardController.show(model: makeWorkSpellSettingsModel())
            logStatus(name: "WORK_SPELL_SETTINGS_ACTIVE", note: "received external open request while work-spell settings were already visible")
            return
        }

        if let workSpellCardController, workSpellCardController.isVisible {
            if workSpellCardController.reshowCurrentState() {
                if case .row(_, let selectedIndex)? = workSpellCardController.currentSelection() {
                    recordLastVisibleSurface(.workSpell(selectedIndex: selectedIndex))
                }
                logStatus(name: "WORK_SPELL_ACTIVE", note: "received external open request while Work Spell was already visible")
            }
            return
        }

        if let companionCardController, companionCardController.isVisible {
            let _ = companionCardController.show(model: makeCompanionStatusModel(
                title: "Companion",
                subtitle: "Still here.",
                transcript: "",
                footer: "Hold center to speak. Double-center closes.",
                symbol: "waveform.badge.mic",
                phase: .success
            ), mode: companionCardController.currentPresentationMode, anchor: companionCardController.currentAnchorMode)
            logStatus(name: "COMPANION_ACTIVE", note: "received external open request while companion was already visible")
            return
        }

        showMainHUD(source: "external-open-request", selectedIndex: nil)
    }

    private func openHUD(source: String) {
        showMainHUD(source: source, selectedIndex: nil)
    }

    private func showMainHUD(source: String, selectedIndex: Int?) {
        if let cipherSetupController, cipherSetupController.isVisible {
            logStatus(name: "CIPHER_SETUP_ACTIVE", note: "refused HUD open via \(source) while cipher setup was active")
            return
        }

        if let cipherUnlockFeedbackController, cipherUnlockFeedbackController.isVisible {
            logStatus(name: "CIPHER_REVEAL_ACTIVE", note: "refused HUD open via \(source) while cipher unlock reveal was active")
            return
        }

        if let pageOnboardingController, pageOnboardingController.isVisible, let activeOnboardingPage {
            logStatus(name: "ONBOARDING_ACTIVE", note: "refused HUD open via \(source) while \(activeOnboardingPage.id.rawValue) onboarding was active")
            return
        }

        guard let hudController = ensureHUDController() else {
            loudFailure(name: "HUD_INIT_FAILED", note: "unable to create the HUD controller")
            return
        }

        cipherSequenceRecognizer.reset()
        clearHUDInteractionState()
        let shown = hudController.show(selectedIndex: selectedIndex)
        if shown, let selection = hudController.currentSelection() {
            recordLastVisibleSurface(.launcher(selectedIndex: selection.index))
            logStatus(name: "HUD_OPEN", note: "opened via \(source) with selection \(selection.index): \(selection.item.title)")
        } else {
            loudFailure(name: "HUD_OPEN_FAILED", note: "\(source) was recognized but the HUD did not become visible")
        }
    }

    private func ensureHUDController() -> LauncherHUDController? {
        if let hudController {
            return hudController
        }

        logStatus(name: "HUD_INIT", note: "creating HUD controller")
        let controller = LauncherHUDController(items: items, idleTimeout: config.idleTimeout)
        self.hudController = controller
        logStatus(name: "HUD_INIT", note: "HUD controller created")
        return controller
    }

    private func ensureTimerCardController() -> TimerCardController {
        if let timerCardController {
            return timerCardController
        }

        let controller = TimerCardController()
        timerCardController = controller
        logStatus(name: "TIMER_INIT", note: "created timer card controller")
        return controller
    }

    private func ensureNowPlayingCardController() -> NowPlayingCardController {
        if let nowPlayingCardController {
            return nowPlayingCardController
        }

        let controller = NowPlayingCardController()
        nowPlayingCardController = controller
        logStatus(name: "NOW_PLAYING_INIT", note: "created now-playing card controller")
        return controller
    }

    private func ensureWorkQueueCardController() -> WorkQueueCardController {
        if let workQueueCardController {
            return workQueueCardController
        }

        let controller = WorkQueueCardController()
        workQueueCardController = controller
        logStatus(name: "WORK_QUEUE_INIT", note: "created work queue card controller")
        return controller
    }

    private func ensureCompanionCardController() -> CompanionCardController {
        if let companionCardController {
            return companionCardController
        }

        let controller = CompanionCardController()
        controller.onSubmit = { [weak self] text in
            Task { @MainActor in
                self?.handleCompanionTypedInput(text)
            }
        }
        controller.onTextDidBegin = { [weak self] in
            Task { @MainActor in
                self?.handleCompanionTypingBegan()
            }
        }
        companionCardController = controller
        logStatus(name: "COMPANION_INIT", note: "created companion card controller")
        return controller
    }

    private func openCompanionCard(fromLauncherIndex index: Int, source: String) {
        launcherReturnIndexFromCompanion = index
        guard companionIntentParser != nil else {
            loudFailure(name: "COMPANION_INIT_FAILED", note: "companion parser was unavailable")
            return
        }

        companionReopenLauncherOnClose = true
        companionConversationState.reset()
        companionLastIntentContext = nil
        companionLastTeachablePhrase = nil
        companionLiveTranscriptPreview = nil
        companionConversationState.append(role: .companion, text: "I’m strongest with spells, timer, search, apps, current thread, work queue, media, capture, and undo.")
        let controller = ensureCompanionCardController()
        clearHUDInteractionState()
        let shown = controller.show(model: makeCompanionStatusModel(
            title: "Companion",
            subtitle: "Short commands work best. Type below or hold center to speak.",
            transcript: renderedCompanionTranscript(),
            footer: "Try “work spell I need to design, build, and ship”, “start a five minute timer”, or “search figma docs”. Double-center closes.",
            symbol: "keyboard",
            phase: .success
        ), mode: .full, anchor: .center)
        if shown {
            controller.clearInput()
            logStatus(name: "COMPANION_OPEN", note: "opened via \(source)")
        } else {
            loudFailure(name: "COMPANION_OPEN_FAILED", note: "\(source) was recognized but companion did not become visible")
        }
    }

    private func openCompactCompanion(
        source: String,
        autoListen: Bool = false,
        seededAction: CompanionIntentAction? = nil
    ) {
        guard companionIntentParser != nil else {
            loudFailure(name: "COMPANION_INIT_FAILED", note: "companion parser was unavailable")
            return
        }

        companionReopenLauncherOnClose = false
        companionConversationState.reset()
        if let seededAction {
            companionLastIntentContext = CompanionIntentContext(
                lastResolvedAction: seededAction,
                lastContinueTarget: nil,
                lastEntityTarget: nil
            )
        } else {
            companionLastIntentContext = nil
        }
        companionLastTeachablePhrase = nil
        companionLiveTranscriptPreview = nil
        companionConversationState.append(
            role: .companion,
            text: seededAction == .activateWorkSpell
                ? "Work Spell is live. Speak tasks, say ordered or unordered, or describe dependencies."
                : "Ask for a timer, spell, search, app, queue, media, or undo."
        )
        let controller = ensureCompanionCardController()
        clearHUDInteractionState()
        let shown = controller.show(model: makeCompanionStatusModel(
            title: "Companion",
            subtitle: seededAction == .activateWorkSpell
                ? "Shape the spell by voice or type."
                : "Speak or type from anywhere.",
            transcript: renderedCompanionTranscript(),
            footer: seededAction == .activateWorkSpell
                ? "Say tasks, ordered or unordered, or describe a dependency web. Double-center closes."
                : "Hold center to talk. Double-center closes.",
            symbol: "waveform.badge.mic",
            phase: .success
        ), mode: .compact, anchor: .topTrailing)
        if shown {
            controller.clearInput()
            logStatus(name: "COMPANION_COMPACT_OPEN", note: "opened via \(source)")
            if autoListen {
                beginCompanionListening(pushToTalk: false)
            }
        } else {
            loudFailure(name: "COMPANION_COMPACT_OPEN_FAILED", note: "\(source) was recognized but compact companion did not become visible")
        }
    }

    private func closeCompanionCard(source: String, reopenLauncher: Bool) {
        companionHoldToSpeakTask?.cancel()
        companionHoldToSpeakTask = nil
        companionPushToTalkActive = false
        companionTask?.cancel()
        companionTask = nil
        companionVoiceTask?.cancel()
        companionVoiceTask = nil
        companionVoiceResponder.stop()
        companionSpeechRecognizer.cancel()
        companionConversationState.pendingFollowUp = nil
        companionLastIntentContext = nil
        companionLastTeachablePhrase = nil
        companionLiveTranscriptPreview = nil
        companionReopenLauncherOnClose = false

        guard let companionCardController, companionCardController.isVisible else {
            return
        }

        let closed = companionCardController.close()
        if closed {
            clearHUDInteractionState()
            logStatus(name: "COMPANION_CLOSE", note: "closed via \(source)")
            if reopenLauncher {
                showMainHUD(source: "companion-return", selectedIndex: launcherReturnIndexFromCompanion)
            }
        } else {
            loudFailure(name: "COMPANION_CLOSE_FAILED", note: "\(source) requested close but companion still appears visible")
        }
    }

    private func ensureSupportCardController() -> SupportCardController {
        if let supportCardController {
            return supportCardController
        }

        let controller = SupportCardController()
        supportCardController = controller
        logStatus(name: "SUPPORT_INIT", note: "created support card controller")
        return controller
    }

    private func makeSupportCardModel() -> SupportCardModel {
        let snapshot = SupportStatusSnapshot.current()
        let canRestartInlay = config.runtimeMode == .bundledApp && Bundle.main.bundleURL.pathExtension == "app"
        let actions = [
            SupportAction(
                kind: .openSpeechSettings,
                title: "Open Speech Settings",
                detail: "Speech Recognition: \(snapshot.speechRecognition.title)",
                symbol: "waveform.badge.mic"
            ),
            SupportAction(
                kind: .openMicrophoneSettings,
                title: "Open Microphone Settings",
                detail: "Microphone: \(snapshot.microphone.title)",
                symbol: "mic"
            ),
            SupportAction(
                kind: .openAccessibilitySettings,
                title: "Open Accessibility Settings",
                detail: "Accessibility: \(snapshot.accessibility.title)",
                symbol: "figure.wave"
            ),
            SupportAction(
                kind: .openCompanionHelp,
                title: "Open Companion Help",
                detail: "See Companion’s strongest domains and example phrases.",
                symbol: "questionmark.bubble"
            ),
            SupportAction(
                kind: .restartInlay,
                title: "Restart Inlay",
                detail: canRestartInlay
                    ? "Close the hidden instance and relaunch a fresh copy."
                    : "Available when running the packaged Inlay.app build.",
                symbol: "arrow.clockwise",
                isEnabled: canRestartInlay
            ),
            SupportAction(
                kind: .revealLogs,
                title: "Reveal Logs",
                detail: "Open the Inlay log folder in Finder.",
                symbol: "doc.text.magnifyingglass"
            ),
            SupportAction(
                kind: .revealSupportFiles,
                title: "Reveal Support Files",
                detail: "Open config, queue, Cipher, and Companion files.",
                symbol: "folder"
            ),
            SupportAction(
                kind: .back,
                title: "Back",
                detail: "Return to the launcher.",
                symbol: "chevron.left"
            )
        ]

        return SupportCardModel(
            title: "Support",
            subtitle: "\(snapshot.readinessTitle) · Permissions, recovery, and current limits.",
            metadataText: snapshot.summaryText,
            footer: "Open settings, Companion help, restart Inlay, or reveal support folders. Hold center to go back.",
            actions: actions
        )
    }

    private func openSupportCard(fromLauncherIndex index: Int, source: String) {
        launcherReturnIndexFromSupport = index
        let controller = ensureSupportCardController()
        clearHUDInteractionState()
        let shown = controller.show(model: makeSupportCardModel())
        if shown {
            logStatus(name: "SUPPORT_OPEN", note: "opened via \(source)")
        } else {
            loudFailure(name: "SUPPORT_OPEN_FAILED", note: "\(source) was recognized but Support did not become visible")
        }
    }

    private func closeSupportCard(source: String, reopenLauncher: Bool) {
        guard let supportCardController, supportCardController.isVisible else {
            return
        }

        let closed = supportCardController.close()
        if closed {
            clearHUDInteractionState()
            logStatus(name: "SUPPORT_CLOSE", note: "closed via \(source)")
            if reopenLauncher {
                showMainHUD(source: "support-return", selectedIndex: launcherReturnIndexFromSupport)
            }
        } else {
            loudFailure(name: "SUPPORT_CLOSE_FAILED", note: "\(source) requested close but Support still appears visible")
        }
    }

    private func refreshSupportCard(source: String, selectedIndex: Int? = nil) {
        guard let supportCardController, supportCardController.isVisible else {
            return
        }

        let shown = supportCardController.show(model: makeSupportCardModel(), selectedIndex: selectedIndex)
        if shown {
            logStatus(name: "SUPPORT_REFRESH", note: "refreshed via \(source)")
        } else {
            loudFailure(name: "SUPPORT_REFRESH_FAILED", note: "\(source) requested a support refresh but the card was not visible")
        }
    }

    private func openSupportSettings(urlStrings: [String]) -> Bool {
        for rawURL in urlStrings {
            guard let url = URL(string: rawURL) else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                return true
            }
        }

        return openApplication(named: "System Settings") != nil
    }

    private func requestAccessibilityAccess() -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt"
        let promptOptions = [promptKey: true] as CFDictionary

        if AXIsProcessTrustedWithOptions(promptOptions) {
            return true
        }

        return openSupportSettings(urlStrings: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security"
        ])
    }

    private func revealSupportItem(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    private func showCompanionHelpFromSupport() {
        launcherReturnIndexFromCompanion = launcherReturnIndexFromSupport
        companionReopenLauncherOnClose = true
        companionConversationState.reset()
        companionConversationState.pendingFollowUp = nil
        companionLastIntentContext = nil
        companionLastTeachablePhrase = nil
        companionLiveTranscriptPreview = nil
        presentCompanionHelp(for: .unknown, source: "support")
    }

    private func relaunchCurrentApplication() -> Bool {
        guard config.runtimeMode == .bundledApp else {
            return false
        }

        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "sleep 0.45; open \(shellLiteral(bundleURL.path))"]

        do {
            try process.run()
            return true
        } catch {
            logStatus(name: "SUPPORT_RESTART_FAILED", note: "could not schedule relaunch: \(error.localizedDescription)")
            return false
        }
    }

    private func ensureCurrentThreadCardController() -> CurrentThreadCardController {
        if let currentThreadCardController {
            return currentThreadCardController
        }

        let controller = CurrentThreadCardController()
        currentThreadCardController = controller
        logStatus(name: "CURRENT_THREAD_INIT", note: "created current-thread card controller")
        return controller
    }

    private func makeCurrentThreadModel() -> CurrentThreadCardModel? {
        guard let currentThreadCoordinator else {
            return nil
        }

        nowPlayingCoordinator?.requestImmediateRefresh()
        return currentThreadCoordinator.makeModel(
            frontmostApp: workQueueCaptureAppContext(),
            nowPlayingSnapshot: nowPlayingCoordinator?.currentModel.snapshot
        )
    }

    private func openCurrentThreadCard(fromLauncherIndex index: Int, source: String) {
        launcherReturnIndexFromCurrentThread = index
        guard let model = makeCurrentThreadModel() else {
            loudFailure(name: "CURRENT_THREAD_INIT_FAILED", note: "current-thread coordinator was unavailable")
            return
        }

        let controller = ensureCurrentThreadCardController()
        clearHUDInteractionState()
        let shown = controller.show(model: model)
        if shown {
            recordLastVisibleSurface(.currentThread)
            logStatus(name: "CURRENT_THREAD_OPEN", note: "opened via \(source)")
        } else {
            loudFailure(name: "CURRENT_THREAD_OPEN_FAILED", note: "\(source) was recognized but Current Thread did not become visible")
        }
    }

    private func closeCurrentThreadCard(source: String, reopenLauncher: Bool) {
        guard let currentThreadCardController, currentThreadCardController.isVisible else {
            return
        }

        let closed = currentThreadCardController.close()
        if closed {
            clearHUDInteractionState()
            logStatus(name: "CURRENT_THREAD_CLOSE", note: "closed via \(source)")
            if reopenLauncher {
                showMainHUD(source: "current-thread-return", selectedIndex: launcherReturnIndexFromCurrentThread)
            }
        } else {
            loudFailure(name: "CURRENT_THREAD_CLOSE_FAILED", note: "\(source) requested close but Current Thread still appears visible")
        }
    }

    private func refreshCurrentThreadCard(source: String, selectedIndex: Int? = nil) {
        guard let currentThreadCardController, currentThreadCardController.isVisible else {
            return
        }
        guard let model = makeCurrentThreadModel() else {
            loudFailure(name: "CURRENT_THREAD_REFRESH_FAILED", note: "\(source) requested a refresh but the current-thread model was unavailable")
            return
        }

        currentThreadCardController.update(model: model, selectedIndex: selectedIndex)
        recordLastVisibleSurface(.currentThread)
        logStatus(name: "CURRENT_THREAD_REFRESH", note: "refreshed via \(source)")
    }

    private func handleCurrentThreadSelection(action: CurrentThreadAction, index: Int) {
        switch action.kind {
        case .saveToQueue:
            captureCheckpointToWorkQueue(source: "current-thread")
            refreshCurrentThreadCard(source: "save-to-queue", selectedIndex: index)
        case .resumeApp:
            guard let bundleIdentifier = workQueueCaptureAppContext()?.bundleIdentifier else {
                loudFailure(name: "CURRENT_THREAD_RESUME_FAILED", note: "no resumable app bundle was available for the current thread")
                return
            }
            guard openApplication(bundleIdentifier: bundleIdentifier) else {
                loudFailure(name: "CURRENT_THREAD_RESUME_FAILED", note: "could not resume bundle \(bundleIdentifier)")
                return
            }
            logStatus(name: "CURRENT_THREAD_RESUME", note: "resumed \(bundleIdentifier) from Current Thread")
            displayPortalNotification(title: "Current Thread", body: "Resumed app")
            closeCurrentThreadCard(source: "resume-app", reopenLauncher: false)
        case .refreshName:
            refreshCurrentThreadCard(source: "refresh-name", selectedIndex: index)
        case .back:
            closeCurrentThreadCard(source: "back-row", reopenLauncher: true)
        }
    }

    private func beginCompanionListening(pushToTalk: Bool = false) {
        companionPushToTalkActive = pushToTalk
        companionHoldToSpeakTask?.cancel()
        companionHoldToSpeakTask = nil
        companionTask?.cancel()
        companionVoiceTask?.cancel()
        companionVoiceTask = nil
        companionVoiceResponder.stop()
        companionLiveTranscriptPreview = nil
        companionTaskGeneration += 1
        let generation = companionTaskGeneration
        companionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.companionTaskGeneration == generation {
                    self.companionTask = nil
                }
            }
            do {
                let neededPrompt = self.companionSpeechRecognizer.needsAuthorizationPrompt
                self.logStatus(name: "COMPANION_LISTEN_BEGIN", note: neededPrompt ? "requesting permissions before listening" : "starting live listening")
                if neededPrompt {
                    self.ensureCompanionCardController().update(model: self.makeCompanionStatusModel(
                        title: "Companion",
                        subtitle: "Approve access, then come back.",
                        transcript: self.renderedCompanionTranscript(includePromptWhenEmpty: false),
                        footer: "You can still type instead. Double-center closes.",
                        symbol: "hand.raised",
                        phase: .thinking
                    ))
                }

                self.logStatus(name: "COMPANION_AUTH_REQUEST", note: "requesting speech and microphone authorization")
                try await self.companionSpeechRecognizer.requestAuthorizationIfNeeded()
                guard !Task.isCancelled else { return }
                self.logStatus(name: "COMPANION_AUTH_GRANTED", note: "speech and microphone authorization available")

                if neededPrompt {
                    let model = self.makeCompanionStatusModel(
                        title: "Companion",
                        subtitle: "Access granted.",
                        transcript: self.renderedCompanionTranscript(includePromptWhenEmpty: false),
                        footer: "Return submits typed input. Hold center to speak. Say “help” anytime. Double-center closes.",
                        symbol: "checkmark.circle",
                        phase: .success
                    )
                    let controller = self.ensureCompanionCardController()
                    controller.update(model: model)
                    let _ = controller.show(model: model, mode: controller.currentPresentationMode, anchor: controller.currentAnchorMode)
                    return
                }

                let listeningFooter = pushToTalk
                    ? "Keep holding while you talk, then release center to send. Double-center closes."
                    : "Speak naturally. Your words will appear live here. Hold center works best. Double-center closes."
                let listeningSubtitle = pushToTalk ? "Listening while held…" : "Listening…"
                let listeningModel = self.makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: listeningSubtitle,
                    transcript: self.renderedCompanionTranscript(),
                    footer: listeningFooter,
                    symbol: "waveform.badge.mic",
                    phase: .listening
                )
                let controller = self.ensureCompanionCardController()
                controller.update(model: listeningModel)
                let _ = controller.show(model: listeningModel, mode: controller.currentPresentationMode, anchor: controller.currentAnchorMode)

                let partialUpdate: @Sendable (String) -> Void = { [weak self] partial in
                    Task { @MainActor in
                        guard let self, self.companionCardController?.isVisible == true else {
                            return
                        }

                        let trimmedPartial = partial.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedPartial.isEmpty else {
                            return
                        }

                        self.companionLiveTranscriptPreview = trimmedPartial
                        self.ensureCompanionCardController().update(model: self.makeCompanionStatusModel(
                            title: "Companion",
                            subtitle: pushToTalk ? "Listening while held…" : "Listening…",
                            transcript: self.renderedCompanionTranscript(),
                            footer: pushToTalk
                                ? "Release center to send. Your live transcript should update here."
                                : "Keep talking, or pause when you’re done. Hold center works best.",
                            symbol: "waveform.badge.mic",
                            phase: .listening
                        ))
                    }
                }

                let transcript = try await self.companionSpeechRecognizer.captureAuthorizedUtterance(onPartialResult: partialUpdate)
                guard !Task.isCancelled else { return }
                self.companionPushToTalkActive = false
                self.companionLiveTranscriptPreview = nil
                await self.processCompanionTranscript(transcript, source: "speech")
            } catch {
                guard !Task.isCancelled else { return }
                self.logStatus(name: "COMPANION_LISTEN_FAILED", note: error.localizedDescription)
                self.companionPushToTalkActive = false
                self.companionLiveTranscriptPreview = nil
                self.ensureCompanionCardController().update(model: self.makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "Couldn’t listen right now.",
                    transcript: self.companionConversationState.renderedTranscript.isEmpty ? error.localizedDescription : self.renderedCompanionTranscript(includePromptWhenEmpty: false),
                    footer: "Type below, hold center to try again, or double-center to go back.",
                    symbol: "exclamationmark.bubble",
                    phase: .failure
                ))
            }
        }
    }

    private func handleCompanionTypingBegan() {
        guard companionTask != nil else {
            return
        }

        companionHoldToSpeakTask?.cancel()
        companionHoldToSpeakTask = nil
        companionPushToTalkActive = false
        companionTask?.cancel()
        companionTask = nil
        companionVoiceTask?.cancel()
        companionVoiceTask = nil
        companionVoiceResponder.stop()
        companionSpeechRecognizer.cancel()
        companionLiveTranscriptPreview = nil
        logStatus(name: "COMPANION_TYPING", note: "canceled speech capture because typed input began")
        ensureCompanionCardController().update(model: makeCompanionStatusModel(
            title: "Companion",
            subtitle: "Typing…",
            transcript: renderedCompanionTranscript(),
            footer: "You can keep typing or hold center to speak. Double-center closes.",
            symbol: "keyboard",
            phase: .success
        ))
    }

    private func handleCompanionTypedInput(_ text: String) {
        companionHoldToSpeakTask?.cancel()
        companionHoldToSpeakTask = nil
        companionPushToTalkActive = false
        companionTask?.cancel()
        companionTask = nil
        companionVoiceTask?.cancel()
        companionVoiceTask = nil
        companionVoiceResponder.stop()
        companionSpeechRecognizer.cancel()
        Task { @MainActor [weak self] in
            await self?.processCompanionTranscript(text, source: "typed")
        }
    }

    private func processCompanionTranscript(_ transcript: String, source: String) async {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else {
            return
        }

        companionLiveTranscriptPreview = nil
        logStatus(name: "COMPANION_TRANSCRIPT", note: "\(source): \(cleanedTranscript)")
        companionConversationState.append(role: .user, text: cleanedTranscript)
        if companionConversationState.pendingFollowUp == nil,
           companionTeachDirectiveTarget(in: cleanedTranscript) == nil,
           companionHelpDomain(for: cleanedTranscript) == nil {
            companionLastTeachablePhrase = cleanedTranscript
        }

        if let helpDomain = companionHelpDomain(for: cleanedTranscript) {
            presentCompanionHelp(for: helpDomain, source: source)
            return
        }

        ensureCompanionCardController().update(model: makeCompanionStatusModel(
            title: "Companion",
            subtitle: "Thinking…",
            transcript: renderedCompanionTranscript(includePromptWhenEmpty: false),
            footer: "Thinking through the right domain. Double-center closes.",
            symbol: "brain.head.profile",
            phase: .thinking
        ))

        let snapshot = makeCompanionStateSnapshot()
        let resolution = await resolveCompanionInput(cleanedTranscript, snapshot: snapshot)

        switch resolution {
        case .informational(let response):
            companionConversationState.pendingFollowUp = response.pendingFollowUp
            companionConversationState.append(role: .companion, text: response.text)
            ensureCompanionCardController().update(model: makeCompanionStatusModel(
                title: "Companion",
                subtitle: response.subtitle,
                transcript: renderedCompanionTranscript(includePromptWhenEmpty: false),
                footer: response.footer,
                symbol: response.symbol,
                phase: response.phase,
                domain: response.domain,
                actions: response.actions
            ))
            if source == "speech", response.shouldSpeak {
                speakCompanionReply(response.spokenText ?? response.subtitle)
            }
            return
        case .followUp(let prompt, let pending):
            companionConversationState.pendingFollowUp = pending
            companionConversationState.append(role: .companion, text: prompt)
            logStatus(name: "COMPANION_FOLLOW_UP", note: prompt)
            let fallbackActions: [CompanionQuickAction]
            let followUpDomain: CompanionCommandDomain
            if case .quickActionChoice(let actions) = pending {
                fallbackActions = actions
                followUpDomain = inferCompanionQuickActionDomain(actions)
            } else {
                fallbackActions = []
                followUpDomain = .unknown
            }
            ensureCompanionCardController().update(model: makeCompanionStatusModel(
                title: "Companion",
                subtitle: fallbackActions.isEmpty ? "I need one more piece." : "I’m not fully sure yet.",
                transcript: renderedCompanionTranscript(includePromptWhenEmpty: false),
                footer: fallbackActions.isEmpty
                    ? "Reply below or hold center to answer. Double-center closes."
                    : "Say first, second, or the action name. You can also type. Choosing one does it now and teaches Companion.",
                symbol: fallbackActions.isEmpty ? "ellipsis.bubble" : "brain",
                phase: .success,
                domain: followUpDomain,
                actions: fallbackActions
            ))
            if source == "speech" {
                speakCompanionFollowUp(prompt)
            }
            return
        case .quickAction(let action):
            companionConversationState.pendingFollowUp = nil
            performCompanionQuickAction(action, source: source)
            return
        case .intent(let intent):
            companionConversationState.pendingFollowUp = nil
            companionConversationState.append(role: .companion, text: intent.spokenResponse)
            if source == "speech" {
                speakCompanionReply(intent.spokenResponse)
            }

            logStatus(name: "COMPANION_INTENT", note: "\(intent.action.rawValue) • \(intent.reason)")
            ensureCompanionCardController().update(model: makeCompanionStatusModel(
                title: "Companion",
                subtitle: intent.spokenResponse,
                transcript: renderedCompanionTranscript(includePromptWhenEmpty: false),
                footer: intent.fallbackActions.isEmpty
                    ? "\(intent.domain.hint) Double-center closes."
                    : "If this feels off, use the choices below. Picking one does it now and teaches Companion.",
                symbol: "sparkles",
                phase: .acting,
                domain: intent.domain,
                actions: intent.fallbackActions
            ))

            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(280)) { [weak self] in
                Task { @MainActor in
                    guard let self, self.companionCardController?.isVisible == true else {
                        return
                    }
                    self.performCompanionIntent(intent, transcript: cleanedTranscript, inputSource: source)
                }
            }
        }
    }

    private func performCompanionQuickAction(_ action: CompanionQuickAction, source: String) {
        companionConversationState.pendingFollowUp = nil
        companionConversationState.append(role: .user, text: action.title)

        if case .showHelp(let domain) = action.kind {
            presentCompanionHelp(for: domain, source: source)
            return
        }

        let teachingNote = teachCompanion(from: action)
        if let teachingNote {
            companionConversationState.append(role: .companion, text: teachingNote)
        }

        if case .chooseSuggestion(_, let suggestedTranscript) = action.kind {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let reparsed = await self.companionIntentParser?.parseIntent(
                    transcript: suggestedTranscript,
                    snapshot: self.makeCompanionStateSnapshot(),
                    context: self.companionLastIntentContext
                ) ?? CompanionIntent(
                    action: .none,
                    durationMinutes: nil,
                    spokenResponse: "I still couldn’t route that.",
                    reason: "Suggestion reparse failed."
                )
                guard reparsed.action != .none else {
                    self.ensureCompanionCardController().update(model: self.makeCompanionStatusModel(
                        title: "Companion",
                        subtitle: "That still didn’t map cleanly.",
                        transcript: self.renderedCompanionTranscript(includePromptWhenEmpty: false),
                        footer: "Try another option, type below, or hold center to speak.",
                        symbol: "questionmark.bubble",
                        phase: .failure
                    ))
                    return
                }
                self.companionConversationState.append(role: .companion, text: reparsed.spokenResponse)
                if source == "speech" {
                    self.speakCompanionReply(self.spokenCompanionReply(teachingNote: teachingNote, reply: reparsed.spokenResponse))
                }
                self.ensureCompanionCardController().update(model: self.makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: teachingNote == nil ? reparsed.spokenResponse : "Learned that. \(reparsed.spokenResponse)",
                    transcript: self.renderedCompanionTranscript(includePromptWhenEmpty: false),
                    footer: teachingNote == nil ? "Working…" : "Learned: \(teachingNote ?? "")",
                    symbol: teachingNote == nil ? "sparkles" : "brain",
                    phase: .acting,
                    domain: reparsed.domain,
                    learningNote: self.visibleCompanionLearningNote(teachingNote)
                ))
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(220)) { [weak self] in
                    Task { @MainActor in
                        guard let self, self.companionCardController?.isVisible == true else {
                            return
                        }
                        self.performCompanionIntent(reparsed, transcript: suggestedTranscript, inputSource: source)
                    }
                }
            }
            return
        }

        guard let intent = companionIntent(for: action) else {
            ensureCompanionCardController().update(model: makeCompanionStatusModel(
                title: "Companion",
                subtitle: "That option didn’t map cleanly.",
                transcript: renderedCompanionTranscript(includePromptWhenEmpty: false),
                footer: "Try another option, type below, or hold center to speak.",
                symbol: "questionmark.bubble",
                phase: .failure,
                domain: inferCompanionQuickActionDomain([action])
            ))
            return
        }

        companionConversationState.append(role: .companion, text: intent.spokenResponse)
        if source == "speech" {
            speakCompanionReply(spokenCompanionReply(teachingNote: teachingNote, reply: intent.spokenResponse))
        }
        logStatus(name: "COMPANION_QUICK_ACTION", note: action.title)
        ensureCompanionCardController().update(model: makeCompanionStatusModel(
            title: "Companion",
            subtitle: teachingNote == nil ? intent.spokenResponse : "Learned that. \(intent.spokenResponse)",
            transcript: renderedCompanionTranscript(includePromptWhenEmpty: false),
            footer: teachingNote == nil
                ? "Working…"
                : "Learned: \(teachingNote ?? "")",
            symbol: teachingNote == nil ? (intent.action == .setTimer ? "timer" : "sparkles") : "brain",
            phase: .acting,
            domain: intent.domain,
            learningNote: visibleCompanionLearningNote(teachingNote)
        ))

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(220)) { [weak self] in
            Task { @MainActor in
                guard let self, self.companionCardController?.isVisible == true else {
                    return
                }
                self.performCompanionIntent(intent, transcript: action.title, inputSource: source)
            }
        }
    }

    private func teachCompanion(from action: CompanionQuickAction) -> String? {
        switch action.kind {
        case .chooseSuggestion(let originalTranscript, let suggestedTranscript):
            do {
                try companionConfigStore.saveCorrection(phrase: originalTranscript, replacement: suggestedTranscript)
                return "Got it. I’ll treat “\(originalTranscript)” like “\(suggestedTranscript)” next time."
            } catch {
                loudFailure(name: "COMPANION_TEACH_FAILED", note: error.localizedDescription)
                return nil
            }
        case .openSearch(let query, let teachPhrase):
            guard let teachPhrase, !teachPhrase.isEmpty else {
                return nil
            }
            do {
                try companionConfigStore.saveCorrection(phrase: teachPhrase, replacement: "search \(query)")
                return "Got it. I’ll search for that next time."
            } catch {
                loudFailure(name: "COMPANION_TEACH_FAILED", note: error.localizedDescription)
                return nil
            }
        case .openApp(let appName, let teachPhrase):
            guard let teachPhrase, !teachPhrase.isEmpty else {
                return nil
            }
            do {
                try companionConfigStore.saveAppMeaning(phrase: teachPhrase, appName: appName)
                return "Got it. “\(teachPhrase)” now means \(appName)."
            } catch {
                loudFailure(name: "COMPANION_TEACH_FAILED", note: error.localizedDescription)
                return nil
            }
        case .teachIntent(let phrase, let target):
            do {
                try companionConfigStore.saveIntentMeaning(phrase: phrase, target: target)
                return "Got it. I’ll treat “\(phrase)” like \(target.title) next time."
            } catch {
                loudFailure(name: "COMPANION_TEACH_FAILED", note: error.localizedDescription)
                return nil
            }
        case .showHelp:
            return nil
        case .runIntent(let intent, let teachPhrase):
            guard let teachPhrase, !teachPhrase.isEmpty else {
                return nil
            }
            do {
                switch intent.action {
                case .openWorkQueue:
                    try companionConfigStore.saveIntentMeaning(phrase: teachPhrase, target: .openWorkQueue)
                    return "Got it. I’ll treat “\(teachPhrase)” like Work Queue next time."
                case .captureCheckpoint:
                    try companionConfigStore.saveIntentMeaning(phrase: teachPhrase, target: .captureCheckpoint)
                    return "Got it. I’ll treat “\(teachPhrase)” like Capture next time."
                case .openCurrentThread:
                    try companionConfigStore.saveIntentMeaning(phrase: teachPhrase, target: .openCurrentThread)
                    return "Got it. I’ll treat “\(teachPhrase)” like Current Thread next time."
                case .activateWorkSpell:
                    try companionConfigStore.saveIntentMeaning(phrase: teachPhrase, target: .activateWorkSpell)
                    return "Got it. I’ll treat “\(teachPhrase)” like Work Spell next time."
                case .removeWorkSpellTasks:
                    return nil
                case .deactivateWorkSpell:
                    return nil
                case .openTimer:
                    try companionConfigStore.saveIntentMeaning(phrase: teachPhrase, target: .openTimer)
                    return "Got it. I’ll treat “\(teachPhrase)” like Timer next time."
                case .cancelTimer:
                    try companionConfigStore.saveIntentMeaning(phrase: teachPhrase, target: .cancelTimer)
                    return "Got it. I’ll treat “\(teachPhrase)” like Cancel Timer next time."
                case .openNowPlaying:
                    try companionConfigStore.saveIntentMeaning(phrase: teachPhrase, target: .openNowPlaying)
                    return "Got it. I’ll treat “\(teachPhrase)” like Now Playing next time."
                case .togglePlayback:
                    try companionConfigStore.saveIntentMeaning(phrase: teachPhrase, target: .togglePlayback)
                    return "Got it. I’ll treat “\(teachPhrase)” like playback next time."
                case .undoLastAction:
                    try companionConfigStore.saveIntentMeaning(phrase: teachPhrase, target: .undoLastAction)
                    return "Got it. I’ll treat “\(teachPhrase)” like Undo next time."
                case .continuePortal:
                    try companionConfigStore.saveIntentMeaning(phrase: teachPhrase, target: .continuePortal)
                    return "Got it. I’ll treat “\(teachPhrase)” like Continue next time."
                case .openEntity:
                    if let entityTarget = intent.entityTarget {
                        switch entityTarget.kind {
                        case .app:
                            try companionConfigStore.saveAppMeaning(phrase: teachPhrase, appName: entityTarget.displayName)
                            return "Got it. “\(teachPhrase)” now means \(entityTarget.displayName)."
                        case .browserTab:
                            let query = entityTarget.rawQuery ?? entityTarget.displayName
                            try companionConfigStore.saveCorrection(phrase: teachPhrase, replacement: "search \(query)")
                            return "Got it. I’ll search for that next time."
                        case .currentThread:
                            try companionConfigStore.saveIntentMeaning(phrase: teachPhrase, target: .openCurrentThread)
                            return "Got it. I’ll treat “\(teachPhrase)” like Current Thread next time."
                        case .workQueue:
                            try companionConfigStore.saveIntentMeaning(phrase: teachPhrase, target: .openWorkQueue)
                            return "Got it. I’ll treat “\(teachPhrase)” like Work Queue next time."
                        case .timer:
                            try companionConfigStore.saveIntentMeaning(phrase: teachPhrase, target: .openTimer)
                            return "Got it. I’ll treat “\(teachPhrase)” like Timer next time."
                        case .nowPlaying:
                            try companionConfigStore.saveIntentMeaning(phrase: teachPhrase, target: .openNowPlaying)
                            return "Got it. I’ll treat “\(teachPhrase)” like Now Playing next time."
                        }
                    }
                    return nil
                case .setTimer, .runMacro, .none:
                    return nil
                }
            } catch {
                loudFailure(name: "COMPANION_TEACH_FAILED", note: error.localizedDescription)
                return nil
            }
        case .noOp:
            return nil
        }
    }

    private func companionIntent(for action: CompanionQuickAction) -> CompanionIntent? {
        switch action.kind {
        case .chooseSuggestion:
            return nil
        case .openSearch(let query, _):
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return CompanionIntent(
                action: .openEntity,
                durationMinutes: nil,
                spokenResponse: "Searching for that.",
                reason: "Used a confidence fallback search action.",
                entityTarget: CompanionEntityTarget(kind: .browserTab, displayName: trimmedQuery, rawQuery: trimmedQuery),
                domain: .search,
                confidence: 0.96
            )
        case .openApp(let appName, _):
            let cleanedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
            return CompanionIntent(
                action: .openEntity,
                durationMinutes: nil,
                spokenResponse: "Opening \(cleanedName).",
                reason: "Used a confidence fallback app action.",
                entityTarget: CompanionEntityTarget(kind: .app, displayName: cleanedName, rawQuery: cleanedName),
                domain: .apps,
                confidence: 0.96
            )
        case .teachIntent(_, let target):
            return CompanionIntent(
                action: target.action,
                durationMinutes: nil,
                spokenResponse: target.spokenResponse,
                reason: "Used a taught fallback intent selection.",
                domain: target.action.defaultDomain,
                confidence: 0.96
            )
        case .runIntent(let intent, _):
            return intent
        case .showHelp:
            return nil
        case .noOp:
            return nil
        }
    }

    private func performCompanionIntent(_ intent: CompanionIntent, transcript: String, inputSource: String) {
        rememberCompanionSuccessfulPhrase(transcript, intent: intent)
        switch intent.action {
        case .openWorkQueue:
            companionLastUndoAction = nil
            rememberCompanionIntent(action: .openWorkQueue)
            pulseCompanionAction(title: "Opening", subtitle: "Work Queue", symbol: "list.bullet.clipboard", accent: .systemTeal) { [weak self] in
                guard let self else { return }
                self.closeCompanionCard(source: "intent-open-work-queue", reopenLauncher: false)
                self.openWorkQueueCard(fromLauncherIndex: self.launcherReturnIndexFromCompanion ?? self.launcherIndex(forItemID: LauncherItem.companionItem.id) ?? 0, source: "companion-intent")
            }
        case .captureCheckpoint:
            rememberCompanionIntent(action: .captureCheckpoint)
            if let outcome = captureCheckpointToWorkQueue(source: "companion") {
                companionLastUndoAction = .deleteCapturedQueueItem(itemID: outcome.item.id, title: outcome.item.title)
                pulseCompanionAction(title: "Captured", subtitle: "Saved to Work Queue", symbol: "tray.and.arrow.down.fill", accent: .systemGreen)
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "Captured.",
                    transcript: companionConversationState.renderedTranscript,
                    footer: "Say “undo that” to remove it, or ask “open work queue”.",
                    symbol: "tray.and.arrow.down.fill",
                    phase: .success
                ))
            }
        case .openCurrentThread:
            companionLastUndoAction = nil
            let target = intent.entityTarget ?? CompanionEntityTarget(kind: .currentThread, displayName: "Current Thread")
            rememberCompanionIntent(action: .openCurrentThread, entity: target)
            pulseCompanionAction(title: "Opening", subtitle: "Current Thread", symbol: "sparkles", accent: .systemOrange) { [weak self] in
                guard let self else { return }
                self.closeCompanionCard(source: "intent-open-current-thread", reopenLauncher: false)
                self.openCurrentThreadCard(
                    fromLauncherIndex: self.launcherReturnIndexFromCompanion ?? self.launcherIndex(forItemID: LauncherItem.currentThreadItem.id) ?? 0,
                    source: "companion-intent"
                )
            }
        case .openTimer:
            companionLastUndoAction = nil
            rememberCompanionIntent(action: .openTimer)
            pulseCompanionAction(title: "Opening", subtitle: "Timer", symbol: "timer", accent: .systemBlue) { [weak self] in
                guard let self else { return }
                self.closeCompanionCard(source: "intent-open-timer", reopenLauncher: false)
                self.openTimerCard(fromLauncherIndex: self.launcherReturnIndexFromCompanion ?? self.launcherIndex(forItemID: "timer") ?? 0, source: "companion-intent")
            }
        case .setTimer:
            guard let totalSeconds = intent.durationSeconds ?? intent.durationMinutes.map({ $0 * 60 }), totalSeconds > 0 else {
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "I need a timer length.",
                    transcript: companionConversationState.renderedTranscript,
                    footer: "Try again with a length like “20 minutes”, “1 hour”, or “90 seconds.”",
                    symbol: "timer",
                    phase: .failure
                ))
                return
            }
            guard let timerCoordinator else {
                loudFailure(name: "COMPANION_TIMER_FAILED", note: "timer coordinator unavailable for spoken timer")
                return
            }
            let previousTimerSnapshot = timerCoordinator.companionSnapshot()
            let spokenDuration = CompanionDurationParser.spokenDurationText(totalSeconds: totalSeconds)
            _ = timerCoordinator.startCompanionTimer(totalSeconds: totalSeconds)
            companionLastUndoAction = .restoreTimer(snapshot: previousTimerSnapshot)
            rememberCompanionIntent(action: .setTimer)
            logStatus(name: "COMPANION_ACTION", note: "started a \(spokenDuration) timer")
            displayPortalNotification(title: "Companion", body: "Started a \(spokenDuration) timer")
            pulseCompanionAction(title: "Timer Started", subtitle: spokenDuration, symbol: "checkmark", accent: .systemGreen)
            ensureCompanionCardController().update(model: makeCompanionStatusModel(
                title: "Companion",
                subtitle: "Timer started.",
                transcript: companionConversationState.renderedTranscript,
                footer: "Ask “open timer” to see it, or say “undo that” to restore the last timer state.",
                symbol: "timer",
                phase: .success
            ))
        case .cancelTimer:
            guard let timerCoordinator else {
                loudFailure(name: "COMPANION_TIMER_CANCEL_FAILED", note: "timer coordinator unavailable for timer cancellation")
                return
            }
            let previousTimerSnapshot = timerCoordinator.companionSnapshot()
            guard timerCoordinator.cancelCompanionTimer() else {
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "There isn’t a timer to cancel.",
                    transcript: companionConversationState.renderedTranscript,
                    footer: "Try “set a timer for five minutes” or ask “open timer”.",
                    symbol: "timer",
                    phase: .failure
                ))
                return
            }
            companionLastUndoAction = .restoreTimer(snapshot: previousTimerSnapshot)
            rememberCompanionIntent(action: .cancelTimer)
            logStatus(name: "COMPANION_ACTION", note: "canceled the active timer")
            displayPortalNotification(title: "Companion", body: "Canceled the timer")
            pulseCompanionAction(title: "Timer Cleared", subtitle: "Canceled", symbol: "xmark", accent: .systemOrange)
            ensureCompanionCardController().update(model: makeCompanionStatusModel(
                title: "Companion",
                subtitle: "Timer canceled.",
                transcript: companionConversationState.renderedTranscript,
                footer: "Say “undo that” to restore it, or ask “set a timer for five minutes”.",
                symbol: "timer",
                phase: .success
            ))
        case .openNowPlaying:
            companionLastUndoAction = nil
            rememberCompanionIntent(action: .openNowPlaying)
            pulseCompanionAction(title: "Opening", subtitle: "Now Playing", symbol: "music.note", accent: .systemMint) { [weak self] in
                guard let self else { return }
                self.closeCompanionCard(source: "intent-open-now-playing", reopenLauncher: false)
                self.openNowPlayingCard(fromLauncherIndex: self.launcherReturnIndexFromCompanion ?? self.launcherIndex(forItemID: "now-playing") ?? 0, source: "companion-intent")
            }
        case .activateWorkSpell:
            rememberCompanionIntent(action: .activateWorkSpell)
            let seedTasks = intent.spellTaskSeeds ?? []
            let wasActive = workSpellStore.isActive
            let previousMode = workSpellStore.mode
            let addedTasks = activateWorkSpell(seedTasks: seedTasks, source: "companion", openCard: false, rawText: transcript)
            let currentMode = workSpellStore.mode
            let modeChanged = currentMode != previousMode
            let taskSummary = companionWorkSpellSummary(for: addedTasks)
            if !addedTasks.isEmpty {
                companionLastUndoAction = .removeWorkSpellTasks(taskIDs: addedTasks.map(\.id), summary: taskSummary)
            } else {
                companionLastUndoAction = nil
            }
            pulseCompanionAction(
                title: modeChanged && addedTasks.isEmpty
                    ? "Mode Updated"
                    : (wasActive && !addedTasks.isEmpty ? "Added" : (seedTasks.isEmpty ? "Activated" : "Spell Ready")),
                subtitle: modeChanged && addedTasks.isEmpty
                    ? currentMode.title
                    : (wasActive && !addedTasks.isEmpty ? taskSummary : (seedTasks.isEmpty ? "Work Spell" : taskSummary)),
                symbol: "wand.and.stars",
                accent: .systemGreen
            )

            if workSpellStore.mode == .ordered && addedTasks.count > 1 {
                let prompt = companionWorkSpellDependencyPrompt(for: addedTasks.map(\.title))
                companionConversationState.pendingFollowUp = .workSpellDependencyPrompt(addedTasks.map(\.title))
                companionConversationState.append(role: .companion, text: prompt)
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "Building the task web…",
                    transcript: renderedCompanionTranscript(includePromptWhenEmpty: false),
                    footer: "Answer by voice or type a dependency like “research before design”. Double-center closes.",
                    symbol: "wand.and.stars",
                    phase: .success,
                    domain: .spells
                ))
                if inputSource == "speech" {
                    speakCompanionFollowUp(prompt)
                }
            } else {
                let oracle = workSpellStore.oracleDecision()
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: modeChanged && addedTasks.isEmpty
                        ? "Work Spell is now \(currentMode.title.lowercased())."
                        : (wasActive && !addedTasks.isEmpty
                            ? "Added \(taskSummary)."
                            : (seedTasks.isEmpty ? "Work Spell activated." : oracle.headline)),
                    transcript: renderedCompanionTranscript(includePromptWhenEmpty: false),
                    footer: modeChanged && addedTasks.isEmpty
                        ? "Say “ordered” or “unordered” anytime, or keep talking to add tasks. Double-center closes."
                        : (wasActive && !addedTasks.isEmpty
                            ? "Say “remove design from the todo” or keep talking to shape dependencies. Double-center closes."
                            : "Hold center to open the spell, or keep talking to add more structure. Double-center closes."),
                    symbol: "wand.and.stars",
                    phase: .success,
                    domain: .spells
                ))
            }
        case .removeWorkSpellTasks:
            rememberCompanionIntent(action: .removeWorkSpellTasks)
            let requestedTitles = intent.spellTaskSeeds ?? []
            let removedTasks = removeWorkSpellTasks(matchingTitles: requestedTitles, source: "companion")
            if removedTasks.isEmpty {
                companionLastUndoAction = nil
                let suggestions = workSpellStore.activeTasks().prefix(3).map(\.title).joined(separator: ", ")
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "I couldn’t find that task.",
                    transcript: renderedCompanionTranscript(includePromptWhenEmpty: false),
                    footer: suggestions.isEmpty
                        ? "Your Work Spell is empty right now. Say “work spell” to start one."
                        : "Try the task name more directly. Right now I can see \(suggestions).",
                    symbol: "minus.circle",
                    phase: .failure,
                    domain: .spells
                ))
                return
            }

            let taskSummary = companionWorkSpellSummary(for: removedTasks)
            companionLastUndoAction = .restoreWorkSpellTasks(tasks: removedTasks, summary: taskSummary)
            pulseCompanionAction(title: "Removed", subtitle: taskSummary, symbol: "minus.circle", accent: .systemOrange)
            ensureCompanionCardController().update(model: makeCompanionStatusModel(
                title: "Companion",
                subtitle: "Removed \(taskSummary).",
                transcript: renderedCompanionTranscript(includePromptWhenEmpty: false),
                footer: "Say “undo that” to restore it, or add another task by voice. Double-center closes.",
                symbol: "wand.and.stars",
                phase: .success,
                domain: .spells
            ))
        case .deactivateWorkSpell:
            companionLastUndoAction = nil
            rememberCompanionIntent(action: .deactivateWorkSpell)
            deactivateWorkSpell(source: "companion")
            pulseCompanionAction(title: "Work Spell", subtitle: "Deactivated", symbol: "moon.zzz", accent: .systemOrange)
            ensureCompanionCardController().update(model: makeCompanionStatusModel(
                title: "Companion",
                subtitle: "Work Spell deactivated.",
                transcript: companionConversationState.renderedTranscript,
                footer: "Say “work spell” to bring it back, or keep typing below.",
                symbol: "wand.and.stars",
                phase: .success
            ))
        case .togglePlayback:
            guard let nowPlayingCoordinator else {
                loudFailure(name: "COMPANION_PLAYBACK_FAILED", note: "now-playing coordinator unavailable for spoken playback toggle")
                return
            }
            switch nowPlayingCoordinator.perform(.playPause) {
            case .success(let outcome):
                logStatus(name: "COMPANION_ACTION", note: outcome.logNote)
                if let notificationBody = outcome.notificationBody {
                    displayPortalNotification(title: "Companion", body: notificationBody)
                }
                companionLastUndoAction = .togglePlayback
                rememberCompanionIntent(action: .togglePlayback)
                pulseCompanionAction(title: "Playback", subtitle: "Updated", symbol: "checkmark", accent: .systemGreen)
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "Playback updated.",
                    transcript: companionConversationState.renderedTranscript,
                    footer: "Ask “open now playing”, or say “undo that” to toggle playback back.",
                    symbol: "music.note",
                    phase: .success
                ))
            case .failure(let error):
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "Playback didn’t respond.",
                    transcript: error.localizedDescription,
                    footer: "Hold center to try again, or double-center to go back.",
                    symbol: "music.note",
                    phase: .failure
                ))
            }
        case .continuePortal:
            companionLastUndoAction = nil
            if let continueTarget = intent.continueTarget {
                performCompanionContinueTarget(continueTarget, transcript: transcript)
            } else {
                performCompanionContinue(transcript: transcript)
            }
        case .openEntity:
            companionLastUndoAction = nil
            guard let target = intent.entityTarget else {
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "I need a clearer target.",
                    transcript: companionConversationState.renderedTranscript,
                    footer: "Try something like “open Safari” or “open current thread”.",
                    symbol: "questionmark.bubble",
                    phase: .failure
                ))
                return
            }
            performCompanionEntityTarget(target)
        case .undoLastAction:
            performCompanionUndo()
        case .runMacro:
            companionLastUndoAction = nil
            guard let steps = intent.macroSteps, !steps.isEmpty else {
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "That macro was empty.",
                    transcript: companionConversationState.renderedTranscript,
                    footer: "Teach it again in Cipher Lexicon.",
                    symbol: "wand.and.stars",
                    phase: .failure
                ))
                return
            }
            rememberCompanionIntent(action: .runMacro)
            performCompanionMacro(steps)
        case .none:
            companionLastUndoAction = nil
            ensureCompanionCardController().update(model: makeCompanionStatusModel(
                title: "Companion",
                subtitle: "I didn’t map that yet.",
                transcript: companionConversationState.renderedTranscript,
                footer: "Reply below, hold center to try speech again, or double-center to go back.",
                symbol: "questionmark.bubble",
                phase: .failure
            ))
        }
    }

    private func rememberCompanionSuccessfulPhrase(_ transcript: String, intent: CompanionIntent) {
        guard intent.action != .none else {
            return
        }

        let normalized = transcript
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        guard normalized.count >= 3 else {
            return
        }

        companionConfigStore.rememberPhrase(normalized, for: intent.action)
    }

    private func performCompanionMacro(_ steps: [String]) {
        let summary = describeMacroSteps(steps)
        pulseCompanionAction(title: "Macro", subtitle: summary, symbol: "wand.and.stars", accent: .systemPurple)

        for step in steps {
            performCompanionMacroStep(step)
        }

        ensureCompanionCardController().update(model: makeCompanionStatusModel(
            title: "Companion",
            subtitle: "Macro complete.",
            transcript: companionConversationState.renderedTranscript,
            footer: "Keep typing, hold center to speak, or double-center to go back.",
            symbol: "wand.and.stars",
            phase: .success
        ))
    }

    private func performCompanionMacroStep(_ step: String) {
        switch step {
        case "continue":
            if let target = availableCompanionContinueTargets().first {
                performCompanionContinueTarget(target, transcript: "macro")
            }
        case "capture":
            captureCheckpointToWorkQueue(source: "companion-macro")
        case "current-thread":
            openCurrentThreadCard(
                fromLauncherIndex: launcherReturnIndexFromCompanion ?? launcherIndex(forItemID: LauncherItem.currentThreadItem.id) ?? 0,
                source: "companion-macro"
            )
        case "work-queue":
            openWorkQueueCard(
                fromLauncherIndex: launcherReturnIndexFromCompanion ?? launcherIndex(forItemID: LauncherItem.workQueueItem.id) ?? 0,
                source: "companion-macro"
            )
        case "timer":
            openTimerCard(
                fromLauncherIndex: launcherReturnIndexFromCompanion ?? launcherIndex(forItemID: "timer") ?? 0,
                source: "companion-macro"
            )
        case let timerStep where timerStep.hasPrefix("timer:"):
            let rawMinutes = timerStep.split(separator: ":").dropFirst().first.map(String.init) ?? ""
            if let minutes = Int(rawMinutes),
               let timerCoordinator {
                _ = timerCoordinator.startCompanionTimer(totalSeconds: minutes * 60)
            }
        case "now-playing":
            openNowPlayingCard(
                fromLauncherIndex: launcherReturnIndexFromCompanion ?? launcherIndex(forItemID: "now-playing") ?? 0,
                source: "companion-macro"
            )
        case "playback":
            _ = nowPlayingCoordinator?.perform(.playPause)
        default:
            break
        }
    }

    private func performCompanionEntityTarget(_ target: CompanionEntityTarget) {
        switch target.kind {
        case .currentThread:
            rememberCompanionIntent(action: .openCurrentThread, entity: target)
            pulseCompanionAction(title: "Opening", subtitle: target.displayName, symbol: "sparkles", accent: .systemOrange) { [weak self] in
                guard let self else { return }
                self.closeCompanionCard(source: "intent-open-entity-current-thread", reopenLauncher: false)
                self.openCurrentThreadCard(
                    fromLauncherIndex: self.launcherReturnIndexFromCompanion ?? self.launcherIndex(forItemID: LauncherItem.currentThreadItem.id) ?? 0,
                    source: "companion-entity"
                )
            }
        case .workQueue:
            rememberCompanionIntent(action: .openWorkQueue, entity: target)
            pulseCompanionAction(title: "Opening", subtitle: target.displayName, symbol: "list.bullet.clipboard", accent: .systemTeal) { [weak self] in
                guard let self else { return }
                self.closeCompanionCard(source: "intent-open-entity-work-queue", reopenLauncher: false)
                self.openWorkQueueCard(
                    fromLauncherIndex: self.launcherReturnIndexFromCompanion ?? self.launcherIndex(forItemID: LauncherItem.workQueueItem.id) ?? 0,
                    source: "companion-entity"
                )
            }
        case .timer:
            rememberCompanionIntent(action: .openTimer, entity: target)
            pulseCompanionAction(title: "Opening", subtitle: target.displayName, symbol: "timer", accent: .systemBlue) { [weak self] in
                guard let self else { return }
                self.closeCompanionCard(source: "intent-open-entity-timer", reopenLauncher: false)
                self.openTimerCard(
                    fromLauncherIndex: self.launcherReturnIndexFromCompanion ?? self.launcherIndex(forItemID: "timer") ?? 0,
                    source: "companion-entity"
                )
            }
        case .nowPlaying:
            rememberCompanionIntent(action: .openNowPlaying, entity: target)
            pulseCompanionAction(title: "Opening", subtitle: target.displayName, symbol: "music.note", accent: .systemMint) { [weak self] in
                guard let self else { return }
                self.closeCompanionCard(source: "intent-open-entity-now-playing", reopenLauncher: false)
                self.openNowPlayingCard(
                    fromLauncherIndex: self.launcherReturnIndexFromCompanion ?? self.launcherIndex(forItemID: "now-playing") ?? 0,
                    source: "companion-entity"
                )
            }
        case .app:
            let appName = target.displayName
            if let openedName = openApplication(named: appName) {
                rememberCompanionIntent(action: .openEntity, entity: target)
                pulseCompanionAction(title: "Opening", subtitle: openedName, symbol: "macwindow", accent: .systemIndigo) { [weak self] in
                    self?.closeCompanionCard(source: "intent-open-app", reopenLauncher: false)
                }
                return
            }

            if let browserName = openNewBrowserTab(for: target.rawQuery ?? appName) {
                rememberCompanionIntent(action: .openEntity, entity: target)
                pulseCompanionAction(title: "Searching", subtitle: browserName, symbol: "safari", accent: .systemBlue) { [weak self] in
                    self?.closeCompanionCard(source: "intent-open-app-browser-fallback", reopenLauncher: false)
                }
                return
            }

            ensureCompanionCardController().update(model: makeCompanionStatusModel(
                title: "Companion",
                subtitle: "Couldn’t open \(appName).",
                transcript: companionConversationState.renderedTranscript,
                footer: "Try a different app name, or ask for a tab/search instead.",
                symbol: "app.badge",
                phase: .failure
            ))
        case .browserTab:
            let query = target.rawQuery ?? target.displayName
            if let browserName = openNewBrowserTab(for: query) {
                rememberCompanionIntent(action: .openEntity, entity: target)
                pulseCompanionAction(title: "Search", subtitle: browserName, symbol: "plus.rectangle.on.rectangle", accent: .systemBlue) { [weak self] in
                    self?.closeCompanionCard(source: "intent-open-browser-tab-new", reopenLauncher: false)
                }
                return
            }

            ensureCompanionCardController().update(model: makeCompanionStatusModel(
                title: "Companion",
                subtitle: "Couldn’t open a search tab.",
                transcript: companionConversationState.renderedTranscript,
                footer: "Companion can open a fresh search tab, but it can’t switch existing tabs yet. Try “search figma docs”.",
                symbol: "safari",
                phase: .failure
            ))
        }
    }

    private func performCompanionContinue(transcript: String) {
        if let target = availableCompanionContinueTargets().first {
            performCompanionContinueTarget(target, transcript: transcript)
            return
        }

        companionConversationState.append(role: .companion, text: "Nothing obvious to resume.")
        ensureCompanionCardController().update(model: makeCompanionStatusModel(
            title: "Companion",
            subtitle: "Nothing obvious to resume.",
            transcript: companionConversationState.renderedTranscript,
            footer: "Reply below, hold center to try again, or double-center to go back.",
            symbol: "sparkles",
            phase: .failure
        ))
    }

    private enum CompanionResolution {
        case informational(CompanionInformationalResponse)
        case intent(CompanionIntent)
        case followUp(String, CompanionPendingFollowUp)
        case quickAction(CompanionQuickAction)
    }

    private struct CompanionInformationalResponse {
        let text: String
        let subtitle: String
        let footer: String
        let symbol: String
        let phase: CompanionPhase
        let domain: CompanionCommandDomain
        let actions: [CompanionQuickAction]
        let shouldSpeak: Bool
        let spokenText: String?
        let pendingFollowUp: CompanionPendingFollowUp?

        init(
            text: String,
            subtitle: String,
            footer: String,
            symbol: String,
            phase: CompanionPhase,
            domain: CompanionCommandDomain = .unknown,
            actions: [CompanionQuickAction] = [],
            shouldSpeak: Bool = true,
            spokenText: String? = nil,
            pendingFollowUp: CompanionPendingFollowUp? = nil
        ) {
            self.text = text
            self.subtitle = subtitle
            self.footer = footer
            self.symbol = symbol
            self.phase = phase
            self.domain = domain
            self.actions = actions
            self.shouldSpeak = shouldSpeak
            self.spokenText = spokenText
            self.pendingFollowUp = pendingFollowUp
        }
    }

    private func resolveCompanionInput(_ transcript: String, snapshot: CompanionStateSnapshot) async -> CompanionResolution {
        if let teachTarget = companionTeachDirectiveTarget(in: transcript) {
            guard let teachPhrase = companionLastTeachablePhrase, !teachPhrase.isEmpty else {
                return .informational(CompanionInformationalResponse(
                    text: "Say the phrase you want first, then tell me what it should mean.",
                    subtitle: "I need a phrase to teach.",
                    footer: "Try a command first, then say “teach this as timer” or “teach this as search.”",
                    symbol: "brain.head.profile",
                    phase: .failure,
                    domain: .teaching,
                    shouldSpeak: true,
                    spokenText: "I need a phrase to teach first."
                ))
            }

            if let voiceTeachingAction = await companionVoiceTeachingAction(for: teachPhrase, targetText: teachTarget, snapshot: snapshot) {
                return .quickAction(voiceTeachingAction)
            }

            return .informational(CompanionInformationalResponse(
                text: "I couldn’t turn that into a teaching rule yet.",
                subtitle: "That teaching target wasn’t clear.",
                footer: "Try “teach this as timer”, “teach this as search”, “teach this as work queue”, or an app name like Chrome.",
                symbol: "questionmark.bubble",
                phase: .failure,
                domain: .teaching
            ))
        }

        if let pending = companionConversationState.pendingFollowUp {
            return await resolveCompanionFollowUp(pending, transcript: transcript, snapshot: snapshot)
        }

        if isIncompleteCompanionTimerRequest(transcript) {
            return .followUp("I think I only caught the start of that. Say just the length, like “five minutes”.", .timerDuration)
        }

        let intent = await companionIntentParser?.parseIntent(
            transcript: transcript,
            snapshot: snapshot,
            context: companionLastIntentContext
        )
            ?? CompanionIntent(action: .none, durationMinutes: nil, spokenResponse: "I couldn’t route that.", reason: "Parser unavailable.")

        if intent.action == .continuePortal {
            let targets = availableCompanionContinueTargets()
            if targets.count > 1 {
                return .followUp(companionContinuePrompt(for: targets), .continueChoice(targets))
            }
        }

        if !intent.fallbackActions.isEmpty && (intent.action == .none || intent.confidence < 0.78) {
            return .followUp(
                companionQuickActionPrompt(for: intent.fallbackActions, domain: intent.domain),
                .quickActionChoice(intent.fallbackActions)
            )
        }

        if intent.action == .none, let suggestions = intent.suggestions, !suggestions.isEmpty {
            return .followUp(
                companionQuickActionPrompt(
                    for: suggestions.map {
                        CompanionQuickAction(
                            title: "Use “\($0)”",
                            detail: "Route this request that way and remember it.",
                            symbol: "arrow.turn.down.right",
                            kind: .chooseSuggestion(originalTranscript: transcript, suggestedTranscript: $0),
                            isEnabled: true
                        )
                    },
                    domain: intent.domain
                ),
                .quickActionChoice(
                    suggestions.map {
                        CompanionQuickAction(
                            title: "Use “\($0)”",
                            detail: "Route this request that way and remember it.",
                            symbol: "arrow.turn.down.right",
                            kind: .chooseSuggestion(originalTranscript: transcript, suggestedTranscript: $0),
                            isEnabled: true
                        )
                    }
                )
            )
        }

        return .intent(intent)
    }

    private func resolveCompanionFollowUp(
        _ pending: CompanionPendingFollowUp,
        transcript: String,
        snapshot: CompanionStateSnapshot
    ) async -> CompanionResolution {
        switch pending {
        case .timerDuration:
            guard let totalSeconds = CompanionDurationParser.parseDurationSeconds(from: transcript) else {
                return .followUp("I still need a length. Try “20 minutes”, “1 hour”, or “90 seconds”.", .timerDuration)
            }
            let spokenDuration = CompanionDurationParser.spokenDurationText(totalSeconds: totalSeconds)
            return .intent(CompanionIntent(
                action: .setTimer,
                durationMinutes: CompanionDurationParser.parseMinutes(from: transcript),
                durationSeconds: totalSeconds,
                spokenResponse: "Starting a \(spokenDuration) timer.",
                reason: "Filled in timer duration from follow-up."
            ))
        case .continueChoice(let targets):
            guard let target = resolveCompanionContinueChoice(transcript, options: targets) else {
                return .followUp(companionContinuePrompt(for: targets), .continueChoice(targets))
            }
            return .intent(CompanionIntent(
                action: .continuePortal,
                durationMinutes: nil,
                spokenResponse: "Taking you to \(target.displayName).",
                reason: "Resolved continue follow-up.",
                continueTarget: target
            ))
        case .quickActionChoice(let actions):
            guard let action = resolveCompanionQuickActionChoice(transcript, actions: actions) else {
                return .followUp(companionQuickActionPrompt(for: actions, domain: inferCompanionQuickActionDomain(actions)), .quickActionChoice(actions))
            }
            return .quickAction(action)
        case .workSpellDependencyPrompt(let taskTitles):
            if WorkSpellDependencyParser.isNegativeResponse(transcript) {
                let oracle = workSpellStore.oracleDecision()
                return .informational(CompanionInformationalResponse(
                    text: "Okay. I’ll keep those tasks independent. \(oracle.headline)",
                    subtitle: "Work Spell mapped.",
                    footer: "Hold center to open the spell, or keep talking to refine it.",
                    symbol: "wand.and.stars",
                    phase: .success,
                    domain: .spells
                ))
            }

            let dependencies = WorkSpellDependencyParser.resolvedDependencies(
                from: transcript,
                tasks: workSpellStore.activeTasks()
            )
            guard !dependencies.isEmpty else {
                return .followUp(
                    companionWorkSpellDependencyPrompt(for: taskTitles),
                    .workSpellDependencyPrompt(taskTitles)
                )
            }

            do {
                let added = try workSpellStore.addDependencies(dependencies)
                let oracle = workSpellStore.oracleDecision()
                let dependencySummary = added == 1
                    ? "Locked in 1 prerequisite."
                    : "Locked in \(added) prerequisites."
                return .informational(CompanionInformationalResponse(
                    text: "\(dependencySummary) \(oracle.headline)",
                    subtitle: "Task web updated.",
                    footer: "Hold center to open the spell, or keep talking to reshape it.",
                    symbol: "wand.and.stars",
                    phase: .success,
                    domain: .spells
                ))
            } catch {
                loudFailure(name: "WORK_SPELL_DEPENDENCY_FAILED", note: error.localizedDescription)
                return .informational(CompanionInformationalResponse(
                    text: "I couldn’t save that dependency yet.",
                    subtitle: "Work Spell hit a save issue.",
                    footer: "Try again with a simpler phrasing like “research before design”.",
                    symbol: "wand.and.stars",
                    phase: .failure,
                    domain: .spells
                ))
            }
        }
    }

    private func availableCompanionContinueTargets() -> [CompanionContinueTarget] {
        var targets: [CompanionContinueTarget] = []
        if let timerCoordinator, timerCoordinator.hasLiveCompanionTarget {
            targets.append(.timer)
        }
        if workQueueCoordinator?.topActiveItem() != nil {
            targets.append(.workQueue)
        }
        if let nowPlayingCoordinator, nowPlayingCoordinator.currentModel.snapshot.source != .none {
            targets.append(.nowPlaying)
        }
        return targets
    }

    private func performCompanionContinueTarget(_ target: CompanionContinueTarget, transcript: String) {
        switch target {
        case .timer:
            rememberCompanionIntent(action: .continuePortal, target: .timer)
            pulseCompanionAction(title: "Continuing", subtitle: "Timer", symbol: "timer", accent: .systemBlue) { [weak self] in
                guard let self else { return }
                self.closeCompanionCard(source: "intent-continue-timer", reopenLauncher: false)
                self.openTimerCard(fromLauncherIndex: self.launcherReturnIndexFromCompanion ?? self.launcherIndex(forItemID: "timer") ?? 0, source: "companion-continue")
            }
        case .workQueue:
            if let topItem = workQueueCoordinator?.topActiveItem(),
               topItem.bundleIdentifier != nil,
               case .success(let outcome)? = workQueueCoordinator?.perform(.resumeApp, itemID: topItem.id) {
                logStatus(name: "COMPANION_ACTION", note: outcome.logNote)
                rememberCompanionIntent(action: .continuePortal, target: .workQueue)
                pulseCompanionAction(title: "Continuing", subtitle: "Current Thread", symbol: "arrowshape.turn.up.forward.fill", accent: .systemGreen) { [weak self] in
                    self?.closeCompanionCard(source: "intent-continue-work-queue", reopenLauncher: false)
                }
                return
            }

            rememberCompanionIntent(action: .continuePortal, target: .workQueue)
            pulseCompanionAction(title: "Continuing", subtitle: "Work Queue", symbol: "list.bullet.clipboard", accent: .systemTeal) { [weak self] in
                guard let self else { return }
                self.closeCompanionCard(source: "intent-continue-work-queue-open", reopenLauncher: false)
                let selectedIndex = self.workQueueCoordinator?.topActiveItem().flatMap { self.workQueueCoordinator?.listSelectionIndex(for: $0.id) }
                self.openWorkQueueCard(
                    fromLauncherIndex: self.launcherReturnIndexFromCompanion ?? self.launcherIndex(forItemID: "work-queue") ?? 0,
                    source: "companion-continue",
                    selectedIndex: selectedIndex
                )
            }
        case .nowPlaying:
            rememberCompanionIntent(action: .continuePortal, target: .nowPlaying)
            pulseCompanionAction(title: "Continuing", subtitle: "Now Playing", symbol: "music.note", accent: .systemMint) { [weak self] in
                guard let self else { return }
                self.closeCompanionCard(source: "intent-continue-now-playing", reopenLauncher: false)
                self.openNowPlayingCard(fromLauncherIndex: self.launcherReturnIndexFromCompanion ?? self.launcherIndex(forItemID: "now-playing") ?? 0, source: "companion-continue")
            }
        }
    }

    private func rememberCompanionIntent(
        action: CompanionIntentAction,
        target: CompanionContinueTarget? = nil,
        entity: CompanionEntityTarget? = nil
    ) {
        companionLastIntentContext = CompanionIntentContext(
            lastResolvedAction: action,
            lastContinueTarget: target,
            lastEntityTarget: entity
        )
    }

    private func performCompanionUndo() {
        guard let undoAction = companionLastUndoAction else {
            ensureCompanionCardController().update(model: makeCompanionStatusModel(
                title: "Companion",
                subtitle: "There isn’t anything recent to undo.",
                transcript: companionConversationState.renderedTranscript,
                footer: "I can undo the last timer change, Work Spell change, capture, or playback toggle.",
                symbol: "arrow.uturn.backward.circle",
                phase: .failure,
                domain: .management
            ))
            return
        }

        switch undoAction {
        case .restoreTimer(let snapshot):
            guard let timerCoordinator else {
                loudFailure(name: "COMPANION_UNDO_FAILED", note: "timer coordinator unavailable for undo")
                return
            }
            _ = timerCoordinator.restoreCompanionSnapshot(snapshot)
            companionLastUndoAction = nil
            rememberCompanionIntent(action: .undoLastAction)
            logStatus(name: "COMPANION_ACTION", note: "undid the last timer change")
            displayPortalNotification(title: "Companion", body: "Undid the timer change")
            pulseCompanionAction(title: "Undid", subtitle: "Timer Change", symbol: "arrow.uturn.backward", accent: .systemGreen)
            ensureCompanionCardController().update(model: makeCompanionStatusModel(
                title: "Companion",
                subtitle: "Undid the timer change.",
                transcript: companionConversationState.renderedTranscript,
                footer: "Ask for another timer change, or say “open timer” to inspect it.",
                symbol: "timer",
                phase: .success,
                domain: .management
            ))
        case .deleteCapturedQueueItem(let itemID, let title):
            guard let workQueueCoordinator else {
                loudFailure(name: "COMPANION_UNDO_FAILED", note: "work queue coordinator unavailable for undo")
                return
            }
            switch workQueueCoordinator.perform(.delete, itemID: itemID) {
            case .success(let outcome):
                companionLastUndoAction = nil
                rememberCompanionIntent(action: .undoLastAction)
                logStatus(name: "COMPANION_ACTION", note: "undid capture of \(title)")
                if let notificationBody = outcome.notificationBody {
                    displayPortalNotification(title: "Companion", body: notificationBody)
                }
                pulseCompanionAction(title: "Undid", subtitle: "Capture", symbol: "arrow.uturn.backward", accent: .systemGreen)
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "Removed that capture.",
                    transcript: companionConversationState.renderedTranscript,
                    footer: "You can capture again anytime with “capture this”.",
                    symbol: "tray.and.arrow.down",
                    phase: .success,
                    domain: .management
                ))
            case .failure:
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "I couldn’t undo that capture.",
                    transcript: companionConversationState.renderedTranscript,
                    footer: "That queue item may have already changed or been removed.",
                    symbol: "arrow.uturn.backward.circle",
                    phase: .failure,
                    domain: .management
                ))
            }
        case .removeWorkSpellTasks(let taskIDs, let summary):
            do {
                var removedCount = 0
                for taskID in taskIDs {
                    if try workSpellStore.removeTask(id: taskID) != nil {
                        removedCount += 1
                    }
                }
                companionLastUndoAction = nil
                rememberCompanionIntent(action: .undoLastAction)
                if let workSpellCardController, workSpellCardController.isVisible {
                    workSpellCardController.update(model: makeWorkSpellCardModel())
                }
                logStatus(name: "COMPANION_ACTION", note: "undid Work Spell add for \(summary)")
                displayPortalNotification(title: "Companion", body: removedCount > 0 ? "Removed \(summary)" : "Nothing changed")
                pulseCompanionAction(title: "Undid", subtitle: "Work Spell Add", symbol: "arrow.uturn.backward", accent: .systemGreen)
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: removedCount > 0 ? "Removed \(summary)." : "Nothing changed.",
                    transcript: companionConversationState.renderedTranscript,
                    footer: "Add another task anytime, or say “work spell” to inspect the list.",
                    symbol: "wand.and.stars",
                    phase: .success,
                    domain: .management
                ))
            } catch {
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "I couldn’t undo that Work Spell add.",
                    transcript: error.localizedDescription,
                    footer: "Try opening Work Spell and adjusting it directly.",
                    symbol: "arrow.uturn.backward.circle",
                    phase: .failure,
                    domain: .management
                ))
            }
        case .restoreWorkSpellTasks(let tasks, let summary):
            do {
                let restored = try workSpellStore.restoreTasks(tasks)
                companionLastUndoAction = nil
                rememberCompanionIntent(action: .undoLastAction)
                if let workSpellCardController, workSpellCardController.isVisible {
                    workSpellCardController.update(model: makeWorkSpellCardModel())
                }
                logStatus(name: "COMPANION_ACTION", note: "restored Work Spell tasks for \(summary)")
                displayPortalNotification(title: "Companion", body: restored.isEmpty ? "Nothing changed" : "Restored \(summary)")
                pulseCompanionAction(title: "Undid", subtitle: "Work Spell Remove", symbol: "arrow.uturn.backward", accent: .systemGreen)
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: restored.isEmpty ? "Nothing changed." : "Restored \(summary).",
                    transcript: companionConversationState.renderedTranscript,
                    footer: "You can remove another task, or keep shaping the spell.",
                    symbol: "wand.and.stars",
                    phase: .success,
                    domain: .management
                ))
            } catch {
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "I couldn’t restore that Work Spell task.",
                    transcript: error.localizedDescription,
                    footer: "Try opening Work Spell and adding it back directly.",
                    symbol: "arrow.uturn.backward.circle",
                    phase: .failure,
                    domain: .management
                ))
            }
        case .togglePlayback:
            guard let nowPlayingCoordinator else {
                loudFailure(name: "COMPANION_UNDO_FAILED", note: "now playing coordinator unavailable for playback undo")
                return
            }
            switch nowPlayingCoordinator.perform(.playPause) {
            case .success:
                companionLastUndoAction = nil
                rememberCompanionIntent(action: .undoLastAction)
                logStatus(name: "COMPANION_ACTION", note: "undid the last playback change")
                pulseCompanionAction(title: "Undid", subtitle: "Playback", symbol: "arrow.uturn.backward", accent: .systemGreen)
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "Undid the playback change.",
                    transcript: companionConversationState.renderedTranscript,
                    footer: "Ask “what’s playing” if you want to inspect media state.",
                    symbol: "music.note",
                    phase: .success,
                    domain: .management
                ))
            case .failure(let error):
                ensureCompanionCardController().update(model: makeCompanionStatusModel(
                    title: "Companion",
                    subtitle: "I couldn’t undo playback.",
                    transcript: error.localizedDescription,
                    footer: "Try asking for Now Playing and control it from there.",
                    symbol: "arrow.uturn.backward.circle",
                    phase: .failure,
                    domain: .management
                ))
            }
        }
    }

    private func pulseCompanionAction(
        title: String,
        subtitle: String,
        symbol: String,
        accent: NSColor,
        completion: (() -> Void)? = nil
    ) {
        companionActionPulseTask?.cancel()
        let controller = ensureCompanionActionFeedbackController()
        let shown = controller.pulse(
            title: title,
            subtitle: subtitle,
            symbolName: symbol,
            accessibilityDescription: "\(title) \(subtitle)",
            accentColor: accent
        )
        if shown {
            logStatus(name: "COMPANION_ACTION_PULSE", note: "\(title) • \(subtitle)")
        } else {
            loudFailure(name: "COMPANION_ACTION_PULSE_FAILED", note: "\(title) pulse did not become visible")
        }

        guard let completion else {
            return
        }

        companionActionPulseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }
            completion()
        }
    }

    private func speakCompanionReply(_ text: String) {
        companionVoiceTask?.cancel()
        companionVoiceTask = nil
        companionVoiceResponder.speak(text)
    }

    private func speakCompanionFollowUp(_ text: String) {
        companionVoiceTask?.cancel()
        companionVoiceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.companionVoiceResponder.speakAndWait(text)
            self.companionVoiceTask = nil
        }
    }

    private func isIncompleteCompanionTimerRequest(_ transcript: String) -> Bool {
        let normalized = transcript.lowercased()
        let mentionsTimer = normalized.contains("timer") || normalized.contains("countdown")
        let asksToSet = normalized.contains("set") || normalized.contains("start") || normalized.contains("begin")
        return mentionsTimer && asksToSet && CompanionDurationParser.parseMinutes(from: normalized) == nil
    }

    private func spokenCompanionReply(teachingNote: String?, reply: String) -> String {
        guard teachingNote != nil else {
            return reply
        }
        return "I’ll remember that. \(reply)"
    }

    private func companionHelpDomain(for transcript: String) -> CompanionCommandDomain? {
        let normalized = normalizeCompanionChoiceTranscript(transcript)
        guard !normalized.isEmpty else {
            return nil
        }

        let exactHelpPhrases = [
            "help", "companion help", "what can you do", "what do you do", "how do i use companion",
            "how do i use this", "what can companion do", "show commands", "show help"
        ]
        let startsWithHelp = normalized.hasPrefix("help ") || normalized.hasPrefix("show help ")
        let isHelpRequest = startsWithHelp || exactHelpPhrases.contains(where: { normalized == $0 })
        guard isHelpRequest else {
            return nil
        }

        let inferredDomain = CompanionCommandDomain.infer(from: normalized)
        return inferredDomain == .teaching ? .unknown : inferredDomain
    }

    private func presentCompanionHelp(for domain: CompanionCommandDomain, source: String) {
        let examples = domain.helpExamples.map { "“\($0)”" }.joined(separator: ", ")
        let body: String
        let subtitle: String
        let footer: String
        let actions = companionHelpQuickActions(for: domain)

        if domain == .unknown {
            body = "I’m best with short commands across a few domains: spells, timer, search, apps, work queue, current thread, media, capture, and continue. If I’m unsure, say first, second, or the action name. You can also say “teach this as timer” or “teach this as search.”"
            subtitle = "Here’s where I’m strongest."
            footer = actions.isEmpty
                ? "Try one of these: \(examples). Hold center to speak. Double-center closes."
                : "Use the rows below for a domain tour, or try one of these: \(examples). Double-center closes."
        } else {
            body = "\(domain.helpSummary) Good examples are \(examples). If I’m unsure, say first, second, or “teach this as \(domain.title.lowercased())”."
            subtitle = "\(domain.title) Help"
            footer = actions.isEmpty
                ? "Try one of those phrases by voice or type it below. Double-center closes."
                : "Try one of those phrases, or use the rows below to keep exploring. Double-center closes."
        }

        companionConversationState.pendingFollowUp = nil
        companionConversationState.append(role: .companion, text: body)
        let model = makeCompanionStatusModel(
            title: "Companion",
            subtitle: subtitle,
            transcript: renderedCompanionTranscript(includePromptWhenEmpty: false),
            footer: footer,
            symbol: domain.symbol,
            phase: .success,
            domain: domain,
            actions: actions
        )
        let controller = ensureCompanionCardController()
        let shown = controller.show(model: model, mode: .full, anchor: .center)
        if shown {
            controller.clearInput()
        } else {
            controller.update(model: model)
        }

        if source == "speech" {
            speakCompanionReply(domain == .unknown ? "I’m strongest with spells, timer, search, apps, queue, thread, media, capture, and continue." : body)
        }
    }

    private func companionTeachDirectiveTarget(in transcript: String) -> String? {
        var normalized = normalizeCompanionChoiceTranscript(transcript)
        guard !normalized.isEmpty else {
            return nil
        }

        let prefixes = [
            "teach this as ",
            "teach that as ",
            "teach it as ",
            "remember this as ",
            "remember that as ",
            "remember it as ",
            "make this mean ",
            "make that mean ",
            "make it mean ",
            "treat this as ",
            "treat that as ",
            "treat it as "
        ]

        for prefix in prefixes where normalized.hasPrefix(prefix) {
            normalized.removeFirst(prefix.count)
            return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func companionVoiceTeachingAction(
        for teachPhrase: String,
        targetText: String,
        snapshot: CompanionStateSnapshot
    ) async -> CompanionQuickAction? {
        let normalizedTarget = normalizeCompanionChoiceTranscript(targetText)
        guard !normalizedTarget.isEmpty else {
            return nil
        }

        if ["search", "search it", "look it up", "google it", "browser", "web"].contains(where: { normalizedTarget == $0 || normalizedTarget.contains($0) }) {
            return CompanionQuickAction(
                title: "Search “\(teachPhrase)”",
                detail: "Open a fresh browser search and remember that meaning.",
                symbol: "magnifyingglass",
                kind: .openSearch(query: teachPhrase, teachPhrase: teachPhrase),
                isEnabled: true
            )
        }

        if let target = CompanionIntentMeaningTarget.parse(from: normalizedTarget) {
            return CompanionQuickAction(
                title: "Teach \(target.title)",
                detail: "Treat this phrase like \(target.title) next time.",
                symbol: target.action.defaultDomain.symbol,
                kind: .teachIntent(phrase: teachPhrase, target: target),
                isEnabled: true
            )
        }

        if let appName = canonicalCompanionAppName(for: normalizedTarget) {
            return CompanionQuickAction(
                title: "Open \(appName)",
                detail: "Open the app and remember that meaning.",
                symbol: "macwindow",
                kind: .openApp(appName: appName, teachPhrase: teachPhrase),
                isEnabled: true
            )
        }

        if let reparsed = await companionIntentParser?.parseIntent(
            transcript: normalizedTarget,
            snapshot: snapshot,
            context: companionLastIntentContext
        ), reparsed.action != .none {
            return CompanionQuickAction(
                title: reparsed.spokenResponse,
                detail: "Use that interpretation next time.",
                symbol: reparsed.domain.symbol,
                kind: .runIntent(intent: reparsed, teachPhrase: teachPhrase),
                isEnabled: true
            )
        }

        return nil
    }

    private func canonicalCompanionAppName(for phrase: String) -> String? {
        let normalized = normalizeCompanionChoiceTranscript(phrase)
        guard !normalized.isEmpty else {
            return nil
        }

        let aliases: [String: String] = [
            "chrome": "Google Chrome",
            "google chrome": "Google Chrome",
            "brave": "Brave Browser",
            "brave browser": "Brave Browser",
            "safari": "Safari",
            "arc": "Arc",
            "spotify": "Spotify",
            "messages": "Messages",
            "message": "Messages",
            "finder": "Finder",
            "figma": "Figma",
            "xcode": "Xcode",
            "cursor": "Cursor",
            "terminal": "Terminal",
            "notes": "Notes",
            "music": "Music",
            "canva": "Canva"
        ]

        if let aliased = aliases[normalized] {
            return aliased
        }

        let candidate = normalized
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")

        if let fullPath = NSWorkspace.shared.fullPath(forApplication: candidate) {
            return URL(fileURLWithPath: fullPath).deletingPathExtension().lastPathComponent
        }

        return nil
    }

    private func companionContinuePrompt(for targets: [CompanionContinueTarget]) -> String {
        let names = targets.map(\.displayName)
        switch names.count {
        case 0:
            return "Nothing obvious to resume."
        case 1:
            return "Do you mean \(names[0])?"
        case 2:
            return "I can take you to \(names[0]) or \(names[1]). Which one?"
        default:
            return "I can take you to \(names.dropLast().joined(separator: ", ")), or \(names.last ?? "something else"). Which one?"
        }
    }

    private func companionSuggestionPrompt(for suggestions: [String]) -> String {
        let cleaned = suggestions.prefix(2)
        if cleaned.count == 2 {
            return "Did you mean “\(cleaned[0])” or “\(cleaned[1])”?"
        }
        if let first = cleaned.first {
            return "Did you mean “\(first)”?"
        }
        return "Try “continue”, “open work queue”, or “set a timer for 20 minutes.”"
    }

    private func companionQuickActionPrompt(for actions: [CompanionQuickAction], domain: CompanionCommandDomain) -> String {
        let cleaned = actions.prefix(3).map(\.title)
        switch cleaned.count {
        case 0:
            return domain.hint
        case 1:
            return "\(domain.title): do you want \(cleaned[0])? I can do it now and remember it."
        case 2:
            return "\(domain.title): do you want \(cleaned[0]) or \(cleaned[1])? Pick the closest one and I’ll remember it."
        default:
            return "\(domain.title): choose \(cleaned[0]), \(cleaned[1]), or \(cleaned[2]). Say first, second, third, or the action name, and I’ll remember it."
        }
    }

    private func companionHelpQuickActions(for domain: CompanionCommandDomain) -> [CompanionQuickAction] {
        switch domain {
        case .unknown:
            return [
                CompanionQuickAction(
                    title: "Timer Help",
                    detail: "Examples for starting, opening, and canceling timers.",
                    symbol: CompanionCommandDomain.timer.symbol,
                    kind: .showHelp(domain: .timer),
                    isEnabled: true
                ),
                CompanionQuickAction(
                    title: "Search Help",
                    detail: "Examples for fresh browser searches and web-style requests.",
                    symbol: CompanionCommandDomain.search.symbol,
                    kind: .showHelp(domain: .search),
                    isEnabled: true
                ),
                CompanionQuickAction(
                    title: "App Help",
                    detail: "Examples for opening apps directly by name.",
                    symbol: CompanionCommandDomain.apps.symbol,
                    kind: .showHelp(domain: .apps),
                    isEnabled: true
                ),
                CompanionQuickAction(
                    title: "Work Queue Help",
                    detail: "Examples for queue, capture, and staged work commands.",
                    symbol: CompanionCommandDomain.workQueue.symbol,
                    kind: .showHelp(domain: .workQueue),
                    isEnabled: true
                ),
                CompanionQuickAction(
                    title: "Current Thread Help",
                    detail: "Examples for naming and reopening what you are doing now.",
                    symbol: CompanionCommandDomain.currentThread.symbol,
                    kind: .showHelp(domain: .currentThread),
                    isEnabled: true
                ),
                CompanionQuickAction(
                    title: "Media Help",
                    detail: "Examples for now playing and playback control.",
                    symbol: CompanionCommandDomain.media.symbol,
                    kind: .showHelp(domain: .media),
                    isEnabled: true
                ),
                CompanionQuickAction(
                    title: "Teach This Help",
                    detail: "Examples for teaching phrases and correcting Companion.",
                    symbol: CompanionCommandDomain.teaching.symbol,
                    kind: .showHelp(domain: .teaching),
                    isEnabled: true
                )
            ]
        case .teaching:
            return [
                CompanionQuickAction(
                    title: "Back to Companion Help",
                    detail: "See all Companion domains again.",
                    symbol: "questionmark.bubble",
                    kind: .showHelp(domain: .unknown),
                    isEnabled: true
                )
            ]
        default:
            return [
                CompanionQuickAction(
                    title: "Back to Companion Help",
                    detail: "See all Companion domains again.",
                    symbol: "questionmark.bubble",
                    kind: .showHelp(domain: .unknown),
                    isEnabled: true
                ),
                CompanionQuickAction(
                    title: "Teach This Help",
                    detail: "See how to correct or personalize Companion phrases.",
                    symbol: CompanionCommandDomain.teaching.symbol,
                    kind: .showHelp(domain: .teaching),
                    isEnabled: true
                )
            ]
        }
    }

    private func resolveCompanionContinueChoice(_ transcript: String, options: [CompanionContinueTarget]) -> CompanionContinueTarget? {
        let normalized = transcript.lowercased()

        if let indexed = resolveCompanionOrdinalChoice(normalized, count: options.count) {
            return options[indexed]
        }

        return options.first { target in
            switch target {
            case .timer:
                return normalized.contains("timer")
            case .workQueue:
                return normalized.contains("queue") || normalized.contains("work")
            case .nowPlaying:
                return normalized.contains("music") || normalized.contains("song") || normalized.contains("playing")
            }
        }
    }

    private func resolveCompanionSuggestionChoice(_ transcript: String, suggestions: [String]) -> String? {
        let normalized = transcript.lowercased()

        if let indexed = resolveCompanionOrdinalChoice(normalized, count: suggestions.count) {
            return suggestions[indexed]
        }

        return suggestions.first { suggestion in
            normalized == suggestion.lowercased() || normalized.contains(suggestion.lowercased())
        }
    }

    private func resolveCompanionQuickActionChoice(_ transcript: String, actions: [CompanionQuickAction]) -> CompanionQuickAction? {
        let normalized = normalizeCompanionChoiceTranscript(transcript)

        if let indexed = resolveCompanionOrdinalChoice(normalized, count: actions.count) {
            return actions[indexed]
        }

        if let semanticMatch = actions.first(where: { companionQuickActionMatchesVoiceChoice(normalized, action: $0) }) {
            return semanticMatch
        }

        return actions.first { action in
            let loweredTitle = normalizeCompanionChoiceTranscript(action.title)
            let loweredDetail = normalizeCompanionChoiceTranscript(action.detail)
            return normalized == loweredTitle
                || normalized.contains(loweredTitle)
                || normalized.contains(loweredDetail)
        }
    }

    private func inferCompanionQuickActionDomain(_ actions: [CompanionQuickAction]) -> CompanionCommandDomain {
        for action in actions {
            switch action.kind {
            case .openSearch:
                return .search
            case .openApp:
                return .apps
            case .teachIntent(_, let target):
                return target.action.defaultDomain
            case .showHelp(let domain):
                return domain == .unknown ? .teaching : domain
            case .runIntent(let intent, _):
                return intent.domain
            case .chooseSuggestion:
                continue
            case .noOp:
                continue
            }
        }
        return .unknown
    }

    private func resolveCompanionOrdinalChoice(_ transcript: String, count: Int) -> Int? {
        let mappings: [(Int, [String])] = [
            (0, ["1", "one", "first"]),
            (1, ["2", "two", "second"]),
            (2, ["3", "three", "third"])
        ]

        for (index, tokens) in mappings where index < count {
            if tokens.contains(where: { transcript == $0 || transcript.contains(" \($0)") || transcript.contains("\($0) ") }) {
                return index
            }
        }

        return nil
    }

    private func normalizeCompanionChoiceTranscript(_ transcript: String) -> String {
        var normalized = transcript
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let prefixes = [
            "choose ",
            "pick ",
            "go with ",
            "use ",
            "open ",
            "launch ",
            "search for ",
            "look up ",
            "teach this as ",
            "teach that as ",
            "teach it as ",
            "remember this as ",
            "remember that as ",
            "remember it as "
        ]

        for prefix in prefixes where normalized.hasPrefix(prefix) {
            normalized.removeFirst(prefix.count)
            break
        }

        let leadingArticles = ["the ", "a ", "an "]
        for article in leadingArticles where normalized.hasPrefix(article) {
            normalized.removeFirst(article.count)
            break
        }

        let suffixes = [" next time", " instead", " for me", " please"]
        for suffix in suffixes where normalized.hasSuffix(suffix) {
            normalized.removeLast(suffix.count)
            break
        }

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func companionQuickActionMatchesVoiceChoice(_ transcript: String, action: CompanionQuickAction) -> Bool {
        let normalized = normalizeCompanionChoiceTranscript(transcript)
        guard !normalized.isEmpty else {
            return false
        }

        return companionQuickActionVoicePhrases(action).contains { phrase in
            let normalizedPhrase = normalizeCompanionChoiceTranscript(phrase)
            guard !normalizedPhrase.isEmpty else {
                return false
            }
            return normalized == normalizedPhrase
                || normalized.contains(normalizedPhrase)
                || normalizedPhrase.contains(normalized)
        }
    }

    private func companionQuickActionVoicePhrases(_ action: CompanionQuickAction) -> [String] {
        switch action.kind {
        case .chooseSuggestion(_, let suggestedTranscript):
            return [
                suggestedTranscript,
                "use \(suggestedTranscript)",
                "that one"
            ]
        case .openSearch(let query, _):
            return [
                "search",
                "search it",
                "look it up",
                "google it",
                "browser",
                "web",
                query
            ]
        case .openApp(let appName, _):
            return [
                appName,
                "app",
                "open \(appName)",
                "launch \(appName)"
            ]
        case .teachIntent(_, let target):
            return target.acceptedInputExamples + [
                target.title,
                "teach \(target.title)",
                "remember \(target.title)"
            ]
        case .runIntent(let intent, _):
            return companionIntentVoicePhrases(intent)
        case .showHelp(let domain):
            if domain == .unknown {
                return ["help", "companion help", "show help"]
            }
            return ["\(domain.title.lowercased()) help", "help with \(domain.title.lowercased())"]
        case .noOp:
            return [action.title]
        }
    }

    private func companionIntentVoicePhrases(_ intent: CompanionIntent) -> [String] {
        switch intent.action {
        case .openWorkQueue:
            return ["work queue", "queue", "open work queue"]
        case .captureCheckpoint:
            return ["capture", "capture this", "save this", "remember this"]
        case .openCurrentThread:
            return ["current thread", "thread", "what i am doing"]
        case .activateWorkSpell:
            return ["work spell", "start work spell", "open work spell", "todo spell"]
        case .removeWorkSpellTasks:
            return ["remove from the todo", "delete from my list", "remove task", "take this off the list"]
        case .deactivateWorkSpell:
            return ["stop work spell", "end work spell", "deactivate work spell"]
        case .openTimer:
            return ["timer", "open timer", "show timer"]
        case .setTimer:
            if let durationSeconds = intent.durationSeconds, durationSeconds > 0 {
                return ["timer", "start timer", CompanionDurationParser.spokenDurationText(totalSeconds: durationSeconds)]
            }
            return ["timer", "start timer"]
        case .cancelTimer:
            return ["cancel timer", "stop timer", "clear timer", "cancel all timers"]
        case .openNowPlaying:
            return ["now playing", "music", "show music", "what s playing"]
        case .togglePlayback:
            return ["playback", "pause", "play", "pause music", "play music"]
        case .continuePortal:
            return ["continue", "resume", "pick up"]
        case .undoLastAction:
            return ["undo that", "undo", "that wasn't right", "take that back"]
        case .openEntity:
            guard let entityTarget = intent.entityTarget else {
                return ["open it"]
            }
            switch entityTarget.kind {
            case .app:
                return [entityTarget.displayName, "app", "open \(entityTarget.displayName)"]
            case .browserTab:
                return ["search", "look it up", entityTarget.rawQuery ?? entityTarget.displayName]
            case .currentThread:
                return ["current thread", "thread"]
            case .workQueue:
                return ["work queue", "queue"]
            case .timer:
                return ["timer"]
            case .nowPlaying:
                return ["now playing", "music"]
            }
        case .runMacro:
            return ["macro"]
        case .none:
            return []
        }
    }

    private func makeCompanionStatusModel(
        title: String,
        subtitle: String,
        transcript: String,
        footer: String,
        symbol: String,
        phase: CompanionPhase,
        domain: CompanionCommandDomain = .unknown,
        learningNote: String? = nil,
        actions: [CompanionQuickAction] = []
    ) -> CompanionCardModel {
        CompanionCardModel(
            title: title,
            subtitle: subtitle,
            transcript: transcript,
            footer: footer,
            symbol: symbol,
            phase: phase,
            domain: domain,
            learningNote: learningNote,
            quickActions: actions
        )
    }

    private func visibleCompanionLearningNote(_ note: String?) -> String? {
        guard let note else {
            return nil
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let withoutLead = trimmed.replacingOccurrences(of: "Got it. ", with: "")
        return "Learned: \(withoutLead)"
    }

    private func renderedCompanionTranscript(includePromptWhenEmpty: Bool = true) -> String {
        let baseTranscript = companionConversationState.renderedTranscript
        let trimmedPreview = companionLiveTranscriptPreview?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedPreview, !trimmedPreview.isEmpty {
            let prefix = baseTranscript.isEmpty ? "" : baseTranscript + "\n\n"
            return prefix + "You: " + trimmedPreview
        }

        if includePromptWhenEmpty && baseTranscript.isEmpty {
            return "Companion: I’m strongest with spells, timer, search, apps, current thread, work queue, media, capture, and undo."
        }

        return baseTranscript
    }

    private func makeCompanionStateSnapshot() -> CompanionStateSnapshot {
        let timerStage = timerCoordinator?.companionStageName ?? "setting"
        let queueCount = workQueueCoordinator?.activeItemCount ?? 0
        let topQueueTitle = workQueueCoordinator?.topActiveItem()?.title
        let nowPlayingSnapshot = nowPlayingCoordinator?.currentModel.snapshot ?? .empty

        return CompanionStateSnapshot(
            timerStage: timerStage,
            timerVisible: timerCardController?.isVisible == true,
            queueCount: queueCount,
            topQueueTitle: topQueueTitle,
            nowPlayingTitle: nowPlayingSnapshot.title,
            nowPlayingSource: nowPlayingSnapshot.source.displayName,
            nowPlayingState: nowPlayingSnapshot.playerState.rawValue,
            hasUndoableAction: companionLastUndoAction != nil
        )
    }

    private func companionWorkSpellDependencyPrompt(for taskTitles: [String]) -> String {
        let quoted = taskTitles.prefix(4).map { "\"\($0)\"" }.joined(separator: ", ")
        if taskTitles.count < 2 {
            return "Anything else you want tied into that spell?"
        }
        return "Any of those depend on another first? Say something like \"research before design\" or say \"no\". I heard \(quoted)."
    }

    private func companionWorkSpellSummary(for tasks: [WorkSpellTask]) -> String {
        guard !tasks.isEmpty else {
            return "Work Spell"
        }
        if tasks.count == 1 {
            return tasks[0].title
        }
        return "\(tasks.count) tasks"
    }

    private func applyRequestedWorkSpellMode(from transcript: String, source: String) -> WorkSpellMode {
        let requestedMode = WorkSpellTaskParser.requestedMode(from: transcript) ?? workSpellStore.mode
        if requestedMode != workSpellStore.mode {
            do {
                try workSpellStore.setMode(requestedMode)
                logStatus(name: "WORK_SPELL_MODE", note: "switched to \(requestedMode.rawValue) via \(source)")
                displayPortalNotification(title: "Work Spell", body: "\(requestedMode.title) mode")
            } catch {
                loudFailure(name: "WORK_SPELL_MODE_FAILED", note: error.localizedDescription)
            }
        }
        return workSpellStore.mode
    }

    @discardableResult
    private func addStructuredWorkSpellPlan(_ plan: WorkSpellStructuredPlan, source: String) -> [WorkSpellTask] {
        let orderedTitles = [plan.rootTitle] + plan.prerequisiteTitles + plan.successorTitles

        do {
            let addedTasks = try workSpellStore.addTasks(titles: orderedTitles)
            guard !addedTasks.isEmpty else {
                return []
            }

            let taskByTitle = Dictionary(uniqueKeysWithValues: addedTasks.map { (WorkSpellTaskParser.cleanTaskTitle($0.title).lowercased(), $0) })
            guard let rootTask = taskByTitle[WorkSpellTaskParser.cleanTaskTitle(plan.rootTitle).lowercased()] else {
                return addedTasks
            }

            let prerequisiteTasks = plan.prerequisiteTitles.compactMap { taskByTitle[WorkSpellTaskParser.cleanTaskTitle($0).lowercased()] }
            let successorTasks = plan.successorTitles.compactMap { taskByTitle[WorkSpellTaskParser.cleanTaskTitle($0).lowercased()] }
            let shouldLock = workSpellStore.mode == .ordered

            let assignments =
                [WorkSpellRelationshipAssignment(
                    taskID: rootTask.id,
                    parentTaskID: nil,
                    branchRole: nil,
                    prerequisiteTaskIDs: shouldLock ? prerequisiteTasks.map(\.id) : []
                )]
                + prerequisiteTasks.map {
                    WorkSpellRelationshipAssignment(
                        taskID: $0.id,
                        parentTaskID: rootTask.id,
                        branchRole: .prerequisite,
                        prerequisiteTaskIDs: []
                    )
                }
                + successorTasks.map {
                    WorkSpellRelationshipAssignment(
                        taskID: $0.id,
                        parentTaskID: rootTask.id,
                        branchRole: .successor,
                        prerequisiteTaskIDs: shouldLock ? [rootTask.id] : []
                    )
                }

            _ = try workSpellStore.applyRelationships(assignments)

            if let workSpellCardController, workSpellCardController.isVisible {
                let selectedIndex = addedTasks.last.flatMap { addedTask in
                    makeWorkSpellCardModel().rows.firstIndex { row in
                        if case .task(let taskID) = row.kind {
                            return taskID == addedTask.id
                        }
                        return false
                    }
                }
                workSpellCardController.update(model: makeWorkSpellCardModel(), selectedIndex: selectedIndex)
            }

            let summary = addedTasks.count == 1 ? addedTasks[0].title : "\(addedTasks.count) tasks"
            logStatus(name: "WORK_SPELL_ADD_TASK", note: "added structured plan \(summary) via \(source)")
            displayPortalNotification(title: "Work Spell", body: "Added \(summary)")
            return addedTasks
        } catch {
            loudFailure(name: "WORK_SPELL_RELATIONSHIP_FAILED", note: error.localizedDescription)
            return []
        }
    }

    private func scheduleCompanionHoldToSpeak() {
        companionHoldToSpeakTask?.cancel()
        companionHoldToSpeakTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard let self,
                  self.companionCardController?.isVisible == true,
                  self.companionCenterPressStartedAt != nil,
                  !Task.isCancelled else {
                return
            }
            guard self.companionTask == nil else {
                return
            }
            self.companionPushToTalkActive = true
            self.suppressGesture(.centerHold, for: 1.4)
            self.logStatus(name: "COMPANION_PUSH_TO_TALK_BEGIN", note: "starting hold-to-speak capture")
            self.ensureCompanionCardController().clearInput()
            self.beginCompanionListening(pushToTalk: true)
        }
    }

    private func cancelCompanionHoldToSpeak() {
        companionHoldToSpeakTask?.cancel()
        companionHoldToSpeakTask = nil
    }

    private func finishCompanionPushToTalk() {
        guard companionPushToTalkActive || companionSpeechRecognizer.isCapturing else {
            return
        }
        companionPushToTalkActive = false
        suppressGesture(.centerHold, for: 1.0)
        suppressGesture(.centerSingle, for: 0.8)
        logStatus(name: "COMPANION_PUSH_TO_TALK_END", note: "finishing the current spoken utterance on release")
        ensureCompanionCardController().update(model: makeCompanionStatusModel(
            title: "Companion",
            subtitle: "Processing what I heard…",
            transcript: renderedCompanionTranscript(includePromptWhenEmpty: false),
            footer: "Thinking through the best match. Double-center closes.",
            symbol: "brain.head.profile",
            phase: .thinking
        ))
        companionSpeechRecognizer.finishCurrentUtterance()
    }

    private func selectCompanionQuickAction(by delta: Int) -> Bool {
        guard let selection = companionCardController?.moveQuickActionSelection(by: delta) else {
            return false
        }
        logStatus(name: "COMPANION_FALLBACK_NAV", note: "moved to \(selection.title)")
        return true
    }

    private func confirmCompanionQuickAction(source: String) -> Bool {
        guard let selection = companionCardController?.confirmQuickActionSelection() else {
            return false
        }
        logStatus(name: "COMPANION_FALLBACK_CONFIRM", note: "confirmed \(selection.title) via \(source)")
        performCompanionQuickAction(selection, source: "typed")
        return true
    }

    private func handleCompanionRawEvent(_ event: HIDRawEvent) -> Bool {
        guard event.usagePage == 12 else {
            return false
        }
        guard let companionCardController, companionCardController.isVisible else {
            return false
        }

        switch event.usage {
        case HIDUsage.volumeUp where event.phase == "down":
            if selectCompanionQuickAction(by: -1) {
                suppressGesture(.volumeUp)
                return true
            }
        case HIDUsage.volumeDown where event.phase == "down":
            if selectCompanionQuickAction(by: 1) {
                suppressGesture(.volumeDown)
                return true
            }
        case HIDUsage.center where event.phase == "down":
            companionCenterPressStartedAt = Date()
            logStatus(name: "COMPANION_CENTER_RAW", note: "center press began")
            scheduleCompanionHoldToSpeak()
            return true
        case HIDUsage.center where event.phase == "up":
            guard let startedAt = companionCenterPressStartedAt else {
                return false
            }

            companionCenterPressStartedAt = nil
            cancelCompanionHoldToSpeak()
            let duration = Date().timeIntervalSince(startedAt)
            if companionPushToTalkActive || companionSpeechRecognizer.isCapturing {
                finishCompanionPushToTalk()
                return true
            }

            if duration < 0.55 {
                logStatus(name: "COMPANION_CENTER_RAW", note: "waiting for delayed tap resolution after \(Int(duration * 1000))ms press")
                return true
            }

            logStatus(name: "COMPANION_CENTER_RAW", note: "center released after \(Int(duration * 1000))ms without immediate confirm")
            return true
        default:
            return true
        }

        return false
    }

    private func handleCompanionGesture(_ event: GestureEvent) -> Bool {
        guard let companionCardController, companionCardController.isVisible else {
            return false
        }

        if shouldSuppressGesture(event.gesture) {
            logStatus(name: "COMPANION_SUPPRESSED_GESTURE", note: "suppressed delayed \(event.gesture.rawValue) while companion was open")
            return true
        }

        switch event.gesture {
        case .volumeUp:
            if selectCompanionQuickAction(by: -1) {
                return true
            }
            logStatus(name: "COMPANION_IGNORED_GESTURE", note: "ignored volume_up while no fallback actions were visible")
        case .volumeDown:
            if selectCompanionQuickAction(by: 1) {
                return true
            }
            logStatus(name: "COMPANION_IGNORED_GESTURE", note: "ignored volume_down while no fallback actions were visible")
        case .centerSingle:
            if confirmCompanionQuickAction(source: "gesture-center") {
                return true
            }
            logStatus(name: "COMPANION_IGNORED_GESTURE", note: "ignored center_single while no fallback actions were visible; hold center to speak")
        case .centerDouble:
            closeCompanionCard(source: "center_double", reopenLauncher: companionReopenLauncherOnClose)
        case .centerHold:
            logStatus(name: "COMPANION_IGNORED_GESTURE", note: "ignored center_hold because push-to-talk owns the hold gesture")
        default:
            logStatus(name: "COMPANION_IGNORED_GESTURE", note: "ignored \(event.gesture.rawValue) while companion was open")
        }

        return true
    }

    private func handleSupportRawEvent(_ event: HIDRawEvent) -> Bool {
        guard event.usagePage == 12 else {
            return false
        }
        guard let supportCardController, supportCardController.isVisible else {
            return false
        }

        switch event.usage {
        case HIDUsage.volumeUp where event.phase == "down":
            if let selection = supportCardController.moveSelection(by: -1) {
                suppressGesture(.volumeUp)
                logStatus(name: "SUPPORT_NAV_RAW", note: "moved up immediately to \(selection.index): \(selection.action.title)")
                return true
            }
        case HIDUsage.volumeDown where event.phase == "down":
            if let selection = supportCardController.moveSelection(by: 1) {
                suppressGesture(.volumeDown)
                logStatus(name: "SUPPORT_NAV_RAW", note: "moved down immediately to \(selection.index): \(selection.action.title)")
                return true
            }
        case HIDUsage.center where event.phase == "down":
            supportCenterPressStartedAt = Date()
            logStatus(name: "SUPPORT_CENTER_RAW", note: "center press began")
            return true
        case HIDUsage.center where event.phase == "up":
            guard let startedAt = supportCenterPressStartedAt else {
                return false
            }

            supportCenterPressStartedAt = nil
            let duration = Date().timeIntervalSince(startedAt)
            if duration < 0.55, let selection = supportCardController.confirmSelection() {
                suppressGesture(.centerSingle)
                logStatus(name: "SUPPORT_CONFIRM_RAW", note: "confirmed immediately after \(Int(duration * 1000))ms press")
                handleSupportSelection(action: selection.action, index: selection.index)
                return true
            }

            logStatus(name: "SUPPORT_CENTER_RAW", note: "center released after \(Int(duration * 1000))ms without immediate confirm")
            return true
        default:
            break
        }

        return false
    }

    private func handleCurrentThreadRawEvent(_ event: HIDRawEvent) -> Bool {
        guard event.usagePage == 12 else {
            return false
        }
        guard let currentThreadCardController, currentThreadCardController.isVisible else {
            return false
        }

        switch event.usage {
        case HIDUsage.volumeUp where event.phase == "down":
            if let selection = currentThreadCardController.moveSelection(by: -1) {
                suppressGesture(.volumeUp)
                logStatus(name: "CURRENT_THREAD_NAV_RAW", note: "moved up immediately to \(selection.index): \(selection.action.title)")
                return true
            }
        case HIDUsage.volumeDown where event.phase == "down":
            if let selection = currentThreadCardController.moveSelection(by: 1) {
                suppressGesture(.volumeDown)
                logStatus(name: "CURRENT_THREAD_NAV_RAW", note: "moved down immediately to \(selection.index): \(selection.action.title)")
                return true
            }
        case HIDUsage.center where event.phase == "down":
            currentThreadCenterPressStartedAt = Date()
            logStatus(name: "CURRENT_THREAD_CENTER_RAW", note: "center press began")
            return true
        case HIDUsage.center where event.phase == "up":
            guard let startedAt = currentThreadCenterPressStartedAt else {
                return false
            }

            currentThreadCenterPressStartedAt = nil
            let duration = Date().timeIntervalSince(startedAt)
            if duration < 0.55, let selection = currentThreadCardController.confirmSelection() {
                suppressGesture(.centerSingle)
                logStatus(name: "CURRENT_THREAD_CONFIRM_RAW", note: "confirmed immediately after \(Int(duration * 1000))ms press")
                handleCurrentThreadSelection(action: selection.action, index: selection.index)
                return true
            }

            logStatus(name: "CURRENT_THREAD_CENTER_RAW", note: "center released after \(Int(duration * 1000))ms without immediate confirm")
            return true
        default:
            break
        }

        return false
    }

    private func handleCurrentThreadGesture(_ event: GestureEvent) -> Bool {
        guard let currentThreadCardController, currentThreadCardController.isVisible else {
            return false
        }

        if shouldSuppressGesture(event.gesture) {
            logStatus(name: "CURRENT_THREAD_SUPPRESSED_GESTURE", note: "suppressed delayed \(event.gesture.rawValue) while current-thread was open")
            return true
        }

        switch event.gesture {
        case .volumeUp:
            if let selection = currentThreadCardController.moveSelection(by: -1) {
                logStatus(name: "CURRENT_THREAD_NAV", note: "moved up to \(selection.index): \(selection.action.title)")
            } else {
                loudFailure(name: "CURRENT_THREAD_NAV_FAILED", note: "volume_up arrived but no current-thread action was available")
            }
        case .volumeDown:
            if let selection = currentThreadCardController.moveSelection(by: 1) {
                logStatus(name: "CURRENT_THREAD_NAV", note: "moved down to \(selection.index): \(selection.action.title)")
            } else {
                loudFailure(name: "CURRENT_THREAD_NAV_FAILED", note: "volume_down arrived but no current-thread action was available")
            }
        case .centerSingle:
            if let selection = currentThreadCardController.confirmSelection() {
                handleCurrentThreadSelection(action: selection.action, index: selection.index)
            } else {
                loudFailure(name: "CURRENT_THREAD_CONFIRM_FAILED", note: "center_single arrived but nothing was selected in Current Thread")
            }
        case .centerHold:
            closeCurrentThreadCard(source: "center_hold", reopenLauncher: true)
        default:
            logStatus(name: "CURRENT_THREAD_IGNORED_GESTURE", note: "ignored \(event.gesture.rawValue) while current-thread was open")
        }

        return true
    }

    private func handleSupportGesture(_ event: GestureEvent) -> Bool {
        guard let supportCardController, supportCardController.isVisible else {
            return false
        }

        if shouldSuppressGesture(event.gesture) {
            logStatus(name: "SUPPORT_SUPPRESSED_GESTURE", note: "suppressed delayed \(event.gesture.rawValue) while Support was open")
            return true
        }

        switch event.gesture {
        case .volumeUp:
            if let selection = supportCardController.moveSelection(by: -1) {
                logStatus(name: "SUPPORT_NAV", note: "moved up to \(selection.index): \(selection.action.title)")
            } else {
                loudFailure(name: "SUPPORT_NAV_FAILED", note: "volume_up arrived but no Support action was available")
            }
        case .volumeDown:
            if let selection = supportCardController.moveSelection(by: 1) {
                logStatus(name: "SUPPORT_NAV", note: "moved down to \(selection.index): \(selection.action.title)")
            } else {
                loudFailure(name: "SUPPORT_NAV_FAILED", note: "volume_down arrived but no Support action was available")
            }
        case .centerSingle:
            if let selection = supportCardController.confirmSelection() {
                handleSupportSelection(action: selection.action, index: selection.index)
            } else {
                loudFailure(name: "SUPPORT_CONFIRM_FAILED", note: "center_single arrived but nothing was selected in Support")
            }
        case .centerHold:
            closeSupportCard(source: "center_hold", reopenLauncher: true)
        default:
            logStatus(name: "SUPPORT_IGNORED_GESTURE", note: "ignored \(event.gesture.rawValue) while Support was open")
        }

        return true
    }

    private func handleWorkSpellSettingsRawEvent(_ event: HIDRawEvent) -> Bool {
        guard event.usagePage == 12 else {
            return false
        }
        guard let workSpellSettingsCardController, workSpellSettingsCardController.isVisible else {
            return false
        }

        switch event.usage {
        case HIDUsage.volumeUp where event.phase == "down":
            if let selection = workSpellSettingsCardController.moveSelection(by: -1) {
                suppressGesture(.volumeUp)
                logStatus(name: "WORK_SPELL_SETTINGS_NAV_RAW", note: "moved up immediately to \(selection.index): \(selection.row.title)")
                return true
            }
        case HIDUsage.volumeDown where event.phase == "down":
            if let selection = workSpellSettingsCardController.moveSelection(by: 1) {
                suppressGesture(.volumeDown)
                logStatus(name: "WORK_SPELL_SETTINGS_NAV_RAW", note: "moved down immediately to \(selection.index): \(selection.row.title)")
                return true
            }
        case HIDUsage.center where event.phase == "down":
            workSpellSettingsCenterPressStartedAt = Date()
            logStatus(name: "WORK_SPELL_SETTINGS_CENTER_RAW", note: "center press began")
            return true
        case HIDUsage.center where event.phase == "up":
            guard let startedAt = workSpellSettingsCenterPressStartedAt else {
                return false
            }

            workSpellSettingsCenterPressStartedAt = nil
            let duration = Date().timeIntervalSince(startedAt)
            if duration < 0.55, let selection = workSpellSettingsCardController.confirmSelection() {
                suppressGesture(.centerSingle)
                logStatus(name: "WORK_SPELL_SETTINGS_CONFIRM_RAW", note: "confirmed immediately after \(Int(duration * 1000))ms press")
                handleWorkSpellSettingsSelection(selection.row, index: selection.index)
                return true
            }

            logStatus(name: "WORK_SPELL_SETTINGS_CENTER_RAW", note: "center released after \(Int(duration * 1000))ms without immediate confirm")
            return true
        default:
            break
        }

        return false
    }

    private func handleWorkSpellSettingsGesture(_ event: GestureEvent) -> Bool {
        guard let workSpellSettingsCardController, workSpellSettingsCardController.isVisible else {
            return false
        }

        if shouldSuppressGesture(event.gesture) {
            logStatus(name: "WORK_SPELL_SETTINGS_SUPPRESSED_GESTURE", note: "suppressed delayed \(event.gesture.rawValue) while Work Spell settings was open")
            return true
        }

        switch event.gesture {
        case .volumeUp:
            if let selection = workSpellSettingsCardController.moveSelection(by: -1) {
                logStatus(name: "WORK_SPELL_SETTINGS_NAV", note: "moved up to \(selection.index): \(selection.row.title)")
            } else {
                loudFailure(name: "WORK_SPELL_SETTINGS_NAV_FAILED", note: "volume_up arrived but no Work Spell settings row was available")
            }
        case .volumeDown:
            if let selection = workSpellSettingsCardController.moveSelection(by: 1) {
                logStatus(name: "WORK_SPELL_SETTINGS_NAV", note: "moved down to \(selection.index): \(selection.row.title)")
            } else {
                loudFailure(name: "WORK_SPELL_SETTINGS_NAV_FAILED", note: "volume_down arrived but no Work Spell settings row was available")
            }
        case .centerSingle:
            if let selection = workSpellSettingsCardController.confirmSelection() {
                handleWorkSpellSettingsSelection(selection.row, index: selection.index)
            } else {
                loudFailure(name: "WORK_SPELL_SETTINGS_CONFIRM_FAILED", note: "center_single arrived but nothing was selected in Work Spell settings")
            }
        case .centerHold:
            closeWorkSpellSettingsCard(source: "center_hold", reopenCipher: true)
        default:
            logStatus(name: "WORK_SPELL_SETTINGS_IGNORED_GESTURE", note: "ignored \(event.gesture.rawValue) while Work Spell settings was open")
        }

        return true
    }

    private func handleWorkSpellRawEvent(_ event: HIDRawEvent) -> Bool {
        guard event.usagePage == 12 else {
            return false
        }
        guard let workSpellCardController, workSpellCardController.isVisible else {
            return false
        }

        switch event.usage {
        case HIDUsage.volumeUp where event.phase == "down":
            if let selection = workSpellCardController.moveSelection(by: -1) {
                suppressGesture(.volumeUp)
                if case .row(_, let index) = selection {
                    recordLastVisibleSurface(.workSpell(selectedIndex: index))
                }
                logStatus(name: "WORK_SPELL_NAV_RAW", note: "moved up immediately in Work Spell")
                return true
            }
        case HIDUsage.volumeDown where event.phase == "down":
            if let selection = workSpellCardController.moveSelection(by: 1) {
                suppressGesture(.volumeDown)
                if case .row(_, let index) = selection {
                    recordLastVisibleSurface(.workSpell(selectedIndex: index))
                }
                logStatus(name: "WORK_SPELL_NAV_RAW", note: "moved down immediately in Work Spell")
                return true
            }
        case HIDUsage.center where event.phase == "down":
            workSpellCenterPressStartedAt = Date()
            logStatus(name: "WORK_SPELL_CENTER_RAW", note: "center press began")
            return true
        case HIDUsage.center where event.phase == "up":
            guard let startedAt = workSpellCenterPressStartedAt else {
                return false
            }

            workSpellCenterPressStartedAt = nil
            let duration = Date().timeIntervalSince(startedAt)
            if duration < 0.55, let selection = workSpellCardController.confirmSelection() {
                suppressGesture(.centerSingle)
                if case .row(let row, let index) = selection {
                    logStatus(name: "WORK_SPELL_CONFIRM_RAW", note: "confirmed immediately after \(Int(duration * 1000))ms press")
                    handleWorkSpellSelection(row, index: index)
                    return true
                }
            }

            logStatus(name: "WORK_SPELL_CENTER_RAW", note: "center released after \(Int(duration * 1000))ms without immediate confirm")
            return true
        default:
            break
        }

        return false
    }

    private func handleWorkSpellGesture(_ event: GestureEvent) -> Bool {
        guard let workSpellCardController, workSpellCardController.isVisible else {
            return false
        }

        if shouldSuppressGesture(event.gesture) {
            logStatus(name: "WORK_SPELL_SUPPRESSED_GESTURE", note: "suppressed delayed \(event.gesture.rawValue) while Work Spell was open")
            return true
        }

        if event.gesture == workSpellStore.binding(for: .addTask) {
            focusWorkSpellInput(source: event.gesture.rawValue)
            return true
        }

        if event.gesture == workSpellStore.binding(for: .completeTask) {
            completeSelectedWorkSpellTask(source: event.gesture.rawValue)
            return true
        }

        switch event.gesture {
        case .volumeUp:
            if let selection = workSpellCardController.moveSelection(by: -1) {
                if case .row(_, let index) = selection {
                    recordLastVisibleSurface(.workSpell(selectedIndex: index))
                }
                logStatus(name: "WORK_SPELL_NAV", note: "moved up in Work Spell")
            } else {
                loudFailure(name: "WORK_SPELL_NAV_FAILED", note: "volume_up arrived but no Work Spell row was available")
            }
        case .volumeDown:
            if let selection = workSpellCardController.moveSelection(by: 1) {
                if case .row(_, let index) = selection {
                    recordLastVisibleSurface(.workSpell(selectedIndex: index))
                }
                logStatus(name: "WORK_SPELL_NAV", note: "moved down in Work Spell")
            } else {
                loudFailure(name: "WORK_SPELL_NAV_FAILED", note: "volume_down arrived but no Work Spell row was available")
            }
        case .centerSingle:
            if let selection = workSpellCardController.confirmSelection(),
               case .row(let row, let index) = selection {
                handleWorkSpellSelection(row, index: index)
            } else {
                loudFailure(name: "WORK_SPELL_CONFIRM_FAILED", note: "center_single arrived but nothing was selected in Work Spell")
            }
        case .centerHold:
            closeWorkSpellCard(source: "center_hold")
        default:
            logStatus(name: "WORK_SPELL_IGNORED_GESTURE", note: "ignored \(event.gesture.rawValue) while Work Spell was open")
        }

        return true
    }

    private func handleSupportSelection(action: SupportAction, index: Int) {
        switch action.kind {
        case .openSpeechSettings:
            if openSupportSettings(urlStrings: [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition",
                "x-apple.systempreferences:com.apple.preference.security"
            ]) {
                logStatus(name: "SUPPORT_ACTION", note: "opened speech settings")
                displayPortalNotification(title: "Support", body: "Opened Speech settings")
                refreshSupportCard(source: "speech-settings", selectedIndex: index)
            } else {
                loudFailure(name: "SUPPORT_ACTION_FAILED", note: "could not open Speech settings")
            }
        case .openMicrophoneSettings:
            if openSupportSettings(urlStrings: [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
                "x-apple.systempreferences:com.apple.preference.security"
            ]) {
                logStatus(name: "SUPPORT_ACTION", note: "opened microphone settings")
                displayPortalNotification(title: "Support", body: "Opened Microphone settings")
                refreshSupportCard(source: "microphone-settings", selectedIndex: index)
            } else {
                loudFailure(name: "SUPPORT_ACTION_FAILED", note: "could not open Microphone settings")
            }
        case .openAccessibilitySettings:
            closeSupportCard(source: "accessibility-prompt", reopenLauncher: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self] in
                guard let self else {
                    return
                }
                if self.requestAccessibilityAccess() {
                    self.logStatus(name: "SUPPORT_ACTION", note: "requested accessibility access")
                    self.displayPortalNotification(title: "Support", body: "Requested Accessibility access")
                } else {
                    self.loudFailure(name: "SUPPORT_ACTION_FAILED", note: "could not open Accessibility settings")
                }
            }
        case .openCompanionHelp:
            closeSupportCard(source: "support-companion-help", reopenLauncher: false)
            logStatus(name: "SUPPORT_ACTION", note: "opened companion help from support")
            showCompanionHelpFromSupport()
        case .restartInlay:
            guard relaunchCurrentApplication() else {
                loudFailure(name: "SUPPORT_ACTION_FAILED", note: "could not schedule an Inlay restart")
                return
            }
            logStatus(name: "SUPPORT_ACTION", note: "scheduled Inlay relaunch")
            closeSupportCard(source: "restart-inlay", reopenLauncher: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) {
                NSApp.terminate(nil)
            }
        case .revealLogs:
            if revealSupportItem(at: URL(fileURLWithPath: config.logPath).deletingLastPathComponent()) {
                logStatus(name: "SUPPORT_ACTION", note: "revealed logs folder")
                displayPortalNotification(title: "Support", body: "Revealed logs in Finder")
            } else {
                loudFailure(name: "SUPPORT_ACTION_FAILED", note: "could not reveal logs folder")
            }
        case .revealSupportFiles:
            if revealSupportItem(at: URL(fileURLWithPath: config.companionConfigPath).deletingLastPathComponent()) {
                logStatus(name: "SUPPORT_ACTION", note: "revealed support files folder")
                displayPortalNotification(title: "Support", body: "Revealed support files in Finder")
            } else {
                loudFailure(name: "SUPPORT_ACTION_FAILED", note: "could not reveal support files folder")
            }
        case .back:
            closeSupportCard(source: "back-row", reopenLauncher: true)
        }
    }

    private func makeWorkSpellCardModel() -> WorkSpellCardModel {
        let pendingTasks = workSpellStore.activeTasks()
        let completedCount = workSpellStore.completedTaskCount()
        let readyCount = workSpellStore.readyTaskCount()
        let oracle = workSpellStore.oracleDecision()
        let addGesture = workSpellGestureDisplayTitle(workSpellStore.binding(for: .addTask))
        let doneGesture = workSpellGestureDisplayTitle(workSpellStore.binding(for: .completeTask))
        let activeTaskIDs = Set(pendingTasks.map(\.id))
        let taskOrder = Dictionary(uniqueKeysWithValues: pendingTasks.enumerated().map { ($1.id, $0) })

        var prerequisiteChildren: [String: [WorkSpellTask]] = [:]
        var successorChildren: [String: [WorkSpellTask]] = [:]
        for task in pendingTasks {
            guard let parentTaskID = task.parentTaskID, activeTaskIDs.contains(parentTaskID) else {
                continue
            }
            switch task.branchRole {
            case .successor:
                successorChildren[parentTaskID, default: []].append(task)
            default:
                prerequisiteChildren[parentTaskID, default: []].append(task)
            }
        }

        let orderedTaskEntries: [(task: WorkSpellTask, indentLevel: Int)] = {
            let roots = pendingTasks.filter { task in
                guard let parentTaskID = task.parentTaskID else {
                    return true
                }
                return !activeTaskIDs.contains(parentTaskID)
            }

            var visited: Set<String> = []
            var entries: [(task: WorkSpellTask, indentLevel: Int)] = []

            func appendBranch(_ task: WorkSpellTask, indentLevel: Int) {
                guard visited.insert(task.id).inserted else {
                    return
                }

                entries.append((task, indentLevel))

                for child in (prerequisiteChildren[task.id] ?? []).sorted(by: {
                    (taskOrder[$0.id] ?? 0) < (taskOrder[$1.id] ?? 0)
                }) {
                    appendBranch(child, indentLevel: indentLevel + 1)
                }

                for child in (successorChildren[task.id] ?? []).sorted(by: {
                    (taskOrder[$0.id] ?? 0) < (taskOrder[$1.id] ?? 0)
                }) {
                    appendBranch(child, indentLevel: indentLevel + 1)
                }
            }

            for root in roots {
                appendBranch(root, indentLevel: 0)
            }

            for task in pendingTasks where !visited.contains(task.id) {
                appendBranch(task, indentLevel: 0)
            }

            return entries
        }()

        var rows: [WorkSpellRow] = orderedTaskEntries.map { entry in
            let task = entry.task
            let unmet = workSpellStore.unmetPrerequisiteTitles(for: task)
            let isNext = oracle.nextTaskID == task.id
            let parentTitle = task.parentTaskID.flatMap { workSpellStore.task(withID: $0)?.title }
            let detail: String
            let symbol: String
            let style: WorkSpellRowStyle
            let eyebrow: String?

            if isNext {
                let branchLead: String?
                switch task.branchRole {
                case .prerequisite:
                    branchLead = parentTitle.map { "Needed before \($0)." }
                case .successor:
                    branchLead = parentTitle.map {
                        workSpellStore.mode == .ordered
                            ? "This unlocks after \($0)."
                            : "This branch sits under \($0)."
                    }
                case nil:
                    branchLead = nil
                }

                if unmet.isEmpty {
                    detail = [branchLead, "Momentum Oracle says start here."].compactMap { $0 }.joined(separator: " ")
                } else {
                    detail = [branchLead, "Unblock \(unmet.joined(separator: ", ")) first."].compactMap { $0 }.joined(separator: " ")
                }
                symbol = "sparkles"
                style = .focus
                eyebrow = "MOMENTUM ORACLE"
            } else if !unmet.isEmpty {
                let branchLead: String?
                switch task.branchRole {
                case .prerequisite:
                    branchLead = parentTitle.map { "Needed before \($0)." }
                case .successor:
                    branchLead = parentTitle.map {
                        workSpellStore.mode == .ordered
                            ? "Comes after \($0)."
                            : "Grouped under \($0)."
                    }
                case nil:
                    branchLead = nil
                }

                detail = [branchLead, "Waiting on \(unmet.joined(separator: ", "))."].compactMap { $0 }.joined(separator: " ")
                symbol = "point.bottomleft.forward.to.point.topright.scurvepath"
                style = .blocked
                switch task.branchRole {
                case .prerequisite:
                    eyebrow = "PREREQUISITE"
                case .successor:
                    eyebrow = workSpellStore.mode == .ordered ? "THEN" : "BRANCH"
                case nil:
                    eyebrow = "WAITING ON \(unmet.count)"
                }
            } else {
                switch task.branchRole {
                case .prerequisite:
                    detail = parentTitle.map { "Needed before \($0)." } ?? "Ready before its parent branch."
                    symbol = "arrow.triangle.branch"
                    eyebrow = "PREREQUISITE"
                case .successor:
                    detail = parentTitle.map {
                        workSpellStore.mode == .ordered
                            ? "Unlocked after \($0)."
                            : "Free branch under \($0)."
                    } ?? "Ready when you are."
                    symbol = "arrow.turn.down.right"
                    eyebrow = workSpellStore.mode == .ordered ? "THEN" : "BRANCH"
                case nil:
                    detail = "Ready when you are."
                    symbol = "circle"
                    eyebrow = nil
                }
                style = .task
            }

            return WorkSpellRow(
                kind: .task(task.id),
                eyebrow: eyebrow,
                title: task.title,
                detail: detail,
                symbol: symbol,
                isEnabled: true,
                style: style,
                indentLevel: entry.indentLevel
            )
        }

        if rows.isEmpty {
            rows.append(
                WorkSpellRow(
                    kind: .newTask,
                    eyebrow: "SPELL IS EMPTY",
                    title: "No Tasks Yet",
                    detail: "Use your add gesture, type below, or speak a task dump in Companion.",
                    symbol: "checklist",
                    isEnabled: false,
                    style: .empty,
                    indentLevel: 0
                )
            )
        }

        rows.append(
            WorkSpellRow(
                kind: .newTask,
                eyebrow: "CONTROL",
                title: "Add New Task",
                detail: "Focus the input or say another task in Companion.",
                symbol: "plus.circle",
                isEnabled: true,
                style: .utility,
                indentLevel: 0
            )
        )
        rows.append(
            WorkSpellRow(
                kind: .shapeByVoice,
                eyebrow: "CONTROL",
                title: "Shape by Voice",
                detail: "Speak tasks, say ordered or unordered, or describe the next branch out loud.",
                symbol: "waveform.badge.mic",
                isEnabled: true,
                style: .utility,
                indentLevel: 0
            )
        )
        rows.append(
            WorkSpellRow(
                kind: .openLauncher,
                eyebrow: "CONTROL",
                title: "Open Launcher",
                detail: "Jump back to the main Inlay launcher.",
                symbol: "square.grid.2x2",
                isEnabled: true,
                style: .utility,
                indentLevel: 0
            )
        )
        rows.append(
            WorkSpellRow(
                kind: .deactivateSpell,
                eyebrow: "CONTROL",
                title: workSpellStore.isActive ? "Deactivate Work Spell" : "Activate Work Spell",
                detail: workSpellStore.isActive
                    ? "Stop routing hidden center-hold into this spell."
                    : "Pin this spell onto hidden center-hold.",
                symbol: workSpellStore.isActive ? "moon.zzz" : "wand.and.stars",
                isEnabled: true,
                style: .utility,
                indentLevel: 0
            )
        )

        let modeLabel = workSpellStore.mode.title
        let modeFooter = workSpellStore.mode == .ordered
            ? "Ordered mode locks dependent branches until their prerequisites are done."
            : "Unordered mode keeps every branch available even when it is grouped visually."

        return WorkSpellCardModel(
            title: "Work Spell",
            subtitle: oracle.headline,
            metadataText: "\(modeLabel) • \(readyCount) ready • \(pendingTasks.count) pending • \(completedCount) done • Add: \(addGesture) • Done: \(doneGesture)",
            footer: "\(oracle.detail) \(modeFooter) Use Shape by Voice or say dependencies like “research before design”. Hold center closes.",
            inputPlaceholder: "Type tasks, or type ordered / unordered",
            rows: rows
        )
    }

    private func makeWorkSpellSettingsModel() -> WorkSpellSettingsModel {
        let pendingCount = workSpellStore.activeTasks().count
        let completedCount = workSpellStore.completedTaskCount()
        let addGesture = workSpellGestureDisplayTitle(workSpellStore.binding(for: .addTask))
        let doneGesture = workSpellGestureDisplayTitle(workSpellStore.binding(for: .completeTask))

        return WorkSpellSettingsModel(
            title: "Spellbook",
            subtitle: "Configure Work Spell and its private controls.",
            metadataText: "\(workSpellStore.isActive ? "Active" : "Inactive") • \(workSpellStore.mode.title) • \(pendingCount) pending • \(completedCount) done",
            footer: "Tap center to toggle or cycle. Hold center returns to Cipher.",
            rows: [
                WorkSpellSettingsRow(
                    kind: .toggleActive,
                    title: workSpellStore.isActive ? "Deactivate Work Spell" : "Activate Work Spell",
                    detail: workSpellStore.isActive
                        ? "Return hidden center-hold to the launcher."
                        : "Make hidden center-hold open Work Spell.",
                    symbol: workSpellStore.isActive ? "moon.zzz" : "wand.and.stars",
                    isEnabled: true
                ),
                WorkSpellSettingsRow(
                    kind: .openNow,
                    title: "Open Work Spell Now",
                    detail: "Preview the task card immediately.",
                    symbol: "checklist",
                    isEnabled: true
                ),
                WorkSpellSettingsRow(
                    kind: .cycleMode,
                    title: "Structure Mode",
                    detail: "Current: \(workSpellStore.mode.title) • \(workSpellStore.mode.helperDetail)",
                    symbol: "arrow.triangle.branch",
                    isEnabled: true
                ),
                WorkSpellSettingsRow(
                    kind: .cycleAddGesture,
                    title: "Add Gesture",
                    detail: "Current: \(addGesture)",
                    symbol: "plus.circle",
                    isEnabled: true
                ),
                WorkSpellSettingsRow(
                    kind: .cycleCompleteGesture,
                    title: "Done Gesture",
                    detail: "Current: \(doneGesture)",
                    symbol: "checkmark.circle",
                    isEnabled: true
                ),
                WorkSpellSettingsRow(
                    kind: .clearCompleted,
                    title: "Clear Completed Tasks",
                    detail: completedCount > 0 ? "Remove \(completedCount) finished task\(completedCount == 1 ? "" : "s")." : "Nothing completed yet.",
                    symbol: "trash",
                    isEnabled: completedCount > 0
                ),
                WorkSpellSettingsRow(
                    kind: .back,
                    title: "Back",
                    detail: "Return to Cipher.",
                    symbol: "chevron.backward.circle",
                    isEnabled: true
                ),
            ]
        )
    }

    private func ensureWorkSpellCardController() -> WorkSpellCardController {
        if let workSpellCardController {
            return workSpellCardController
        }

        let controller = WorkSpellCardController()
        controller.onSubmit = { [weak self] text in
            Task { @MainActor in
                self?.handleWorkSpellInput(text, source: "keyboard")
            }
        }
        controller.onSelectionActivated = { [weak self] row, index in
            Task { @MainActor in
                self?.handleWorkSpellSelection(row, index: index)
            }
        }
        workSpellCardController = controller
        logStatus(name: "WORK_SPELL_INIT", note: "created Work Spell controller")
        return controller
    }

    private func ensureWorkSpellSettingsCardController() -> WorkSpellSettingsCardController {
        if let workSpellSettingsCardController {
            return workSpellSettingsCardController
        }

        let controller = WorkSpellSettingsCardController()
        controller.onSelectionActivated = { [weak self] row, index in
            Task { @MainActor in
                self?.handleWorkSpellSettingsSelection(row, index: index)
            }
        }
        workSpellSettingsCardController = controller
        logStatus(name: "WORK_SPELL_SETTINGS_INIT", note: "created Work Spell settings controller")
        return controller
    }

    private func preferredWorkSpellSelectionIndex(in model: WorkSpellCardModel) -> Int {
        if let oracleIndex = model.rows.firstIndex(where: { row in
            row.eyebrow == "MOMENTUM ORACLE"
        }) {
            return oracleIndex
        }

        if let firstTaskIndex = model.rows.firstIndex(where: { row in
            if case .task = row.kind {
                return true
            }
            return false
        }) {
            return firstTaskIndex
        }

        return model.rows.firstIndex(where: \.isEnabled) ?? 0
    }

    private func openWorkSpellCard(source: String, selectedIndex: Int? = nil, focusInput: Bool = false) {
        let controller = ensureWorkSpellCardController()
        clearHUDInteractionState()
        let model = makeWorkSpellCardModel()
        let resolvedSelection = selectedIndex ?? preferredWorkSpellSelectionIndex(in: model)
        let shown = controller.show(model: model, selectedIndex: resolvedSelection, focusInput: focusInput)
        if shown {
            if case .row(_, let currentIndex)? = controller.currentSelection() {
                recordLastVisibleSurface(.workSpell(selectedIndex: currentIndex))
            } else {
                recordLastVisibleSurface(.workSpell(selectedIndex: resolvedSelection))
            }
            logStatus(name: "WORK_SPELL_OPEN", note: "opened via \(source)")
        } else {
            loudFailure(name: "WORK_SPELL_OPEN_FAILED", note: "\(source) requested Work Spell but the card did not become visible")
        }
    }

    private func closeWorkSpellCard(source: String) {
        guard let workSpellCardController, workSpellCardController.isVisible else {
            return
        }

        let closed = workSpellCardController.close()
        if closed {
            clearHUDInteractionState()
            logStatus(name: "WORK_SPELL_CLOSE", note: "closed via \(source)")
        } else {
            loudFailure(name: "WORK_SPELL_CLOSE_FAILED", note: "\(source) requested close but the Work Spell card still appears visible")
        }
    }

    private func openWorkSpellSettingsCard(source: String, selectedIndex: Int? = nil) {
        let controller = ensureWorkSpellSettingsCardController()
        clearHUDInteractionState()
        let shown = controller.show(model: makeWorkSpellSettingsModel(), selectedIndex: selectedIndex)
        if shown {
            logStatus(name: "WORK_SPELL_SETTINGS_OPEN", note: "opened via \(source)")
        } else {
            loudFailure(name: "WORK_SPELL_SETTINGS_OPEN_FAILED", note: "\(source) requested Work Spell settings but the card did not become visible")
        }
    }

    private func closeWorkSpellSettingsCard(source: String, reopenCipher: Bool) {
        guard let workSpellSettingsCardController, workSpellSettingsCardController.isVisible else {
            return
        }

        let closed = workSpellSettingsCardController.close()
        if closed {
            clearHUDInteractionState()
            logStatus(name: "WORK_SPELL_SETTINGS_CLOSE", note: "closed via \(source)")
            if reopenCipher {
                openCipherCard(source: "work-spell-settings-return", selectedIndex: cipherSpellIndex(for: .spellbook))
            }
        } else {
            loudFailure(name: "WORK_SPELL_SETTINGS_CLOSE_FAILED", note: "\(source) requested close but the Work Spell settings card still appears visible")
        }
    }

    @discardableResult
    private func activateWorkSpell(seedTasks: [String], source: String, openCard: Bool = true, rawText: String? = nil) -> [WorkSpellTask] {
        do {
            try workSpellStore.setActive(true)
            let sourceText = rawText ?? seedTasks.joined(separator: ", ")
            _ = applyRequestedWorkSpellMode(from: sourceText, source: source)
            let added: [WorkSpellTask]
            if let rawText,
               let structuredPlan = WorkSpellTaskParser.structuredPlan(from: rawText) {
                added = addStructuredWorkSpellPlan(structuredPlan, source: source)
            } else {
                added = try workSpellStore.addTasks(titles: seedTasks)
            }
            let note = added.isEmpty ? "activated via \(source)" : "activated via \(source) with \(added.count) seeded task(s)"
            logStatus(name: "WORK_SPELL_ACTIVATE", note: note)
            if openCard {
                openWorkSpellCard(source: source, focusInput: added.isEmpty)
            }
            displayPortalNotification(
                title: "Work Spell",
                body: added.isEmpty
                    ? "Activated"
                    : "Activated with \(added.count) task\(added.count == 1 ? "" : "s")"
            )
            return added
        } catch {
            loudFailure(name: "WORK_SPELL_ACTIVATE_FAILED", note: error.localizedDescription)
            return []
        }
    }

    private func deactivateWorkSpell(source: String, reopenLauncher: Bool = false) {
        do {
            try workSpellStore.setActive(false)
            logStatus(name: "WORK_SPELL_DEACTIVATE", note: "deactivated via \(source)")
            closeWorkSpellCard(source: source)
            if reopenLauncher {
                showMainHUD(source: "work-spell-deactivate", selectedIndex: launcherIndex(forItemID: LauncherItem.companionItem.id) ?? 0)
            }
            displayPortalNotification(title: "Work Spell", body: "Deactivated")
        } catch {
            loudFailure(name: "WORK_SPELL_DEACTIVATE_FAILED", note: error.localizedDescription)
        }
    }

    @discardableResult
    private func addWorkSpellTasks(_ titles: [String], source: String, focusInput: Bool = false) -> [WorkSpellTask] {
        do {
            let addedTasks = try workSpellStore.addTasks(titles: titles)
            guard !addedTasks.isEmpty else {
                return []
            }
            let selectedIndex = addedTasks.last.flatMap { addedTask in
                workSpellStore.activeTasks().firstIndex(where: { $0.id == addedTask.id })
            }
            if let workSpellCardController, workSpellCardController.isVisible {
                workSpellCardController.update(model: makeWorkSpellCardModel(), selectedIndex: selectedIndex)
                if focusInput {
                    workSpellCardController.focusInput()
                }
            }
            let summary = addedTasks.count == 1
                ? addedTasks[0].title
                : "\(addedTasks.count) tasks"
            logStatus(name: "WORK_SPELL_ADD_TASK", note: "added \(summary) via \(source)")
            displayPortalNotification(title: "Work Spell", body: "Added \(summary)")
            return addedTasks
        } catch {
            loudFailure(name: "WORK_SPELL_ADD_FAILED", note: error.localizedDescription)
            return []
        }
    }

    @discardableResult
    private func removeWorkSpellTasks(matchingTitles titles: [String], source: String) -> [WorkSpellTask] {
        do {
            let removedTasks = try workSpellStore.removeTasks(matchingTitles: titles)
            guard !removedTasks.isEmpty else {
                return []
            }
            if let workSpellCardController, workSpellCardController.isVisible {
                workSpellCardController.update(model: makeWorkSpellCardModel())
            }
            let summary = removedTasks.count == 1
                ? removedTasks[0].title
                : "\(removedTasks.count) tasks"
            logStatus(name: "WORK_SPELL_REMOVE_TASK", note: "removed \(summary) via \(source)")
            displayPortalNotification(title: "Work Spell", body: "Removed \(summary)")
            return removedTasks
        } catch {
            loudFailure(name: "WORK_SPELL_REMOVE_FAILED", note: error.localizedDescription)
            return []
        }
    }

    private func handleWorkSpellInput(_ text: String, source: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        _ = applyRequestedWorkSpellMode(from: trimmed, source: source)

        let removeTitles = WorkSpellTaskParser.taskTitlesForRemovalCommand(from: trimmed)
        if !removeTitles.isEmpty {
            let removed = removeWorkSpellTasks(matchingTitles: removeTitles, source: source)
            if removed.isEmpty {
                loudFailure(name: "WORK_SPELL_REMOVE_FAILED", note: "no active task matched “\(trimmed)”")
                if source == "keyboard" {
                    ensureWorkSpellCardController().focusInput()
                }
            } else if source == "keyboard" {
                workSpellCardController?.exitComposerMode()
                ensureWorkSpellCardController().clearInput()
            }
            return
        }

        if WorkSpellTaskParser.isModeOnlyCommand(trimmed) {
            if let workSpellCardController, workSpellCardController.isVisible {
                workSpellCardController.update(model: makeWorkSpellCardModel())
            }
            if source == "keyboard" {
                workSpellCardController?.exitComposerMode()
                ensureWorkSpellCardController().clearInput()
            }
            return
        }

        if let structuredPlan = WorkSpellTaskParser.structuredPlan(from: trimmed) {
            let added = addStructuredWorkSpellPlan(structuredPlan, source: source)
            if added.isEmpty {
                loudFailure(name: "WORK_SPELL_ADD_FAILED", note: "structured input “\(trimmed)” did not produce a task")
                if source == "keyboard" {
                    ensureWorkSpellCardController().focusInput()
                }
            } else if source == "keyboard" {
                workSpellCardController?.exitComposerMode()
                ensureWorkSpellCardController().clearInput()
            }
            return
        }

        let addTitles = WorkSpellTaskParser.taskTitlesForAddCommand(from: trimmed)
        let fallbackTitles = WorkSpellTaskParser.taskTitles(fromListText: trimmed)
        let titlesToAdd = !addTitles.isEmpty ? addTitles : fallbackTitles
        let added = addWorkSpellTasks(titlesToAdd, source: source, focusInput: false)
        if added.isEmpty {
            loudFailure(name: "WORK_SPELL_ADD_FAILED", note: "input “\(trimmed)” did not produce a task")
            if source == "keyboard" {
                ensureWorkSpellCardController().focusInput()
            }
        } else if source == "keyboard" {
            workSpellCardController?.exitComposerMode()
            ensureWorkSpellCardController().clearInput()
        }
    }

    private func focusWorkSpellInput(source: String) {
        guard let workSpellCardController, workSpellCardController.isVisible else {
            return
        }
        workSpellCardController.focusInput()
        logStatus(name: "WORK_SPELL_ADD_GESTURE", note: "focused task input via \(source)")
    }

    private func completeSelectedWorkSpellTask(source: String) {
        guard let workSpellCardController, workSpellCardController.isVisible,
              case .row(let row, let selectedIndex)? = workSpellCardController.currentSelection() else {
            return
        }
        guard case .task(let taskID) = row.kind else {
            return
        }

        do {
            guard let task = try workSpellStore.completeTask(id: taskID) else {
                return
            }
            let rows = makeWorkSpellCardModel().rows
            let nextIndex = min(selectedIndex, max(rows.count - 1, 0))
            workSpellCardController.update(model: makeWorkSpellCardModel(), selectedIndex: nextIndex)
            logStatus(name: "WORK_SPELL_COMPLETE", note: "completed \(task.title) via \(source)")
            displayPortalNotification(title: "Work Spell", body: "Completed \(task.title)")
        } catch {
            loudFailure(name: "WORK_SPELL_COMPLETE_FAILED", note: error.localizedDescription)
        }
    }

    private func handleWorkSpellSelection(_ row: WorkSpellRow, index: Int) {
        switch row.kind {
        case .task:
            completeSelectedWorkSpellTask(source: "center_single")
        case .newTask:
            focusWorkSpellInput(source: "row")
        case .shapeByVoice:
            openCompactCompanion(source: "work-spell-voice", autoListen: true, seededAction: .activateWorkSpell)
        case .openLauncher:
            closeWorkSpellCard(source: "open-launcher-row")
            showMainHUD(source: "work-spell-open-launcher", selectedIndex: launcherIndex(forItemID: LauncherItem.companionItem.id) ?? 0)
        case .deactivateSpell:
            if workSpellStore.isActive {
                deactivateWorkSpell(source: "row", reopenLauncher: true)
            } else {
                activateWorkSpell(seedTasks: [], source: "row", openCard: true)
                ensureWorkSpellCardController().update(model: makeWorkSpellCardModel(), selectedIndex: index)
            }
        }
    }

    private func handleWorkSpellSettingsSelection(_ row: WorkSpellSettingsRow, index: Int) {
        switch row.kind {
        case .toggleActive:
            if workSpellStore.isActive {
                deactivateWorkSpell(source: "settings-toggle")
            } else {
                activateWorkSpell(seedTasks: [], source: "settings-toggle", openCard: false)
            }
            workSpellSettingsCardController?.update(model: makeWorkSpellSettingsModel(), selectedIndex: index)
        case .openNow:
            closeWorkSpellSettingsCard(source: "open-now-row", reopenCipher: false)
            openWorkSpellCard(source: "settings-open-now", focusInput: false)
        case .cycleMode:
            do {
                let mode = try workSpellStore.cycleMode()
                workSpellSettingsCardController?.update(model: makeWorkSpellSettingsModel(), selectedIndex: index)
                if let workSpellCardController, workSpellCardController.isVisible {
                    workSpellCardController.update(model: makeWorkSpellCardModel())
                }
                logStatus(name: "WORK_SPELL_MODE", note: "cycled structure mode to \(mode.rawValue)")
                displayPortalNotification(title: "Work Spell", body: "\(mode.title) mode")
            } catch {
                loudFailure(name: "WORK_SPELL_MODE_FAILED", note: error.localizedDescription)
            }
        case .cycleAddGesture:
            do {
                let gesture = try workSpellStore.cycleBinding(for: .addTask)
                workSpellSettingsCardController?.update(model: makeWorkSpellSettingsModel(), selectedIndex: index)
                logStatus(name: "WORK_SPELL_BINDING", note: "add gesture is now \(gesture.rawValue)")
            } catch {
                loudFailure(name: "WORK_SPELL_BINDING_FAILED", note: error.localizedDescription)
            }
        case .cycleCompleteGesture:
            do {
                let gesture = try workSpellStore.cycleBinding(for: .completeTask)
                workSpellSettingsCardController?.update(model: makeWorkSpellSettingsModel(), selectedIndex: index)
                logStatus(name: "WORK_SPELL_BINDING", note: "complete gesture is now \(gesture.rawValue)")
            } catch {
                loudFailure(name: "WORK_SPELL_BINDING_FAILED", note: error.localizedDescription)
            }
        case .clearCompleted:
            do {
                let removed = try workSpellStore.clearCompleted()
                workSpellSettingsCardController?.update(model: makeWorkSpellSettingsModel(), selectedIndex: index)
                if let workSpellCardController, workSpellCardController.isVisible {
                    workSpellCardController.update(model: makeWorkSpellCardModel())
                }
                logStatus(name: "WORK_SPELL_CLEAR_COMPLETED", note: "removed \(removed) completed task(s)")
            } catch {
                loudFailure(name: "WORK_SPELL_CLEAR_COMPLETED_FAILED", note: error.localizedDescription)
            }
        case .back:
            closeWorkSpellSettingsCard(source: "back-row", reopenCipher: true)
        }
    }

    private func ensureCipherCardController() -> CipherCardController {
        if let cipherCardController {
            return cipherCardController
        }

        let controller = CipherCardController(model: makeCipherCardModel())
        cipherCardController = controller
        logStatus(name: "CIPHER_INIT", note: "created cipher card controller")
        return controller
    }

    private func ensureCipherLexiconCardController() -> CipherLexiconCardController {
        if let cipherLexiconCardController {
            return cipherLexiconCardController
        }

        let controller = CipherLexiconCardController()
        cipherLexiconCardController = controller
        logStatus(name: "CIPHER_LEXICON_INIT", note: "created cipher lexicon controller")
        return controller
    }

    private func ensureCipherLexiconEntryController() -> CipherLexiconEntryController {
        if let cipherLexiconEntryController {
            return cipherLexiconEntryController
        }

        let controller = CipherLexiconEntryController()
        controller.onSubmit = { [weak self] text in
            Task { @MainActor in
                self?.handleCipherLexiconEntrySubmit(text)
            }
        }
        cipherLexiconEntryController = controller
        logStatus(name: "CIPHER_LEXICON_ENTRY_INIT", note: "created cipher lexicon entry controller")
        return controller
    }

    private func ensureCipherUnlockFeedbackController() -> CipherUnlockFeedbackController {
        if let cipherUnlockFeedbackController {
            return cipherUnlockFeedbackController
        }

        let controller = CipherUnlockFeedbackController()
        cipherUnlockFeedbackController = controller
        logStatus(name: "CIPHER_REVEAL_INIT", note: "created cipher unlock feedback controller")
        return controller
    }

    private func ensureCompanionActionFeedbackController() -> PortalActionFeedbackController {
        if let companionActionFeedbackController {
            return companionActionFeedbackController
        }

        let controller = PortalActionFeedbackController()
        companionActionFeedbackController = controller
        logStatus(name: "COMPANION_ACTION_FEEDBACK_INIT", note: "created companion action feedback controller")
        return controller
    }

    private func openCipherLexiconCard(source: String, selectedIndex: Int? = nil) {
        let controller = ensureCipherLexiconCardController()
        clearHUDInteractionState()
        let shown = controller.show(model: makeCipherLexiconModel(), selectedIndex: selectedIndex)
        if shown {
            logStatus(name: "CIPHER_LEXICON_OPEN", note: "opened via \(source)")
        } else {
            loudFailure(name: "CIPHER_LEXICON_OPEN_FAILED", note: "\(source) was recognized but the cipher lexicon did not become visible")
        }
    }

    private func closeCipherLexiconCard(source: String, reopenCipher: Bool) {
        guard let cipherLexiconCardController, cipherLexiconCardController.isVisible else {
            return
        }

        let closed = cipherLexiconCardController.close()
        if closed {
            clearHUDInteractionState()
            logStatus(name: "CIPHER_LEXICON_CLOSE", note: "closed via \(source)")
            if reopenCipher {
                openCipherCard(source: "cipher-lexicon-return", selectedIndex: cipherSpellIndex(for: .lexicon))
            }
        } else {
            loudFailure(name: "CIPHER_LEXICON_CLOSE_FAILED", note: "\(source) requested close but the cipher lexicon still appears visible")
        }
    }

    private func presentCipherLexiconEntry(flow: CipherLexiconEntryFlow, source: String) {
        activeCipherLexiconEntryFlow = flow
        let controller = ensureCipherLexiconEntryController()
        controller.clearInput()
        let shown = controller.show(model: makeCipherLexiconEntryModel(for: flow))
        if shown {
            clearHUDInteractionState()
            logStatus(name: "CIPHER_LEXICON_ENTRY_OPEN", note: "opened \(cipherLexiconEntryDescription(flow)) via \(source)")
        } else {
            loudFailure(name: "CIPHER_LEXICON_ENTRY_OPEN_FAILED", note: "\(source) requested \(cipherLexiconEntryDescription(flow)) but the entry overlay did not become visible")
        }
    }

    private func closeCipherLexiconEntry(source: String, reopenLexicon: Bool) {
        guard let cipherLexiconEntryController, cipherLexiconEntryController.isVisible else {
            activeCipherLexiconEntryFlow = nil
            return
        }

        let flow = activeCipherLexiconEntryFlow
        let closed = cipherLexiconEntryController.close()
        if closed {
            activeCipherLexiconEntryFlow = nil
            clearHUDInteractionState()
            logStatus(name: "CIPHER_LEXICON_ENTRY_CLOSE", note: "closed via \(source)")
            if reopenLexicon {
                openCipherLexiconCard(
                    source: "cipher-lexicon-entry-return",
                    selectedIndex: cipherLexiconRowIndex(for: flow)
                )
            }
        } else {
            loudFailure(name: "CIPHER_LEXICON_ENTRY_CLOSE_FAILED", note: "\(source) requested close but the lexicon entry overlay still appears visible")
        }
    }

    private func handleCipherLexiconSelection(_ selection: CipherLexiconSelection) {
        guard case .row(let row, let index) = selection else {
            return
        }

        switch row.kind {
        case .ritual(let target):
            logStatus(name: "CIPHER_LEXICON_SELECT", note: "selected \(target.rawValue)")
            closeCipherLexiconCard(source: "lexicon-ritual", reopenCipher: false)
            presentCipherLexiconEntry(flow: .ritual(target), source: "cipher-lexicon-row-\(index)")
        case .intentMeaning:
            logStatus(name: "CIPHER_LEXICON_SELECT", note: "selected intent meaning")
            closeCipherLexiconCard(source: "lexicon-intent-meaning", reopenCipher: false)
            presentCipherLexiconEntry(flow: .intentMeaningPhrase, source: "cipher-lexicon-row-\(index)")
        case .savedIntentMeaning(let phrase):
            logStatus(name: "CIPHER_LEXICON_SELECT", note: "selected saved intent meaning \(phrase)")
            closeCipherLexiconCard(source: "lexicon-saved-intent-meaning", reopenCipher: false)
            presentCipherLexiconEntry(flow: .intentMeaningTarget(phrase: phrase), source: "cipher-lexicon-row-\(index)")
        case .macro:
            logStatus(name: "CIPHER_LEXICON_SELECT", note: "selected macro")
            closeCipherLexiconCard(source: "lexicon-macro", reopenCipher: false)
            presentCipherLexiconEntry(flow: .macroPhrase, source: "cipher-lexicon-row-\(index)")
        case .savedMacro(let phrase):
            logStatus(name: "CIPHER_LEXICON_SELECT", note: "selected saved macro \(phrase)")
            closeCipherLexiconCard(source: "lexicon-saved-macro", reopenCipher: false)
            presentCipherLexiconEntry(flow: .macroSteps(phrase: phrase), source: "cipher-lexicon-row-\(index)")
        case .appMeaning:
            logStatus(name: "CIPHER_LEXICON_SELECT", note: "selected app meaning")
            closeCipherLexiconCard(source: "lexicon-app-meaning", reopenCipher: false)
            presentCipherLexiconEntry(flow: .appMeaningPhrase, source: "cipher-lexicon-row-\(index)")
        case .savedAppMeaning(let phrase):
            logStatus(name: "CIPHER_LEXICON_SELECT", note: "selected saved app meaning \(phrase)")
            closeCipherLexiconCard(source: "lexicon-saved-app-meaning", reopenCipher: false)
            presentCipherLexiconEntry(flow: .appMeaningTarget(phrase: phrase), source: "cipher-lexicon-row-\(index)")
        case .correction:
            logStatus(name: "CIPHER_LEXICON_SELECT", note: "selected correction")
            closeCipherLexiconCard(source: "lexicon-correction", reopenCipher: false)
            presentCipherLexiconEntry(flow: .correctionPhrase, source: "cipher-lexicon-row-\(index)")
        case .savedCorrection(let phrase):
            logStatus(name: "CIPHER_LEXICON_SELECT", note: "selected saved correction \(phrase)")
            closeCipherLexiconCard(source: "lexicon-saved-correction", reopenCipher: false)
            presentCipherLexiconEntry(flow: .correctionReplacement(phrase: phrase), source: "cipher-lexicon-row-\(index)")
        case .semanticOpenBias:
            do {
                let preferences = try companionConfigStore.cycleOpenBiasPreference()
                logStatus(name: "CIPHER_LEXICON_PREFERENCE", note: "cycled open bias to \(preferences.openBias.rawValue)")
                displayPortalNotification(title: "Cipher Lexicon", body: "Ambiguous opens: \(preferences.openBias.title)")
                ensureCipherLexiconCardController().update(model: makeCipherLexiconModel(), selectedIndex: index)
            } catch {
                loudFailure(name: "CIPHER_LEXICON_PREFERENCE_FAILED", note: error.localizedDescription)
            }
        case .semanticPreferredBrowser:
            do {
                let preferences = try companionConfigStore.cyclePreferredBrowserPreference()
                logStatus(name: "CIPHER_LEXICON_PREFERENCE", note: "cycled preferred browser to \(preferences.preferredBrowser.rawValue)")
                displayPortalNotification(title: "Cipher Lexicon", body: "Preferred browser: \(preferences.preferredBrowser.title)")
                ensureCipherLexiconCardController().update(model: makeCipherLexiconModel(), selectedIndex: index)
            } catch {
                loudFailure(name: "CIPHER_LEXICON_PREFERENCE_FAILED", note: error.localizedDescription)
            }
        case .resetRituals:
            do {
                try companionConfigStore.clearAllRitualPhrases()
                logStatus(name: "CIPHER_LEXICON_RESET", note: "cleared ritual phrases")
                displayPortalNotification(title: "Cipher Lexicon", body: "Cleared ritual phrases")
                ensureCipherLexiconCardController().update(
                    model: makeCipherLexiconModel(),
                    selectedIndex: index
                )
            } catch {
                loudFailure(name: "CIPHER_LEXICON_RESET_FAILED", note: error.localizedDescription)
            }
        case .resetIntentMeanings:
            do {
                try companionConfigStore.clearAllIntentMeanings()
                logStatus(name: "CIPHER_LEXICON_RESET", note: "cleared intent meanings")
                displayPortalNotification(title: "Cipher Lexicon", body: "Cleared intent meanings")
                ensureCipherLexiconCardController().update(
                    model: makeCipherLexiconModel(),
                    selectedIndex: index
                )
            } catch {
                loudFailure(name: "CIPHER_LEXICON_RESET_FAILED", note: error.localizedDescription)
            }
        case .resetMacros:
            do {
                try companionConfigStore.clearAllMacros()
                logStatus(name: "CIPHER_LEXICON_RESET", note: "cleared macros")
                displayPortalNotification(title: "Cipher Lexicon", body: "Cleared macros")
                ensureCipherLexiconCardController().update(
                    model: makeCipherLexiconModel(),
                    selectedIndex: index
                )
            } catch {
                loudFailure(name: "CIPHER_LEXICON_RESET_FAILED", note: error.localizedDescription)
            }
        case .resetMeanings:
            do {
                try companionConfigStore.clearAllAppMeanings()
                logStatus(name: "CIPHER_LEXICON_RESET", note: "cleared app meanings")
                displayPortalNotification(title: "Cipher Lexicon", body: "Cleared app meanings")
                ensureCipherLexiconCardController().update(
                    model: makeCipherLexiconModel(),
                    selectedIndex: index
                )
            } catch {
                loudFailure(name: "CIPHER_LEXICON_RESET_FAILED", note: error.localizedDescription)
            }
        case .resetCorrections:
            do {
                try companionConfigStore.clearAllCorrections()
                logStatus(name: "CIPHER_LEXICON_RESET", note: "cleared corrections")
                displayPortalNotification(title: "Cipher Lexicon", body: "Cleared corrections")
                ensureCipherLexiconCardController().update(
                    model: makeCipherLexiconModel(),
                    selectedIndex: index
                )
            } catch {
                loudFailure(name: "CIPHER_LEXICON_RESET_FAILED", note: error.localizedDescription)
            }
        case .back:
            closeCipherLexiconCard(source: "back-row", reopenCipher: true)
        }
    }

    private func handleCipherLexiconEntrySubmit(_ text: String) {
        guard let flow = activeCipherLexiconEntryFlow else {
            loudFailure(name: "CIPHER_LEXICON_ENTRY_FAILED", note: "received lexicon input without an active entry flow")
            return
        }

        switch flow {
        case .ritual(let target):
            do {
                try companionConfigStore.saveRitualPhrase(text, for: target)
                logStatus(name: "CIPHER_LEXICON_SAVE", note: "saved ritual phrase for \(target.rawValue)")
                displayPortalNotification(title: "Cipher Lexicon", body: "Saved \(target.title.replacingOccurrences(of: "Teach ", with: "").replacingOccurrences(of: " Phrase", with: ""))")
                closeCipherLexiconEntry(source: "ritual-saved", reopenLexicon: true)
            } catch {
                loudFailure(name: "CIPHER_LEXICON_SAVE_FAILED", note: error.localizedDescription)
            }
        case .intentMeaningPhrase:
            let normalizedPhrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedPhrase.count >= 2 else {
                ensureCipherLexiconEntryController().update(model: makeCipherLexiconEntryModel(for: .intentMeaningPhrase))
                return
            }
            activeCipherLexiconEntryFlow = .intentMeaningTarget(phrase: normalizedPhrase)
            ensureCipherLexiconEntryController().clearInput()
            ensureCipherLexiconEntryController().update(model: makeCipherLexiconEntryModel(for: .intentMeaningTarget(phrase: normalizedPhrase)))
            logStatus(name: "CIPHER_LEXICON_ENTRY_STAGE", note: "captured intent meaning phrase \(normalizedPhrase)")
        case .intentMeaningTarget(let phrase):
            guard let target = CompanionIntentMeaningTarget.parse(from: text) else {
                ensureCipherLexiconEntryController().update(model: makeCipherLexiconEntryModel(for: .intentMeaningTarget(phrase: phrase)))
                return
            }
            do {
                try companionConfigStore.saveIntentMeaning(phrase: phrase, target: target)
                logStatus(name: "CIPHER_LEXICON_SAVE", note: "saved intent meaning \(phrase) => \(target.rawValue)")
                displayPortalNotification(title: "Cipher Lexicon", body: "Taught “\(phrase)” to mean \(target.title)")
                closeCipherLexiconEntry(source: "intent-meaning-saved", reopenLexicon: true)
            } catch {
                loudFailure(name: "CIPHER_LEXICON_SAVE_FAILED", note: error.localizedDescription)
            }
        case .macroPhrase:
            let normalizedPhrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedPhrase.count >= 2 else {
                ensureCipherLexiconEntryController().update(model: makeCipherLexiconEntryModel(for: .macroPhrase))
                return
            }
            activeCipherLexiconEntryFlow = .macroSteps(phrase: normalizedPhrase)
            ensureCipherLexiconEntryController().clearInput()
            ensureCipherLexiconEntryController().update(model: makeCipherLexiconEntryModel(for: .macroSteps(phrase: normalizedPhrase)))
            logStatus(name: "CIPHER_LEXICON_ENTRY_STAGE", note: "captured macro phrase \(normalizedPhrase)")
        case .macroSteps(let phrase):
            let steps = parseCipherMacroSteps(from: text)
            guard !steps.isEmpty else {
                ensureCipherLexiconEntryController().update(model: makeCipherLexiconEntryModel(for: .macroSteps(phrase: phrase)))
                return
            }
            do {
                try companionConfigStore.saveMacro(phrase: phrase, steps: steps)
                logStatus(name: "CIPHER_LEXICON_SAVE", note: "saved macro \(phrase) => \(steps.joined(separator: ","))")
                displayPortalNotification(title: "Cipher Lexicon", body: "Saved macro for “\(phrase)”")
                closeCipherLexiconEntry(source: "macro-saved", reopenLexicon: true)
            } catch {
                loudFailure(name: "CIPHER_LEXICON_SAVE_FAILED", note: error.localizedDescription)
            }
        case .appMeaningPhrase:
            let normalizedPhrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedPhrase.count >= 2 else {
                ensureCipherLexiconEntryController().update(model: makeCipherLexiconEntryModel(for: .appMeaningPhrase))
                return
            }
            activeCipherLexiconEntryFlow = .appMeaningTarget(phrase: normalizedPhrase)
            ensureCipherLexiconEntryController().clearInput()
            ensureCipherLexiconEntryController().update(model: makeCipherLexiconEntryModel(for: .appMeaningTarget(phrase: normalizedPhrase)))
            logStatus(name: "CIPHER_LEXICON_ENTRY_STAGE", note: "captured app meaning phrase \(normalizedPhrase)")
        case .appMeaningTarget(let phrase):
            do {
                try companionConfigStore.saveAppMeaning(phrase: phrase, appName: text)
                logStatus(name: "CIPHER_LEXICON_SAVE", note: "saved app meaning \(phrase) => \(text)")
                displayPortalNotification(title: "Cipher Lexicon", body: "Taught “\(phrase)” to mean \(text)")
                closeCipherLexiconEntry(source: "app-meaning-saved", reopenLexicon: true)
            } catch {
                loudFailure(name: "CIPHER_LEXICON_SAVE_FAILED", note: error.localizedDescription)
            }
        case .correctionPhrase:
            let normalizedPhrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedPhrase.count >= 2 else {
                ensureCipherLexiconEntryController().update(model: makeCipherLexiconEntryModel(for: .correctionPhrase))
                return
            }
            activeCipherLexiconEntryFlow = .correctionReplacement(phrase: normalizedPhrase)
            ensureCipherLexiconEntryController().clearInput()
            ensureCipherLexiconEntryController().update(model: makeCipherLexiconEntryModel(for: .correctionReplacement(phrase: normalizedPhrase)))
            logStatus(name: "CIPHER_LEXICON_ENTRY_STAGE", note: "captured correction phrase \(normalizedPhrase)")
        case .correctionReplacement(let phrase):
            do {
                try companionConfigStore.saveCorrection(phrase: phrase, replacement: text)
                logStatus(name: "CIPHER_LEXICON_SAVE", note: "saved correction \(phrase) => \(text)")
                displayPortalNotification(title: "Cipher Lexicon", body: "Taught “\(phrase)” to rewrite first")
                closeCipherLexiconEntry(source: "correction-saved", reopenLexicon: true)
            } catch {
                loudFailure(name: "CIPHER_LEXICON_SAVE_FAILED", note: error.localizedDescription)
            }
        }
    }

    private func presentCipherSetup(flow: CipherSetupFlow, source: String) -> Bool {
        guard closeActiveCipherSetup() else {
            loudFailure(
                name: flow == .rekey ? "CIPHER_REKEY_OPEN_FAILED" : "CIPHER_SETUP_OPEN_FAILED",
                note: "could not replace the existing cipher setup overlay before opening a new one"
            )
            return false
        }

        let controller = CipherSetupController(
            mode: flow == .rekey ? .rekey : .initialSetup
        )
        cipherSetupController = controller
        activeCipherSetupFlow = flow
        cipherSequenceRecognizer.reset()
        clearHUDInteractionState()
        logStatus(
            name: "CIPHER_SETUP_INIT",
            note: "created \(flow == .rekey ? "rekey" : "initial") cipher setup controller"
        )

        let shown = controller.show()
        if shown {
            logStatus(
                name: flow == .rekey ? "CIPHER_REKEY_OPEN" : "CIPHER_SETUP_OPEN",
                note: "opened via \(source)"
            )
        } else {
            loudFailure(
                name: flow == .rekey ? "CIPHER_REKEY_OPEN_FAILED" : "CIPHER_SETUP_OPEN_FAILED",
                note: "\(source) requested cipher setup but the overlay did not become visible"
            )
        }
        return shown
    }

    @discardableResult
    private func closeActiveCipherSetup() -> Bool {
        guard let cipherSetupController else {
            activeCipherSetupFlow = nil
            return true
        }

        let closed = cipherSetupController.close()
        if closed {
            self.cipherSetupController = nil
            activeCipherSetupFlow = nil
        }
        return closed
    }

    @discardableResult
    private func presentPageOnboarding(_ model: OnboardingPageModel, source: String) -> Bool {
        if let existingController = pageOnboardingController,
           existingController.pageID == model.id {
            activeOnboardingPage = model
            let shown = existingController.show()
            if shown {
                logStatus(name: "ONBOARDING_OPEN", note: "reopened \(model.id.rawValue) onboarding via \(source)")
            }
            return shown
        }

        _ = pageOnboardingController?.close()
        let controller = PageOnboardingController(model: model)
        pageOnboardingController = controller
        activeOnboardingPage = model
        cipherSequenceRecognizer.reset()
        clearHUDInteractionState()
        let shown = controller.show()
        if shown {
            logStatus(name: "ONBOARDING_OPEN", note: "opened \(model.id.rawValue) onboarding via \(source)")
        } else {
            loudFailure(name: "ONBOARDING_OPEN_FAILED", note: "\(source) was recognized but the \(model.id.rawValue) onboarding overlay did not become visible")
        }
        return shown
    }

    private func finishActiveOnboarding(source: String) {
        guard let pageOnboardingController, let activeOnboardingPage else {
            return
        }

        if activeOnboardingPage.persistCompletion {
            do {
                try onboardingStateStore.markCompleted(activeOnboardingPage.id)
            } catch {
                loudFailure(name: "ONBOARDING_PERSIST_FAILED", note: "failed to persist \(activeOnboardingPage.id.rawValue) onboarding completion: \(error.localizedDescription)")
                return
            }
        }

        let closed = pageOnboardingController.close()
        if closed {
            let completedPageID = activeOnboardingPage.id
            clearHUDInteractionState()
            self.pageOnboardingController = nil
            self.activeOnboardingPage = nil
            logStatus(name: "ONBOARDING_COMPLETE", note: "closed \(completedPageID.rawValue) onboarding with \(source)")
            if completedPageID == .launcher, showCipherSetupIfNeeded(source: "post-launcher-onboarding") {
                return
            }
            continueAfterOnboarding()
        } else {
            loudFailure(name: "ONBOARDING_CLOSE_FAILED", note: "\(source) completed \(activeOnboardingPage.id.rawValue) onboarding but the overlay did not close")
        }
    }

    private func continueAfterOnboarding() {
        guard let pendingOnboardingAction else {
            return
        }
        self.pendingOnboardingAction = nil

        switch pendingOnboardingAction {
        case .confirmSelection(let item, let index):
            handleConfirmedSelection(item: item, index: index)
        }
    }

    private func openTimerCard(fromLauncherIndex index: Int, source: String) {
        launcherReturnIndexFromTimer = index
        guard let timerCoordinator else {
            loudFailure(name: "TIMER_INIT_FAILED", note: "timer coordinator was unavailable")
            return
        }

        let controller = ensureTimerCardController()
        cipherSequenceRecognizer.reset()
        let shown = controller.show(model: timerCoordinator.currentModel())
        if shown {
            recordLastVisibleSurface(.timer)
            logStatus(name: "TIMER_OPEN", note: "opened via \(source)")
        } else {
            loudFailure(name: "TIMER_OPEN_FAILED", note: "\(source) was recognized but the timer card did not become visible")
        }
    }

    private func closeTimerCard(source: String, reopenLauncher: Bool) {
        guard let timerCardController, timerCardController.isVisible else {
            return
        }

        cancelTimerAdjustmentRepeat()
        cancelTimerCompletionAlert()
        let closed = timerCardController.close()
        if closed {
            clearHUDInteractionState()
            logStatus(name: "TIMER_CLOSE", note: "closed via \(source)")
            if reopenLauncher {
                showMainHUD(source: "timer-return", selectedIndex: launcherReturnIndexFromTimer)
            }
        } else {
            loudFailure(name: "TIMER_CLOSE_FAILED", note: "\(source) requested close but the timer card still appears visible")
        }
    }

    private func openNowPlayingCard(fromLauncherIndex index: Int, source: String) {
        launcherReturnIndexFromNowPlaying = index
        guard let nowPlayingCoordinator else {
            loudFailure(name: "NOW_PLAYING_INIT_FAILED", note: "media coordinator was unavailable")
            return
        }

        nowPlayingCoordinator.requestImmediateRefresh()
        let controller = ensureNowPlayingCardController()
        cipherSequenceRecognizer.reset()
        let shown = controller.show(model: nowPlayingCoordinator.currentModel, selectedIndex: 0)
        if shown {
            recordLastVisibleSurface(.nowPlaying)
            logStatus(name: "NOW_PLAYING_OPEN", note: "opened via \(source) with source \(nowPlayingCoordinator.currentModel.snapshot.source.displayName)")
        } else {
            loudFailure(name: "NOW_PLAYING_OPEN_FAILED", note: "\(source) was recognized but the now-playing card did not become visible")
        }
    }

    private func openWorkQueueCard(fromLauncherIndex index: Int, source: String, selectedIndex: Int? = nil) {
        launcherReturnIndexFromWorkQueue = index
        guard let workQueueCoordinator else {
            loudFailure(name: "WORK_QUEUE_INIT_FAILED", note: "work queue coordinator was unavailable")
            return
        }

        let controller = ensureWorkQueueCardController()
        cipherSequenceRecognizer.reset()
        let model = workQueueCoordinator.listModel()
        let shown = controller.showList(model: model, selectedIndex: selectedIndex)
        if shown {
            if case .listRow(_, let currentIndex)? = controller.currentSelection() {
                recordLastVisibleSurface(.workQueue(selectedIndex: currentIndex))
            } else {
                recordLastVisibleSurface(.workQueue(selectedIndex: selectedIndex ?? 0))
            }
            logStatus(name: "WORK_QUEUE_OPEN", note: "opened via \(source)")
        } else {
            loudFailure(name: "WORK_QUEUE_OPEN_FAILED", note: "\(source) was recognized but the work queue did not become visible")
        }
    }

    private func showWorkQueueList(source: String, selectedItemID: String? = nil, selectedIndex: Int? = nil) {
        guard let workQueueCoordinator, let workQueueCardController else {
            loudFailure(name: "WORK_QUEUE_SHOW_FAILED", note: "\(source) requested the work queue list before it was initialized")
            return
        }

        let resolvedIndex = selectedItemID.flatMap { workQueueCoordinator.listSelectionIndex(for: $0) } ?? selectedIndex
        let model = workQueueCoordinator.listModel()
        let shown = workQueueCardController.showList(model: model, selectedIndex: resolvedIndex)
        if shown {
            if case .listRow(_, let currentIndex)? = workQueueCardController.currentSelection() {
                recordLastVisibleSurface(.workQueue(selectedIndex: currentIndex))
            }
            logStatus(name: "WORK_QUEUE_LIST", note: "showed the list via \(source)")
        } else {
            loudFailure(name: "WORK_QUEUE_LIST_FAILED", note: "\(source) requested the list but it did not become visible")
        }
    }

    private func showWorkQueueDetail(itemID: String, source: String, selectedIndex: Int? = 0) {
        guard let workQueueCoordinator else {
            loudFailure(name: "WORK_QUEUE_DETAIL_FAILED", note: "\(source) requested item detail but the coordinator was unavailable")
            return
        }
        guard let model = workQueueCoordinator.detailModel(for: itemID) else {
            loudFailure(name: "WORK_QUEUE_DETAIL_FAILED", note: "\(source) requested item detail for a missing checkpoint")
            return
        }

        let controller = ensureWorkQueueCardController()
        let shown = controller.showDetail(model: model, selectedIndex: selectedIndex)
        if shown {
            logStatus(name: "WORK_QUEUE_DETAIL", note: "opened detail for \(model.title) via \(source)")
        } else {
            loudFailure(name: "WORK_QUEUE_DETAIL_FAILED", note: "\(source) requested item detail but it did not become visible")
        }
    }

    private func showWorkQueueLabelPicker(itemID: String, source: String, selectedIndex: Int? = nil) {
        guard let workQueueCoordinator else {
            loudFailure(name: "WORK_QUEUE_LABEL_PICKER_FAILED", note: "\(source) requested label picker but the coordinator was unavailable")
            return
        }
        guard let model = workQueueCoordinator.labelPickerModel(for: itemID) else {
            loudFailure(name: "WORK_QUEUE_LABEL_PICKER_FAILED", note: "\(source) requested label picker for a missing checkpoint")
            return
        }

        let controller = ensureWorkQueueCardController()
        let shown = controller.showDetail(
            model: model,
            selectedIndex: selectedIndex ?? workQueueCoordinator.labelPickerSelectionIndex(for: itemID)
        )
        if shown {
            logStatus(name: "WORK_QUEUE_LABEL_PICKER", note: "opened label picker for \(model.title) via \(source)")
        } else {
            loudFailure(name: "WORK_QUEUE_LABEL_PICKER_FAILED", note: "\(source) requested label picker but it did not become visible")
        }
    }

    private func closeWorkQueueCard(source: String, reopenLauncher: Bool) {
        guard let workQueueCardController, workQueueCardController.isVisible else {
            return
        }

        let closed = workQueueCardController.close()
        if closed {
            clearHUDInteractionState()
            logStatus(name: "WORK_QUEUE_CLOSE", note: "closed via \(source)")
            if reopenLauncher {
                showMainHUD(source: "work-queue-return", selectedIndex: launcherReturnIndexFromWorkQueue)
            }
        } else {
            loudFailure(name: "WORK_QUEUE_CLOSE_FAILED", note: "\(source) requested close but the work queue still appears visible")
        }
    }

    private func closeNowPlayingCard(source: String, reopenLauncher: Bool) {
        guard let nowPlayingCardController, nowPlayingCardController.isVisible else {
            return
        }

        let closed = nowPlayingCardController.close()
        if closed {
            clearHUDInteractionState()
            logStatus(name: "NOW_PLAYING_CLOSE", note: "closed via \(source)")
            if reopenLauncher {
                showMainHUD(source: "now-playing-return", selectedIndex: launcherReturnIndexFromNowPlaying)
            }
        } else {
            loudFailure(name: "NOW_PLAYING_CLOSE_FAILED", note: "\(source) requested close but the now-playing card still appears visible")
        }
    }

    private func handleNowPlayingSelection(action: NowPlayingAction, index: Int) {
        if action.kind == .back {
            closeNowPlayingCard(source: "back-row", reopenLauncher: true)
            return
        }

        guard let nowPlayingCoordinator else {
            loudFailure(name: "NOW_PLAYING_ACTION_FAILED", note: "media coordinator was unavailable for \(action.kind.rawValue)")
            return
        }

        switch nowPlayingCoordinator.perform(action.kind) {
        case .success(let outcome):
            logStatus(name: "NOW_PLAYING_ACTION", note: outcome.logNote)
            if let notificationBody = outcome.notificationBody {
                displayPortalNotification(title: launcherDisplayName, body: notificationBody)
            }
            if let nowPlayingCardController, nowPlayingCardController.isVisible {
                nowPlayingCardController.update(model: nowPlayingCoordinator.currentModel, selectedIndex: index)
            }
        case .failure(let message):
            loudFailure(name: "NOW_PLAYING_ACTION_FAILED", note: message.localizedDescription)
        }
    }

    @discardableResult
    private func captureCheckpointToWorkQueue(source: String) -> WorkQueueCaptureOutcome? {
        guard let workQueueCoordinator else {
            loudFailure(name: "WORK_QUEUE_CAPTURE_FAILED", note: "work queue coordinator was unavailable")
            return nil
        }

        nowPlayingCoordinator?.requestImmediateRefresh()
        let nowPlayingSnapshot = nowPlayingCoordinator?.currentModel.snapshot
        let frontmostApp = workQueueCaptureAppContext()

        switch workQueueCoordinator.captureCurrentContext(frontmostApp: frontmostApp, nowPlayingSnapshot: nowPlayingSnapshot) {
        case .success(let outcome):
            logStatus(name: "WORK_QUEUE_CAPTURE", note: "\(outcome.logNote) via \(source)")
            displayPortalNotification(title: "Work Queue", body: outcome.notificationBody)
            if let workQueueCardController, workQueueCardController.isVisible {
                showWorkQueueList(source: "capture-refresh", selectedItemID: outcome.item.id)
            }
            return outcome
        case .failure(let error):
            loudFailure(name: "WORK_QUEUE_CAPTURE_FAILED", note: error.localizedDescription)
            return nil
        }
    }

    private func startTrackingFrontmostApplications() {
        updateLastNonLauncherAppContext(from: NSWorkspace.shared.frontmostApplication)
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                guard let self else { return }
                self.updateLastNonLauncherAppContext(from: app)
            }
        }
    }

    private func workQueueCaptureAppContext() -> WorkQueueAppContext? {
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           let context = makeWorkQueueAppContext(from: frontmostApplication) {
            return context
        }

        guard let lastNonLauncherAppContext else {
            return nil
        }

        return refreshedWorkQueueAppContext(from: lastNonLauncherAppContext)
    }

    private func updateLastNonLauncherAppContext(from application: NSRunningApplication?) {
        guard let application, let context = makeWorkQueueAppContext(from: application) else {
            return
        }

        lastNonLauncherAppContext = context
    }

    private func makeWorkQueueAppContext(from application: NSRunningApplication) -> WorkQueueAppContext? {
        let bundleIdentifier = application.bundleIdentifier
        let localizedName = application.localizedName

        if bundleIdentifier == launcherBundleIdentifier || localizedName == launcherDisplayName || localizedName == legacyLauncherDisplayName {
            return nil
        }

        let windowTitle = focusedWindowTitle(for: application)
        let semanticContext = appSemanticContext(for: application, fallbackWindowTitle: windowTitle)

        return WorkQueueAppContext(
            applicationName: localizedName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            semanticTitle: semanticContext?.semanticTitle,
            semanticDetail: semanticContext?.semanticDetail
        )
    }

    private func refreshedWorkQueueAppContext(from context: WorkQueueAppContext) -> WorkQueueAppContext {
        guard let bundleIdentifier = context.bundleIdentifier,
              let application = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return context
        }

        return WorkQueueAppContext(
            applicationName: context.applicationName ?? application.localizedName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: focusedWindowTitle(for: application) ?? context.windowTitle,
            semanticTitle: appSemanticContext(for: application, fallbackWindowTitle: context.windowTitle)?.semanticTitle ?? context.semanticTitle,
            semanticDetail: appSemanticContext(for: application, fallbackWindowTitle: context.windowTitle)?.semanticDetail ?? context.semanticDetail
        )
    }

    private func appSemanticContext(for application: NSRunningApplication, fallbackWindowTitle: String?) -> AppSemanticContext? {
        guard let bundleIdentifier = application.bundleIdentifier else {
            return nil
        }

        if let browser = browserTabSpecs().first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return browserSemanticContext(for: browser, fallbackWindowTitle: fallbackWindowTitle)
        }

        if bundleIdentifier == "com.apple.finder" {
            return finderSemanticContext()
        }

        return nil
    }

    private func browserSemanticContext(for browser: BrowserTabBrowserSpec, fallbackWindowTitle: String?) -> AppSemanticContext? {
        let delimiter = "<<<CTXSEP>>>"
        let currentTabLine = browser.bundleIdentifier == "com.apple.Safari"
            ? "set t to current tab of front window"
            : "set t to active tab of front window"

        let output = runAppleScript(lines: [
            "set outputDelimiter to \(appleScriptLiteral(delimiter))",
            "tell application \(appleScriptLiteral(browser.appName))",
            "if (count of windows) = 0 then return \"\"",
            "try",
            currentTabLine,
            "set tabTitle to \"\"",
            "set tabURL to \"\"",
            "try",
            "set tabTitle to \(browser.titleExpression)",
            "end try",
            "try",
            "set tabURL to \(browser.urlExpression)",
            "end try",
            "return tabTitle & outputDelimiter & tabURL",
            "on error",
            "return \"\"",
            "end try",
            "end tell"
        ])

        guard let output, !output.isEmpty else {
            return nil
        }

        let parts = output.components(separatedBy: delimiter)
        let rawTitle = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawURL = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let semanticTitle = CurrentThreadNamingEngine.cleanContextTitle(
            rawTitle,
            applicationName: browser.name,
            fallbackWindowTitle: fallbackWindowTitle
        )
        let semanticDetail = browserHost(from: rawURL)

        if semanticTitle == nil, semanticDetail == nil {
            return nil
        }

        return AppSemanticContext(semanticTitle: semanticTitle, semanticDetail: semanticDetail)
    }

    private func finderSemanticContext() -> AppSemanticContext? {
        let delimiter = "<<<CTXSEP>>>"
        let output = runAppleScript(lines: [
            "set outputDelimiter to \(appleScriptLiteral(delimiter))",
            "tell application \"Finder\"",
            "if (count of Finder windows) = 0 then return \"\"",
            "try",
            "set targetRef to target of front Finder window",
            "set targetName to name of targetRef",
            "set targetPath to POSIX path of (targetRef as alias)",
            "return targetName & outputDelimiter & targetPath",
            "on error",
            "return \"\"",
            "end try",
            "end tell"
        ])

        guard let output, !output.isEmpty else {
            return nil
        }

        let parts = output.components(separatedBy: delimiter)
        let semanticTitle = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let semanticDetail = parts.count > 1 ? shortenHomePath(parts[1]) : nil
        if (semanticTitle?.isEmpty ?? true) && (semanticDetail?.isEmpty ?? true) {
            return nil
        }
        return AppSemanticContext(semanticTitle: semanticTitle, semanticDetail: semanticDetail)
    }

    private func browserHost(from rawURL: String?) -> String? {
        guard let rawURL = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty,
              let url = URL(string: rawURL),
              var host = url.host,
              !host.isEmpty else {
            return nil
        }

        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
    }

    private func shortenHomePath(_ path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }

        let homePath = NSHomeDirectory()
        if path.hasPrefix(homePath) {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }

    private func focusedWindowTitle(for application: NSRunningApplication) -> String? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)

        for attribute in [kAXFocusedWindowAttribute as CFString, kAXMainWindowAttribute as CFString] {
            var windowValue: CFTypeRef?
            let windowResult = AXUIElementCopyAttributeValue(applicationElement, attribute, &windowValue)
            guard windowResult == .success, let windowValue else {
                continue
            }

            let windowElement = unsafeDowncast(windowValue, to: AXUIElement.self)
            var titleValue: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleValue)
            if titleResult == .success, let title = titleValue as? String {
                let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanedTitle.isEmpty {
                    return cleanedTitle
                }
            }
        }

        return nil
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

    private func openApplication(named applicationName: String) -> String? {
        let trimmedName = applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return nil
        }

        for candidateName in candidateApplicationNames(for: trimmedName) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", candidateName]

            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    continue
                }

                activateRunningApplication(named: candidateName)
                return candidateName
            } catch {
                continue
            }
        }

        return nil
    }

    private func candidateApplicationNames(for applicationName: String) -> [String] {
        let normalizedName = applicationName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedName.isEmpty else {
            return []
        }

        let aliases: [String: String] = [
            "chrome": "Google Chrome",
            "google chrome": "Google Chrome",
            "brave": "Brave Browser",
            "brave browser": "Brave Browser",
            "arc": "Arc",
            "safari": "Safari",
            "spotify": "Spotify",
            "messages": "Messages",
            "finder": "Finder",
            "figma": "Figma",
            "xcode": "Xcode",
            "cursor": "Cursor",
            "terminal": "Terminal",
            "notes": "Notes",
            "calculator": "Calculator"
        ]

        var candidates: [String] = []
        if let alias = aliases[normalizedName] {
            candidates.append(alias)
        }

        let runningMatches = NSWorkspace.shared.runningApplications
            .compactMap(\.localizedName)
            .filter { localizedName in
                let normalizedLocalizedName = localizedName.lowercased()
                return normalizedLocalizedName == normalizedName
                    || normalizedLocalizedName.contains(normalizedName)
                    || normalizedName.contains(normalizedLocalizedName)
            }
            .sorted { $0.count < $1.count }

        candidates.append(contentsOf: runningMatches)
        candidates.append(applicationName)

        var seen: Set<String> = []
        return candidates.filter { candidate in
            let normalizedCandidate = candidate.lowercased()
            if seen.contains(normalizedCandidate) {
                return false
            }
            seen.insert(normalizedCandidate)
            return true
        }
    }

    private func activateRunningApplication(named applicationName: String) {
        let normalizedName = applicationName.lowercased()
        guard let application = NSWorkspace.shared.runningApplications.first(where: { runningApplication in
            guard let localizedName = runningApplication.localizedName?.lowercased() else {
                return false
            }
            return localizedName == normalizedName || localizedName.contains(normalizedName) || normalizedName.contains(localizedName)
        }) else {
            return
        }

        application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private func openBrowserTab(matching query: String) -> String? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return nil
        }

        let queryTokens = matchingTokens(from: normalizedQuery)
        guard !queryTokens.isEmpty else {
            return nil
        }

        var browserSpecs = browserTabSpecs()
        if let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           let frontmostIndex = browserSpecs.firstIndex(where: { $0.bundleIdentifier == frontmostBundleIdentifier }) {
            let preferred = browserSpecs.remove(at: frontmostIndex)
            browserSpecs.insert(preferred, at: 0)
        }

        var bestMatch: (candidate: BrowserTabCandidate, browser: BrowserTabBrowserSpec, score: Double)?
        for browser in browserSpecs {
            guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == browser.bundleIdentifier }) else {
                continue
            }

            for candidate in fetchBrowserTabCandidates(for: browser) {
                let score = scoreBrowserTabCandidate(candidate, query: normalizedQuery, queryTokens: queryTokens)
                guard score > 0 else {
                    continue
                }

                if let currentBest = bestMatch {
                    if score > currentBest.score {
                        bestMatch = (candidate, browser, score)
                    }
                } else {
                    bestMatch = (candidate, browser, score)
                }
            }
        }

        guard let bestMatch, bestMatch.score >= 2.2 else {
            return nil
        }

        guard activateBrowserTab(candidate: bestMatch.candidate, browser: bestMatch.browser) else {
            return nil
        }

        let displayTitle = bestMatch.candidate.title.isEmpty ? bestMatch.candidate.url : bestMatch.candidate.title
        return bestMatch.browser.name + (displayTitle.isEmpty ? "" : " • \(displayTitle)")
    }

    private func openNewBrowserTab(for query: String) -> String? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty,
              let destinationURL = browserDestinationURL(for: normalizedQuery) else {
            return nil
        }

        if let browser = preferredBrowserForNewTab(),
           openURL(destinationURL, inApplicationNamed: browser.appName, bundleIdentifier: browser.bundleIdentifier) {
            return browser.name + " • " + browserDestinationLabel(for: normalizedQuery, url: destinationURL)
        }

        guard NSWorkspace.shared.open(destinationURL) else {
            return nil
        }

        return browserDestinationLabel(for: normalizedQuery, url: destinationURL)
    }

    private func preferredBrowserForNewTab() -> BrowserTabBrowserSpec? {
        var browserSpecs = browserTabSpecs()
        let preferredBrowser = companionConfigStore.semanticPreferences().preferredBrowser

        if let preferredAppName = preferredBrowser.appName,
           let preferredIndex = browserSpecs.firstIndex(where: { $0.appName == preferredAppName }) {
            let preferred = browserSpecs.remove(at: preferredIndex)
            browserSpecs.insert(preferred, at: 0)
        }

        if let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           let frontmostIndex = browserSpecs.firstIndex(where: { $0.bundleIdentifier == frontmostBundleIdentifier }) {
            let preferred = browserSpecs.remove(at: frontmostIndex)
            if preferredBrowser == .automatic {
                browserSpecs.insert(preferred, at: 0)
            } else {
                browserSpecs.append(preferred)
            }
        }

        return browserSpecs.first { browser in
            NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == browser.bundleIdentifier })
        }
    }

    private func openURL(_ url: URL, inApplicationNamed applicationName: String, bundleIdentifier: String? = nil) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", applicationName, url.absoluteString]

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return false
            }

            if let bundleIdentifier {
                activateRunningApplication(bundleIdentifier: bundleIdentifier)
            }
            return true
        } catch {
            return false
        }
    }

    private func activateRunningApplication(bundleIdentifier: String) {
        guard let application = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return
        }

        application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private func browserDestinationURL(for query: String) -> URL? {
        if let directURL = directBrowserDestinationURL(for: query) {
            return directURL
        }

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/search?q=\(encodedQuery)")
    }

    private func directBrowserDestinationURL(for query: String) -> URL? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmedQuery),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }

        if trimmedQuery.range(of: #"^[a-z0-9-]+(\.[a-z0-9-]+)+([/?#].*)?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return URL(string: "https://\(trimmedQuery)")
        }

        return nil
    }

    private func browserDestinationLabel(for query: String, url: URL) -> String {
        if directBrowserDestinationURL(for: query) != nil {
            return url.host ?? query
        }

        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedQuery.isEmpty ? "Search" : "Search \(cleanedQuery)"
    }

    private struct BrowserTabBrowserSpec {
        let name: String
        let appName: String
        let bundleIdentifier: String
        let titleExpression: String
        let urlExpression: String
        let activateLines: (_ windowIndex: Int, _ tabIndex: Int) -> [String]
        let newTabLines: (_ destinationURL: String) -> [String]
    }

    private struct BrowserTabCandidate {
        let windowIndex: Int
        let tabIndex: Int
        let title: String
        let url: String
    }

    private func browserTabSpecs() -> [BrowserTabBrowserSpec] {
        [
            BrowserTabBrowserSpec(
                name: "Arc",
                appName: "Arc",
                bundleIdentifier: "company.thebrowser.Browser",
                titleExpression: "title of t",
                urlExpression: "URL of t",
                activateLines: { windowIndex, tabIndex in
                    [
                        "tell application \"Arc\"",
                        "set w to window \(windowIndex)",
                        "set active tab index of w to \(tabIndex)",
                        "set index of w to 1",
                        "activate",
                        "end tell"
                    ]
                },
                newTabLines: { destinationURL in
                    [
                        "tell application \"Arc\"",
                        "activate",
                        "if (count of windows) = 0 then",
                        "make new window",
                        "end if",
                        "tell front window",
                        "set newTab to make new tab with properties {URL:\(appleScriptLiteral(destinationURL))}",
                        "set active tab index to (index of newTab)",
                        "end tell",
                        "end tell"
                    ]
                }
            ),
            BrowserTabBrowserSpec(
                name: "Google Chrome",
                appName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                titleExpression: "title of t",
                urlExpression: "URL of t",
                activateLines: { windowIndex, tabIndex in
                    [
                        "tell application \"Google Chrome\"",
                        "set w to window \(windowIndex)",
                        "set active tab index of w to \(tabIndex)",
                        "set index of w to 1",
                        "activate",
                        "end tell"
                    ]
                },
                newTabLines: { destinationURL in
                    [
                        "tell application \"Google Chrome\"",
                        "activate",
                        "if (count of windows) = 0 then",
                        "make new window",
                        "end if",
                        "tell front window",
                        "set newTab to make new tab with properties {URL:\(appleScriptLiteral(destinationURL))}",
                        "set active tab index to (index of newTab)",
                        "end tell",
                        "end tell"
                    ]
                }
            ),
            BrowserTabBrowserSpec(
                name: "Safari",
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                titleExpression: "name of t",
                urlExpression: "URL of t",
                activateLines: { windowIndex, tabIndex in
                    [
                        "tell application \"Safari\"",
                        "set w to window \(windowIndex)",
                        "set current tab of w to tab \(tabIndex) of w",
                        "set index of w to 1",
                        "activate",
                        "end tell"
                    ]
                },
                newTabLines: { destinationURL in
                    [
                        "tell application \"Safari\"",
                        "activate",
                        "if (count of windows) = 0 then",
                        "make new document",
                        "end if",
                        "tell front window",
                        "set newTab to make new tab with properties {URL:\(appleScriptLiteral(destinationURL))}",
                        "set current tab to newTab",
                        "end tell",
                        "end tell"
                    ]
                }
            ),
            BrowserTabBrowserSpec(
                name: "Brave Browser",
                appName: "Brave Browser",
                bundleIdentifier: "com.brave.Browser",
                titleExpression: "title of t",
                urlExpression: "URL of t",
                activateLines: { windowIndex, tabIndex in
                    [
                        "tell application \"Brave Browser\"",
                        "set w to window \(windowIndex)",
                        "set active tab index of w to \(tabIndex)",
                        "set index of w to 1",
                        "activate",
                        "end tell"
                    ]
                },
                newTabLines: { destinationURL in
                    [
                        "tell application \"Brave Browser\"",
                        "activate",
                        "if (count of windows) = 0 then",
                        "make new window",
                        "end if",
                        "tell front window",
                        "set newTab to make new tab with properties {URL:\(appleScriptLiteral(destinationURL))}",
                        "set active tab index to (index of newTab)",
                        "end tell",
                        "end tell"
                    ]
                }
            )
        ]
    }

    private func fetchBrowserTabCandidates(for browser: BrowserTabBrowserSpec) -> [BrowserTabCandidate] {
        let delimiter = "<<<TABSEP>>>"
        let output = runAppleScript(lines: [
            "set outputRows to {}",
            "tell application \(appleScriptLiteral(browser.appName))",
            "repeat with w in windows",
            "repeat with t in tabs of w",
            "set tabTitle to \"\"",
            "set tabURL to \"\"",
            "try",
            "set tabTitle to \(browser.titleExpression)",
            "end try",
            "try",
            "set tabURL to \(browser.urlExpression)",
            "end try",
            "set end of outputRows to ((index of w as string) & \(appleScriptLiteral(delimiter)) & (index of t as string) & \(appleScriptLiteral(delimiter)) & tabTitle & \(appleScriptLiteral(delimiter)) & tabURL)",
            "end repeat",
            "end repeat",
            "set AppleScript's text item delimiters to linefeed",
            "return outputRows as string",
            "end tell"
        ])

        guard let output, !output.isEmpty else {
            return []
        }

        return output
            .split(separator: "\n")
            .compactMap { line -> BrowserTabCandidate? in
                let parts = line.components(separatedBy: delimiter)
                guard parts.count >= 4,
                      let windowIndex = Int(parts[0]),
                      let tabIndex = Int(parts[1]) else {
                    return nil
                }

                return BrowserTabCandidate(
                    windowIndex: windowIndex,
                    tabIndex: tabIndex,
                    title: parts[2].trimmingCharacters(in: .whitespacesAndNewlines),
                    url: parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
    }

    private func activateBrowserTab(candidate: BrowserTabCandidate, browser: BrowserTabBrowserSpec) -> Bool {
        runAppleScript(lines: browser.activateLines(candidate.windowIndex, candidate.tabIndex)) != nil
    }

    private func scoreBrowserTabCandidate(_ candidate: BrowserTabCandidate, query: String, queryTokens: [String]) -> Double {
        let normalizedTitle = normalizedMatchingText(candidate.title)
        let normalizedURL = normalizedMatchingText(candidate.url)
        let combined = normalizedMatchingText(candidate.title + " " + candidate.url)
        let semanticTitle = semanticMatchingText(candidate.title)
        let semanticURL = semanticMatchingText(candidate.url)
        let semanticQuery = semanticMatchingText(query)

        var score = 0.0
        if combined.contains(normalizedMatchingText(query)) {
            score += 3.5
        }

        var matchedTokens = 0
        for token in queryTokens {
            if normalizedTitle.contains(token) {
                score += 1.8
                matchedTokens += 1
            } else if normalizedURL.contains(token) {
                score += 1.1
                matchedTokens += 1
            }
        }

        if matchedTokens == queryTokens.count {
            score += 1.4
        }

        if queryTokens.count > 1 && matchedTokens == 0 {
            score -= 0.45
        }

        if let browserSemanticEmbedding, !semanticQuery.isEmpty {
            let titleDistance = browserSemanticEmbedding.distance(between: semanticQuery, and: semanticTitle, distanceType: .cosine)
            let urlDistance = browserSemanticEmbedding.distance(between: semanticQuery, and: semanticURL, distanceType: .cosine)
            let titleScore = max(0, 1.0 - (titleDistance / 2.0))
            let urlScore = max(0, 1.0 - (urlDistance / 2.0))
            score += max(titleScore, urlScore) * 1.15
        }

        return score
    }

    private func matchingTokens(from query: String) -> [String] {
        let stopWords: Set<String> = ["a", "an", "the", "to", "for", "me", "my", "please", "that", "this", "up"]
        return normalizedMatchingText(query)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
    }

    private func semanticMatchingText(_ text: String) -> String {
        let stopWords: Set<String> = ["a", "an", "the", "to", "for", "me", "my", "please", "that", "this", "up"]
        let normalized = normalizedMatchingText(text)
        let tokens = normalized.split(separator: " ").map(String.init).filter { !stopWords.contains($0) }
        if tokens.isEmpty {
            return normalized
        }
        return tokens.joined(separator: " ")
    }

    private func normalizedMatchingText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runAppleScript(lines: [String]) -> String? {
        let stdout = Pipe()
        let stderr = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")

        var arguments: [String] = []
        for line in lines {
            arguments.append("-e")
            arguments.append(line)
        }
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let rawOutput = String(data: data, encoding: .utf8) else {
            return ""
        }
        return rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleWorkQueueSelection(_ selection: WorkQueueSelection) {
        switch selection {
        case .listRow(let row, let index):
            switch row.kind {
            case .item(let itemID):
                showWorkQueueDetail(itemID: itemID, source: "work-queue-selection", selectedIndex: 0)
                recordLastVisibleSurface(.workQueue(selectedIndex: index))
            case .captureCurrentContext:
                captureCheckpointToWorkQueue(source: "work-queue-capture-row")
            case .back:
                closeWorkQueueCard(source: "back-row", reopenLauncher: true)
            }
        case .detailAction(let action, _):
            guard let workQueueCardController, let itemID = workQueueCardController.currentDetailItemID else {
                loudFailure(name: "WORK_QUEUE_ACTION_FAILED", note: "detail action fired without an active item detail model")
                return
            }

            switch action.kind {
            case .editLabel:
                showWorkQueueLabelPicker(itemID: itemID, source: "work-queue-label-action")
                return
            case .backToActions:
                showWorkQueueDetail(itemID: itemID, source: "work-queue-label-back", selectedIndex: 1)
                return
            default:
                break
            }

            switch workQueueCoordinator?.perform(action.kind, itemID: itemID) {
            case .success(let outcome):
                logStatus(name: "WORK_QUEUE_ACTION", note: outcome.logNote)
                if let notificationBody = outcome.notificationBody {
                    displayPortalNotification(title: "Work Queue", body: notificationBody)
                }
                if outcome.closeQueueToHidden {
                    closeWorkQueueCard(source: action.kind.rawValue, reopenLauncher: false)
                } else if action.kind.isLabelMutation {
                    showWorkQueueDetail(itemID: itemID, source: action.kind.rawValue, selectedIndex: 1)
                } else {
                    showWorkQueueList(source: action.kind.rawValue, selectedItemID: outcome.reopenListSelectionItemID)
                }
            case .failure(let error):
                loudFailure(name: "WORK_QUEUE_ACTION_FAILED", note: error.localizedDescription)
            case .none:
                loudFailure(name: "WORK_QUEUE_ACTION_FAILED", note: "work queue coordinator was unavailable for \(action.kind.rawValue)")
            }
        }
    }

    private func handleWorkQueueQuickRemove() {
        guard let workQueueCardController else {
            loudFailure(name: "WORK_QUEUE_REMOVE_FAILED", note: "work queue remove gesture fired before the queue controller was available")
            return
        }

        guard let selection = workQueueCardController.currentSelection() else {
            loudFailure(name: "WORK_QUEUE_REMOVE_FAILED", note: "work queue remove gesture fired without an active selection")
            return
        }

        guard case .listRow(let row, let index) = selection else {
            logStatus(name: "WORK_QUEUE_IGNORED_GESTURE", note: "ignored center_double while work queue detail was visible")
            return
        }

        guard case .item(let itemID) = row.kind else {
            logStatus(name: "WORK_QUEUE_IGNORED_GESTURE", note: "ignored center_double on non-item queue row \(row.title)")
            return
        }

        switch workQueueCoordinator?.perform(.archive, itemID: itemID) {
        case .success(let outcome):
            logStatus(name: "WORK_QUEUE_ACTION", note: "\(outcome.logNote) via center_double quick-remove")
            if let notificationBody = outcome.notificationBody {
                displayPortalNotification(title: "Work Queue", body: notificationBody)
            }
            showWorkQueueList(source: "center_double-archive", selectedIndex: index)
        case .failure(let error):
            loudFailure(name: "WORK_QUEUE_REMOVE_FAILED", note: error.localizedDescription)
        case .none:
            loudFailure(name: "WORK_QUEUE_REMOVE_FAILED", note: "work queue coordinator was unavailable for quick remove")
        }
    }

    private func openCipherCard(source: String, selectedIndex: Int? = nil) {
        cipherUnlockOpenTask?.cancel()
        cipherUnlockOpenTask = nil
        cipherUnlockFeedbackController?.close()
        let controller = ensureCipherCardController()
        cipherSequenceRecognizer.reset()
        let shown = controller.show(model: makeCipherCardModel(), selectedIndex: selectedIndex)
        if shown {
            clearHUDInteractionState()
            logStatus(name: "CIPHER_OPEN", note: "opened via \(source)")
        } else {
            loudFailure(name: "CIPHER_OPEN_FAILED", note: "\(source) was recognized but the cipher card did not become visible")
        }
    }

    private func closeCipherCard(source: String) {
        guard let cipherCardController, cipherCardController.isVisible else {
            return
        }

        let closed = cipherCardController.close()
        if closed {
            clearHUDInteractionState()
            logStatus(name: "CIPHER_CLOSE", note: "closed via \(source)")
        } else {
            loudFailure(name: "CIPHER_CLOSE_FAILED", note: "\(source) requested close but the cipher card still appears visible")
        }
    }

    private func handleCipherSelection(spell: CipherSpell, index: Int) {
        switch spell.kind {
        case .veil:
            portalRuntimeState.isVeiled.toggle()
            logStatus(name: "CIPHER_VEIL_TOGGLE", note: "veil is now \(portalRuntimeState.isVeiled ? "on" : "off")")
            cipherCardController?.update(model: makeCipherCardModel(), selectedIndex: index)
        case .echo:
            guard let lastVisibleSurface = portalRuntimeState.lastVisibleSurface else {
                logStatus(name: "CIPHER_ECHO_SKIPPED", note: "echo was selected without a cached surface")
                cipherCardController?.update(model: makeCipherCardModel(), selectedIndex: index)
                return
            }

            logStatus(name: "CIPHER_ECHO_TARGET", note: "echo selected \(lastVisibleSurface.displayName)")
            closeCipherCard(source: "echo")
            switch lastVisibleSurface {
            case .launcher(let selectedIndex):
                showMainHUD(source: "cipher-echo", selectedIndex: selectedIndex)
            case .currentThread:
                openCurrentThreadCard(fromLauncherIndex: launcherIndex(forItemID: LauncherItem.currentThreadItem.id) ?? 0, source: "cipher-echo")
            case .timer:
                openTimerCard(fromLauncherIndex: launcherIndex(forItemID: "timer") ?? 0, source: "cipher-echo")
            case .nowPlaying:
                openNowPlayingCard(fromLauncherIndex: launcherIndex(forItemID: "now-playing") ?? 0, source: "cipher-echo")
            case .workQueue(let selectedIndex):
                openWorkQueueCard(fromLauncherIndex: launcherIndex(forItemID: "work-queue") ?? 0, source: "cipher-echo", selectedIndex: selectedIndex)
            case .workSpell(let selectedIndex):
                openWorkSpellCard(source: "cipher-echo", selectedIndex: selectedIndex)
            }
        case .seal:
            portalRuntimeState.isSealed.toggle()
            logStatus(name: "CIPHER_SEAL_TOGGLE", note: "seal is now \(portalRuntimeState.isSealed ? "on" : "off")")
            cipherCardController?.update(model: makeCipherCardModel(), selectedIndex: index)
        case .lexicon:
            logStatus(name: "CIPHER_SPELL", note: "selected Lexicon")
            closeCipherCard(source: "lexicon")
            openCipherLexiconCard(source: "cipher-lexicon")
        case .spellbook:
            logStatus(name: "CIPHER_SPELL", note: "selected Spellbook")
            closeCipherCard(source: "spellbook")
            openWorkSpellSettingsCard(source: "cipher-spellbook")
        case .rekey:
            logStatus(name: "CIPHER_SPELL", note: "selected Rekey")
            closeCipherCard(source: "rekey")
            _ = presentCipherSetup(flow: .rekey, source: "cipher-rekey")
        case .back:
            logStatus(name: "CIPHER_SPELL", note: "selected Back")
            closeCipherCard(source: "back-row")
        }
    }

    private func presentCipherUnlockReveal() {
        cipherUnlockOpenTask?.cancel()
        clearHUDInteractionState()

        let controller = ensureCipherUnlockFeedbackController()
        let shown = controller.pulse()
        if shown {
            logStatus(name: "CIPHER_REVEAL", note: "showed cipher unlock feedback pulse")
        } else {
            loudFailure(name: "CIPHER_REVEAL_FAILED", note: "cipher unlock pulse failed to become visible")
        }

        logStatus(name: "CIPHER_REVEAL_SCHEDULED", note: "scheduled cipher card open after unlock pulse")

        cipherUnlockOpenTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 430_000_000)
            guard !Task.isCancelled else {
                await MainActor.run {
                    self?.logStatus(name: "CIPHER_REVEAL_CANCELLED", note: "canceled cipher card open before handoff")
                }
                return
            }

            await MainActor.run {
                guard let self else { return }
                self.logStatus(name: "CIPHER_REVEAL_HANDOFF", note: "opening cipher card after unlock pulse")
                self.openCipherCard(source: "hidden-sequence")
            }
        }
    }

    private func handleHiddenCipherGesture(_ event: GestureEvent) -> Bool {
        guard isPortalFullyHidden else {
            return false
        }

        if shouldSuppressGesture(event.gesture) {
            logStatus(name: "CIPHER_HIDDEN_SUPPRESSED_GESTURE", note: "suppressed delayed \(event.gesture.rawValue) after hidden raw handling")
            return true
        }

        return handleHiddenCipherOutcome(
            cipherSequenceRecognizer.consume(event.gesture),
            trigger: event.gesture.rawValue
        )
    }

    private var isPortalFullyHidden: Bool {
        hudController?.isVisible != true &&
        currentThreadCardController?.isVisible != true &&
        timerCardController?.isVisible != true &&
        nowPlayingCardController?.isVisible != true &&
        workQueueCardController?.isVisible != true &&
        cipherUnlockFeedbackController?.isVisible != true &&
        cipherCardController?.isVisible != true &&
        cipherLexiconCardController?.isVisible != true &&
        cipherLexiconEntryController?.isVisible != true &&
        cipherSetupController?.isVisible != true &&
        pageOnboardingController?.isVisible != true
    }

    private func makeCipherCardModel() -> CipherCardModel {
        CipherCardModel.make(from: portalRuntimeState)
    }

    private func makeCipherLexiconModel() -> CipherLexiconCardModel {
        let ritualFamilies = companionConfigStore.ritualPhraseFamilies()
        let appMeanings = companionConfigStore.appMeaningOverrides()
        let intentMeanings = companionConfigStore.intentMeaningEntries()
        let macros = companionConfigStore.macroEntries()
        let corrections = companionConfigStore.correctionEntries()
        let semanticPreferences = companionConfigStore.semanticPreferences()
        let ritualCount = ritualFamilies.reduce(0) { $0 + $1.value.count }
        let familyCount = ritualFamilies.count
        let meaningCount = appMeanings.count
        let metadataText = "\(ritualCount) ritual phrases • \(intentMeanings.count) intent meanings • \(macros.count) macros"

        let ritualRows: [CipherLexiconRow] = CompanionRitualTarget.allCases.map { target in
            let family = ritualFamilies[target] ?? []
            return CipherLexiconRow(
                kind: .ritual(target),
                title: target.title,
                detail: family.isEmpty
                    ? target.helperDetail
                    : "Family of \(family.count). Primary: “\(family[0])”",
                symbol: target.symbol,
                isEnabled: true,
                style: .primary,
                sectionTitle: target == CompanionRitualTarget.allCases.first ? "RITUALS" : nil
            )
        }

        let intentRows: [CipherLexiconRow] = [
            CipherLexiconRow(
                kind: .intentMeaning,
                title: "Teach Intent Meaning",
                detail: intentMeanings.isEmpty
                    ? "Teach a phrase like “lock in” to mean a portal action."
                    : "Teach another action meaning. Current count: \(intentMeanings.count).",
                symbol: "bolt.badge.automatic",
                isEnabled: true,
                style: .primary,
                sectionTitle: "INTENTS"
            )
        ] + intentMeanings.map { entry in
            CipherLexiconRow(
                kind: .savedIntentMeaning(entry.phrase),
                title: "“\(entry.phrase)”",
                detail: "Means \(entry.target.title). Tap to retarget it.",
                symbol: "bolt.badge.automatic",
                isEnabled: true,
                style: .primary,
                sectionTitle: nil
            )
        }

        let macroRows: [CipherLexiconRow] = [
            CipherLexiconRow(
                kind: .macro,
                title: "Teach Macro",
                detail: macros.isEmpty
                    ? "Teach a phrase that runs multiple portal steps."
                    : "Teach another macro. Current count: \(macros.count).",
                symbol: "wand.and.stars",
                isEnabled: true,
                style: .primary,
                sectionTitle: "MACROS"
            )
        ] + macros.map { entry in
            CipherLexiconRow(
                kind: .savedMacro(entry.phrase),
                title: "“\(entry.phrase)”",
                detail: "Runs \(describeMacroSteps(entry.steps)). Tap to retarget it.",
                symbol: "wand.and.stars",
                isEnabled: true,
                style: .primary,
                sectionTitle: nil
            )
        }

        let meaningRows: [CipherLexiconRow] = [
            CipherLexiconRow(
                kind: .appMeaning,
                title: "Teach App Meaning",
                detail: meaningCount == 0
                    ? "Teach a noun like “canvas” to mean a specific app."
                    : "Teach another noun-to-app meaning. Current count: \(meaningCount).",
                symbol: "square.text.square",
                isEnabled: true,
                style: .primary,
                sectionTitle: "MEANINGS"
            )
        ] + appMeanings.keys.sorted().compactMap { phrase in
            guard let appName = appMeanings[phrase] else {
                return nil
            }
            return CipherLexiconRow(
                kind: .savedAppMeaning(phrase),
                title: "“\(phrase)”",
                detail: "Means \(appName). Tap to retarget it.",
                symbol: "app.badge",
                isEnabled: true,
                style: .primary,
                sectionTitle: nil
            )
        }

        let correctionRows: [CipherLexiconRow] = [
            CipherLexiconRow(
                kind: .correction,
                title: "Teach Correction",
                detail: corrections.isEmpty
                    ? "Teach Companion how to rewrite a phrase before it interprets it."
                    : "Teach another correction. Current count: \(corrections.count).",
                symbol: "arrow.left.arrow.right.circle",
                isEnabled: true,
                style: .primary,
                sectionTitle: "CORRECTIONS"
            )
        ] + corrections.map { correction in
            CipherLexiconRow(
                kind: .savedCorrection(correction.phrase),
                title: "“\(correction.phrase)”",
                detail: "Rewrites to “\(correction.replacement)”. Tap to retarget it.",
                symbol: "arrow.left.arrow.right.circle",
                isEnabled: true,
                style: .primary,
                sectionTitle: nil
            )
        }

        let preferenceRows = [
            CipherLexiconRow(
                kind: .semanticOpenBias,
                title: "Ambiguous Opens",
                detail: semanticPreferences.openBias.title + ". Tap to cycle app vs search bias.",
                symbol: "dial.medium",
                isEnabled: true,
                style: .primary,
                sectionTitle: "PREFERENCES"
            ),
            CipherLexiconRow(
                kind: .semanticPreferredBrowser,
                title: "Preferred Browser",
                detail: semanticPreferences.preferredBrowser.title + ". Tap to cycle browser target for searches.",
                symbol: "safari",
                isEnabled: true,
                style: .primary,
                sectionTitle: nil
            )
        ]

        let utilityRows = [
            CipherLexiconRow(
                kind: .resetRituals,
                title: "Reset Rituals",
                detail: familyCount == 0 ? "No ritual phrases saved yet." : "Clear all private ritual phrase families.",
                symbol: "arrow.counterclockwise.circle",
                isEnabled: ritualCount > 0,
                style: .utility,
                sectionTitle: "UTILITIES"
            ),
            CipherLexiconRow(
                kind: .resetIntentMeanings,
                title: "Reset Intent Meanings",
                detail: intentMeanings.isEmpty ? "No intent meanings saved yet." : "Clear all personal intent meanings.",
                symbol: "arrow.counterclockwise.circle",
                isEnabled: !intentMeanings.isEmpty,
                style: .utility,
                sectionTitle: nil
            ),
            CipherLexiconRow(
                kind: .resetMacros,
                title: "Reset Macros",
                detail: macros.isEmpty ? "No macros saved yet." : "Clear all taught macros.",
                symbol: "wand.and.rays.inverse",
                isEnabled: !macros.isEmpty,
                style: .utility,
                sectionTitle: nil
            ),
            CipherLexiconRow(
                kind: .resetMeanings,
                title: "Reset Meanings",
                detail: meaningCount == 0 ? "No app meanings saved yet." : "Clear all personal app meanings.",
                symbol: "eraser",
                isEnabled: meaningCount > 0,
                style: .utility,
                sectionTitle: nil
            ),
            CipherLexiconRow(
                kind: .resetCorrections,
                title: "Reset Corrections",
                detail: corrections.isEmpty ? "No corrections saved yet." : "Clear all transcript corrections.",
                symbol: "arrow.uturn.backward.circle",
                isEnabled: !corrections.isEmpty,
                style: .utility,
                sectionTitle: nil
            ),
            CipherLexiconRow(
                kind: .back,
                title: "Back",
                detail: "Return to Cipher.",
                symbol: "chevron.backward",
                isEnabled: true,
                style: .utility,
                sectionTitle: nil
            )
        ]

        let rows = ritualRows
            + intentRows
            + macroRows
            + meaningRows
            + correctionRows
            + preferenceRows
            + utilityRows

        return CipherLexiconCardModel(
            title: "Cipher Lexicon",
            subtitle: "Teach Companion rituals, meanings, macros, corrections, and semantic preferences.",
            metadataText: metadataText,
            footer: "Use + and - to move, tap center to teach or retarget, and hold center to return to Cipher.",
            rows: rows
        )
    }

    private func makeCipherLexiconEntryModel(for flow: CipherLexiconEntryFlow) -> CipherLexiconEntryModel {
        switch flow {
        case .ritual(let target):
            return CipherLexiconEntryModel(
                title: target.title,
                subtitle: "Type another phrase for this ritual family.",
                helperText: target.helperDetail + " You can teach multiple phrases for the same ritual.",
                placeholder: "Type a private phrase and press Return",
                footer: "Return saves it. Hold center cancels and returns to the Lexicon.",
                symbol: target.symbol
            )
        case .intentMeaningPhrase:
            return CipherLexiconEntryModel(
                title: "Teach Intent Meaning",
                subtitle: "Type the phrase Companion should reinterpret semantically.",
                helperText: "Example: “lock in”, “show my work”, or “save that”.",
                placeholder: "Type a phrase and press Return",
                footer: "Return moves to the meaning step. Hold center cancels.",
                symbol: "bolt.badge.automatic"
            )
        case .intentMeaningTarget(let phrase):
            return CipherLexiconEntryModel(
                title: "Teach Intent Meaning",
                subtitle: "Now type what “\(phrase)” should mean.",
                helperText: "Examples: continue, queue, capture, current thread, timer, now playing, playback.",
                placeholder: "Type a meaning target and press Return",
                footer: "Return saves it. Hold center cancels.",
                symbol: "bolt.badge.automatic"
            )
        case .macroPhrase:
            return CipherLexiconEntryModel(
                title: "Teach Macro",
                subtitle: "Type the phrase that should trigger a multi-step macro.",
                helperText: "Example: “focus sprint” or “queue sweep”.",
                placeholder: "Type a macro phrase and press Return",
                footer: "Return moves to the macro steps. Hold center cancels.",
                symbol: "wand.and.stars"
            )
        case .macroSteps(let phrase):
            return CipherLexiconEntryModel(
                title: "Teach Macro",
                subtitle: "Now type the steps for “\(phrase)”.",
                helperText: "Use comma-separated steps like timer:25, current thread or capture, work queue.",
                placeholder: "Type steps and press Return",
                footer: "Supported steps: continue, capture, current thread, work queue, timer, timer:25, now playing, playback.",
                symbol: "wand.and.stars"
            )
        case .appMeaningPhrase:
            return CipherLexiconEntryModel(
                title: "Teach App Meaning",
                subtitle: "Type the word or phrase you want Companion to reinterpret.",
                helperText: "Example: type “canvas” if you want that to mean Canva.",
                placeholder: "Type a word or phrase and press Return",
                footer: "Return moves to the app step. Hold center cancels.",
                symbol: "square.text.square"
            )
        case .appMeaningTarget(let phrase):
            return CipherLexiconEntryModel(
                title: "Teach App Meaning",
                subtitle: "Now type the app that “\(phrase)” should open.",
                helperText: "Example: Canva, Figma, Chrome, Messages.",
                placeholder: "Type an app name and press Return",
                footer: "Return saves it. Hold center cancels.",
                symbol: "app.badge"
            )
        case .correctionPhrase:
            return CipherLexiconEntryModel(
                title: "Teach Correction",
                subtitle: "Type the phrase you want Companion to rewrite.",
                helperText: "Example: “canvas” if you want to rewrite it before parsing.",
                placeholder: "Type a phrase and press Return",
                footer: "Return moves to the correction target. Hold center cancels.",
                symbol: "arrow.left.arrow.right.circle"
            )
        case .correctionReplacement(let phrase):
            return CipherLexiconEntryModel(
                title: "Teach Correction",
                subtitle: "Now type what “\(phrase)” should become first.",
                helperText: "Example: Canva, open work queue, or figma docs.",
                placeholder: "Type the replacement phrase and press Return",
                footer: "Return saves it. Hold center cancels.",
                symbol: "arrow.left.arrow.right.circle"
            )
        }
    }

    private func cipherLexiconRowIndex(for flow: CipherLexiconEntryFlow?) -> Int? {
        guard let flow else {
            return nil
        }

        let rows = makeCipherLexiconModel().rows
        switch flow {
        case .ritual(let target):
            return rows.firstIndex { $0.kind == .ritual(target) }
        case .intentMeaningPhrase:
            return rows.firstIndex { $0.kind == .intentMeaning }
        case .intentMeaningTarget(let phrase):
            return rows.firstIndex {
                if case .savedIntentMeaning(let candidatePhrase) = $0.kind {
                    return candidatePhrase == phrase
                }
                return false
            } ?? rows.firstIndex { $0.kind == .intentMeaning }
        case .macroPhrase:
            return rows.firstIndex { $0.kind == .macro }
        case .macroSteps(let phrase):
            return rows.firstIndex {
                if case .savedMacro(let candidatePhrase) = $0.kind {
                    return candidatePhrase == phrase
                }
                return false
            } ?? rows.firstIndex { $0.kind == .macro }
        case .appMeaningPhrase:
            return rows.firstIndex { $0.kind == .appMeaning }
        case .appMeaningTarget(let phrase):
            return rows.firstIndex {
                if case .savedAppMeaning(let candidatePhrase) = $0.kind {
                    return candidatePhrase == phrase
                }
                return false
            } ?? rows.firstIndex { $0.kind == .appMeaning }
        case .correctionPhrase:
            return rows.firstIndex { $0.kind == .correction }
        case .correctionReplacement(let phrase):
            return rows.firstIndex {
                if case .savedCorrection(let candidatePhrase) = $0.kind {
                    return candidatePhrase == phrase
                }
                return false
            } ?? rows.firstIndex { $0.kind == .correction }
        }
    }

    private func cipherLexiconEntryDescription(_ flow: CipherLexiconEntryFlow) -> String {
        switch flow {
        case .ritual(let target):
            return target.rawValue
        case .intentMeaningPhrase:
            return "intent-meaning-phrase"
        case .intentMeaningTarget:
            return "intent-meaning-target"
        case .macroPhrase:
            return "macro-phrase"
        case .macroSteps:
            return "macro-steps"
        case .appMeaningPhrase:
            return "app-meaning-phrase"
        case .appMeaningTarget:
            return "app-meaning-target"
        case .correctionPhrase:
            return "correction-phrase"
        case .correctionReplacement:
            return "correction-replacement"
        }
    }

    private func describeMacroSteps(_ steps: [String]) -> String {
        steps.map { step in
            let lowered = step.lowercased()
            if lowered.hasPrefix("timer:"),
               let minutes = Int(lowered.split(separator: ":").dropFirst().first ?? "") {
                return "Timer \(minutes)m"
            }

            switch lowered {
            case "continue":
                return "Continue"
            case "capture":
                return "Capture"
            case "current-thread", "current thread", "thread":
                return "Current Thread"
            case "work-queue", "work queue", "queue":
                return "Work Queue"
            case "timer":
                return "Timer"
            case "now-playing", "now playing", "music":
                return "Now Playing"
            case "playback", "toggle-playback", "pause":
                return "Playback"
            default:
                return lowered
            }
        }.joined(separator: " → ")
    }

    private func parseCipherMacroSteps(from text: String) -> [String] {
        text
            .split(separator: ",")
            .map { segment in
                segment
                    .lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            }
            .compactMap { rawStep in
                if rawStep.hasPrefix("timer:") {
                    let suffix = rawStep.split(separator: ":").dropFirst().first.map(String.init) ?? ""
                    if let minutes = Int(suffix), minutes > 0 {
                        return "timer:\(min(minutes, 24 * 60))"
                    }
                    return nil
                }

                switch rawStep {
                case "continue", "resume":
                    return "continue"
                case "capture", "save", "checkpoint":
                    return "capture"
                case "current thread", "thread", "current-thread":
                    return "current-thread"
                case "work queue", "queue", "work-queue":
                    return "work-queue"
                case "timer":
                    return "timer"
                case "now playing", "music", "now-playing":
                    return "now-playing"
                case "playback", "toggle playback", "pause", "play":
                    return "playback"
                default:
                    return nil
                }
            }
    }

    private func cipherSpellIndex(for kind: CipherSpellKind) -> Int? {
        makeCipherCardModel().spells.firstIndex(where: { $0.kind == kind && $0.isEnabled })
    }

    private func launcherIndex(forItemID itemID: String) -> Int? {
        items.firstIndex(where: { $0.id == itemID })
    }

    private func recordLastVisibleSurface(_ surface: PortalSurface) {
        portalRuntimeState.lastVisibleSurface = surface
    }

    private func runBundledAppStartupFlow() {
        guard config.runtimeMode == .bundledApp else {
            return
        }

        logStatus(name: "APP_STARTUP_FLOW", note: "running bundled-app startup flow")

        if !cipherConfigStore.isConfigured, showLauncherOnboardingIfNeeded() {
            return
        }

        if showCipherSetupIfNeeded(source: "startup") {
            return
        }

        markBundledAppReady()
    }

    @discardableResult
    private func showLauncherOnboardingIfNeeded() -> Bool {
        guard config.runtimeMode == .bundledApp else {
            return false
        }

        let shown = presentPageOnboarding(.launcher, source: "startup")
        if shown {
            logger.write(
                EventRecord(
                    timestamp: iso8601Now(),
                    recordType: "status",
                    mode: "launcher",
                    product: nil,
                    transport: nil,
                    vendorID: nil,
                    productID: nil,
                    registryID: nil,
                    usagePage: nil,
                    usage: nil,
                    integerValue: 1,
                    phase: "shown",
                    eventName: "ONBOARDING_OVERLAY",
                    gesture: nil,
                    rawData1: nil,
                    rawSubtype: nil,
                    note: "displayed launcher onboarding overlay"
                )
            )
        } else {
            displayPortalNotification(title: launcherDisplayName, body: "Inlay is running. Finish setup with +, -, tap center, then hold center.")
        }
        return shown
    }

    @discardableResult
    private func showCipherSetupIfNeeded(source: String) -> Bool {
        guard !cipherConfigStore.isConfigured else {
            return false
        }

        return presentCipherSetup(flow: .initialSetup, source: source)
    }

    private func markBundledAppReady() {
        logStatus(name: "APP_READY", note: "bundled app is ready and waiting for center_hold")
    }

    private func clearHUDInteractionState() {
        hudCenterPressStartedAt = nil
        companionCenterPressStartedAt = nil
        companionPushToTalkActive = false
        nowPlayingCenterPressStartedAt = nil
        cipherCenterPressStartedAt = nil
        cipherLexiconCenterPressStartedAt = nil
        supportCenterPressStartedAt = nil
        workSpellCenterPressStartedAt = nil
        workSpellSettingsCenterPressStartedAt = nil
        onboardingCenterPressStartedAt = nil
        workQueueCenterPressStartedAt = nil
        currentThreadCenterPressStartedAt = nil
        hiddenCipherVolumeUpPressStartedAt = nil
        hiddenCipherVolumeDownPressStartedAt = nil
    }

    private func suppressGesture(_ gesture: GestureKind, for duration: TimeInterval = 1.0) {
        suppressedGestures[gesture] = Date().addingTimeInterval(duration)
    }

    private func suppressHiddenCipherVolumeFamily(_ gesture: GestureKind) {
        switch gesture {
        case .volumeUp:
            suppressGesture(.volumeUp, for: 1.2)
            suppressGesture(.volumeUpDouble, for: 1.2)
            suppressGesture(.volumeUpTriple, for: 1.2)
        case .volumeDown:
            suppressGesture(.volumeDown, for: 1.2)
            suppressGesture(.volumeDownDouble, for: 1.2)
            suppressGesture(.volumeDownTriple, for: 1.2)
        default:
            break
        }
    }

    private func shouldSuppressGesture(_ gesture: GestureKind) -> Bool {
        let now = Date()
        suppressedGestures = suppressedGestures.filter { $0.value > now }
        guard let expiry = suppressedGestures[gesture] else {
            return false
        }
        return expiry > now
    }

    private func logLaunch(item: LauncherItem, index: Int) {
        let timestamp = iso8601Now()
        let record = EventRecord(
            timestamp: timestamp,
            recordType: "launch",
            mode: "launcher",
            product: nil,
            transport: nil,
            vendorID: nil,
            productID: nil,
            registryID: nil,
            usagePage: nil,
            usage: nil,
            integerValue: index,
            phase: "confirmed",
            eventName: "launcher-selection",
            gesture: GestureKind.centerSingle.rawValue,
            rawData1: nil,
            rawSubtype: nil,
            note: "confirmed from HUD selection",
            itemID: item.id,
            itemTitle: item.title,
            itemSymbol: item.symbol,
            selectedIndex: index
        )

        logger.write(record)
        emitStdout("[\(timestamp)] LAUNCH item=\(item.id) title=\(item.title) symbol=\(item.symbol) index=\(index)")
        if config.runtimeMode.successBeepsEnabled {
            playBeeps(2)
        }
    }

    private func logStatus(name: String, note: String) {
        let timestamp = iso8601Now()
        logger.write(
            EventRecord(
                timestamp: timestamp,
                recordType: "status",
                mode: "launcher",
                product: nil,
                transport: nil,
                vendorID: nil,
                productID: nil,
                registryID: nil,
                usagePage: nil,
                usage: nil,
                integerValue: 0,
                phase: "debug",
                eventName: name,
                gesture: nil,
                rawData1: nil,
                rawSubtype: nil,
                note: note
            )
        )
        emitStdout("[\(timestamp)] \(name) \(note)")
    }

    private func loudFailure(name: String, note: String) {
        let timestamp = iso8601Now()
        logger.write(
            EventRecord(
                timestamp: timestamp,
                recordType: "failure",
                mode: "launcher",
                product: nil,
                transport: nil,
                vendorID: nil,
                productID: nil,
                registryID: nil,
                usagePage: nil,
                usage: nil,
                integerValue: 0,
                phase: "failure",
                eventName: name,
                gesture: nil,
                rawData1: nil,
                rawSubtype: nil,
                note: note
            )
        )

        if config.runtimeMode.diagnosticsEnabled {
            FileHandle.standardError.write(Data("[\(timestamp)] FAILURE \(name) \(note)\n".utf8))
        }
        playBeeps(3)
        displayNotification(title: "\(launcherDisplayName) Failure", body: "\(name): \(note)")
    }

    private func emitFailureToUser(_ message: String) {
        if config.runtimeMode.diagnosticsEnabled {
            FileHandle.standardError.write(Data("\(message)\n".utf8))
        }
        if config.runtimeMode == .bundledApp {
            displayNotification(title: launcherDisplayName, body: message)
        }
    }

    private var isNonCriticalPortalFeedbackSuppressed: Bool {
        config.runtimeMode == .bundledApp && portalRuntimeState.isVeiled
    }

    private func displayPortalNotification(title: String, body: String) {
        guard !isNonCriticalPortalFeedbackSuppressed else {
            return
        }
        displayNotification(title: title, body: body)
    }

    private func emitStdout(_ line: String) {
        guard config.runtimeMode.diagnosticsEnabled else {
            return
        }

        print(line)
        fflush(stdout)
    }

    private func adjustTimer(direction: Int, isRepeat: Bool = false) {
        guard let timerCoordinator else {
            return
        }

        if direction > 0 {
            timerCoordinator.incrementCurrentValue()
            logStatus(name: isRepeat ? "TIMER_ADJUST_REPEAT" : "TIMER_ADJUST_RAW", note: "increased timer value")
        } else if direction < 0 {
            timerCoordinator.decrementCurrentValue()
            logStatus(name: isRepeat ? "TIMER_ADJUST_REPEAT" : "TIMER_ADJUST_RAW", note: "decreased timer value")
        }
    }

    private func beginTimerAdjustmentRepeat(direction: Int, usage: UInt32) {
        cancelTimerAdjustmentRepeat()
        activeTimerAdjustmentUsage = usage
        let generation = UUID()
        timerAdjustmentRepeatGeneration = generation

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(420)) { [weak self] in
            self?.continueTimerAdjustmentRepeat(direction: direction, usage: usage, generation: generation)
        }
    }

    private func continueTimerAdjustmentRepeat(direction: Int, usage: UInt32, generation: UUID) {
        guard generation == timerAdjustmentRepeatGeneration else {
            return
        }
        guard activeTimerAdjustmentUsage == usage else {
            return
        }
        guard let timerCardController, timerCardController.isVisible else {
            cancelTimerAdjustmentRepeat()
            return
        }

        adjustTimer(direction: direction, isRepeat: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(95)) { [weak self] in
            self?.continueTimerAdjustmentRepeat(direction: direction, usage: usage, generation: generation)
        }
    }

    private func cancelTimerAdjustmentRepeat(for usage: UInt32? = nil) {
        if let usage, activeTimerAdjustmentUsage != usage {
            return
        }

        activeTimerAdjustmentUsage = nil
        timerAdjustmentRepeatGeneration = UUID()
    }

    private func handleTimerCompletion() {
        logStatus(name: "TIMER_COMPLETE", note: "timer finished")
        cancelTimerAdjustmentRepeat()

        if let hudController, hudController.isVisible {
            _ = hudController.close()
            logStatus(name: "HUD_CLOSE", note: "closed main launcher because timer finished")
        }

        if let nowPlayingCardController, nowPlayingCardController.isVisible {
            _ = nowPlayingCardController.close()
            logStatus(name: "NOW_PLAYING_CLOSE", note: "closed now-playing card because timer finished")
        }

        if let workQueueCardController, workQueueCardController.isVisible {
            _ = workQueueCardController.close()
            logStatus(name: "WORK_QUEUE_CLOSE", note: "closed work queue because timer finished")
        }

        if let currentThreadCardController, currentThreadCardController.isVisible {
            _ = currentThreadCardController.close()
            logStatus(name: "CURRENT_THREAD_CLOSE", note: "closed current-thread because timer finished")
        }

        if let cipherCardController, cipherCardController.isVisible {
            _ = cipherCardController.close()
            logStatus(name: "CIPHER_CLOSE", note: "closed cipher because timer finished")
        }

        guard let timerCoordinator else {
            loudFailure(name: "TIMER_COMPLETE_FAILED", note: "timer finished but the timer coordinator was unavailable")
            return
        }

        let controller = ensureTimerCardController()
        let shown = controller.show(model: timerCoordinator.currentModel())
        if shown {
            recordLastVisibleSurface(.timer)
            logStatus(name: "TIMER_REOPEN", note: "reopened timer card for completion state")
        } else {
            loudFailure(name: "TIMER_REOPEN_FAILED", note: "timer finished but the completion card did not become visible")
        }

        startTimerCompletionAlert()
        displayNotification(title: launcherDisplayName, body: "Timer finished")
    }

    private func startTimerCompletionAlert() {
        cancelTimerCompletionAlert()
        let generation = UUID()
        timerCompletionAlertGeneration = generation

        for index in 0..<8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(index * 1100)) { [weak self] in
                self?.playTimerCompletionAlertPulse(generation: generation)
            }
        }
    }

    private func playTimerCompletionAlertPulse(generation: UUID) {
        guard generation == timerCompletionAlertGeneration else {
            return
        }

        if let sound = NSSound(named: NSSound.Name("Glass")) {
            activeTimerCompletionSound = sound
            sound.stop()
            sound.play()
        } else if let sound = NSSound(named: NSSound.Name("Funk")) {
            activeTimerCompletionSound = sound
            sound.stop()
            sound.play()
        } else {
            playBeeps(2)
        }
    }

    private func cancelTimerCompletionAlert() {
        timerCompletionAlertGeneration = UUID()
        activeTimerCompletionSound?.stop()
        activeTimerCompletionSound = nil
    }

    private func playBeeps(_ count: Int) {
        guard count > 0 else {
            return
        }

        for index in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(index * 160)) {
                NSSound.beep()
            }
        }
    }

    private func displayNotification(title: String, body: String) {
        DispatchQueue.global(qos: .utility).async {
            let script = "display notification \(appleScriptLiteral(body)) with title \(appleScriptLiteral(title))"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                if self.config.runtimeMode.diagnosticsEnabled {
                    fputs("Failed to trigger launcher notification: \(error.localizedDescription)\n", stderr)
                }
            }
        }
    }
}

private final class SignalTrap {
    private var sources: [DispatchSourceSignal] = []
    private let stopHandler: @MainActor () -> Void

    init(stopHandler: @MainActor @escaping () -> Void) {
        self.stopHandler = stopHandler
    }

    func install() {
        for signalCode in [SIGINT, SIGTERM] {
            signal(signalCode, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalCode, queue: .main)
            source.setEventHandler { [stopHandler] in
                print("\nStopping launcher.")
                Task { @MainActor in
                    stopHandler()
                    NSApp.stop(nil)
                    exit(0)
                }
            }
            source.resume()
            sources.append(source)
        }
    }
}

private func loadLauncherItems(from path: String) throws -> [LauncherItem] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    var items = try JSONDecoder().decode([LauncherItem].self, from: data)

    guard !items.isEmpty else {
        throw CLIError("Launcher config must contain at least one item.")
    }

    for item in items {
        if item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CLIError("Launcher config contains an item with an empty `id`.")
        }
        if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CLIError("Launcher config contains an item with an empty `title`.")
        }
        if item.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CLIError("Launcher config contains an item with an empty `symbol`.")
        }
    }

    items = items.filter { LauncherItem.supportedVisibleIDs.contains($0.id) }
    items.removeAll { $0.id == LauncherItem.supportItem.id }

    if !items.contains(where: { $0.id == LauncherItem.companionItem.id }) {
        items.insert(LauncherItem.companionItem, at: 0)
    }

    if !items.contains(where: { $0.id == LauncherItem.currentThreadItem.id }) {
        let insertionIndex = min(1, items.count)
        items.insert(LauncherItem.currentThreadItem, at: insertionIndex)
    }

    if !items.contains(where: { $0.id == LauncherItem.workQueueItem.id }) {
        let insertionIndex = min(2, items.count)
        items.insert(LauncherItem.workQueueItem, at: insertionIndex)
    }

    return items + [LauncherItem.supportItem, LauncherItem.quitItem]
}

private func printUsage() {
    print(
        """
        Usage:
          swift run earpods-launcher [--config path] [--log-path path] [--idle-timeout-ms ms]

        Options:
          --config path         Launcher menu JSON. Defaults to `./config/launcher.example.json` in CLI mode and `~/Library/Application Support/EarPodsLauncher/launcher.json` in app mode.
          --log-path path       NDJSON output path. Defaults to `./logs/launcher-events.ndjson` in CLI mode and `~/Library/Logs/EarPodsLauncher/launcher-events.ndjson` in app mode.
          --idle-timeout-ms     Close the HUD after this many idle milliseconds. Defaults to `5000`.
          -h, --help            Show this help.
        """
    )
}

private func appleScriptLiteral(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
}

private func shellLiteral(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

do {
    let config = try LauncherConfig.parse(arguments: Array(CommandLine.arguments.dropFirst()))

    let singleInstanceCoordinator: SingleInstanceCoordinator?
    if let lockPath = config.singletonLockPath {
        if let coordinator = try SingleInstanceCoordinator.acquire(lockPath: lockPath) {
            singleInstanceCoordinator = coordinator
        } else {
            SingleInstanceCoordinator.signalOpenRequest()
            exit(0)
        }
    } else {
        singleInstanceCoordinator = nil
    }

    let items = try loadLauncherItems(from: config.configPath)
    let logger = try NDJSONLogger(path: config.logPath)
    let onboardingStateStore = try OnboardingStateStore(path: config.onboardingStatePath)
    let cipherConfigStore = try CipherConfigStore(path: config.cipherConfigPath)
    let workQueueStore = try WorkQueueStore(path: config.workQueuePath)
    let workSpellStore = try WorkSpellStore(path: config.workSpellPath)
    let companionConfigStore = try CompanionConfigStore(path: config.companionConfigPath)

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = LauncherApplicationDelegate(
        config: config,
        logger: logger,
        items: items,
        singleInstanceCoordinator: singleInstanceCoordinator,
        onboardingStateStore: onboardingStateStore,
        cipherConfigStore: cipherConfigStore,
        workQueueStore: workQueueStore,
        workSpellStore: workSpellStore,
        companionConfigStore: companionConfigStore
    )

    if config.runtimeMode == .commandLine {
        let trap = SignalTrap {
            delegate.stop()
        }
        trap.install()
        withExtendedLifetime(trap) {
            app.delegate = delegate
            app.run()
        }
    } else {
        app.delegate = delegate
        app.run()
    }
} catch is CLIHelp {
    printUsage()
    exit(0)
} catch {
    fputs("\(error.localizedDescription)\n\n", stderr)
    printUsage()
    exit(1)
}

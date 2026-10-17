@preconcurrency import AppKit
import Dispatch
import EarPodsCore
import Foundation

private enum ProbeMode: String {
    case hid
    case system
}

private struct Config {
    let mode: ProbeMode
    let logPath: String
    let actionsPath: String?
    let notificationsEnabled: Bool
    let seizeHIDDevice: Bool
    let multiClickWindow: TimeInterval
    let holdThreshold: TimeInterval

    static func parse(arguments: [String]) throws -> Config {
        var mode: ProbeMode = .hid
        var logPath = "./logs/earpods-events.ndjson"
        var actionsPath: String?
        var notificationsEnabled = true
        var seizeHIDDevice = false
        var multiClickWindow: TimeInterval = 0.65
        var holdThreshold: TimeInterval = 0.60

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--mode":
                index += 1
                guard index < arguments.count, let parsedMode = ProbeMode(rawValue: arguments[index]) else {
                    throw CLIError("Expected `hid` or `system` after `--mode`.")
                }
                mode = parsedMode
            case "--log-path":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("Expected a file path after `--log-path`.")
                }
                logPath = arguments[index]
            case "--actions-path":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("Expected a file path after `--actions-path`.")
                }
                actionsPath = arguments[index]
            case "--click-window-ms":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("Expected a number after `--click-window-ms`.")
                }
                multiClickWindow = try parseMillisecondsArgument(arguments[index], flag: "--click-window-ms")
            case "--hold-threshold-ms":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("Expected a number after `--hold-threshold-ms`.")
                }
                holdThreshold = try parseMillisecondsArgument(arguments[index], flag: "--hold-threshold-ms")
            case "--no-notify":
                notificationsEnabled = false
            case "--seize":
                seizeHIDDevice = true
            case "--help", "-h":
                throw CLIHelp()
            default:
                throw CLIError("Unknown argument: \(argument)")
            }

            index += 1
        }

        return Config(
            mode: mode,
            logPath: logPath,
            actionsPath: actionsPath,
            notificationsEnabled: notificationsEnabled,
            seizeHIDDevice: seizeHIDDevice,
            multiClickWindow: multiClickWindow,
            holdThreshold: holdThreshold
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

private struct GestureActionDefinition: Codable {
    let shellCommand: String?
    let notifyTitle: String?
    let notifyBody: String?
    let notificationsEnabled: Bool?
}

private final class ActionRunner {
    let notificationsEnabled: Bool
    let actionsPath: String?
    private let definitions: [String: GestureActionDefinition]

    init(notificationsEnabled: Bool, actionsPath: String?) throws {
        self.notificationsEnabled = notificationsEnabled
        self.actionsPath = actionsPath.map(normalizePath)

        if let actionsPath {
            let url = URL(fileURLWithPath: normalizePath(actionsPath))
            let data = try Data(contentsOf: url)
            self.definitions = try JSONDecoder().decode([String: GestureActionDefinition].self, from: data)
        } else {
            self.definitions = [:]
        }
    }

    func describeConfiguration() {
        print("Notifications: \(notificationsEnabled ? "enabled" : "disabled")")
        if let actionsPath {
            print("Action config: \(actionsPath)")
        } else {
            print("Action config: none")
        }
    }

    func performActions(for gesture: GestureKind) {
        let definition = definitions[gesture.rawValue]
        let shouldNotify = notificationsEnabled && (definition?.notificationsEnabled ?? true)
        let title = definition?.notifyTitle ?? gesture.defaultNotificationTitle
        let body = definition?.notifyBody ?? gesture.defaultNotificationBody

        if shouldNotify {
            displayNotification(title: title, body: body)
            print("Action notification: \(title) - \(body)")
        }

        if let shellCommand = definition?.shellCommand, !shellCommand.isEmpty {
            runShellCommand(shellCommand, gesture: gesture.rawValue)
            print("Action command: \(gesture.rawValue) -> \(shellCommand)")
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
                fputs("Failed to trigger macOS notification: \(error.localizedDescription)\n", stderr)
            }
        }
    }

    private func runShellCommand(_ command: String, gesture: String) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    fputs("Command for \(gesture) exited with status \(process.terminationStatus)\n", stderr)
                }
            } catch {
                fputs("Failed to run command for \(gesture): \(error.localizedDescription)\n", stderr)
            }
        }
    }
}

private final class HIDProbe {
    private let logger: NDJSONLogger
    private let actionRunner: ActionRunner
    private let listener: EarPodsHIDListener
    private let multiClickWindow: TimeInterval
    private let holdThreshold: TimeInterval

    init(logger: NDJSONLogger, actionRunner: ActionRunner, config: Config) {
        self.logger = logger
        self.actionRunner = actionRunner
        self.multiClickWindow = config.multiClickWindow
        self.holdThreshold = config.holdThreshold
        self.listener = EarPodsHIDListener(
            configuration: HIDListenerConfiguration(
                seizeHIDDevice: config.seizeHIDDevice,
                multiClickWindow: config.multiClickWindow,
                holdThreshold: config.holdThreshold
            )
        )
    }

    func start() throws {
        printHeader(title: "HID Probe")
        print("Matching devices on primary usage page 12 (consumer controls).")
        print("Candidate EarPods devices are marked with `*`.")

        listener.onDeviceMatched = { snapshot in
            print("Device matched: \(snapshot.displayLine)")
        }
        listener.onDeviceRemoved = { snapshot in
            print("Device removed: \(snapshot.displayLine)")
        }
        listener.onRawEvent = { [logger] event in
            logger.write(event.makeLogRecord(mode: ProbeMode.hid.rawValue))
            print("[\(event.timestamp)] HID product=\(event.snapshot.product ?? "(unknown)") usagePage=\(event.usagePage) usage=\(event.usage) value=\(event.integerValue) phase=\(event.phase) event=\(event.eventName ?? "unknown")")
            fflush(stdout)
        }
        listener.onGesture = { [logger, actionRunner] event in
            logger.write(event.makeLogRecord(mode: ProbeMode.hid.rawValue))
            print("[\(event.timestamp)] GESTURE gesture=\(event.gesture.rawValue) product=\(event.snapshot?.product ?? "(unknown)") sourceUsage=\(event.usage?.description ?? "n/a") note=\(event.note)")
            fflush(stdout)
            actionRunner.performActions(for: event.gesture)
        }

        try listener.start()

        print("Log file: \(logger.path)")
        actionRunner.describeConfiguration()
        print("Exclusive seize: \(listener.isSeizing ? "enabled" : "disabled")")
        print("Click window: \(Int(multiClickWindow * 1000))ms")
        print("Hold threshold: \(Int(holdThreshold * 1000))ms")
        print("Waiting for inline remote button events. Press Control-C to stop.\n")

        let devices = listener.enumerateCurrentDevices()
        if devices.isEmpty {
            print("No consumer-control HID devices are currently visible.\n")
        } else {
            print("Currently matched devices:")
            for snapshot in devices {
                print(snapshot.displayLine)
            }
            print("")
        }

        CFRunLoopRun()
    }

    func stop() {
        listener.stop()
        logger.close()
    }
}

private final class SystemEventProbe {
    private let logger: NDJSONLogger
    private var monitor: Any?

    init(logger: NDJSONLogger) {
        self.logger = logger
    }

    func start() {
        printHeader(title: "System Event Probe")
        print("Listening for AppKit `systemDefined` media events.")
        print("If nothing appears here while button presses still change volume or playback, macOS may be handling the remote above the HID layer visible to this process.")
        print("Log file: \(logger.path)")
        print("Waiting for inline remote button events. Press Control-C to stop.\n")

        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.systemDefined]) { [weak self] event in
            self?.handle(event)
        }

        RunLoop.main.run()
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        logger.close()
    }

    private func handle(_ event: NSEvent) {
        guard event.subtype.rawValue == 8 else {
            return
        }

        let data1 = Int(event.data1)
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyFlags = data1 & 0x0000FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isRepeat = (keyFlags & 0x1) == 0x1

        let phase: String
        switch keyState {
        case 0xA:
            phase = isRepeat ? "repeat" : "down"
        case 0xB:
            phase = "up"
        default:
            phase = "raw"
        }

        let record = EventRecord(
            timestamp: iso8601Now(),
            recordType: "raw",
            mode: ProbeMode.system.rawValue,
            product: "SystemEvent",
            transport: "AppKit",
            vendorID: nil,
            productID: nil,
            registryID: nil,
            usagePage: nil,
            usage: UInt32(keyCode),
            integerValue: keyFlags & 0x1,
            phase: phase,
            eventName: mediaKeyName(for: keyCode),
            gesture: nil,
            rawData1: data1,
            rawSubtype: Int(event.subtype.rawValue),
            note: nil
        )

        logger.write(record)
        print("[\(record.timestamp)] SYSTEM keyCode=\(keyCode) phase=\(phase) repeat=\(isRepeat) event=\(record.eventName ?? "unknown") rawData1=\(data1)")
        fflush(stdout)
    }
}

private final class SignalTrap {
    private var sources: [DispatchSourceSignal] = []
    private let stopHandler: () -> Void

    init(stopHandler: @escaping () -> Void) {
        self.stopHandler = stopHandler
    }

    func install() {
        for signalCode in [SIGINT, SIGTERM] {
            signal(signalCode, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalCode, queue: .main)
            source.setEventHandler { [stopHandler] in
                print("\nStopping probe.")
                stopHandler()
                CFRunLoopStop(CFRunLoopGetMain())
                exit(0)
            }
            source.resume()
            sources.append(source)
        }
    }
}

private func mediaKeyName(for keyCode: Int) -> String? {
    switch keyCode {
    case 0: return "volume-up"
    case 1: return "volume-down"
    case 7: return "mute"
    case 16: return "play-pause"
    case 17: return "next-track"
    case 18: return "previous-track"
    case 19: return "fast-forward"
    case 20: return "rewind"
    default: return nil
    }
}

private func appleScriptLiteral(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
}

private func printUsage() {
    print(
        """
        Usage:
          swift run earpods-probe [--mode hid|system] [--log-path path] [--actions-path path] [--click-window-ms ms] [--hold-threshold-ms ms] [--seize] [--no-notify]

        Options:
          --mode hid|system   Listener mode. Defaults to `hid`.
          --log-path path     NDJSON output path. Defaults to `./logs/earpods-events.ndjson`.
          --actions-path path Optional JSON config mapping gestures to shell commands and notification overrides.
          --click-window-ms   Delay before a center click is committed. Defaults to `650`.
          --hold-threshold-ms Duration needed to recognize hold gestures. Defaults to `600`.
          --seize             Request exclusive access to the EarPods HID device so macOS may stop handling the buttons itself.
          --no-notify         Disable macOS notifications while keeping gesture logging active.
          -h, --help          Show this help.
        """
    )
}

do {
    let config = try Config.parse(arguments: Array(CommandLine.arguments.dropFirst()))
    let logger = try NDJSONLogger(path: config.logPath)
    let actionRunner = try ActionRunner(notificationsEnabled: config.notificationsEnabled, actionsPath: config.actionsPath)

    switch config.mode {
    case .hid:
        let probe = HIDProbe(logger: logger, actionRunner: actionRunner, config: config)
        let trap = SignalTrap {
            probe.stop()
        }
        trap.install()
        try probe.start()
    case .system:
        let probe = SystemEventProbe(logger: logger)
        let trap = SignalTrap {
            probe.stop()
        }
        trap.install()
        probe.start()
    }
} catch is CLIHelp {
    printUsage()
    exit(0)
} catch {
    fputs("\(error.localizedDescription)\n\n", stderr)
    printUsage()
    exit(1)
}

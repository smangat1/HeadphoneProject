import AVFoundation
import ApplicationServices
import Foundation
import Speech

enum SupportPermissionStatus {
    case allowed
    case needsPrompt
    case denied
    case unavailable

    var title: String {
        switch self {
        case .allowed:
            return "Allowed"
        case .needsPrompt:
            return "Not Asked Yet"
        case .denied:
            return "Needs Access"
        case .unavailable:
            return "Unavailable"
        }
    }

    var detail: String {
        switch self {
        case .allowed:
            return "Looks good on this Mac."
        case .needsPrompt:
            return "Inlay will ask the first time you use that feature."
        case .denied:
            return "Open System Settings to grant access."
        case .unavailable:
            return "macOS is not offering this service right now."
        }
    }
}

struct SupportStatusSnapshot {
    let speechRecognition: SupportPermissionStatus
    let microphone: SupportPermissionStatus
    let accessibility: SupportPermissionStatus

    static func current() -> SupportStatusSnapshot {
        let speechStatus: SupportPermissionStatus
        if SFSpeechRecognizer() == nil {
            speechStatus = .unavailable
        } else {
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized:
                speechStatus = .allowed
            case .notDetermined:
                speechStatus = .needsPrompt
            case .denied, .restricted:
                speechStatus = .denied
            @unknown default:
                speechStatus = .denied
            }
        }

        let microphoneStatus: SupportPermissionStatus
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneStatus = .allowed
        case .notDetermined:
            microphoneStatus = .needsPrompt
        case .denied, .restricted:
            microphoneStatus = .denied
        @unknown default:
            microphoneStatus = .denied
        }

        let accessibilityStatus: SupportPermissionStatus = AXIsProcessTrusted() ? .allowed : .denied

        return SupportStatusSnapshot(
            speechRecognition: speechStatus,
            microphone: microphoneStatus,
            accessibility: accessibilityStatus
        )
    }

    var readinessTitle: String {
        if needsSetup {
            return "Setup Needed"
        }
        return "Ready"
    }

    var needsSetup: Bool {
        [speechRecognition, microphone, accessibility].contains { status in
            switch status {
            case .allowed:
                return false
            case .needsPrompt, .denied, .unavailable:
                return true
            }
        }
    }

    var summaryText: String {
        [
            "Speech Recognition: \(speechRecognition.title)",
            "Microphone: \(microphone.title)",
            "Accessibility: \(accessibility.title)",
            "Companion opens fresh browser searches. Existing-tab switching is not supported yet.",
            "Now Playing can read Spotify, Music, and the frontmost supported browser media tab.",
            "Finder, browser, Spotify, and Music prompts appear the first time Inlay automates them.",
            "If Inlay feels hidden, launch it again to wake the running instance.",
            "If it still feels stuck, use Restart Inlay below. The rows below also reveal logs and support files."
        ].joined(separator: "\n")
    }
}

enum SupportActionKind {
    case openSpeechSettings
    case openMicrophoneSettings
    case openAccessibilitySettings
    case openCompanionHelp
    case restartInlay
    case revealLogs
    case revealSupportFiles
    case back
}

struct SupportAction {
    let kind: SupportActionKind
    let title: String
    let detail: String
    let symbol: String
    let isEnabled: Bool

    init(
        kind: SupportActionKind,
        title: String,
        detail: String,
        symbol: String,
        isEnabled: Bool = true
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.isEnabled = isEnabled
    }
}

struct SupportCardModel {
    let title: String
    let subtitle: String
    let metadataText: String
    let footer: String
    let actions: [SupportAction]
}

import EarPodsCore
import Foundation

let cipherDefaultStepCount = 4

extension GestureKind {
    static let cipherAllowedSteps: [GestureKind] = [.volumeUp, .volumeDown, .centerSingle, .centerDouble]
    static let cipherAllowedStepSet: Set<GestureKind> = Set(cipherAllowedSteps)

    var cipherDisplayTitle: String {
        switch self {
        case .volumeUp:
            return "+"
        case .volumeDown:
            return "-"
        case .centerSingle:
            return "Tap"
        case .centerDouble:
            return "Double"
        default:
            return rawValue
        }
    }

    var cipherDisplayDetail: String {
        switch self {
        case .volumeUp:
            return "Plus"
        case .volumeDown:
            return "Minus"
        case .centerSingle:
            return "Center Tap"
        case .centerDouble:
            return "Center Double"
        default:
            return rawValue
        }
    }
}

enum PortalSurface: Equatable {
    case launcher(selectedIndex: Int)
    case currentThread
    case timer
    case nowPlaying
    case workQueue(selectedIndex: Int)
    case workSpell(selectedIndex: Int)

    var displayName: String {
        switch self {
        case .launcher:
            return "Launcher"
        case .currentThread:
            return "Current Thread"
        case .timer:
            return "Timer"
        case .nowPlaying:
            return "Now Playing"
        case .workQueue:
            return "Work Queue"
        case .workSpell:
            return "Work Spell"
        }
    }
}

struct PortalRuntimeState {
    var isVeiled = false
    var isSealed = false
    var lastVisibleSurface: PortalSurface?
}

struct CipherConfiguration: Codable {
    let sequence: [GestureKind]
}

final class CipherConfigStore {
    private let path: String
    private(set) var currentSequence: [GestureKind]?

    init(path: String) throws {
        self.path = normalizePath(path)
        try load()
    }

    var isConfigured: Bool {
        currentSequence?.count == cipherDefaultStepCount
    }

    func save(sequence: [GestureKind]) throws {
        let normalizedSequence = Array(sequence.prefix(cipherDefaultStepCount))
        guard normalizedSequence.count == cipherDefaultStepCount else {
            throw NSError(domain: "CipherConfigStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cipher sequence must contain exactly \(cipherDefaultStepCount) steps."])
        }
        guard normalizedSequence.allSatisfy({ GestureKind.cipherAllowedStepSet.contains($0) }) else {
            throw NSError(domain: "CipherConfigStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cipher sequence contains an unsupported gesture."])
        }

        currentSequence = normalizedSequence
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(CipherConfiguration(sequence: normalizedSequence))
        try data.write(to: url, options: .atomic)
    }

    private func load() throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        guard FileManager.default.fileExists(atPath: url.path) else {
            currentSequence = nil
            return
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            currentSequence = nil
            return
        }

        let decoded = try JSONDecoder().decode(CipherConfiguration.self, from: data)
        if decoded.sequence.count == cipherDefaultStepCount,
           decoded.sequence.allSatisfy({ GestureKind.cipherAllowedStepSet.contains($0) }) {
            currentSequence = decoded.sequence
        } else {
            currentSequence = nil
        }
    }
}

enum CipherSpellKind: String {
    case veil
    case echo
    case seal
    case spellbook
    case lexicon
    case rekey
    case back
}

struct CipherSpell {
    let kind: CipherSpellKind
    let title: String
    let symbol: String
    let detail: String
    let isEnabled: Bool
}

struct CipherCardModel {
    let title: String
    let subtitle: String
    let spells: [CipherSpell]
    let isVeiled: Bool
    let isSealed: Bool

    static func make(from runtimeState: PortalRuntimeState) -> CipherCardModel {
        let echoDetail: String
        let echoEnabled: Bool
        if let lastVisibleSurface = runtimeState.lastVisibleSurface {
            echoDetail = "Return to \(lastVisibleSurface.displayName)"
            echoEnabled = true
        } else {
            echoDetail = "Nothing cached yet"
            echoEnabled = false
        }

        let spells = [
            CipherSpell(
                kind: .veil,
                title: runtimeState.isVeiled ? "Veil: On" : "Veil: Off",
                symbol: "moon.stars",
                detail: "Quiet non-critical portal feedback",
                isEnabled: true
            ),
            CipherSpell(
                kind: .echo,
                title: "Echo",
                symbol: "arrow.uturn.backward.circle",
                detail: echoDetail,
                isEnabled: echoEnabled
            ),
            CipherSpell(
                kind: .seal,
                title: runtimeState.isSealed ? "Seal: On" : "Seal: Off",
                symbol: "lock.shield",
                detail: "Block hidden center-hold launcher open",
                isEnabled: true
            ),
            CipherSpell(
                kind: .spellbook,
                title: "Spellbook",
                symbol: "wand.and.stars",
                detail: "Configure Work Spell gestures and state",
                isEnabled: true
            ),
            CipherSpell(
                kind: .lexicon,
                title: "Lexicon",
                symbol: "text.word.spacing",
                detail: "Teach Companion private phrases and meanings",
                isEnabled: true
            ),
            CipherSpell(
                kind: .rekey,
                title: "Rekey",
                symbol: "key.horizontal",
                detail: "Choose a new hidden unlock code",
                isEnabled: true
            ),
            CipherSpell(
                kind: .back,
                title: "Back",
                symbol: "chevron.backward.circle",
                detail: "Dismiss Cipher and go dark again",
                isEnabled: true
            ),
        ]

        return CipherCardModel(
            title: "Cipher",
            subtitle: "A hidden spell layer for the portal.",
            spells: spells,
            isVeiled: runtimeState.isVeiled,
            isSealed: runtimeState.isSealed
        )
    }
}

enum CipherSequenceOutcome {
    case ignored
    case progressed(step: Int, total: Int)
    case reset(reason: String)
    case unlocked
}

final class CipherSequenceRecognizer {
    static let stepTimeout: TimeInterval = 2.5
    static let acceptedGestures: Set<GestureKind> = GestureKind.cipherAllowedStepSet

    private var sequence: [GestureKind]
    private var currentIndex = 0
    private var lastAcceptedAt: Date?

    init(sequence: [GestureKind] = []) {
        self.sequence = sequence
    }

    func updateSequence(_ sequence: [GestureKind]) {
        self.sequence = sequence
        reset()
    }

    func consume(_ gesture: GestureKind, now: Date = Date()) -> CipherSequenceOutcome {
        guard !sequence.isEmpty else {
            return .ignored
        }
        guard Self.acceptedGestures.contains(gesture) else {
            return .ignored
        }

        if let lastAcceptedAt, now.timeIntervalSince(lastAcceptedAt) > Self.stepTimeout {
            reset()
        }

        let expectedGesture = sequence[currentIndex]
        guard gesture == expectedGesture else {
            reset()
            if gesture == sequence[0] {
                currentIndex = 1
                self.lastAcceptedAt = now
                return .reset(reason: "sequence reset; restarted at step 1/\(sequence.count)")
            }
            return .reset(reason: "sequence reset after wrong step")
        }

        currentIndex += 1
        lastAcceptedAt = now

        if currentIndex == sequence.count {
            reset()
            return .unlocked
        }

        return .progressed(step: currentIndex, total: sequence.count)
    }

    func reset() {
        currentIndex = 0
        lastAcceptedAt = nil
    }
}

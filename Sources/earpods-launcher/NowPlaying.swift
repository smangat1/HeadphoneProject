import AppKit
import Foundation

enum NowPlayingSource: String {
    case spotify
    case music
    case browser
    case none

    var displayName: String {
        switch self {
        case .spotify:
            return "Spotify"
        case .music:
            return "Music"
        case .browser:
            return "Browser"
        case .none:
            return "Nothing Playing"
        }
    }

    var badgeSymbol: String {
        switch self {
        case .spotify:
            return "waveform.and.magnifyingglass"
        case .music:
            return "music.note.house"
        case .browser:
            return "play.rectangle.on.rectangle"
        case .none:
            return "music.note"
        }
    }
}

enum NowPlayingPlayerState: String {
    case playing
    case paused
    case stopped
    case unknown

    init(scriptValue: String) {
        switch scriptValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "playing":
            self = .playing
        case "paused":
            self = .paused
        case "stopped":
            self = .stopped
        default:
            self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .stopped:
            return "Stopped"
        case .unknown:
            return "Unknown"
        }
    }
}

struct NowPlayingSnapshot {
    let source: NowPlayingSource
    let playerState: NowPlayingPlayerState
    let title: String
    let artist: String
    let album: String
    let trackIdentifier: String?
    let externalURL: URL?
    let artworkURL: URL?

    var hasTrackContext: Bool {
        !title.isEmpty
    }

    static let empty = NowPlayingSnapshot(
        source: .none,
        playerState: .stopped,
        title: "Nothing Playing",
        artist: "Open Spotify or Music from here.",
        album: "",
        trackIdentifier: nil,
        externalURL: nil,
        artworkURL: nil
    )
}

enum NowPlayingActionKind: String {
    case openSpotify
    case openMusic
    case openBrowser
    case playPause
    case copySpotifyLink
    case back
}

struct NowPlayingAction {
    let kind: NowPlayingActionKind
    let title: String
    let symbol: String
}

struct NowPlayingCardModel {
    let snapshot: NowPlayingSnapshot
    let actions: [NowPlayingAction]
    let sessionText: String

    static let empty = NowPlayingCardModel(
        snapshot: .empty,
        actions: [
            NowPlayingAction(kind: .openSpotify, title: "Open Spotify", symbol: "arrow.up.right.square"),
            NowPlayingAction(kind: .openMusic, title: "Open Music", symbol: "music.note.house"),
            NowPlayingAction(kind: .back, title: "Back", symbol: "chevron.backward")
        ],
        sessionText: "Session 0:00"
    )
}

struct NowPlayingActionOutcome {
    let logNote: String
    let notificationBody: String?
}

struct NowPlayingActionError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
final class NowPlayingCoordinator {
    nonisolated private static let spotifyBundleID = "com.spotify.client"
    nonisolated private static let musicBundleID = "com.apple.Music"
    nonisolated private static let scriptDelimiter = String(UnicodeScalar(30))
    nonisolated private static let knownBrowserMediaHosts = [
        "youtube.com",
        "music.youtube.com",
        "youtu.be",
        "soundcloud.com",
        "vimeo.com",
        "netflix.com",
        "twitch.tv",
        "hulu.com",
        "disneyplus.com"
    ]

    private var sessionTracker: NowPlayingSessionTracker
    private let refreshInterval: TimeInterval
    private var refreshTimer: Timer?
    private var refreshSequence: UInt64 = 0

    private(set) var currentModel: NowPlayingCardModel = .empty
    var onUpdate: ((NowPlayingCardModel) -> Void)?

    init(refreshInterval: TimeInterval = 2.0, resetGap: TimeInterval = 5 * 60) {
        self.refreshInterval = refreshInterval
        self.sessionTracker = NowPlayingSessionTracker(resetGap: resetGap)
    }

    func start() {
        refreshAsync()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAsync()
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func requestImmediateRefresh() {
        refreshAsync()
    }

    func perform(_ action: NowPlayingActionKind) -> Result<NowPlayingActionOutcome, NowPlayingActionError> {
        switch action {
        case .openSpotify:
            openSpotify(using: currentModel.snapshot)
            refreshAsync()
            return .success(
                NowPlayingActionOutcome(
                    logNote: "opened Spotify from now-playing card",
                    notificationBody: nil
                )
            )
        case .openMusic:
            let success = openMusic(using: currentModel.snapshot)
            refreshAsync()
            if success {
                return .success(
                    NowPlayingActionOutcome(
                        logNote: "opened Music from now-playing card",
                        notificationBody: nil
                    )
                )
            }
            return .failure(NowPlayingActionError(message: "Music could not be opened from the Now Playing card."))
        case .openBrowser:
            guard let externalURL = currentModel.snapshot.externalURL else {
                return .failure(NowPlayingActionError(message: "There is no browser media page to reopen right now."))
            }
            _ = NSWorkspace.shared.open(externalURL)
            return .success(
                NowPlayingActionOutcome(
                    logNote: "opened browser media page \(externalURL.absoluteString)",
                    notificationBody: nil
                )
            )
        case .playPause:
            let source = currentModel.snapshot.source
            guard source != .none else {
                return .failure(NowPlayingActionError(message: "There is nothing active to play or pause right now."))
            }
            let success = playPause(source: source)
            refreshAsync()
            if success {
                return .success(
                    NowPlayingActionOutcome(
                        logNote: "toggled play/pause for \(source.displayName)",
                        notificationBody: nil
                    )
                )
            }
            return .failure(NowPlayingActionError(message: "The player did not accept a play/pause command."))
        case .copySpotifyLink:
            guard let shareURL = spotifyShareURL(from: currentModel.snapshot.externalURL) else {
                return .failure(NowPlayingActionError(message: "Spotify did not expose a shareable track link for this item."))
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(shareURL.absoluteString, forType: .string)
            return .success(
                NowPlayingActionOutcome(
                    logNote: "copied Spotify link \(shareURL.absoluteString)",
                    notificationBody: "Copied Spotify link"
                )
            )
        case .back:
            return .success(
                NowPlayingActionOutcome(
                    logNote: "returned to main launcher from now-playing card",
                    notificationBody: nil
                )
            )
        }
    }

    private func refreshAsync() {
        refreshSequence &+= 1
        let sequence = refreshSequence

        Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.resolveCurrentSnapshot()
            }.value

            await MainActor.run {
                guard let self, sequence == self.refreshSequence else {
                    return
                }

                let now = Date()
                self.sessionTracker.update(with: snapshot, now: now)
                self.currentModel = self.makeCardModel(snapshot: snapshot, sessionText: self.sessionTracker.formatted(now: now))
                self.onUpdate?(self.currentModel)
            }
        }
    }

    private func makeCardModel(snapshot: NowPlayingSnapshot, sessionText: String) -> NowPlayingCardModel {
        let actions: [NowPlayingAction]
        switch snapshot.source {
        case .spotify:
            actions = [
                NowPlayingAction(kind: .openSpotify, title: "Open in Spotify", symbol: "arrow.up.right.square"),
                NowPlayingAction(kind: .playPause, title: "Play/Pause", symbol: "playpause"),
                NowPlayingAction(kind: .copySpotifyLink, title: "Copy Spotify Link", symbol: "link"),
                NowPlayingAction(kind: .back, title: "Back", symbol: "chevron.backward")
            ]
        case .music:
            actions = [
                NowPlayingAction(kind: .openMusic, title: "Open in Music", symbol: "arrow.up.right.square"),
                NowPlayingAction(kind: .playPause, title: "Play/Pause", symbol: "playpause"),
                NowPlayingAction(kind: .back, title: "Back", symbol: "chevron.backward")
            ]
        case .browser:
            actions = [
                NowPlayingAction(kind: .openBrowser, title: "Open in Browser", symbol: "arrow.up.right.square"),
                NowPlayingAction(kind: .back, title: "Back", symbol: "chevron.backward")
            ]
        case .none:
            actions = [
                NowPlayingAction(kind: .openSpotify, title: "Open Spotify", symbol: "arrow.up.right.square"),
                NowPlayingAction(kind: .openMusic, title: "Open Music", symbol: "music.note.house"),
                NowPlayingAction(kind: .back, title: "Back", symbol: "chevron.backward")
            ]
        }

        return NowPlayingCardModel(snapshot: snapshot, actions: actions, sessionText: sessionText)
    }

    nonisolated private static func resolveCurrentSnapshot() -> NowPlayingSnapshot {
        let spotifySnapshot = resolveSpotifySnapshot()
        let musicSnapshot = resolveMusicSnapshot()
        let browserSnapshot = resolveBrowserSnapshot()

        if spotifySnapshot.playerState == .playing, spotifySnapshot.hasTrackContext {
            return spotifySnapshot
        }
        if musicSnapshot.playerState == .playing, musicSnapshot.hasTrackContext {
            return musicSnapshot
        }
        if browserSnapshot.playerState == .playing, browserSnapshot.hasTrackContext {
            return browserSnapshot
        }
        if spotifySnapshot.playerState == .paused, spotifySnapshot.hasTrackContext {
            return spotifySnapshot
        }
        if musicSnapshot.playerState == .paused, musicSnapshot.hasTrackContext {
            return musicSnapshot
        }
        if browserSnapshot.hasTrackContext {
            return browserSnapshot
        }
        return .empty
    }

    nonisolated private static func resolveSpotifySnapshot() -> NowPlayingSnapshot {
        guard isAppRunning(bundleIdentifier: Self.spotifyBundleID) else {
            return .empty
        }

        let script = [
            "set outputDelimiter to character id 30",
            "tell application id \"\(Self.spotifyBundleID)\"",
            "set stateText to (player state as text)",
            "if stateText is \"stopped\" then return stateText",
            "try",
            "set trackRef to current track",
            "set titleText to name of trackRef",
            "set artistText to artist of trackRef",
            "set albumText to album of trackRef",
            "set identifierText to id of trackRef",
            "set linkText to spotify url of trackRef",
            "set artText to artwork url of trackRef",
            "return stateText & outputDelimiter & titleText & outputDelimiter & artistText & outputDelimiter & albumText & outputDelimiter & identifierText & outputDelimiter & linkText & outputDelimiter & artText",
            "on error",
            "return stateText",
            "end try",
            "end tell",
        ]

        guard let output = runAppleScript(lines: script) else {
            return .empty
        }

        let parts = output.components(separatedBy: Self.scriptDelimiter)
        let playerState = NowPlayingPlayerState(scriptValue: parts.first ?? "unknown")
        guard parts.count >= 7 else {
            return NowPlayingSnapshot(
                source: .spotify,
                playerState: playerState,
                title: "",
                artist: "",
                album: "",
                trackIdentifier: nil,
                externalURL: nil,
                artworkURL: nil
            )
        }

        return NowPlayingSnapshot(
            source: .spotify,
            playerState: playerState,
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            trackIdentifier: parts[4].nilIfEmpty,
            externalURL: URL(string: parts[5]),
            artworkURL: URL(string: parts[6])
        )
    }

    nonisolated private static func resolveMusicSnapshot() -> NowPlayingSnapshot {
        guard isAppRunning(bundleIdentifier: Self.musicBundleID) else {
            return .empty
        }

        let script = [
            "set outputDelimiter to character id 30",
            "tell application id \"\(Self.musicBundleID)\"",
            "set stateText to (player state as text)",
            "if stateText is \"stopped\" then return stateText",
            "try",
            "set trackRef to current track",
            "set titleText to name of trackRef",
            "set artistText to artist of trackRef",
            "set albumText to album of trackRef",
            "set identifierText to persistent ID of trackRef",
            "return stateText & outputDelimiter & titleText & outputDelimiter & artistText & outputDelimiter & albumText & outputDelimiter & identifierText",
            "on error",
            "return stateText",
            "end try",
            "end tell",
        ]

        guard let output = runAppleScript(lines: script) else {
            return .empty
        }

        let parts = output.components(separatedBy: Self.scriptDelimiter)
        let playerState = NowPlayingPlayerState(scriptValue: parts.first ?? "unknown")
        guard parts.count >= 5 else {
            return NowPlayingSnapshot(
                source: .music,
                playerState: playerState,
                title: "",
                artist: "",
                album: "",
                trackIdentifier: nil,
                externalURL: nil,
                artworkURL: nil
            )
        }

        return NowPlayingSnapshot(
            source: .music,
            playerState: playerState,
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            trackIdentifier: parts[4].nilIfEmpty,
            externalURL: nil,
            artworkURL: nil
        )
    }

    nonisolated private static func resolveBrowserSnapshot() -> NowPlayingSnapshot {
        guard let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              let browser = browserMediaSpecs().first(where: { $0.bundleIdentifier == frontmostBundleIdentifier }) else {
            return .empty
        }

        guard let output = runAppleScript(lines: browser.snapshotLines(delimiter: Self.scriptDelimiter)),
              !output.isEmpty else {
            return .empty
        }

        let parts = output.components(separatedBy: Self.scriptDelimiter)
        guard parts.count >= 3 else {
            return .empty
        }

        let rawTitle = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let rawURL = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let rawMediaState = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let host = host(from: rawURL)
        let cleanedTitle = cleanedBrowserTitle(rawTitle, host: host)
        let playerState = NowPlayingPlayerState(scriptValue: rawMediaState)

        guard looksLikeBrowserMedia(title: cleanedTitle, host: host, playerState: playerState) else {
            return .empty
        }

        let detailHost = host ?? browser.name.lowercased()
        let state = playerState == .stopped ? .unknown : playerState

        return NowPlayingSnapshot(
            source: .browser,
            playerState: state,
            title: cleanedTitle,
            artist: detailHost,
            album: browser.name,
            trackIdentifier: nil,
            externalURL: URL(string: rawURL),
            artworkURL: nil
        )
    }

    private func openSpotify(using snapshot: NowPlayingSnapshot) {
        if let externalURL = snapshot.externalURL {
            _ = NSWorkspace.shared.open(externalURL)
            return
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.spotifyBundleID) {
            _ = NSWorkspace.shared.open(appURL)
        }
    }

    private func openMusic(using snapshot: NowPlayingSnapshot) -> Bool {
        if snapshot.source == .music {
            let script = [
                "tell application id \"\(Self.musicBundleID)\"",
                "activate",
                "try",
                "reveal current track",
                "end try",
                "end tell",
            ]
            return Self.runAppleScript(lines: script) != nil
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.musicBundleID) {
            _ = NSWorkspace.shared.open(appURL)
            return true
        }

        return false
    }

    private func playPause(source: NowPlayingSource) -> Bool {
        let bundleIdentifier: String
        switch source {
        case .spotify:
            bundleIdentifier = Self.spotifyBundleID
        case .music:
            bundleIdentifier = Self.musicBundleID
        case .browser:
            return false
        case .none:
            return false
        }

        let script = [
            "tell application id \"\(bundleIdentifier)\"",
            "playpause",
            "end tell",
        ]
        return Self.runAppleScript(lines: script) != nil
    }

    private func spotifyShareURL(from externalURL: URL?) -> URL? {
        guard let externalURL else {
            return nil
        }
        if externalURL.scheme == "https" {
            return externalURL
        }
        guard externalURL.scheme == "spotify" else {
            return externalURL
        }

        let parts = externalURL.absoluteString.components(separatedBy: ":")
        guard parts.count >= 3 else {
            return externalURL
        }
        let entityType = parts[1]
        let entityID = parts[2]
        return URL(string: "https://open.spotify.com/\(entityType)/\(entityID)")
    }

    nonisolated private static func isAppRunning(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    nonisolated private static func runAppleScript(lines: [String]) -> String? {
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
            return nil
        }
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : trimmed
    }

    nonisolated private static func browserMediaSpecs() -> [BrowserMediaSpec] {
        [
            BrowserMediaSpec(
                name: "Arc",
                appName: "Arc",
                bundleIdentifier: "company.thebrowser.Browser",
                titleExpression: "title of active tab of front window",
                urlExpression: "URL of active tab of front window",
                mediaStateExpression: #"execute active tab of front window javascript "(() => { try { const media = document.querySelector('video, audio'); if (!media) return 'no-media'; return media.paused ? 'paused' : 'playing'; } catch (e) { return 'unknown'; } })()""#
            ),
            BrowserMediaSpec(
                name: "Google Chrome",
                appName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                titleExpression: "title of active tab of front window",
                urlExpression: "URL of active tab of front window",
                mediaStateExpression: #"execute active tab of front window javascript "(() => { try { const media = document.querySelector('video, audio'); if (!media) return 'no-media'; return media.paused ? 'paused' : 'playing'; } catch (e) { return 'unknown'; } })()""#
            ),
            BrowserMediaSpec(
                name: "Safari",
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                titleExpression: "name of current tab of front window",
                urlExpression: "URL of current tab of front window",
                mediaStateExpression: #"do JavaScript "(() => { try { const media = document.querySelector('video, audio'); if (!media) return 'no-media'; return media.paused ? 'paused' : 'playing'; } catch (e) { return 'unknown'; } })()" in current tab of front window"#
            ),
            BrowserMediaSpec(
                name: "Brave Browser",
                appName: "Brave Browser",
                bundleIdentifier: "com.brave.Browser",
                titleExpression: "title of active tab of front window",
                urlExpression: "URL of active tab of front window",
                mediaStateExpression: #"execute active tab of front window javascript "(() => { try { const media = document.querySelector('video, audio'); if (!media) return 'no-media'; return media.paused ? 'paused' : 'playing'; } catch (e) { return 'unknown'; } })()""#
            )
        ]
    }

    nonisolated private static func looksLikeBrowserMedia(title: String, host: String?, playerState: NowPlayingPlayerState) -> Bool {
        if playerState == .playing || playerState == .paused {
            return !title.isEmpty
        }

        guard let host else {
            return false
        }
        return knownBrowserMediaHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) && !title.isEmpty
    }

    nonisolated private static func cleanedBrowserTitle(_ rawTitle: String, host: String?) -> String {
        var title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = [
            " - YouTube",
            " - Music.youtube.com",
            " - Netflix",
            " - Vimeo",
            " - SoundCloud",
            " - Twitch",
            " - Hulu",
            " - Disney+"
        ]

        for suffix in suffixes where title.hasSuffix(suffix) {
            title.removeLast(suffix.count)
            break
        }

        if let host, title == host {
            return rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return title
    }

    nonisolated private static func host(from rawURL: String) -> String? {
        guard let url = URL(string: rawURL),
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        return host.lowercased()
    }
}

private struct BrowserMediaSpec {
    let name: String
    let appName: String
    let bundleIdentifier: String
    let titleExpression: String
    let urlExpression: String
    let mediaStateExpression: String

    func snapshotLines(delimiter: String) -> [String] {
        [
            "set outputDelimiter to character id 30",
            "tell application \(appleScriptLiteral(appName))",
            "if (count of windows) = 0 then return \"\"",
            "set titleText to \"\"",
            "set urlText to \"\"",
            "set mediaStateText to \"unknown\"",
            "try",
            "set titleText to \(titleExpression)",
            "end try",
            "try",
            "set urlText to \(urlExpression)",
            "end try",
            "try",
            "set mediaStateText to \(mediaStateExpression)",
            "end try",
            "return titleText & outputDelimiter & urlText & outputDelimiter & mediaStateText",
            "end tell"
        ]
    }
}

private struct NowPlayingSessionTracker {
    private let resetGap: TimeInterval
    private var accumulated: TimeInterval = 0
    private var activeStartedAt: Date?
    private var inactiveSince: Date?

    init(resetGap: TimeInterval) {
        self.resetGap = resetGap
    }

    mutating func update(with snapshot: NowPlayingSnapshot, now: Date) {
        if snapshot.playerState == .playing {
            if let inactiveSince, now.timeIntervalSince(inactiveSince) > resetGap {
                accumulated = 0
            }
            inactiveSince = nil
            if activeStartedAt == nil {
                activeStartedAt = now
            }
            return
        }

        if let activeStartedAt {
            accumulated += now.timeIntervalSince(activeStartedAt)
            self.activeStartedAt = nil
        }

        if inactiveSince == nil {
            inactiveSince = now
        }
    }

    func formatted(now: Date) -> String {
        let liveDuration = accumulated + (activeStartedAt.map { now.timeIntervalSince($0) } ?? 0)
        let totalSeconds = max(Int(liveDuration.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let hours = minutes / 60

        if hours > 0 {
            return "Session \(hours):" + String(format: "%02d:%02d", minutes % 60, seconds)
        }
        return "Session \(minutes):" + String(format: "%02d", seconds)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func appleScriptLiteral(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
}

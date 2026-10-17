import Foundation

enum CurrentThreadActionKind: String {
    case saveToQueue = "save_to_queue"
    case resumeApp = "resume_app"
    case refreshName = "refresh_name"
    case back
}

struct CurrentThreadAction {
    let kind: CurrentThreadActionKind
    let title: String
    let detail: String
    let symbol: String
    let isEnabled: Bool
}

struct CurrentThreadDescription {
    let title: String
    let subtitle: String
    let metadataText: String
    let badgeTitle: String
    let badgeSymbol: String
    let applicationName: String
    let bundleIdentifier: String?
    let windowTitle: String?
    let musicSummary: String?
    let isCapturable: Bool
}

struct CurrentThreadCardModel {
    let description: CurrentThreadDescription
    let actions: [CurrentThreadAction]
    let footer: String
}

private enum CurrentThreadCategory {
    case building
    case researching
    case designing
    case writing
    case communicating
    case organizing
    case reviewing
    case listening
    case working

    var badgeTitle: String {
        switch self {
        case .building:
            return "Build"
        case .researching:
            return "Research"
        case .designing:
            return "Design"
        case .writing:
            return "Write"
        case .communicating:
            return "Reply"
        case .organizing:
            return "Organize"
        case .reviewing:
            return "Review"
        case .listening:
            return "Listen"
        case .working:
            return "Thread"
        }
    }

    var badgeSymbol: String {
        switch self {
        case .building:
            return "hammer"
        case .researching:
            return "magnifyingglass"
        case .designing:
            return "wand.and.stars"
        case .writing:
            return "square.and.pencil"
        case .communicating:
            return "bubble.left.and.bubble.right"
        case .organizing:
            return "folder"
        case .reviewing:
            return "doc.text.magnifyingglass"
        case .listening:
            return "music.note"
        case .working:
            return "sparkles"
        }
    }

    var progressiveVerb: String {
        switch self {
        case .building:
            return "Building"
        case .researching:
            return "Researching"
        case .designing:
            return "Designing"
        case .writing:
            return "Writing"
        case .communicating:
            return "Replying"
        case .organizing:
            return "Organizing"
        case .reviewing:
            return "Reviewing"
        case .listening:
            return "Listening in"
        case .working:
            return "Working in"
        }
    }

    func defaultTitle(in applicationName: String) -> String {
        "\(progressiveVerb) \(applicationName)"
    }

    static func infer(applicationName: String, bundleIdentifier: String?, windowTitle: String?) -> CurrentThreadCategory {
        let corpus = [
            applicationName.lowercased(),
            bundleIdentifier?.lowercased() ?? "",
            windowTitle?.lowercased() ?? ""
        ].joined(separator: " ")

        if corpus.contains("cursor") ||
            corpus.contains("xcode") ||
            corpus.contains("visual studio") ||
            corpus.contains("codex") ||
            corpus.contains("terminal") ||
            corpus.contains("iterm") ||
            corpus.contains("warp") ||
            corpus.contains("zed") {
            return .building
        }

        if corpus.contains("safari") ||
            corpus.contains("chrome") ||
            corpus.contains("arc") ||
            corpus.contains("firefox") ||
            corpus.contains("edge") ||
            corpus.contains("brave") {
            return .researching
        }

        if corpus.contains("figma") ||
            corpus.contains("framer") ||
            corpus.contains("sketch") ||
            corpus.contains("photoshop") ||
            corpus.contains("illustrator") ||
            corpus.contains("pixelmator") ||
            corpus.contains("canva") {
            return .designing
        }

        if corpus.contains("notes") ||
            corpus.contains("obsidian") ||
            corpus.contains("ulysses") ||
            corpus.contains("pages") ||
            corpus.contains("word") ||
            corpus.contains("bear") {
            return .writing
        }

        if corpus.contains("mail") ||
            corpus.contains("messages") ||
            corpus.contains("slack") ||
            corpus.contains("discord") ||
            corpus.contains("teams") {
            return .communicating
        }

        if corpus.contains("finder") {
            return .organizing
        }

        if corpus.contains("preview") ||
            corpus.contains("books") ||
            corpus.contains("pdf") ||
            corpus.contains("reader") {
            return .reviewing
        }

        if corpus.contains("spotify") || corpus.contains("music") {
            return .listening
        }

        return .working
    }
}

enum CurrentThreadNamingEngine {
    static func describe(frontmostApp: WorkQueueAppContext?, nowPlayingSnapshot: NowPlayingSnapshot?) -> CurrentThreadDescription {
        let musicSummary = makeMusicSummary(from: nowPlayingSnapshot)
        guard let activeAppName = sanitize(frontmostApp?.applicationName) else {
            let metadata = musicSummary.map { "Soundtrack: \($0)" }
                ?? "Open a real app or document first, then come back here."
            return CurrentThreadDescription(
                title: "No Current Thread Yet",
                subtitle: "The portal will name the app and window you’re actually in.",
                metadataText: metadata,
                badgeTitle: "Idle",
                badgeSymbol: "sparkles",
                applicationName: "Current Context",
                bundleIdentifier: nil,
                windowTitle: nil,
                musicSummary: musicSummary,
                isCapturable: false
            )
        }

        let windowTitle = cleanWindowTitle(frontmostApp?.windowTitle, applicationName: activeAppName)
        let semanticTitle = cleanContextTitle(
            frontmostApp?.semanticTitle,
            applicationName: activeAppName,
            fallbackWindowTitle: windowTitle
        )
        let semanticDetail = sanitize(frontmostApp?.semanticDetail)
        let category = CurrentThreadCategory.infer(
            applicationName: activeAppName,
            bundleIdentifier: frontmostApp?.bundleIdentifier,
            windowTitle: semanticTitle ?? windowTitle
        )
        let primaryTitle = makePrimaryTitle(
            applicationName: activeAppName,
            windowTitle: windowTitle,
            semanticTitle: semanticTitle,
            semanticDetail: semanticDetail,
            category: category,
            nowPlayingSnapshot: nowPlayingSnapshot
        )
        let subtitle = makeSubtitle(
            applicationName: activeAppName,
            windowTitle: windowTitle,
            semanticTitle: semanticTitle,
            semanticDetail: semanticDetail,
            category: category,
            nowPlayingSnapshot: nowPlayingSnapshot
        )
        let metadataText = makeMetadataText(
            applicationName: activeAppName,
            windowTitle: windowTitle,
            semanticTitle: semanticTitle,
            semanticDetail: semanticDetail,
            title: primaryTitle,
            musicSummary: musicSummary,
            category: category
        )

        return CurrentThreadDescription(
            title: primaryTitle,
            subtitle: subtitle,
            metadataText: metadataText,
            badgeTitle: category.badgeTitle,
            badgeSymbol: category.badgeSymbol,
            applicationName: activeAppName,
            bundleIdentifier: frontmostApp?.bundleIdentifier,
            windowTitle: windowTitle,
            musicSummary: musicSummary,
            isCapturable: true
        )
    }

    static func cleanWindowTitle(_ value: String?, applicationName: String) -> String? {
        guard var title = sanitize(value) else {
            return nil
        }

        for separator in [" — ", " - ", " – "] {
            let suffix = "\(separator)\(applicationName)"
            if title.hasSuffix(suffix) {
                title.removeLast(suffix.count)
                title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        guard let cleaned = sanitize(title), cleaned.caseInsensitiveCompare(applicationName) != .orderedSame else {
            return nil
        }

        return truncate(cleaned, maxLength: 58)
    }

    static func cleanContextTitle(
        _ value: String?,
        applicationName: String,
        fallbackWindowTitle: String?
    ) -> String? {
        guard let cleaned = cleanWindowTitle(value, applicationName: applicationName) else {
            return nil
        }

        if let fallbackWindowTitle,
           cleaned.caseInsensitiveCompare(fallbackWindowTitle) == .orderedSame {
            return nil
        }

        return cleaned
    }

    static func makeMusicSummary(from snapshot: NowPlayingSnapshot?) -> String? {
        guard let snapshot, snapshot.hasTrackContext, snapshot.source != .none else {
            return nil
        }

        let album = snapshot.album.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if artist.isEmpty, album.isEmpty {
            return snapshot.title
        }

        var parts: [String] = [snapshot.title]
        if !artist.isEmpty {
            parts.append(artist)
        }
        if !album.isEmpty {
            parts.append(album)
        }
        return parts.joined(separator: " — ")
    }

    private static func sanitize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func makePrimaryTitle(
        applicationName: String,
        windowTitle: String?,
        semanticTitle: String?,
        semanticDetail: String?,
        category: CurrentThreadCategory,
        nowPlayingSnapshot: NowPlayingSnapshot?
    ) -> String {
        if category == .listening,
           let nowPlayingSnapshot,
           nowPlayingSnapshot.hasTrackContext {
            let album = nowPlayingSnapshot.album.trimmingCharacters(in: .whitespacesAndNewlines)
            if !album.isEmpty {
                return "Listening to \(truncate(album, maxLength: 44))"
            }
            return truncate(nowPlayingSnapshot.title, maxLength: 58)
        }

        if let semanticTitle, !semanticTitle.isEmpty {
            return semanticTitle
        }

        if let windowTitle, !windowTitle.isEmpty {
            return windowTitle
        }

        if category == .researching, let semanticDetail, !semanticDetail.isEmpty {
            return "Browsing \(semanticDetail)"
        }

        return category.defaultTitle(in: applicationName)
    }

    private static func makeSubtitle(
        applicationName: String,
        windowTitle: String?,
        semanticTitle: String?,
        semanticDetail: String?,
        category: CurrentThreadCategory,
        nowPlayingSnapshot: NowPlayingSnapshot?
    ) -> String {
        if category == .listening,
           let nowPlayingSnapshot,
           nowPlayingSnapshot.hasTrackContext {
            let artist = nowPlayingSnapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let track = nowPlayingSnapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !artist.isEmpty && !track.isEmpty {
                return "\(track) — \(artist)"
            }
            if !track.isEmpty {
                return "Playing in \(applicationName)"
            }
        }

        if category == .researching, let semanticDetail, !semanticDetail.isEmpty {
            return "Browsing \(semanticDetail)"
        }

        if semanticTitle != nil || (windowTitle != nil && !(windowTitle?.isEmpty ?? true)) {
            return "\(category.progressiveVerb) \(applicationName)"
        }

        if let windowTitle, !windowTitle.isEmpty {
            return "\(category.progressiveVerb) \(applicationName)"
        }
        return "Named from the app you’re in right now."
    }

    private static func makeMetadataText(
        applicationName: String,
        windowTitle: String?,
        semanticTitle: String?,
        semanticDetail: String?,
        title: String,
        musicSummary: String?
        ,
        category: CurrentThreadCategory
    ) -> String {
        var lines = ["App: \(applicationName)"]

        if let windowTitle, !windowTitle.isEmpty, windowTitle.caseInsensitiveCompare(title) != .orderedSame {
            lines.append("Window: \(windowTitle)")
        }

        if let semanticTitle,
           !semanticTitle.isEmpty,
           semanticTitle.caseInsensitiveCompare(title) != .orderedSame,
           semanticTitle.caseInsensitiveCompare(windowTitle ?? "") != .orderedSame {
            lines.append("Context: \(semanticTitle)")
        }

        if let semanticDetail, !semanticDetail.isEmpty {
            lines.append("\(detailLabel(for: category, applicationName: applicationName)): \(semanticDetail)")
        }

        if let musicSummary, !musicSummary.isEmpty {
            lines.append("Soundtrack: \(musicSummary)")
        }

        return lines.joined(separator: "\n")
    }

    private static func detailLabel(for category: CurrentThreadCategory, applicationName: String) -> String {
        switch category {
        case .researching:
            return "Site"
        case .organizing where applicationName.lowercased().contains("finder"):
            return "Folder"
        default:
            return "Context"
        }
    }

    private static func truncate(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else {
            return value
        }

        let endIndex = value.index(value.startIndex, offsetBy: maxLength - 1)
        return String(value[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

@MainActor
final class CurrentThreadCoordinator {
    func makeModel(frontmostApp: WorkQueueAppContext?, nowPlayingSnapshot: NowPlayingSnapshot?) -> CurrentThreadCardModel {
        let description = CurrentThreadNamingEngine.describe(
            frontmostApp: frontmostApp,
            nowPlayingSnapshot: nowPlayingSnapshot
        )

        let actions = [
            CurrentThreadAction(
                kind: .saveToQueue,
                title: "Save to Queue",
                detail: "Stage this named thread in Work Queue.",
                symbol: "tray.and.arrow.down",
                isEnabled: description.isCapturable
            ),
            CurrentThreadAction(
                kind: .resumeApp,
                title: "Resume App",
                detail: "Bring \(description.applicationName) back to the front.",
                symbol: "arrow.turn.up.right",
                isEnabled: description.bundleIdentifier != nil
            ),
            CurrentThreadAction(
                kind: .refreshName,
                title: "Refresh Name",
                detail: "Read the current app and window title again.",
                symbol: "arrow.clockwise",
                isEnabled: true
            ),
            CurrentThreadAction(
                kind: .back,
                title: "Back",
                detail: "Return to the launcher.",
                symbol: "chevron.backward",
                isEnabled: true
            ),
        ]

        return CurrentThreadCardModel(
            description: description,
            actions: actions,
            footer: "Tap center to act. Hold center to go back."
        )
    }
}

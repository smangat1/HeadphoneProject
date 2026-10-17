import AppKit

@MainActor var portalShouldActivateAppOnShow = false

enum PortalHUDStyle {
    static let cornerRadius: CGFloat = 30
    static let compactCornerRadius: CGFloat = 28
    static let contentInset: CGFloat = 22
    static let rowCornerRadius: CGFloat = 14
    static let badgeCornerRadius: CGFloat = 11

    static let primaryTextColor = NSColor.white
    static let secondaryTextColor = NSColor.white.withAlphaComponent(0.74)
    static let tertiaryTextColor = NSColor.white.withAlphaComponent(0.60)
    static let quaternaryTextColor = NSColor.white.withAlphaComponent(0.35)

    static let rowSelectedFillColor = NSColor.white.withAlphaComponent(0.16)
    static let rowIdleFillColor = NSColor.white.withAlphaComponent(0.03)
    static let rowMutedFillColor = NSColor.white.withAlphaComponent(0.02)
    static let rowSelectedBorderColor = NSColor.white.withAlphaComponent(0.12)
    static let surfaceBorderColor = NSColor.white.withAlphaComponent(0.08)
}

enum PortalRowSurfaceState {
    case selected
    case idle
    case muted
    case disabled
}

enum PortalTextEmphasis {
    case icon
    case primary
    case secondary
}

@MainActor
func makePortalHUDChrome(
    accentColor: NSColor,
    tintOpacity: CGFloat,
    cornerRadius: CGFloat = PortalHUDStyle.cornerRadius
) -> (rootView: NSView, chromeView: NSVisualEffectView) {
    let chromeView = NSVisualEffectView()
    chromeView.translatesAutoresizingMaskIntoConstraints = false
    chromeView.material = .hudWindow
    chromeView.blendingMode = .behindWindow
    chromeView.state = .active
    chromeView.wantsLayer = true
    chromeView.layer?.cornerRadius = cornerRadius
    chromeView.layer?.cornerCurve = .continuous
    chromeView.layer?.masksToBounds = true
    chromeView.layer?.borderWidth = 1
    chromeView.layer?.borderColor = PortalHUDStyle.surfaceBorderColor.cgColor

    let tintOverlay = NSView()
    tintOverlay.translatesAutoresizingMaskIntoConstraints = false
    tintOverlay.wantsLayer = true
    tintOverlay.layer?.backgroundColor = accentColor.withAlphaComponent(tintOpacity).cgColor
    chromeView.addSubview(tintOverlay, positioned: .below, relativeTo: nil)

    let rootView = NSView()
    rootView.translatesAutoresizingMaskIntoConstraints = false
    rootView.addSubview(chromeView)

    NSLayoutConstraint.activate([
        tintOverlay.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor),
        tintOverlay.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor),
        tintOverlay.topAnchor.constraint(equalTo: chromeView.topAnchor),
        tintOverlay.bottomAnchor.constraint(equalTo: chromeView.bottomAnchor),

        chromeView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
        chromeView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
        chromeView.topAnchor.constraint(equalTo: rootView.topAnchor),
        chromeView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
    ])

    return (rootView, chromeView)
}

@MainActor
func applyPortalFloatingWindowStyle(_ window: NSWindow) {
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = true
    window.isReleasedWhenClosed = false
}

@MainActor
func configurePortalRowSurface(_ view: NSView, cornerRadius: CGFloat = PortalHUDStyle.rowCornerRadius) {
    view.translatesAutoresizingMaskIntoConstraints = false
    view.wantsLayer = true
    view.layer?.cornerRadius = cornerRadius
    view.layer?.cornerCurve = .continuous
}

@MainActor
func applyPortalRowSurface(_ view: NSView, state: PortalRowSurfaceState) {
    switch state {
    case .selected:
        view.layer?.backgroundColor = PortalHUDStyle.rowSelectedFillColor.cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = PortalHUDStyle.rowSelectedBorderColor.cgColor
    case .idle:
        view.layer?.backgroundColor = PortalHUDStyle.rowIdleFillColor.cgColor
        view.layer?.borderWidth = 0
        view.layer?.borderColor = PortalHUDStyle.rowSelectedBorderColor.cgColor
    case .muted:
        view.layer?.backgroundColor = PortalHUDStyle.rowMutedFillColor.cgColor
        view.layer?.borderWidth = 0
        view.layer?.borderColor = PortalHUDStyle.surfaceBorderColor.cgColor
    case .disabled:
        view.layer?.backgroundColor = PortalHUDStyle.rowMutedFillColor.cgColor
        view.layer?.borderWidth = 0
        view.layer?.borderColor = PortalHUDStyle.surfaceBorderColor.cgColor
    }
}

@MainActor
func colorForState(isSelected: Bool, enabled: Bool, emphasis: PortalTextEmphasis) -> NSColor {
    if !enabled {
        return PortalHUDStyle.quaternaryTextColor
    }

    if isSelected {
        switch emphasis {
        case .icon, .primary:
            return PortalHUDStyle.primaryTextColor
        case .secondary:
            return PortalHUDStyle.secondaryTextColor
        }
    }

    switch emphasis {
    case .icon:
        return PortalHUDStyle.secondaryTextColor
    case .primary:
        return PortalHUDStyle.primaryTextColor
    case .secondary:
        return PortalHUDStyle.tertiaryTextColor
    }
}

@MainActor
func configurePortalBadgeSurface(_ view: NSView, cornerRadius: CGFloat = PortalHUDStyle.badgeCornerRadius) {
    view.translatesAutoresizingMaskIntoConstraints = false
    view.wantsLayer = true
    view.layer?.cornerRadius = cornerRadius
    view.layer?.cornerCurve = .continuous
    view.layer?.backgroundColor = PortalHUDStyle.rowIdleFillColor.cgColor
    view.layer?.borderWidth = 1
    view.layer?.borderColor = PortalHUDStyle.surfaceBorderColor.cgColor
}

@MainActor
func centerPortalWindow(_ window: NSWindow) {
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first!
    let visibleFrame = screen.visibleFrame
    let windowSize = window.frame.size
    let origin = CGPoint(
        x: visibleFrame.midX - (windowSize.width / 2),
        y: visibleFrame.midY - (windowSize.height / 2)
    )
    window.setFrameOrigin(origin)
}

@MainActor
func topTrailingPortalWindow(_ window: NSWindow, inset: CGPoint = CGPoint(x: 18, y: 18)) {
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first!
    let visibleFrame = screen.visibleFrame
    let windowSize = window.frame.size
    let origin = CGPoint(
        x: visibleFrame.maxX - windowSize.width - inset.x,
        y: visibleFrame.maxY - windowSize.height - inset.y
    )
    window.setFrameOrigin(origin)
}

@MainActor
func showPortalWindow(_ window: NSWindow, makeKey: Bool = false) {
    if portalShouldActivateAppOnShow {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
    }

    if makeKey, window.canBecomeKey {
        window.makeKeyAndOrderFront(nil)
    } else {
        window.orderFrontRegardless()
    }

    window.displayIfNeeded()
}

@MainActor
func stylePortalTitle(_ field: NSTextField, alignment: NSTextAlignment = .center) {
    field.translatesAutoresizingMaskIntoConstraints = false
    field.font = NSFont.systemFont(ofSize: 22, weight: .bold)
    field.textColor = PortalHUDStyle.primaryTextColor
    field.alignment = alignment
}

@MainActor
func stylePortalSubtitle(_ field: NSTextField, alignment: NSTextAlignment = .center) {
    field.translatesAutoresizingMaskIntoConstraints = false
    field.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    field.textColor = PortalHUDStyle.secondaryTextColor
    field.alignment = alignment
}

@MainActor
func stylePortalFooter(_ field: NSTextField, alignment: NSTextAlignment = .center) {
    field.translatesAutoresizingMaskIntoConstraints = false
    field.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    field.textColor = PortalHUDStyle.tertiaryTextColor
    field.alignment = alignment
}

import Foundation
import IOKit
@preconcurrency import IOKit.hid

public struct DeviceSnapshot {
    public let product: String?
    public let transport: String?
    public let vendorID: UInt32?
    public let productID: UInt32?
    public let registryID: UInt64?
    public let usagePage: UInt32?
    public let usage: UInt32?

    public var isLikelyEarPods: Bool {
        let productName = product?.localizedCaseInsensitiveContains("earpods") == true
        return (vendorID == 0x05ac && productID == 0x110b) || productName
    }

    public var displayLine: String {
        let marker = isLikelyEarPods ? "*" : "-"
        let productName = product ?? "(unknown product)"
        let transportName = transport ?? "(unknown transport)"
        let vendor = vendorID.map(hex32) ?? "n/a"
        let productIDText = productID.map(hex32) ?? "n/a"
        let registry = registryID.map(hex64) ?? "n/a"
        return "\(marker) \(productName) transport=\(transportName) vendorID=\(vendor) productID=\(productIDText) registryID=\(registry) usagePage=\(usagePage?.description ?? "n/a") usage=\(usage?.description ?? "n/a")"
    }
}

public enum GestureKind: String, Codable, Sendable {
    case volumeUp = "volume_up"
    case volumeUpDouble = "volume_up_double"
    case volumeUpTriple = "volume_up_triple"
    case volumeDown = "volume_down"
    case volumeDownDouble = "volume_down_double"
    case volumeDownTriple = "volume_down_triple"
    case volumeUpHold = "volume_up_hold"
    case volumeDownHold = "volume_down_hold"
    case centerSingle = "center_single"
    case centerDouble = "center_double"
    case centerTriple = "center_triple"
    case centerHold = "center_hold"

    public var defaultNotificationTitle: String {
        "EarPods"
    }

    public var defaultNotificationBody: String {
        switch self {
        case .volumeUp:
            return "Volume Up button"
        case .volumeUpDouble:
            return "Volume Up double click"
        case .volumeUpTriple:
            return "Volume Up triple click"
        case .volumeDown:
            return "Volume Down button"
        case .volumeDownDouble:
            return "Volume Down double click"
        case .volumeDownTriple:
            return "Volume Down triple click"
        case .volumeUpHold:
            return "Volume Up hold"
        case .volumeDownHold:
            return "Volume Down hold"
        case .centerSingle:
            return "Center single click"
        case .centerDouble:
            return "Center double click"
        case .centerTriple:
            return "Center triple click"
        case .centerHold:
            return "Center hold"
        }
    }
}

public struct HIDRawEvent {
    public let timestamp: String
    public let snapshot: DeviceSnapshot
    public let usagePage: UInt32
    public let usage: UInt32
    public let integerValue: Int
    public let phase: String
    public let eventName: String?

    public func makeLogRecord(mode: String) -> EventRecord {
        EventRecord(
            timestamp: timestamp,
            recordType: "raw",
            mode: mode,
            product: snapshot.product,
            transport: snapshot.transport,
            vendorID: snapshot.vendorID,
            productID: snapshot.productID,
            registryID: snapshot.registryID,
            usagePage: usagePage,
            usage: usage,
            integerValue: integerValue,
            phase: phase,
            eventName: eventName,
            gesture: nil,
            rawData1: nil,
            rawSubtype: nil,
            note: nil
        )
    }
}

public struct GestureEvent {
    public let timestamp: String
    public let gesture: GestureKind
    public let snapshot: DeviceSnapshot?
    public let usagePage: UInt32?
    public let usage: UInt32?
    public let integerValue: Int
    public let note: String

    public func makeLogRecord(mode: String) -> EventRecord {
        EventRecord(
            timestamp: timestamp,
            recordType: "gesture",
            mode: mode,
            product: snapshot?.product,
            transport: snapshot?.transport,
            vendorID: snapshot?.vendorID,
            productID: snapshot?.productID,
            registryID: snapshot?.registryID,
            usagePage: usagePage,
            usage: usage,
            integerValue: integerValue,
            phase: "recognized",
            eventName: gesture.defaultNotificationBody,
            gesture: gesture.rawValue,
            rawData1: nil,
            rawSubtype: nil,
            note: note
        )
    }
}

public struct HIDListenerConfiguration {
    public let seizeHIDDevice: Bool
    public let multiClickWindow: TimeInterval
    public let holdThreshold: TimeInterval

    public init(
        seizeHIDDevice: Bool = false,
        multiClickWindow: TimeInterval = 0.85,
        holdThreshold: TimeInterval = 0.60
    ) {
        self.seizeHIDDevice = seizeHIDDevice
        self.multiClickWindow = multiClickWindow
        self.holdThreshold = holdThreshold
    }
}

public struct EarPodsHIDListenerError: LocalizedError {
    public let code: IOReturn
    public let seizeRequested: Bool

    public var errorDescription: String? {
        let hint: String
        if code == kIOReturnNotPermitted {
            hint = " Permission was denied. If you're running inside Codex or another sandboxed tool, run the built binary directly in Terminal or allow elevated execution."
        } else if seizeRequested {
            hint = " Exclusive access failed. Another process may already own the device, or macOS may refuse seizure for this hardware."
        } else {
            hint = ""
        }

        return "Failed to open IOHIDManager: \(code).\(hint)"
    }
}

public final class EarPodsHIDListener {
    public var onDeviceMatched: ((DeviceSnapshot) -> Void)?
    public var onDeviceRemoved: ((DeviceSnapshot) -> Void)?
    public var onRawEvent: ((HIDRawEvent) -> Void)?
    public var onGesture: ((GestureEvent) -> Void)?

    public let configuration: HIDListenerConfiguration
    public let isSeizing: Bool

    private let manager: IOHIDManager
    private let openOptions: IOOptionBits
    private let gestureDetector: GestureDetector
    private var lastValues: [String: Int] = [:]
    private var isRunning = false

    public init(configuration: HIDListenerConfiguration) {
        self.configuration = configuration
        self.isSeizing = configuration.seizeHIDDevice
        self.openOptions = IOOptionBits(configuration.seizeHIDDevice ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone)
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.gestureDetector = GestureDetector(
            multiClickWindow: configuration.multiClickWindow,
            holdThreshold: configuration.holdThreshold
        )
        self.gestureDetector.onGesture = { _ in }
    }

    public func start() throws {
        guard !isRunning else {
            return
        }

        let match: [String: Any] = [
            kIOHIDPrimaryUsagePageKey as String: 12,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, earPodsDeviceMatchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, earPodsDeviceRemovalCallback, context)
        IOHIDManagerRegisterInputValueCallback(manager, earPodsInputValueCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let openResult = IOHIDManagerOpen(manager, openOptions)
        guard openResult == kIOReturnSuccess else {
            throw EarPodsHIDListenerError(code: openResult, seizeRequested: configuration.seizeHIDDevice)
        }

        gestureDetector.onGesture = { [weak self] event in
            self?.onGesture?(event)
        }
        isRunning = true
    }

    public func stop() {
        guard isRunning else {
            return
        }

        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, openOptions)
        isRunning = false
    }

    public func enumerateCurrentDevices() -> [DeviceSnapshot] {
        guard let devices = IOHIDManagerCopyDevices(manager) else {
            return []
        }

        let deviceSet = devices as NSSet
        guard deviceSet.count > 0 else {
            return []
        }

        var snapshots: [DeviceSnapshot] = []
        for case let device as IOHIDDevice in deviceSet {
            snapshots.append(snapshotForDevice(device))
        }
        return snapshots
    }

    fileprivate func handleMatchedDevice(_ device: IOHIDDevice) {
        onDeviceMatched?(snapshotForDevice(device))
    }

    fileprivate func handleRemovedDevice(_ device: IOHIDDevice) {
        onDeviceRemoved?(snapshotForDevice(device))
    }

    fileprivate func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let snapshot = snapshotForDevice(device)
        let usagePage = UInt32(IOHIDElementGetUsagePage(element))
        let usage = UInt32(IOHIDElementGetUsage(element))
        let integerValue = IOHIDValueGetIntegerValue(value)
        let stateKey = "\(snapshot.registryID ?? 0):\(usagePage):\(usage)"
        let phase = inferPhase(previousValue: lastValues[stateKey], currentValue: integerValue)
        lastValues[stateKey] = integerValue

        let rawEvent = HIDRawEvent(
            timestamp: iso8601Now(),
            snapshot: snapshot,
            usagePage: usagePage,
            usage: usage,
            integerValue: integerValue,
            phase: phase,
            eventName: hidUsageName(usagePage: usagePage, usage: usage)
        )

        onRawEvent?(rawEvent)
        gestureDetector.handleHIDEvent(
            snapshot: snapshot,
            usagePage: usagePage,
            usage: usage,
            integerValue: integerValue
        )
    }
}

private final class GestureDetector: @unchecked Sendable {
    var onGesture: (GestureEvent) -> Void

    private let multiClickWindow: TimeInterval
    private let holdThreshold: TimeInterval

    private var volumeUpIsPressed = false
    private var volumeUpHoldTriggered = false
    private var volumeUpHoldTimer: Timer?
    private var volumeUpClickCount = 0
    private var volumeUpCommitTimer: Timer?
    private var volumeUpSourceSnapshot: DeviceSnapshot?

    private var volumeDownIsPressed = false
    private var volumeDownHoldTriggered = false
    private var volumeDownHoldTimer: Timer?
    private var volumeDownClickCount = 0
    private var volumeDownCommitTimer: Timer?
    private var volumeDownSourceSnapshot: DeviceSnapshot?

    private var centerIsPressed = false
    private var centerHoldTriggered = false
    private var centerClickCount = 0
    private var centerHoldTimer: Timer?
    private var centerCommitTimer: Timer?
    private var centerSourceSnapshot: DeviceSnapshot?

    init(multiClickWindow: TimeInterval, holdThreshold: TimeInterval) {
        self.multiClickWindow = multiClickWindow
        self.holdThreshold = holdThreshold
        self.onGesture = { _ in }
    }

    func handleHIDEvent(snapshot: DeviceSnapshot, usagePage: UInt32, usage: UInt32, integerValue: Int) {
        guard usagePage == 12 else {
            return
        }

        switch usage {
        case 0x00E9:
            handleVolumeUp(integerValue: integerValue, snapshot: snapshot, usagePage: usagePage, usage: usage)
        case 0x00EA:
            handleVolumeDown(integerValue: integerValue, snapshot: snapshot, usagePage: usagePage, usage: usage)
        case 0x00B5 where integerValue > 0:
            resetCenterTracking()
            emitGesture(.centerDouble, snapshot: snapshot, usagePage: usagePage, usage: usage, integerValue: 2, note: "derived from HID next-track usage")
        case 0x00B6 where integerValue > 0:
            resetCenterTracking()
            emitGesture(.centerTriple, snapshot: snapshot, usagePage: usagePage, usage: usage, integerValue: 3, note: "derived from HID previous-track usage")
        case 0x00CD:
            handleCenterButton(snapshot: snapshot, usagePage: usagePage, usage: usage, integerValue: integerValue)
        default:
            break
        }
    }

    private func handleVolumeUp(integerValue: Int, snapshot: DeviceSnapshot, usagePage: UInt32, usage: UInt32) {
        volumeUpSourceSnapshot = snapshot

        if integerValue > 0 {
            volumeUpIsPressed = true
            volumeUpHoldTriggered = false
            volumeUpHoldTimer?.invalidate()
            volumeUpHoldTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
                self?.fireVolumeUpHold(usagePage: usagePage, usage: usage)
            }
            return
        }

        volumeUpHoldTimer?.invalidate()
        volumeUpHoldTimer = nil

        guard volumeUpIsPressed else {
            return
        }

        volumeUpIsPressed = false
        if volumeUpHoldTriggered {
            volumeUpHoldTriggered = false
            return
        }

        volumeUpClickCount += 1
        volumeUpCommitTimer?.invalidate()
        volumeUpCommitTimer = Timer.scheduledTimer(withTimeInterval: multiClickWindow, repeats: false) { [weak self] _ in
            self?.commitVolumeUpClicks(usagePage: usagePage, usage: usage)
        }
    }

    private func fireVolumeUpHold(usagePage: UInt32, usage: UInt32) {
        guard volumeUpIsPressed, !volumeUpHoldTriggered else {
            return
        }

        volumeUpHoldTriggered = true
        volumeUpClickCount = 0
        volumeUpCommitTimer?.invalidate()
        volumeUpCommitTimer = nil
        emitGesture(.volumeUpHold, snapshot: volumeUpSourceSnapshot, usagePage: usagePage, usage: usage, integerValue: 1, note: "derived from volume-button hold timing")
    }

    private func commitVolumeUpClicks(usagePage: UInt32, usage: UInt32) {
        defer {
            volumeUpClickCount = 0
            volumeUpCommitTimer = nil
        }

        guard volumeUpClickCount > 0 else {
            return
        }

        let gesture: GestureKind
        let integerValue: Int
        switch volumeUpClickCount {
        case 1:
            gesture = .volumeUp
            integerValue = 1
        case 2:
            gesture = .volumeUpDouble
            integerValue = 2
        default:
            gesture = .volumeUpTriple
            integerValue = volumeUpClickCount
        }

        emitGesture(gesture, snapshot: volumeUpSourceSnapshot, usagePage: usagePage, usage: usage, integerValue: integerValue, note: "derived from volume-up click timing")
    }

    private func handleVolumeDown(integerValue: Int, snapshot: DeviceSnapshot, usagePage: UInt32, usage: UInt32) {
        volumeDownSourceSnapshot = snapshot

        if integerValue > 0 {
            volumeDownIsPressed = true
            volumeDownHoldTriggered = false
            volumeDownHoldTimer?.invalidate()
            volumeDownHoldTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
                self?.fireVolumeDownHold(usagePage: usagePage, usage: usage)
            }
            return
        }

        volumeDownHoldTimer?.invalidate()
        volumeDownHoldTimer = nil

        guard volumeDownIsPressed else {
            return
        }

        volumeDownIsPressed = false
        if volumeDownHoldTriggered {
            volumeDownHoldTriggered = false
            return
        }

        volumeDownClickCount += 1
        volumeDownCommitTimer?.invalidate()
        volumeDownCommitTimer = Timer.scheduledTimer(withTimeInterval: multiClickWindow, repeats: false) { [weak self] _ in
            self?.commitVolumeDownClicks(usagePage: usagePage, usage: usage)
        }
    }

    private func fireVolumeDownHold(usagePage: UInt32, usage: UInt32) {
        guard volumeDownIsPressed, !volumeDownHoldTriggered else {
            return
        }

        volumeDownHoldTriggered = true
        volumeDownClickCount = 0
        volumeDownCommitTimer?.invalidate()
        volumeDownCommitTimer = nil
        emitGesture(.volumeDownHold, snapshot: volumeDownSourceSnapshot, usagePage: usagePage, usage: usage, integerValue: 1, note: "derived from volume-button hold timing")
    }

    private func commitVolumeDownClicks(usagePage: UInt32, usage: UInt32) {
        defer {
            volumeDownClickCount = 0
            volumeDownCommitTimer = nil
        }

        guard volumeDownClickCount > 0 else {
            return
        }

        let gesture: GestureKind
        let integerValue: Int
        switch volumeDownClickCount {
        case 1:
            gesture = .volumeDown
            integerValue = 1
        case 2:
            gesture = .volumeDownDouble
            integerValue = 2
        default:
            gesture = .volumeDownTriple
            integerValue = volumeDownClickCount
        }

        emitGesture(gesture, snapshot: volumeDownSourceSnapshot, usagePage: usagePage, usage: usage, integerValue: integerValue, note: "derived from volume-down click timing")
    }

    private func handleCenterButton(snapshot: DeviceSnapshot, usagePage: UInt32, usage: UInt32, integerValue: Int) {
        centerSourceSnapshot = snapshot

        if integerValue > 0 {
            centerIsPressed = true
            centerHoldTriggered = false
            centerHoldTimer?.invalidate()
            centerHoldTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
                self?.fireCenterHold(usagePage: usagePage, usage: usage)
            }
            return
        }

        centerHoldTimer?.invalidate()
        centerHoldTimer = nil

        guard centerIsPressed else {
            return
        }

        centerIsPressed = false
        if centerHoldTriggered {
            centerHoldTriggered = false
            return
        }

        centerClickCount += 1
        centerCommitTimer?.invalidate()
        centerCommitTimer = Timer.scheduledTimer(withTimeInterval: multiClickWindow, repeats: false) { [weak self] _ in
            self?.commitCenterClicks(usagePage: usagePage, usage: usage)
        }
    }

    private func fireCenterHold(usagePage: UInt32, usage: UInt32) {
        guard centerIsPressed, !centerHoldTriggered else {
            return
        }

        centerHoldTriggered = true
        centerClickCount = 0
        centerCommitTimer?.invalidate()
        centerCommitTimer = nil
        emitGesture(.centerHold, snapshot: centerSourceSnapshot, usagePage: usagePage, usage: usage, integerValue: 1, note: "derived from center-button hold timing")
    }

    private func commitCenterClicks(usagePage: UInt32, usage: UInt32) {
        defer {
            centerClickCount = 0
            centerCommitTimer = nil
        }

        guard centerClickCount > 0 else {
            return
        }

        let gesture: GestureKind
        let integerValue: Int
        switch centerClickCount {
        case 1:
            gesture = .centerSingle
            integerValue = 1
        case 2:
            gesture = .centerDouble
            integerValue = 2
        default:
            gesture = .centerTriple
            integerValue = centerClickCount
        }

        emitGesture(gesture, snapshot: centerSourceSnapshot, usagePage: usagePage, usage: usage, integerValue: integerValue, note: "derived from center-button click timing")
    }

    private func resetCenterTracking() {
        centerIsPressed = false
        centerHoldTriggered = false
        centerClickCount = 0
        centerHoldTimer?.invalidate()
        centerHoldTimer = nil
        centerCommitTimer?.invalidate()
        centerCommitTimer = nil
    }

    private func emitGesture(
        _ gesture: GestureKind,
        snapshot: DeviceSnapshot?,
        usagePage: UInt32?,
        usage: UInt32?,
        integerValue: Int,
        note: String
    ) {
        onGesture(
            GestureEvent(
                timestamp: iso8601Now(),
                gesture: gesture,
                snapshot: snapshot,
                usagePage: usagePage,
                usage: usage,
                integerValue: integerValue,
                note: note
            )
        )
    }
}

nonisolated(unsafe) private let earPodsDeviceMatchingCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else {
        return
    }

    let listener = Unmanaged<EarPodsHIDListener>.fromOpaque(context).takeUnretainedValue()
    listener.handleMatchedDevice(device)
}

nonisolated(unsafe) private let earPodsDeviceRemovalCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else {
        return
    }

    let listener = Unmanaged<EarPodsHIDListener>.fromOpaque(context).takeUnretainedValue()
    listener.handleRemovedDevice(device)
}

nonisolated(unsafe) private let earPodsInputValueCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else {
        return
    }

    let listener = Unmanaged<EarPodsHIDListener>.fromOpaque(context).takeUnretainedValue()
    listener.handleInputValue(value)
}

private func snapshotForDevice(_ device: IOHIDDevice) -> DeviceSnapshot {
    let service = IOHIDDeviceGetService(device)
    var registryID: UInt64 = 0
    if service != 0 {
        let result = IORegistryEntryGetRegistryEntryID(service, &registryID)
        if result != KERN_SUCCESS {
            registryID = 0
        }
    }

    return DeviceSnapshot(
        product: hidStringProperty(device, key: kIOHIDProductKey as CFString),
        transport: hidStringProperty(device, key: kIOHIDTransportKey as CFString),
        vendorID: hidUInt32Property(device, key: kIOHIDVendorIDKey as CFString),
        productID: hidUInt32Property(device, key: kIOHIDProductIDKey as CFString),
        registryID: registryID == 0 ? nil : registryID,
        usagePage: hidUInt32Property(device, key: kIOHIDPrimaryUsagePageKey as CFString),
        usage: hidUInt32Property(device, key: kIOHIDPrimaryUsageKey as CFString)
    )
}

private func hidStringProperty(_ device: IOHIDDevice, key: CFString) -> String? {
    guard let property = IOHIDDeviceGetProperty(device, key) else {
        return nil
    }

    if let string = property as? String {
        return string
    }
    if let number = property as? NSNumber {
        return number.stringValue
    }
    return nil
}

private func hidUInt32Property(_ device: IOHIDDevice, key: CFString) -> UInt32? {
    guard let property = IOHIDDeviceGetProperty(device, key) else {
        return nil
    }

    if let number = property as? NSNumber {
        return number.uint32Value
    }
    if let string = property as? String, let value = UInt32(string) {
        return value
    }
    return nil
}

private func inferPhase(previousValue: Int?, currentValue: Int) -> String {
    if currentValue == 0 {
        return "up"
    }
    guard let previousValue else {
        return "down"
    }
    if previousValue == 0 {
        return "down"
    }
    if previousValue == currentValue {
        return "repeat"
    }
    return "raw"
}

private func hidUsageName(usagePage: UInt32, usage: UInt32) -> String? {
    guard usagePage == 12 else {
        return nil
    }

    switch usage {
    case 0x00E2: return "mute"
    case 0x00E9: return "volume-increment"
    case 0x00EA: return "volume-decrement"
    case 0x00B0: return "play"
    case 0x00B1: return "pause"
    case 0x00CD: return "play-pause"
    case 0x00B5: return "scan-next-track"
    case 0x00B6: return "scan-previous-track"
    case 0x0223: return "ac-home"
    default: return nil
    }
}

private func hex32(_ value: UInt32) -> String {
    String(format: "0x%04x", value)
}

private func hex64(_ value: UInt64) -> String {
    String(format: "0x%llx", value)
}

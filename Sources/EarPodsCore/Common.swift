import Foundation

public struct EventRecord: Codable {
    public let timestamp: String
    public let recordType: String
    public let mode: String
    public let product: String?
    public let transport: String?
    public let vendorID: UInt32?
    public let productID: UInt32?
    public let registryID: UInt64?
    public let usagePage: UInt32?
    public let usage: UInt32?
    public let integerValue: Int
    public let phase: String
    public let eventName: String?
    public let gesture: String?
    public let rawData1: Int?
    public let rawSubtype: Int?
    public let note: String?
    public let itemID: String?
    public let itemTitle: String?
    public let itemSymbol: String?
    public let selectedIndex: Int?

    public init(
        timestamp: String,
        recordType: String,
        mode: String,
        product: String?,
        transport: String?,
        vendorID: UInt32?,
        productID: UInt32?,
        registryID: UInt64?,
        usagePage: UInt32?,
        usage: UInt32?,
        integerValue: Int,
        phase: String,
        eventName: String?,
        gesture: String?,
        rawData1: Int?,
        rawSubtype: Int?,
        note: String?,
        itemID: String? = nil,
        itemTitle: String? = nil,
        itemSymbol: String? = nil,
        selectedIndex: Int? = nil
    ) {
        self.timestamp = timestamp
        self.recordType = recordType
        self.mode = mode
        self.product = product
        self.transport = transport
        self.vendorID = vendorID
        self.productID = productID
        self.registryID = registryID
        self.usagePage = usagePage
        self.usage = usage
        self.integerValue = integerValue
        self.phase = phase
        self.eventName = eventName
        self.gesture = gesture
        self.rawData1 = rawData1
        self.rawSubtype = rawSubtype
        self.note = note
        self.itemID = itemID
        self.itemTitle = itemTitle
        self.itemSymbol = itemSymbol
        self.selectedIndex = selectedIndex
    }
}

public final class NDJSONLogger {
    public let path: String
    private let fileHandle: FileHandle
    private let encoder: JSONEncoder

    public init(path: String) throws {
        let normalizedPath = normalizePath(path)
        self.path = normalizedPath

        let url = URL(fileURLWithPath: normalizedPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            throw NSError(
                domain: "EarPodsCore.NDJSONLogger",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to open log file at \(url.path)"]
            )
        }

        self.fileHandle = handle
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.fileHandle.seekToEndOfFile()
    }

    deinit {
        try? fileHandle.close()
    }

    public func write(_ record: EventRecord) {
        do {
            let data = try encoder.encode(record)
            fileHandle.write(data)
            fileHandle.write(Data([0x0A]))
        } catch {
            fputs("Failed to write log entry: \(error.localizedDescription)\n", stderr)
        }
    }

    public func close() {
        try? fileHandle.close()
    }
}

public func normalizePath(_ path: String) -> String {
    let expandedPath = NSString(string: path).expandingTildeInPath
    if expandedPath.hasPrefix("/") {
        return expandedPath
    }

    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(expandedPath)
        .path
}

public func iso8601Now() -> String {
    ISO8601DateFormatter().string(from: Date())
}

public func printHeader(title: String) {
    print(title)
    print(String(repeating: "=", count: title.count))
}

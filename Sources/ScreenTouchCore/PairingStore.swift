import Foundation

public struct PairingStore {
    public let fileURL: URL

    public init(fileURL: URL = PairingStore.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenTouch Mapper", isDirectory: true)
            .appendingPathComponent("pairings.json")
    }

    /// A missing or unreadable file gives an empty list.
    public func load() -> [Pairing] {
        guard let data = try? Data(contentsOf: fileURL),
              let pairings = try? JSONDecoder().decode([Pairing].self, from: data)
        else { return [] }
        return pairings
    }

    public func save(_ pairings: [Pairing]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(pairings).write(to: fileURL, options: .atomic)
    }
}

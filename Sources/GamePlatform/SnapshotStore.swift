import Foundation
import GameSimulation

public protocol SnapshotStore {
    @discardableResult
    func save(snapshot: WorldSnapshot, name: String) throws -> URL
    func load(name: String) throws -> WorldSnapshot
}

public enum SnapshotStoreError: Error {
    case missingFile(URL)
}

public final class FileSnapshotStore: SnapshotStore {
    public let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    @discardableResult
    public func save(snapshot: WorldSnapshot, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(for: name)
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic])
        return url
    }

    public func load(name: String) throws -> WorldSnapshot {
        let url = fileURL(for: name)
        guard FileManager.default.fileExists(atPath: url.path()) else {
            throw SnapshotStoreError.missingFile(url)
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(WorldSnapshot.self, from: data)
    }

    private func fileURL(for name: String) -> URL {
        directory.appendingPathComponent("\(name).json")
    }
}

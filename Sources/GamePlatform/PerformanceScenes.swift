import Foundation

public struct PerformanceSceneDefinition: Codable, Hashable, Sendable {
    public var id: String
    public var description: String
    public var ticks: Int

    public init(id: String, description: String, ticks: Int) {
        self.id = id
        self.description = description
        self.ticks = ticks
    }
}

public struct PerformanceSceneCatalog {
    public init() {}

    public func load(from url: URL) throws -> [PerformanceSceneDefinition] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([PerformanceSceneDefinition].self, from: data)
    }
}

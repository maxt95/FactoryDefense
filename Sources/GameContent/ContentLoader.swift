import Foundation

public struct ContentLoader {
    public enum LoaderError: Error {
        case missingFile(String)
        case decodeFailure(file: String, error: Error)
    }

    public init() {}

    public func loadBundle(from directory: URL) throws -> GameContentBundle {
        let items: [ItemDef] = try decode("items.json", in: directory)
        let recipes: [RecipeDef] = try decode("recipes.json", in: directory)
        let turrets: [TurretDef] = try decode("turrets.json", in: directory)
        let enemies: [EnemyDef] = try decode("enemies.json", in: directory)
        let waves: [WaveDef] = try decode("waves.json", in: directory)
        let techNodes: [TechNodeDef] = try decode("tech_nodes.json", in: directory)

        return GameContentBundle(
            items: items,
            recipes: recipes,
            turrets: turrets,
            enemies: enemies,
            waves: waves,
            techNodes: techNodes
        )
    }

    private func decode<T: Decodable>(_ file: String, in directory: URL) throws -> T {
        let url = directory.appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: url.path()) else {
            throw LoaderError.missingFile(file)
        }

        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LoaderError.decodeFailure(file: file, error: error)
        }
    }
}

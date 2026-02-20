import XCTest
@testable import GameContent

final class ContentLoaderTests: XCTestCase {
    func testLoaderDecodesOrePatchesConfig() throws {
        let bundle = try ContentLoader().loadBundle(from: bootstrapContentURL())

        XCTAssertEqual(bundle.orePatches.rings.first?.index, 0)
        XCTAssertFalse(bundle.orePatches.rings.isEmpty)
        XCTAssertFalse(bundle.orePatches.oreTypes.isEmpty)
    }

    func testLoaderRequiresOrePatchesFile() throws {
        let fileManager = FileManager.default
        let source = bootstrapContentURL()
        let destination = source
            .deletingLastPathComponent()
            .appendingPathComponent("tmp-content-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: destination) }

        let files = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for fileURL in files where fileURL.pathExtension == "json" && fileURL.lastPathComponent != "ore_patches.json" {
            try fileManager.copyItem(at: fileURL, to: destination.appendingPathComponent(fileURL.lastPathComponent))
        }

        do {
            _ = try ContentLoader().loadBundle(from: destination)
            XCTFail("Expected missing ore_patches.json to throw")
        } catch let error as ContentLoader.LoaderError {
            switch error {
            case .missingFile(let name):
                XCTAssertEqual(name, "ore_patches.json")
            case .decodeFailure:
                XCTFail("Expected missingFile error, got decodeFailure")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    private func bootstrapContentURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Content/bootstrap")
    }
}

import XCTest
@testable import GameRendering

final class ShaderVariantTests: XCTestCase {
    func testVariantSelectionChangesByPreset() {
        let library = ShaderVariantLibrary()

        let mobile = library.activeVariant(for: .mobileBalanced, debugMode: .none)
        let mac = library.activeVariant(for: .macCinematic, debugMode: .none)

        XCTAssertNotEqual(mobile.enableEmission, mac.enableEmission)
        XCTAssertTrue(mac.enableFog)
    }
}

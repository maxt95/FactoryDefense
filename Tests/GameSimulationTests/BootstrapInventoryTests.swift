import XCTest
@testable import GameSimulation

final class BootstrapInventoryTests: XCTestCase {
    func testBootstrapProvidesStarterConstructionStock() {
        let inventory = WorldState.bootstrap().economy.inventories

        XCTAssertEqual(inventory["ore_iron", default: 0], 10)
        XCTAssertEqual(inventory["ammo_light", default: 0], 80)
        XCTAssertEqual(inventory["plate_iron", default: 0], 12)
        XCTAssertEqual(inventory["plate_copper", default: 0], 4)
        XCTAssertEqual(inventory["plate_steel", default: 0], 4)
        XCTAssertEqual(inventory["gear", default: 0], 6)
        XCTAssertEqual(inventory["circuit", default: 0], 4)
    }
}

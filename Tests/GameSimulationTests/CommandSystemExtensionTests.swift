import XCTest
@testable import GameSimulation
@testable import GameContent

final class CommandSystemExtensionTests: XCTestCase {
    func testRemoveStructureEmitsEventAndAppliesRefund() {
        var entities = EntityStore()
        let assemblerID = entities.spawnStructure(.assembler, at: GridPosition(x: 2, y: 2))
        let world = makeWorld(
            entities: entities,
            inventories: [
                "plate_iron": 0,
                "circuit": 0
            ]
        )

        let engine = SimulationEngine(worldState: world, systems: [CommandSystem()])
        engine.enqueue(PlayerCommand(tick: 0, actor: PlayerID(1), payload: .removeStructure(entityID: assemblerID)))
        let events = engine.step()

        XCTAssertNil(engine.worldState.entities.entity(id: assemblerID))
        XCTAssertTrue(events.contains(where: { $0.kind == EventKind.structureRemoved && $0.entity == assemblerID }))
        XCTAssertEqual(engine.worldState.economy.inventories["plate_iron"], 2)
        XCTAssertEqual(engine.worldState.economy.inventories["circuit"], 1)
    }

    func testPlaceConveyorCommandPlacesDirectionalConveyor() {
        let world = makeWorld(inventories: ["plate_iron": 5])
        let engine = SimulationEngine(worldState: world, systems: [CommandSystem()])
        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .placeConveyor(position: GridPosition(x: 3, y: 2), direction: .south)
            )
        )

        let events = engine.step()
        let placedID = events.first(where: { $0.kind == EventKind.structurePlaced })?.entity
        XCTAssertNotNil(placedID)
        let placed = placedID.flatMap { engine.worldState.entities.entity(id: $0) }
        XCTAssertEqual(placed?.structureType, .conveyor)
        XCTAssertEqual(placed?.rotation, .south)
    }

    func testPlacingProductionStructureSetsDefaultPinnedRecipe() {
        let world = makeWorld(inventories: ["plate_steel": 4])
        let engine = SimulationEngine(worldState: world, systems: [CommandSystem()])
        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .placeStructure(
                    BuildRequest(structure: .smelter, position: GridPosition(x: 4, y: 4))
                )
            )
        )

        let events = engine.step()
        let smelterID = events.first(where: { $0.kind == .structurePlaced })?.entity
        XCTAssertNotNil(smelterID)
        XCTAssertEqual(
            smelterID.flatMap { engine.worldState.economy.pinnedRecipeByStructure[$0] },
            StructureType.smelter.defaultRecipeID
        )
    }

    func testPinRecipeCommandStoresPinnedRecipe() {
        var entities = EntityStore()
        let smelterID = entities.spawnStructure(.smelter, at: GridPosition(x: 1, y: 1))
        let world = makeWorld(entities: entities)
        let engine = SimulationEngine(worldState: world, systems: [CommandSystem()])

        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .pinRecipe(entityID: smelterID, recipeID: "smelt_iron")
            )
        )
        _ = engine.step()

        XCTAssertEqual(engine.worldState.economy.pinnedRecipeByStructure[smelterID], "smelt_iron")
    }

    func testPinRecipeCommandRejectsUnsupportedRecipe() {
        var entities = EntityStore()
        let smelterID = entities.spawnStructure(.smelter, at: GridPosition(x: 1, y: 1))
        let world = makeWorld(entities: entities)
        let engine = SimulationEngine(worldState: world, systems: [CommandSystem()])

        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .pinRecipe(entityID: smelterID, recipeID: "craft_ammo_light")
            )
        )
        _ = engine.step()

        XCTAssertNil(engine.worldState.economy.pinnedRecipeByStructure[smelterID])
    }

    func testConfigureConveyorIOCommandStoresRouting() {
        var entities = EntityStore()
        let conveyorID = entities.spawnStructure(.conveyor, at: GridPosition(x: 1, y: 1), rotation: .east)
        let world = makeWorld(entities: entities)
        let engine = SimulationEngine(worldState: world, systems: [CommandSystem()])

        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .configureConveyorIO(entityID: conveyorID, inputDirection: .north, outputDirection: .east)
            )
        )
        _ = engine.step()

        XCTAssertEqual(
            engine.worldState.economy.conveyorIOByEntity[conveyorID],
            ConveyorIOConfig(inputDirection: .north, outputDirection: .east)
        )
    }

    private func makeWorld(
        entities: EntityStore = EntityStore(),
        inventories: [ItemID: Int] = [:]
    ) -> WorldState {
        var entities = entities
        let board = BoardState(
            width: 12,
            height: 8,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 11,
            spawnYMin: 0,
            spawnYMax: 0,
            blockedCells: [],
            restrictedCells: [],
            ramps: []
        )
        let hqID = entities.structures(of: .hq).first?.id
            ?? entities.spawnStructure(.hq, at: GridPosition(x: 11, y: 7))

        return WorldState(
            tick: 0,
            board: board,
            entities: entities,
            economy: EconomyState(
                inventories: inventories,
                storageSharedPoolByEntity: inventories.isEmpty ? [:] : [hqID: inventories]
            ),
            threat: ThreatState(),
            run: RunState(hqEntityID: hqID),
            combat: CombatState(
                basePosition: GridPosition(x: 0, y: 0),
                spawnEdgeX: 11,
                spawnYMin: 0,
                spawnYMax: 0
            )
        )
    }
}

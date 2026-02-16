import XCTest
@testable import GameSimulation

final class LogisticsRuntimeTests: XCTestCase {
    func testConveyorTransfersByRotationDirection() {
        var entities = EntityStore()
        let northTarget = entities.spawnStructure(.conveyor, at: GridPosition(x: 3, y: 2), rotation: .north)
        let eastTarget = entities.spawnStructure(.conveyor, at: GridPosition(x: 5, y: 4), rotation: .east)
        let southTarget = entities.spawnStructure(.conveyor, at: GridPosition(x: 3, y: 6), rotation: .south)
        let westTarget = entities.spawnStructure(.conveyor, at: GridPosition(x: 1, y: 4), rotation: .west)

        let northConveyor = entities.spawnStructure(.conveyor, at: GridPosition(x: 3, y: 3), rotation: .north)
        let eastConveyor = entities.spawnStructure(.conveyor, at: GridPosition(x: 4, y: 4), rotation: .east)
        let southConveyor = entities.spawnStructure(.conveyor, at: GridPosition(x: 3, y: 5), rotation: .south)
        let westConveyor = entities.spawnStructure(.conveyor, at: GridPosition(x: 2, y: 4), rotation: .west)

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(
                conveyorPayloadByEntity: [
                    northConveyor: ConveyorPayload(itemID: "plate_iron", progressTicks: 5),
                    eastConveyor: ConveyorPayload(itemID: "plate_copper", progressTicks: 5),
                    southConveyor: ConveyorPayload(itemID: "plate_steel", progressTicks: 5),
                    westConveyor: ConveyorPayload(itemID: "gear", progressTicks: 5)
                ]
            ),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(
            worldState: world,
            systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])]
        )
        _ = engine.step()

        XCTAssertEqual(engine.worldState.economy.conveyorPayloadByEntity[northTarget]?.itemID, "plate_iron")
        XCTAssertEqual(engine.worldState.economy.conveyorPayloadByEntity[eastTarget]?.itemID, "plate_copper")
        XCTAssertEqual(engine.worldState.economy.conveyorPayloadByEntity[southTarget]?.itemID, "plate_steel")
        XCTAssertEqual(engine.worldState.economy.conveyorPayloadByEntity[westTarget]?.itemID, "gear")
    }

    func testSplitterAlternatesOutputs() {
        var entities = EntityStore()
        let splitterID = entities.spawnStructure(.splitter, at: GridPosition(x: 3, y: 3), rotation: .east)
        let northTarget = entities.spawnStructure(.conveyor, at: GridPosition(x: 3, y: 2), rotation: .north)
        let southTarget = entities.spawnStructure(.conveyor, at: GridPosition(x: 3, y: 4), rotation: .south)

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(
            worldState: world,
            systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])]
        )

        engine.worldState.economy.conveyorPayloadByEntity[splitterID] = ConveyorPayload(itemID: "plate_iron", progressTicks: 5)
        _ = engine.step()
        XCTAssertEqual(engine.worldState.economy.conveyorPayloadByEntity[northTarget]?.itemID, "plate_iron")
        XCTAssertNil(engine.worldState.economy.conveyorPayloadByEntity[southTarget])

        engine.worldState.economy.conveyorPayloadByEntity[splitterID] = ConveyorPayload(itemID: "plate_iron", progressTicks: 5)
        _ = engine.step()
        XCTAssertEqual(engine.worldState.economy.conveyorPayloadByEntity[southTarget]?.itemID, "plate_iron")
    }

    func testSplitterRetriesAlternateWhenPreferredOutputBlocked() {
        var entities = EntityStore()
        let splitterID = entities.spawnStructure(.splitter, at: GridPosition(x: 3, y: 3), rotation: .east)
        let northTarget = entities.spawnStructure(.conveyor, at: GridPosition(x: 3, y: 2), rotation: .north)
        let southTarget = entities.spawnStructure(.conveyor, at: GridPosition(x: 3, y: 4), rotation: .south)

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(
                conveyorPayloadByEntity: [
                    splitterID: ConveyorPayload(itemID: "plate_iron", progressTicks: 5),
                    northTarget: ConveyorPayload(itemID: "gear", progressTicks: 0)
                ]
            ),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(
            worldState: world,
            systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])]
        )
        _ = engine.step()

        XCTAssertEqual(engine.worldState.economy.conveyorPayloadByEntity[northTarget]?.itemID, "gear")
        XCTAssertEqual(engine.worldState.economy.conveyorPayloadByEntity[southTarget]?.itemID, "plate_iron")
        XCTAssertEqual(engine.worldState.economy.splitterOutputToggleByEntity[splitterID], 1)
    }

    func testMergerFallsBackWhenPreferredInputEmpty() {
        var entities = EntityStore()
        let mergerID = entities.spawnStructure(.merger, at: GridPosition(x: 3, y: 3), rotation: .east)
        let southInput = entities.spawnStructure(.conveyor, at: GridPosition(x: 3, y: 4), rotation: .north)

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(
                conveyorPayloadByEntity: [
                    southInput: ConveyorPayload(itemID: "plate_copper", progressTicks: 5)
                ]
            ),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(
            worldState: world,
            systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])]
        )
        _ = engine.step()

        XCTAssertEqual(engine.worldState.economy.conveyorPayloadByEntity[mergerID]?.itemID, "plate_copper")
        XCTAssertNil(engine.worldState.economy.conveyorPayloadByEntity[southInput])
    }

    func testStorageSharedPoolAcceptsBidirectionalPortsFromBuildingDefs() {
        var entities = EntityStore()
        let storageID = entities.spawnStructure(.storage, at: GridPosition(x: 3, y: 3))
        let westIn = entities.spawnStructure(.conveyor, at: GridPosition(x: 2, y: 3), rotation: .east)
        let eastIn = entities.spawnStructure(.conveyor, at: GridPosition(x: 4, y: 3), rotation: .west)

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(
                conveyorPayloadByEntity: [
                    westIn: ConveyorPayload(itemID: "plate_iron", progressTicks: 5),
                    eastIn: ConveyorPayload(itemID: "plate_copper", progressTicks: 5)
                ]
            ),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(
            worldState: world,
            systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])]
        )
        _ = engine.step()

        XCTAssertEqual(engine.worldState.economy.storageSharedPoolByEntity[storageID]?["plate_iron", default: 0] ?? 0, 0)
        XCTAssertEqual(engine.worldState.economy.storageSharedPoolByEntity[storageID]?["plate_copper", default: 0] ?? 0, 0)
        XCTAssertNotNil(engine.worldState.economy.conveyorPayloadByEntity[westIn]?.itemID)
        XCTAssertNotNil(engine.worldState.economy.conveyorPayloadByEntity[eastIn]?.itemID)
    }

    func testAssemblerRejectsInputFromInvalidPortSide() {
        var entities = EntityStore()
        let assemblerID = entities.spawnStructure(.assembler, at: GridPosition(x: 4, y: 4))
        let southConveyor = entities.spawnStructure(.conveyor, at: GridPosition(x: 4, y: 5), rotation: .north)

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(
                conveyorPayloadByEntity: [
                    southConveyor: ConveyorPayload(itemID: "plate_iron", progressTicks: 5)
                ]
            ),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(
            worldState: world,
            systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])]
        )
        _ = engine.step()

        XCTAssertEqual(engine.worldState.economy.structureInputBuffers[assemblerID]?["plate_iron", default: 0] ?? 0, 0)
        XCTAssertEqual(engine.worldState.economy.conveyorPayloadByEntity[southConveyor]?.itemID, "plate_iron")
    }

    func testSmelterRejectsItemNotAllowedByPortFilter() {
        var entities = EntityStore()
        let smelterID = entities.spawnStructure(.smelter, at: GridPosition(x: 4, y: 4))
        let westConveyor = entities.spawnStructure(.conveyor, at: GridPosition(x: 3, y: 4), rotation: .east)

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(
                conveyorPayloadByEntity: [
                    westConveyor: ConveyorPayload(itemID: "gear", progressTicks: 5)
                ]
            ),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(
            worldState: world,
            systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])]
        )
        _ = engine.step()

        XCTAssertEqual(engine.worldState.economy.structureInputBuffers[smelterID]?["gear", default: 0] ?? 0, 0)
        XCTAssertEqual(engine.worldState.economy.conveyorPayloadByEntity[westConveyor]?.itemID, "gear")
    }

    func testConveyorCarriesOutputToNeighborInputBuffer() {
        var entities = EntityStore()
        _ = entities.spawnStructure(.powerPlant, at: GridPosition(x: 0, y: 1))
        _ = entities.spawnStructure(.smelter, at: GridPosition(x: 0, y: 0))
        _ = entities.spawnStructure(.conveyor, at: GridPosition(x: 1, y: 0), rotation: .east)
        let assemblerID = entities.spawnStructure(.assembler, at: GridPosition(x: 2, y: 0))

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(inventories: ["ore_iron": 2], structureInputBuffers: [assemblerID: [:]]),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(
            worldState: world,
            systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])]
        )

        _ = engine.run(ticks: 50)

        XCTAssertEqual(engine.worldState.economy.inventories["plate_iron", default: 0], 0)
        XCTAssertEqual(engine.worldState.economy.structureInputBuffers[assemblerID]?["plate_iron", default: 0], 1)
    }

    func testConnectedConveyorBackpressureBlocksOutputDrain() {
        var entities = EntityStore()
        _ = entities.spawnStructure(.powerPlant, at: GridPosition(x: 0, y: 1))
        let ammoModuleID = entities.spawnStructure(.ammoModule, at: GridPosition(x: 0, y: 0))
        let conveyorID = entities.spawnStructure(.conveyor, at: GridPosition(x: 1, y: 0))

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(inventories: ["plate_iron": 8]),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(
            worldState: world,
            systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])]
        )

        _ = engine.run(ticks: 200)

        XCTAssertEqual(engine.worldState.economy.inventories["ammo_light", default: 0], 0)
        XCTAssertEqual(engine.worldState.economy.structureOutputBuffers[ammoModuleID]?["ammo_light", default: 0], 7)
        XCTAssertEqual(engine.worldState.economy.conveyorPayloadByEntity[conveyorID]?.itemID, "ammo_light")
    }

    func testTurretConsumesLocalBufferAmmoBeforeGlobalInventory() {
        var entities = EntityStore()
        let turretID = entities.spawnStructure(.turretMount, at: GridPosition(x: 0, y: 0), turretDefID: "turret_mk1")
        let enemyID = entities.spawnEnemy(at: GridPosition(x: 2, y: 0), health: 100)

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(
                inventories: ["ammo_light": 1],
                structureInputBuffers: [turretID: ["ammo_light": 1]]
            ),
            threat: ThreatState(),
            run: RunState(),
            combat: CombatState(
                enemies: [
                    enemyID: EnemyRuntime(
                        id: enemyID,
                        archetype: .droneScout,
                        moveEveryTicks: 10,
                        baseDamage: 1,
                        rewardCurrency: 1
                    )
                ],
                basePosition: GridPosition(x: 0, y: 0),
                spawnEdgeX: 6,
                spawnYMin: 0,
                spawnYMax: 6
            )
        )

        let engine = SimulationEngine(worldState: world, systems: [CombatSystem()])
        let events = engine.step()

        XCTAssertTrue(events.contains(where: { $0.kind == .projectileFired }))
        XCTAssertEqual(engine.worldState.economy.inventories["ammo_light", default: 0], 1)
        XCTAssertEqual(engine.worldState.economy.structureInputBuffers[turretID]?["ammo_light", default: 0], 0)
    }

    func testMinerPlacementBindsRequestedPatch() {
        let board = BoardState(
            width: 12,
            height: 12,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 11,
            spawnYMin: 0,
            spawnYMax: 0,
            blockedCells: [],
            restrictedCells: [GridPosition(x: 4, y: 4)],
            ramps: []
        )
        let world = WorldState(
            tick: 0,
            board: board,
            entities: EntityStore(),
            orePatches: [
                OrePatch(
                    id: 7,
                    oreType: "ore_iron",
                    richness: .normal,
                    position: GridPosition(x: 4, y: 4),
                    totalOre: 500,
                    remainingOre: 500
                )
            ],
            economy: EconomyState(inventories: ["plate_iron": 6, "gear": 3]),
            threat: ThreatState(),
            run: RunState()
        )
        let engine = SimulationEngine(worldState: world, systems: [CommandSystem()])
        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .placeStructure(
                    BuildRequest(
                        structure: .miner,
                        position: GridPosition(x: 5, y: 4),
                        targetPatchID: 7
                    )
                )
            )
        )

        _ = engine.step()

        guard let miner = engine.worldState.entities.structures(of: .miner).first else {
            XCTFail("Expected miner placement to succeed")
            return
        }
        XCTAssertEqual(miner.boundPatchID, 7)
        XCTAssertEqual(engine.worldState.orePatches.first?.boundMinerID, miner.id)
    }

    func testMinerPlacementAutoBindsAdjacentPatchWhenTargetOmitted() {
        let board = BoardState(
            width: 12,
            height: 12,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 11,
            spawnYMin: 0,
            spawnYMax: 0,
            blockedCells: [],
            restrictedCells: [GridPosition(x: 4, y: 4)],
            ramps: []
        )
        let world = WorldState(
            tick: 0,
            board: board,
            entities: EntityStore(),
            orePatches: [
                OrePatch(
                    id: 7,
                    oreType: "ore_iron",
                    richness: .normal,
                    position: GridPosition(x: 4, y: 4),
                    totalOre: 500,
                    remainingOre: 500
                )
            ],
            economy: EconomyState(inventories: ["plate_iron": 6, "gear": 3]),
            threat: ThreatState(),
            run: RunState()
        )
        let engine = SimulationEngine(worldState: world, systems: [CommandSystem()])
        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .placeStructure(
                    BuildRequest(
                        structure: .miner,
                        position: GridPosition(x: 5, y: 4)
                    )
                )
            )
        )

        _ = engine.step()

        guard let miner = engine.worldState.entities.structures(of: .miner).first else {
            XCTFail("Expected miner placement to succeed")
            return
        }
        XCTAssertEqual(miner.boundPatchID, 7)
        XCTAssertEqual(engine.worldState.orePatches.first?.boundMinerID, miner.id)
    }

    func testMinerPlacementRejectsInvalidPatchTarget() {
        let board = BoardState(
            width: 12,
            height: 12,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 11,
            spawnYMin: 0,
            spawnYMax: 0,
            blockedCells: [],
            restrictedCells: [GridPosition(x: 4, y: 4)],
            ramps: []
        )
        let world = WorldState(
            tick: 0,
            board: board,
            entities: EntityStore(),
            orePatches: [
                OrePatch(
                    id: 13,
                    oreType: "ore_coal",
                    richness: .poor,
                    position: GridPosition(x: 4, y: 4),
                    totalOre: 150,
                    remainingOre: 150
                )
            ],
            economy: EconomyState(inventories: ["plate_iron": 6, "gear": 3]),
            threat: ThreatState(),
            run: RunState()
        )
        let engine = SimulationEngine(worldState: world, systems: [CommandSystem()])
        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .placeStructure(
                    BuildRequest(
                        structure: .miner,
                        position: GridPosition(x: 7, y: 4),
                        targetPatchID: 13
                    )
                )
            )
        )

        let events = engine.step()

        XCTAssertTrue(events.contains(where: {
            $0.kind == .placementRejected && $0.value == PlacementResult.invalidMinerPlacement.rawValue
        }))
        XCTAssertTrue(engine.worldState.entities.structures(of: .miner).isEmpty)
    }

    func testMinerExtractsFromBoundPatchAndEmitsDepletionEvents() {
        let board = BoardState(
            width: 12,
            height: 12,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 11,
            spawnYMin: 0,
            spawnYMax: 0,
            blockedCells: [],
            restrictedCells: [GridPosition(x: 4, y: 4)],
            ramps: []
        )
        var entities = EntityStore()
        _ = entities.spawnStructure(.powerPlant, at: GridPosition(x: 0, y: 1))
        let minerID = entities.spawnStructure(.miner, at: GridPosition(x: 5, y: 4), boundPatchID: 21)

        let world = WorldState(
            tick: 0,
            board: board,
            entities: entities,
            orePatches: [
                OrePatch(
                    id: 21,
                    oreType: "ore_iron",
                    richness: .poor,
                    position: GridPosition(x: 4, y: 4),
                    totalOre: 2,
                    remainingOre: 2,
                    boundMinerID: minerID
                )
            ],
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(
            worldState: world,
            systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])]
        )

        let events = engine.run(ticks: 45)

        XCTAssertEqual(engine.worldState.orePatches.first?.remainingOre, 0)
        XCTAssertEqual(engine.worldState.economy.structureOutputBuffers[minerID]?["ore_iron", default: 0], 2)
        XCTAssertEqual(engine.worldState.economy.inventories["ore_iron", default: 0], 0)
        XCTAssertEqual(engine.worldState.economy.powerDemand, 0)
        XCTAssertTrue(events.contains(where: { $0.kind == .patchExhausted && $0.entity == minerID && $0.value == 21 }))
        XCTAssertTrue(events.contains(where: { $0.kind == .minerIdled && $0.entity == minerID && $0.value == 21 }))
    }
}

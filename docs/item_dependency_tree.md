# Item Dependency Tree (Code-Driven)

This tree is derived from the runtime production logic:

- Recipe source: `Content/bootstrap/recipes.json`
- Recipe execution: `EconomySystem.runProduction` in `Sources/GameSimulation/Systems.swift`
- Producer structure mapping:
  - `Smelter`: `smelt_steel`, `smelt_iron`, `smelt_copper`
  - `Assembler`: `craft_turret_core`, `craft_wall_kit`, `craft_repair_kit`, `assemble_power_cell`, `etch_circuit`, `forge_gear`
  - `Ammo Module`: `craft_ammo_plasma`, `craft_ammo_heavy`, `craft_ammo_light`
- Raw ore source: miners extract `ore_iron`, `ore_copper`, `ore_coal` from ore patches.

## Building Node Costs (Placement Costs)

Source of truth: `StructureType.buildCosts` in `Sources/GameSimulation/SimulationTypes.swift`.

- `Miner`: 6 `plate_iron` + 3 `gear`
- `Smelter`: 4 `plate_steel`
- `Assembler`: 4 `plate_iron` + 2 `circuit`
- `Ammo Module`: 2 `circuit` + 2 `plate_steel`
- `Power Plant`: 2 `circuit` + 4 `plate_copper`
- `Conveyor`: 1 `plate_iron`
- `Splitter`: 1 `plate_iron`
- `Merger`: 1 `plate_iron`
- `Storage`: 3 `plate_steel` + 2 `gear`
- `Wall`: 1 `wall_kit`
- `Turret Mount`: 1 `turret_core` + 2 `plate_steel`

```text
ore_iron (ore patch)
└─ Miner [cost: 6 plate_iron + 3 gear] -> ore_iron
   └─ Smelter [cost: 4 plate_steel] (smelt_iron) -> plate_iron
      ├─ Assembler [cost: 4 plate_iron + 2 circuit] (forge_gear) -> gear
      │  ├─ Assembler (craft_wall_kit) -> wall_kit [needs plate_steel + gear]
      │  └─ Assembler (craft_turret_core) -> turret_core [needs plate_steel + circuit + gear]
      ├─ Smelter (smelt_steel) -> plate_steel [needs ore_coal]
      │  ├─ Assembler (craft_wall_kit) -> wall_kit [needs gear]
      │  ├─ Assembler (craft_turret_core) -> turret_core [needs circuit + gear]
      │  ├─ Assembler (craft_repair_kit) -> repair_kit [needs circuit]
      │  └─ Ammo Module [cost: 2 circuit + 2 plate_steel] (craft_ammo_heavy) -> ammo_heavy [needs ammo_light]
      └─ Ammo Module (craft_ammo_light) -> ammo_light
         └─ Ammo Module (craft_ammo_heavy) -> ammo_heavy [needs plate_steel]

ore_copper (ore patch)
└─ Miner [cost: 6 plate_iron + 3 gear] -> ore_copper
   └─ Smelter [cost: 4 plate_steel] (smelt_copper) -> plate_copper
      ├─ Assembler [cost: 4 plate_iron + 2 circuit] (etch_circuit) -> circuit [needs ore_coal]
      │  ├─ Assembler (assemble_power_cell) -> power_cell [needs plate_copper]
      │  │  └─ Ammo Module (craft_ammo_plasma) -> ammo_plasma [needs circuit]
      │  ├─ Assembler (craft_turret_core) -> turret_core [needs plate_steel + gear]
      │  └─ Assembler (craft_repair_kit) -> repair_kit [needs plate_steel]
      └─ Assembler (assemble_power_cell) -> power_cell [needs circuit]
         └─ Ammo Module (craft_ammo_plasma) -> ammo_plasma [needs circuit]

ore_coal (ore patch)
└─ Miner [cost: 6 plate_iron + 3 gear] -> ore_coal
   ├─ Smelter [cost: 4 plate_steel] (smelt_steel) -> plate_steel [needs plate_iron]
   │  ├─ Assembler (craft_wall_kit) -> wall_kit [needs gear]
   │  ├─ Assembler (craft_turret_core) -> turret_core [needs circuit + gear]
   │  ├─ Assembler (craft_repair_kit) -> repair_kit [needs circuit]
   │  └─ Ammo Module (craft_ammo_heavy) -> ammo_heavy [needs ammo_light]
   └─ Assembler [cost: 4 plate_iron + 2 circuit] (etch_circuit) -> circuit [needs plate_copper]
      ├─ Assembler (assemble_power_cell) -> power_cell [needs plate_copper]
      │  └─ Ammo Module (craft_ammo_plasma) -> ammo_plasma [needs circuit]
      ├─ Assembler (craft_turret_core) -> turret_core [needs plate_steel + gear]
      └─ Assembler (craft_repair_kit) -> repair_kit [needs plate_steel]
```

Reachable crafted items from the ore roots:

- `plate_iron`
- `plate_copper`
- `plate_steel`
- `gear`
- `circuit`
- `power_cell`
- `wall_kit`
- `turret_core`
- `ammo_light`
- `ammo_heavy`
- `ammo_plasma`
- `repair_kit`

## Is Starting Inventory Enough For A Sustaining Factory?

Starting inventory source: `Content/bootstrap/hq.json`.

Logistics constraints from runtime (`EconomySystem`):

- Items move only via adjacent output/input ports or belt nodes.
- `Storage` has bidirectional ports on **west/east**.
- So for "into storage and then out of storage", you need either:
  - direct adjacency on both sides of storage, or
  - at least belt links around storage.

Definitions used for this check:

- **Core sustaining factory** = `Power Plant + Miner + Smelter + Assembler`
- **Core + dedicated storage I/O** = Core + `Storage` + `2x Conveyor`  
  (one conservative transport link in, one out; direct-adjacent layouts can reduce belt count).
- **Core + Ammo** = Core + `Ammo Module`.

Resource totals required:

- Core sustaining factory:
  - 2 `circuit` + 4 `plate_copper` (power plant)
  - 6 `plate_iron` + 3 `gear` (miner)
  - 4 `plate_steel` (smelter)
  - 4 `plate_iron` + 2 `circuit` (assembler)
  - **Total:** 4 `circuit`, 4 `plate_copper`, 10 `plate_iron`, 3 `gear`, 4 `plate_steel`
- Core + Ammo:
  - Core totals plus ammo module (2 `circuit` + 2 `plate_steel`)
  - **Total:** 6 `circuit`, 4 `plate_copper`, 10 `plate_iron`, 3 `gear`, 6 `plate_steel`
- Core + dedicated storage I/O:
  - Core totals plus storage (3 `plate_steel` + 2 `gear`) plus 2 conveyors (2 `plate_iron`)
  - **Total:** 4 `circuit`, 4 `plate_copper`, 12 `plate_iron`, 5 `gear`, 7 `plate_steel`

By difficulty:

- `easy` start = 5 circuit, 8 plate_copper, 18 plate_iron, 5 gear, 10 plate_steel
  - Core: **Yes**
  - Core + Ammo immediately: **No** (short 1 circuit), but can craft it after assembler is online.
  - Core + dedicated storage I/O immediately: **Yes** (exact on gear).
- `normal` start = 4 circuit, 6 plate_copper, 14 plate_iron, 4 gear, 8 plate_steel
  - Core: **Yes** (exact on circuits)
  - Core + Ammo immediately: **No** (short 2 circuits), but can craft it after assembler is online.
  - Core + dedicated storage I/O immediately: **No** (short 1 gear), but assembler can craft gear quickly.
- `hard` start = 2 circuit, 4 plate_copper, 10 plate_iron, 3 gear, 8 plate_steel
  - Core: **No** (short 2 circuits)
  - Core + dedicated storage I/O immediately: **No** (short 2 circuits, 2 gear, 2 plate_iron).
  - Practical implication: you can place power + miner + smelter, but not assembler; without assembler, circuits/gears cannot be manufactured, so full self-sustaining progression (including storage I/O loop) is blocked.

Power check (same source: `StructureType.powerDemand`):

- Core demand = 8, one power plant provides 12.
- Core + dedicated storage I/O demand = 10.
- Core + Ammo + dedicated storage I/O demand = 14, so it needs a second power plant or reduced powered logistics.

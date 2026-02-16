# Whitebox 3D Asset Strategy for Factory Defense

Last updated: 2026-02-16
Status: Implementation guide

## Context

The game has a fully scaffolded Metal render pipeline (render graph, pass nodes, PBR shader, quality presets, debug modes) but **zero actual geometry rendering**. All render pass nodes create encoders and immediately end them. There is no mesh loading, no vertex descriptor setup, no pipeline state, and no draw calls. Before any visual can appear on screen, the rendering infrastructure must be completed — regardless of how mesh data is sourced.

This document compares two approaches for creating whitebox 3D assets and recommends a path forward.

---

## Recommendation: Procedural Geometry (with future DCC migration path)

**Procedural geometry in Swift is the clear winner for the whitebox phase.** Here's why:

1. **Camera distance makes detail irrelevant.** The isometric camera sits at distance 28 with ~56-degree FOV. A 1-unit tile is ~50-80px on screen. Color-coded boxes with correct proportions are perfectly readable.

2. **The shader only supports position + normal.** No UVs, no textures, no materials. A DCC pipeline adds value when you need textured detailed meshes — the renderer can't display those yet.

3. **25 assets is small.** Each whitebox asset is 3-10 lines of primitive composition. The entire catalog is ~400 lines of Swift — less code than a robust Model I/O loading pipeline with error handling and caching.

4. **Grid-based placement maps perfectly to instanced procedural geometry.** `EntityStore` already groups entities by type. Generating instance buffers from `WorldState` is straightforward.

5. **No external tooling required.** No Blender, no asset files to manage/version/bundle, no coordinate system mismatches to debug.

6. **Future migration is clean.** Define a `MeshProvider` protocol. Both the procedural library and a future `ModelIOMeshLibrary` (loading USD/USDZ) conform to it. Assets migrate incrementally — swap one mesh at a time.

---

## Approach A: DCC Tool Pipeline (Blender → Metal) — For Later

Best saved for when production art begins. The recommended pipeline when that time comes:

- **Format:** glTF 2.0 / GLB as primary interchange — designed for runtime delivery, clear PBR metallic/roughness semantics, lighter tooling than USD. See `docs/prd/asset_pipeline.md` §3 for full format analysis.
- **Alternative:** USDC (binary USD) — Apple-native, valid for scene layout and Apple Preview validation. Remains useful for archival and multi-asset composition but is not the primary interchange format.
- **Loading:** `MDLAsset` + `MTKMesh` with `MTKModelIOVertexDescriptorFromMetal()` to bridge vertex layouts (for USD path). GLTFKit2 for glTF path.
- **Fallback:** OBJ if simplicity is needed (no scene hierarchy, but dead-simple for single meshes)

Key concerns for when this is built:
- Coordinate system: Blender default is Z-up, Metal/camera uses Y-up. USD export must set Forward=-Z, Up=Y
- Model at origin, 1 Blender unit = 1 game tile, apply all transforms before export
- Model I/O handles vertex re-layout to match `MTLVertexDescriptor` automatically

---

## Approach B: Procedural Geometry — Implementation Plan

### Phase 1: Rendering Infrastructure (prerequisite for any approach)

These changes are needed regardless of how mesh data is sourced.

**Files to modify:**

| File | Changes |
|------|---------|
| `Sources/GameRendering/Shaders/pbr.metal` | Add MVP transform via `InstanceUniforms` buffer, add `instance_id`, add per-instance `tintColor` |
| `Sources/GameRendering/Math.swift` | Add `simd_float4x4.translation()` factory method |
| `Sources/GameRendering/RenderTypes.swift` | Extend `RenderContext` to carry pipeline state + mesh/instance state; update `OpaquePBRNode` to encode real draw calls |
| `Sources/GameRendering/Renderer.swift` | Create `MTLRenderPipelineState`, `MTLDepthStencilState`, `MTLVertexDescriptor`, and mesh library at init |

**Shader changes (`pbr.metal`):**

The current shader passes position through untransformed and has no color. It needs:

```metal
struct InstanceUniforms {
    float4x4 modelViewProjection;
    float4x4 modelMatrix;
    half4 tintColor;
};

// VSOut must be extended to carry color
struct VSOut {
    float4 position [[position]];
    half3 normal;
    half4 color;
};

vertex VSOut pbr_vertex(
    VSIn in [[stage_in]],
    constant InstanceUniforms *instances [[buffer(1)]],
    uint iid [[instance_id]]
) {
    VSOut out;
    out.position = instances[iid].modelViewProjection * float4(in.position, 1.0);
    out.normal = normalize(in.normal);
    out.color = instances[iid].tintColor;
    return out;
}

fragment half4 pbr_fragment(VSOut in [[stage_in]]) {
    half3 baseColor = in.color.rgb;
    half3 lit = baseColor * (half3(0.2h) + max(in.normal.y, 0.0h) * half3(0.8h));
    return half4(lit, 1.0h);
}
```

**Vertex descriptor setup:**

```swift
func makeWhiteboxVertexDescriptor() -> MTLVertexDescriptor {
    let desc = MTLVertexDescriptor()
    // attribute(0): float3 position at offset 0 (12 bytes)
    desc.attributes[0].format = .float3
    desc.attributes[0].offset = 0
    desc.attributes[0].bufferIndex = 0
    // attribute(1): half3 normal at offset 12 (6 bytes)
    desc.attributes[1].format = .half3
    desc.attributes[1].offset = 12
    desc.attributes[1].bufferIndex = 0
    // stride: 20 bytes (2 bytes padding for 4-byte alignment)
    desc.layouts[0].stride = 20
    desc.layouts[0].stepRate = 1
    desc.layouts[0].stepFunction = .perVertex
    return desc
}
```

**GridPosition → world space mapping:**

```swift
// GridPosition.x → world X
// GridPosition.z (elevation) → world Y (up)
// GridPosition.y → world Z (depth)
```

This matches the camera's Y-up convention in `IsometricCamera`.

### Phase 2: Procedural Mesh Primitives

**New files to create in `Sources/GameRendering/`:**

| File | Purpose |
|------|---------|
| `Mesh/WhiteboxVertex.swift` | `PackedWhiteboxVertex` struct (12B position + 6B half3 normal + 2B pad = 20B stride), half-float packing utilities |
| `Mesh/MeshPrimitives.swift` | `BoxPrimitive`, `CylinderPrimitive`, `WedgePrimitive` generators producing vertex + index arrays with per-face normals |
| `Mesh/WhiteboxAssetBuilder.swift` | Composition API: combine primitives with local transforms, merge into single vertex/index buffer pair |
| `Mesh/WhiteboxMeshLibrary.swift` | `MeshID` → GPU buffers mapping, `MeshProvider` protocol for future DCC migration |
| `Mesh/WhiteboxAssetCatalog.swift` | All 25 asset definitions composed from primitives |
| `WhiteboxColors.swift` | Color palette: cool/neutral for player structures, warm/hot for enemies |

**Swift-side vertex struct mirroring the shader:**

```swift
struct PackedWhiteboxVertex {
    var px: Float; var py: Float; var pz: Float   // 12 bytes → float3
    var nx: UInt16; var ny: UInt16; var nz: UInt16 // 6 bytes → half3
    var _pad: UInt16 = 0                           // 2 bytes padding
}   // Total: 20 bytes stride

func packHalf(_ v: Float) -> UInt16 {
    Float16(v).bitPattern
}
```

**Primitive generators:** Each outputs `([PackedWhiteboxVertex], [UInt16])` with flat-shading normals.

- **BoxPrimitive:** 24 vertices (4 per face x 6 faces), 36 indices. Parameterized by half-extents. This is the workhorse — most structures are box compositions.
- **CylinderPrimitive:** ~32-48 vertices for 8-segment cylinder. For turret barrels, projectiles, drill heads.
- **WedgePrimitive:** 5 faces, ~18 vertices. For terrain ramps (z elevation transitions).

**Composition API:**

```swift
struct WhiteboxAssetBuilder {
    /// Add a primitive with a local transform (translation, rotation, scale).
    /// Transforms both positions (by model matrix) and normals (by normal matrix).
    mutating func add(
        vertices: [PackedWhiteboxVertex],
        indices: [UInt16],
        transform: simd_float4x4 = matrix_identity_float4x4
    )

    /// Merge all added parts into a single vertex/index buffer pair.
    func build(device: MTLDevice) -> (vertexBuffer: MTLBuffer, indexBuffer: MTLBuffer, indexCount: Int)?
}
```

**Asset composition examples:**

| Asset | Composition | Approx dimensions (half-extents) |
|-------|-------------|----------------------------------|
| Wall | Single box | (0.45, 0.5, 0.45) |
| Turret mount | Wide flat box + narrow tall box + medium box on top | base: (0.45, 0.1, 0.45), pillar: (0.15, 0.25, 0.15), housing: (0.25, 0.1, 0.25) |
| Miner | Box base + small cylinder on top | base: (0.4, 0.2, 0.4), drill: r=0.1, h=0.3 |
| Smelter | Box body + thin tall box (chimney) | body: (0.4, 0.3, 0.4), chimney: (0.08, 0.25, 0.08) |
| Assembler | Wider box with notch (two boxes) | (0.45, 0.25, 0.45) |
| Ammo module | Box with small box on side | (0.35, 0.3, 0.35) |
| Power plant | Tall box | (0.4, 0.4, 0.4) |
| Conveyor | Very flat box | (0.45, 0.05, 0.45) |
| Storage | Wide, low box | (0.45, 0.2, 0.45) |
| Swarmling | Small box | (0.15, 0.15, 0.15) |
| Drone scout | Flat box | (0.2, 0.08, 0.2) |
| Raider | Medium box | (0.2, 0.3, 0.2) |
| Breacher | Wide box | (0.3, 0.25, 0.3) |
| Artillery bug | Box + cylinder barrel | body: (0.25, 0.2, 0.25), barrel: r=0.06, h=0.3 |
| Overseer | Large box + small box on top | body: (0.35, 0.35, 0.35), head: (0.15, 0.15, 0.15) |
| Light projectile | Tiny box | (0.05, 0.05, 0.05) |
| Heavy projectile | Small box | (0.08, 0.08, 0.08) |
| Plasma projectile | Tiny box (distinct color) | (0.06, 0.06, 0.06) |
| Grid tile | Extremely flat box | (0.49, 0.02, 0.49) |
| Ramp | Wedge | width=1.0, height=1.0, depth=1.0 |
| Base core | Distinctive box | (0.45, 0.45, 0.45) |
| Resource node | Flattened irregular box | (0.3, 0.15, 0.3) |

### Phase 3: Instanced Rendering

**Per-instance data struct:**

```swift
struct InstanceData {
    var modelViewProjection: simd_float4x4  // 64 bytes
    var modelMatrix: simd_float4x4          // 64 bytes
    var color: SIMD4<Float16>               // 8 bytes
}   // 136 bytes per instance
```

**Strategy:** Group entities by `MeshID` (derived from `StructureType` / `EnemyArchetype`). Build one `MTLBuffer` of `InstanceData` per group per frame. One `drawIndexedPrimitives(instanceCount:)` call per group. For a typical game state with ~100-200 entities, this results in ~15-20 draw calls total (one per mesh type that has active instances).

Triple-buffer instance data buffers (using a semaphore or ring buffer) to avoid CPU/GPU contention.

**Draw call pattern:**

```swift
// For each mesh type with active instances:
encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)    // vertex data
encoder.setVertexBuffer(instanceGroup.buffer, offset: 0, index: 1) // per-instance data
encoder.drawIndexedPrimitives(
    type: .triangle,
    indexCount: mesh.indexCount,
    indexType: .uint16,
    indexBuffer: mesh.indexBuffer,
    indexBufferOffset: 0,
    instanceCount: instanceGroup.count
)
```

### Phase 4: Color Coding

Friend/foe distinction at a glance:

| Category | Color family | Rationale |
|----------|-------------|-----------|
| Player structures | Cool/neutral: grays, blues, greens, yellows | Non-threatening, functional feel |
| Enemies | Warm/hot: reds, oranges, purples | Danger, immediately distinguishable from structures |
| Terrain | Dark neutrals | Background, non-distracting |
| Projectiles | Bright/emissive: pale yellow, gold, cyan | High visibility against all backgrounds |

**Suggested palette:**

```swift
// Structures
wall        = (0.6, 0.6, 0.6)  // Gray
turretMount = (0.2, 0.5, 0.8)  // Blue
miner       = (0.8, 0.6, 0.2)  // Amber
smelter     = (0.9, 0.3, 0.1)  // Red-orange
assembler   = (0.3, 0.7, 0.3)  // Green
ammoModule  = (0.8, 0.2, 0.2)  // Red
powerPlant  = (0.9, 0.9, 0.2)  // Yellow
conveyor    = (0.5, 0.5, 0.7)  // Slate blue
storage     = (0.6, 0.4, 0.2)  // Brown

// Enemies (warm/hot spectrum)
swarmling    = (1.0, 0.2, 0.2)  // Bright red
droneScout   = (1.0, 0.5, 0.0)  // Orange
raider       = (0.8, 0.0, 0.3)  // Crimson
breacher     = (0.6, 0.0, 0.6)  // Purple
artilleryBug = (0.4, 0.0, 0.0)  // Dark red
overseer     = (0.3, 0.0, 0.5)  // Deep purple

// Projectiles
lightBallistic = (1.0, 1.0, 0.6)  // Pale yellow
heavyBallistic = (1.0, 0.8, 0.3)  // Gold
plasma         = (0.3, 0.8, 1.0)  // Cyan

// Terrain & special
gridTile     = (0.25, 0.25, 0.25)  // Dark gray
ramp         = (0.35, 0.30, 0.25)  // Warm dark gray
baseCore     = (0.2, 0.8, 0.9)    // Teal
resourceNode = (0.7, 0.5, 0.1)    // Gold-brown
```

Each of the 25 asset types gets a unique hue. Combined with distinct proportions, all types are instantly distinguishable from the isometric camera.

### Phase 5: Debug Visualizations

Leverage the existing `DebugVisualizationMode` enum to add:
- Grid-line overlay (thin line boxes at each tile boundary)
- Turret range circles (line-rendered or thin cylinder rings)
- Enemy path visualization (from spawn edge to base)
- Wireframe mode

---

## Future Migration Path (Procedural → DCC Assets)

> **Full production pipeline:** The complete DCC-to-runtime asset pipeline — including texture strategy, LOD generation, memory management, and distribution — is documented in `docs/prd/asset_pipeline.md`.

When production art is ready:

1. Define `MeshProvider` protocol:
   ```swift
   protocol MeshProvider {
       func mesh(for id: MeshID) -> (vertexBuffer: MTLBuffer, indexBuffer: MTLBuffer, indexCount: Int)?
   }
   ```
2. `WhiteboxMeshLibrary` already conforms to this protocol
3. Build `ModelIOMeshLibrary` that loads glTF (via GLTFKit2) or USDC/USDZ (via `MDLAsset` + `MTKMesh`)
4. Swap providers per-asset incrementally (real wall model + procedural enemies is fine)
5. Rendering code unchanged — only the data source changes

**DCC asset file organization (for when this phase begins):**
```
Assets/Whitebox/
  structures/wb_wall.usdc, wb_turret_mount.usdc, ...
  turrets/wb_turret_mk1.usdc, ...
  enemies/wb_swarmling.usdc, ...
  projectiles/wb_proj_light.usdc, ...
  terrain/wb_tile_flat.usdc, wb_tile_ramp.usdc
  misc/wb_base_core.usdc, wb_resource_node.usdc
```

---

## Production Art Pipeline Preview

This section bridges the whitebox phase to the full production asset pipeline. None of these apply during the current whitebox phase — they document decisions and conventions that take effect when the first DCC asset enters the project. See `docs/prd/asset_pipeline.md` for the complete pipeline design.

### Format Decision: glTF-First Pipeline

The DCC interchange format is **glTF 2.0 / GLB** (not USDC as originally suggested in Approach A above). glTF is designed for runtime delivery with clear PBR metallic/roughness semantics and lighter tooling requirements. USDC remains valid for scene layout composition, Apple Preview validation, and archival, but glTF is the primary format that feeds the asset compiler.

See `docs/prd/asset_pipeline.md` §3 for the full format comparison and decision rationale.

### Texture Compression (When PBR Textures Arrive)

- **Standardize on ASTC** for all Apple targets. iOS 18+ and macOS 15+ (Apple Silicon) natively support ASTC — no PVRTC or BC fallbacks needed.
- **ORM channel packing** (single texture, linear color space):
  - R = Ambient Occlusion
  - G = Roughness
  - B = Metallic
  - This is the glTF 2.0 / Khronos standard packing. Reduces texture fetches from 3 to 1 for material properties — critical for TBDR bandwidth on Apple GPUs.
- **Texture resolution ceiling:** 256×256 for standard 1×1 structures (50–80px on screen at isometric distance). 512×512 maximum for hero structures (HQ, Lab) with 2×2 footprints.
- **Generate mipmaps offline** for all textures — no runtime mipmap generation.

See `docs/prd/asset_pipeline.md` §6 for the full texture strategy including ASTC block size recommendations per texture class.

### LOD Generation

- **meshoptimizer** (MIT license, C library) for offline LOD generation when transitioning to DCC meshes.
- 2 LOD levels for standard structures, 2–3 for hero structures.
- Screen-size thresholds stored per LOD in asset metadata; quality preset drives LOD bias.
- **Not needed for the whitebox phase** — procedural geometry is already minimal-polygon.

See `docs/prd/asset_pipeline.md` §7 for LOD levels per asset category and selection criteria.

### iOS Memory Considerations

- **GPU-native compressed textures (ASTC) avoid transient RGBA8 decode spikes** — critical for iOS memory management where jetsam enforces dynamic termination limits.
- Placeholder LOD rendering during streaming keeps the scene populated while higher-detail assets load.
- Quality preset drives texture resolution cap and LOD bias to stay within device memory budgets.
- Must monitor and respond to memory warnings by evicting non-essential cached textures and LODs.

See `docs/prd/asset_pipeline.md` §8 for full memory budget tables per quality preset and Metal resource storage mode conventions.

### Asset Compiler Concept

When DCC assets arrive, a build-time Swift CLI tool validates and converts interchange files (glTF) into the engine-native runtime format. The compiler enforces:
- Coordinate system normalization (Y-up)
- Tangent basis computation (MikkTSpace)
- ORM texture packing validation
- ASTC compression with platform-specific block sizes
- LOD chain generation
- Mipmap generation
- Provenance metadata recording

**Not needed during the whitebox phase.** The compiler becomes necessary when the first DCC asset enters the pipeline.

See `docs/prd/asset_pipeline.md` §4 for the full compiler pipeline specification.

---

## Verification

After implementation, verify by:
1. `swift test` — all existing tests should still pass (render tests create resources but don't draw)
2. `swift run FactoryDefense` — the macOS app should show HQ-only bootstrap state at tick 0 (single HQ structure + Ring 0 ore patch markers; no pre-placed production/defense structures)
3. Run the prototype with `swift run FactoryDefensePrototype` and load the saved snapshot to verify the renderer can display a mid-game state with enemies and projectiles
4. Toggle `DebugVisualizationMode` values to verify debug rendering still works alongside whitebox geometry

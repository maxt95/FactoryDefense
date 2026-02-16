# Asset Pipeline PRD

**Version:** 1.0-draft
**Parent:** `docs/GAME_PRD_LIVING.md`
**Status:** Forward-looking design
**Last updated:** 2026-02-16

> **Core truth:** The asset pipeline transforms authored 3D content into GPU-ready runtime data. It must scale from the current whitebox phase (procedural geometry, no external assets) through full production art, targeting Apple-only platforms with an isometric camera where visual clarity beats fidelity.

**Companion docs:**
- [`../WHITEBOX_ASSET_STRATEGY.md`](../WHITEBOX_ASSET_STRATEGY.md) — current whitebox rendering approach and MeshProvider migration path
- [`combat_rendering_vfx.md`](combat_rendering_vfx.md) — instanced rendering pipeline, GPU particle system, TBDR optimization
- [`ore_patches_resource_nodes.md`](ore_patches_resource_nodes.md) — ore patch visual requirements and material conventions

---

## Table of Contents

1. [Overview & Design Intent](#1-overview--design-intent)
2. [Authoring Conventions](#2-authoring-conventions)
3. [Interchange Format Strategy](#3-interchange-format-strategy)
4. [Asset Compiler (Build-Time Tool)](#4-asset-compiler-build-time-tool)
5. [Runtime Format](#5-runtime-format)
6. [Texture Strategy](#6-texture-strategy)
7. [LOD Strategy](#7-lod-strategy)
8. [Memory & Streaming](#8-memory--streaming)
9. [Distribution & Packaging](#9-distribution--packaging)
10. [Tool Recommendations](#10-tool-recommendations)
11. [Provenance Tracking](#11-provenance-tracking)
12. [Integration with Existing Systems](#12-integration-with-existing-systems)
13. [Implementation Roadmap](#13-implementation-roadmap)
14. [Open Questions](#14-open-questions)

---

## 1. Overview & Design Intent

### 1.1 Two-Stage Model

The asset pipeline follows a two-stage architecture: DCC authoring produces interchange files, and a build-time asset compiler transforms them into engine-native runtime formats optimized for Metal.

```
┌──────────────┐    ┌───────────────────┐    ┌──────────────┐    ┌────────────────┐    ┌───────────────┐    ┌───────────────────┐    ┌─────────────────┐
│   Authoring  │───>│ Interchange Export │───>│Asset Compiler│───>│ Runtime Format │───>│   Packaging   │───>│ Runtime Streaming │───>│ Metal Resources │
│ (Blender,    │    │  (glTF 2.0 / GLB) │    │  (build-time │    │ (binary, GPU-  │    │ (app bundle / │    │ (mip streaming,  │    │ (buffers,       │
│  Substance)  │    │                   │    │   Swift CLI)  │    │  optimized)    │    │  Background   │    │  LOD swap,       │    │  textures,      │
└──────────────┘    └───────────────────┘    └──────────────┘    │               │    │  Assets)      │    │  placeholder)    │    │  pipeline       │
                                                                 └────────────────┘    └───────────────┘    └───────────────────┘    │  states)        │
                                                                                                                                    └─────────────────┘
```

### 1.2 Design Constraints

- **Pipeline must scale from whitebox (current) through stylized production art.** No external assets exist today; all rendering is procedural geometry in Swift.
- **Apple-only target simplifies format decisions.** No cross-GPU transcoding needed — ASTC compression works on all target hardware (iOS 18+, macOS 15+ Apple Silicon).
- **Isometric camera context.** Camera is distant (28 units). Entities are 50–80px on screen. Visual clarity > fidelity. 1000+ simultaneous entities.

### 1.3 Current State

The game uses procedural whitebox geometry (WHITEBOX_ASSET_STRATEGY.md). No DCC assets, no textures, no asset compiler. This PRD defines the full production pipeline that will be built incrementally as the game transitions from whitebox to production art.

---

## 2. Authoring Conventions

| Convention | Value | Rationale |
|---|---|---|
| Coordinate system | Y-up, right-handed | Matches `IsometricCamera` and Metal conventions |
| Units | 1 Blender unit = 1 game tile (grid cell) | Direct correspondence with `GridPosition` |
| Material model | PBR metallic/roughness (glTF 2.0 compatible) | Standard, well-tooled, matches planned shader evolution |
| Asset naming | `snake_case` matching `StructureType`/`EnemyArchetype` raw values | e.g., `turret_mk1.glb`, `swarmling.glb` |
| Skeleton joint naming | Deferred | No skeletal animation in v1 |
| Transforms | Apply all transforms before export | No scale/rotation baked into scene hierarchy |
| Origin | Asset origin at center-bottom of footprint | Aligns with grid placement anchor |

**Export checklist (Blender):**
1. Set scene to Y-up before export (Blender default is Z-up)
2. Apply all transforms (Ctrl+A → All Transforms)
3. Export as glTF 2.0 / GLB with metallic/roughness PBR
4. Verify 1 unit = 1 tile in the viewport

---

## 3. Interchange Format Strategy

### 3.1 Primary Interchange: glTF 2.0 / GLB

glTF 2.0 is the primary interchange format for all DCC-to-engine asset transfer.

**Rationale:**
- Designed for runtime delivery with clear PBR metallic/roughness semantics
- Blender exports natively with metallic/roughness PBR
- Single-file GLB is convenient for asset compiler input (geometry + materials + textures in one file)
- Industry standard with broad tooling support
- Lighter than USD for single-asset workflows

**Extensions policy:** Core spec only for v1. No Draco compression or KTX2 in interchange files — the asset compiler handles all compression.

### 3.2 Source-of-Truth Archive: USD/USDZ

USD/USDZ serves as the archival and scene-layout format:
- Complex multi-asset scene layout and composition
- Apple Preview / Quick Look validation
- Reality Composer Pro inspection
- **Not used at runtime** — always compiled to engine-native format via the asset compiler

### 3.3 FBX: Artist-Side Only

- Accept FBX from external artists; convert to glTF in the build pipeline
- Never ship FBX SDK in the runtime binary (licensing constraints)

### 3.4 Format Decision Table

| Criterion | glTF 2.0 / GLB | USD / USDZ | FBX | OBJ |
|---|---|---|---|---|
| **Pipeline role** | Primary interchange | Archive / scene layout | Artist handoff only | Legacy fallback |
| **PBR semantics** | Native metallic/roughness | Supported (UsdPreviewSurface) | Vendor-dependent | None |
| **Blender export** | Native, high quality | Good (via USD exporter) | Good | Good |
| **Apple tooling** | GLTFKit2 (3rd party) | Model I/O (native) | Model I/O (native) | Model I/O (native) |
| **Single-file option** | GLB | USDZ | Yes | No (separate .mtl) |
| **Runtime suitability** | Designed for runtime | Heavyweight for runtime | Not suitable | Too simple |
| **Licensing** | Open (Khronos) | Open (Pixar) | Autodesk SDK restrictions | Open |
| **Use in our pipeline** | Asset compiler input | Validation, archival | Convert to glTF on receipt | Not used |

---

## 4. Asset Compiler (Build-Time Tool)

A Swift CLI tool that processes interchange files into engine-native runtime format. **Not needed during the whitebox phase** — the compiler becomes necessary when the first DCC asset enters the pipeline.

### 4.1 Pipeline Steps

1. **Validate** mesh topology (manifold, no degenerate triangles)
2. **Triangulate** all polygons
3. **Compute tangent basis** (MikkTSpace algorithm)
4. **Normalize coordinate system** (enforce Y-up, right-handed)
5. **Reorder vertices** for GPU cache locality (meshoptimizer)
6. **Generate LOD chain** (2–3 levels per asset, see §7)
7. **Validate/enforce ORM texture packing** and color space metadata (see §6.2)
8. **Compress textures** to ASTC with platform-specific block sizes (see §6.1)
9. **Generate mipmaps** for all minified textures
10. **Emit per-LOD bounds** and screen-size thresholds
11. **Record provenance metadata** (source file, license, timestamp — see §11)
12. **Pack into platform-specific bundles**

### 4.2 Input/Output

- **Input:** glTF 2.0 / GLB files from DCC authoring
- **Output:** Custom binary format optimized for Metal buffer creation (see §5)
- **Sidecar:** JSON manifest with provenance, LOD metadata, and texture references

### 4.3 Build Integration

The asset compiler runs as either:
- A standalone script invoked manually or from CI
- An Xcode build phase (post-v1, when the catalog is large enough to warrant automation)

---

## 5. Runtime Format

A custom binary format optimized for Metal buffer creation. **Implementation deferred until the asset compiler is built.**

### 5.1 Design Goals

- **Zero-copy where possible** — buffer data is directly uploadable to Metal
- **Pre-triangulated** — no runtime tessellation
- **Quantized** — positions and normals use minimal precision for the isometric use case
- **Cache-ordered** — vertex order optimized for GPU vertex cache

### 5.2 Packet Structure

- **Mesh packet:** Vertex buffer (position + normal + UV + tangent) + index buffer + per-LOD index ranges + bounding box
- **Material packet:** Texture references + PBR parameters (metallic, roughness, base color factor) + blend mode
- **Versioned header** for forward compatibility

### 5.3 Streaming Support

The format supports chunk loading for future streaming:
- Geometry, materials, and textures are stored in separate sections
- Textures are split by mip level (stream high-res mips later)
- Placeholder LOD can render immediately while higher detail streams in

---

## 6. Texture Strategy

### 6.1 Compression

All target platforms support ASTC (iOS 18+ and macOS 15+ Apple Silicon). No PVRTC or BC format fallbacks needed.

| Texture Class | ASTC Block Size | Quality | Notes |
|---|---|---|---|
| Normal maps | 4×4 | High | Preserve tangent-space detail |
| Base color (hero assets) | 5×5 | Medium-high | Readable at isometric distance |
| Base color (tiling) | 6×6 | Medium | Larger surfaces, less visible detail |
| ORM packed | 6×6 | Medium | Linear data, less perceptual impact |
| UI textures | 4×4 | High | Sharp at screen resolution |
| Particle / VFX | 8×8 | Low | Small, fast-moving, alpha-blended |

### 6.2 PBR Texture Conventions

| Texture | Color Space | Channels | Convention |
|---|---|---|---|
| Base color | sRGB | RGB + optional Alpha | Standard albedo |
| Normal map | Linear | RG (tangent-space) | OpenGL convention (Y+ = up) |
| ORM packed | Linear | R=Occlusion, G=Roughness, B=Metallic | glTF 2.0 / Khronos standard packing |

**ORM packing** combines ambient occlusion, roughness, and metallic into a single texture:
- **R channel:** Ambient Occlusion
- **G channel:** Roughness
- **B channel:** Metallic

This reduces texture fetches from 3 to 1 for material properties — critical for TBDR bandwidth optimization on Apple GPUs. See `combat_rendering_vfx.md` §7.10 for TBDR considerations.

All textures must have **mipmaps generated offline** by the asset compiler. No runtime mipmap generation.

### 6.3 Resolution Budget (Isometric Context)

At camera distance 28, a 1-tile entity occupies approximately 50–80px on screen. Higher texture resolutions waste memory and bandwidth with zero visual payoff at this distance.

| Asset Category | Max Texture Size | Notes |
|---|---|---|
| Hero structures (HQ, Lab) | 512×512 | 2×2 footprint, most screen space |
| Standard structures | 256×256 | 1×1 footprint |
| Enemies | 128×128 | Small, many instances |
| Projectiles | 64×64 | Tiny, fast-moving |
| Terrain tiles | 256×256 (tiling) | Repeated across board |

---

## 7. LOD Strategy

### 7.1 Tool: meshoptimizer

meshoptimizer (MIT license, C library) handles LOD generation and vertex cache optimization. It integrates into the asset compiler as a build-time dependency.

### 7.2 LOD Levels by Asset Category

| Category | LOD0 | LOD1 | LOD2 | Notes |
|---|---|---|---|---|
| Hero structures | Full | 50% tris | 25% tris | 2–3 LODs |
| Standard structures | Full | 40% tris | — | 2 LODs sufficient |
| Enemies | Full | 50% tris | — | 2 LODs; LOD1 for distant hordes |
| Projectiles | Full only | — | — | Already tiny geometry |
| Terrain tiles | Full only | — | — | Fixed grid, no distance LOD |

### 7.3 Selection Criteria

- Screen-size thresholds stored per LOD in asset metadata
- Quality preset selects LOD bias: `mobileBalanced` uses LOD1 more aggressively
- **Silhouette preservation** is the priority for enemies — readability > polygon count at isometric scale

---

## 8. Memory & Streaming

### 8.1 iOS Memory Pressure

iOS enforces dynamic memory limits via jetsam. Termination thresholds vary by device and system conditions — there is no hard "safe" memory ceiling.

**Key constraints:**
- Must respond to memory warnings by evicting non-essential cached textures and LODs
- Avoid large transient allocations during loading — do **not** decode to uncompressed RGBA8; use GPU-native ASTC directly
- Use Xcode memory gauges and jetsam event reports to tune budgets per device class

### 8.2 Streaming Architecture (Future)

The asset format is designed for chunk loading:
- Separate geometry / materials / textures in storage
- Split textures by mip group (stream high-res mips later)
- Support placeholder LOD rendering during streaming

### 8.3 Memory Budgets by Quality Preset

Budgets are lower than typical 3D game recommendations because the isometric camera means less visible geometry and smaller on-screen asset sizes.

| Preset | Target Devices | Resident Texture Budget | Triangle Budget (visible) | Notes |
|---|---|---|---|---|
| mobileBalanced | Older iPhones/iPads | 150–300 MB | 300k–600k | Aggressive LODs, small textures |
| tabletHigh | Modern iPads | 300–600 MB | 600k–1.5M | ASTC everywhere, streaming |
| macCinematic | Apple Silicon Macs | 600 MB–1.5 GB | 1.5M–5M | Higher-res targets, more effects |

**Adaptive eviction:** LRU texture cache with preset-specific ceiling. On memory warning, drop to `mobileBalanced` ceilings and evict cached LODs.

### 8.4 Metal Resource Patterns

| Pattern | Use Case | Storage Mode |
|---|---|---|
| Staging upload | CPU → GPU texture/buffer transfer | `.shared` → blit → `.private` |
| Render intermediates | G-buffers, depth consumed within same pass | `.memoryless` |
| Streaming textures | Fast allocation/aliasing of streamed pages | `MTLHeap` with `.private` |
| Many-material scenes | Reduce CPU binding overhead | Argument buffers |
| Instance buffers | CPU writes, GPU reads each frame | `.shared` (triple-buffered) |
| Particle pool | GPU-only, no CPU readback | `.private` |

See `combat_rendering_vfx.md` §9.3 for buffer binding conventions and §7.10 for TBDR optimization notes.

---

## 9. Distribution & Packaging

### 9.1 App Bundle (v1)

All assets ship in the app bundle for v1:
- Whitebox phase = procedural geometry, no external asset files
- JSON content files already bundled via SPM `.process()`
- No download required at launch

### 9.2 Background Assets (Post-v1, When Asset Size Grows)

Apple designates On-Demand Resources (ODR) as legacy. The modern replacement is **Background Assets / Managed Background Assets**.

**Download policies:**
- **Essential:** Blocks launch until downloaded
- **Prefetch:** Downloaded in background before first play session
- **On-demand:** Lazy-loaded when the content area is accessed

**Implementation details:**
- Package with `ba-package` tool, Apple-hosted with included CDN capacity
- Must disclose download size and prompt user before first-launch downloads (App Review §2.3.12)
- Asset pack organization: core (essential) + expansion packs by content tier

### 9.3 Size Targets

| Category | Target | Rationale |
|---|---|---|
| Core app bundle | < 200 MB | App Store cellular download limit; target conservative |
| Per asset pack | < 512 MB | Manageable download size for background fetch |
| Total installed | < 2 GB | Reasonable for a mobile game |

---

## 10. Tool Recommendations

| Tool | Role | License | Integration Point |
|---|---|---|---|
| Blender | DCC: modeling, UV, rigging, animation, export | GPL (assets are yours) | Export glTF 2.0 / GLB |
| Substance 3D Painter/Designer | PBR texturing, ORM packing | Subscription | Export ORM-packed texture sets |
| meshoptimizer | LOD generation, vertex cache optimization | MIT | Asset compiler (build-time) |
| cgltf | glTF parsing (single-file C library) | MIT | Asset compiler (build-time) |
| Xcode GPU Frame Capture | Profiling, debugging | Included | Dev workflow |
| Metal System Trace | Timeline profiling CPU/GPU overlap | Included | Dev workflow |

**Not needed for this game:**
- SpeedTree, ZBrush, Houdini, Marmoset — overkill for isometric stylized game at this scale
- Megascans/Fab scanned assets — unlikely fit for stylized art direction

---

## 11. Provenance Tracking

All third-party assets must have metadata recorded in a JSON sidecar per asset:

| Field | Description | Example |
|---|---|---|
| Source | Marketplace, artist, or in-house | "In-house", "Fab marketplace" |
| License type | Fab Standard, custom, CC, etc. | "Fab Standard License" |
| Acquisition date | ISO 8601 date | "2026-03-15" |
| Project assignment | Which project/module uses the asset | "factory-defense/structures" |
| Original filename | Source file as received | "turret_mk1_v3.blend" |

**Fab Standard License notes:** Allows commercial use, modification, and distribution as incorporated into a product. Prohibits standalone redistribution of the asset.

The asset compiler reads and validates provenance sidecar files during processing and embeds a summary in the compiled output manifest.

---

## 12. Integration with Existing Systems

### 12.1 MeshProvider Protocol

The `MeshProvider` protocol (defined in WHITEBOX_ASSET_STRATEGY.md) is the boundary between asset sources and the renderer:

```
MeshProvider (protocol)
  ├── WhiteboxMeshLibrary (procedural) — conforms now
  └── ModelIOMeshLibrary (USD/glTF)    — conforms later
```

Assets migrate incrementally — swap one mesh at a time. The rendering code consumes `MeshProvider` output and requires no changes when the asset source changes.

### 12.2 Render Graph

Render graph pass nodes consume `MeshProvider` output. No pass node changes are needed for an asset source swap. The existing pass structure (depth prepass → opaque → transparent → post → UI) works for both procedural and DCC-sourced geometry.

### 12.3 Content JSON

Content JSON remains authoritative for all game data (stats, recipes, waves, tech nodes). The asset pipeline handles **visual representation only** — it does not affect simulation behavior.

### 12.4 Quality Presets

Quality presets (`mobileBalanced`, `tabletHigh`, `macCinematic`) drive:
- LOD bias (which LOD level is selected at a given screen size)
- Texture resolution caps (per §6.3)
- Particle budgets (per `combat_rendering_vfx.md` §10.3)
- Resident texture memory ceiling (per §8.3)

---

## 13. Implementation Roadmap

### Phase 0: Current State (Whitebox)

- Procedural geometry via `WhiteboxMeshLibrary`
- No textures, no DCC assets, no asset compiler
- All rendering via whitebox compute (current) → instanced primitives (planned, see `combat_rendering_vfx.md` Phase 4–7)

### Phase 1: Procedural Whitebox Complete (Milestone 3)

- Implement `MeshProvider` protocol + `WhiteboxMeshLibrary`
- Instanced rendering pipeline (`combat_rendering_vfx.md` Phases 4–7)
- Color-coded procedural meshes for all 25+ asset types
- No external asset dependencies

### Phase 2: Art Direction Established

- Define visual style guide (stylized? low-poly? painterly?)
- Create 1–2 hero assets in Blender as style targets
- Validate glTF export → Model I/O → Metal rendering path
- Establish ORM texture conventions with test assets
- Build `ModelIOMeshLibrary` conforming to `MeshProvider`

### Phase 3: Asset Compiler MVP

- Swift CLI tool: glTF input → validated/optimized binary output
- ASTC texture compression pipeline
- LOD generation via meshoptimizer
- Mipmap generation
- Integration into Xcode build phase or standalone script

### Phase 4: Production Art Pipeline

- Full asset catalog authored in Blender/Substance
- All structures, enemies, projectiles, terrain have production models
- Asset compiler processes full catalog per-platform
- LOD chains validated at isometric camera distance
- Memory budgets validated per quality preset on real devices

### Phase 5: Distribution (If Needed)

- Evaluate app bundle size post-production art
- If > 200 MB: implement Background Assets framework
- Split into core + expansion packs
- Add download UI and progress indicators

---

## 14. Open Questions

- Should the stylized art direction target low-poly (Factorio-esque) or more detailed (Mindustry-esque)?
- Will skeletal animation be needed for enemies, or sprite-sheet/flipbook/vertex animation?
- Should the asset compiler be a standalone CLI or integrated into Xcode build phases?
- At what app size threshold do we implement Background Assets?

---

## Changelog

- 2026-02-16: Initial draft — full asset pipeline design from authoring through distribution.

#include <metal_stdlib>
using namespace metal;

struct WhiteboxUniforms {
    uint viewportPixelWidth;
    uint viewportPixelHeight;
    float viewWidthPoints;
    float viewHeightPoints;
    float drawableScaleX;
    float drawableScaleY;
    uint boardWidth;
    uint boardHeight;
    int baseX;
    int baseY;
    int spawnEdgeX;
    int spawnYMin;
    int spawnYMax;
    uint blockedCount;
    uint restrictedCount;
    uint rampCount;
    uint structureCount;
    uint entityCount;
    uint turretOverlayCount;
    uint pathSegmentCount;
    uint wallFlowSegmentCount;
    uint debugModeRaw;
    int highlightedX;
    int highlightedY;
    uint highlightedPathCount;
    uint highlightedAffordableCount;
    uint highlightedStructureTypeRaw;
    int placementResultRaw;
    float cameraPanX;
    float cameraPanY;
    float cameraZoom;
    float animationTick;
    float cursorWorldX;
    float cursorWorldY;
    float gridRevealRadius;
    float gridRevealStrength;
    uint oreCount;
};

struct WhiteboxPoint {
    int x;
    int y;
    int _pad0;
    int _pad1;
};

struct WhiteboxRamp {
    int x;
    int y;
    int elevation;
    int _pad0;
};

struct WhiteboxStructure {
    int anchorX;
    int anchorY;
    uint typeRaw;
    uint _pad0;
    int footprintWidth;
    int footprintHeight;
    int _pad1;
    int _pad2;
};

struct WhiteboxEntity {
    int x;
    int y;
    uint category;
    uint _pad0;
};

struct WhiteboxTurretOverlay {
    int x;
    int y;
    float rangeTiles;
    float _pad0;
};

struct WhiteboxPathSegment {
    int fromX;
    int fromY;
    int toX;
    int toY;
};

struct WhiteboxWallFlowSegment {
    int fromX;
    int fromY;
    int toX;
    int toY;
    float intensity;
    uint ammoTypeRaw;
    float phaseOffset;
    uint _pad0;
};

struct WhiteboxOreInfluence {
    int x;
    int y;
    uint oreTypeRaw;
    float richness;
};

inline bool in_bounds(int2 cell, constant WhiteboxUniforms& uniforms) {
    return cell.x >= 0 && cell.y >= 0 && cell.x < int(uniforms.boardWidth) && cell.y < int(uniforms.boardHeight);
}

inline float2 cell_to_screen(int2 cell, float2 origin, float tileWidth, float tileHeight) {
    return float2(
        origin.x + (float(cell.x) + 0.5) * tileWidth,
        origin.y + (float(cell.y) + 0.5) * tileHeight
    );
}

inline bool contains_cell(const device WhiteboxPoint* points, uint count, int2 cell) {
    for (uint i = 0; i < count; ++i) {
        if (points[i].x == cell.x && points[i].y == cell.y) {
            return true;
        }
    }
    return false;
}

inline int index_of_cell(const device WhiteboxPoint* points, uint count, int2 cell) {
    for (uint i = 0; i < count; ++i) {
        if (points[i].x == cell.x && points[i].y == cell.y) {
            return int(i);
        }
    }
    return -1;
}

inline int ramp_elevation(const device WhiteboxRamp* ramps, uint count, int2 cell) {
    for (uint i = 0; i < count; ++i) {
        if (ramps[i].x == cell.x && ramps[i].y == cell.y) {
            return ramps[i].elevation;
        }
    }
    return 0;
}

inline int2 footprint_size_for_type(uint typeRaw) {
    if (typeRaw == 12u) {
        return int2(2, 2);
    }
    return int2(1, 1);
}

inline int4 footprint_rect_from_anchor(int anchorX, int anchorY, int footprintWidth, int footprintHeight) {
    const int clampedWidth = max(1, footprintWidth);
    const int clampedHeight = max(1, footprintHeight);
    const int minX = anchorX - (clampedWidth - 1);
    const int maxX = anchorX;
    const int minY = anchorY - (clampedHeight - 1);
    const int maxY = anchorY;
    return int4(minX, minY, maxX, maxY);
}

inline bool point_in_rect(int2 cell, int4 rect) {
    return cell.x >= rect.x && cell.x <= rect.z && cell.y >= rect.y && cell.y <= rect.w;
}

inline float structure_height_in_tiles(uint typeRaw) {
    switch (typeRaw) {
        case 1u: return 0.28; // wall
        case 2u: return 0.95; // turret mount
        case 3u: return 0.60; // miner
        case 4u: return 0.68; // smelter
        case 5u: return 0.58; // assembler
        case 6u: return 0.52; // ammo module
        case 7u: return 1.05; // power plant
        case 8u: return 0.18; // conveyor
        case 9u: return 0.20; // splitter
        case 10u: return 0.20; // merger
        case 11u: return 0.72; // storage
        case 12u: return 0.90; // hq
        case 13u: return 0.65; // research center
        default: return 0.50;
    }
}

inline float3 structure_base_color(uint typeRaw) {
    switch (typeRaw) {
        case 1u: return float3(0.60, 0.60, 0.60);
        case 2u: return float3(0.20, 0.50, 0.80);
        case 3u: return float3(0.80, 0.60, 0.20);
        case 4u: return float3(0.90, 0.30, 0.10);
        case 5u: return float3(0.30, 0.70, 0.30);
        case 6u: return float3(0.80, 0.20, 0.20);
        case 7u: return float3(0.90, 0.90, 0.20);
        case 8u: return float3(0.50, 0.50, 0.70);
        case 9u: return float3(0.35, 0.55, 0.78);
        case 10u: return float3(0.48, 0.52, 0.80);
        case 11u: return float3(0.60, 0.40, 0.20);
        case 12u: return float3(0.20, 0.80, 0.90);
        case 13u: return float3(0.55, 0.28, 0.72); // research center (purple)
        default: return float3(0.75, 0.76, 0.78);
    }
}

inline float contact_shadow_strength(
    float2 pixel,
    float minX,
    float maxX,
    float minY,
    float maxY,
    float maxStrength
) {
    if (pixel.x < minX || pixel.x > maxX || pixel.y < minY || pixel.y > maxY) {
        return 0.0;
    }

    const float cx = (minX + maxX) * 0.5;
    const float cy = (minY + maxY) * 0.5;
    const float rx = max(1.0, (maxX - minX) * 0.5);
    const float ry = max(1.0, (maxY - minY) * 0.5);
    const float nx = (pixel.x - cx) / rx;
    const float ny = (pixel.y - cy) / ry;
    const float radial = nx * nx + ny * ny;
    if (radial >= 1.0) {
        return 0.0;
    }

    return (1.0 - radial) * maxStrength;
}

inline float distance_to_segment(float2 p, float2 a, float2 b) {
    const float2 ab = b - a;
    const float denom = max(dot(ab, ab), 1e-4);
    const float t = clamp(dot(p - a, ab) / denom, 0.0, 1.0);
    const float2 closest = a + ab * t;
    return length(p - closest);
}

// --- Procedural noise primitives ---

inline float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

inline float value_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f); // Hermite interpolation

    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

inline float fbm2(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float2 pos = p;
    for (int i = 0; i < 3; ++i) {
        value += amplitude * value_noise(pos);
        pos *= 2.17;
        amplitude *= 0.5;
    }
    return value;
}

inline float2 voronoi(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float minDist = 8.0;
    float secondDist = 8.0;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            float2 neighbor = float2(float(x), float(y));
            float2 point = float2(
                hash21(i + neighbor),
                hash21(i + neighbor + float2(127.1, 311.7))
            );
            float2 diff = neighbor + point - f;
            float dist = dot(diff, diff);
            if (dist < minDist) {
                secondDist = minDist;
                minDist = dist;
            } else if (dist < secondDist) {
                secondDist = dist;
            }
        }
    }
    return float2(sqrt(minDist), sqrt(secondDist));
}

inline float3 wall_flow_color(uint ammoTypeRaw) {
    switch (ammoTypeRaw) {
        case 2u: return float3(0.95, 0.54, 0.18); // heavy
        case 3u: return float3(0.72, 0.36, 0.95); // plasma
        case 1u: return float3(0.96, 0.84, 0.24); // light
        default: return float3(0.85, 0.85, 0.70); // mixed/unknown
    }
}

kernel void whitebox_board(
    texture2d<float, access::write> output [[texture(0)]],
    constant WhiteboxUniforms& uniforms [[buffer(0)]],
    device const WhiteboxPoint* blockedCells [[buffer(1)]],
    device const WhiteboxPoint* restrictedCells [[buffer(2)]],
    device const WhiteboxRamp* ramps [[buffer(3)]],
    device const WhiteboxStructure* structures [[buffer(4)]],
    device const WhiteboxEntity* entities [[buffer(5)]],
    device const WhiteboxTurretOverlay* turretOverlays [[buffer(6)]],
    device const WhiteboxPathSegment* pathSegments [[buffer(7)]],
    device const WhiteboxPoint* highlightedPath [[buffer(8)]],
    device const WhiteboxWallFlowSegment* wallFlowSegments [[buffer(9)]],
    device const WhiteboxOreInfluence* oreInfluences [[buffer(10)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.viewportPixelWidth || gid.y >= uniforms.viewportPixelHeight) {
        return;
    }

    const float2 pixel = (float2(gid) + float2(0.5, 0.5)) / float2(uniforms.drawableScaleX, uniforms.drawableScaleY);
    const float verticalT = clamp(pixel.y / max(uniforms.viewHeightPoints, 1.0), 0.0, 1.0);
    float3 color = float3(
        0.045 + 0.02 * verticalT,
        0.05 + 0.025 * verticalT,
        0.065 + 0.03 * verticalT
    );

    const float zoom = max(0.001, uniforms.cameraZoom);
    const float tileWidth = 34.0 * zoom;
    const float tileHeight = 22.0 * zoom;
    const float2 boardPixelSize = float2(
        float(uniforms.boardWidth) * tileWidth,
        float(uniforms.boardHeight) * tileHeight
    );
    const float2 origin = float2(
        (uniforms.viewWidthPoints - boardPixelSize.x) * 0.5 + uniforms.cameraPanX,
        uniforms.viewHeightPoints * 0.5 - boardPixelSize.y * 0.5 + uniforms.cameraPanY
    );

    const float2 cellF = (pixel - origin) / float2(tileWidth, tileHeight);
    const int2 cell = int2(int(floor(cellF.x)), int(floor(cellF.y)));

    if (in_bounds(cell, uniforms)) {
        color = float3(0.16, 0.18, 0.20);

        // Spawn edge - corrupted ground
        if (cell.x == uniforms.spawnEdgeX && cell.y >= uniforms.spawnYMin && cell.y <= uniforms.spawnYMax) {
            const float spawnDist = abs(float(cell.x - uniforms.spawnEdgeX));
            const float corruption = clamp(1.0 - spawnDist / 6.0, 0.0, 1.0);
            const float3 corruptBase = float3(0.18, 0.10, 0.14);
            const float2 voro = voronoi(cellF * 1.8 + float2(0.0, uniforms.animationTick * 0.003));
            const float veins = smoothstep(0.04, 0.15, voro.y - voro.x);
            float3 corruptColor = mix(corruptBase, corruptBase * 1.4, veins * 0.5);
            // Subtle animated pulse
            const float pulse = 0.92 + 0.08 * sin(uniforms.animationTick * 0.08 + float(cell.y) * 0.5);
            corruptColor *= pulse;
            color = mix(color, corruptColor, corruption * 0.7);
        }

        // Blocked cells - rough impassable terrain
        if (contains_cell(blockedCells, uniforms.blockedCount, cell)) {
            const float3 rockBase = float3(0.10, 0.10, 0.11);
            const float2 voro = voronoi(cellF * 2.5);
            const float rockDetail = smoothstep(0.06, 0.22, voro.y - voro.x);
            color = rockBase + float3(rockDetail * 0.06);
        }

        // Restricted cells - paved foundation
        if (contains_cell(restrictedCells, uniforms.restrictedCount, cell)) {
            const float3 paveBase = float3(0.30, 0.28, 0.22);
            const float2 voro = voronoi(cellF * 3.2);
            const float paverPattern = smoothstep(0.02, 0.06, voro.y - voro.x);
            const float3 paveColor = paveBase * (0.95 + 0.05 * paverPattern);
            color = mix(color, paveColor, 0.7);
        }

        const int elevation = ramp_elevation(ramps, uniforms.rampCount, cell);
        if (elevation > 0) {
            const float boost = min(float(elevation) * 0.08, 0.32);
            color += float3(boost, boost, boost);
        }

        // HQ area - cleared platform with paved concrete look
        {
            const float chebyshevDist = max(abs(float(cell.x - uniforms.baseX)), abs(float(cell.y - uniforms.baseY)));
            if (chebyshevDist <= 3.0) {
                const float3 concreteBase = float3(0.25, 0.27, 0.30);
                const float2 voro = voronoi(cellF * 2.0);
                const float tilePattern = smoothstep(0.02, 0.08, voro.y - voro.x);
                float3 platformColor = concreteBase * (0.96 + 0.04 * tilePattern);
                // Inner core teal accent
                if (chebyshevDist <= 1.0) {
                    const float innerBlend = 1.0 - chebyshevDist;
                    platformColor = mix(platformColor, float3(0.18, 0.52, 0.56), innerBlend * 0.6);
                }
                const float edgeFade = smoothstep(2.5, 3.0, chebyshevDist);
                color = mix(platformColor, color, edgeFade);
            }
        }

        // Soft AO edge darkening (replaces hard grid borders)
        const float2 local = fract(cellF);
        const float edgeDist = min(min(local.x, 1.0 - local.x), min(local.y, 1.0 - local.y));
        const float edgeAO = smoothstep(0.0, 0.18, edgeDist);
        color *= (0.97 + 0.03 * edgeAO);

        // Ore terrain staining
        for (uint i = 0; i < uniforms.oreCount; ++i) {
            const WhiteboxOreInfluence ore = oreInfluences[i];
            const float dx = cellF.x - (float(ore.x) + 0.5);
            const float dy = cellF.y - (float(ore.y) + 0.5);
            const float dist = sqrt(dx * dx + dy * dy);
            const float falloff = 1.0 - smoothstep(0.3, 2.0, dist);
            if (falloff > 0.001) {
                float3 oreColor;
                if (ore.oreTypeRaw == 1u) {
                    oreColor = float3(0.45, 0.28, 0.14); // iron - rusty brown
                } else if (ore.oreTypeRaw == 2u) {
                    oreColor = float3(0.14, 0.36, 0.32); // copper - teal-green
                } else {
                    oreColor = float3(0.15, 0.14, 0.13); // coal - dark charcoal
                }
                const float stainStrength = falloff * ore.richness * 0.45;
                color = mix(color, oreColor, stainStrength);
            }
        }

        // Grid-on-hover reveal
        if (uniforms.gridRevealStrength > 0.001) {
            const float cursorDist = max(abs(cellF.x - uniforms.cursorWorldX), abs(cellF.y - uniforms.cursorWorldY));
            const float reveal = (1.0 - smoothstep(uniforms.gridRevealRadius * 0.6, uniforms.gridRevealRadius, cursorDist));
            if (reveal > 0.001) {
                // Thin grid lines that adapt to zoom for ~1px appearance
                const float lineWidth = clamp(0.04 / max(0.3, uniforms.cameraZoom), 0.02, 0.08);
                const float gridLine = 1.0 - smoothstep(0.0, lineWidth, edgeDist);
                const float gridAlpha = gridLine * reveal * uniforms.gridRevealStrength;
                color = mix(color, float3(0.85, 0.88, 0.92), gridAlpha * 0.5);
            }
        }

        const int pathIndex = index_of_cell(highlightedPath, uniforms.highlightedPathCount, cell);
        if (pathIndex >= 0) {
            const bool affordable = uint(pathIndex) < uniforms.highlightedAffordableCount;
            const float3 previewColor = affordable
                ? float3(0.08, 0.46, 0.70)
                : float3(0.66, 0.12, 0.12);
            color = mix(color, previewColor, 0.62);
        }

        if (uniforms.highlightedX >= 0 && uniforms.highlightedY >= 0) {
            const int2 previewFootprint = footprint_size_for_type(uniforms.highlightedStructureTypeRaw);
            const int4 previewRect = footprint_rect_from_anchor(
                uniforms.highlightedX,
                uniforms.highlightedY,
                previewFootprint.x,
                previewFootprint.y
            );
            if (point_in_rect(cell, previewRect)) {
                const float3 accent = uniforms.placementResultRaw == 0
                    ? float3(0.11, 0.56, 0.19)
                    : float3(0.62, 0.12, 0.12);
                color = mix(color, accent, 0.75);
            }
        }
    }

    if (in_bounds(cell, uniforms)) {
        float shadowDarken = 0.0;
        for (uint i = 0; i < uniforms.structureCount; ++i) {
            const WhiteboxStructure structure = structures[i];
            const int4 footprint = footprint_rect_from_anchor(
                structure.anchorX,
                structure.anchorY,
                structure.footprintWidth,
                structure.footprintHeight
            );

            const float baseMinX = origin.x + float(footprint.x) * tileWidth;
            const float baseMaxX = origin.x + float(footprint.z + 1) * tileWidth;
            const float baseMinY = origin.y + float(footprint.y) * tileHeight;
            const float baseMaxY = origin.y + float(footprint.w + 1) * tileHeight;
            const float heightPixels = max(1.0, structure_height_in_tiles(structure.typeRaw) * tileHeight);

            const float shadowOffsetX = heightPixels * 0.28;
            const float shadowOffsetY = heightPixels * 0.46;
            const float shadowPadX = tileWidth * 0.09;
            const float shadowPadY = tileHeight * 0.08;
            const float shadowMinX = baseMinX + shadowOffsetX - shadowPadX;
            const float shadowMaxX = baseMaxX + shadowOffsetX + shadowPadX;
            const float shadowMinY = baseMinY + shadowOffsetY - shadowPadY;
            const float shadowMaxY = baseMaxY + shadowOffsetY + shadowPadY;

            const float heightStrength = clamp(heightPixels / max(1.0, tileHeight * 1.1), 0.0, 1.0);
            const float shadowStrength = 0.10 + (0.18 * heightStrength);
            shadowDarken = max(
                shadowDarken,
                contact_shadow_strength(
                    pixel,
                    shadowMinX,
                    shadowMaxX,
                    shadowMinY,
                    shadowMaxY,
                    shadowStrength
                )
            );
        }

        color *= (1.0 - shadowDarken);
    }

    bool hitStructure = false;
    int bestDrawKey = -2147483647;
    float3 structureColor = color;

    for (uint i = 0; i < uniforms.structureCount; ++i) {
        const WhiteboxStructure structure = structures[i];
        const int4 footprint = footprint_rect_from_anchor(
            structure.anchorX,
            structure.anchorY,
            structure.footprintWidth,
            structure.footprintHeight
        );

        const float baseMinX = origin.x + float(footprint.x) * tileWidth;
        const float baseMaxX = origin.x + float(footprint.z + 1) * tileWidth;
        const float baseMinY = origin.y + float(footprint.y) * tileHeight;
        const float baseMaxY = origin.y + float(footprint.w + 1) * tileHeight;
        const float heightPixels = max(1.0, structure_height_in_tiles(structure.typeRaw) * tileHeight);
        const float topMinY = baseMinY - heightPixels;

        const bool insideBounds =
            pixel.x >= baseMinX && pixel.x <= baseMaxX &&
            pixel.y >= topMinY && pixel.y <= baseMaxY;
        if (!insideBounds) {
            continue;
        }

        const int drawKey = structure.anchorY * int(uniforms.boardWidth) + structure.anchorX;
        if (hitStructure && drawKey < bestDrawKey) {
            continue;
        }

        hitStructure = true;
        bestDrawKey = drawKey;

        const float3 baseColor = structure_base_color(structure.typeRaw);
        if (pixel.y < baseMinY) {
            const float topT = clamp((pixel.y - topMinY) / heightPixels, 0.0, 1.0);
            const float xSpan = max(1.0, baseMaxX - baseMinX);
            const float xT = clamp((pixel.x - baseMinX) / xSpan, 0.0, 1.0);
            const float lightMix = clamp((1.0 - xT) * 0.62 + (1.0 - topT) * 0.38, 0.0, 1.0);
            const float edge = min(
                min(pixel.x - baseMinX, baseMaxX - pixel.x),
                min(pixel.y - topMinY, baseMinY - pixel.y)
            );
            const float rim = clamp((2.4 - edge) / 2.4, 0.0, 1.0);
            structureColor = baseColor * (1.02 + (0.26 * lightMix));
            structureColor += rim * float3(0.05, 0.05, 0.05);
            if (edge < 1.5) {
                structureColor *= 0.88;
            }
        } else {
            const float ySpan = max(1.0, baseMaxY - baseMinY);
            const float xSpan = max(1.0, baseMaxX - baseMinX);
            const float sideT = clamp((pixel.y - baseMinY) / ySpan, 0.0, 1.0);
            const float xT = clamp((pixel.x - baseMinX) / xSpan, 0.0, 1.0);
            const float directional = (1.0 - xT);
            const float verticalShade = 0.62 + (0.26 * (1.0 - sideT));
            const float sideHighlight = 0.82 + (0.24 * directional);
            structureColor = baseColor * verticalShade * sideHighlight;
            const float topEdgeRim = clamp((baseMinY + 1.6 - pixel.y) / 1.6, 0.0, 1.0);
            structureColor += topEdgeRim * baseColor * 0.08;
            const float baseAO = clamp((pixel.y - (baseMaxY - tileHeight * 0.22)) / max(1.0, tileHeight * 0.22), 0.0, 1.0);
            structureColor *= (1.0 - (0.14 * baseAO));
            if (pixel.y < (baseMinY + 1.0)) {
                structureColor = mix(baseColor * 1.03, structureColor, 0.35);
            }
        }
    }

    if (hitStructure) {
        color = structureColor;
    }

    if (in_bounds(cell, uniforms)) {
        const float2 cellCenter = cell_to_screen(cell, origin, tileWidth, tileHeight);
        const float markerDistance = length((pixel - cellCenter) / float2(tileWidth * 0.5, tileHeight * 0.5));
        for (uint i = 0; i < uniforms.entityCount; ++i) {
            const WhiteboxEntity marker = entities[i];
            if (marker.x != cell.x || marker.y != cell.y) {
                continue;
            }

            if (markerDistance < 0.42) {
                if (marker.category == 2u) {
                    color = float3(0.82, 0.24, 0.19);
                } else {
                    color = float3(0.95, 0.88, 0.34);
                }
            }
        }
    }

    const bool showTurretRanges = uniforms.debugModeRaw == 1u || uniforms.debugModeRaw == 3u;
    const bool showEnemyPaths = uniforms.debugModeRaw == 2u || uniforms.debugModeRaw == 3u;
    const bool showWallAmmoFlow = uniforms.debugModeRaw == 3u || uniforms.debugModeRaw == 4u;
    if (showTurretRanges) {
        const float ringThickness = max(1.0, tileWidth * 0.045);
        for (uint i = 0; i < uniforms.turretOverlayCount; ++i) {
            const WhiteboxTurretOverlay overlay = turretOverlays[i];
            const float2 center = cell_to_screen(int2(overlay.x, overlay.y), origin, tileWidth, tileHeight);
            const float radius = overlay.rangeTiles * tileWidth;
            const float distance = abs(length(pixel - center) - radius);
            if (distance <= ringThickness) {
                color = mix(color, float3(0.10, 0.72, 0.95), 0.78);
            }
        }
    }

    if (showEnemyPaths) {
        const float pathThickness = max(1.0, tileWidth * 0.085);
        for (uint i = 0; i < uniforms.pathSegmentCount; ++i) {
            const WhiteboxPathSegment segment = pathSegments[i];
            const float2 a = cell_to_screen(int2(segment.fromX, segment.fromY), origin, tileWidth, tileHeight);
            const float2 b = cell_to_screen(int2(segment.toX, segment.toY), origin, tileWidth, tileHeight);
            if (distance_to_segment(pixel, a, b) <= pathThickness) {
                color = mix(color, float3(0.96, 0.22, 0.74), 0.82);
            }
        }
    }

    if (showWallAmmoFlow) {
        const float tickTime = uniforms.animationTick * 0.035;
        const float pathThickness = max(1.0, tileWidth * 0.11);
        const float pulseLength = 0.22;
        const float pulseFade = 0.18;
        const float repeatCount = 2.8;

        for (uint i = 0; i < uniforms.wallFlowSegmentCount; ++i) {
            const WhiteboxWallFlowSegment segment = wallFlowSegments[i];
            const float2 a = cell_to_screen(int2(segment.fromX, segment.fromY), origin, tileWidth, tileHeight);
            const float2 b = cell_to_screen(int2(segment.toX, segment.toY), origin, tileWidth, tileHeight);
            const float distance = distance_to_segment(pixel, a, b);
            if (distance > pathThickness) {
                continue;
            }

            const float2 ab = b - a;
            const float segmentLength = max(length(ab), 1e-3);
            const float2 direction = ab / segmentLength;
            const float projected = clamp(dot(pixel - a, direction), 0.0, segmentLength);
            const float t = projected / segmentLength;

            const float cycle = fract(t * repeatCount - tickTime + segment.phaseOffset);
            const float head = smoothstep(0.0, pulseFade, cycle);
            const float tail = 1.0 - smoothstep(pulseLength, pulseLength + pulseFade, cycle);
            const float pulse = clamp(head * tail, 0.0, 1.0);

            const float laneMask = 1.0 - smoothstep(pathThickness * 0.55, pathThickness, distance);
            const float glow = (0.18 + pulse * 0.82) * laneMask * clamp(segment.intensity, 0.0, 1.0);
            color = mix(color, wall_flow_color(segment.ammoTypeRaw), glow);
        }
    }

    output.write(float4(color, 1.0), gid);
}

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
    int highlightedX;
    int highlightedY;
    uint highlightedStructureTypeRaw;
    int placementResultRaw;
    float cameraPanX;
    float cameraPanY;
    float cameraZoom;
    uint _padding0;
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

inline int ramp_elevation(const device WhiteboxRamp* ramps, uint count, int2 cell) {
    for (uint i = 0; i < count; ++i) {
        if (ramps[i].x == cell.x && ramps[i].y == cell.y) {
            return ramps[i].elevation;
        }
    }
    return 0;
}

inline int2 footprint_size_for_type(uint typeRaw) {
    if (typeRaw == 2u || typeRaw == 7u || typeRaw == 9u) {
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
        case 9u: return 0.72; // storage
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
        case 9u: return float3(0.60, 0.40, 0.20);
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

kernel void whitebox_board(
    texture2d<float, access::write> output [[texture(0)]],
    constant WhiteboxUniforms& uniforms [[buffer(0)]],
    device const WhiteboxPoint* blockedCells [[buffer(1)]],
    device const WhiteboxPoint* restrictedCells [[buffer(2)]],
    device const WhiteboxRamp* ramps [[buffer(3)]],
    device const WhiteboxStructure* structures [[buffer(4)]],
    device const WhiteboxEntity* entities [[buffer(5)]],
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

        if (cell.x == uniforms.spawnEdgeX && cell.y >= uniforms.spawnYMin && cell.y <= uniforms.spawnYMax) {
            color = mix(color, float3(0.36, 0.20, 0.18), 0.55);
        }

        if (contains_cell(blockedCells, uniforms.blockedCount, cell)) {
            color = float3(0.08, 0.09, 0.10);
        }

        if (contains_cell(restrictedCells, uniforms.restrictedCount, cell)) {
            color = mix(color, float3(0.40, 0.32, 0.10), 0.7);
        }

        const int elevation = ramp_elevation(ramps, uniforms.rampCount, cell);
        if (elevation > 0) {
            const float boost = min(float(elevation) * 0.08, 0.32);
            color += float3(boost, boost, boost);
        }

        if (cell.x == uniforms.baseX && cell.y == uniforms.baseY) {
            color = float3(0.12, 0.42, 0.46);
        }

        const float2 local = fract(cellF);
        const float borderDistance = min(min(local.x, 1.0 - local.x), min(local.y, 1.0 - local.y));
        if (borderDistance < 0.05) {
            color *= 0.68;
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

    output.write(float4(color, 1.0), gid);
}

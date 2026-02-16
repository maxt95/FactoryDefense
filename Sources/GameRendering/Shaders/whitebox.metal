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
    uint entityCount;
    int highlightedX;
    int highlightedY;
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

kernel void whitebox_board(
    texture2d<float, access::write> output [[texture(0)]],
    constant WhiteboxUniforms& uniforms [[buffer(0)]],
    device const WhiteboxPoint* blockedCells [[buffer(1)]],
    device const WhiteboxPoint* restrictedCells [[buffer(2)]],
    device const WhiteboxRamp* ramps [[buffer(3)]],
    device const WhiteboxEntity* entities [[buffer(4)]],
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

        if (cell.x == uniforms.highlightedX && cell.y == uniforms.highlightedY) {
            const float3 accent = uniforms.placementResultRaw == 0
                ? float3(0.11, 0.56, 0.19)
                : float3(0.62, 0.12, 0.12);
            color = mix(color, accent, 0.75);
        }

        const float2 cellCenter = cell_to_screen(cell, origin, tileWidth, tileHeight);
        const float markerDistance = length((pixel - cellCenter) / float2(tileWidth * 0.5, tileHeight * 0.5));
        for (uint i = 0; i < uniforms.entityCount; ++i) {
            const WhiteboxEntity marker = entities[i];
            if (marker.x != cell.x || marker.y != cell.y) {
                continue;
            }

            if (markerDistance < 0.42) {
                if (marker.category == 1) {
                    color = float3(0.75, 0.76, 0.78);
                } else if (marker.category == 2) {
                    color = float3(0.82, 0.24, 0.19);
                } else {
                    color = float3(0.95, 0.88, 0.34);
                }
            }
        }
    }

    output.write(float4(color, 1.0), gid);
}

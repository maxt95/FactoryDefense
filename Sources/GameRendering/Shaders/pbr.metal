#include <metal_stdlib>
using namespace metal;

// ─── Shared types ────────────────────────────────────────────

struct VSIn {
    float3 position [[attribute(0)]];
    half3 normal [[attribute(1)]];
};

struct InstanceUniforms {
    float4x4 modelViewProjection;
    float4x4 modelMatrix;
    float4 tintColor;
};

// ─── Sky gradient ────────────────────────────────────────────
// Draws a fullscreen triangle; fragment interpolates a vertical sky gradient.

struct SkyVSOut {
    float4 position [[position]];
    float2 uv;
};

vertex SkyVSOut sky_vertex(uint vid [[vertex_id]]) {
    // Fullscreen triangle: 3 vertices cover the entire screen
    SkyVSOut out;
    out.uv = float2((vid << 1) & 2, vid & 2);
    out.position = float4(out.uv * 2.0 - 1.0, 0.999, 1.0); // at far depth
    return out;
}

fragment half4 sky_fragment(SkyVSOut in [[stage_in]]) {
    // UV: (0,0) = top-left, (1,1) = bottom-left (Metal NDC: Y up, but position.y is screen Y)
    float t = in.uv.y; // 0 = top of screen, 1 = bottom

    // Sky colors
    const float3 zenithColor  = float3(0.15, 0.35, 0.65);   // Deep blue at top
    const float3 horizonColor = float3(0.55, 0.70, 0.85);   // Light blue at horizon
    const float3 groundColor  = float3(0.25, 0.28, 0.22);   // Dark ground below horizon

    // Horizon sits at roughly 55% down the screen (adjustable)
    const float horizonLine = 0.55;

    float3 color;
    if (t < horizonLine) {
        // Sky: zenith → horizon
        float skyT = t / horizonLine;
        // Use a power curve to concentrate blue at the top
        float curved = pow(skyT, 0.7);
        color = mix(zenithColor, horizonColor, curved);
    } else {
        // Below horizon: horizon → ground
        float groundT = (t - horizonLine) / (1.0 - horizonLine);
        float curved = pow(groundT, 0.5);
        color = mix(horizonColor, groundColor, curved);
    }

    // Subtle warm tint near horizon
    float horizonProximity = 1.0 - abs(t - horizonLine) * 4.0;
    horizonProximity = saturate(horizonProximity);
    const float3 warmTint = float3(0.70, 0.60, 0.45);
    color = mix(color, warmTint, horizonProximity * 0.15);

    return half4(half3(color), 1.0h);
}

// ─── PBR mesh rendering with distance fog ────────────────────

struct PBRVSOut {
    float4 position [[position]];
    half3 normal;
    half4 color;
    float3 worldPosition;
};

struct FogParams {
    float3 fogColor;       // Should match horizon color
    float fogStart;        // Distance where fog begins
    float fogEnd;          // Distance where fog is fully opaque
    float3 cameraPosition; // Eye position for distance calc
};

vertex PBRVSOut pbr_vertex(
    VSIn in [[stage_in]],
    constant InstanceUniforms *instances [[buffer(1)]],
    uint iid [[instance_id]]
) {
    PBRVSOut out;
    const float4 modelPosition = float4(in.position, 1.0);
    const float3x3 model3x3 = float3x3(
        instances[iid].modelMatrix[0].xyz,
        instances[iid].modelMatrix[1].xyz,
        instances[iid].modelMatrix[2].xyz
    );
    const float3 worldNormal = normalize(model3x3 * float3(in.normal));
    const float4 worldPos = instances[iid].modelMatrix * modelPosition;

    out.position = instances[iid].modelViewProjection * modelPosition;
    out.normal = half3(worldNormal);
    out.color = half4(instances[iid].tintColor);
    out.worldPosition = worldPos.xyz;
    return out;
}

fragment half4 pbr_fragment(
    PBRVSOut in [[stage_in]],
    constant FogParams &fog [[buffer(0)]]
) {
    // Directional lighting (sun)
    const half3 lightDirection = normalize(half3(0.35h, 0.82h, 0.44h));
    const half nDotL = max(dot(normalize(in.normal), lightDirection), 0.0h);
    const half3 ambient = half3(0.28h);
    const half3 lit = in.color.rgb * (ambient + nDotL * half3(0.72h));

    // Distance fog
    float dist = distance(in.worldPosition, fog.cameraPosition);
    float fogFactor = saturate((dist - fog.fogStart) / max(fog.fogEnd - fog.fogStart, 0.001));
    // Exponential-ish fog curve for more natural falloff
    fogFactor = fogFactor * fogFactor;

    half3 finalColor = mix(lit, half3(fog.fogColor), half(fogFactor));
    return half4(finalColor, 1.0h);
}

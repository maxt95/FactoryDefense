#include <metal_stdlib>
using namespace metal;

struct VSIn {
    float3 position [[attribute(0)]];
    half3 normal [[attribute(1)]];
};

struct InstanceUniforms {
    float4x4 modelViewProjection;
    float4x4 modelMatrix;
    float4 tintColor;
};

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
    const float4 modelPosition = float4(in.position, 1.0);
    const float3x3 model3x3 = float3x3(
        instances[iid].modelMatrix[0].xyz,
        instances[iid].modelMatrix[1].xyz,
        instances[iid].modelMatrix[2].xyz
    );
    const float3 worldNormal = normalize(model3x3 * float3(in.normal));
    out.position = instances[iid].modelViewProjection * modelPosition;
    out.normal = half3(worldNormal);
    out.color = half4(instances[iid].tintColor);
    return out;
}

fragment half4 pbr_fragment(VSOut in [[stage_in]]) {
    const half3 lightDirection = normalize(half3(0.35h, 0.82h, 0.44h));
    const half nDotL = max(dot(normalize(in.normal), lightDirection), 0.0h);
    const half3 lit = in.color.rgb * (half3(0.24h) + nDotL * half3(0.76h));
    return half4(lit, 1.0h);
}

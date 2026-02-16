#include <metal_stdlib>
using namespace metal;

struct VSIn {
    float3 position [[attribute(0)]];
    half3 normal [[attribute(1)]];
};

struct VSOut {
    float4 position [[position]];
    half3 normal;
};

vertex VSOut pbr_vertex(VSIn in [[stage_in]]) {
    VSOut out;
    out.position = float4(in.position, 1.0);
    out.normal = normalize(in.normal);
    return out;
}

fragment half4 pbr_fragment(VSOut in [[stage_in]]) {
    half3 lit = half3(0.2h) + max(in.normal.y, 0.0h) * half3(0.8h, 0.7h, 0.6h);
    return half4(lit, 1.0h);
}

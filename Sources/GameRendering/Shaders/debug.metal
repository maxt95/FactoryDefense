#include <metal_stdlib>
using namespace metal;

half3 heat_map(half v) {
    v = clamp(v, half(0.0), half(1.0));
    return v < half(0.5)
        ? mix(half3(0.0h, 0.0h, 1.0h), half3(0.0h, 1.0h, 0.0h), v * 2.0h)
        : mix(half3(0.0h, 1.0h, 0.0h), half3(1.0h, 0.0h, 0.0h), (v - 0.5h) * 2.0h);
}

kernel void debug_heat(texture2d<half, access::write> outTex [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) {
        return;
    }

    half u = half(gid.x) / half(outTex.get_width());
    outTex.write(half4(heat_map(u), 1.0h), gid);
}

#include <metal_stdlib>
using namespace metal;

struct VIn  { float2 pos [[attribute(0)]], uv [[attribute(1)]]; };
struct VOut { float4 position [[position]]; float2 uv; };

vertex VOut subtitle_vertex(VIn in [[stage_in]],
                            constant float2 &viewport [[buffer(1)]]) {
    VOut o;
    float2 ndc = (in.pos / viewport) * 2.0 - 1.0;
    o.position = float4(ndc.x, -ndc.y, 0, 1);
    o.uv = in.uv;
    return o;
}

fragment float4 subtitle_fragment(VOut in [[stage_in]],
                                  texture2d<float> atlas [[texture(0)]],
                                  sampler s [[sampler(0)]],
                                  constant float4 &col [[buffer(0)]]) {
    float4 texColor = atlas.sample(s, in.uv);
    float alpha = texColor.r; // brightness of red channel
    return float4(col.rgb, col.a * alpha);
}

#version 440
// Full-screen glow layer: a flowing gradient bloom at the screen edges, a
// glowing ring around the selection, and a one-shot scan across it.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;      // item size, px
    float time;    // seconds
    float edge;    // edge glow strength 0..1
    vec4 sel;      // selection x, y, w, h (px)
    float selOn;   // 0..1
    float radius;  // selection corner radius
    float scan;    // scan band position, 0..1 sweeps the selection
    float busy;    // 0..1 while Claude is thinking
    vec4 c1;
    vec4 c2;
    vec4 c3;
};

const float TAU = 6.28318530718;

vec3 grad(float t) {
    t = fract(t) * 3.0;
    if (t < 1.0) return mix(c1.rgb, c2.rgb, smoothstep(0.0, 1.0, t));
    if (t < 2.0) return mix(c2.rgb, c3.rgb, smoothstep(0.0, 1.0, t - 1.0));
    return mix(c3.rgb, c1.rgb, smoothstep(0.0, 1.0, t - 2.0));
}

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 p = qt_TexCoord0 * res;
    // Every speed here is constant. Scaling the clock by a changing factor
    // (e.g. faster while busy) jumps the phase and makes the colours flash.
    float drift = time * 0.03;

    // --- edge bloom ----------------------------------------------------
    vec2 c = res * 0.5;
    float ang = atan(p.y - c.y, p.x - c.x) / TAU;
    float d = min(min(p.x, p.y), min(res.x - p.x, res.y - p.y));
    float width = 30.0 + 14.0 * busy;
    float wave = 0.8 + 0.2 * sin(ang * TAU * 2.0 + time * 0.5);
    float ea = edge * exp(-d / width) * wave * 0.6;
    vec3 ecol = grad(ang + drift);

    // --- selection ring --------------------------------------------------
    vec2 sc = sel.xy + sel.zw * 0.5;
    float sd = sdRoundBox(p - sc, sel.zw * 0.5, min(radius, min(sel.z, sel.w) * 0.5));
    float ring = smoothstep(1.6, 0.3, abs(sd)) * 0.9;           // crisp 1.5px line
    float halo = exp(-max(sd, 0.0) / 9.0) * step(-0.5, sd) * (0.22 + 0.1 * busy);
    float sa = selOn * max(ring, halo);
    float sang = atan(p.y - sc.y, p.x - sc.x) / TAU;
    vec3 scol = grad(sang - drift * 2.0);

    // --- scan shimmer inside the selection ------------------------------
    float diag = ((p.x - sel.x) + (p.y - sel.y)) / max(sel.z + sel.w, 1.0);
    float band = exp(-pow((diag - (scan * 1.4 - 0.2)) * 8.0, 2.0));
    float inside = 1.0 - smoothstep(-1.0, 0.0, sd);
    float ba = selOn * inside * band * 0.14 * step(0.001, scan) * step(scan, 0.999);
    vec3 bcol = mix(grad(diag + drift), vec3(1.0), 0.3);

    // composite (premultiplied)
    vec3 col = ecol * ea + scol * sa + bcol * ba;
    float a = clamp(ea + sa + ba, 0.0, 1.0);
    fragColor = vec4(col, a) * qt_Opacity;
}

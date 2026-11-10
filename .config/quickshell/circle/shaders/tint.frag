#version 440
// Recolours a layer (lasso stroke, shimmer text, busy ring) with the same
// flowing gradient, keeping its alpha.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;
    float time;
    float period;  // px per gradient cycle
    vec4 c1;
    vec4 c2;
    vec4 c3;
};
layout(binding = 1) uniform sampler2D source;

vec3 grad(float t) {
    t = fract(t) * 3.0;
    if (t < 1.0) return mix(c1.rgb, c2.rgb, smoothstep(0.0, 1.0, t));
    if (t < 2.0) return mix(c2.rgb, c3.rgb, smoothstep(0.0, 1.0, t - 1.0));
    return mix(c3.rgb, c1.rgb, smoothstep(0.0, 1.0, t - 2.0));
}

void main() {
    vec4 s = texture(source, qt_TexCoord0);
    vec2 p = qt_TexCoord0 * res;
    vec3 col = grad((p.x + p.y * 0.4) / period - time * 0.35);
    fragColor = vec4(col * s.a, s.a) * qt_Opacity;
}

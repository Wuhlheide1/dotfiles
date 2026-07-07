#version 300 es
// Warm sepia "paper" tint for comfortable long reading (distinct from the
// night-light colour temperature, which only shifts white balance).
// Applied via the Control Center "Color Filter" tile.
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
layout(location = 0) out vec4 fragColor;

void main() {
    vec4 c = texture(tex, v_texcoord);
    float g = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
    // blend the original toward a warm paper tone, keeping some colour
    vec3 sepia = vec3(g) * vec3(1.07, 0.94, 0.78);
    fragColor = vec4(mix(c.rgb, sepia, 0.72), c.a);
}

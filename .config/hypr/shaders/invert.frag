#version 300 es
// Full color inversion (dark-mode-everything / high-contrast reading).
// Applied via the Control Center "Color Filter" tile.
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
layout(location = 0) out vec4 fragColor;

void main() {
    vec4 c = texture(tex, v_texcoord);
    fragColor = vec4(1.0 - c.rgb, c.a);
}

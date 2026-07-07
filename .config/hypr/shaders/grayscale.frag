#version 300 es
// Grayscale screen filter (luminance-weighted). Applied via the Control
// Center "Color Filter" tile -> hyprctl decoration:screen_shader.
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
layout(location = 0) out vec4 fragColor;

void main() {
    vec4 c = texture(tex, v_texcoord);
    float g = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
    fragColor = vec4(vec3(g), c.a);
}

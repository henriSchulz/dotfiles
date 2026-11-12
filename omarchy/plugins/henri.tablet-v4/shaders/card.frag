#version 440
// A window snapshot as a card: rounded corners, narrowed to a square from the sides while it
// morphs into its icon (inset), the content's own fade. One texture lookup, an analytic mask.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // the card's size in its own px
    float inset;    // px taken off left and right
    float radius;   // corner radius in its own px
    float aa;       // one screen px in its own px (the card is drawn scaled)
    float fade;     // the content's opacity
};
layout(binding = 1) uniform sampler2D source;
void main() {
    vec2 p = qt_TexCoord0 * size - size * 0.5;
    vec2 halfSize = vec2(size.x * 0.5 - inset, size.y * 0.5);
    vec2 q = abs(p) - halfSize + vec2(radius);
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float a = clamp(0.5 - d / max(aa, 0.0001), 0.0, 1.0);
    fragColor = texture(source, qt_TexCoord0) * (a * fade * qt_Opacity);
}

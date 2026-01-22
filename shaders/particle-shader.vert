#version 450

layout(location = 0) in float size;
layout(location = 1) in vec2 inPosition;
layout(location = 2) in vec4 inColor;

layout(binding = 0) uniform UniformBufferObject {
    mat4  proj;
    float worldUnitToPixelRatio;
} ubo;

layout(location = 0) out vec4 fragColor;

void main() {
    gl_Position = ubo.proj * vec4(inPosition, inColor.a, 1.0);

    gl_PointSize = size * ubo.worldUnitToPixelRatio;

    fragColor = inColor;
}

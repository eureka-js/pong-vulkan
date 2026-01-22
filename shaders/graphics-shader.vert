#version 450

layout(push_constant) uniform PushConstants {
    vec2  model;
    float depth;
    float opacity;
} pc;

layout(binding = 0) uniform UniformBufferObject {
    mat4 proj;
} ubo;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec4 inColor;

layout(location = 0) out vec4 fragColor;

void main() {
    vec4 finalPrePosition = vec4(inPosition, 1.0);
    finalPrePosition.xy   += pc.model;
    finalPrePosition.z    = pc.depth;
    gl_Position = ubo.proj * finalPrePosition;

    vec4 finalColor = inColor;
    finalColor.w    = pc.opacity;
    fragColor = finalColor;
}

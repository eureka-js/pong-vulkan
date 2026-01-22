const cglm = @import("bindings/cglm.zig").cglm;
const vk   = @import("bindings/vulkan.zig").vk;

const std = @import("std");

const ParticleBoundingBox = @import("particle-bounding-box.zig").ParticleBoundingBox;

pub const Particle = struct {
    currBoundingBox:        ParticleBoundingBox,
    prevBoundingBox:        ParticleBoundingBox,
    color:                  cglm.vec4,
    position:               cglm.vec2,
    currVelocity:           cglm.vec2,
    prevVelocityDeltaTimed: cglm.vec2,
    size:                   f32,
    _pad: [1]f32 = undefined,

    pub fn getBindingDescription() vk.VkVertexInputBindingDescription {
        return .{
            .binding   = 0,
            .stride    = @sizeOf(@This()),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        };
    }

    pub fn getAttributeDescriptions() []const vk.VkVertexInputAttributeDescription {
        return &.{
            .{
                .binding  = 0,
                .location = 0,
                .format   = vk.VK_FORMAT_R32_SFLOAT,
                .offset   = @offsetOf(@This(), "size"),
            },
            .{
                .binding  = 0,
                .location = 1,
                .format   = vk.VK_FORMAT_R32G32_SFLOAT,
                .offset   = @offsetOf(@This(), "position"),
            },
            .{
                .binding  = 0,
                .location = 2,
                .format   = vk.VK_FORMAT_R32G32B32A32_SFLOAT,
                .offset   = @offsetOf(@This(), "color"),
            },
        };
    }
};

const vk   = @import("bindings/vulkan.zig").vk;
const cglm = @import("bindings/cglm.zig").cglm;

const std = @import("std");

pub const Vertex = struct {
    pos:   cglm.vec3,
    color: cglm.vec4,

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
                .format   = vk.VK_FORMAT_R32G32B32_SFLOAT,
                .offset   = @offsetOf(@This(), "pos"),
            },
            .{
                .binding  = 0,
                .location = 1,
                .format   = vk.VK_FORMAT_R32G32B32A32_SFLOAT,
                .offset   = @offsetOf(@This(), "color"),
            },
        };
    }
};

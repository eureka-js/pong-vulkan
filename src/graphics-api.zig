const vk   = @import("bindings//vulkan.zig").vk;
const glfw = @import("bindings//glfw.zig").glfw;

const std = @import("std");

const ThreadContextRuntime  = @import("thread-context.zig").ThreadContextRuntime;
const ThreadContextComptime = @import("thread-context.zig").ThreadContextComptime;
const ComputeWorldEntities  = @import("comp-world-entity.zig").ComputeWorldEntity;
const VulkanLayer           = @import("vulkan-layer.zig").VulkanLayer;
const Node                  = @import("node.zig").Node;

pub const GraphicsAPI = union(enum) {
    vulkan: VulkanLayer,

    pub fn waitUntilComputeIndexIsAvailable(self: *GraphicsAPI, index: usize) void {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.waitUntilComputeIndexIsAvailable(index),
        };
    }

    pub fn waitUntilRenderIndexIsAvailable(self: *GraphicsAPI, index: usize) void {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.waitUntilRenderIndexIsAvailable(index),
        };
    }

    pub fn submitComputeWorldEntities(self: *GraphicsAPI, entities: []const u8) !void {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.createComputeWorldEntityStorageBuffers(entities),
        };
    }

    pub fn initPre(
        self:        *GraphicsAPI,
        ctx:         *ThreadContextRuntime,
        ctxComptime: *const ThreadContextComptime,
        width:       u32,
        height:      u32,
    ) !void {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.initPre(ctx, ctxComptime, width, height),
        };
    }

    pub fn initPost(
        self:               *GraphicsAPI,
        particleSize:       usize,
        numOfParticles:     usize,
        worldEntitySize:    usize,
        numOfWorldEntities: usize,
    ) !void {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.initPost(particleSize, numOfParticles, worldEntitySize, numOfWorldEntities),
        };
    }

    pub fn waitForDevice(self: *GraphicsAPI) u32 {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.waitForDevice(),
        };
    }

    pub fn recreateSwapChain(
        self:              *GraphicsAPI,
        ctx:               *ThreadContextRuntime,
        frameBufferWidth:  u32,
        frameBufferheight: u32,
    ) !void {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.recreateSwapChain(ctx, frameBufferWidth, frameBufferheight),
        };
    }

    pub fn runCompute(self: *GraphicsAPI, ctx: *ThreadContextRuntime) !void {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.runCompute(ctx),
        };
    }

    pub fn runRender(self: *GraphicsAPI, ctx: *ThreadContextRuntime) !void {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.runRender(ctx),
        };
    }

    pub fn initParticlesResources(
        self:         *GraphicsAPI,
        particles:    []const u8,
        particleSize:  usize,
    ) !void {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.createParticleStorageBuffers(particles, particleSize),
        };
    }

    pub fn initRenderWorldEntitiesResources(
        self:      *GraphicsAPI,
        nodes:     []*Node,
        batchSize: usize,
    ) !void {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.createWorldEntityRenderBuffer(nodes, batchSize),
        };
    }

    pub fn submitParticles(
        self:         *GraphicsAPI,
        index:        usize,
        particles:    []const u8,
        checkpoints:  [4]usize,
        particleSize: usize,
    ) !void {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.injectParticlesIntoBuffer(index, particles, checkpoints, particleSize),
        };
    }

    pub fn updateComputeWorldEntities(
        self:     *GraphicsAPI,
        index:    usize,
        entities: []const u8,
    ) !void {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.updateComputeWorldEntityStorageBuffers(index, entities),
        };
    }

    pub fn deinitRenderWorldEntitiesResources(self: *GraphicsAPI) void {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.deinitWorldEntitiesRenderBufferManager(),
        };
    }

    pub fn deinitParticlesResources(self: *GraphicsAPI) void {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.deinitParticleShaderStorageBuffers(),
        };
    }

    pub fn cleanup(self: *GraphicsAPI) !void {
        return switch(self.*) {
            inline .vulkan => |*vulkan| vulkan.cleanup(),
        };
    }
};

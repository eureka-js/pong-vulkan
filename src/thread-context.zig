const glfw = @import("bindings//glfw.zig").glfw;
const vk   = @import("bindings//vulkan.zig").vk;

const std = @import("std");

const ApplicationLayer = @import("application-layer.zig").ApplicationLayer;
const ThreadStates     = @import("thread-states.zig").ThreadStates;
const GraphicsAPI      = @import("graphics-api.zig").GraphicsAPI;
const InputHandler     = @import("input-handler.zig").InputHandler;
const Node             = @import("node.zig").Node;
const cfg              = @import("config.zig");

pub const ThreadContextRuntime = struct {
    window:                                 ?*glfw.GLFWwindow,
    threadStates:                           *ThreadStates,
    appInputHandler:                        *InputHandler,
    shouldClose:                            std.atomic.Value(bool),
    shouldRecreateSwapchain:                std.atomic.Value(bool),
    numOfWaitingThreads:                    std.atomic.Value(usize),
    isGraphicsAndComputeQueueBeingAccessed: std.atomic.Value(bool),
    renderAvgFrameTime:                     std.atomic.Value(f32),
    gameLayerSyncWaitTimeNs:                std.atomic.Value(u64),
    accumulatedGameDeltaTimesSnapshot:      [cfg.NUM_OF_THREADS]([cfg.NUM_OF_THREADS]std.atomic.Value(f32)),
    framebufferResized:                     std.atomic.Value(bool),
    aspectRatio:                            f32,
    viewportWidth:                          f32,
    viewportHeight:                         f32,
};

pub const ThreadContextComptime = struct {
    pub const GraphicsAPIRelated = struct {
        graphicsAPI:                        *const anyopaque,
        waitUntilComputeIndexIsAvailable:   *const fn (*const anyopaque, usize) void,
        waitUntilRenderIndexIsAvailable:    *const fn (*const anyopaque, usize) void,
        initParticlesResources:             *const fn (*const anyopaque, []const u8, usize) anyerror!void,
        initRenderWorldEntitiesResources:   *const fn (*const anyopaque, []*Node, usize) anyerror!void,
        submitComputeWorldEntities:         *const fn (*const anyopaque, []const u8) anyerror!void,
        updateComputeWorldEntities:         *const fn (*const anyopaque, usize, []const u8) anyerror!void,
        deinitRenderWorldEntitiesResoruces: *const fn (*const anyopaque) void,
        deinitParticlesResources:           *const fn (*const anyopaque) void,
        submitParticles:                    *const fn (*const anyopaque, usize, []const u8, [4]usize, usize) void,
        cleanup:                            *const fn (*const anyopaque) anyerror!void,

        pub inline fn init(
            graphicsAPI:                        *GraphicsAPI,
            waitUntilComputeIndexIsAvailable:   @TypeOf(GraphicsAPI.waitUntilComputeIndexIsAvailable),
            waitUntilRenderIndexIsAvailable:    @TypeOf(GraphicsAPI.waitUntilRenderIndexIsAvailable),
            initParticlesResources:             @TypeOf(GraphicsAPI.initParticlesResources),
            initRenderWorldEntitiesResources:   @TypeOf(GraphicsAPI.initRenderWorldEntitiesResources),
            submitComputeWorldEntities:         @TypeOf(GraphicsAPI.submitComputeWorldEntities),
            updateComputeWorldEntities:         @TypeOf(GraphicsAPI.updateComputeWorldEntities),
            deinitRenderWorldEntitiesResoruces: @TypeOf(GraphicsAPI.deinitRenderWorldEntitiesResources),
            deinitParticlesResources:           @TypeOf(GraphicsAPI.deinitParticlesResources),
            submitParticles:                    @TypeOf(GraphicsAPI.submitParticles),
            cleanup:                            @TypeOf(GraphicsAPI.cleanup),
        ) GraphicsAPIRelated {
            return .{
                .graphicsAPI                        = @ptrCast(graphicsAPI),
                .waitUntilComputeIndexIsAvailable   = @ptrCast(&waitUntilComputeIndexIsAvailable),
                .waitUntilRenderIndexIsAvailable    = @ptrCast(&waitUntilRenderIndexIsAvailable),
                .initParticlesResources             = @ptrCast(&initParticlesResources),
                .initRenderWorldEntitiesResources   = @ptrCast(&initRenderWorldEntitiesResources),
                .submitComputeWorldEntities         = @ptrCast(&submitComputeWorldEntities),
                .updateComputeWorldEntities         = @ptrCast(&updateComputeWorldEntities),
                .deinitRenderWorldEntitiesResoruces = @ptrCast(&deinitRenderWorldEntitiesResoruces),
                .deinitParticlesResources           = @ptrCast(&deinitParticlesResources),
                .submitParticles                    = @ptrCast(&submitParticles),
                .cleanup                            = @ptrCast(&cleanup),
            };
        }
    };

    pub const AppRelated = struct {
        getRequiredVulkanExtensions: *const fn (*u32) [*c][*c]const u8,
        createVulkanSurface:         *const fn (*ThreadContextRuntime, vk.VkInstance, *vk.VkSurfaceKHR) anyerror!void,

        pub inline fn init(
            getRequiredVulkanExtensions: *const fn (*u32) [*c][*c]const u8,
            createVulkanSurface:         *const fn (*ThreadContextRuntime, vk.VkInstance, *vk.VkSurfaceKHR) anyerror!void,
        ) AppRelated {
            return .{
                .getRequiredVulkanExtensions = getRequiredVulkanExtensions,
                .createVulkanSurface         = createVulkanSurface,
            };
        }
    };

    graphicsApiRelated: GraphicsAPIRelated,
    appRelated:         AppRelated,

    pub inline fn init(graphicsApiRelated: GraphicsAPIRelated, appRelated: AppRelated) ThreadContextComptime {
        return .{
            .graphicsApiRelated = graphicsApiRelated,
            .appRelated         = appRelated,
        };
    }
};

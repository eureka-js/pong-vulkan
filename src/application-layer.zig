const glfwLib = @import("bindings//glfw.zig");
const glfw    = glfwLib.glfw;
const vk      = @import("bindings//vulkan.zig").vk;

const std = @import("std");

const ThreadStates          = @import("thread-states.zig").ThreadStates;
const ThreadContextRuntime  = @import("thread-context.zig").ThreadContextRuntime;
const ThreadContextComptime = @import("thread-context.zig").ThreadContextComptime;
const GraphicsAPI           = @import("graphics-api.zig").GraphicsAPI;
const AudioDevice           = @import("audio-device.zig").AudioDevice;
const AudioHandler          = @import("audio-handler.zig").AudioHandler;
const InputHandler          = @import("input-handler.zig").InputHandler;
const VulkanLayer           = @import("vulkan-layer.zig").VulkanLayer;
const GameLayer             = @import("game-layer.zig").GameLayer;
const Node                  = @import("node.zig").Node;
const cfg                   = @import("config.zig");
const time                  = @import("time.zig");

const WIDTH:  u32 = 1280;
const HEIGHT: u32 = 720;

pub const ApplicationLayer = struct {
    const FrameBufferSize = struct {
        width:  u32,
        height: u32,
    };

    threadStates: ThreadStates = .{
        .states           = [_]std.atomic.Value(ThreadStates.State){std.atomic.Value(ThreadStates.State).init(.GAME)} ** ThreadStates.NUM_OF_STATES,
        .currGameIndex    = std.atomic.Value(usize).init(0),
        .currComputeIndex = 0,
        .currRenderIndex  = 0,
    },

    graphicsAPILayer: GraphicsAPI,
    gameLayer:        GameLayer,

    ctx: ThreadContextRuntime = undefined,

    appInputHandler: InputHandler = undefined,

    audioDevice: AudioDevice = undefined,

    allocator: *const std.mem.Allocator,
    prng:      *const std.Random,

    pub fn init(allocator: *const std.mem.Allocator, prng: *const std.Random) ApplicationLayer {
       return .{
            .allocator        = allocator,
            .prng             = prng,
            .graphicsAPILayer = .{
                .vulkan = .{
                    .allocator = allocator
                }
            },
            .gameLayer        = .{
                .prng      = prng,
                .allocator = allocator,
            },
        };
    }

    pub fn run(self: *ApplicationLayer) !void {
        const KEY = @TypeOf(self.appInputHandler).KEY;
        self.appInputHandler = .{
            .keys = &.{KEY.ESC.asInt()},
        };

        self.ctx = .{
            .window                                 = undefined,
            .threadStates                           = &self.threadStates,
            .appInputHandler                        = &self.appInputHandler,
            .shouldClose                            = std.atomic.Value(bool).init(false),
            .shouldRecreateSwapchain                = std.atomic.Value(bool).init(false),
            .numOfWaitingThreads                    = std.atomic.Value(usize).init(0),
            .isGraphicsAndComputeQueueBeingAccessed = std.atomic.Value(bool).init(false),
            .renderAvgFrameTime                     = std.atomic.Value(f32).init(0.0),
            .gameLayerSyncWaitTimeNs                = std.atomic.Value(u64).init(0),
            .accumulatedGameDeltaTimesSnapshot      = [_]([cfg.NUM_OF_THREADS]std.atomic.Value(f32)){
                [_]std.atomic.Value(f32){std.atomic.Value(f32).init(0.0)} ** cfg.NUM_OF_THREADS,
            } ** cfg.NUM_OF_THREADS,
            .framebufferResized                     = std.atomic.Value(bool).init(false),
            .aspectRatio                            = undefined,
            .viewportWidth                          = WIDTH,
            .viewportHeight                         = HEIGHT,
        };

        const ctxComptime = ThreadContextComptime.init(
            ThreadContextComptime.GraphicsAPIRelated.init(
                &self.graphicsAPILayer,
                GraphicsAPI.waitUntilComputeIndexIsAvailable,
                GraphicsAPI.waitUntilRenderIndexIsAvailable,
                GraphicsAPI.initParticlesResources,
                GraphicsAPI.initRenderWorldEntitiesResources,
                GraphicsAPI.submitComputeWorldEntities,
                GraphicsAPI.updateComputeWorldEntities,
                GraphicsAPI.deinitRenderWorldEntitiesResources,
                GraphicsAPI.deinitParticlesResources,
                GraphicsAPI.submitParticles,
                GraphicsAPI.cleanup,
            ),
            ThreadContextComptime.AppRelated.init(
                ApplicationLayer.getRequiredVulkanExtensions,
                ApplicationLayer.createVulkanSurface,
            ),
        );

        try self.initWindow();

        _ = glfw.glfwSetKeyCallback(self.ctx.window, InputHandler.keyCallback);

        const frameBufferSize = getFramebufferSize(self.ctx.window);
        try self.graphicsAPILayer.initPre(&self.ctx, &ctxComptime, frameBufferSize.width, frameBufferSize.height);

        const res = try self.gameLayer.initGameLogic(&self.ctx, &ctxComptime, self.threadStates.currGameIndex.load(.acquire));
        try self.graphicsAPILayer.initPost(res.sizeOfParticle, res.numOfParticles, res.sizeOfWorldEntity, res.numOfWorldEntities);

        try self.audioDevice.setup(AudioHandler.dataCallback, @ptrCast(&self.gameLayer.audioHandler.state));
        try self.audioDevice.start();

        try self.mainLoop(&ctxComptime);

        try self.gameLayer.cleanup(&ctxComptime);
        try ctxComptime.graphicsApiRelated.cleanup(ctxComptime.graphicsApiRelated.graphicsAPI);
        try self.cleanup();
    }

    fn initWindow(self: *ApplicationLayer) !void {
        if (glfw.glfwInit() == glfw.GLFW_FALSE) {
            return error.FailedGlfwInitialization;
        }

        glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);
        //glfw.glfwWindowHint(glfw.GLFW_RESIZABLE, glfw.GLFW_FALSE);

        self.ctx.window = glfw.glfwCreateWindow(@intFromFloat(self.ctx.viewportWidth), @intFromFloat(self.ctx.viewportHeight), "Pong", null, null);
        glfw.glfwSetWindowUserPointer(self.ctx.window, self);
        _ = glfw.glfwSetFramebufferSizeCallback(self.ctx.window, framebufferResizeCallback);
    }

    fn framebufferResizeCallback(window: ?*glfw.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
        _, _ = .{width, height};
        const app: *ApplicationLayer = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(window)));
        app.ctx.framebufferResized.store(true, .release);
    }

    fn mainLoop(self: *ApplicationLayer, ctxComptime: *const ThreadContextComptime) !void {
        defer _ = self.graphicsAPILayer.waitForDevice();

        var gameLogicThread    = try std.Thread.spawn(.{}, GameLayer.run, .{&self.gameLayer, &self.ctx, ctxComptime});
        defer gameLogicThread.join();

        var computeLogicThread = try std.Thread.spawn(.{}, GraphicsAPI.runCompute, .{&self.graphicsAPILayer, &self.ctx});
        defer computeLogicThread.join();

        var renderLogicThread  = try std.Thread.spawn(.{}, GraphicsAPI.runRender, .{&self.graphicsAPILayer, &self.ctx});
        defer renderLogicThread.join();

        defer self.ctx.shouldClose.store(true, .release);

        while (glfw.glfwWindowShouldClose(self.ctx.window.?) == 0) {
            std.Thread.sleep(10 * std.time.ns_per_us);

            glfw.glfwPollEvents();

            const KEY = @TypeOf(self.appInputHandler).KEY;
            if (self.appInputHandler.isKeyClicked(KEY.ESC.asInt())) {
                _ = glfw.glfwSetWindowShouldClose(self.ctx.window, glfw.GLFW_TRUE);
            }

            if (self.ctx.shouldRecreateSwapchain.load(.acquire) and self.ctx.numOfWaitingThreads.load(.acquire) == cfg.NUM_OF_THREADS) {
                try self.recreateSwapChain();

                self.ctx.shouldRecreateSwapchain.store(false, .release);
            }

            const renderAvgFrameTime        = self.ctx.renderAvgFrameTime.load(.acquire);
            const gameCurrPreSyncFrameTime  = self.gameLayer.gameCurrPreSyncFrameTime.load(.acquire);
            const waitTime                  = @max((renderAvgFrameTime / 2 - gameCurrPreSyncFrameTime) * std.time.ns_per_s, 0.0);
            self.ctx.gameLayerSyncWaitTimeNs.store(@intFromFloat(waitTime), .release);
        }
    }

    fn cleanup(self: *ApplicationLayer) !void {
        self.audioDevice.deinit();

        glfw.glfwDestroyWindow(self.ctx.window);

        glfw.glfwTerminate();
    }

    fn recreateSwapChain(self: *ApplicationLayer) !void {
        const frameBufferSize = getFramebufferSize(self.ctx.window);

        self.ctx.viewportWidth  = @floatFromInt(frameBufferSize.width);
        self.ctx.viewportHeight = @floatFromInt(frameBufferSize.height);

        try self.graphicsAPILayer.recreateSwapChain(&self.ctx, frameBufferSize.width, frameBufferSize.height);
        try self.gameLayer.updateForNewViewport(&self.ctx);
    }

    fn getFramebufferSize(window: ?*glfw.GLFWwindow) FrameBufferSize {
        var res: FrameBufferSize = .{.width = 0, .height = 0};
        while (res.width == 0 or res.height == 0) {
            glfw.glfwGetFramebufferSize(window, @ptrCast(&res.width), @ptrCast(&res.height));
            glfw.glfwPollEvents();
        }

        return res;
    }

    fn getRequiredVulkanExtensions(extensionCount: *u32) [*c][*c]const u8 {
        return glfw.glfwGetRequiredInstanceExtensions(extensionCount);
    }

    fn createVulkanSurface(
        ctx:      *ThreadContextRuntime,
        instance: vk.VkInstance,
        surface:  *vk.VkSurfaceKHR,
    ) !void {
        if (glfwLib.glfwCreateWindowSurface(instance, ctx.window, null, surface) != vk.VK_SUCCESS) {
            return error.FailedToCreateAWindowSurface;
        }
    }
};

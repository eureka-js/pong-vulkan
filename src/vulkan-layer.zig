const vk   = @import("bindings/vulkan.zig").vk;
const cglm = @import("bindings//cglm.zig").cglm;

const builtin = @import("builtin");
const std     = @import("std");

const ThreadContextRuntime  = @import("thread-context.zig").ThreadContextRuntime;
const ThreadContextComptime = @import("thread-context.zig").ThreadContextComptime;
const ParticleManager       = @import("particle-manager.zig").ParticleManager;
const Particle              = @import("particle.zig").Particle;
const Node                  = @import("node.zig").Node;
const Vertex                = @import("vertex.zig").Vertex;
const ComputeWorldEntity    = @import("comp-world-entity.zig").ComputeWorldEntity;
const WorldEntityManager    = @import("world-entity-manager.zig").WorldEntityManager;
const BufferManager         = @import("buffer-manager.zig").BufferManager;
const cfg                   = @import("config.zig");
const time                  = @import("time.zig");
const frameTiming           = @import("frame-timing.zig");

const validationLayers       = &[_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
const enableValidationLayers = builtin.mode == .Debug;

const deviceExtensions = &[_][*c]const u8{vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

fn DestroyDebugUtilsMessengerEXT(
    instance:       vk.VkInstance,
    debugMessenger: vk.VkDebugUtilsMessengerEXT,
    pAllocator:     ?*const vk.VkAllocationCallbacks,
) void {
    const func: vk.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(vk.vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
    if (func) |f| {
        f(instance, debugMessenger, pAllocator);
    }
}

const QueueFamilyIndices = struct {
    graphicsAndComputeFamily: ?u32 = null,
    presentFamily:            ?u32 = null,
    transferFamily:           ?u32 = null,

    fn isComplete(self: QueueFamilyIndices) bool {
        return self.graphicsAndComputeFamily != null and self.presentFamily != null and self.transferFamily != null;
    }
};

const SwapChainSupportDetails = struct {
    capabilities: vk.VkSurfaceCapabilitiesKHR,
    formats:      std.ArrayList(vk.VkSurfaceFormatKHR),
    presentModes: std.ArrayList(vk.VkPresentModeKHR),

    allocator:    *const std.mem.Allocator,

    fn init(allocator: *const std.mem.Allocator) !SwapChainSupportDetails {
        return .{
            .capabilities = undefined,
            .formats      = try std.ArrayList(vk.VkSurfaceFormatKHR).initCapacity(allocator.*, 0),
            .presentModes = try std.ArrayList(vk.VkPresentModeKHR).initCapacity(allocator.*, 0),
            .allocator    = allocator,
        };
    }

    fn deinit(self: *SwapChainSupportDetails) void {
        self.formats.deinit(self.allocator.*);
        self.presentModes.deinit(self.allocator.*);
    }
};

const ComputeUniformBufferObject = struct {
    prevPrevDeltaTime:    f32 = 0.0,
    prevDeltaTime:        f32 = 0.0,
    currDeltaTime:        f32 = 0.0,
    particleCurrDeltaTime:f32 = 0.0,
    worldHeight:          f32 = 0.0,
    worldWidth:           f32 = 0.0,
    epsilon:              f32 = 0.0,
    padding_: [1]f32 = undefined,
};

const WorldEntityUniformBufferObject = struct {
    proj: cglm.mat4 align(16) = undefined,
};

const ParticleUniformBufferObject = struct {
    proj:                   cglm.mat4 align(16) = undefined,
    worldUnitsToPixelRatio: f32                 = undefined,
};

pub const VulkanLayer = struct {
    instance: vk.VkInstance   = undefined,
    surface:  vk.VkSurfaceKHR = undefined,

    swapChain:            vk.VkSwapchainKHR = undefined,
    swapChainImages:      []vk.VkImage      = undefined,
    swapChainImageFormat: vk.VkFormat       = undefined,
    swapChainExtent:      vk.VkExtent2D     = undefined,
    swapChainImageViews:  []vk.VkImageView  = undefined,

    debugMessenger: vk.VkDebugUtilsMessengerEXT = undefined,

    physicalDevice: vk.VkPhysicalDevice      = @ptrCast(vk.VK_NULL_HANDLE),
    msaaSamples:    vk.VkSampleCountFlagBits = vk.VK_SAMPLE_COUNT_1_BIT,
    device:         vk.VkDevice              = undefined,

    graphicsQueue: vk.VkQueue = undefined,
    computeQueue:  vk.VkQueue = undefined,
    presentQueue:  vk.VkQueue = undefined,
    transferQueue: vk.VkQueue = undefined,

    renderPass: vk.VkRenderPass = undefined,

    computeDescriptorSetLayout: vk.VkDescriptorSetLayout = undefined,
    computePipelineLayout:      vk.VkPipelineLayout      = undefined,
    computePipeline:            vk.VkPipeline            = undefined,

    graphicsDescriptorSetLayout: vk.VkDescriptorSetLayout = undefined,
    graphicsPipelineLayout:      vk.VkPipelineLayout      = undefined,
    graphicsPipeline:            vk.VkPipeline            = undefined,

    particleDescriptorSetLayout: vk.VkDescriptorSetLayout = undefined,
    particlePipelineLayout:      vk.VkPipelineLayout      = undefined,
    particlePipeline:            vk.VkPipeline            = undefined,

    colorImage:       vk.VkImage        = undefined,
    colorImageMemory: vk.VkDeviceMemory = undefined,
    colorImageView:   vk.VkImageView    = undefined,

    depthImage:       vk.VkImage        = undefined,
    depthImageMemory: vk.VkDeviceMemory = undefined,
    depthImageView:   vk.VkImageView    = undefined,

    swapChainFramebuffers: []vk.VkFramebuffer = undefined,

    computeCommandPool:     vk.VkCommandPool                       = undefined,
    graphicsCommandPool:    vk.VkCommandPool                       = undefined,
    transferCommandPool:    vk.VkCommandPool                       = undefined,
    graphicsCommandBuffers: [cfg.NUM_OF_THREADS]vk.VkCommandBuffer = undefined,
    computeCommandBuffers:  [cfg.NUM_OF_THREADS]vk.VkCommandBuffer = undefined,

    worldEntityRenderBufferManagers: [cfg.NUM_OF_THREADS]BufferManager = undefined,

    particleShaderStorageBuffers:       [cfg.NUM_OF_THREADS]vk.VkBuffer       = undefined,
    particleShaderStorageBuffersMemory: [cfg.NUM_OF_THREADS]vk.VkDeviceMemory = undefined,
    particleStagingBuffer:              vk.VkBuffer                           = undefined,
    particleStagingBufferMemory:        vk.VkDeviceMemory                     = undefined,
    particleStagingBufferMemoryMapped:  [*]u8                                 = undefined,

    computeUniformBuffers:       [cfg.NUM_OF_THREADS]vk.VkBuffer                 = undefined,
    computeUniformBuffersMemory: [cfg.NUM_OF_THREADS]vk.VkDeviceMemory           = undefined,
    computeUniformBuffersMapped: [cfg.NUM_OF_THREADS]*ComputeUniformBufferObject = undefined,

    worldEntityUniformBuffers:       [cfg.NUM_OF_THREADS]vk.VkBuffer                     = undefined,
    worldEntityUniformBuffersMemory: [cfg.NUM_OF_THREADS]vk.VkDeviceMemory               = undefined,
    worldEntityUniformBuffersMapped: [cfg.NUM_OF_THREADS]*WorldEntityUniformBufferObject = undefined,

    particleUniformBuffers:       [cfg.NUM_OF_THREADS]vk.VkBuffer                  = undefined,
    particleUniformBuffersMemory: [cfg.NUM_OF_THREADS]vk.VkDeviceMemory            = undefined,
    particleUniformBuffersMapped: [cfg.NUM_OF_THREADS]*ParticleUniformBufferObject = undefined,

    computeWorldEntityStorageBuffer:             [cfg.NUM_OF_THREADS]vk.VkBuffer       = undefined,
    computeWorldEntityStorageBufferMemory:       [cfg.NUM_OF_THREADS]vk.VkDeviceMemory = undefined,
    computeWorldEntityStorageBufferMapped:       [cfg.NUM_OF_THREADS][*]u8             = undefined,
    computeWorldEntityStagingBuffer:             vk.VkBuffer                           = undefined,
    computeWorldEntityStagingBufferMemory:       vk.VkDeviceMemory                     = undefined,
    computeWorldEntityStagingBufferMemoryMapped: [*]u8                                 = undefined,

    computeDescriptorPool:  vk.VkDescriptorPool                    = undefined,
    graphicsDescriptorPool: vk.VkDescriptorPool                    = undefined,
    particleDescriptorPool: vk.VkDescriptorPool                    = undefined,
    computeDescriptorSets:  [cfg.NUM_OF_THREADS]vk.VkDescriptorSet = undefined,
    graphicsDescriptorSets: [cfg.NUM_OF_THREADS]vk.VkDescriptorSet = undefined,
    particleDescriptorSets: [cfg.NUM_OF_THREADS]vk.VkDescriptorSet = undefined,

    imageAvailableSemaphores:  [cfg.NUM_OF_THREADS]vk.VkSemaphore = undefined,
    renderFinishedSemaphores:  std.ArrayList(vk.VkSemaphore)      = undefined,
    computeFinishedSemaphores: [cfg.NUM_OF_THREADS]vk.VkSemaphore = undefined,
    renderInFlightFences:      [cfg.NUM_OF_THREADS]vk.VkFence     = undefined,
    computeInFlightFences:     [cfg.NUM_OF_THREADS]vk.VkFence     = undefined,

    renderLastTime:             f64                   = 0.0,
    renderDeltaTime:            std.atomic.Value(f32) = std.atomic.Value(f32).init(0.0),
    accumulatedRenderDeltaTime: f32                   = 0.0,
    numOfRenderLoopItterations: f32                   = 0.0,

    computeLastTime:             f64 = 0.0,
    computeDeltaTime:            f32 = 0.0,
    accumulatedComputeDeltaTime: f32 = 0.0,
    numOfComputeLoopItterations: f32 = 0.0,
    computeAvgFrameTime:         std.atomic.Value(f32) = std.atomic.Value(f32).init(0.0),

    worldHeight: f32 = undefined,
    worldWidth:  f32 = undefined,

    allocator:    *const std.mem.Allocator,

    pub fn initPre(
        self:        *VulkanLayer,
        ctx:         *ThreadContextRuntime,
        ctxComptime: *const ThreadContextComptime,
        width:       u32,
        height:      u32,
    ) !void {
        try self.createInstance(ctxComptime);
        try self.setupDebugMessenger();
        try self.createSurface(ctx, ctxComptime);
        try self.pickPhysicalDevice();
        try self.createLogicalDevice();
        try self.createSwapChain(ctx, width, height);
        try self.createImageViews();
        try self.createRenderPass();
        try self.createDescriptorSetLayouts();
        try self.createComputePipeline();
        try self.createGraphicsPipeline();
        try self.createParticlePipeline();
        try self.createCommandPools();
        try self.createColorResources();
        try self.createDepthResources();
        try self.createFramebuffers();
        try self.createAllUniformBuffers();
        try self.createAllDescriptorPool();
        try self.createAllCommandBuffers();
        try self.createSyncObjects();
    }

    pub fn initPost(
        self:               *VulkanLayer,
        particleSize:       usize,
        numOfParticles:     usize,
        worldEntitySize:    usize,
        numOfWorldEntities: usize,
    ) !void {
        try self.createAllDescriptorSets(particleSize, numOfParticles, worldEntitySize, numOfWorldEntities);
    }

    pub fn cleanup(self: *VulkanLayer) !void {
        self.cleanupSwapChain();

        vk.vkDestroyPipeline(self.device, self.particlePipeline, null);
        vk.vkDestroyPipelineLayout(self.device, self.particlePipelineLayout, null);
        vk.vkDestroyPipeline(self.device, self.graphicsPipeline, null);
        vk.vkDestroyPipelineLayout(self.device, self.graphicsPipelineLayout, null);
        vk.vkDestroyPipeline(self.device, self.computePipeline, null);
        vk.vkDestroyPipelineLayout(self.device, self.computePipelineLayout, null);

        vk.vkDestroyRenderPass(self.device, self.renderPass, null);

        for (0..self.particleUniformBuffers.len) |i| {
            vk.vkDestroyBuffer(self.device, self.particleUniformBuffers[i], null);
            vk.vkFreeMemory(self.device, self.particleUniformBuffersMemory[i], null);
        }
        for (0..self.worldEntityUniformBuffers.len) |i| {
            vk.vkDestroyBuffer(self.device, self.worldEntityUniformBuffers[i], null);
            vk.vkFreeMemory(self.device, self.worldEntityUniformBuffersMemory[i], null);
        }
        for (0..self.computeUniformBuffers.len) |i| {
            vk.vkDestroyBuffer(self.device, self.computeUniformBuffers[i], null);
            vk.vkFreeMemory(self.device, self.computeUniformBuffersMemory[i], null);
        }
        for (0..self.computeWorldEntityStorageBuffer.len) |i| {
            vk.vkDestroyBuffer(self.device, self.computeWorldEntityStorageBuffer[i], null);
            vk.vkFreeMemory(self.device, self.computeWorldEntityStorageBufferMemory[i], null);
        }
        vk.vkDestroyBuffer(self.device, self.computeWorldEntityStagingBuffer, null);
        vk.vkFreeMemory(self.device, self.computeWorldEntityStagingBufferMemory, null);

        vk.vkDestroyDescriptorPool(self.device, self.particleDescriptorPool, null);
        vk.vkDestroyDescriptorPool(self.device, self.graphicsDescriptorPool, null);
        vk.vkDestroyDescriptorPool(self.device, self.computeDescriptorPool, null);

        vk.vkDestroyDescriptorSetLayout(self.device, self.particleDescriptorSetLayout, null);
        vk.vkDestroyDescriptorSetLayout(self.device, self.graphicsDescriptorSetLayout, null);
        vk.vkDestroyDescriptorSetLayout(self.device, self.computeDescriptorSetLayout, null);

        for (0..cfg.NUM_OF_THREADS) |i| {
            vk.vkDestroySemaphore(self.device, self.computeFinishedSemaphores[i], null);
            vk.vkDestroySemaphore(self.device, self.imageAvailableSemaphores[i], null);
            vk.vkDestroyFence(self.device, self.computeInFlightFences[i], null);
            vk.vkDestroyFence(self.device, self.renderInFlightFences[i], null);
        }
        for (self.renderFinishedSemaphores.items) |semaphore| {
            vk.vkDestroySemaphore(self.device, semaphore, null);
        }
        self.renderFinishedSemaphores.deinit(self.allocator.*);

        vk.vkDestroyCommandPool(self.device, self.computeCommandPool , null);
        vk.vkDestroyCommandPool(self.device, self.graphicsCommandPool , null);
        vk.vkDestroyCommandPool(self.device, self.transferCommandPool, null);

        vk.vkDestroyDevice(self.device, null);

        if (enableValidationLayers) {
            DestroyDebugUtilsMessengerEXT(self.instance, self.debugMessenger, null);
        }

        vk.vkDestroySurfaceKHR(self.instance, self.surface, null);
        vk.vkDestroyInstance(self.instance, null);
    }

    fn cleanupSwapChain(self: *VulkanLayer) void {
        vk.vkDestroyImageView(self.device, self.colorImageView, null);
        vk.vkDestroyImage(self.device, self.colorImage, null);
        vk.vkFreeMemory(self.device, self.colorImageMemory, null);

        vk.vkDestroyImageView(self.device, self.depthImageView, null);
        vk.vkDestroyImage(self.device, self.depthImage, null);
        vk.vkFreeMemory(self.device, self.depthImageMemory, null);

        for (self.swapChainFramebuffers) |framebuffer| {
            vk.vkDestroyFramebuffer(self.device, framebuffer, null);
        }
        self.allocator.free(self.swapChainFramebuffers);

        for (self.swapChainImageViews) |imageView| {
            vk.vkDestroyImageView(self.device, imageView, null);
        }
        self.allocator.free(self.swapChainImageViews);

        vk.vkDestroySwapchainKHR(self.device, self.swapChain, null);
        self.allocator.free(self.swapChainImages);
    }

    pub fn recreateSwapChain(
        self:   *VulkanLayer,
        ctx:    *ThreadContextRuntime,
        width:  u32,
        height: u32,
    ) !void {
        _ = vk.vkDeviceWaitIdle(self.device);

        self.cleanupSwapChain();

        try self.createSwapChain(ctx, width, height);
        try self.createImageViews();
        try self.createColorResources();
        try self.createDepthResources();
        try self.createFramebuffers();
    }

    pub fn runCompute(self: *VulkanLayer, ctx: *ThreadContextRuntime) !void {
        self.computeLastTime = time.getTimeInSeconds();

        while (!ctx.shouldClose.load(.acquire)) {
            std.Thread.sleep(10 * std.time.ns_per_us);

            if (ctx.shouldRecreateSwapchain.load(.acquire)) {
                for (0..cfg.NUM_OF_THREADS) |i| {
                    _ = vk.vkWaitForFences(self.device, 1, &self.computeInFlightFences[i], vk.VK_TRUE, vk.UINT64_MAX);
                }

                _ = ctx.numOfWaitingThreads.fetchAdd(1, .acq_rel);
                while (ctx.shouldRecreateSwapchain.load(.acquire)) {
                    std.Thread.sleep(10 * std.time.ns_per_us);
                }
                _ = ctx.numOfWaitingThreads.fetchSub(1, .acq_rel);
            }

            const currComputeIndex = ctx.threadStates.currComputeIndex;
            if (ctx.threadStates.states[currComputeIndex].load(.acquire) != .COMPUTE) {
                continue;
            }

            const currTime             = time.getTimeInSeconds();
            defer self.computeLastTime = currTime;
            self.computeDeltaTime      = @floatCast(currTime - self.computeLastTime);

            try self.computeFrame(currComputeIndex, ctx);

            const nextComputeIndex = (currComputeIndex + 1) % cfg.NUM_OF_THREADS;
            ctx.threadStates.currComputeIndex = nextComputeIndex;
            ctx.threadStates.states[currComputeIndex].store(.RENDER, .release);

            frameTiming.updateFrameTime(self.computeDeltaTime, &self.accumulatedComputeDeltaTime, &self.numOfComputeLoopItterations, &self.computeAvgFrameTime);
            //if (self.accumulatedComputeDeltaTime == 0.0) {
            //    frameTiming.showFrameTime("Compute", self.computeAvgFrameTime.load(.acquire));
            //}
        }
    }

    pub fn runRender(self: *VulkanLayer, ctx: *ThreadContextRuntime) !void {
        self.renderLastTime = time.getTimeInSeconds();

        while (!ctx.shouldClose.load(.acquire)) {
            std.Thread.sleep(10 * std.time.ns_per_us);

            if (ctx.shouldRecreateSwapchain.load(.acquire)) {
                for (0..cfg.NUM_OF_THREADS) |i| {
                    _ = vk.vkWaitForFences(self.device, 1, &self.renderInFlightFences[i], vk.VK_TRUE, vk.UINT64_MAX);
                }

                _ = ctx.numOfWaitingThreads.fetchAdd(1, .acq_rel);
                while (ctx.shouldRecreateSwapchain.load(.acquire)) {
                    std.Thread.sleep(10 * std.time.ns_per_us);
                }
                _ = ctx.numOfWaitingThreads.fetchSub(1, .acq_rel);
            }

            const currRenderIndex = ctx.threadStates.currRenderIndex;
            if (ctx.threadStates.states[currRenderIndex].load(.acquire) != .RENDER) {
                continue;
            }

            const currTime            = time.getTimeInSeconds();
            defer self.renderLastTime = currTime;
            const deltaTime: f32      = @floatCast(currTime - self.renderLastTime);
            self.renderDeltaTime.store(deltaTime, .release);

            try self.drawFrame(ctx, currRenderIndex);

            ctx.threadStates.currRenderIndex = (currRenderIndex + 1) % cfg.NUM_OF_THREADS;
            ctx.threadStates.states[currRenderIndex].store(.GAME, .release);

            frameTiming.updateFrameTime(deltaTime, &self.accumulatedRenderDeltaTime, &self.numOfRenderLoopItterations, &ctx.renderAvgFrameTime);
            //if (self.accumulatedRenderDeltaTime == 0.0) {
            //    frameTiming.showFrameTime("Render", ctx.renderAvgFrameTime.load(.acquire));
            //}
        }
    }

    fn computeFrame(
        self:             *VulkanLayer,
        currComputeIndex: usize,
        ctx:              *ThreadContextRuntime,
    ) !void {
        // NOTE: vkWaitForFences already executes in the gameLogicThread so it is not neccessary here. (2025-11-19)

        self.updateComputeUniformBuffer(ctx, currComputeIndex);

        _ = vk.vkResetFences(self.device, 1, &self.computeInFlightFences[currComputeIndex]);

        _ = vk.vkResetCommandBuffer(self.computeCommandBuffers[currComputeIndex], 0);
        try self.recordComputeCommandBuffer(self.computeCommandBuffers[currComputeIndex], currComputeIndex);

        const computeSubmitInfo: vk.VkSubmitInfo = .{
            .sType                = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount   = 1,
            .pCommandBuffers      = &self.computeCommandBuffers[currComputeIndex],
            .signalSemaphoreCount = 1,
            .pSignalSemaphores    = &self.computeFinishedSemaphores[currComputeIndex],
        };

        while (ctx.isGraphicsAndComputeQueueBeingAccessed.load(.acquire)) {
            std.Thread.sleep(10 * std.time.ns_per_us);
        }
        ctx.isGraphicsAndComputeQueueBeingAccessed.store(true, .release);
        defer ctx.isGraphicsAndComputeQueueBeingAccessed.store(false, .release);
        if (vk.vkQueueSubmit(self.computeQueue, 1, &computeSubmitInfo, self.computeInFlightFences[currComputeIndex]) != vk.VK_SUCCESS) {
            return error.FailedToSubmitComputeCommandBuffer;
        }
    }

    fn drawFrame(
        self:        *VulkanLayer,
        ctx:         *ThreadContextRuntime,
        renderIndex: usize,
    ) !void {
        // NOTE: vkWaitForFences already executes in the gameLogicThread so it is not neccessary here. (2025-11-19)

        var imageIndex: u32 = undefined;

        switch (vk.vkAcquireNextImageKHR(self.device, self.swapChain, vk.UINT64_MAX, self.imageAvailableSemaphores[renderIndex], @ptrCast(vk.VK_NULL_HANDLE), &imageIndex)) {
            vk.VK_SUCCESS, vk.VK_SUBOPTIMAL_KHR => {},
            vk.VK_ERROR_OUT_OF_DATE_KHR         => {
                ctx.shouldRecreateSwapchain.store(true, .release);
                return;
            },
            else => return error.FailedToAcquireSwapChainImage,
        }

        self.updateWorldEntityUniformBufferObject(renderIndex);
        self.updateParticleUniformBufferObject(renderIndex, ctx);

        _ = vk.vkResetFences(self.device, 1, &self.renderInFlightFences[renderIndex]);

        _ = vk.vkResetCommandBuffer(self.graphicsCommandBuffers[renderIndex], 0);
        try self.recordCommandBuffer(self.graphicsCommandBuffers[renderIndex], imageIndex, renderIndex);

        const waitSemaphores   = [_]vk.VkSemaphore{
            self.computeFinishedSemaphores[renderIndex],
            self.imageAvailableSemaphores[renderIndex]
        };
        const waitStages       = [_]vk.VkPipelineStageFlags{
            vk.VK_PIPELINE_STAGE_VERTEX_INPUT_BIT,
            vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        };
        const signalSemaphores = [_]vk.VkSemaphore{self.renderFinishedSemaphores.items[imageIndex]};
        const graphicsSubmitInfo: vk.VkSubmitInfo = .{
            .sType                = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount   = waitSemaphores.len,
            .pWaitSemaphores      = &waitSemaphores,
            .pWaitDstStageMask    = &waitStages,
            .commandBufferCount   = 1,
            .pCommandBuffers      = &self.graphicsCommandBuffers[renderIndex],
            .signalSemaphoreCount = 1,
            .pSignalSemaphores    = &signalSemaphores,
        };

        while (ctx.isGraphicsAndComputeQueueBeingAccessed.load(.acquire)) {
            std.Thread.sleep(10 * std.time.ns_per_us);
        }
        ctx.isGraphicsAndComputeQueueBeingAccessed.store(true, .release);
        defer ctx.isGraphicsAndComputeQueueBeingAccessed.store(false, .release);
        if (vk.vkQueueSubmit(self.graphicsQueue, 1, &graphicsSubmitInfo, self.renderInFlightFences[renderIndex]) != vk.VK_SUCCESS) {
            return error.FailedToSubmitDrawCommandBuffer;
        }

        const swapChains = &[_]vk.VkSwapchainKHR{self.swapChain};
        const presentInfo: vk.VkPresentInfoKHR = .{
            .sType              = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores    = &signalSemaphores,
            .swapchainCount     = 1,
            .pSwapchains        = swapChains.ptr,
            .pImageIndices      = &imageIndex,
            .pResults           = null, // Optional
        };

        const result = vk.vkQueuePresentKHR(self.presentQueue, &presentInfo);
        if (result == vk.VK_ERROR_OUT_OF_DATE_KHR or result == vk.VK_SUBOPTIMAL_KHR or ctx.framebufferResized.load(.acquire)) {
            ctx.framebufferResized.store(false, .release);
            ctx.shouldRecreateSwapchain.store(true, .release);
        } else if (result != vk.VK_SUCCESS) {
            return error.FailedToPresentSwapChainImage;
        }
    }

    fn updateComputeUniformBuffer(
        self:             *VulkanLayer,
        ctx:              *ThreadContextRuntime,
        currComputeIndex: usize
    ) void {
        const deltaTimes = &ctx.accumulatedGameDeltaTimesSnapshot[currComputeIndex];

        self.computeUniformBuffersMapped[currComputeIndex].* = .{
            .prevPrevDeltaTime     = deltaTimes[0].load(.acquire),
            .prevDeltaTime         = deltaTimes[1].load(.acquire),
            .currDeltaTime         = deltaTimes[2].load(.acquire),
            .particleCurrDeltaTime = ParticleManager.SPAWN_DELTA_TIME,
            .worldHeight           = self.worldHeight,
            .worldWidth            = self.worldWidth,
            .epsilon               = cfg.GENERAL_PURPOSE_EPSILON / 2,
        };
    }

    fn updateWorldEntityUniformBufferObject(self: *VulkanLayer, renderIndex: usize) void {
        var ubo: WorldEntityUniformBufferObject align(32) = undefined;
        cglm.glm_mat4_identity(&ubo.proj);

        // NOTE: worldHeight value is used as a bottom and 0 as a top because Vulkan's framebuffer origin is top-left instead of bottom-left. (2025-10-03)
        cglm.glm_ortho(0.0, self.worldWidth, self.worldHeight, 0.0, 0.0, -1.0, &ubo.proj);

        self.worldEntityUniformBuffersMapped[renderIndex].* = ubo;
    }

    fn updateParticleUniformBufferObject(
        self:        *VulkanLayer,
        renderIndex: usize,
        ctx:         *ThreadContextRuntime,
    ) void {
        var ubo: ParticleUniformBufferObject align(32) = undefined;
        cglm.glm_mat4_identity(&ubo.proj);
        ubo.worldUnitsToPixelRatio = ctx.viewportHeight / self.worldHeight;

        // NOTE: worldHeight value is used as a bottom and 0 as a top because Vulkan's framebuffer origin is top-left instead of bottom-left. (2025-10-03)
        cglm.glm_ortho(0.0, self.worldWidth, self.worldHeight, 0.0, 0.0, -1.0, &ubo.proj);

        self.particleUniformBuffersMapped[renderIndex].* = ubo;
    }

    fn recordComputeCommandBuffer(
        self:             *VulkanLayer,
        commandBuffer:    vk.VkCommandBuffer,
        currComputeIndex: usize,
    ) !void {
        const beginInfo: vk.VkCommandBufferBeginInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        };

        if (vk.vkBeginCommandBuffer(commandBuffer, &beginInfo) != vk.VK_SUCCESS) {
            return error.FailedToBeginRecordingComputeCommandBuffer;
        }

        vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_COMPUTE, self.computePipeline);

        vk.vkCmdBindDescriptorSets(commandBuffer, vk.VK_PIPELINE_BIND_POINT_COMPUTE, self.computePipelineLayout, 0, 1, &self.computeDescriptorSets[currComputeIndex], 0, null);

        const localSizeX = comptime blk: {
            const tmp = 256;
            std.debug.assert(ParticleManager.PARTICLE_COUNT % tmp == 0);
            break :blk tmp;
        };
        vk.vkCmdDispatch(commandBuffer, ParticleManager.PARTICLE_COUNT / localSizeX, 1, 1);

        if (vk.vkEndCommandBuffer(commandBuffer) != vk.VK_SUCCESS) {
            return error.FailedToRecordComputeCommandBuffer;
        }
    }

    fn recordCommandBuffer(
        self:          *VulkanLayer,
        commandBuffer: vk.VkCommandBuffer,
        imageIndex:    u32,
        renderIndex:   usize,
    ) !void {
        const beginInfo: vk.VkCommandBufferBeginInfo = .{
            .sType            = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags            = 0,    // Optional
            .pInheritanceInfo = null, // Optional
        };

        if (vk.vkBeginCommandBuffer(commandBuffer, &beginInfo) != vk.VK_SUCCESS) {
            return error.FailedToBeginRecordingFramebuffer;
        }

        const clearValues = [_]vk.VkClearValue{
            .{.color = .{ .float32 = .{0.005, 0.005, 0.005, 1.0} }},
            .{.depthStencil = .{ .depth = 1.0, .stencil = 0}},
        };
        const renderPassInfo: vk.VkRenderPassBeginInfo = .{
            .sType           = vk.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass      = self.renderPass,
            .framebuffer     = self.swapChainFramebuffers[imageIndex],
            .renderArea      = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.swapChainExtent,
            },
            .clearValueCount = clearValues.len,
            .pClearValues    = &clearValues,
        };

        vk.vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, vk.VK_SUBPASS_CONTENTS_INLINE);

        const viewPort: vk.VkViewport = .{
            .x        = 0.0,
            .y        = 0.0,
            .width    = @floatFromInt(self.swapChainExtent.width),
            .height   = @floatFromInt(self.swapChainExtent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        vk.vkCmdSetViewport(commandBuffer, 0, 1, &viewPort);

        const scissor: vk.VkRect2D = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapChainExtent,
        };
        vk.vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

        {
            const entityBuffer = &self.worldEntityRenderBufferManagers[renderIndex];

            vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.graphicsPipeline);

            const vertexBuffers = [_]vk.VkBuffer{entityBuffer.vertexBuffer};
            const offsets       = [_]vk.VkDeviceSize{0};
            vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers, &offsets);

            vk.vkCmdBindIndexBuffer(commandBuffer, entityBuffer.indexBuffer, 0, vk.VK_INDEX_TYPE_UINT32);

            vk.vkCmdBindDescriptorSets(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.graphicsPipelineLayout, 0, 1, &self.graphicsDescriptorSets[renderIndex], 0, null);

            for (entityBuffer.data.items) |*item| {
                self.recordGraphicsIndexedDrawCmd(commandBuffer, item.node, item.firstVertex, item.firstIndex);
            }
        }

        {
            vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.particlePipeline);

            const vertexBuffers = [_]vk.VkBuffer{self.particleShaderStorageBuffers[renderIndex]};
            const offsets       = [_]vk.VkDeviceSize{0};
            vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers, &offsets);
            vk.vkCmdBindDescriptorSets(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.particlePipelineLayout, 0, 1, &self.particleDescriptorSets[renderIndex], 0, null);

            vk.vkCmdDraw(commandBuffer, ParticleManager.PARTICLE_COUNT, 1, 0, 0);
        }

        vk.vkCmdEndRenderPass(commandBuffer);

        if (vk.vkEndCommandBuffer(commandBuffer) != vk.VK_SUCCESS) {
            return error.FailedToRecordCommandBuffer;
        }
    }

    fn recordGraphicsIndexedDrawCmd(
        self:          *VulkanLayer,
        commandBuffer: vk.VkCommandBuffer,
        node:          *const Node,
        firstVertex:   i32,
        firstIndex:    u32,
    ) void {
        const PushData = struct {
            translation: [2]f32,
            depth:       f32,
            opacity:     f32,
        };
        const pushData: PushData = .{
            .translation = node.translation,
            .depth       = node.depth,
            .opacity     = node.opacity,
        };

        vk.vkCmdPushConstants(
            commandBuffer,
            self.graphicsPipelineLayout,
            vk.VK_SHADER_STAGE_VERTEX_BIT,
            0,
            @sizeOf(@TypeOf(pushData)),
            &pushData
        );

        vk.vkCmdDrawIndexed(commandBuffer, @intCast(node.mesh.indices.items.len), 1, firstIndex, firstVertex, 0);
    }

    fn createInstance(self: *VulkanLayer, ctxComptime: *const ThreadContextComptime) !void {
        if (enableValidationLayers and !(try checkValidationLayerSupport(self.allocator))) {
            return error.ValidationLayersNotFound;
        }

        const appInfo: vk.VkApplicationInfo = .{
            .sType              = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName   = "Pong",
            .applicationVersion = vk.VK_MAKE_VERSION(1, 0, 0),
            .pEngineName        = "PongEngine",
            .engineVersion      = vk.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion         = vk.VK_API_VERSION_1_0,
        };

        var extensions = try getRequiredExtensions(self.allocator, ctxComptime);
        defer extensions.deinit(self.allocator.*);
        var createInfo: vk.VkInstanceCreateInfo = .{};
        createInfo.sType                   = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        createInfo.pApplicationInfo        = &appInfo;
        createInfo.enabledExtensionCount   = @intCast(extensions.items.len);
        createInfo.ppEnabledExtensionNames = extensions.items.ptr;
        var debugCreateInfo: vk.VkDebugUtilsMessengerCreateInfoEXT = undefined;
        if (enableValidationLayers) {
            createInfo.enabledLayerCount   = validationLayers.len;
            createInfo.ppEnabledLayerNames = validationLayers.ptr;

            populateDebugMessengerCreateInfo(&debugCreateInfo);
            createInfo.pNext = &debugCreateInfo;
        } else {
            createInfo.enabledLayerCount = 0;
            createInfo.pNext             = null;
        }

        if (vk.vkCreateInstance(&createInfo, null, &self.instance) != vk.VK_SUCCESS) {
            return error.FailedToCreateInstance;
        }
    }

    fn checkValidationLayerSupport(allocator: *const std.mem.Allocator) !bool {
        var layerCount: u32 = 0;
        _ = vk.vkEnumerateInstanceLayerProperties(&layerCount, null);

        const availableLayers = try allocator.alloc(vk.VkLayerProperties, layerCount);
        defer allocator.free(availableLayers);
        _ = vk.vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.ptr);

        outer: for (validationLayers) |layerName| {
            const name = std.mem.span(layerName);
            for (availableLayers) |property| {
                const property_name = std.mem.sliceTo(&property.layerName, 0);
                if (std.mem.eql(u8, name, property_name)) {
                    continue :outer;
                }
            }

            return false;
        }
        return true;
    }

    fn getRequiredExtensions( allocator: *const std.mem.Allocator, ctxComptime: *const ThreadContextComptime) !std.ArrayList([*c]const u8) {
        var glfwExtensionCount: u32 = 0;
        const glfwExtensions = ctxComptime.appRelated.getRequiredVulkanExtensions(&glfwExtensionCount);

        var extensions = try std.ArrayList([*c]const u8).initCapacity(allocator.*, 0);
        for (0..glfwExtensionCount) |i| {
            try extensions.append(allocator.*, glfwExtensions[i]);
        }
        if (enableValidationLayers) {
            try extensions.append(allocator.*, vk.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
        }

        return extensions;
    }

    fn populateDebugMessengerCreateInfo(createInfo: *vk.VkDebugUtilsMessengerCreateInfoEXT) void {
        createInfo.* = .{
            .sType           = vk.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            .messageSeverity = vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
            .messageType     = vk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
            .pfnUserCallback = debugCallback,
            .pUserData       = null,
        };
    }

    fn debugCallback(
        messageSeverity: vk.VkDebugUtilsMessageSeverityFlagBitsEXT,
        messageType:     vk.VkDebugUtilsMessageTypeFlagsEXT,
        pCallbackData:   [*c]const vk.VkDebugUtilsMessengerCallbackDataEXT,
        pUserData:       ?*anyopaque,
    ) callconv(.c) vk.VkBool32 {
        _, _, _ = .{&messageSeverity, &messageType, &pUserData};
        std.debug.print("validation layer: {s}\n", .{pCallbackData.*.pMessage});

        return vk.VK_FALSE;
    }

    fn setupDebugMessenger(self: *VulkanLayer) !void {
        if (!enableValidationLayers) {
            return;
        }

        var createInfo: vk.VkDebugUtilsMessengerCreateInfoEXT = undefined;
        populateDebugMessengerCreateInfo(&createInfo);
        if (createDebugUtilMessengerEXT(self.instance, &createInfo, null, &self.debugMessenger) != vk.VK_SUCCESS) {
            return error.FailedToSetupDebugMessenger;
        }
    }

    fn createDebugUtilMessengerEXT(
        instance:        vk.VkInstance,
        pCreateInfo:     *vk.VkDebugUtilsMessengerCreateInfoEXT,
        pAllocator:      ?*const vk.VkAllocationCallbacks,
        pDebugMessenger: *vk.VkDebugUtilsMessengerEXT,
    ) vk.VkResult {
        const func: vk.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(vk.vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
        if (func) |f| {
            return f(instance, pCreateInfo, pAllocator, pDebugMessenger);
        } else {
            return vk.VK_ERROR_EXTENSION_NOT_PRESENT;
        }
    }

    fn createSurface(
        self:        *VulkanLayer,
        ctx:         *ThreadContextRuntime,
        ctxComptime: *const ThreadContextComptime,
    ) !void {
        try ctxComptime.appRelated.createVulkanSurface(ctx, self.instance, &self.surface);
    }

    fn pickPhysicalDevice(self: *VulkanLayer) !void {
        var deviceCount: u32 = 0;
        _ = vk.vkEnumeratePhysicalDevices(self.instance, &deviceCount, null);
        if (deviceCount == 0) {
            return error.FailedToFindGpuWithVulkanSupport;
        }

        const devices = try self.allocator.alloc(vk.VkPhysicalDevice, deviceCount);
        defer self.allocator.free(devices);
        _ = vk.vkEnumeratePhysicalDevices(self.instance, &deviceCount, devices.ptr);
        for (devices) |device| {
            if (try isDeviceSuitable(device, self.surface, self.allocator)) {
                self.physicalDevice = device;
                self.msaaSamples    = try self.getMaxUsableSampleCount();
                break;
            }
        }

        if (self.physicalDevice == @as(vk.VkPhysicalDevice, @ptrCast(vk.VK_NULL_HANDLE))) {
            return error.FailedToFindASuitableGpu;
        }
    }

    fn isDeviceSuitable(
        device:    vk.VkPhysicalDevice,
        surface:   vk.VkSurfaceKHR,
        allocator: *const std.mem.Allocator,
    ) !bool {
        const familyIndices = try findQueueFamilies(device, surface, allocator);
        if (!familyIndices.isComplete()) {
            return false;
        }

        const extensionsSupported = try checkDeviceExtensionSupport(device, allocator);
        if (!extensionsSupported) {
            return false;
        }

        var swapChainSupport = try SwapChainSupportDetails.init(allocator);
        defer swapChainSupport.deinit();
        try querySwapChainSupport(device, surface, &swapChainSupport);
        const swapChainAdequate = swapChainSupport.formats.items.len > 0 and swapChainSupport.presentModes.items.len > 0;
        if (!swapChainAdequate) {
            return false;
        }

        var supportedFeatures: vk.VkPhysicalDeviceFeatures = undefined;
        vk.vkGetPhysicalDeviceFeatures(device, &supportedFeatures);
        if (supportedFeatures.samplerAnisotropy != vk.VK_TRUE) {
            return false;
        }

        return true;
    }

    fn findQueueFamilies(
        device:    vk.VkPhysicalDevice,
        surface:   vk.VkSurfaceKHR,
        allocator: *const std.mem.Allocator
    ) !QueueFamilyIndices {
        var familyIndices: QueueFamilyIndices = .{};

        var queueFamilyCount: u32 = 0;
        vk.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);
        const queueFamilies = try allocator.alloc(vk.VkQueueFamilyProperties, queueFamilyCount);
        defer allocator.free(queueFamilies);
        vk.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);
        for (queueFamilies, 0..) |queueFamily, i| {
            // NOTE: The same queue family used for both drawing and presentation would yield improved performance
            // compared to this loop implementation (even though it can happen in this implementation
            // that the same queue family gets selected for both). (2025-04-19)
            // IMPORTANT: There is no fallback for when the transfer queue family is not found for familyIndices.transferFamily
            // because the tutorial task requires that transfer queue is selected from a queue family that doesn't contain the graphics queue. (2025-06-04)

            if ((queueFamily.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT) != 0) {
                if ((queueFamily.queueFlags & vk.VK_QUEUE_COMPUTE_BIT) != 0) {
                    familyIndices.graphicsAndComputeFamily = @intCast(i);
                }
            } else if ((queueFamily.queueFlags & vk.VK_QUEUE_TRANSFER_BIT) != 0) {
                familyIndices.transferFamily = @intCast(i);
            }

            var doesSupportPresent: vk.VkBool32 = 0;
            _ = vk.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface, &doesSupportPresent);
            if (doesSupportPresent != 0) {
                familyIndices.presentFamily = @intCast(i);
            }

            if (familyIndices.isComplete()) {
                break;
            }
        }

        return familyIndices;
    }

    fn checkDeviceExtensionSupport(device: vk.VkPhysicalDevice, allocator: *const std.mem.Allocator) !bool {
        var extensionCount: u32 = 0;
        _ = vk.vkEnumerateDeviceExtensionProperties(device, null, &extensionCount, null);
        const availableExtensions = try allocator.alloc(vk.VkExtensionProperties, extensionCount);
        defer allocator.free(availableExtensions);
        _ = vk.vkEnumerateDeviceExtensionProperties(device, null, &extensionCount, availableExtensions.ptr);

        var requiredExtensions = std.StringHashMap(void).init(allocator.*);
        defer requiredExtensions.deinit();
        for (deviceExtensions) |extensionName| {
            const name = std.mem.span(extensionName);
            try requiredExtensions.put(name, {});
        }
        for (availableExtensions) |extension| {
            const name = std.mem.sliceTo(&extension.extensionName, 0);
            _ = requiredExtensions.remove(name);
        }

        return requiredExtensions.count() == 0;
    }

    fn createLogicalDevice(self: *VulkanLayer) !void {
        const familyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);

        var queueCreateInfos = try std.ArrayList(vk.VkDeviceQueueCreateInfo).initCapacity(self.allocator.*, 0);
        defer queueCreateInfos.deinit(self.allocator.*);

        var uniqueQueueFamilies = std.AutoHashMap(u32, void).init(self.allocator.*);
        defer uniqueQueueFamilies.deinit();
        try uniqueQueueFamilies.put(familyIndices.graphicsAndComputeFamily.?, {});
        try uniqueQueueFamilies.put(familyIndices.presentFamily.?, {});
        try uniqueQueueFamilies.put(familyIndices.transferFamily.?, {});
        const queuePriority: f32 = 1.0;
        var it = uniqueQueueFamilies.iterator();
        while (it.next()) |entry| {
            const queueCreateInfo: vk.VkDeviceQueueCreateInfo = .{
                .sType            = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = entry.key_ptr.*,
                .queueCount       = 1,
                .pQueuePriorities = &queuePriority,
            };
            try queueCreateInfos.append(self.allocator.*, queueCreateInfo);
        }

        var deviceFeatures: vk.VkPhysicalDeviceFeatures = .{};
        const createInfo: vk.VkDeviceCreateInfo = .{
            .sType                   = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .queueCreateInfoCount    = @intCast(queueCreateInfos.items.len),
            .pQueueCreateInfos       = queueCreateInfos.items.ptr,
            .pEnabledFeatures        = &deviceFeatures,
            .enabledExtensionCount   = @intCast(deviceExtensions.len),
            .ppEnabledExtensionNames = deviceExtensions.ptr,
        };
        if (vk.vkCreateDevice(self.physicalDevice, &createInfo, null, &self.device) != vk.VK_SUCCESS) {
            return error.FailedToCreateLogicalDevice;
        }

        vk.vkGetDeviceQueue(self.device, familyIndices.graphicsAndComputeFamily.?, 0, &self.graphicsQueue);
        vk.vkGetDeviceQueue(self.device, familyIndices.graphicsAndComputeFamily.?, 0, &self.computeQueue);
        vk.vkGetDeviceQueue(self.device, familyIndices.presentFamily.?, 0, &self.presentQueue);
        vk.vkGetDeviceQueue(self.device, familyIndices.transferFamily.?, 0, &self.transferQueue);
    }

    fn querySwapChainSupport(
        device:    vk.VkPhysicalDevice,
        surface:   vk.VkSurfaceKHR,
        details:   *SwapChainSupportDetails
    ) !void {
        _ = vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &details.capabilities);

        var formatCount: u32 = 0;
        _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, null);
        if (formatCount != 0) {
            try details.formats.ensureTotalCapacity(details.allocator.*, formatCount);
            try details.formats.resize(details.allocator.*, formatCount);
            _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, details.formats.items.ptr);
        }

        var presentModeCount: u32 = 0;
        _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, null);
        if (presentModeCount != 0) {
            try details.presentModes.ensureTotalCapacity(details.allocator.*, presentModeCount);
            try details.presentModes.resize(details.allocator.*, presentModeCount);
            _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, details.presentModes.items.ptr);
        }
    }


    fn createSwapChain(
        self:              *VulkanLayer,
        ctx:               *ThreadContextRuntime,
        frameBufferWidth:  u32,
        frameBufferHeight: u32,
    ) !void {
        var swapChainSupport = try SwapChainSupportDetails.init(self.allocator);
        defer swapChainSupport.deinit();
        try querySwapChainSupport(self.physicalDevice, self.surface, &swapChainSupport);

        const surfaceFormat       = chooseSwapChainSurfaceFormat(&swapChainSupport.formats);
        self.swapChainImageFormat = surfaceFormat.format;

        const presentMode = chooseSwapPresentMode(&swapChainSupport.presentModes);

        const extent         = chooseSwapExtent(&swapChainSupport.capabilities, frameBufferWidth, frameBufferHeight);
        self.swapChainExtent = extent;

        var imageCount: u32 = swapChainSupport.capabilities.minImageCount + 1;
        if (swapChainSupport.capabilities.maxImageCount > 0 and imageCount > swapChainSupport.capabilities.maxImageCount) {
            imageCount = swapChainSupport.capabilities.maxImageCount;
        }

        var createInfo: vk.VkSwapchainCreateInfoKHR = .{
            .sType            = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface          = self.surface,
            .minImageCount    = imageCount,
            .imageFormat      = surfaceFormat.format,
            .imageExtent      = extent,
            .imageArrayLayers = 1,
            .imageUsage       = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .preTransform     = swapChainSupport.capabilities.currentTransform,
            .compositeAlpha   = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode      = presentMode,
            .clipped          = vk.VK_TRUE,
            .oldSwapchain     = @ptrCast(vk.VK_NULL_HANDLE),
        };

        const familyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);
        if (familyIndices.graphicsAndComputeFamily == familyIndices.presentFamily) {
            createInfo.imageSharingMode      = vk.VK_SHARING_MODE_EXCLUSIVE;
        } else {
            createInfo.imageSharingMode      = vk.VK_SHARING_MODE_CONCURRENT;
            createInfo.queueFamilyIndexCount = 2;
            createInfo.pQueueFamilyIndices   = &[_]u32{ familyIndices.graphicsAndComputeFamily.?, familyIndices.presentFamily.?};
        }

        if (vk.vkCreateSwapchainKHR(self.device, &createInfo, null, &self.swapChain) != vk.VK_SUCCESS) {
            return error.FailedToCreateSwapChain;
        }

        _ = vk.vkGetSwapchainImagesKHR(self.device, self.swapChain, &imageCount, null);
        self.swapChainImages = try self.allocator.alloc(vk.VkImage, imageCount);
        _ = vk.vkGetSwapchainImagesKHR(self.device, self.swapChain, &imageCount, self.swapChainImages.ptr);

        const width:  f32 = @floatFromInt(self.swapChainExtent.width);
        const height: f32 = @floatFromInt(self.swapChainExtent.height);
        const aspectRatio = width / height;
        self.worldHeight = cfg.WORLD_HEIGHT;
        self.worldWidth  = self.worldHeight * aspectRatio;
        ctx.aspectRatio = aspectRatio;
    }

    fn chooseSwapChainSurfaceFormat(availableFormats: *const std.ArrayList(vk.VkSurfaceFormatKHR)) vk.VkSurfaceFormatKHR {
        for (availableFormats.items) |availableFormat| {
            if (availableFormat.format == vk.VK_FORMAT_B8G8R8A8_SRGB and availableFormat.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                return availableFormat;
            }
        }

        return availableFormats.items[0];
    }

    fn chooseSwapPresentMode(availablePresentModes: *const std.ArrayList(vk.VkPresentModeKHR)) vk.VkPresentModeKHR {
        _ = availablePresentModes;

        // NOTE: VK_PRESENT_MODE_MAILBOX_KHR is not selected because it causes the GPU to have a greater power usage
        //  and an audible coil whine. VK_PRESENT_MODE_FIFO_KHR limits the GPU to the monitor's refresh rate. (2025-12-18)
        //for (availablePresentModes.items) |availablePresentMode| {
        //    if (availablePresentMode == vk.VK_PRESENT_MODE_MAILBOX_KHR) {
        //        return availablePresentMode;
        //    }
        //}
        return vk.VK_PRESENT_MODE_FIFO_KHR;
    }

    fn chooseSwapExtent(
        capabilities: *const vk.VkSurfaceCapabilitiesKHR,
        width:        u32,
        height:       u32,
    ) vk.VkExtent2D {
        if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
            return capabilities.currentExtent;
        }

        const actualExtent: vk.VkExtent2D = .{
            .width  = std.math.clamp(
                width,
                capabilities.minImageExtent.width,
                capabilities.maxImageExtent.width,
            ),
            .height = std.math.clamp(
                height,
                capabilities.minImageExtent.height,
                capabilities.maxImageExtent.height,
            ),
        };

        return actualExtent;
    }

    fn createImageViews(self: *VulkanLayer) !void {
        self.swapChainImageViews = try self.allocator.alloc(vk.VkImageView, self.swapChainImages.len);

        for (0..self.swapChainImages.len) |i| {
            self.swapChainImageViews[i] = try self.createImageView(self.swapChainImages[i], self.swapChainImageFormat, vk.VK_IMAGE_ASPECT_COLOR_BIT);
        }
    }

    fn createRenderPass(self: *VulkanLayer) !void {
        const colorAttachment: vk.VkAttachmentDescription = .{
            .format         = self.swapChainImageFormat,
            .samples        = self.msaaSamples,
            .loadOp         = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp        = vk.VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp  = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout  = vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout    = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };

        const depthAttachment: vk.VkAttachmentDescription = .{
            .format         = try self.findDepthFormat(),
            .samples        = self.msaaSamples,
            .loadOp         = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
            // NOTE: Depth data will not be used after drawing so we don't have to store it. According to the tutorial,
            // storing it will allow the hardware to perform additional optimizations (2025-08-25)
            .storeOp        = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .stencilLoadOp  = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout  = vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout    = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        };

        const colorAttachmentResolve: vk.VkAttachmentDescription = .{
            .format         = self.swapChainImageFormat,
            .samples        = vk.VK_SAMPLE_COUNT_1_BIT,
            .loadOp         = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .storeOp        = vk.VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp  = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout  = vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout    = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        };

        const colorAttachmentRef: vk.VkAttachmentReference = .{
            .attachment = 0,
            .layout     = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };

        const depthAttachmentRef: vk.VkAttachmentReference = .{
            .attachment = 1,
            .layout     = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        };

        const colorAttachmentResolveRef: vk.VkAttachmentReference = .{
            .attachment = 2,
            .layout     = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };

        const subpass: vk.VkSubpassDescription = .{
            .pipelineBindPoint       = vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .colorAttachmentCount    = 1,
            .pColorAttachments       = &colorAttachmentRef,
            .pDepthStencilAttachment = &depthAttachmentRef,
            .pResolveAttachments     = &colorAttachmentResolveRef,
        };

        const dependency: vk.VkSubpassDependency = .{
            .srcSubpass    = vk.VK_SUBPASS_EXTERNAL,
            .dstSubpass    = 0,
            .srcStageMask  = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | vk.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
            .srcAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
            .dstStageMask  = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        };

        const attachments = [_]vk.VkAttachmentDescription{colorAttachment, depthAttachment, colorAttachmentResolve};
        const renderPassInfo: vk.VkRenderPassCreateInfo = .{
            .sType           = vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .attachmentCount = attachments.len,
            .pAttachments    = &attachments,
            .subpassCount    = 1,
            .pSubpasses      = &subpass,
            .dependencyCount = 1,
            .pDependencies   = &dependency,
        };

        if (vk.vkCreateRenderPass(self.device, &renderPassInfo, null, &self.renderPass) != vk.VK_SUCCESS) {
            return error.FailedToCreateRenderPass;
        }
    }

    fn findDepthFormat(self: *VulkanLayer) !vk.VkFormat {
        return try self.findSupportedFormat(
            &.{ vk.VK_FORMAT_D32_SFLOAT, vk.VK_FORMAT_D32_SFLOAT_S8_UINT, vk.VK_FORMAT_D24_UNORM_S8_UINT },
            vk.VK_IMAGE_TILING_OPTIMAL,
            vk.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT,
        );
    }

    fn findSupportedFormat(
        self:       *VulkanLayer,
        candidates: []const vk.VkFormat,
        tiling:     vk.VkImageTiling,
        features:   vk.VkFormatFeatureFlags,
    ) !vk.VkFormat {
        for (candidates) |format| {
            var props: vk.VkFormatProperties = undefined;
            vk.vkGetPhysicalDeviceFormatProperties(self.physicalDevice, format, &props);

            if (tiling == vk.VK_IMAGE_TILING_LINEAR and (props.linearTilingFeatures & features) == features) {
                return format;
            } else if (tiling == vk.VK_IMAGE_TILING_OPTIMAL and (props.optimalTilingFeatures & features) == features) {
                return format;
            }
        }

        return error.FailedToFindSupportedFormat;
    }

    fn getMaxUsableSampleCount(self: *VulkanLayer) !vk.VkSampleCountFlagBits {
        var physicalDeviceProperties: vk.VkPhysicalDeviceProperties = undefined;
        vk.vkGetPhysicalDeviceProperties(self.physicalDevice, &physicalDeviceProperties);

        const counts = physicalDeviceProperties.limits.framebufferColorSampleCounts & physicalDeviceProperties.limits.framebufferDepthSampleCounts;
        if      ((counts & vk.VK_SAMPLE_COUNT_64_BIT) != 0) {return vk.VK_SAMPLE_COUNT_64_BIT;}
        else if ((counts & vk.VK_SAMPLE_COUNT_32_BIT) != 0) {return vk.VK_SAMPLE_COUNT_32_BIT;}
        else if ((counts & vk.VK_SAMPLE_COUNT_16_BIT) != 0) {return vk.VK_SAMPLE_COUNT_16_BIT;}
        else if ((counts & vk.VK_SAMPLE_COUNT_8_BIT)  != 0) {return vk.VK_SAMPLE_COUNT_8_BIT;}
        else if ((counts & vk.VK_SAMPLE_COUNT_4_BIT)  != 0) {return vk.VK_SAMPLE_COUNT_4_BIT;}
        else if ((counts & vk.VK_SAMPLE_COUNT_2_BIT)  != 0) {return vk.VK_SAMPLE_COUNT_2_BIT;}

        return vk.VK_SAMPLE_COUNT_1_BIT;
    }

    fn createDescriptorSetLayouts(self: *VulkanLayer) !void {
        try self.createComputeDescriptorSetLayout();
        try self.createGraphicsDescriptorSetLayout();
        try self.createParticleDescriptorSetLayout();
    }

    fn createComputeDescriptorSetLayout(self: *VulkanLayer) !void {
        const layoutBindings = [_]vk.VkDescriptorSetLayoutBinding{
            .{
                .binding            = 0,
                .descriptorType     = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount    = 1,
                .stageFlags         = vk.VK_SHADER_STAGE_COMPUTE_BIT,
                .pImmutableSamplers = null, // Optional
            },
            .{
                .binding            = 1,
                .descriptorType     = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .descriptorCount    = 1,
                .stageFlags         = vk.VK_SHADER_STAGE_COMPUTE_BIT,
                .pImmutableSamplers = null, // Optional
            },
            .{
                .binding            = 2,
                .descriptorType     = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .descriptorCount    = 1,
                .stageFlags         = vk.VK_SHADER_STAGE_COMPUTE_BIT,
                .pImmutableSamplers = null, // Optional
            },
            .{
                .binding            = 3,
                .descriptorType     = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .descriptorCount    = 1,
                .stageFlags         = vk.VK_SHADER_STAGE_COMPUTE_BIT,
                .pImmutableSamplers = null, // Optional
            },
        };

        const layoutInfo: vk.VkDescriptorSetLayoutCreateInfo = .{
            .sType        = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = layoutBindings.len,
            .pBindings    = &layoutBindings,
        };

        if (vk.vkCreateDescriptorSetLayout(self.device, &layoutInfo, null, &self.computeDescriptorSetLayout) != vk.VK_SUCCESS) {
            return error.FailedToCreateComputeDescriptorSetLayout;
        }
    }

    fn createGraphicsDescriptorSetLayout(self: *VulkanLayer) !void {
        const uboLayoutBinding: vk.VkDescriptorSetLayoutBinding = .{
            .binding            = 0,
            .descriptorType     = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount    = 1,
            .stageFlags         = vk.VK_SHADER_STAGE_VERTEX_BIT,
            .pImmutableSamplers = null, // Optional
        };
        const bindings = [_]vk.VkDescriptorSetLayoutBinding{uboLayoutBinding};

        const layoutInfo: vk.VkDescriptorSetLayoutCreateInfo = .{
            .sType        = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = bindings.len,
            .pBindings    = &bindings,
        };

        if (vk.vkCreateDescriptorSetLayout(self.device, &layoutInfo, null, &self.graphicsDescriptorSetLayout) != vk.VK_SUCCESS) {
            return error.FailedToCreateDescriptorSetLayout;
        }
    }

    fn createParticleDescriptorSetLayout(self: *VulkanLayer) !void {
        const uboLayoutBinding: vk.VkDescriptorSetLayoutBinding = .{
            .binding            = 0,
            .descriptorType     = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount    = 1,
            .stageFlags         = vk.VK_SHADER_STAGE_VERTEX_BIT,
            .pImmutableSamplers = null, // Optional
        };
        const bindings = [_]vk.VkDescriptorSetLayoutBinding{uboLayoutBinding};

        const layoutInfo: vk.VkDescriptorSetLayoutCreateInfo = .{
            .sType        = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = bindings.len,
            .pBindings    = &bindings,
        };

        if (vk.vkCreateDescriptorSetLayout(self.device, &layoutInfo, null, &self.particleDescriptorSetLayout) != vk.VK_SUCCESS) {
            return error.FailedToCreateDescriptorSetLayout;
        }
    }

    fn createComputePipeline(self: *VulkanLayer) !void {
        const pipelineLayoutInfo: vk.VkPipelineLayoutCreateInfo = .{
            .sType                  = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount         = 1,
            .pSetLayouts            = &self.computeDescriptorSetLayout,
        };

        if (vk.vkCreatePipelineLayout(self.device, &pipelineLayoutInfo, null, &self.computePipelineLayout) != vk.VK_SUCCESS) {
            return error.FailedToCreateComputePipelineLayout;
        }

        const computeShaderCode = comptime readFile("shaders/comp.spv");

        const computeShaderModule = try createShaderModule(self, computeShaderCode);
        defer vk.vkDestroyShaderModule(self.device, computeShaderModule, null);

        const computeShaderStageInfo: vk.VkPipelineShaderStageCreateInfo = .{
            .sType  = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage  = vk.VK_SHADER_STAGE_COMPUTE_BIT,
            .module = computeShaderModule,
            .pName  = "main",
        };

        const pipelineCreateInfo: vk.VkComputePipelineCreateInfo = .{
            .sType  = vk.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
            .layout = self.computePipelineLayout,
            .stage  = computeShaderStageInfo,
        };

        if (vk.vkCreateComputePipelines(self.device, @ptrCast(vk.VK_NULL_HANDLE), 1, &pipelineCreateInfo, null, &self.computePipeline) != vk.VK_SUCCESS) {
            return error.FailedToCreateComputePipeline;
        }
    }

    fn createGraphicsPipeline(self: *VulkanLayer) !void {
        const vertShaderCode = comptime readFile("shaders/graphics-vert.spv");
        const fragShaderCode = comptime readFile("shaders/graphics-frag.spv");

        const vertShaderModule = try self.createShaderModule(vertShaderCode);
        defer vk.vkDestroyShaderModule(self.device, vertShaderModule, null);
        const fragShaderModule = try self.createShaderModule(fragShaderCode);
        defer vk.vkDestroyShaderModule(self.device, fragShaderModule, null);

        const vertShaderStageInfo: vk.VkPipelineShaderStageCreateInfo = .{
            .sType  = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage  = vk.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vertShaderModule,
            .pName  = "main",
        };
        const fragShaderStageInfo: vk.VkPipelineShaderStageCreateInfo = .{
            .sType  = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage  = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = fragShaderModule,
            .pName  = "main",
        };

        const shaderStages = [_]vk.VkPipelineShaderStageCreateInfo{ vertShaderStageInfo, fragShaderStageInfo };

        const bindingDescription    = Vertex.getBindingDescription();
        const attributeDescriptions = Vertex.getAttributeDescriptions();
        const vertexInputInfo: vk.VkPipelineVertexInputStateCreateInfo = .{
            .sType                           = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount   = 1,
            .pVertexBindingDescriptions      = &bindingDescription,
            .vertexAttributeDescriptionCount = @intCast(attributeDescriptions.len),
            .pVertexAttributeDescriptions    = attributeDescriptions.ptr,
        };

        const inputAssembly: vk.VkPipelineInputAssemblyStateCreateInfo = .{
            .sType                  = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology               = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = vk.VK_FALSE,
        };

        const viewportState: vk.VkPipelineViewportStateCreateInfo = .{
            .sType         = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .scissorCount  = 1,
        };

        const rasterizer: vk.VkPipelineRasterizationStateCreateInfo = .{
            .sType                   = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .depthClampEnable        = vk.VK_FALSE,
            .rasterizerDiscardEnable = vk.VK_FALSE,
            .polygonMode             = vk.VK_POLYGON_MODE_FILL,
            .lineWidth               = 1.0,
            .cullMode                = vk.VK_CULL_MODE_BACK_BIT,
            .frontFace               = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE,
            .depthBiasEnable         = vk.VK_FALSE,
        };

        const multisampling: vk.VkPipelineMultisampleStateCreateInfo = .{
            .sType                = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .sampleShadingEnable  = vk.VK_FALSE,
            .rasterizationSamples = self.msaaSamples,
        };

        const depthStencil: vk.VkPipelineDepthStencilStateCreateInfo = .{
            .sType                 = vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .depthTestEnable       = vk.VK_TRUE,
            .depthWriteEnable      = vk.VK_TRUE,
            .depthCompareOp        = vk.VK_COMPARE_OP_LESS,
            .depthBoundsTestEnable = vk.VK_FALSE,
            .stencilTestEnable     = vk.VK_FALSE,
        };

        const colorBlendAttachment: vk.VkPipelineColorBlendAttachmentState = .{
            .colorWriteMask      = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
            .blendEnable         = vk.VK_TRUE,
            .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
            .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_ALPHA,
            .colorBlendOp        = vk.VK_BLEND_OP_ADD,
            .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
            .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
            .alphaBlendOp        = vk.VK_BLEND_OP_ADD,
        };
        const colorBlending: vk.VkPipelineColorBlendStateCreateInfo = .{
            .sType           = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable   = vk.VK_FALSE,
            .attachmentCount = 1,
            .pAttachments    = &colorBlendAttachment,
        };

        const dynamicStates = &[_]vk.VkDynamicState{vk.VK_DYNAMIC_STATE_VIEWPORT, vk.VK_DYNAMIC_STATE_SCISSOR};
        const dynamicState: vk.VkPipelineDynamicStateCreateInfo = .{
            .sType             = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = dynamicStates.len,
            .pDynamicStates    = dynamicStates.ptr,
        };

        const pushConstant: vk.VkPushConstantRange = .{
            .offset     = 0,
            .size       = @sizeOf(cglm.mat4),
            .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
        };

        const pipelineLayoutInfo: vk.VkPipelineLayoutCreateInfo = .{
            .sType                  = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount         = 1,
            .pSetLayouts            = &self.graphicsDescriptorSetLayout,
            .pPushConstantRanges    = &pushConstant,
            .pushConstantRangeCount = 1
        };
        if (vk.vkCreatePipelineLayout(self.device, &pipelineLayoutInfo, null, &self.graphicsPipelineLayout) != vk.VK_SUCCESS) {
            return error.FailedToCreatePipelineLayout;
        }

        const pipelineInfo: vk.VkGraphicsPipelineCreateInfo = .{
            .sType               = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .stageCount          = 2,
            .pStages             = &shaderStages,
            .pVertexInputState   = &vertexInputInfo,
            .pInputAssemblyState = &inputAssembly,
            .pViewportState      = &viewportState,
            .pRasterizationState = &rasterizer,
            .pMultisampleState   = &multisampling,
            .pDepthStencilState  = &depthStencil,
            .pColorBlendState    = &colorBlending,
            .pDynamicState       = &dynamicState,
            .layout              = self.graphicsPipelineLayout,
            .renderPass          = self.renderPass,
            .subpass             = 0,
            .basePipelineHandle  = @ptrCast(vk.VK_NULL_HANDLE), // Optional
            .basePipelineIndex   = -1, // Optional
        };

        if (vk.vkCreateGraphicsPipelines(self.device, @ptrCast(vk.VK_NULL_HANDLE), 1, &pipelineInfo, null, &self.graphicsPipeline) != vk.VK_SUCCESS) {
            return error.FailedToCreateGraphicsPipeline;
        }
    }

    fn createParticlePipeline(self: *VulkanLayer) !void {
        const vertShaderCode = comptime readFile("shaders/particle-vert.spv");
        const fragShaderCode = comptime readFile("shaders/particle-frag.spv");

        const vertShaderModule = try createShaderModule(self, vertShaderCode);
        defer vk.vkDestroyShaderModule(self.device, vertShaderModule, null);
        const fragShaderModule = try createShaderModule(self, fragShaderCode);
        defer vk.vkDestroyShaderModule(self.device, fragShaderModule, null);

        const vertShaderStageInfo: vk.VkPipelineShaderStageCreateInfo = .{
            .sType  = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage  = vk.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vertShaderModule,
            .pName  = "main",
        };
        const fragShaderStageInfo: vk.VkPipelineShaderStageCreateInfo = .{
            .sType  = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage  = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = fragShaderModule,
            .pName  = "main",
        };

        const bindingDescription    = Particle.getBindingDescription();
        const attributeDescriptions = Particle.getAttributeDescriptions();
        const vertexInputInfo: vk.VkPipelineVertexInputStateCreateInfo = .{
            .sType                           = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount   = 1,
            .pVertexBindingDescriptions      = &bindingDescription,
            .vertexAttributeDescriptionCount = @intCast(attributeDescriptions.len),
            .pVertexAttributeDescriptions    = attributeDescriptions.ptr,
        };

        const inputAssembly: vk.VkPipelineInputAssemblyStateCreateInfo = .{
            .sType                  = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology               = vk.VK_PRIMITIVE_TOPOLOGY_POINT_LIST,
            .primitiveRestartEnable = vk.VK_FALSE,
        };

        const viewportState: vk.VkPipelineViewportStateCreateInfo = .{
            .sType         = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .scissorCount  = 1,
        };

        const rasterizer: vk.VkPipelineRasterizationStateCreateInfo = .{
            .sType                   = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .depthClampEnable        = vk.VK_FALSE,
            .rasterizerDiscardEnable = vk.VK_FALSE,
            .polygonMode             = vk.VK_POLYGON_MODE_FILL,
            .cullMode                = vk.VK_CULL_MODE_BACK_BIT,
            .frontFace               = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE,
            .depthBiasEnable         = vk.VK_FALSE,
            .lineWidth               = 1.0,
        };

        const multisampling: vk.VkPipelineMultisampleStateCreateInfo = .{
            .sType                = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .rasterizationSamples = self.msaaSamples,
            .sampleShadingEnable  = vk.VK_FALSE,
        };

        const depthStencil: vk.VkPipelineDepthStencilStateCreateInfo = .{
            .sType                 = vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .depthTestEnable       = vk.VK_TRUE,
            .depthWriteEnable      = vk.VK_TRUE,
            .depthCompareOp        = vk.VK_COMPARE_OP_LESS,
            .depthBoundsTestEnable = vk.VK_FALSE,
            .stencilTestEnable     = vk.VK_FALSE,
        };

        const colorBlendAttachment: vk.VkPipelineColorBlendAttachmentState = .{
            .blendEnable         = vk.VK_TRUE,
            .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
            .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            .colorBlendOp        = vk.VK_BLEND_OP_ADD,
            .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
            .alphaBlendOp        = vk.VK_BLEND_OP_ADD,
            .colorWriteMask      = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
        };

        const colorBlending: vk.VkPipelineColorBlendStateCreateInfo = .{
            .sType           = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable   = vk.VK_FALSE,
            .logicOp         = vk.VK_LOGIC_OP_COPY,
            .attachmentCount = 1,
            .pAttachments    = &colorBlendAttachment,
            .blendConstants  = .{0.0, 0.0, 0.0, 0.0}
        };

        const dynamicStates = [_]vk.VkDynamicState{ vk.VK_DYNAMIC_STATE_VIEWPORT, vk.VK_DYNAMIC_STATE_SCISSOR };
        const dynamicState: vk.VkPipelineDynamicStateCreateInfo = .{
            .sType             = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = dynamicStates.len,
            .pDynamicStates    = &dynamicStates,
        };

        const pipelineLayoutInfo: vk.VkPipelineLayoutCreateInfo = .{
            .sType                  = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount         = 1,
            .pSetLayouts            = &self.particleDescriptorSetLayout,
        };
        if (vk.vkCreatePipelineLayout(self.device, &pipelineLayoutInfo, null, &self.particlePipelineLayout) != vk.VK_SUCCESS) {
            return error.FailedToCreateGraphicsPipelineLayout;
        }

        const shaderStages = [_]vk.VkPipelineShaderStageCreateInfo{vertShaderStageInfo, fragShaderStageInfo};
        const pipelineInfo: vk.VkGraphicsPipelineCreateInfo = .{
            .sType               = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .stageCount          = 2,
            .pStages             = &shaderStages,
            .pVertexInputState   = &vertexInputInfo,
            .pInputAssemblyState = &inputAssembly,
            .pViewportState      = &viewportState,
            .pRasterizationState = &rasterizer,
            .pMultisampleState   = &multisampling,
            .pDepthStencilState  = &depthStencil,
            .pColorBlendState    = &colorBlending,
            .pDynamicState       = &dynamicState,
            .layout              = self.particlePipelineLayout,
            .renderPass          = self.renderPass,
            .subpass             = 0,
            .basePipelineHandle  = @ptrCast(vk.VK_NULL_HANDLE)
        };

        if (vk.vkCreateGraphicsPipelines(self.device, @ptrCast(vk.VK_NULL_HANDLE), 1, &pipelineInfo, null, &self.particlePipeline) != vk.VK_SUCCESS) {
            return error.FailedToCreateGraphicsPipeline;
        }
    }

    fn createCommandPools(self: *VulkanLayer) !void {
        const queueFamilyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);

        const computePoolInfo: vk.VkCommandPoolCreateInfo = .{
            .sType            = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags            = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = queueFamilyIndices.graphicsAndComputeFamily.?,
        };

        if (vk.vkCreateCommandPool(self.device, &computePoolInfo, null, &self.computeCommandPool) != vk.VK_SUCCESS) {
            return error.FailedToCreateGraphicsCommandPool;
        }

        const graphicsPoolInfo: vk.VkCommandPoolCreateInfo = .{
            .sType            = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags            = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = queueFamilyIndices.graphicsAndComputeFamily.?,
        };

        if (vk.vkCreateCommandPool(self.device, &graphicsPoolInfo, null, &self.graphicsCommandPool) != vk.VK_SUCCESS) {
            return error.FailedToCreateGraphicsCommandPool;
        }

        const transferPoolInfo: vk.VkCommandPoolCreateInfo = .{
            .sType            = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags            = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = queueFamilyIndices.transferFamily.?,
        };

        if (vk.vkCreateCommandPool(self.device, &transferPoolInfo, null, &self.transferCommandPool) != vk.VK_SUCCESS) {
            return error.FailedToCreateTransferCommandPool;
        }
    }

    fn createColorResources(self: *VulkanLayer) !void {
        const colorFormat = self.swapChainImageFormat;

        try self.createImage(
            self.swapChainExtent.width,
            self.swapChainExtent.height,
            1,
            self.msaaSamples,
            colorFormat,
            vk.VK_IMAGE_TILING_OPTIMAL,
            vk.VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT | vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            &self.colorImage,
            &self.colorImageMemory,
        );
        self.colorImageView = try self.createImageView(self.colorImage, colorFormat, vk.VK_IMAGE_ASPECT_COLOR_BIT);
    }

    fn createDepthResources(self: *VulkanLayer) !void {
        const depthFormat = try self.findDepthFormat();

        try self.createImage(
            self.swapChainExtent.width,
            self.swapChainExtent.height,
            1,
            self.msaaSamples,
            depthFormat,
            vk.VK_IMAGE_TILING_OPTIMAL,
            vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            &self.depthImage,
            &self.depthImageMemory,
        );
        self.depthImageView = try self.createImageView(self.depthImage, depthFormat, vk.VK_IMAGE_ASPECT_DEPTH_BIT);
    }

    fn createFramebuffers(self: *VulkanLayer) !void {
        self.swapChainFramebuffers = try self.allocator.alloc(vk.VkFramebuffer, self.swapChainImageViews.len);

        for (0..self.swapChainImageViews.len) |i| {
            const attachments = [_]vk.VkImageView{self.colorImageView, self.depthImageView, self.swapChainImageViews[i]};

            const frameBufferInfo: vk.VkFramebufferCreateInfo = .{
                .sType           = vk.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .renderPass      = self.renderPass,
                .attachmentCount = attachments.len,
                .pAttachments    = &attachments,
                .width           = self.swapChainExtent.width,
                .height          = self.swapChainExtent.height,
                .layers          = 1,
            };

            if (vk.vkCreateFramebuffer(self.device, &frameBufferInfo, null, &self.swapChainFramebuffers[i]) != vk.VK_SUCCESS) {
                return error.FailedToCreateFramebuffer;
            }
        }
    }

    fn createAllUniformBuffers(self: *VulkanLayer) !void {
        try self.createUniformBuffers(ComputeUniformBufferObject, &self.computeUniformBuffers, &self.computeUniformBuffersMemory, &self.computeUniformBuffersMapped);
        try self.createUniformBuffers(WorldEntityUniformBufferObject, &self.worldEntityUniformBuffers, &self.worldEntityUniformBuffersMemory, &self.worldEntityUniformBuffersMapped);
        try self.createUniformBuffers(ParticleUniformBufferObject, &self.particleUniformBuffers, &self.particleUniformBuffersMemory, &self.particleUniformBuffersMapped);
    }

    fn createUniformBuffers(
        self:                 *VulkanLayer,
        T:                    type,
        uniformBuffers:       []vk.VkBuffer,
        uniformBuffersMemory: []vk.VkDeviceMemory,
        uniformBuffersMapped: []*T,
    ) !void {
        const bufferSize = @sizeOf(T);

        for (0..uniformBuffers.len) |i| {
            try self.createBuffer(
                bufferSize,
                vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                &uniformBuffers[i],
                &uniformBuffersMemory[i],
            );
            _ = vk.vkMapMemory(self.device, uniformBuffersMemory[i], 0, bufferSize, 0, @ptrCast(@alignCast(&uniformBuffersMapped[i])));
        }
    }

    pub fn createComputeWorldEntityStorageBuffers(self: *VulkanLayer, entities: []const u8) !void {
        try self.createBuffer(
            entities.len,
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &self.computeWorldEntityStagingBuffer,
            &self.computeWorldEntityStagingBufferMemory,
        );
        _ = vk.vkMapMemory(self.device, self.computeWorldEntityStagingBufferMemory, 0, entities.len, 0, @alignCast(@ptrCast(&self.computeWorldEntityStagingBufferMemoryMapped)));
        @memcpy(self.computeWorldEntityStagingBufferMemoryMapped, entities);

        for (0..self.computeWorldEntityStorageBuffer.len) |i| {
            try createBuffer(
                self,
                entities.len,
                vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                &self.computeWorldEntityStorageBuffer[i],
                &self.computeWorldEntityStorageBufferMemory[i],
            );

            self.copyBuffer(self.computeWorldEntityStagingBuffer, self.computeWorldEntityStorageBuffer[i], 0, 0, entities.len);
        }
    }

    fn createAllDescriptorPool(self: *VulkanLayer) !void  {
        try self.createComputeDescriptorPool();
        try self.createGraphicsDescriptorPool();
        try self.createParticleDescriptorPool();
    }

    fn createComputeDescriptorPool(self: *VulkanLayer) !void  {
        const poolSizes = [_]vk.VkDescriptorPoolSize{
            .{
                .type            = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = cfg.NUM_OF_THREADS,
            },
            .{
                .type            = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .descriptorCount = cfg.NUM_OF_THREADS * 3,
            },
        };

        const poolInfo: vk.VkDescriptorPoolCreateInfo = .{
            .sType         = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .poolSizeCount = poolSizes.len,
            .pPoolSizes    = &poolSizes,
            .maxSets       = cfg.NUM_OF_THREADS,
        };

        if (vk.vkCreateDescriptorPool(self.device, &poolInfo, null, &self.computeDescriptorPool) != vk.VK_SUCCESS) {
            return error.FailedToCreateDescriptorPool;
        }
    }

    fn createGraphicsDescriptorPool(self: *VulkanLayer) !void  {
        const poolSizes = [_]vk.VkDescriptorPoolSize{
            .{
                .type            = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = cfg.NUM_OF_THREADS,
            },
            .{
                .type            = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = cfg.NUM_OF_THREADS,
            },
        } ** cfg.NUM_OF_THREADS;

        const poolInfo: vk.VkDescriptorPoolCreateInfo = .{
            .sType         = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .flags         = vk.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
            .poolSizeCount = poolSizes.len,
            .pPoolSizes    = &poolSizes,
            .maxSets       = cfg.NUM_OF_THREADS,
        };

        if (vk.vkCreateDescriptorPool(self.device, &poolInfo, null, &self.graphicsDescriptorPool) != vk.VK_SUCCESS) {
            return error.FailedToCreateDescriptorPool;
        }
    }

    fn createParticleDescriptorPool(self: *VulkanLayer) !void  {
        const poolSizes = [_]vk.VkDescriptorPoolSize{
            .{
                .type            = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = cfg.NUM_OF_THREADS,
            },
            .{
                .type            = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = cfg.NUM_OF_THREADS,
            },
        } ** cfg.NUM_OF_THREADS;

        const poolInfo: vk.VkDescriptorPoolCreateInfo = .{
            .sType         = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .flags         = vk.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
            .poolSizeCount = poolSizes.len,
            .pPoolSizes    = &poolSizes,
            .maxSets       = cfg.NUM_OF_THREADS,
        };

        if (vk.vkCreateDescriptorPool(self.device, &poolInfo, null, &self.particleDescriptorPool) != vk.VK_SUCCESS) {
            return error.FailedToCreateDescriptorPool;
        }
    }

    fn createAllCommandBuffers(self: *VulkanLayer) !void {
        try self.createCommandBuffers(self.graphicsCommandPool, &self.graphicsCommandBuffers);
        try self.createCommandBuffers(self.computeCommandPool, &self.computeCommandBuffers);
    }

    fn createCommandBuffers(
        self:           *VulkanLayer,
        commandPool:    vk.VkCommandPool,
        commandBuffers: []vk.VkCommandBuffer
    ) !void {
        const allocInfoGraphics: vk.VkCommandBufferAllocateInfo = .{
            .sType              = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool        = commandPool,
            .level              = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = @intCast(commandBuffers.len),
        };

        if (vk.vkAllocateCommandBuffers(self.device, &allocInfoGraphics, @ptrCast(commandBuffers)) != vk.VK_SUCCESS) {
            return error.FailedToCreateGraphicsCommandBuffers;
        }
    }

    fn createSyncObjects(self: *VulkanLayer) !void {
        const semaphoreInfo: vk.VkSemaphoreCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };

        const fenceInfo: vk.VkFenceCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        for (0..cfg.NUM_OF_THREADS) |i| {
            if (vk.vkCreateSemaphore(self.device, &semaphoreInfo, null, &self.computeFinishedSemaphores[i]) != vk.VK_SUCCESS or
                vk.vkCreateSemaphore(self.device, &semaphoreInfo, null, &self.imageAvailableSemaphores[i]) != vk.VK_SUCCESS or
                vk.vkCreateFence(self.device, &fenceInfo, null, &self.computeInFlightFences[i]) != vk.VK_SUCCESS or
                vk.vkCreateFence(self.device, &fenceInfo, null, &self.renderInFlightFences[i]) != vk.VK_SUCCESS)
            {
                return error.FailedToCreateSemaphores;
            }
        }

        self.renderFinishedSemaphores = try std.ArrayList(vk.VkSemaphore).initCapacity(self.allocator.*, self.swapChainImages.len);
        self.renderFinishedSemaphores.appendNTimesAssumeCapacity(undefined, self.renderFinishedSemaphores.capacity);
        for (self.renderFinishedSemaphores.items) |*semaphore| {
            if (vk.vkCreateSemaphore(self.device, &semaphoreInfo, null, semaphore) != vk.VK_SUCCESS) {
                return error.FailedToCreateSemaphores;
            }
        }
    }

    pub fn createBuffer(
        self:         *VulkanLayer,
        size:         vk.VkDeviceSize,
        usage:        vk.VkBufferUsageFlags,
        properties:   vk.VkMemoryPropertyFlags,
        buffer:       *vk.VkBuffer,
        bufferMemory: *vk.VkDeviceMemory,
    ) !void {
        const familyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);
        const bufferInfo: vk.VkBufferCreateInfo = .{
            .sType                 = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size                  = size,
            .usage                 = usage,
            .sharingMode           = vk.VK_SHARING_MODE_CONCURRENT,
            .queueFamilyIndexCount = 2,
            .pQueueFamilyIndices   = &[_]u32{familyIndices.graphicsAndComputeFamily.?, familyIndices.transferFamily.?},
        };
        if (vk.vkCreateBuffer(self.device, &bufferInfo, null, buffer) != vk.VK_SUCCESS) {
            return error.FailedToCreateVertexBuffer;
        }

        var memRequirements: vk.VkMemoryRequirements = undefined;
        vk.vkGetBufferMemoryRequirements(self.device, buffer.*, &memRequirements);

        const allocInfo: vk.VkMemoryAllocateInfo = .{
            .sType           = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize  = memRequirements.size,
            .memoryTypeIndex = try self.findMemoryType(memRequirements.memoryTypeBits, properties),
        };
        // NOTE: It's not good to call vkAllocateMemory for each individual buffer in production code
        // because simultaneous memory allocations are limited by the maxMemoryAllocationCount physical device limit. (2025-03-06)
        if (vk.vkAllocateMemory(self.device, &allocInfo, null, bufferMemory) != vk.VK_SUCCESS) {
            return error.FailedToAllocateVertexBufferMemory;
        }

        _ = vk.vkBindBufferMemory(self.device, buffer.*, bufferMemory.*, 0);
    }

    fn findMemoryType(
        self:       *VulkanLayer,
        typeFilter: u32,
        properties: vk.VkMemoryPropertyFlags
    ) !u32 {
        var memProperties: vk.VkPhysicalDeviceMemoryProperties = undefined;
        vk.vkGetPhysicalDeviceMemoryProperties(self.physicalDevice, &memProperties);
        for (0..memProperties.memoryTypeCount) |i| {
            const bit = @as(u32, 1) << @intCast(i);
            if (typeFilter & bit != 0 and (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
                return @intCast(i);
            }
        }
        return error.FailedToFindSuitableMemoryType;
    }

    fn createImageView(
        self:        *VulkanLayer,
        image:       vk.VkImage,
        format:      vk.VkFormat,
        aspectFlags: vk.VkImageAspectFlags,
    ) !vk.VkImageView {
        const viewInfo: vk.VkImageViewCreateInfo = .{
            .sType            = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image            = image,
            .viewType         = vk.VK_IMAGE_VIEW_TYPE_2D,
            .format           = format,
            .subresourceRange = .{
                .aspectMask     = aspectFlags,
                .baseMipLevel   = 0,
                .levelCount     = 1,
                .baseArrayLayer = 0,
                .layerCount     = 1
            },
        };

        var imageView: vk.VkImageView = undefined;
        if (vk.vkCreateImageView(self.device, &viewInfo, null, &imageView) != vk.VK_SUCCESS) {
            return error.FailedToCreateImageView;
        }

        return imageView;
    }

    fn createImage(
        self:        *VulkanLayer,
        width:       u32,
        height:      u32,
        mipLevels:   u32,
        numSamples:  vk.VkSampleCountFlagBits,
        format:      vk.VkFormat,
        tiling:      vk.VkImageTiling,
        usage:       vk.VkImageUsageFlags,
        properties:  vk.VkMemoryPropertyFlags,
        image:       *vk.VkImage,
        imageMemory: *vk.VkDeviceMemory,
    ) !void {
        const imageInfo: vk.VkImageCreateInfo = .{
            .sType         = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType     = vk.VK_IMAGE_TYPE_2D,
            .extent        = .{
                .width  = width,
                .height = height,
                .depth  = 1,
            },
            .mipLevels     = mipLevels,
            .arrayLayers   = 1,
            .format        = format,
            .tiling        = tiling,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .usage         = usage,
            .sharingMode   = vk.VK_SHARING_MODE_EXCLUSIVE,
            .samples       = numSamples,
            .flags         = 0,
        };

        if (vk.vkCreateImage(self.device, &imageInfo, null, image) != vk.VK_SUCCESS) {
            return error.FailedToCreateImage;
        }

        var memRequirements: vk.VkMemoryRequirements = undefined;
        vk.vkGetImageMemoryRequirements(self.device, image.*, &memRequirements);

        const allocInfo: vk.VkMemoryAllocateInfo = .{
            .sType           = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize  = memRequirements.size,
            .memoryTypeIndex = try self.findMemoryType(memRequirements.memoryTypeBits, properties),
        };

        if (vk.vkAllocateMemory(self.device, &allocInfo, null, imageMemory) != vk.VK_SUCCESS) {
            return error.FailedToALlocateImageMemory;
        }

        _ = vk.vkBindImageMemory(self.device, image.*, imageMemory.*, 0);
    }

    fn copyBuffer(
        self:      *VulkanLayer,
        srcBuffer: vk.VkBuffer,
        dstBuffer: vk.VkBuffer,
        srcOffset: vk.VkDeviceSize,
        dstOffset: vk.VkDeviceSize,
        size:      vk.VkDeviceSize
    ) void {
        const commandBuffer: vk.VkCommandBuffer = try self.beginSingleTimeCommands(self.transferCommandPool);

        var copyRegion: vk.VkBufferCopy = .{
            .srcOffset = srcOffset,
            .dstOffset = dstOffset,
            .size      = size,
        };
        vk.vkCmdCopyBuffer(commandBuffer, srcBuffer, dstBuffer, 1, &copyRegion);

        try self.endSingleTimeCommands(self.transferCommandPool, self.transferQueue, commandBuffer);
    }

    fn copyBufferToImage(
        self:   *VulkanLayer,
        buffer: vk.VkBuffer,
        image:  vk.VkImage,
        width:  u32,
        height: u32
    ) !void {
        const commandBuffer: vk.VkCommandBuffer = try self.beginSingleTimeCommands(self.transferCommandPool);

        const region: vk.VkBufferImageCopy = .{
            .bufferOffset      = 0,
            .bufferRowLength   = 0,
            .bufferImageHeight = 0,
            .imageSubresource  = .{
                .aspectMask     = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel       = 0,
                .baseArrayLayer = 0,
                .layerCount     = 1,
            },
            .imageOffset       = .{
                .x = 0,
                .y = 0,
                .z = 0,
            },
            .imageExtent       = .{
                .width  = width,
                .height = height,
                .depth  = 1,
            },
        };

        vk.vkCmdCopyBufferToImage(
            commandBuffer,
            buffer,
            image,
            vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &region,
        );

        try self.endSingleTimeCommands(self.transferCommandPool, self.transferQueue, commandBuffer);
    }

    pub fn injectParticlesIntoBuffer(
        self:           *VulkanLayer,
        index:          usize,
        particles:      []const u8,
        checkpoints:    [4]usize,
        particleSize:   usize,
    ) void {
        var i: usize = 1;
        while (i < checkpoints.len) : (i += 2) {
            const start = checkpoints[i - 1];
            const end   = checkpoints[i];
            if (start == end) {
                break;
            }

            const offsetStart = particleSize * start;
            const offsetEnd   = particleSize * end;
            const bufferSize  = offsetEnd - offsetStart;
            @memcpy(self.particleStagingBufferMemoryMapped + offsetStart, particles[offsetStart..offsetEnd]);
            self.copyBuffer(self.particleStagingBuffer, self.particleShaderStorageBuffers[index], offsetStart, offsetStart, bufferSize);
        }
    }

    pub fn updateComputeWorldEntityStorageBuffers(
        self:     *VulkanLayer,
        index:    usize,
        entities: []const u8,
    ) !void {
        @memcpy(self.computeWorldEntityStagingBufferMemoryMapped, entities);
        self.copyBuffer(self.computeWorldEntityStagingBuffer, self.computeWorldEntityStorageBuffer[index], 0, 0, entities.len);
    }

    fn beginSingleTimeCommands(self: *VulkanLayer, commandPool: vk.VkCommandPool) !vk.VkCommandBuffer {
        const allocInfo: vk.VkCommandBufferAllocateInfo = .{
            .sType              = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .level              = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandPool        = commandPool,
            .commandBufferCount = 1,
        };
        var commandBuffer: vk.VkCommandBuffer = undefined;
        _ = vk.vkAllocateCommandBuffers(self.device, &allocInfo, &commandBuffer);

        const beginInfo: vk.VkCommandBufferBeginInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };
        _ = vk.vkBeginCommandBuffer(commandBuffer, &beginInfo);

        return commandBuffer;
    }

    fn endSingleTimeCommands(
        self:          *VulkanLayer,
        commandPool:   vk.VkCommandPool,
        queue:         vk.VkQueue,
        commandBuffer: vk.VkCommandBuffer
    ) !void {
        _ = vk.vkEndCommandBuffer(commandBuffer);

        const submitInfo: vk.VkSubmitInfo = .{
            .sType              = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers    = &commandBuffer,
        };
        _ = vk.vkQueueSubmit(queue, 1, &submitInfo, @ptrCast(vk.VK_NULL_HANDLE));

        _ = vk.vkQueueWaitIdle(queue);

        vk.vkFreeCommandBuffers(self.device, commandPool, 1, &commandBuffer);
    }

    pub fn createWorldEntityRenderBuffer(
        self:      *VulkanLayer,
        nodes:     []*Node,
        batchSize: usize,
    ) !void {
        for (&self.worldEntityRenderBufferManagers, 0..) |*bufferManager, i| {
            const start = i * batchSize;
            const end   = (i + 1) * batchSize;

            bufferManager.* = try BufferManager.init(self.device, self.allocator, end - start);

            for (nodes[start..end]) |node| {
                try bufferManager.addNode(node);
            }

            var vertices = try bufferManager.getVertices(self.allocator);
            defer vertices.deinit(self.allocator.*);
            try self.createModelVertexBuffer(vertices.items, bufferManager.vertexBufferSize, &bufferManager.vertexBuffer, &bufferManager.vertexBufferMemory);

            var indices  = try bufferManager.getIndices(self.allocator);
            defer indices.deinit(self.allocator.*);
            try self.createModelIndexBuffer(indices.items, bufferManager.indexBufferSize, &bufferManager.indexBuffer, &bufferManager.indexBufferMemory);
        }
    }

    pub fn deinitWorldEntitiesRenderBufferManager(self: *VulkanLayer) void {
        for (&self.worldEntityRenderBufferManagers) |*bufferManager| {
            bufferManager.deinit();
        }
    }

    pub fn deinitParticleShaderStorageBuffers(self: *VulkanLayer) void {
        for (0..self.particleShaderStorageBuffers.len) |i| {
            vk.vkDestroyBuffer(self.device, self.particleShaderStorageBuffers[i], null);
            vk.vkFreeMemory(self.device, self.particleShaderStorageBuffersMemory[i], null);
        }

        vk.vkDestroyBuffer(self.device, self.particleStagingBuffer, null);
        vk.vkFreeMemory(self.device, self.particleStagingBufferMemory, null);
    }

    pub fn createParticleStorageBuffers(
        self:         *VulkanLayer,
        particles:    []const u8,
        particleSize: usize,
    ) !void {
        std.debug.assert(particles.len % particleSize == 0);
        const numOfParticles = particles.len / particleSize;

        try self.createBuffer(
            particles.len,
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &self.particleStagingBuffer,
            &self.particleStagingBufferMemory,
        );
        _ = vk.vkMapMemory(self.device, self.particleStagingBufferMemory, 0, particles.len, 0, @alignCast(@ptrCast(&self.particleStagingBufferMemoryMapped)));

        for (0..self.particleShaderStorageBuffers.len) |i| {
            try self.createBuffer(
                particles.len,
                vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                &self.particleShaderStorageBuffers[i],
                &self.particleShaderStorageBuffersMemory[i],
            );

            self.injectParticlesIntoBuffer(i, particles, [_]usize{0, numOfParticles, 0, 0}, particleSize);
        }
    }

    fn createModelVertexBuffer(
        self:                    *VulkanLayer,
        vertices:                []const Vertex,
        bufferSize:              vk.VkDeviceSize,
        modelVertexBuffer:       *vk.VkBuffer,
        modelVertexBufferMemory: *vk.VkDeviceMemory,
    ) !void {
        var stagingBuffer:       vk.VkBuffer       = undefined;
        var stagingBufferMemory: vk.VkDeviceMemory = undefined;
        try self.createBuffer(
            bufferSize,
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &stagingBuffer,
            &stagingBufferMemory,
        );
        defer vk.vkDestroyBuffer(self.device, stagingBuffer, null);
        defer vk.vkFreeMemory(self.device, stagingBufferMemory, null);

        var data: [*]Vertex = undefined;
        _ = vk.vkMapMemory(self.device, stagingBufferMemory, 0, bufferSize, 0, @ptrCast(&data));
        @memcpy(data, vertices[0..vertices.len]);
        vk.vkUnmapMemory(self.device, stagingBufferMemory);

        try self.createBuffer(
            bufferSize,
            vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT | vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            modelVertexBuffer,
            modelVertexBufferMemory,
        );

        self.copyBuffer(stagingBuffer, modelVertexBuffer.*, 0, 0, bufferSize);
    }

    fn createModelIndexBuffer(
        self:                   *VulkanLayer,
        indices:                []const u32,
        bufferSize:             vk.VkDeviceSize,
        modelIndexBuffer:       *vk.VkBuffer,
        modelIndexBufferMemory: *vk.VkDeviceMemory,
    ) !void {
        var stagingBuffer:       vk.VkBuffer       = undefined;
        var stagingBufferMemory: vk.VkDeviceMemory = undefined;
        try self.createBuffer(
            bufferSize,
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &stagingBuffer,
            &stagingBufferMemory,
        );
        defer vk.vkDestroyBuffer(self.device, stagingBuffer, null);
        defer vk.vkFreeMemory(self.device, stagingBufferMemory, null);

        var data: [*]u32 = undefined;
        _ = vk.vkMapMemory(self.device, stagingBufferMemory, 0, bufferSize, 0, @ptrCast(&data));
        @memcpy(data, indices[0..indices.len]);
        vk.vkUnmapMemory(self.device, stagingBufferMemory);

        try self.createBuffer(
            bufferSize,
            vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT | vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
            vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            modelIndexBuffer,
            modelIndexBufferMemory,
        );

        self.copyBuffer(stagingBuffer, modelIndexBuffer.*, 0, 0, bufferSize);
    }


    fn createAllDescriptorSets(
        self:               *VulkanLayer,
        particleSize:       usize,
        numOfParticles:     usize,
        worldEntitySize:    usize,
        numOfWorldEntities: usize,
    ) !void {
        try self.createComputeDescriptorSets(particleSize, numOfParticles, worldEntitySize, numOfWorldEntities);
        try self.createGraphicsDescriptorSets();
        try self.createParticleDescriptorSets();
    }

    fn createComputeDescriptorSets(
        self:               *VulkanLayer,
        particleSize:       usize,
        numOfParticles:     usize,
        worldEntitySize:    usize,
        numOfWorldEntities: usize,
    ) !void {
        var layouts = [_]vk.VkDescriptorSetLayout{self.computeDescriptorSetLayout} ** cfg.NUM_OF_THREADS;
        const allocInfo: vk.VkDescriptorSetAllocateInfo = .{
            .sType              = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool     = self.computeDescriptorPool,
            .descriptorSetCount = layouts.len,
            .pSetLayouts        = &layouts,
        };
        if (vk.vkAllocateDescriptorSets(self.device, &allocInfo, &self.computeDescriptorSets) != vk.VK_SUCCESS) {
            return error.FailedToAllocateDescriptorSets;
        }

        const particlesBufferSize     = particleSize * numOfParticles;
        const worldEntitiesBufferSize = worldEntitySize * numOfWorldEntities;
        for (0..self.computeDescriptorSets.len) |i| {
            const uniformBufferInfo: vk.VkDescriptorBufferInfo = .{
                .buffer = self.computeUniformBuffers[i],
                .offset = 0,
                .range  = @sizeOf(ComputeUniformBufferObject),
            };
            const prevIndex: usize = @intCast(@mod((@as(isize, @intCast(i)) - 1), cfg.NUM_OF_THREADS));
            const storageBufferInfoLastFrameInfo: vk.VkDescriptorBufferInfo = .{
                .buffer = self.particleShaderStorageBuffers[prevIndex],
                .offset = 0,
                .range  = particlesBufferSize,
            };
            const storageBufferInfoCurrentFrameInfo: vk.VkDescriptorBufferInfo = .{
                .buffer = self.particleShaderStorageBuffers[i],
                .offset = 0,
                .range  = particlesBufferSize,
            };
            const storageBufferWorldEntitiesInfo: vk.VkDescriptorBufferInfo = .{
                .buffer = self.computeWorldEntityStorageBuffer[i],
                .offset = 0,
                .range = worldEntitiesBufferSize,
            };

            var descriptorWrites = [_]vk.VkWriteDescriptorSet{
                .{
                    .sType           = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .dstSet          = self.computeDescriptorSets[i],
                    .dstBinding      = 0,
                    .dstArrayElement = 0,
                    .descriptorType  = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .descriptorCount = 1,
                    .pBufferInfo     = &uniformBufferInfo,
                },
                .{
                    .sType           = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .dstSet          = self.computeDescriptorSets[i],
                    .dstBinding      = 1,
                    .dstArrayElement = 0,
                    .descriptorType  = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                    .descriptorCount = 1,
                    .pBufferInfo     = &storageBufferInfoLastFrameInfo,
                },
                .{
                    .sType           = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .dstSet          = self.computeDescriptorSets[i],
                    .dstBinding      = 2,
                    .dstArrayElement = 0,
                    .descriptorType  = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                    .descriptorCount = 1,
                    .pBufferInfo     = &storageBufferInfoCurrentFrameInfo,
                },
                .{
                    .sType           = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .dstSet          = self.computeDescriptorSets[i],
                    .dstBinding      = 3,
                    .dstArrayElement = 0,
                    .descriptorType  = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                    .descriptorCount = 1,
                    .pBufferInfo     = &storageBufferWorldEntitiesInfo,
                }
            };

            vk.vkUpdateDescriptorSets(self.device, descriptorWrites.len, &descriptorWrites, 0, null);
        }
     }

    fn createGraphicsDescriptorSets(self: *VulkanLayer) !void {
        var layouts = [_]vk.VkDescriptorSetLayout{self.graphicsDescriptorSetLayout} ** cfg.NUM_OF_THREADS;
        const allocInfo: vk.VkDescriptorSetAllocateInfo = .{
            .sType              = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool     = self.graphicsDescriptorPool,
            .descriptorSetCount = layouts.len,
            .pSetLayouts        = &layouts,
        };
        if (vk.vkAllocateDescriptorSets(self.device, &allocInfo, &self.graphicsDescriptorSets) != vk.VK_SUCCESS) {
            return error.FailedToAllocateDescriptorSets;
        }

        for (0..self.graphicsDescriptorSets.len) |i| {
            const bufferInfo: vk.VkDescriptorBufferInfo = .{
                .buffer = self.worldEntityUniformBuffers[i],
                .offset = 0,
                .range  = @sizeOf(WorldEntityUniformBufferObject),
            };

            const descriptorWrites = [_]vk.VkWriteDescriptorSet{
                .{
                    .sType            = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .dstSet           = self.graphicsDescriptorSets[i],
                    .dstBinding       = 0,
                    .dstArrayElement  = 0,
                    .descriptorType   = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .descriptorCount  = 1,
                    .pBufferInfo      = &bufferInfo,
                    .pImageInfo       = null, // Optional
                    .pTexelBufferView = null, // Optional
                },
            };

            vk.vkUpdateDescriptorSets(self.device, descriptorWrites.len, &descriptorWrites, 0, null);
        }
    }

    fn createParticleDescriptorSets(self: *VulkanLayer) !void {
        var layouts = [_]vk.VkDescriptorSetLayout{self.particleDescriptorSetLayout} ** cfg.NUM_OF_THREADS;
        const allocInfo: vk.VkDescriptorSetAllocateInfo = .{
            .sType              = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool     = self.particleDescriptorPool,
            .descriptorSetCount = layouts.len,
            .pSetLayouts        = &layouts,
        };
        if (vk.vkAllocateDescriptorSets(self.device, &allocInfo, &self.particleDescriptorSets) != vk.VK_SUCCESS) {
            return error.FailedToAllocateDescriptorSets;
        }

        for (0..self.particleDescriptorSets.len) |i| {
            const bufferInfo: vk.VkDescriptorBufferInfo = .{
                .buffer = self.particleUniformBuffers[i],
                .offset = 0,
                .range  = @sizeOf(ParticleUniformBufferObject),
            };

            const descriptorWrites = [_]vk.VkWriteDescriptorSet{
                .{
                    .sType            = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .dstSet           = self.particleDescriptorSets[i],
                    .dstBinding       = 0,
                    .dstArrayElement  = 0,
                    .descriptorType   = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .descriptorCount  = 1,
                    .pBufferInfo      = &bufferInfo,
                    .pImageInfo       = null, // Optional
                    .pTexelBufferView = null, // Optional
                },
            };

            vk.vkUpdateDescriptorSets(self.device, descriptorWrites.len, &descriptorWrites, 0, null);
        }
    }

    fn readFile(comptime fileName: []const u8) []const u8 {
        return @embedFile(fileName);
    }

    fn createShaderModule(self: *VulkanLayer, comptime code: []const u8) !vk.VkShaderModule {
        const createInfo: vk.VkShaderModuleCreateInfo = .{
            .sType    = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = code.len,
            .pCode    = @alignCast(@ptrCast(code.ptr)),
        };

        var shaderModule: vk.VkShaderModule = undefined;
        if (vk.vkCreateShaderModule(self.device, &createInfo, null, &shaderModule) != vk.VK_SUCCESS) {
            return error.FailedToCreateShaderModule;
        }

        return shaderModule;
    }

    pub fn waitForDevice(self: *VulkanLayer) u32 {
        return @intCast(vk.vkDeviceWaitIdle(self.device));
    }

    pub fn waitUntilComputeIndexIsAvailable(self: *VulkanLayer, index: usize) void {
        _ = vk.vkWaitForFences(self.device, 1, &self.computeInFlightFences[index], vk.VK_TRUE, vk.UINT64_MAX);
    }

    pub fn waitUntilRenderIndexIsAvailable(self: *VulkanLayer, index: usize) void {
        _ = vk.vkWaitForFences(self.device, 1, &self.renderInFlightFences[index], vk.VK_TRUE, vk.UINT64_MAX);
    }
};

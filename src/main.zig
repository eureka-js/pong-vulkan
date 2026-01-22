const std     = @import("std");
const builtin = @import("builtin");

const GraphicsAPI      = @import("graphics-api.zig").GraphicsAPI;
const ApplicationLayer = @import("application-layer.zig").ApplicationLayer;
const VulkanLayer      = @import("vulkan-layer.zig").VulkanLayer;
const GameLayer        = @import("game-layer.zig").GameLayer;

const winmm = struct {
    pub extern fn timeBeginPeriod(ms: u32) u32;
    pub extern fn timeEndPeriod(ms: u32) u32;
};

pub fn main() !void {
    const isWindows = builtin.os.tag == .windows;
            if (isWindows) _ = winmm.timeBeginPeriod(1);
    defer { if (isWindows) _ = winmm.timeEndPeriod(1); }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));

    var appLayer = ApplicationLayer.init(&allocator, &prng.random());

    try appLayer.run();
}

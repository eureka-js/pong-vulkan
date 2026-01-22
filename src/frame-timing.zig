const std = @import("std");

pub fn updateFrameTime(
    currDeltaTime:        f32,
    accumulatedDeltaTime: *f32,
    numOfLoopItterations: *f32,
    avgFrameTime:         *std.atomic.Value(f32),
) void {
    accumulatedDeltaTime.* += currDeltaTime;
    numOfLoopItterations.* += 1.0;
    avgFrameTime.store(accumulatedDeltaTime.* / numOfLoopItterations.*, .release);

    if (accumulatedDeltaTime.* >= 1.0) {
        accumulatedDeltaTime.* = 0.0;
        numOfLoopItterations.* = 0.0;
    }
}

pub fn showFrameTime(printPrefix: []const u8, avgFrameTime: f32) void {
    std.debug.print("{s} logic ms:     {}\n",   .{printPrefix, avgFrameTime * std.time.ms_per_s});
    std.debug.print("{s} logic avgFps: {}\n\n", .{printPrefix, 1.0 / avgFrameTime});
}

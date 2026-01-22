const std = @import("std");

const cfg = @import("config.zig");

pub const ThreadStates = struct {
    pub const NUM_OF_STATES = cfg.NUM_OF_THREADS;

    pub const State = enum(u8) {
        GAME, COMPUTE, RENDER
    };

    states:           [NUM_OF_STATES]std.atomic.Value(State),
    currGameIndex:    std.atomic.Value(usize),
    currComputeIndex: usize,
    currRenderIndex:  usize,
};

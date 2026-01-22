const std = @import("std");

const Node = @import("node.zig").Node;

const time = @import("time.zig");

pub const ControlIndicator = struct {
    pub const OFF:  f32    = 1.0 / 80.0;
    pub const ON:   f32    = OFF * 4;
    const states:   [3]f32 = .{OFF, ON, ON * 3};
    currStateIndex: usize,

    node: Node,

    pub fn flipOn(self: *ControlIndicator) void {
        self.setSwitchTo(ON);
    }

    pub fn flipOff(self: *ControlIndicator) void {
        self.setSwitchTo(OFF);
    }

    pub fn flip(self: *ControlIndicator) void {
        self.currStateIndex = (self.currStateIndex + 1) % states.len;
        const state = states[self.currStateIndex];
        self.setSwitchTo(state);
    }

    fn setSwitchTo(self: *ControlIndicator, state: f32) void {
        self.node.opacity = state;
    }

    pub fn deinit(self: *ControlIndicator) void {
        self.node.deinit();
    }
};

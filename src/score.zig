const cglm = @import("bindings/cglm.zig").cglm;

const std  = @import("std");

const Mesh   = @import("mesh.zig").Mesh;
const Vertex = @import("vertex.zig").Vertex;
const Node   = @import("node.zig").Node;

pub const Score = struct{
    const ON_DEPTH:  f16 = 0.9;
    const OFF_DEPTH: f16 = 1.0;
    const DIGIT_SEGMENT_DEPTHS  = [_][]const f32{
        &.{ON_DEPTH,  ON_DEPTH,  ON_DEPTH,  ON_DEPTH,  ON_DEPTH,  ON_DEPTH,  OFF_DEPTH},
        &.{OFF_DEPTH, ON_DEPTH,  ON_DEPTH,  OFF_DEPTH, OFF_DEPTH, OFF_DEPTH, OFF_DEPTH},
        &.{ON_DEPTH,  ON_DEPTH,  OFF_DEPTH, ON_DEPTH,  ON_DEPTH,  OFF_DEPTH, ON_DEPTH},
        &.{ON_DEPTH,  ON_DEPTH,  ON_DEPTH,  ON_DEPTH,  OFF_DEPTH, OFF_DEPTH, ON_DEPTH},
        &.{OFF_DEPTH, ON_DEPTH,  ON_DEPTH,  OFF_DEPTH, OFF_DEPTH, ON_DEPTH,  ON_DEPTH},
        &.{ON_DEPTH,  OFF_DEPTH, ON_DEPTH,  ON_DEPTH,  OFF_DEPTH, ON_DEPTH,  ON_DEPTH},
        &.{ON_DEPTH,  OFF_DEPTH, ON_DEPTH,  ON_DEPTH,  ON_DEPTH,  ON_DEPTH,  ON_DEPTH},
        &.{ON_DEPTH,  ON_DEPTH,  ON_DEPTH,  OFF_DEPTH, OFF_DEPTH, OFF_DEPTH, OFF_DEPTH},
        &.{ON_DEPTH,  ON_DEPTH,  ON_DEPTH,  ON_DEPTH,  ON_DEPTH,  ON_DEPTH,  ON_DEPTH},
        &.{ON_DEPTH,  ON_DEPTH,  ON_DEPTH,  OFF_DEPTH, OFF_DEPTH, ON_DEPTH,  ON_DEPTH},
    };

    // Seven-segment display
    //  --- A ---
    // |        |
    // F        B
    // |        |
    //  --- G ---
    // |        |
    // E        C
    // |        |
    //  --- D ---
    // A = 0, B = 1, C = 2, D = 3, E = 4, F = 5, G = 6
    nodes: [7]Node,

    currDigit: usize,
    didWrap:   bool,

    pub fn increment(self: *Score) void {
        self.currDigit = (self.currDigit + 1) % 10;
        if (self.currDigit == 0) {
            self.didWrap = true;
        }

        const depths = Score.DIGIT_SEGMENT_DEPTHS[self.currDigit];
        for (0..self.nodes.len) |i| {
            self.nodes[i].depth = depths[i];
        }
    }

    pub fn setToZero(self: *Score) void {
        self.currDigit = 0;

        const depths = Score.DIGIT_SEGMENT_DEPTHS[self.currDigit];
        for (0..self.nodes.len) |i| {
            self.nodes[i].depth = depths[i];
        }
    }

    pub fn reset(self: *Score) void {
        self.setToZero();
        self.didWrap = false;
    }

    pub fn isZero(self: *Score) bool {
        return self.currDigit == 0;
    }

    pub fn deinit(self: *Score) void {
        for (&self.nodes) |*node| {
            node.deinit();
        }
    }
};

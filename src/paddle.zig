const cglm = @import("bindings/cglm.zig").cglm;

const std  = @import("std");

const Mesh        = @import("mesh.zig").Mesh;
const Node        = @import("node.zig").Node;
const BoundingBox = @import("bounding-box.zig").BoundingBox;

pub const Paddle = struct{
    node: Node,

    currBoundingBox: BoundingBox,
    prevBoundingBox: BoundingBox,

    prevTranslation: cglm.vec2,
    currVelocity:    cglm.vec2,
    prevVelocity:    cglm.vec2,
    speed:           f32,

    hasWon:          bool,
    isDirty:         bool,

    pub fn setTranslation(
        self:        *Paddle,
        translation: cglm.vec2,
        epsilon:     f32,
    ) void {
        self.prevTranslation  = self.node.translation;
        self.node.translation = translation;

        self.prevBoundingBox  = self.currBoundingBox;
        self.currBoundingBox.setTo(translation, self.node.width, self.node.height, epsilon);

        self.isDirty          = true;
    }

    pub fn moveBy(self: *Paddle, velocity: cglm.vec2) void {
        self.prevTranslation = self.node.translation;

        self.prevBoundingBox = self.currBoundingBox;
        cglm.glm_vec2_add(&self.node.translation, @constCast(@ptrCast(&velocity)), &self.node.translation);
        self.currBoundingBox.updateBy(velocity);

        self.isDirty         = true;
    }

    pub fn setVelocityYTo(self: *Paddle, velY: f32) void {
        self.prevVelocity    = self.currVelocity;
        self.currVelocity[1] = velY;
        self.isDirty         = true;
    }

    pub fn deinit(self: *Paddle) void {
        self.node.deinit();
    }
};

const cglm = @import("bindings/cglm.zig").cglm;

const std = @import("std");

const Mesh        = @import("mesh.zig").Mesh;
const Node        = @import("node.zig").Node;
const BoundingBox = @import("bounding-box.zig").BoundingBox;
const time        = @import("time.zig");

pub const Ball = struct {
    node: Node,

    currBoundingBox: BoundingBox,
    prevBoundingBox: BoundingBox,
 
    prevTranslation:  cglm.vec2,
    currVelocity:     cglm.vec2,
    prevVelocity:     cglm.vec2,
    speed:            f32,

    timeTillMovement: f64,
    doRestart:        bool,
    isDirty:          bool,

    pub fn canMove(self: *Ball) bool {
        return time.getTimeInSeconds() > self.timeTillMovement;
    }

    pub fn setTranslation(
        self:        *Ball,
        translation: cglm.vec2,
        epsilon:     f32,
    ) void {
        self.prevTranslation  = self.node.translation;
        self.node.translation = translation;

        self.prevBoundingBox  = self.currBoundingBox;
        self.currBoundingBox.setTo(translation, self.node.width, self.node.height, epsilon);

        self.isDirty = true;
    }

    pub fn moveBy(self: *Ball, velocity: cglm.vec2) void {
        self.prevTranslation = self.node.translation;

        self.prevBoundingBox = self.currBoundingBox;
        cglm.glm_vec2_add(&self.node.translation, @constCast(@ptrCast(&velocity)), &self.node.translation);
        self.currBoundingBox.updateBy(velocity);

        self.isDirty = true;
    }

    pub fn correctThePosition(self: *Ball, velocity: cglm.vec2) void {
        cglm.glm_vec2_add(&self.node.translation, @constCast(@ptrCast(&velocity)), &self.node.translation);
        self.currBoundingBox.updateBy(velocity);

        self.isDirty = true;
    }

    pub fn setVelocityTo(self: *Ball, velocity: cglm.vec2) void {
        self.prevVelocity = self.currVelocity;
        self.currVelocity = velocity;

        self.isDirty = true;
    }

    pub fn deinit(self: *Ball) void {
        self.node.deinit();
    }
};

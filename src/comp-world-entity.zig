const cglm = @import("bindings//cglm.zig").cglm;

const BoundingBox = @import("bounding-box.zig").BoundingBox;

pub const ComputeWorldEntity = struct {
    pub const NUM_OF_ENTITIES: usize = 3;

    currBoundingBox:     BoundingBox,
    prevBoundingBox:     BoundingBox,
    currVelocity:        cglm.vec2,
    prevVelocity:        cglm.vec2,
    prevPrevVelocity:    cglm.vec2,
    _pad: [2]f32 = undefined,
};

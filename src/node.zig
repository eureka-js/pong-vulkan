const cglm = @import("bindings/cglm.zig").cglm;

const std  = @import("std");

const Mesh             = @import("mesh.zig").Mesh;
const Vertex           = @import("vertex.zig").Vertex;
const BoundingBox      = @import("bounding-box.zig").BoundingBox;
const CollisionHandler = @import("collision-handler.zig").CollisionHandler;

pub const Node = struct{
    mesh:        *Mesh,
    translation: cglm.vec2,
    width:       f32,
    height:      f32,
    depth:       f32,
    opacity:     f32,

    pub fn getCenter(self: *Node) cglm.vec2 {
        return .{self.translation[0] + self.width / 2, self.translation[1] + self.height / 2};
    }

    pub fn deinit(self: *Node) void {
        self.mesh.deinit();
    }
};

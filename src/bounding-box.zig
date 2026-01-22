const cglm = @import("bindings/cglm.zig").cglm;

pub const BoundingBox = struct {
    minX: f32,
    maxX: f32,
    minY: f32,
    maxY: f32,

    pub fn init(
        position: cglm.vec2,
        width:    f32,
        height:   f32,
        epsilon:  f32,
    ) BoundingBox {
        return .{
            .minX = position[0] - epsilon,
            .maxX = position[0] + width + epsilon,
            .minY = position[1] - epsilon,
            .maxY = position[1] + height + epsilon,
        };
    }

    pub fn updateBy(self: *BoundingBox, velocity: cglm.vec2) void {
        self.minX += velocity[0];
        self.maxX += velocity[0];
        self.minY += velocity[1];
        self.maxY += velocity[1];
    }

    pub fn setTo(
        self:     *BoundingBox,
        position: cglm.vec2,
        width:    f32,
        height:   f32,
        epsilon:  f32,
    ) void {
        self.minX = position[0] - epsilon;
        self.maxX = position[0] + width + epsilon;
        self.minY = position[1] - epsilon;
        self.maxY = position[1] + height + epsilon;
    }

    pub fn getSweptBoundingBoxFromVel(self: *BoundingBox, velocity: cglm.vec2) BoundingBox {
        return .{
            .minX = @min(self.minX, self.minX + velocity[0]),
            .maxX = @max(self.maxX, self.maxX + velocity[0]),
            .minY = @min(self.minY, self.minY + velocity[1]),
            .maxY = @max(self.maxY, self.maxY + velocity[1]),
        };
    }

    pub fn getSweptBoundingBoxFromBB(self: *BoundingBox, bb1: *const BoundingBox) BoundingBox {
        return .{
            .minX = @min(self.minX, bb1.minX),
            .maxX = @max(self.maxX, bb1.maxX),
            .minY = @min(self.minY, bb1.minY),
            .maxY = @max(self.maxY, bb1.maxY),
        };
    }

    pub fn getShavedOffBy(self: *BoundingBox, amount: f32) BoundingBox {
        return .{
            .minX = self.minX + amount,
            .maxX = self.maxX - amount,
            .minY = self.minY + amount,
            .maxY = self.maxY - amount,
        };
    }

    pub fn getHeight(self: *const BoundingBox) f32 {
        return self.maxY - self.minY;
    }

    pub fn getWidth(self: *const BoundingBox) f32 {
        return self.maxX - self.minX;
    }

    pub fn getCenterX(self: *const BoundingBox) f32 {
        return 0.5 * (self.maxX + self.minX);
    }

    pub fn getCenterY(self: *const BoundingBox) f32 {
        return 0.5 * (self.maxY + self.minY);
    }
};

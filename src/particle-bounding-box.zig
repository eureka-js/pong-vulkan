const cglm = @import("bindings/cglm.zig").cglm;

pub const ParticleBoundingBox = struct {
    minX: f32,
    maxX: f32,
    minY: f32,
    maxY: f32,

    pub fn init(position: cglm.vec2, size: f32) ParticleBoundingBox {
        const halfSize = size / 2;
        return .{
            .minX = position[0] - halfSize,
            .maxX = position[0] + halfSize,
            .minY = position[1] - halfSize,
            .maxY = position[1] + halfSize,
        };
    }

    pub fn setTo(
        self:     *ParticleBoundingBox,
        position: cglm.vec2,
        size:     f32,
    ) void {
        const halfSize = size / 2;
        self.minX = position[0] - halfSize;
        self.maxX = position[0] + halfSize;
        self.minY = position[1] - halfSize;
        self.maxY = position[1] + halfSize;
    }

    pub fn getSweptBoundingBox(
        self:               *ParticleBoundingBox,
        velocityDeltaTimed: cglm.vec2,
    ) ParticleBoundingBox {
        return .{
            .minX = @min(self.minX, self.minX + velocityDeltaTimed[0]),
            .maxX = @max(self.maxX, self.maxX + velocityDeltaTimed[0]),
            .minY = @min(self.minY, self.minY + velocityDeltaTimed[1]),
            .maxY = @max(self.maxY, self.maxY + velocityDeltaTimed[1]),
        };
    }
};

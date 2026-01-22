const cglm = @import("bindings/cglm.zig").cglm;

const std = @import("std");

const Node        = @import("node.zig").Node;
const Paddle      = @import("paddle.zig").Paddle;
const Ball        = @import("ball.zig").Ball;
const BoundingBox = @import("bounding-box.zig").BoundingBox;

pub const CollisionHandler = struct {
    pub const Side = enum {
        UP, DOWN, LEFT, RIGHT
    };

    pub const SweptAABBResult = struct {
        normalX:       f32,
        normalY:       f32,
        collisionTime: f32,
    };

    worldBoundingBox: BoundingBox,
    epsilon:          f32,

    pub fn doCollide(box0: BoundingBox, box1: BoundingBox) bool {
        return AABB(box0, box1);
    }

    pub fn AABB(box0: BoundingBox, box1: BoundingBox) bool {
        return box0.minX <= box1.maxX and box0.maxX >= box1.minX and box0.minY <= box1.maxY and box0.maxY >= box1.minY;
    }

    pub fn sweptAABB(
        box0:    BoundingBox,
        box1:    BoundingBox,
        box0Vel: cglm.vec2,
        box1Vel: cglm.vec2,
    ) SweptAABBResult {
        // NOTE: This is a somewhat bastardized version of Swept AABB that more accurately determines the side of the box1
        //  at which the box0 and box1 collided at. Pure Swept AABB doesn't determine that accurately because it calculates
        //  the penetration from the sides (top, bottom, right, left) and not from the point of impact. (2025-10-24)
        // NOTE: This is still inaccurate for some special edge cases, but it being only one ball that is relatively close
        //  to paddles in terms of size means that it works for all cases in practice, even though there could be some false positives
        //  in terms of flipping y velocity direction instead of x for the ball. I haven't noticed that edge case in my testing. (2025-10-28)

        var result: SweptAABBResult = undefined;

        const box0VelX = box0Vel[0];
        const box0VelY = box0Vel[1];
        const box1VelX = box1Vel[0];
        const box1VelY = box1Vel[1];

        const finalVelX = box0VelX - box1VelX;
        const finalVelY = box0VelY - box1VelY;

        var xInvEntry: f32 = undefined;
        var xInvExit:  f32 = undefined;
        var yInvEntry: f32 = undefined;
        var yInvExit:  f32 = undefined;
        if (finalVelX > 0.0) {
            xInvEntry = box1.minX - box0.maxX;
            xInvExit  = box1.maxX - box0.minX;
        } else {
            xInvEntry = box1.maxX - box0.minX;
            xInvExit  = box1.minX - box0.maxX;
        }
        if (finalVelY > 0.0) {
            yInvEntry = box1.minY - box0.maxY;
            yInvExit  = box1.maxY - box0.minY;
        } else {
            yInvEntry = box1.maxY - box0.minY;
            yInvExit  = box1.minY - box0.maxY;
        }

        var xEntry: f32 = undefined;
        var xExit:  f32 = undefined;
        var yEntry: f32 = undefined;
        var yExit:  f32 = undefined;
        if (finalVelX == 0.0) {
            xEntry = -std.math.inf(f32);
            xExit  =  std.math.inf(f32);
        } else {
            xEntry = xInvEntry / finalVelX;
            xExit  = xInvExit / finalVelX;

            if (yInvEntry * -std.math.sign(finalVelY) >= 0.0 and xEntry < -1.0) {
                xEntry = -std.math.inf(f32);
                xExit  =  std.math.inf(f32);
            }
        }
        if (finalVelY == 0.0) {
            yEntry = -std.math.inf(f32);
            yExit  =  std.math.inf(f32);
        } else {
            yEntry = yInvEntry / finalVelY;
            yExit  = yInvExit / finalVelY;

            if (xInvEntry * -std.math.sign(finalVelX) >= 0.0 and yEntry < -1.0) {
                yEntry = -std.math.inf(f32);
                yExit  =  std.math.inf(f32);
            }
        }

        const entryTime = @max(xEntry, yEntry);
        const exitTime  = @min(xExit, yExit);
        if (std.math.sign(entryTime) == std.math.sign(exitTime) and @abs(entryTime) > @abs(exitTime) or entryTime > exitTime
                or entryTime > 0.0
                or xEntry < -1.0 and xEntry != -std.math.inf(f32) or yEntry < -1.0 and yEntry != -std.math.inf(f32)) {
            result = .{
                .normalX       = 0.0,
                .normalY       = 0.0,
                .collisionTime = 1.0,
            };
        } else {
            if (xEntry == entryTime) {
                result.normalX = if (@abs(box0VelX) >= @abs(box1VelX)) -std.math.sign(box0VelX) else std.math.sign(box1VelX);
                result.normalY = 0.0;
            } else {
                result.normalX = 0.0;
                result.normalY = if (@abs(box0VelY) >= @abs(box1VelY)) -std.math.sign(box0VelY) else std.math.sign(box1VelY);
            }
            result.collisionTime = entryTime;
        }

        return result;
    }
};

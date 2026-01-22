const cglm = @import("bindings//cglm.zig").cglm;

const std = @import("std");

const GameInputHandler = @import("game-input-handler.zig").GameInputHandler;
const CollisionHandler = @import("collision-handler.zig").CollisionHandler;
const BoundingBox      = @import("bounding-box.zig").BoundingBox;
const Player           = @import("player.zig").Player;
const Paddle           = @import("paddle.zig").Paddle;
const Ball             = @import("ball.zig").Ball;
const Node             = @import("node.zig").Node;
const time             = @import("time.zig");

pub const AI = struct {
    const Mode = enum {
        UNCONSTRAINED,
        CONSTRAINED,
    };

    const PredictionResult = struct {
        ballCenterPosY:   f32,
        numOfBallBounces: f32,
    };

    inputHandler: GameInputHandler,

    doesGoUp:   bool = false,
    doesGoDown: bool = false,

    predictedBallCenterPosY: f32,
    previousBallVelocity:    cglm.vec2,

    mode:                   Mode,
    reactionTimeInMs:       f64,
    timeTillNextActionInMs: f64 = 0.0,

    doForceAction: bool,

    prng: *const std.Random,

    pub fn getInputHandler(self: *AI) *GameInputHandler {
        return &self.inputHandler;
    }

    pub fn signalTurnOff(self: *AI) void {
        self.forceAction();
    }

    pub fn forceAction(self: *AI) void {
        self.doForceAction = true;
    }

    pub fn takeAction(
        self:             *AI,
        paddleInfo:       *const Player.GameEntityInfo,
        ballInfo:         *const Player.GameEntityInfo,
        worldBoundingBox: BoundingBox,
    ) void {
        const currTimeInMs = time.getTimeInSeconds() * std.time.ms_per_s;
        if (currTimeInMs < self.timeTillNextActionInMs) {
            return;
        }

        defer {
            // NOTE: This will cause the AI paddle to never perfectly align with the predicted center of the ball, because
            //  these are only booleans that the input logic uses to apply the velocity to the paddle. The reason is that
            //  controling via the velocity will cause the paddle to overshoot the predicted y position. (2025-10-16)
            self.doesGoUp   = paddleInfo.centerY < self.predictedBallCenterPosY;
            self.doesGoDown = paddleInfo.centerY > self.predictedBallCenterPosY;
        }

        if (!self.doForceAction) {
            if (ballInfo.currVelocity[0] == self.previousBallVelocity[0] and ballInfo.currVelocity[1] == self.previousBallVelocity[1]) {
                return;
            }
        } else {
            self.doForceAction = false;
        }

        self.previousBallVelocity = ballInfo.currVelocity;

        // NOTE: This prediction is a pure trigonometric calculation that doesn't account for the positional correction
        //  that this project's collision logic performs. The result is that, here, the ball's predicted center y
        //  is the y of the actual surface collision point. Whereas the swept AABB (that this project uses) doesn't
        //  give information about both axis penetrations; instead it gives only the smallest one from the pov of
        //  the sides of the paddle and not the point of impact, hence, it corrects only that axis. (2025-11-04)
        const res = predictFinalBallPositionY(ballInfo.currBoundingBox, ballInfo.currVelocity, paddleInfo.currBoundingBox, worldBoundingBox);

        var paddlePosOffset:  f32 = undefined;
        var currReactionTime: f32 = undefined;
        if (self.mode == .UNCONSTRAINED) {
            paddlePosOffset  = 0.0;
            currReactionTime = @floatCast(self.reactionTimeInMs);
        } else {
            const paddleBBHeight = paddleInfo.currBoundingBox.getHeight();
            paddlePosOffset  = (@as(f32, @floatFromInt(self.prng.intRangeAtMost(u32, 0, @intFromFloat(paddleBBHeight / 2)))) - paddleBBHeight / 4) * (res.numOfBallBounces + 1.0 / 1.5) * 1.5;
            currReactionTime = @floatFromInt(self.prng.intRangeAtMost(
                i32,
                @as(i32, @intFromFloat(self.reactionTimeInMs / 2)),
                @as(i32, @intFromFloat(self.reactionTimeInMs * 2))
            ));
        }

        self.predictedBallCenterPosY = res.ballCenterPosY + paddlePosOffset;
        self.timeTillNextActionInMs  = currTimeInMs + currReactionTime;
    }

    fn predictFinalBallPositionY(
        ballCurrBoundingBox:   BoundingBox,
        ballCurrVelocity:      cglm.vec2,
        paddleCurrBoundingBox: BoundingBox,
        worldBoundingBox:      BoundingBox,
    ) PredictionResult {
        // This uses trigonometry to calculate the end ball position. It extends the velocity 'vector' of the ball
        //  until it reaches the side of the world it points to. It uses the length of the calculated opposite side
        //  of that triangle to get the total ball travel in the y direction, and it uses reasoning
        //  to correctly decide the end y position based on that total travel.
        // NOTE: The reasoning given bellow in the comments is the reasoning that made me write the correct prediction
        //  algorithm; but it should not be accepted as an absolute truth because I might have explained it poorly, or I might have
        //  a wrong understanding of it even though I wrote it such that it works correctly within the bounds of this Pong game. (2025-09-10)

        // The prediction needs to look for an end y position that is on the front side of the paddle,
        //  not on the actual left or right world side. The reason is that, otherwise, when the ball comes from the shallow angle;
        //  the paddle would not be positioned such that the ball hits the paddle. "paddleContactPosOffsetX' corrects this.
        const paddleContactPosX = if (paddleCurrBoundingBox.getCenterX() < worldBoundingBox.getCenterX())
                paddleCurrBoundingBox.maxX
            else
                worldBoundingBox.maxX - paddleCurrBoundingBox.minX;
        const ballContactPosX   = if (ballCurrVelocity[0] < 0.0)
                ballCurrBoundingBox.minX - paddleContactPosX
            else
                worldBoundingBox.maxX - ballCurrBoundingBox.maxX - paddleContactPosX;
        // It uses the absolute value of the velocity slope because 'triangleOppositeSide' represents the amount of travel,
        //  and not the direction as well.
        const triangleOppositeSide = ballCurrVelocity[1] / @abs(ballCurrVelocity[0]) * @max(0.0, ballContactPosX);
        const totalY               = ballCurrBoundingBox.getCenterY() - worldBoundingBox.minY + triangleOppositeSide;

        // The trigonometric calculation doesn't take into account the ball's height, so you have to lower the
        //  world height by the ball's height to use the values of the proper distance that the ball covered.
        // If the ball's height is not being taken into account, then the remainderY would be lower than it has to be,
        //  and the numOfBounces could be higher in some edge cases which would cause the endY calculation to
        //  be the reverse of what it should be which would wrap the remainderY to the opposite side.
        // NOTE: The origin of the ball is at the bottom left so it cannot travel the whole world height
        //  because of it's own height. (2025-10-09)
        const correctedWorldHeight = worldBoundingBox.getHeight() - ballCurrBoundingBox.getHeight();

        const remainderY = @mod(totalY, correctedWorldHeight);

        // It could be looked at such that each full world height travel represent a bounce, and that each uneven bounce
        //  represents the opposite y direction of the first, pre bounce, direction. Each current world height partition
        //  represents a ball direction (and at what side the bottom is) at that bounce; and at the last world height partition,
        //  the remainder y represents the final ball y position. If the last bounce/world_partition is uneven, then the
        //  velocity direction of the ball is the opposite of the first direction, which means that you need to reverse
        //  from which vertical world side you calculate the remainder y (worldMinY + remainderY, or worldMaxY - remainderY).
        const numOfBounces = @floor(totalY / correctedWorldHeight);

        const endY = if (@mod(numOfBounces, 2) == 0) worldBoundingBox.minY + remainderY else worldBoundingBox.maxY - remainderY;

        return .{.ballCenterPosY = endY, .numOfBallBounces = numOfBounces};
    }

    pub fn init(
        inputHandler:     GameInputHandler,
        worldHeight:      f32,
        prng:             *const std.Random,
        mode:             Mode,
        reactionTimeInMs: f32,
    ) AI {
        return .{
            .inputHandler            = inputHandler,
            .predictedBallCenterPosY = worldHeight / 2,
            .previousBallVelocity    = .{0.0, 0.0},
            .prng                    = prng,
            .mode                    = mode,
            .reactionTimeInMs        = reactionTimeInMs,
            .doForceAction           = true,
        };
    }
};

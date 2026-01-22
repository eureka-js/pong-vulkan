const cglm = @import("bindings//cglm.zig").cglm;

const Human            = @import("human.zig").Human;
const AI               = @import("ai.zig").AI;
const GameInputHandler = @import("game-input-handler.zig").GameInputHandler;
const Paddle           = @import("paddle.zig").Paddle;
const Ball             = @import("ball.zig").Ball;
const BoundingBox      = @import("bounding-box.zig").BoundingBox;

pub const Player = union(enum) {
    pub const GameEntityInfo = struct {
        currBoundingBox:         BoundingBox,
        currVelocity:            cglm.vec2,
        centerY:                 f32,
    };

    human: Human,
    ai:    AI,

    pub fn getInputHandler(self: *Player) *GameInputHandler {
        return switch(self.*) {
            inline .human => |*human| human.getInputHandler(),
            inline .ai    => |*ai|    ai.getInputHandler(),
        };
    }

    pub fn signalTurnOff(self: *Player) void {
        return switch(self.*) {
            inline .human => |*human| human.signalTurnOff(),
            inline .ai    => |*ai|    ai.signalTurnOff(),
        };
    }

    pub fn forceAction(self: *Player) void {
        return switch(self.*) {
            inline .human => |*human| human.forceAction(),
            inline .ai    => |*ai|    ai.forceAction(),
        };
    }

    pub fn takeAction(
        self:             *Player,
        paddleInfo:       *const GameEntityInfo,
        ballInfo:         *const GameEntityInfo,
        worldBoundingBox: BoundingBox,
    ) void {
        return switch(self.*) {
            inline .human => |*human| human.takeAction(paddleInfo, ballInfo, worldBoundingBox),
            inline .ai    => |*ai|    ai.takeAction(paddleInfo, ballInfo, worldBoundingBox),
        };
    }

    pub fn doesGoUp(self: *Player) bool {
        return switch(self.*) {
            inline .human => |*human| human.doesGoUp,
            inline .ai    => |*ai|    ai.doesGoUp,
        };
    }

    pub fn doesGoDown(self: *Player) bool {
        return switch(self.*) {
            inline .human => |*human| human.doesGoDown,
            inline .ai    => |*ai|    ai.doesGoDown,
        };
    }
};

const GameInputHandler = @import("game-input-handler.zig").GameInputHandler;
const BoundingBox      = @import("bounding-box.zig").BoundingBox;
const Player           = @import("player.zig").Player;
const Paddle           = @import("paddle.zig").Paddle;
const Ball             = @import("ball.zig").Ball;

pub const Human = struct {
    inputHandler: GameInputHandler,

    doesGoUp:   bool = false,
    doesGoDown: bool = false,

    pub fn getInputHandler(self: *Human) *GameInputHandler {
        return &self.inputHandler;
    }

    pub fn signalTurnOff(self: *Human) void {
        _ = self;
    }

    pub fn forceAction(self: *Human) void {
        _ = self;
    }

    pub fn takeAction(
        self:             *Human,
        paddle:           *const Player.GameEntityInfo,
        ball:             *const Player.GameEntityInfo,
        worldBoundingBox: BoundingBox,
    ) void {
        _, _, _, _ = .{self, paddle, ball, worldBoundingBox};

        self.doesGoUp   = self.inputHandler.isKeyPressed(self.inputHandler.keys[0]);
        self.doesGoDown = self.inputHandler.isKeyPressed(self.inputHandler.keys[1]);
    }
};

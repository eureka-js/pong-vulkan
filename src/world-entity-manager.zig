const std = @import("std");

const ThreadContextComptime = @import("thread-context.zig").ThreadContextComptime;
const PlayerManager         = @import("player-manager.zig").PlayerManager;
const Paddle                = @import("paddle.zig").Paddle;
const Ball                  = @import("ball.zig").Ball;
const Score                 = @import("score.zig").Score;
const CenterLine            = @import("center-line.zig").CenterLine;
const ControlIndicator      = @import("control-indicator.zig").ControlIndicator;
const BufferManager         = @import("buffer-manager.zig").BufferManager;

const cfg = @import("config.zig");

pub const WorldEntityManager = struct {
    pub const NUM_OF_STATES = cfg.NUM_OF_THREADS;

    underlyingBall:       Ball,
    underlyingPaddles:    [PlayerManager.PLAYER_COUNT]Paddle,
    underlyingCenterLine: CenterLine,
    underlyingScores:     [PlayerManager.PLAYER_COUNT]Score,
    underlyingIndicators: [PlayerManager.PLAYER_COUNT][3]ControlIndicator,

    ball:       [NUM_OF_STATES]Ball,
    paddles:    [NUM_OF_STATES][PlayerManager.PLAYER_COUNT]Paddle,
    centerLine: [NUM_OF_STATES]CenterLine,
    scores:     [NUM_OF_STATES][PlayerManager.PLAYER_COUNT]Score,
    indicators: [NUM_OF_STATES][PlayerManager.PLAYER_COUNT][3]ControlIndicator,

    pub fn deinit(self: *WorldEntityManager, ctx: *const ThreadContextComptime) void {
        ctx.graphicsApiRelated.deinitRenderWorldEntitiesResoruces(ctx.graphicsApiRelated.graphicsAPI);
        for (&self.underlyingPaddles)    |*paddle|                                      paddle.deinit();
        for (&self.underlyingScores)     |*score|                                       score.deinit();
        for (&self.underlyingIndicators) |*indicators|    for (indicators) |*indicator| indicator.deinit();
                                                                                        self.underlyingBall.deinit();
                                                                                        self.underlyingCenterLine.deinit();
    }
};

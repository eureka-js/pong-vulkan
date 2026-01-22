const Player       = @import("player.zig").Player;
const Human        = @import("human.zig").Human;
const AI           = @import("ai.zig").AI;
const InputHandler = @import("input-handler.zig").InputHandler;

pub const PlayerManager = struct {
    pub const PLAYER_COUNT = 2;

    players: [6]Player,
    playerOneIndex: usize = 0,
    playerTwoIndex: usize = 0,

    playerOne: *Player,
    playerTwo: *Player,

    pub fn flipPlayerOne(self: *PlayerManager) void {
        self.playerOne.signalTurnOff();
        self.playerOneIndex = (self.playerOneIndex + 1) % 3;
        self.playerOne = &self.players[self.playerOneIndex];
    }

    pub fn flipPlayerTwo(self: *PlayerManager) void {
        self.playerTwo.signalTurnOff();
        self.playerTwoIndex = (self.playerTwoIndex + 1) % 3 + 3;
        self.playerTwo = &self.players[self.playerTwoIndex];
    }
};

const InputHandler = @import("input-handler.zig").InputHandler;

pub const GameInputHandler = struct {
    inputHandler: *InputHandler,
    keys:         []const c_int,

    pub fn isKeyPressed(self: *GameInputHandler, key: c_int) bool {
        return self.inputHandler.isKeyPressed(key);
    }

    pub fn isKeyClicked(self: *GameInputHandler, key: c_int) bool {
        return self.inputHandler.isKeyClicked(key);
    }

    pub fn cleanKeys(self: *GameInputHandler) void {
        self.inputHandler.cleanKeys(self.keys);
    }
};

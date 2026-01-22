const glfw = @import("bindings/glfw.zig").glfw;

const ApplicationLayer = @import("application-layer.zig").ApplicationLayer;
const GameInputHandler = @import("game-input-handler.zig").GameInputHandler;

pub const InputHandler = struct {
    pub const KEY = enum(c_int) {
        ESC    = glfw.GLFW_KEY_ESCAPE,
        W      = glfw.GLFW_KEY_W,
        S      = glfw.GLFW_KEY_S,
        UP     = glfw.GLFW_KEY_UP,
        DOWN   = glfw.GLFW_KEY_DOWN,
        A      = glfw.GLFW_KEY_A,
        RIGHT  = glfw.GLFW_KEY_RIGHT,

        pub inline fn asInt(self: KEY) c_int {
            return @intFromEnum(self);
        }
    };

    pub const STATE = enum(c_int) {
        PRESS   = glfw.GLFW_PRESS,
        RELEASE = glfw.GLFW_RELEASE,

        pub inline fn asInt(self: STATE) c_int {
            return @intFromEnum(self);
        }
    };

    const KEY_COUNT: usize = glfw.GLFW_KEY_LAST;

    keysPressed:  [KEY_COUNT]bool = .{false} ** (KEY_COUNT),
    keysReleased: [KEY_COUNT]bool = .{false} ** (KEY_COUNT),
    keys:         []const c_int,

    pub fn isKeyPressed(self: *InputHandler, key: c_int) bool {
        return self.keysPressed[@intCast(key)];
    }

    pub fn isKeyClicked(self: *InputHandler, key: c_int) bool {
        return self.keysReleased[@intCast(key)];
    }

    pub fn clean(self: *InputHandler) void {
        for (self.keys) |key| {
            self.keysReleased[@intCast(key)] = false;
        }
    }

    pub fn cleanKeys(self: *InputHandler, keys: []const c_int) void {
        for (keys) |key| {
            self.keysReleased[@intCast(key)] = false;
        }
    }

    pub fn keyCallback(
        window:   ?*glfw.GLFWwindow,
        key:      c_int,
        scancode: c_int,
        action:   c_int,
        mods:     c_int
    ) callconv(.c) void {
        _, _ = .{scancode, mods};
        const app: *ApplicationLayer = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(window)));

        const allInputHandlerKeys = [_][]const c_int{
            app.appInputHandler.keys,
            app.gameLayer.gameSettingsInputHandler.keys,
            app.gameLayer.playerManager.playerOne.getInputHandler().keys,
            app.gameLayer.playerManager.playerTwo.getInputHandler().keys,
        };
        for (allInputHandlerKeys) |inputHandlerKeys| {
            for (inputHandlerKeys) |inputHandlerKey| {
                if (key != inputHandlerKey) {
                    continue;
                }

                if (action == STATE.PRESS.asInt()) {
                    app.appInputHandler.keysPressed[@intCast(key)]  = true;
                } else if (action == STATE.RELEASE.asInt()) {
                    app.appInputHandler.keysPressed[@intCast(key)]  = false;
                    app.appInputHandler.keysReleased[@intCast(key)] = true;
                }

                return;
            }
        }
    }
};

const ma = @import("bindings//miniaudio.zig").ma;

pub const AudioDevice = struct {
    device: ma.ma_device,

    pub fn start(self: *AudioDevice) !void {
        if (ma.ma_device_start(&self.device) != ma.MA_SUCCESS) {
            return error.FailedToOpenPlaybackDevice;
        }
    }

    pub inline fn setup(
        self:         *AudioDevice,
        dataCallback: *const fn([*c]ma.ma_device, ?*anyopaque, ?*const anyopaque, ma.ma_uint32) callconv(.c) void,
        pUserData:    ?*anyopaque,
    ) !void {
        var deviceConfig = ma.ma_device_config_init(ma.ma_device_type_playback);
        deviceConfig.playback.format   = ma.ma_format_f32;
        deviceConfig.playback.channels = 2;
        deviceConfig.sampleRate        = 48000;
        deviceConfig.dataCallback      = dataCallback;
        deviceConfig.pUserData         = pUserData;

        if (ma.ma_device_init(null, &deviceConfig, &self.device) != ma.MA_SUCCESS) {
            return error.FailedToOpenPlaybackDevice;
        }
    }

    pub fn deinit(self: *AudioDevice) void {
        ma.ma_device_uninit(&self.device);
    }
};

const std     = @import("std");
const builtin = @import("builtin");

pub fn getTimeInSeconds() f64 {
    return @as(f64, @floatFromInt(std.time.nanoTimestamp())) / std.time.ns_per_s;
}

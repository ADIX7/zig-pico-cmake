const std = @import("std");

pub const pico_sdk = @import("src/picosdk.zig");

pub fn build(b: *std.Build) !void {
    // expose pico_sdk as a normal zig pkg through addModule
    _ = b.addModule("pico_sdk", .{
        .root_source_file = b.path("src/picosdk.zig"),
    });
}

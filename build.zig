const std = @import("std");
const pico = @import("src/picosdk.zig");

const proj_name = "blink";

// supported board: pico, pico_w, pico2, pico2_w
const board_name = "pico2_w";
// supported pico platform: rp2040, rp2350-arm-s, rp2350-riscv
const pico_platform = "rp2350-arm-s";

pub fn build(b: *std.Build) anyerror!void {
    const stdio_type = .usb;
    const cwy43_arch = .threadsafe_background;
    const board = try pico.getBoardConfig(board_name, pico_platform, stdio_type, cwy43_arch);

    const target = try pico.getCrossTarget(pico_platform);
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addObject(.{
        .name = "zig-pico",
        .root_source_file = b.path("src/main.zig"),
        .target = std.Build.resolveTargetQuery(b, target),
        .optimize = optimize,
    });

    const option = .{
        .app_name = comptime proj_name,
        .app_lib = lib,
        .board = board,
    };

    b.default_step = try pico.addPicoApp(b, option);
}

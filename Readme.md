# zig-pico-cmake
A standalone zig package for building Raspberry Pi Pico applications using the Raspberry Pi Pico's pico-sdk. Use the zig build command to generate a flashable uf2 file.

## install
Use zig fetch command to install this zig package.
```bash
zig fetch --save "git+https://github.com/flyfish30/zig-pico-cmake.git"
```
Or use build.zig.zon file to install this package, add url of this package into dependencies in build.zig.zon file. The relative code as bellow:
```zig
    .dependencies = .{
        .pico_sdk = .{
            .url = "git+https://github.com/flyfish30/zig-pico-cmake.git",
            .hash = "12205f264d4c80458d720071b88a3af6202e342783df0499896290a87f904467f4af",
        },
    },
```
## sample project
The current sample project is in directory samples/blink, this is a blink example.
This sample project's configuration is for the Pico W and this is basically the Pico W blink example. You can modify the variable board_name and pico_platform at the top of build.zig for other pico board.

## How to build a pico application
Create a new directory for your new pico application, copy samples/blink/build.zig file of sample project to this directory, modify some variables for your project such as proj_name, board_name, pico_platform, etc. Modify variable root_source_file to your top zig file, or custom your build step of lib.
The sample file of build.zig is in bellow:
```zig
const std = @import("std");
const pico = @import("pico_sdk").pico_sdk;

// Modify proj_name for your project name
const proj_name = "blink";

// supported board: pico, pico_w, pico2, pico2_w
// Modify board_name for your board
const board_name = "pico2_w";
// supported pico platform: rp2040, rp2350-arm-s, rp2350-riscv
// Modify pico_platform for select arm or risc-v, but the risc-v is not supported.
const pico_platform = "rp2350-arm-s";

pub fn build(b: *std.Build) anyerror!void {
    const stdio_type = .usb;
    const cwy43_arch = .threadsafe_background;
    const board = try pico.getBoardConfig(board_name, pico_platform, stdio_type, cwy43_arch);

    const target = try pico.getCrossTarget(pico_platform);
    const optimize = b.standardOptimizeOption(.{});

    // Modify to addStaticLibrary for large project
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

    std.log.info("Begin build app\n", .{});
    b.default_step = try pico.addPicoApp(b, option);
}
```

Add a build.zig.zon file, add url of zig-pico-cmake to dependencies.

Copy samples/blink/setup_pico_app.sh to this directory, and run this file by bellow command.
```bash
. setup_pico_app.sh -p 12205f264d4c80458d720071b88a3af6202e342783df0499896290a87f904467f4af
```

Build a pico application by bellow command.
```bash
zig build
```
Or bellow command for release.
```bash
zig build --release=fast
```

## guide for CMakeLists.txt
Like in the C Version, you need to adjust the linked libraries in the CMakeLists.txt.

To build this example with the regular non-W Pico, remove the `pico_cyw43_arch_none` library from CMakeLists and rewrite `main.zig` to not use the W-specific cyw43 functions.

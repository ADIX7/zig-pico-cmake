const std = @import("std");
const builtin = @import("builtin");

const Board = "pico2_w";
const PicoPlatform = "rp2350-arm-s";

const SocType = enum {
    RP2040,
    RP2350,
};

const PicoSoc = if (std.mem.eql(u8, Board, "pico") or
    std.mem.eql(u8, Board, "pico_w"))
    .RP2040
else if (std.mem.eql(u8, Board, "pico2") or
    std.mem.eql(u8, Board, "pico2_w"))
    .RP2350
else
    @compileError("Can not support board: " ++ Board);

const soc_exclude_dirs = dirs_blk: {
    const fields = std.meta.fields(SocType);
    var dirs: [fields.len - 1][]const u8 = undefined;
    var i = 0;
    for (fields) |field| {
        if (@as(SocType, @enumFromInt(field.value)) == PicoSoc) {
            continue;
        }
        dirs[i] = field.name ++ "/";
        i += 1;
    }
    break :dirs_blk dirs;
};

fn isContainExcludeDir(path: []const u8, exclude_dirs: [][]const u8) bool {
    var lower_dir: [100]u8 = undefined;
    _ = &lower_dir;
    for (exclude_dirs) |dir| {
        const lower_exclude = std.ascii.lowerString(&lower_dir, dir);
        if (std.mem.startsWith(u8, path, lower_exclude)) {
            std.debug.print("exclude path: {s}\n", .{path});
            return true;
        }
    }
    return false;
}

// RP2040 -- This includes a specific header file.
const IsPicoSoc = if ((PicoSoc == .RP2040) or (PicoSoc == .RP2350)) true else false;

// Choose whether Stdio goes to USB or UART
const StdioUsb = true;
const PicoSocDefine = switch (PicoSoc) {
    .RP2040 => "PICO_RP2040",
    .RP2350 => "PICO_RP2350",
    else => @compileError("Can not support pico cpu: " ++ @tagName(PicoSoc)),
};

const PicoStdlibDefine = if (StdioUsb) "LIB_PICO_STDIO_USB" else "LIB_PICO_STDIO_UART";

// Pico SDK path can be specified here for your convenience
const PicoSDKPath: ?[]const u8 = null;

// arm-none-eabi toolchain path may be specified here as well
const ARMNoneEabiPath: ?[]const u8 = null;

pub fn build(b: *std.Build) anyerror!void {
    const host_os_tag = builtin.target.os.tag;

    // get cpu model and set cross target
    const cpu_model = switch (PicoSoc) {
        .RP2040 => &std.Target.arm.cpu.cortex_m0plus,
        .RP2350 => &std.Target.arm.cpu.cortex_m33,
        else => @compileError("Can not support pico cpu: " ++ @tagName(PicoSoc)),
    };
    const target = std.zig.CrossTarget{
        .abi = .eabi,
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = cpu_model },
        .os_tag = .freestanding,
    };

    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addObject(.{
        .name = "zig-pico",
        .root_source_file = b.path("src/main.zig"),
        .target = std.Build.resolveTargetQuery(b, target),
        .optimize = optimize,
    });

    // get and perform basic verification on the pico sdk path
    // if the sdk path contains the pico_sdk_init.cmake file then we know its correct
    const pico_sdk_path =
        if (PicoSDKPath) |sdk_path| sdk_path else std.process.getEnvVarOwned(b.allocator, "PICO_SDK_PATH") catch null orelse {
        std.log.err("The Pico SDK path must be set either through the PICO_SDK_PATH environment variable or at the top of build.zig.", .{});
        return;
    };

    const pico_init_cmake_path = b.pathJoin(&.{ pico_sdk_path, "pico_sdk_init.cmake" });
    std.fs.cwd().access(pico_init_cmake_path, .{}) catch {
        std.log.err(
            \\Provided Pico SDK path does not contain the file pico_sdk_init.cmake
            \\Tried: {s}
            \\Are you sure you entered the path correctly?"
        , .{pico_init_cmake_path});
        return;
    };

    // default arm-none-eabi includes
    lib.linkLibC();

    // Standard libary headers may be in different locations on different platforms
    const arm_header_location = blk: {
        if (ARMNoneEabiPath) |path| {
            break :blk path;
        }

        if (std.process.getEnvVarOwned(b.allocator, "ARM_NONE_EABI_PATH") catch null) |path| {
            break :blk path;
        }

        const unix_path = switch (host_os_tag) {
            .linux => "/usr/arm-none-eabi/include",
            .macos => "/Applications/ArmGNUToolchain/14.2.rel1/arm-none-eabi/arm-none-eabi/include",
            else => @compileError("Only support the host os is linux or macOS"),
        };
        if (std.fs.accessAbsolute(unix_path, .{})) |_| {
            break :blk unix_path;
        } else |err| err catch {};

        break :blk error.StandardHeaderLocationNotSpecified;
    } catch |err| {
        err catch {};
        std.log.err(
            \\Could not determine ARM Toolchain include directory.
            \\Please set the ARM_NONE_EABI_PATH environment variable with the correct path
            \\or set the ARMNoneEabiPath variable at the top of build.zig 
        , .{});
        return;
    };
    lib.addSystemIncludePath(.{ .cwd_relative = arm_header_location });

    // find the board header
    const board_header = blk: {
        const boards_directory_path = b.pathJoin(&.{ pico_sdk_path, "src/boards/include/boards/" });
        var boards_dir = try std.fs.cwd().openDir(boards_directory_path, .{});
        defer boards_dir.close();

        var it = boards_dir.iterate();
        while (try it.next()) |file| {
            if (std.mem.containsAtLeast(u8, file.name, 1, Board)) {
                // found the board header
                break :blk file.name;
            }
        }
        std.log.err("Could not find the header file for board '{s}'\n", .{Board});
        return;
    };

    // Autogenerate the header file like the pico sdk would
    const cmsys_exception_prefix = if (IsPicoSoc) "" else "//";
    const header_str = try std.fmt.allocPrint(b.allocator,
        \\#include "{s}/src/boards/include/boards/{s}"
        \\{s}#include "{s}/src/rp2_common/cmsis/include/cmsis/rename_exceptions.h"
    , .{ pico_sdk_path, board_header, cmsys_exception_prefix, pico_sdk_path });

    // Write and include the generated header
    const config_autogen_step = b.addWriteFile("pico/config_autogen.h", header_str);
    lib.step.dependOn(&config_autogen_step.step);
    lib.addIncludePath(config_autogen_step.getDirectory());
    // Define cpu type of pico
    lib.root_module.addCMacro("PICO_BOARD", Board);
    lib.root_module.addCMacro("PICO_PLATFORM", PicoPlatform);
    lib.root_module.addCMacro(PicoSocDefine, "1");

    // requires running cmake at least once
    lib.addSystemIncludePath(b.path("build/generated/pico_base"));

    // PICO SDK includes
    // Find all folders called include in the Pico SDK
    {
        const pico_sdk_src = try std.fmt.allocPrint(b.allocator, "{s}/src", .{pico_sdk_path});
        var dir = try std.fs.cwd().openDir(pico_sdk_src, .{
            .no_follow = true,
        });
        var walker = try dir.walk(b.allocator);
        defer walker.deinit();
        while (try walker.next()) |entry| {
            if (std.mem.eql(u8, entry.basename, "include")) {
                if (!(std.mem.containsAtLeast(u8, entry.path, 1, "host") or
                    isContainExcludeDir(entry.path, @constCast(&soc_exclude_dirs))))
                {
                    const pico_sdk_include = try std.fmt.allocPrint(b.allocator, "{s}/src/{s}", .{ pico_sdk_path, entry.path });
                    lib.addIncludePath(.{ .cwd_relative = pico_sdk_include });
                }
            }
        }
    }

    // Define UART or USB constant for headers
    lib.root_module.addCMacro(PicoStdlibDefine, "1");

    // required for pico_w wifi
    lib.root_module.addCMacro("PICO_CYW43_ARCH_THREADSAFE_BACKGROUND", "1");
    const cyw43_include = try std.fmt.allocPrint(b.allocator, "{s}/lib/cyw43-driver/src", .{pico_sdk_path});
    lib.addIncludePath(.{ .cwd_relative = cyw43_include });

    // required by cyw43
    const lwip_include = try std.fmt.allocPrint(b.allocator, "{s}/lib/lwip/src/include", .{pico_sdk_path});
    lib.addIncludePath(.{ .cwd_relative = lwip_include });

    // options headers
    lib.addIncludePath(b.path("config/"));

    const compiled = lib.getEmittedBin();
    const install_step = b.addInstallFile(compiled, "mlem.o");
    install_step.step.dependOn(&lib.step);

    // create build directory
    if (std.fs.cwd().makeDir("build")) |_| {} else |err| {
        if (err != error.PathAlreadyExists) return err;
    }

    const uart_or_usb = if (StdioUsb) "-DSTDIO_USB=1" else "-DSTDIO_UART=1";
    const cmake_pico_sdk_path = b.fmt("-DPICO_SDK_PATH={s}", .{pico_sdk_path});
    const cmake_argv = [_][]const u8{
        "cmake", "-B", "./build", "-S .", cmake_pico_sdk_path, uart_or_usb, "-DPICO_BOARD=" ++ Board, "-DPICO_PLATFORM=" ++ PicoPlatform,
    };
    const cmake_step = b.addSystemCommand(&cmake_argv);
    cmake_step.step.dependOn(&install_step.step);

    const make_argv = [_][]const u8{ "cmake", "--build", "./build", "--parallel" };
    const make_step = b.addSystemCommand(&make_argv);
    make_step.step.dependOn(&cmake_step.step);

    const uf2_create_step = b.addInstallFile(b.path("build/mlem.uf2"), "firmware.uf2");
    uf2_create_step.step.dependOn(&make_step.step);

    const uf2_step = b.step("uf2", "Create firmware.uf2");
    uf2_step.dependOn(&uf2_create_step.step);
    b.default_step = uf2_step;
}

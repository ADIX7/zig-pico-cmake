const std = @import("std");
const builtin = @import("builtin");

pub const PicoConfig = struct {
    // supported board: pico, pico_w, pico2, pico2_w
    board_name: []const u8,
    // supported pico platform: rp2040, rp2350-arm-s, rp2350-riscv
    pico_platform: []const u8,
    // stdio use usb or uart
    stdio_type: StdioType,
};

pub const PicowConfig = struct {
    // supported board: pico, pico_w, pico2, pico2_w
    board_name: []const u8,
    // supported pico platform: rp2040, rp2350-arm-s, rp2350-riscv
    pico_platform: []const u8,
    // stdio use usb or uart
    stdio_type: StdioType,
    cyw43_arch: Cyw43ArchType,
};

const BoardType = enum {
    PICO,
    PICO_W,
    PICO2,
    PICO2_W,
};

pub const Board = union(enum) {
    pico: PicoConfig,
    pico_w: PicowConfig,
    pico2: PicoConfig,
    pico2_w: PicowConfig,
};

pub const SocType = enum {
    RP2040,
    RP2350,
};

pub const Cyw43ArchType = enum {
    threadsafe_background,
    poll,
};

pub const StdioType = enum {
    uart,
    usb,
};

/// The options for build pico app by Zig
pub const PicoAppOption = struct {
    /// application name
    app_name: []const u8,
    /// the step for compile zig files of application
    app_lib: *std.Build.Step.Compile,
    /// board information
    board: Board,
    /// additional pico-sdk libs should be linked into application
    /// the name of library is seprated by ";", for example "pico_lib_aa;pico_lib_bb".
    pico_libs: []const u8,
};

fn isContainExcludeDir(path: []const u8, exclude_dirs: [][]const u8) bool {
    var lower_dir: [100]u8 = undefined;
    _ = &lower_dir;
    for (exclude_dirs) |dir| {
        const lower_exclude = std.ascii.lowerString(&lower_dir, dir);
        if (std.mem.startsWith(u8, path, lower_exclude)) {
            return true;
        }
    }
    return false;
}

pub fn getBoardConfig(board_name: []const u8, pico_platform: []const u8, stdio_type: StdioType, cyw43_arch: Cyw43ArchType) !Board {
    if (std.mem.eql(u8, board_name, "pico")) {
        if (!std.mem.eql(u8, pico_platform, "rp2040")) {
            std.log.err("Invalid input pico_platform: {s}", .{pico_platform});
            return error.InvalidInput;
        }
        return .{
            .pico = PicoConfig{
                .board_name = board_name,
                .pico_platform = pico_platform,
                .stdio_type = stdio_type,
            },
        };
    } else if (std.mem.eql(u8, board_name, "pico_w")) {
        if (!std.mem.eql(u8, pico_platform, "rp2040")) {
            std.log.err("Invalid input pico_platform: {s}", .{pico_platform});
            return error.InvalidInput;
        }
        return .{
            .pico_w = PicowConfig{
                .board_name = board_name,
                .pico_platform = pico_platform,
                .stdio_type = stdio_type,
                .cyw43_arch = cyw43_arch,
            },
        };
    } else if (std.mem.eql(u8, board_name, "pico2")) {
        if (!std.mem.startsWith(u8, pico_platform, "rp2350")) {
            std.log.err("Invalid input pico_platform: {s}", .{pico_platform});
            return error.InvalidInput;
        }
        return .{
            .pico2 = PicoConfig{
                .board_name = board_name,
                .pico_platform = pico_platform,
                .stdio_type = stdio_type,
            },
        };
    } else if (std.mem.eql(u8, board_name, "pico2_w")) {
        if (!std.mem.startsWith(u8, pico_platform, "rp2350")) {
            std.log.err("Invalid input pico_platform: {s}", .{pico_platform});
            return error.InvalidInput;
        }
        return .{
            .pico2_w = PicowConfig{
                .board_name = board_name,
                .pico_platform = pico_platform,
                .stdio_type = stdio_type,
                .cyw43_arch = cyw43_arch,
            },
        };
    } else {
        std.log.err("Can not support board: {s}", .{board_name});
        return error.NotSupported;
    }
}

pub fn getCrossTarget(platform: []const u8) !std.Target.Query {
    const cpu_model = if (std.mem.eql(u8, platform, "rp2040"))
        &std.Target.arm.cpu.cortex_m0plus
    else if (std.mem.eql(u8, platform, "rp2350-arm-s"))
        &std.Target.arm.cpu.cortex_m33
    else if (std.mem.eql(u8, platform, "rp2350-riscv")) {
        // TODO: add support riscv cpu
        std.log.err("Can not support pico platform: rp2350-riscv", .{});
        return error.NotSupported;
    } else {
        std.log.err("Can not support pico platform: {s}", .{platform});
        return error.NotSupported;
    };
    return std.zig.CrossTarget{
        .abi = .eabi,
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = cpu_model },
        .os_tag = .freestanding,
    };
}

// Pico SDK path can be specified here for your convenience
const PicoSDKPath: ?[]const u8 = null;

// arm-none-eabi toolchain path may be specified here as well
const ARMNoneEabiPath: ?[]const u8 = null;

fn getSocExcludeDirs(comptime pico_soc: SocType) [std.meta.fields(SocType).len - 1][]const u8 {
    const fields = std.meta.fields(SocType);
    var dirs: [fields.len - 1][]const u8 = undefined;
    comptime var i = 0;
    inline for (fields) |field| {
        if (@as(SocType, @enumFromInt(field.value)) == pico_soc) {
            continue;
        }
        dirs[i] = field.name ++ "/";
        i += 1;
    }
    return dirs;
}

pub fn addPicoApp(b: *std.Build, option: PicoAppOption) !*std.Build.Step {
    const host_os_tag = builtin.target.os.tag;
    const app_lib = option.app_lib;
    const board_name, const pico_platform = switch (option.board) {
        .pico, .pico2 => |board| .{ board.board_name, board.pico_platform },
        .pico_w, .pico2_w => |board| .{ board.board_name, board.pico_platform },
    };
    const has_wifi, const cyw43_arch = switch (option.board) {
        .pico, .pico2 => .{ false, null },
        .pico_w, .pico2_w => |board| .{ true, board.cyw43_arch },
    };
    const soc_exclude_dirs = switch (option.board) {
        .pico, .pico_w => getSocExcludeDirs(.RP2040),
        .pico2, .pico2_w => getSocExcludeDirs(.RP2350),
    };

    // Check if is pico soc: RP2040 or RP2350 -- This includes a specific header file.
    const IsPicoSoc = true;

    // Choose whether Stdio goes to USB or UART
    const StdioUsb = true;
    const PicoSocDefine = switch (option.board) {
        .pico, .pico_w => "PICO_RP2040",
        .pico2, .pico2_w => "PICO_RP2350",
    };

    const PicoStdlibDefine = if (StdioUsb) "LIB_PICO_STDIO_USB" else "LIB_PICO_STDIO_UART";

    // get and perform basic verification on the pico sdk path
    // if the sdk path contains the pico_sdk_init.cmake file then we know its correct
    const pico_sdk_path = if (PicoSDKPath) |sdk_path|
        sdk_path
    else
        std.process.getEnvVarOwned(b.allocator, "PICO_SDK_PATH") catch null orelse {
            std.log.err("The Pico SDK path must be set either through the PICO_SDK_PATH environment variable or at the top of build.zig.", .{});
            return error.NoPicoSdkPath;
        };

    const pico_init_cmake_path = b.pathJoin(&.{ pico_sdk_path, "pico_sdk_init.cmake" });
    std.fs.cwd().access(pico_init_cmake_path, .{}) catch {
        std.log.err(
            \\Provided Pico SDK path does not contain the file pico_sdk_init.cmake
            \\Tried: {s}
            \\Are you sure you entered the path correctly?
        , .{pico_init_cmake_path});
        return error.InvlidPicoSdkPath;
    };

    // default arm-none-eabi includes
    app_lib.linkLibC();

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
        std.log.err(
            \\Could not determine ARM Toolchain include directory.
            \\Please set the ARM_NONE_EABI_PATH environment variable with the correct path
            \\or set the ARMNoneEabiPath variable at the top of build.zig 
        , .{});
        return err;
    };
    app_lib.addSystemIncludePath(.{ .cwd_relative = arm_header_location });

    // find the board header
    const board_header = blk: {
        const boards_directory_path = b.pathJoin(&.{ pico_sdk_path, "src/boards/include/boards/" });
        var boards_dir = try std.fs.cwd().openDir(boards_directory_path, .{});
        defer boards_dir.close();

        var it = boards_dir.iterate();
        while (try it.next()) |file| {
            if (std.mem.containsAtLeast(u8, file.name, 1, board_name)) {
                // found the board header
                break :blk file.name;
            }
        }
        std.log.err("Could not find the header file for board '{s}'\n", .{board_name});
        return error.InvalidPicoBoard;
    };

    // Autogenerate the header file like the pico sdk would
    const cmsys_exception_prefix = if (IsPicoSoc) "" else "//";
    const header_str = try std.fmt.allocPrint(b.allocator,
        \\#include "{s}/src/boards/include/boards/{s}"
        \\{s}#include "{s}/src/rp2_common/cmsis/include/cmsis/rename_exceptions.h"
    , .{ pico_sdk_path, board_header, cmsys_exception_prefix, pico_sdk_path });

    // Write and include the generated header
    const config_autogen_step = b.addWriteFile("pico/config_autogen.h", header_str);
    app_lib.step.dependOn(&config_autogen_step.step);
    app_lib.addIncludePath(config_autogen_step.getDirectory());
    // Define soc type of pico
    app_lib.root_module.addCMacro("PICO_BOARD", board_name);
    app_lib.root_module.addCMacro("PICO_PLATFORM", pico_platform);
    app_lib.root_module.addCMacro(PicoSocDefine, "1");

    // requires running cmake at least once
    app_lib.addSystemIncludePath(b.path("build/generated/pico_base"));

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
                    app_lib.addIncludePath(.{ .cwd_relative = pico_sdk_include });
                }
            }
        }
    }

    // Define UART or USB constant for headers
    app_lib.root_module.addCMacro(PicoStdlibDefine, "1");

    if (has_wifi) {
        // required for pico_w wifi
        switch (cyw43_arch.?) {
            .threadsafe_background => {
                app_lib.root_module.addCMacro("PICO_CYW43_ARCH_THREADSAFE_BACKGROUND", "1");
            },
            .poll => {
                app_lib.root_module.addCMacro("PICO_CYW43_ARCH_POLL", "1");
            },
        }
        const cyw43_include = try std.fmt.allocPrint(b.allocator, "{s}/lib/cyw43-driver/src", .{pico_sdk_path});
        app_lib.addIncludePath(.{ .cwd_relative = cyw43_include });

        // required by cyw43
        const lwip_include = try std.fmt.allocPrint(b.allocator, "{s}/lib/lwip/src/include", .{pico_sdk_path});
        app_lib.addIncludePath(.{ .cwd_relative = lwip_include });
    }

    // options headers
    app_lib.addIncludePath(b.path("config/"));

    var zig_lib_buf: [64]u8 = undefined;
    _ = &zig_lib_buf;
    const zig_lib_str = try std.fmt.bufPrint(&zig_lib_buf, "{s}.a", .{option.app_name});
    const compiled = app_lib.getEmittedBin();
    const install_step = b.addInstallFile(compiled, zig_lib_str);
    install_step.step.dependOn(&app_lib.step);

    // create build directory
    if (std.fs.cwd().makeDir("build")) |_| {} else |err| {
        if (err != error.PathAlreadyExists) return err;
    }

    const board_def_str = try std.fmt.allocPrint(b.allocator, "-DPICO_BOARD={s}", .{board_name});
    defer b.allocator.free(board_def_str);
    const platform_def_str = try std.fmt.allocPrint(b.allocator, "-DPICO_PLATFORM={s}", .{pico_platform});
    defer b.allocator.free(platform_def_str);
    const proj_name_str = try std.fmt.allocPrint(b.allocator, "-DPROJ_NAME={s}", .{option.app_name});
    defer b.allocator.free(proj_name_str);
    const uart_or_usb = if (StdioUsb) "-DSTDIO_USB=1" else "-DSTDIO_UART=1";
    const cmake_pico_sdk_path = b.fmt("-DPICO_SDK_PATH={s}", .{pico_sdk_path});
    const app_pico_libs_def = if (has_wifi)
        try std.fmt.allocPrint(b.allocator, "-DAPP_PICO_LIBS=pico_stdlib;pico_cyw43_arch_none;{s}", .{option.pico_libs})
    else
        try std.fmt.allocPrint(b.allocator, "-DAPP_PICO_LIBS=pico_stdlib;{s}", .{option.pico_libs});
    defer b.allocator.free(app_pico_libs_def);
    const cmake_argv = [_][]const u8{
        "cmake", "-B", "./build", "-S .", proj_name_str, cmake_pico_sdk_path, uart_or_usb, board_def_str, platform_def_str, app_pico_libs_def,
    };
    const cmake_step = b.addSystemCommand(&cmake_argv);
    cmake_step.step.dependOn(&install_step.step);

    const make_argv = [_][]const u8{ "cmake", "--build", "./build", "--parallel" };
    const make_step = b.addSystemCommand(&make_argv);
    make_step.step.dependOn(&cmake_step.step);
    return &make_step.step;
}

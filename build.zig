const std     = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    std.log.info("Example for compiling shaders using the debug build option (Vulkan SDK needed): \"zig build -Dwith-shaders\" or \"zig build -Donly-shaders\"", .{});

    if (b.release_mode == .off) {
        std.log.warn("Debug build binary will not run if you don't have the Vulkan SDK installed, as it uses validation layers.", .{});
    }

    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (target.result.os.tag == .linux) {
        if (builtin.os.tag == .windows and b.release_mode != .off) {
            std.log.err("Cross-compiling from Windows to Linux in release mode is not supported. Consider using a VM or a Linux host or other.", .{});
            return;
        }
    } else if (target.result.os.tag != .windows) {
        std.log.err("Only Windows and Linux are supported.", .{});
        return;
    }

    const exe = b.addExecutable(.{
        .name        = "vulkan-pong",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target           = target,
            .optimize         = optimize,
        }),
    });
    if (b.release_mode == .any) {
        exe.root_module.strip              = true;
        exe.root_module.omit_frame_pointer = true;
        exe.root_module.dwarf_format       = null;
    }

    const isWithShaders    = b.option(bool, "with-shaders", "Compile both GLSL shaders to SPIR-V, and the program") orelse false;
    const doCompileShaders = b.option(bool, "only-shaders", "Compile GLSL shaders to SPIR-V") orelse false or isWithShaders;
    if (doCompileShaders) {
        const systemCommands = .{
            b.addSystemCommand(&.{"glslc", "shaders/shader.comp", "-o", "src/shaders/comp.spv"}),
            b.addSystemCommand(&.{"glslc", "shaders/graphics-shader.vert", "-o", "src/shaders/graphics-vert.spv"}),
            b.addSystemCommand(&.{"glslc", "shaders/graphics-shader.frag", "-o", "src/shaders/graphics-frag.spv"}),
            b.addSystemCommand(&.{"glslc", "shaders/particle-shader.vert", "-o", "src/shaders/particle-vert.spv"}),
            b.addSystemCommand(&.{"glslc", "shaders/particle-shader.frag", "-o", "src/shaders/particle-frag.spv"}),
        };

        if (isWithShaders) {
            inline for (&systemCommands) |cmd| exe.step.dependOn(&cmd.step);
        } else {
            inline for (&systemCommands) |cmd| b.default_step.dependOn(&cmd.step);
            return;
        }
    }

    b.installArtifact(exe);

    exe.root_module.addIncludePath(b.path("deps/glfw/include"));

    if (target.result.os.tag == .windows) {
        exe.root_module.linkSystemLibrary("winmm", .{});

        exe.root_module.linkSystemLibrary("gdi32", .{});

        exe.root_module.addObjectFile(b.path("deps/glfw/lib-windows/libglfw3.a"));

        exe.root_module.addIncludePath(b.path("deps/vulkan-sdk/windows/"));
        exe.root_module.addIncludePath(b.path("deps/vulkan-sdk/windows/include/vulkan/"));
        exe.root_module.addIncludePath(b.path("deps/vulkan-sdk/windows/include/"));
        exe.root_module.addLibraryPath(b.path("deps/vulkan-sdk/windows/lib"));
        exe.root_module.linkSystemLibrary("vulkan-1", .{});
    } else {
        exe.root_module.addObjectFile(b.path("deps/glfw/lib-linux/libglfw3.a"));

        exe.root_module.addIncludePath(b.path("deps/vulkan-sdk/linux/"));
        exe.root_module.addIncludePath(b.path("deps/vulkan-sdk/linux/include/vulkan/"));
        exe.root_module.addIncludePath(b.path("deps/vulkan-sdk/linux/include/"));
        exe.root_module.addLibraryPath(b.path("deps/vulkan-sdk/linux/lib"));
        exe.root_module.linkSystemLibrary("vulkan", .{});
    }

    const cglmLib = b.addLibrary(.{
        .name        = "cglm",
        .root_module = b.createModule(.{
            .target    = target,
            .optimize  = optimize,
            .link_libc = true,
        }),
    });
    cglmLib.installHeadersDirectory(b.path("libs/cglm/include"), ".", .{});
    cglmLib.root_module.addCSourceFiles(.{
        .files = &.{
            "libs/cglm/src/vec2.c",
            "libs/cglm/src/vec3.c",
            "libs/cglm/src/mat4.c",
        },
    });
    exe.root_module.linkLibrary(cglmLib);

    const miniaudioLib = b.addLibrary(.{
        .name        = "miniaudio",
        .root_module = b.createModule(.{
            .target    = target,
            .optimize  = optimize,
            .link_libc = true,
        }),
    });
    miniaudioLib.installHeadersDirectory(b.path("libs/miniaudio-0.11.23"), ".", .{});
    miniaudioLib.root_module.addCSourceFile(.{.file = b.path("libs/miniaudio-0.11.23/miniaudio.c")});
    exe.root_module.linkLibrary(miniaudioLib);
}

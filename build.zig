const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("symmetry454", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "symmetry454",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "symmetry454", .module = lib_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "sym454",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_exe.addArgs(args);

    const run_step = b.step("run", "Run the sym454 command");
    run_step.dependOn(&run_exe.step);

    const test_step = b.step("test", "Run unit tests");

    test_step.dependOn(&b.addRunArtifact(b.addTest(.{
        .root_module = lib_mod,
    })).step);

    test_step.dependOn(&b.addRunArtifact(b.addTest(.{
        .root_module = exe_mod,
    })).step);

    for ([_][]const u8{
        "src/cli/calendar.zig",
        "src/cli/convert.zig",
        "src/cli/zone.zig",
    }) |source| {
        const module = b.createModule(.{
            .root_source_file = b.path(source),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "symmetry454", .module = lib_mod },
            },
        });

        test_step.dependOn(&b.addRunArtifact(b.addTest(.{
            .root_module = module,
        })).step);
    }
}

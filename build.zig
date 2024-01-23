const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const btree_lib = b.addStaticLibrary(.{
        .target = target,
        .name = "btree.c",
        .optimize = optimize,
    });

    const root = comptime std.fs.path.dirname(@src().file) orelse ".";

    btree_lib.addCSourceFiles(.{ .files = &.{root ++ "/vendor/btree.c/btree.c"} });

    btree_lib.addIncludePath(.{ .path = root ++ "/vendor/btree.c" });

    btree_lib.linkLibC();

    b.installArtifact(btree_lib);

    const exe = b.addExecutable(.{
        .name = "1brc-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibrary(btree_lib);
    exe.addIncludePath(.{ .path = root ++ "/vendor/btree.c" });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

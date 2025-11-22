const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const server = b.addExecutable(.{
        .name = "liver",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link CoreServices on macOS for file watching
    if (target.result.os.tag == .macos) {
        server.linkFramework("CoreServices");
    }

    b.installArtifact(server);

    // Install man page
    const man_page = b.addInstallFile(b.path("src/liver.1"), "bin/liver.1");
    b.getInstallStep().dependOn(&man_page.step);

    // Run command
    const run_cmd = b.addRunArtifact(server);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the server");
    run_step.dependOn(&run_cmd.step);
}

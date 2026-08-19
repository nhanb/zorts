const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zorts", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "zorts",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zorts", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    switch (target.result.os.tag) {
        .windows => {
            const dvui_dep = b.dependency("dvui", .{
                .target = target,
                .optimize = optimize,
                .backend = .dx11,
            });
            exe.root_module.addImport("dvui", dvui_dep.module("dvui_dx11"));
            // for zls:
            exe.root_module.addImport("dx11-backend", dvui_dep.module("dx11"));

            // This manifest makes hidpi work
            exe.win32_manifest = dvui_dep.path("./src/main.manifest");
            exe.subsystem = .Windows; // prevent console from showing
            exe.root_module.addWin32ResourceFile(.{ .file = b.path("resource.rc") });
        },
        else => {
            const dvui_dep = b.dependency("dvui", .{
                .target = target,
                .optimize = optimize,
                .backend = .sdl3,
            });

            // Can either link the backend ourselves:
            //const dvui_mod = dvui_dep.module("dvui");
            //const sdl3_mod = dvui_dep.module("sdl3");
            //@import("dvui").linkBackend(dvui_mod, sdl3_mod);
            //mod.addImport("dvui", dvui_mod);

            // Or use a prelinked one:
            exe.root_module.addImport("dvui", dvui_dep.module("dvui_sdl3"));
            exe.root_module.addImport("sdl-backend", dvui_dep.module("sdl3")); // for zls
        },
    }

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}

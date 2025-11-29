const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ============================================================
    // MODULE
    // ============================================================
    const ost_mod = b.addModule("ost", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ============================================================
    // COMPILE DEMO
    // ============================================================
    const demo_exe = b.addExecutable(.{
        .name = "ost-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    demo_exe.root_module.addImport("ost", ost_mod);
    b.installArtifact(demo_exe);
    const demo_asm_install = b.addInstallBinFile(
        demo_exe.getEmittedAsm(),
        "ost-demo.s", // ASM TO CHECK IF WE CAN REDUCE THE OVERHEAD
    );
    b.getInstallStep().dependOn(&demo_asm_install.step);

    const run_demo = b.addRunArtifact(demo_exe);
    run_demo.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_demo.addArgs(args);
    }
    const demo_step = b.step("demo", "Run the demo");
    demo_step.dependOn(&run_demo.step);

    // ============================================================
    // COMPILE BENCHMARK
    // ============================================================
    const bench_exe = b.addExecutable(.{
        .name = "benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/main.zig"),
            .target = target,
            .optimize = .ReleaseFast, // Always use ReleaseFast for benchmarks
        }),
    });
    bench_exe.root_module.addImport("ost", ost_mod);
    b.installArtifact(bench_exe);

    const run_bench = b.addRunArtifact(bench_exe);
    run_bench.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_bench.addArgs(args);
    }
    const bench_step = b.step("bench", "Run benchmarks (always ReleaseFast)");
    bench_step.dependOn(&run_bench.step);

    // ============================================================
    // TESTS
    // ============================================================
    // Library-internal tests in src/root.zig
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    // External tests in src/tests.zig (imports ost)
    const exe_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe_tests.root_module.addImport("ost", ost_mod);
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}

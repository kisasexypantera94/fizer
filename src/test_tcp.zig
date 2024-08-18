const std = @import("std");
const Scheduler = @import("scheduler.zig").Scheduler;
const Fiber = @import("fiber.zig").Fiber;
const xev = @import("xev");
const TcpConnection = @import("tcp_connection.zig").TcpConnection;
const tcp_connect = @import("tcp_connection.zig").tcp_connect;

test "tcp" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var scheduler = Scheduler.new();

    var thread_pool = xev.ThreadPool.init(.{});
    defer thread_pool.deinit();
    defer thread_pool.shutdown();

    var loop = try xev.Loop.init(.{
        .entries = std.math.pow(u13, 2, 12),
        .thread_pool = &thread_pool,
    });
    defer loop.deinit();

    var stop = false;

    const f = try Fiber.new(&allocator, struct {
        pub fn f(me: *Fiber, loop_: *xev.Loop, stop_: *bool) !void {
            std.debug.print("Connecting\n", .{});
            var conn = try TcpConnection.connect(loop_, me);
            std.debug.print("Connected!\n", .{});

            std.debug.print("Writing\n", .{});
            conn.write(&[_]u8{ 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 33 }, me);
            std.debug.print("Done!\n", .{});

            stop_.* = true;
        }
    }.f, .{ &loop, &stop });

    scheduler.schedule(f);

    while (!stop) {
        try scheduler.run();
        try loop.run(xev.RunMode.no_wait);
    }
}

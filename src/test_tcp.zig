const std = @import("std");
const Scheduler = @import("scheduler.zig").Scheduler;
const Fiber = @import("fiber.zig").Fiber;
const xev = @import("xev");
const TcpConnection = @import("tcp_connection.zig").TcpConnection;

test "tcp" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var scheduler = Scheduler.new();

    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    var stop = false;

    const f = try Fiber.new(&allocator, struct {
        pub fn f(me: *Fiber, loop_: *xev.Loop, stop_: *bool) !void {
            std.debug.print("Connecting\n", .{});
            var conn = try TcpConnection.connect(loop_, me);
            std.debug.print("Connected!\n", .{});

            std.debug.print("Writing\n", .{});
            conn.write("Hello world!", me);
            std.debug.print("Done!\n", .{});

            std.debug.print("Reading\n", .{});
            var buf: [256]u8 = undefined;
            const n = conn.read(&buf, me);
            std.debug.print("Done: buf=[{s}]\n", .{buf[0..n]});

            stop_.* = true;
        }
    }.f, .{ &loop, &stop });

    scheduler.schedule(f);

    while (!stop) {
        try scheduler.run();
        try loop.run(xev.RunMode.no_wait);
    }
}

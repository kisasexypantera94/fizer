const std = @import("std");

const Fiber = @import("fiber.zig").Fiber;
const Scheduler = @import("scheduler.zig").Scheduler;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var scheduler = Scheduler.new();

    var y: i32 = 0;

    const f0 = try Fiber.new(&allocator, struct {
        pub fn f(yh: *Fiber.YieldHandle, x: i32, y_ptr: *i32) !void {
            std.debug.print("Hello from f0, x={}\n", .{x});

            std.debug.print("One\n", .{});
            try yh.yield();

            std.debug.print("Two\n", .{});
            try yh.yield();

            std.debug.print("Three\n", .{});

            y_ptr.* += 1;
        }
    }.f, .{ 123, &y });

    const f1 = try Fiber.new(&allocator, struct {
        pub fn f(yh: *Fiber.YieldHandle, x: i32, y_ptr: *i32) !void {
            std.debug.print("Hello from f1, x={}\n", .{x});

            std.debug.print("Raz\n", .{});
            try yh.yield();

            std.debug.print("Dva\n", .{});
            try yh.yield();

            std.debug.print("Tri\n", .{});

            y_ptr.* += 1;
        }
    }.f, .{ 321, &y });

    std.debug.print("Schedule\n", .{});
    scheduler.schedule(f0);
    scheduler.schedule(f1);

    std.debug.print("Run\n", .{});
    try scheduler.run();

    std.debug.print("Done, y=[{}]\n", .{y});
}

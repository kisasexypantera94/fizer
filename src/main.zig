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

    const f0 = try Fiber.new(&allocator, struct {
        pub fn f(yh: *Fiber.YieldHandle) void {
            std.debug.print("One\n", .{});
            yh.yield();
            std.debug.print("Two\n", .{});
            yh.yield();
            std.debug.print("Three\n", .{});
        }
    }.f);

    const f1 = try Fiber.new(&allocator, struct {
        pub fn f(yh: *Fiber.YieldHandle) void {
            std.debug.print("Raz\n", .{});
            yh.yield();
            std.debug.print("Dva\n", .{});
            yh.yield();
            std.debug.print("Tri\n", .{});
        }
    }.f);

    std.debug.print("Schedule\n", .{});
    scheduler.schedule(f0);
    scheduler.schedule(f1);

    scheduler.run();

    std.debug.print("Oplya\n", .{});
}

const std = @import("std");
const Scheduler = @import("scheduler.zig").Scheduler;
const Fiber = @import("fiber.zig").Fiber;
const Strand = @import("strand.zig").Strand;

fn runScheduler(scheduler: *Scheduler) void {
    std.debug.print("Run\n", .{});

    const start = std.time.nanoTimestamp();
    scheduler.run() catch {};
    const end = std.time.nanoTimestamp();

    std.debug.print("Done, elapsed=[{}]\n", .{@divTrunc(end - start, std.time.ns_per_us)});
}

test "multithreaded" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var scheduler0 = Scheduler.new();
    var scheduler1 = Scheduler.new();
    var schedulers = [_]*Scheduler{ &scheduler0, &scheduler1 };

    var strand = Strand.new(&schedulers);

    var y: i32 = 0;

    const f0 = try Fiber.new(&allocator, struct {
        pub fn f(me: *Fiber, x: i32, y_ptr: *i32) !void {
            std.debug.print("Hello from f0, x={}\n", .{x});

            std.debug.print("One\n", .{});
            me.yield();

            std.debug.print("Two\n", .{});
            me.yield();

            std.debug.print("Three\n", .{});

            y_ptr.* += 1;
        }
    }.f, .{ 123, &y });

    const f1 = try Fiber.new(&allocator, struct {
        pub fn f(me: *Fiber, x: i32, y_ptr: *i32, strand_: *Strand) !void {
            std.debug.print("Hello from f1, x={}\n", .{x});

            std.debug.print("Raz\n", .{});

            {
                var uh = strand_.lock(me);
                defer uh.unlock();

                std.debug.print("Dva\n", .{});
                me.yield();
            }

            std.debug.print("Tri\n", .{});

            y_ptr.* += 1;
        }
    }.f, .{ 321, &y, &strand });

    std.debug.print("Schedule\n", .{});
    scheduler0.schedule(f0);
    scheduler0.schedule(f1);

    var thread0 = try std.Thread.spawn(.{}, runScheduler, .{&scheduler0});
    thread0.join();

    var thread1 = try std.Thread.spawn(.{}, runScheduler, .{&scheduler1});
    thread1.join();
}

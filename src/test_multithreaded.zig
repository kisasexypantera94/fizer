const std = @import("std");
const Scheduler = @import("scheduler.zig").Scheduler;
const Fiber = @import("fiber.zig").Fiber;
const Strand = @import("strand.zig").Strand;
const AtomicOrder = @import("std").builtin.AtomicOrder;
const AtomicRmwOp = @import("std").builtin.AtomicRmwOp;

fn runScheduler(scheduler: *Scheduler, cnt: *i32) void {
    while (@atomicLoad(i32, cnt, AtomicOrder.seq_cst) > 0) {
        scheduler.run() catch {};
    }
}

test "multithreaded" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    const schedulers = try allocator.alloc(Scheduler, try std.Thread.getCpuCount());
    defer allocator.free(schedulers);

    for (schedulers) |*s| {
        s.* = Scheduler.new();
    }

    const num_iters = 1e5;
    var strand = Strand.new(schedulers);
    var y: i32 = 0;
    var cnt: i32 = 2;

    var common = .{
        .strand = &strand,
        .y = &y,
        .cnt = &cnt,
    };

    const f0 = try Fiber.new(&allocator, struct {
        pub fn f(me: *Fiber, common_: *@TypeOf(common)) !void {
            defer _ = @atomicRmw(i32, common_.cnt, AtomicRmwOp.Sub, 1, AtomicOrder.seq_cst);

            for (0..num_iters) |_| {
                var uh = common_.strand.lock(me);
                defer uh.unlock();

                common_.y.* += 1;
            }
        }
    }.f, .{&common});

    const f1 = try Fiber.new(&allocator, struct {
        pub fn f(me: *Fiber, common_: *@TypeOf(common)) !void {
            defer _ = @atomicRmw(i32, common_.cnt, AtomicRmwOp.Sub, 1, AtomicOrder.seq_cst);

            for (0..num_iters) |_| {
                var uh = common_.strand.lock(me);
                defer uh.unlock();

                common_.y.* += 1;
            }
        }
    }.f, .{&common});

    schedulers[0].schedule(f0);
    schedulers[0].schedule(f1);

    var threads = std.ArrayList(std.Thread).init(allocator);
    defer threads.clearAndFree();

    for (schedulers) |*s| {
        try threads.append(try std.Thread.spawn(.{}, runScheduler, .{ s, &cnt }));
    }

    for (threads.items) |*t| {
        t.join();
    }

    try std.testing.expect(y == num_iters * 2);
}

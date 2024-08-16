const std = @import("std");
const Scheduler = @import("scheduler.zig").Scheduler;
const Fiber = @import("fiber.zig").Fiber;
const Strand = @import("strand.zig").Strand;
const AtomicOrder = @import("std").builtin.AtomicOrder;
const AtomicRmwOp = @import("std").builtin.AtomicRmwOp;

fn runScheduler(scheduler: *Scheduler, cnt: *usize) void {
    while (@atomicLoad(usize, cnt, AtomicOrder.seq_cst) > 0) {
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

    const num_iters: usize = 1e3;
    var strand = Strand.new(schedulers);
    var y: usize = 0;
    const num_fibers: usize = 1e3;
    var cnt: usize = num_fibers;

    var common = .{
        .strand = &strand,
        .y = &y,
        .cnt = &cnt,
    };

    const routine = struct {
        pub fn f(me: *Fiber, common_: *@TypeOf(common)) !void {
            defer _ = @atomicRmw(usize, common_.cnt, AtomicRmwOp.Sub, 1, AtomicOrder.seq_cst);

            for (0..num_iters) |_| {
                var uh = common_.strand.lock(me);
                defer uh.unlock();

                common_.y.* += 1;
            }
        }
    }.f;

    const fibers = try allocator.alloc(*Fiber, num_fibers);
    defer allocator.free(fibers);

    for (fibers) |*f| {
        f.* = try Fiber.new(&allocator, routine, .{&common});
        schedulers[0].schedule(f.*);
    }

    var threads = std.ArrayList(std.Thread).init(allocator);
    defer threads.clearAndFree();

    for (schedulers) |*s| {
        try threads.append(try std.Thread.spawn(.{}, runScheduler, .{ s, &cnt }));
    }

    for (threads.items) |*t| {
        t.join();
    }

    std.debug.print("Y=[{}]\n", .{y});

    try std.testing.expect(y == num_iters * num_fibers);
}

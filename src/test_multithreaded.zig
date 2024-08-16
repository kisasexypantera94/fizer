const std = @import("std");
const Scheduler = @import("scheduler.zig").Scheduler;
const Fiber = @import("fiber.zig").Fiber;
const Strand = @import("strand.zig").Strand;
const AtomicOrder = @import("std").builtin.AtomicOrder;
const AtomicRmwOp = @import("std").builtin.AtomicRmwOp;
const WaitGroup = @import("std").Thread.WaitGroup;

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

    var scheduler0 = Scheduler.new();
    var scheduler1 = Scheduler.new();
    var schedulers = [_]*Scheduler{ &scheduler0, &scheduler1 };

    var strand = Strand.new(&schedulers);

    const num_iters = 16384;
    var x0: i32 = 0;
    var x1: i32 = 0;
    var y: i32 = 0;

    var cnt: i32 = 2;

    const f0 = try Fiber.new(&allocator, struct {
        pub fn f(me: *Fiber, x0_ptr: *i32, y_ptr: *i32, strand_: *Strand, cnt_: *i32) !void {
            defer _ = @atomicRmw(i32, cnt_, AtomicRmwOp.Sub, 1, AtomicOrder.seq_cst);

            for (0..num_iters) |_| {
                x0_ptr.* += 1;

                {
                    var uh = strand_.lock(me);
                    defer uh.unlock();

                    y_ptr.* += 1;
                }
            }
        }
    }.f, .{ &x0, &y, &strand, &cnt });

    const f1 = try Fiber.new(&allocator, struct {
        pub fn f(me: *Fiber, x1_ptr: *i32, y_ptr: *i32, strand_: *Strand, cnt_: *i32) !void {
            defer _ = @atomicRmw(i32, cnt_, AtomicRmwOp.Sub, 1, AtomicOrder.seq_cst);

            for (0..num_iters) |_| {
                x1_ptr.* += 1;

                {
                    var uh = strand_.lock(me);
                    defer uh.unlock();

                    y_ptr.* += 1;
                }
            }
        }
    }.f, .{ &x1, &y, &strand, &cnt });

    scheduler0.schedule(f0);
    scheduler0.schedule(f1);

    var thread0 = try std.Thread.spawn(.{}, runScheduler, .{ &scheduler0, &cnt });
    var thread1 = try std.Thread.spawn(.{}, runScheduler, .{ &scheduler1, &cnt });

    thread0.join();
    thread1.join();

    try std.testing.expect(y == num_iters * 2);
}

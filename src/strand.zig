const Scheduler = @import("scheduler.zig").Scheduler;
const Fiber = @import("fiber.zig").Fiber;
const Mutex = @import("std").Thread.Mutex;
const AtomicOrder = @import("std").builtin.AtomicOrder;

pub const Strand = struct {
    schedulers: []Scheduler,
    lock_scheduler_idx: usize,
    unlock_scheduler_idx: usize,
    mtx: Mutex,
    lock_cnt: usize,
    flag: bool,

    pub fn new(schedulers: []Scheduler) Strand {
        return .{
            .schedulers = schedulers,
            .lock_scheduler_idx = 0,
            .unlock_scheduler_idx = 0,
            .mtx = Mutex{},
            .lock_cnt = 0,
            .flag = false,
        };
    }

    pub fn lock(self: *Strand, fiber: *Fiber) UnlockHandle {
        self.mtx.lock();
        const scheduler = &self.schedulers[self.lock_scheduler_idx];
        self.lock_cnt += 1;
        self.mtx.unlock();

        fiber.teleportTo(scheduler);

        _ = @atomicLoad(bool, &self.flag, AtomicOrder.acquire);

        return .{ .fiber = fiber, .strand = self };
    }

    fn unlock(self: *Strand, fiber: *Fiber) void {
        {
            self.mtx.lock();
            defer self.mtx.unlock();

            self.lock_cnt -= 1;

            if (self.lock_cnt == 0) {
                self.lock_scheduler_idx += 1;
                self.lock_scheduler_idx %= self.schedulers.len;
            }

            self.unlock_scheduler_idx += 1;
            self.unlock_scheduler_idx %= self.schedulers.len;
        }

        // Note: somehow changes made in T0 are visible in T1 even without this release-acquire ritual,
        // would be nice to investigate further
        _ = @atomicStore(bool, &self.flag, true, AtomicOrder.release);

        fiber.teleportTo(&self.schedulers[self.unlock_scheduler_idx]);
    }

    const UnlockHandle = struct {
        fiber: *Fiber,
        strand: *Strand,

        pub fn unlock(self: *UnlockHandle) void {
            self.strand.unlock(self.fiber);
        }
    };
};

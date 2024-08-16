const std = @import("std");
const Fiber = @import("fiber.zig").Fiber;
const Mutex = std.Thread.Mutex;

pub const Scheduler = struct {
    const FifoType = std.fifo.LinearFifo(*Fiber, std.fifo.LinearFifoBufferType{ .Static = 16384 });

    queue: FifoType,
    mtx: Mutex,

    pub fn new() Scheduler {
        return .{
            .queue = FifoType.init(),
            .mtx = Mutex{},
        };
    }

    pub fn run(self: *Scheduler) !void {
        while (self.queue.count > 0) {
            self.mtx.lock();
            const f_opt = self.queue.readItem();
            self.mtx.unlock();

            const f = f_opt.?;

            try f.next();

            switch (f.next_action) {
                .Reschedule => self.schedule(f),
                .Teleport => |to| to.schedule(f),
                .Destroy => f.destroy(),
            }
        }
    }

    /// Note: this transfers ownership of fiber.
    pub fn schedule(self: *Scheduler, f: *Fiber) void {
        self.mtx.lock();
        defer self.mtx.unlock();

        self.queue.writeItem(f) catch {};
    }
};

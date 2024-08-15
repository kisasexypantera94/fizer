const std = @import("std");
const Fiber = @import("fiber.zig").Fiber;

pub const Scheduler = struct {
    const FifoType = std.fifo.LinearFifo(*Fiber, std.fifo.LinearFifoBufferType{ .Static = 1024 });

    queue: FifoType,

    pub fn new() Scheduler {
        return .{
            .queue = FifoType.init(),
        };
    }

    pub fn run(self: *Scheduler) void {
        while (self.queue.count > 0) {
            const f = self.queue.readItem().?;
            f.next();

            if (f.is_completed) {
                f.destroy();
            } else {
                self.queue.writeItem(f) catch {};
            }
        }
    }

    /// Note: this transfers ownership of fiber.
    pub fn schedule(self: *Scheduler, f: *Fiber) void {
        self.queue.writeItem(f) catch {};
    }
};

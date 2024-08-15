const std = @import("std");
const ExecutionContext = @import("execution_context.zig").ExecutionContext;

const stack_size = 16384;

pub const Fiber = struct {
    allocator: *std.mem.Allocator,
    stack: [stack_size]u8,
    capture: *anyopaque,
    capture_free: *const fn (*Fiber) void,
    caller_ctx: ExecutionContext,
    ctx: ExecutionContext,
    is_completed: bool,

    pub fn new(allocator: *std.mem.Allocator, func: anytype, args: anytype) !*Fiber {
        // This way, fibers can be safely moved between threads
        var fiber = try allocator.create(Fiber);

        const trampoline = struct {
            fn f(func_lo: u32, func_hi: u32, fiber_lo: u32, fiber_hi: u32) callconv(.C) void {
                const func_: *@TypeOf(func) = @ptrFromInt(@as(usize, @bitCast([2]u32{ func_lo, func_hi })));
                const fiber_: *Fiber = @ptrFromInt(@as(usize, @bitCast([2]u32{ fiber_lo, fiber_hi })));

                const args_: *@TypeOf(args) = @ptrCast(@alignCast(fiber_.capture));

                var yieldHandle = YieldHandle{ .fiber = fiber_ };
                @call(.auto, func_, .{&yieldHandle} ++ args_.*);

                fiber_.is_completed = true;

                // I guess we can assume that the user always wants to return to the caller's ctx.
                ExecutionContext.exit(&fiber_.caller_ctx) catch {};
            }
        }.f;

        const capture = try allocator.create(@TypeOf(args));
        capture.* = args;

        fiber.allocator = allocator;
        fiber.capture = @ptrCast(capture);
        fiber.capture_free = struct {
            fn f(me: *Fiber) void {
                me.allocator.destroy(@as(*@TypeOf(args), @ptrCast(@alignCast(me.capture))));
            }
        }.f;
        fiber.stack = undefined;
        fiber.caller_ctx = undefined;
        fiber.ctx = try ExecutionContext.new(&fiber.stack, trampoline, @ptrCast(@constCast(&func)), @ptrCast(fiber));

        return fiber;
    }

    pub fn destroy(self: *Fiber) void {
        self.capture_free(self);
        self.allocator.destroy(self);
    }

    // Since 'resume' is a keyword, let's stick to an iterator-like interface.
    pub fn next(self: *Fiber) void {
        if (self.is_completed) {
            return;
        }

        self.caller_ctx.switchTo(&self.ctx) catch {};
    }

    fn yield(self: *Fiber) void {
        self.ctx.switchTo(&self.caller_ctx) catch {};
    }

    pub const YieldHandle = struct {
        fiber: *Fiber,

        pub fn yield(self: *YieldHandle) void {
            self.fiber.yield();
        }
    };
};

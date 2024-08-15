const std = @import("std");
const ExecutionContext = @import("execution_context.zig").ExecutionContext;

const stack_size = 16384;

pub const Fiber = struct {
    allocator: *std.mem.Allocator,
    stack: [stack_size]u8,
    func: *const fn (*YieldHandle) void,
    caller_ctx: ExecutionContext,
    ctx: ExecutionContext,
    is_completed: bool,

    pub fn new(allocator: *std.mem.Allocator, func: *const fn (*YieldHandle) void) !*Fiber {
        // This way, fibers can be safely moved between threads
        var self = try allocator.create(Fiber);

        self.allocator = allocator;
        self.stack = undefined;
        self.func = func;
        self.caller_ctx = undefined;
        self.ctx = try ExecutionContext.new(&self.stack, trampoline, @ptrCast(self));

        return self;
    }

    pub fn destroy(self: *Fiber) void {
        self.allocator.destroy(self);
    }

    fn trampoline(lo: u32, hi: u32) callconv(.C) void {
        const ptr_int: usize = @bitCast([2]u32{ lo, hi });
        const arg: *void = @ptrFromInt(ptr_int);

        const self: *Fiber = @ptrCast(@alignCast(arg));

        var yieldHandle = .{ .fiber = self };
        self.func(&yieldHandle);

        self.is_completed = true;

        // I guess we can assume that the user always wants to return to the caller's ctx.
        ExecutionContext.exit(&self.caller_ctx) catch {};
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

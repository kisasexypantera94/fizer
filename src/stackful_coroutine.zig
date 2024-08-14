const std = @import("std");
const ec = @import("execution_context.zig");

const stack_size = 16384;

pub const StackfulCoroutine = struct {
    allocator: *std.mem.Allocator,
    stack: [stack_size]u8,
    func: *const fn (*YieldHandle) void,
    caller_ctx: ec.ExecutionContext,
    ctx: ec.ExecutionContext,
    is_completed: bool,

    pub fn new(allocator: *std.mem.Allocator, func: *const fn (*YieldHandle) void) !*StackfulCoroutine {
        var self = try allocator.create(StackfulCoroutine);

        self.allocator = allocator;
        self.stack = undefined;
        self.func = func;
        self.caller_ctx = undefined;
        self.ctx = try ec.ExecutionContext.new(&self.stack, trampoline, @ptrCast(self));

        return self;
    }

    pub fn destroy(self: *StackfulCoroutine) void {
        self.allocator.destroy(self);
    }

    fn trampoline(lo: u32, hi: u32) callconv(.C) void {
        const ptr_int: usize = @bitCast([2]u32{ lo, hi });
        const arg: *void = @ptrFromInt(ptr_int);

        const coro: *StackfulCoroutine = @ptrCast(@alignCast(arg));

        var yieldHandler = .{ .coro = coro };
        coro.func(&yieldHandler);

        coro.is_completed = true;

        ec.ExecutionContext.exit(&coro.caller_ctx) catch {};
    }

    pub fn next(self: *StackfulCoroutine) void {
        if (self.is_completed) {
            return;
        }

        self.caller_ctx.switchTo(&self.ctx) catch {};
    }

    fn yield(self: *StackfulCoroutine) void {
        self.ctx.switchTo(&self.caller_ctx) catch {};
    }
};

pub const YieldHandle = struct {
    coro: *StackfulCoroutine,

    pub fn yield(self: @This()) void {
        self.coro.yield();
    }
};

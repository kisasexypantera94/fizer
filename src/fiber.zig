const std = @import("std");
const ExecutionContext = @import("execution_context.zig").ExecutionContext;
const Scheduler = @import("scheduler.zig").Scheduler;

const stack_size = 16384;

pub const Fiber = struct {
    allocator: *std.mem.Allocator,

    stack: [stack_size]u8,
    caller_ctx: ExecutionContext,
    ctx: ExecutionContext,

    capture: *anyopaque,
    capture_free: *const fn (*Fiber) void,

    after_yield_func: *const fn (*Fiber, *Scheduler, *anyopaque) void,
    after_yield_capture: *anyopaque,

    pub fn new(allocator: *std.mem.Allocator, func: anytype, args: anytype) !*Fiber {
        const FuncType = @TypeOf(func);
        const ArgsType = @TypeOf(args);

        const trampoline = struct {
            fn f(func_lo: u32, func_hi: u32, fiber_lo: u32, fiber_hi: u32) callconv(.C) void {
                const func_: *const FuncType = @ptrFromInt(@as(usize, @bitCast([2]u32{ func_lo, func_hi })));
                const fiber_: *Fiber = @ptrFromInt(@as(usize, @bitCast([2]u32{ fiber_lo, fiber_hi })));

                const args_: *ArgsType = @ptrCast(@alignCast(fiber_.capture));

                @call(.auto, func_, .{fiber_} ++ args_.*) catch |err| {
                    std.debug.print("unexpected error: {}", .{err});
                };

                fiber_.after_yield_func = struct {
                    fn f(me: *Fiber, _: *Scheduler, _: *anyopaque) void {
                        me.destroy();
                    }
                }.f;

                // I guess we can assume that the user always wants to return to the caller's ctx.
                ExecutionContext.exit(&fiber_.caller_ctx);
            }
        }.f;

        const capture_free = struct {
            fn f(me: *Fiber) void {
                me.allocator.destroy(@as(*ArgsType, @ptrCast(@alignCast(me.capture))));
            }
        }.f;

        // This way, fibers can be safely moved between threads
        var fiber = try allocator.create(Fiber);

        const capture = try allocator.create(ArgsType);
        capture.* = args;

        fiber.allocator = allocator;
        fiber.stack = undefined;
        fiber.caller_ctx = undefined;
        fiber.ctx = try ExecutionContext.new(&fiber.stack, trampoline, &func, fiber);
        fiber.capture = capture;
        fiber.capture_free = capture_free;
        fiber.after_yield_func = undefined;
        fiber.after_yield_capture = undefined;

        return fiber;
    }

    pub fn destroy(self: *Fiber) void {
        self.capture_free(self);
        self.allocator.destroy(self);
    }

    // Since 'resume' is a keyword, let's stick to an iterator-like interface.
    pub fn next(self: *Fiber) !void {
        self.caller_ctx.switchTo(&self.ctx);
    }

    pub fn yield(self: *Fiber) void {
        self.after_yield_func = struct {
            fn f(me: *Fiber, scheduler: *Scheduler, _: *anyopaque) void {
                scheduler.schedule(me);
            }
        }.f;

        self.ctx.switchTo(&self.caller_ctx);
    }

    pub fn teleportTo(self: *Fiber, scheduler: *Scheduler) void {
        self.after_yield_func = struct {
            fn f(me: *Fiber, _: *Scheduler, args: *anyopaque) void {
                const scheduler_: *Scheduler = @ptrCast(@alignCast(args));
                scheduler_.schedule(me);
            }
        }.f;

        self.after_yield_capture = scheduler;

        self.ctx.switchTo(&self.caller_ctx);
    }
};

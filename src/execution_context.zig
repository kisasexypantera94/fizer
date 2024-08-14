const std = @import("std");

const c = @cImport({
    @cDefine("_XOPEN_SOURCE", "");
    @cInclude("ucontext.h");
});

const ucontext_t = c.ucontext_t;
extern "c" fn getcontext(ucp: *ucontext_t) callconv(.C) c_int;
extern "c" fn makecontext(ucp: *ucontext_t, func: *const anyopaque, argc: c_int, ...) callconv(.C) void;
extern "c" fn swapcontext(oucp: *ucontext_t, ucp: *ucontext_t) callconv(.C) c_int;
extern "c" fn setcontext(ucp: *ucontext_t) callconv(.C) c_int;

pub const ExecutionContext = struct {
    uctx: ucontext_t,

    pub fn make(allocation: []u8, func: *const anyopaque, arg: *void) !ExecutionContext {
        var uctx = ucontext_t{};

        const err = getcontext(&uctx);
        if (err != 0) {
            return error.FailedToGetContext;
        }

        uctx.uc_stack.ss_size = allocation.len;
        uctx.uc_stack.ss_sp = allocation.ptr;

        // makecontext wants arguments as 32-bit ints,
        // so we have to split the 64-bit pointer into lo and hi
        const args: [2]u32 = @bitCast(@intFromPtr(arg));
        makecontext(&uctx, func, 2, args[0], args[1]);

        return ExecutionContext{ .uctx = uctx };
    }

    pub fn switchTo(this: *ExecutionContext, other: *ExecutionContext) !void {
        const ret = swapcontext(&this.uctx, &other.uctx);
        if (ret != 0) {
            std.debug.print("ret = {}, c.errno = {}\n", .{ ret, std.c._errno().* });
            return error.FailedToSwitchContext;
        }
    }

    pub fn setTo(_: *ExecutionContext, other: *ExecutionContext) !void {
        const ret = setcontext(&other.uctx);
        if (ret != 0) {
            std.debug.print("ret = {}, c.errno = {}\n", .{ ret, std.c._errno().* });
            return error.FailedToSetContext;
        }
    }
};

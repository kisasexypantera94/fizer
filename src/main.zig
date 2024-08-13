const std = @import("std");

const ec = @import("execution_context.zig");

pub fn main() !void {
    var allocator = std.heap.page_allocator;

    var bytes = try allocator.alloc(u8, 16384);
    defer allocator.free(bytes);

    var caller_ctx = try allocator.create(ec.ExecutionContext);
    defer allocator.destroy(caller_ctx);

    const arg: *void = @ptrCast(caller_ctx);
    var ctx = try ec.ExecutionContext.new(&bytes, tramp, arg);

    std.debug.print("Arg addr is {any} \n", .{arg});

    caller_ctx.switchTo(&ctx);

    std.debug.print("Welcome back \n", .{});
}

fn foo() void {
    std.debug.print("Here is the real work", .{});
}

fn tramp(lo: u32, hi: u32) callconv(.C) void {
    const ptr_int: usize = @bitCast([2]u32{ lo, hi });
    const arg: *void = @ptrFromInt(ptr_int);
    std.debug.print("Arg addr is {any} \n", .{arg});

    const ctx: *ec.ExecutionContext = @ptrCast(@alignCast(arg));

    var caller_ctx = ec.ExecutionContext{ .uctx = .{} };
    caller_ctx.switchTo(ctx);
}

const std = @import("std");

const ec = @import("execution_context.zig");
const sc = @import("stackful_coroutine.zig");

pub fn main() !void {
    var allocator = std.heap.page_allocator;

    const co0 = try sc.StackfulCoroutine.new(&allocator, struct {
        pub fn f(self: *sc.StackfulCoroutine) void {
            std.debug.print("One\n", .{});
            self.yield();
            std.debug.print("Two\n", .{});
            self.yield();
            std.debug.print("Three\n", .{});
        }
    }.f);

    std.debug.print("Raz\n", .{});
    co0.next();
    std.debug.print("Dva\n", .{});
    co0.next();
    std.debug.print("Tri\n", .{});
    co0.next();

    std.debug.print("Oplya\n", .{});
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
    caller_ctx.switchTo(ctx) catch {};
}

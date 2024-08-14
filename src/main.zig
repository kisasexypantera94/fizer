const std = @import("std");

const ec = @import("execution_context.zig");
const sc = @import("stackful_coroutine.zig");

pub fn main() !void {
    var allocator = std.heap.page_allocator;

    const co0 = try sc.StackfulCoroutine.new(&allocator, struct {
        pub fn f(yh: *sc.YieldHandle) void {
            std.debug.print("One\n", .{});
            yh.yield();
            std.debug.print("Two\n", .{});
            yh.yield();
            std.debug.print("Three\n", .{});
        }
    }.f);

    defer co0.destroy();

    std.debug.print("Raz\n", .{});
    co0.next();
    std.debug.print("Dva\n", .{});
    co0.next();
    std.debug.print("Tri\n", .{});
    co0.next();

    std.debug.print("Oplya\n", .{});
}

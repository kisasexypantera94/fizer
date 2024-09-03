comptime {
    _ = @import("test_singlethreaded.zig");
    _ = @import("test_multithreaded.zig");
    _ = @import("test_tcp.zig");
}

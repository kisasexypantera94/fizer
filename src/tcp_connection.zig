const xev = @import("xev");
const std = @import("std");
const Fiber = @import("fiber.zig").Fiber;
const Scheduler = @import("scheduler.zig").Scheduler;

pub const TcpConnection = struct {
    loop: *xev.Loop,
    completion: xev.Completion,
    addr: std.net.Address,
    socket: xev.TCP,

    pub fn connect(loop: *xev.Loop, fiber: *Fiber) !TcpConnection {
        const ConnectionContext = struct {
            scheduler: *Scheduler,
            fiber: *Fiber,
            c: TcpConnection,
        };

        const connectCallback = struct {
            fn f(
                self_: ?*ConnectionContext,
                _: *xev.Loop,
                _: *xev.Completion,
                _: xev.TCP,
                r: xev.TCP.ConnectError!void,
            ) xev.CallbackAction {
                _ = r catch unreachable;

                const self = self_.?;

                self.scheduler.schedule(self.fiber);
                return .disarm;
            }
        }.f;

        const addr = try std.net.Address.parseIp4("127.0.0.1", 8000);
        const socket = try xev.TCP.init(addr);

        var conn = ConnectionContext{
            .scheduler = undefined,
            .fiber = undefined,
            .c = .{
                .loop = loop,
                .completion = xev.Completion{},
                .addr = addr,
                .socket = socket,
            },
        };

        fiber.after_yield_func = struct {
            fn f(me: *Fiber, scheduler: *Scheduler, args: *anyopaque) void {
                const conn_: *ConnectionContext = @ptrCast(@alignCast(args));
                conn_.scheduler = scheduler;
                conn_.fiber = me;
                conn_.c.socket.connect(conn_.c.loop, &conn_.c.completion, conn_.c.addr, ConnectionContext, conn_, connectCallback);
            }
        }.f;

        fiber.after_yield_capture = &conn;

        fiber.ctx.switchTo(&fiber.caller_ctx);

        return conn.c;
    }

    pub fn write(self: *TcpConnection, buffer: []const u8, fiber: *Fiber) void {
        const WriteContext = struct {
            scheduler: *Scheduler,
            fiber: *Fiber,
            c: *TcpConnection,
            buffer: []const u8,
        };

        const writeCallback = struct {
            fn f(
                self_: ?*WriteContext,
                l: *xev.Loop,
                _: *xev.Completion,
                s: xev.TCP,
                b: xev.WriteBuffer,
                r: xev.TCP.WriteError!usize,
            ) xev.CallbackAction {
                _ = r catch unreachable;
                _ = l;
                _ = s;
                _ = b;

                self_.?.scheduler.schedule(self_.?.fiber);
                // Put back the completion.
                return .disarm;
            }
        }.f;

        var ctx = WriteContext{
            .scheduler = undefined,
            .fiber = undefined,
            .c = self,
            .buffer = buffer,
        };

        fiber.after_yield_func = struct {
            fn f(me: *Fiber, scheduler: *Scheduler, args: *anyopaque) void {
                const ctx_: *WriteContext = @ptrCast(@alignCast(args));
                ctx_.scheduler = scheduler;
                ctx_.fiber = me;
                ctx_.c.socket.write(ctx_.c.loop, &ctx_.c.completion, .{ .slice = ctx_.buffer }, WriteContext, ctx_, writeCallback);
            }
        }.f;

        fiber.after_yield_capture = &ctx;

        fiber.ctx.switchTo(&fiber.caller_ctx);
    }

    pub fn read(self: *TcpConnection, buffer: []u8, fiber: *Fiber) usize {
        const ReadContext = struct {
            scheduler: *Scheduler,
            fiber: *Fiber,
            c: *TcpConnection,
            buffer: []u8,
            n: usize,
        };

        const readCallback = struct {
            fn f(
                self_: ?*ReadContext,
                l: *xev.Loop,
                _: *xev.Completion,
                s: xev.TCP,
                b: xev.ReadBuffer,
                r: xev.TCP.ReadError!usize,
            ) xev.CallbackAction {
                self_.?.n = r catch unreachable;
                _ = l;
                _ = s;
                _ = b;

                self_.?.scheduler.schedule(self_.?.fiber);
                // Put back the completion.
                return .disarm;
            }
        }.f;

        var ctx = ReadContext{
            .scheduler = undefined,
            .fiber = undefined,
            .c = self,
            .buffer = buffer,
            .n = 0,
        };

        fiber.after_yield_func = struct {
            fn f(me: *Fiber, scheduler: *Scheduler, args: *anyopaque) void {
                const ctx_: *ReadContext = @ptrCast(@alignCast(args));
                ctx_.scheduler = scheduler;
                ctx_.fiber = me;
                ctx_.c.socket.read(ctx_.c.loop, &ctx_.c.completion, .{ .slice = ctx_.buffer }, ReadContext, ctx_, readCallback);
            }
        }.f;

        fiber.after_yield_capture = &ctx;

        fiber.ctx.switchTo(&fiber.caller_ctx);

        return ctx.n;
    }
};

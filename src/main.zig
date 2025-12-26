const std = @import("std");
const net = std.net;
const mem = std.mem;
const process = std.process;
const zactus = @import("zactus.zig");

const NUM_WORKERS: usize = 4;
const PORT: usize = 8080;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pool: std.Thread.Pool = undefined;

    try pool.init(.{
        .allocator = allocator,
        .n_jobs = NUM_WORKERS,
    });
    defer pool.deinit();

    std.log.info("Server starting on port {d} with {d} worker threads.", .{ PORT, NUM_WORKERS });

    const address = try net.Address.parseIp("0.0.0.0", PORT);
    var listener = try address.listen(.{ .reuse_address = true });
    defer listener.deinit();

    while (true) {
        const connection = std.net.Server.accept(&listener) catch |err| {
            if (err == error.Interrupted) continue;
            std.log.err("Listener error: {s}", .{@errorName(err)});
            return err;
        };

        pool.spawn(
            zactus.request_handler,
            .{ connection, allocator },
        ) catch |err| {
            std.log.err("Failed to spawn request handler: {s}", .{@errorName(err)});
            connection.stream.close();
        };
    }
}

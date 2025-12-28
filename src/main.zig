const std = @import("std");
const net = std.net;
const mem = std.mem;
const process = std.process;
const posix = std.posix;
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
    const protocol = posix.IPPROTO.TCP;
    const tpe: u32 = posix.SOCK.STREAM | posix.SOCK.NONBLOCK;
    const listener = try posix.socket(address.any.family, tpe, protocol);
    defer posix.close(listener);

    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(listener, &address.any, address.getOsSockLen());
    try posix.listen(listener, 128);

    var polls: [4096]posix.pollfd = undefined;
    polls[0] = .{
        .fd = listener,
        .events = posix.POLL.IN,
        .revents = 0,
    };
    var poll_count: usize = 1;

    while (true) {
        var active = polls[0..poll_count];
        _ = try posix.poll(active, -1);

        if (active[0].revents != 0) {
            const connection = try posix.accept(listener, null, null, posix.SOCK.NONBLOCK);

            polls[poll_count] = .{
                .fd = connection,
                .revents = 0,
                .events = posix.POLL.IN,
            };

            poll_count += 1;
        }

        var i: usize = 1;
        while (i < active.len) {
            const polled = active[i];
            const revents = polled.revents;
            if (revents == 0) {
                i += 1;
                continue;
            }

            if (revents & posix.POLL.IN == posix.POLL.IN) {
                pool.spawn(
                    zactus.request_handler,
                    .{ polled.fd, allocator },
                ) catch |err| {
                    std.log.err("Failed to spawn request handler: {s}", .{@errorName(err)});
                };
            }

            if (revents & posix.POLL.HUP == posix.POLL.HUP) {
                posix.close(polled.fd);

                const last_index = active.len - 1;
                active[i] = active[last_index];
                active = active[0..last_index];
                poll_count -= 1;
            } else {
                i += 1;
            }
        }
    }
}

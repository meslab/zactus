const std = @import("std");
const net = std.net;
const mem = std.mem;
const process = std.process;

const NUM_WORKERS: usize = 4;
const PORT: usize = 8080;

fn request_handler(
    connection: net.Server.Connection,
    allocator: mem.Allocator,
) void {
    defer connection.stream.close();

    const handle = connection.stream.handle;

    var buffer: [1024]u8 = undefined;

    var conn_reader: net.Stream.Reader = connection.stream.reader(&buffer);
    var conn_writer: net.Stream.Writer = connection.stream.writer(&.{});

    _ = conn_reader.interface().takeDelimiterInclusive('\n') catch |err| {
        std.log.err("Worker {d}: Request read failed: {s}", .{ handle, @errorName(err) });
        return;
    };

    std.log.info("Worker {d}: Handled incoming request.", .{handle});

    const response_body = mem.concat(allocator, u8, &.{
        "Hello from Zig Thread Pool Worker ",
        std.fmt.bufPrint(&buffer, "{}", .{handle}) catch unreachable,
        "!\n",
    }) catch @panic("OOM: response body");
    defer allocator.free(response_body);

    const response_header = std.fmt.allocPrint(
        allocator,
        "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: text/plain\r\n" ++
            "Content-Length: {d}\r\r\n" ++
            "Connection: close\r\n\r\n",
        .{response_body.len},
    ) catch @panic("OOM: response header");
    defer allocator.free(response_header);

    conn_writer.interface.writeAll(response_header) catch {};
    conn_writer.interface.writeAll(response_body) catch {};

    std.log.info("Worker {d}: Sent response.", .{handle});
}

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
            request_handler,
            .{ connection, allocator },
        ) catch |err| {
            std.log.err("Failed to spawn request handler: {s}", .{@errorName(err)});
            connection.stream.close();
        };
    }
}

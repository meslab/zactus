const std = @import("std");
const net = std.net;
const mem = std.mem;
const process = std.process;
const posix = std.posix;

pub fn request_handler(
    connection: i32,
    allocator: mem.Allocator,
) void {
    defer posix.close(connection);

    const handle = connection;

    var buffer: [1024]u8 = undefined;

    const read = posix.read(connection, &buffer) catch 0;
    if (read == 0) {
        // closed = true;
        return;
    }

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

    _ = posix.write(connection, response_header) catch |err| {
        std.log.err("Failed to write response header: {s}", .{@errorName(err)});
    };
    _ = posix.write(connection, response_body) catch |err| {
        std.log.err("Failed to write response body: {s}", .{@errorName(err)});
    };

    std.log.info("Worker {d}: Sent response.", .{handle});
}

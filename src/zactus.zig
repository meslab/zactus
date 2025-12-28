const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const linux = std.os.linux;

pub fn request_handler(
    connection: posix.pollfd,
    allocator: mem.Allocator,
) void {
    defer posix.close(connection.fd);

    const handle = connection.fd;

    var buffer: [1024]u8 = undefined;

    const read = posix.read(connection.fd, &buffer) catch 0;
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

    _ = posix.write(connection.fd, response_header) catch |err| {
        std.log.err("Failed to write response header: {s}", .{@errorName(err)});
    };
    _ = posix.write(connection.fd, response_body) catch |err| {
        std.log.err("Failed to write response body: {s}", .{@errorName(err)});
    };

    std.log.info("Worker {d}: Sent response.", .{handle});
}

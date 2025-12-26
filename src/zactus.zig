const std = @import("std");
const net = std.net;
const mem = std.mem;
const process = std.process;

pub fn request_handler(
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

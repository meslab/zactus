const std = @import("std");
const posix = std.posix;
const net = std.net;
const Reader = @import("reader.zig");

const Client = struct {
    socket: posix.socket_t,
    address: net.Address,

    fn _handle(self: Client) !void {
        const socket = self.socket;
        defer posix.close(socket);

        std.debug.print("{} connected\n", .{self.address});

        const timeout = posix.timeval{ .sec = 2, .usec = 500_000 };
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, &std.mem.toBytes(timeout));
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.SNDTIMEO, &std.mem.toBytes(timeout));

        var buffer: [1024]u8 = undefined;
        var reader = Reader.Reader{ .position = 0, .buffer = &buffer, .socket = socket };

        while (true) {
            const message = try reader.readMessage();
            std.debug.print("[{}] sent: {s}\n", .{ self.address, message });
        }
    }
};

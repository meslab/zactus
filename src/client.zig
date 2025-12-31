const std = @import("std");
const posix = std.posix;
const net = std.net;
const socket_reader = @import("reader.zig");
const Reader = socket_reader.Reader;

pub const Client = struct {
    socket: posix.socket_t,
    address: net.Address,

    fn _handle(self: Client) !void {
        const socket = self.socket;

        std.debug.print("{} connected\n", .{self.address});

        const timeout = posix.timeval{ .sec = 2, .usec = 500_000 };
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, &std.mem.toBytes(timeout));
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.SNDTIMEO, &std.mem.toBytes(timeout));

        var buffer: [1024]u8 = undefined;
        var reader = Reader{ .position = 0, .buffer = &buffer, .socket = socket };

        while (true) {
            const message = try reader.readMessage();
            std.debug.print("[{}] sent: {s}\n", .{ self.address, message });
        }
    }

    pub fn handle(self: Client) void {
        defer posix.close(self.socket);
        self._handle() catch |err| switch (err) {
            error.Closed => {},
            error.WouldBlock => {},
            else => std.debug.print("[{}] client handle error: {}\n", .{ self.address, err }),
        };
    }
};

test "default address" {
    const address = try net.Address.parseIp("0.0.0.0", 8080);
    try std.testing.expect(address.eql(address));
}

test "default client" {
    const address = try net.Address.parseIp("0.0.0.0", 8080);
    const protocol = posix.IPPROTO.TCP;
    const socket_flags: u32 = posix.SOCK.STREAM | posix.SOCK.NONBLOCK;
    const socket = try posix.socket(address.any.family, socket_flags, protocol);
    defer posix.close(socket);
    const client = Client{ .socket = socket, .address = address };
    try std.testing.expect(client.address.eql(address));
}

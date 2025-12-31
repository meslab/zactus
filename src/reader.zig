const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const Reader = struct {
    buffer: []u8,
    position: usize = 0,
    start: usize = 0,
    socket: posix.socket_t,

    pub fn readMessage(self: *Reader) ![]u8 {
        var buffer = self.buffer;

        while (true) {
            if (try self.bufferedMessage()) |message| {
                return message;
            }
            const position = self.position;
            const n = try posix.read(self.socket, buffer[position..]);
            if (n == 0) {
                return error.Closed;
            }
            self.position = position + n;
        }
    }

    fn bufferedMessage(self: *Reader) !?[]u8 {
        const buffer = self.buffer;
        const position = self.position;
        const start = self.start;

        std.debug.assert(position >= start);
        const unprocessed = buffer[start..position];
        if (unprocessed.len < 4) {
            self.ensureSpace(4 - unprocessed.len) catch unreachable;
            return null;
        }

        const message_len = mem.readInt(u32, unprocessed[0..4], .little);
        const total_len = message_len + 4;

        if (unprocessed.len < total_len) {
            try self.ensureSpace(total_len);
            return null;
        }

        self.start += total_len;
        return unprocessed[4..total_len];
    }

    fn ensureSpace(self: *Reader, space: usize) error{BufferTooSmall}!void {
        const buffer = self.buffer;
        if (buffer.len < space) {
            return error.BufferTooSmall;
        }

        const start = self.start;
        const spare = buffer.len - start;
        if (spare >= space) {
            return;
        }

        const unprocessed = buffer[start..self.position];
        mem.copyForwards(u8, buffer[0..unprocessed.len], unprocessed);
        self.start = 0;
        self.position = unprocessed.len;
    }
};

test "default reader" {
    const address = try std.net.Address.parseIp("0.0.0.0", 8080);
    const protocol = posix.IPPROTO.TCP;
    const socket_flags: u32 = posix.SOCK.STREAM | posix.SOCK.NONBLOCK;
    const socket = try posix.socket(address.any.family, socket_flags, protocol);
    defer posix.close(socket);
    var buffer: [1024]u8 = undefined;
    const reader = Reader{ .buffer = &buffer, .start = 0, .position = 0, .socket = socket };
    try std.testing.expect(reader.position == 0);
}

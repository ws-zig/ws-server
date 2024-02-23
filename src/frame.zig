// Copyright 2024 Nick-Ilhan Atamgüc
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Frame format:
//
//       0                   1                   2                   3
//       0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//      +-+-+-+-+-------+-+-------------+-------------------------------+
//      |F|R|R|R|opcode |M| Payload len |    Extended payload length    |
//      |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
//      |N|V|V|V|       |S|             |   (if payload len==126/127)   |
//      | |1|2|3|       |K|             |                               |
//      +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
//      |   Extended payload length continued, if payload len == 127    |
//      + - - - - - - - - - - - - - - - +-------------------------------+
//      |                               | Masking-key, if MASK set to 1 |
//      +-------------------------------+-------------------------------+
//      |    Masking-key (continued)    |          Payload Data         |
//      +-------------------------------- - - - - - - - - - - - - - - - +
//      :                     Payload Data continued ...                :
//      + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
//      |                     Payload Data continued ...                |
//      +---------------------------------------------------------------+
//
// First byte:
// - bit 0:   FIN
// - bit 1:   RSV1
// - bit 2:   RSV2
// - bit 3:   RSV3
// - bit 4-7: OPCODE
// Bytes 2-10: payload length.
// If masking is used, the next 4 bytes contain the masking key.
// All subsequent bytes are payload.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const FrameError = error{ Unknown, OutOfMemory, MissingAllocator, MissingBytes, TooManyBytes };

pub const Opcode = enum(u8) {
    Continue = 0,
    Text = 1,
    Binary = 2,

    Close = 8,
    Ping = 9,
    Pong = 10,
};

pub const Frame = struct {
    allocator: *const Allocator = undefined,
    bytes: ?[]const u8 = null,

    _fin: bool = true,
    _rsv1: u8 = 0,
    _rsv2: u8 = 0,
    _rsv3: u8 = 0,
    _opcode: u8 = 0,
    _masked: bool = false,

    _payload_len: u16 = 0,
    _payload_data: ?[]u8 = null,

    const Self = @This();

    pub fn getFin(self: *Self) bool {
        return self._fin;
    }

    pub fn getOpcode(self: *Self) Opcode {
        return @enumFromInt(self._opcode);
    }

    pub fn read(self: *Self) FrameError!*[]u8 {
        if (self.allocator == undefined) {
            return FrameError.MissingAllocator;
        }
        if (self.bytes == null) {
            return FrameError.MissingBytes;
        }

        self._parse_flags();
        try self._parse_payload();
        return &self._payload_data.?;
    }

    fn _parse_flags(self: *Self) void {
        // The FIN bit tells whether this is the last message in a series.
        // If it's false, then the server keeps listening for more parts of the message.
        self._fin = (self.bytes.?[0] & 0b10000000) != 0;
        //std.debug.print("fin: {any}\n", .{self._fin});

        self._rsv1 = self.bytes.?[0] & 0b10000000; // rsv1
        self._rsv2 = self.bytes.?[0] & 0b01000000; // rsv2
        self._rsv3 = self.bytes.?[0] & 0b00100000; // rsv3
        //std.debug.print("rsv1: {d}\nrsv2: {d}\nrsv3: {d}\n", .{ self._rsv1, self._rsv2, self._rsv3 });

        // Fragmentation is only available on 0-2.
        // 0 = continue; 1 = text; 2 = binary; 9 = ping; 10 = pong
        self._opcode = self.bytes.?[0] & 0b00001111;
        //std.debug.print("opcode: {d}\n", .{self._opcode});

        self._masked = (self.bytes.?[1] & 0b10000000) != 0;
        //std.debug.print("masked: {any}\n", .{self._masked});

        self._payload_len = self.bytes.?[1] & 0b01111111;
        //std.debug.print("payload length: {any}\n", .{self._payload_len});
    }

    fn _parse_payload(self: *Self) !void {
        var extra_len: u8 = 0;
        if (self._payload_len == 126) {
            self._payload_len = @intCast(@as(u16, self.bytes.?[2]) << 8 | self.bytes.?[3]);
            extra_len += 2;
        } else if (self._payload_len > 126) {
            self._payload_len = @intCast(@as(u32, self.bytes.?[2]) << 24 | @as(u32, self.bytes.?[3]) << 16 | @as(u32, self.bytes.?[4]) << 8 | self.bytes.?[5]);
            extra_len += 4;
        }

        var masking_key: [4]u8 = .{ 0x00, 0x00, 0x00, 0x00 };
        if (self._masked == true) {
            masking_key = self.bytes.?[(2 + extra_len)..(6 + extra_len)][0..4].*;
        }

        self._payload_data = try self.allocator.alloc(u8, self._payload_len);
        @memcpy(self._payload_data.?, self.bytes.?[(6 + extra_len)..(6 + extra_len + self._payload_len)]);

        for (self._payload_data.?, 0..) |v, i| {
            self._payload_data.?[i] = (v ^ masking_key[i % 4]);
        }
    }

    pub fn write(self: *Self, opcode: Opcode) FrameError!*[]u8 {
        var extra_len: u8 = 0;
        var extra_data: [4]u8 = .{ 0x00, 0x00, 0x00, 0x00 };
        extra_data[0] = @intFromEnum(opcode) | 0b10000000;
        if (self.bytes.?.len <= 125) {
            extra_data[1] = @intCast(self.bytes.?.len);
            extra_len += 2;
        } else if (self.bytes.?.len <= 65531) {
            extra_data[1] = 126;
            extra_data[2] = @intCast((self.bytes.?.len >> 8 & 0b11111111));
            extra_data[3] = @intCast(self.bytes.?.len & 0b11111111);
            extra_len += 4;
        } else { // Don't send more data than we can receive
            return FrameError.TooManyBytes;
        }
        self._payload_data = try self.allocator.alloc(u8, extra_len + self.bytes.?.len);
        @memcpy(self._payload_data.?[0..extra_len], extra_data[0..extra_len]);
        @memcpy(self._payload_data.?[extra_len..], self.bytes.?);
        return &self._payload_data.?;
    }

    pub fn deinit(self: *Self) void {
        if (self.allocator == undefined) {
            return;
        }

        if (self._payload_data != null) {
            self.allocator.free(self._payload_data.?);
        }
    }
};

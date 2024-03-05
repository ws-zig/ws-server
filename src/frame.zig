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

const Utils = @import("./utils/lib.zig");

pub const Frame = struct {
    allocator: *const Allocator,
    bytes: []const u8,

    _fin: bool = false,
    _rsv1: bool = false, // Compressed
    _rsv2: u8 = 0,
    _rsv3: u8 = 0,
    _opcode: u8 = 0,
    _masked: bool = false,

    _payload_len: usize = 0,
    _payload_data: ?[]u8 = null,

    const Self = @This();

    pub inline fn isLastFrame(self: *const Self) bool {
        return self._fin;
    }

    pub inline fn setLastFrame(self: *Self, state: bool) void {
        self._fin = state;
    }

    pub inline fn setCompression(self: *Self, value: bool) void {
        self._rsv1 = value;
    }

    pub inline fn getOpcode(self: *const Self) u8 {
        return self._opcode;
    }

    pub fn read(self: *Self) anyerror![]u8 {
        try self._parseFlags();
        try self._parsePayload();
        return self._payload_data.?;
    }

    fn _parseFlags(self: *Self) anyerror!void {
        // Prevent clients from crashing the server with too few bytes.
        if (self.bytes.len < 2) {
            return error.Frame_TooFewBytes;
        }

        // The FIN bit tells whether this is the last message in a series.
        // If it's false, then the server keeps listening for more parts of the message.
        self._fin = (self.bytes[0] & 0b10000000) != 0;
        //std.debug.print("fin: {any}\n", .{self._fin});

        // The extensions. Not currently implemented (02/29/2024).
        self._rsv1 = (self.bytes[0] & 0b01000000) != 0;
        self._rsv2 = self.bytes[0] & 0b00100000;
        self._rsv3 = self.bytes[0] & 0b00010000;
        //std.debug.print("rsv1: {d}\nrsv2: {d}\nrsv3: {d}\n", .{ self._rsv1, self._rsv2, self._rsv3 });

        // Fragmentation is only available on 0-2.
        // 0 = continue; 1 = text; 2 = binary; 8 = close; 9 = ping; 10 = pong
        self._opcode = self.bytes[0] & 0b00001111;
        //std.debug.print("opcode: {d}\n", .{self._opcode});

        self._masked = (self.bytes[1] & 0b10000000) != 0;
        //std.debug.print("masked: {any}\n", .{self._masked});

        self._payload_len = self.bytes[1] & 0b01111111;
        //std.debug.print("payload length: {any}\n", .{self._payload_len});
    }

    fn _parsePayload(self: *Self) anyerror!void {
        var extra_len: u8 = 2;
        if (self._payload_len == 126) {
            extra_len += 2;
            // A minimum of 4 bytes is required.
            if (self.bytes.len < extra_len) {
                return error.Frame_TooFewBytes;
            }

            self._payload_len = @as(u16, self.bytes[2]) << 8 | self.bytes[3];
        } else if (self._payload_len == 127) {
            extra_len += 8;
            // A minimum of 10 bytes is required.
            if (self.bytes.len < extra_len) {
                return error.Frame_TooFewBytes;
            }

            if (Utils.CPU.is64bit() == false) {
                return error.Frame_64bitRequired;
            }

            self._payload_len =
                @as(usize, self.bytes[2]) << 56 |
                @as(usize, self.bytes[3]) << 48 |
                @as(usize, self.bytes[4]) << 40 |
                @as(usize, self.bytes[5]) << 32 |
                @as(usize, self.bytes[6]) << 24 |
                @as(usize, self.bytes[7]) << 16 |
                @as(usize, self.bytes[8]) << 8 |
                self.bytes[9];
        }

        var masking_key: [4]u8 = .{ 0x00, 0x00, 0x00, 0x00 };
        if (self._masked == true) {
            // A minimum of 6|8|12 bytes is required.
            if (self.bytes.len < (extra_len + 4)) {
                return error.Frame_TooFewBytes;
            }

            masking_key = self.bytes[extra_len..][0..4].*;
            extra_len += 4;
        }

        self._payload_data = try self.allocator.alloc(u8, self._payload_len);
        @memcpy(self._payload_data.?, self.bytes[(extra_len)..(extra_len + self._payload_len)]);

        for (self._payload_data.?, 0..) |v, i| {
            self._payload_data.?[i] = (v ^ masking_key[i % 4]);
        }

        if (self._rsv1 == true) {
            self._payload_data = try self._decompress(self._payload_data.?);
        }
    }

    fn _decompress(self: *const Self, data: []u8) anyerror![]u8 {
        var stream = std.io.fixedBufferStream(data);
        var result = std.ArrayList(u8).init(self.allocator.*);
        defer result.deinit();
        // Temporary solution: https://github.com/ziglang/zig/issues/19187
        try std.compress.flate.decompress(stream.reader(), result.writer());
        return result.toOwnedSlice();
    }

    fn _compress(self: *const Self, data: []const u8) anyerror![]u8 {
        var result = std.ArrayList(u8).init(self.allocator.*);
        defer result.deinit();
        var comp = try std.compress.flate.compressor(result.writer(), .{});
        _ = try comp.write(data);
        try comp.finish();
        return try result.toOwnedSlice();
    }

    pub fn write(self: *Self, opcode: u8) anyerror![]u8 {
        var bytes_compressed = false;
        if (self._rsv1 == true) {
            self.bytes = try self._compress(self.bytes);
            bytes_compressed = true;
        }

        var extra_len: u8 = 0;
        var extra_data: [10]u8 = .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
        extra_data[0] = opcode | 0b00000000;
        if (self._fin == true) {
            extra_data[0] |= 0b10000000;
        }
        if (self._rsv1 == true) {
            extra_data[0] |= 0b01000000;
        }

        if (self.bytes.len <= 125) {
            extra_data[1] = @intCast(self.bytes.len | 0b00000000); // 0b10000000 = masked
            extra_len += 2;
        } else if (self.bytes.len <= 65531) {
            extra_data[1] = 126 | 0b00000000; // 0b10000000 = masked
            extra_data[2] = @intCast(self.bytes.len >> 8 & 0b11111111);
            extra_data[3] = @intCast(self.bytes.len & 0b11111111);
            extra_len += 4;
        } else {
            if (Utils.CPU.is64bit() == false) {
                return error.Frame_64bitRequired;
            }

            extra_data[1] = 127 | 0b00000000; // 0b10000000 = masked
            extra_data[2] = @intCast(self.bytes.len >> 56 & 0b11111111);
            extra_data[3] = @intCast(self.bytes.len >> 48 & 0b11111111);
            extra_data[4] = @intCast(self.bytes.len >> 40 & 0b11111111);
            extra_data[5] = @intCast(self.bytes.len >> 32 & 0b11111111);
            extra_data[6] = @intCast(self.bytes.len >> 24 & 0b11111111);
            extra_data[7] = @intCast(self.bytes.len >> 16 & 0b11111111);
            extra_data[8] = @intCast(self.bytes.len >> 8 & 0b11111111);
            extra_data[9] = @intCast(self.bytes.len & 0b11111111);
            extra_len += 10;
        }

        self._payload_data = try self.allocator.alloc(u8, extra_len + self.bytes.len);
        @memcpy(self._payload_data.?[0..extra_len], extra_data[0..extra_len]);
        @memcpy(self._payload_data.?[extra_len..], self.bytes);
        if (bytes_compressed == true) {
            self.allocator.free(self.bytes);
        }
        return self._payload_data.?;
    }

    pub fn deinit(self: *Self) void {
        if (self._payload_data != null) {
            self.allocator.free(self._payload_data.?);
        }
        self.* = undefined;
    }
};

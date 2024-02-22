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

const std = @import("std");
const Allocator = std.mem.Allocator;

const Message = @import("./message.zig").Message;
const Callbacks = @import("./callbacks.zig");

const MAGIC_STRING = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const ENCODER_ALPHABETE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

const PrivateFields = struct {
    allocator: *const std.mem.Allocator = undefined,
    stream: ?std.net.Stream = null,

    closeConn: bool = false,
    connClosed: bool = false,
};

pub const Client = struct {
    /// Private data that should not be touched.
    _private: PrivateFields = undefined,

    const Self = @This();

    pub fn sendText(self: *Self, data: []const u8) !void {
        var message = Message{ .allocator = self._private.allocator };
        try message.writeText(data);
        const testdata = message.get().*.?;
        try self._private.stream.?.writeAll(testdata);
    }

    pub fn closeImmediately(self: *Self) void {
        self.deinit();
    }

    pub fn sendClose(self: *Self) !void {
        var message = Message{ .allocator = self._private.allocator };
        try message.writeClose();
        const testdata = message.get().*.?;
        try self._private.stream.?.writeAll(testdata);
    }

    pub fn sendPing(self: *Self) !void {
        var message = Message{ .allocator = self._private.allocator };
        try message.writePing();
        const testdata = message.get().*.?;
        try self._private.stream.?.writeAll(testdata);
    }

    pub fn sendPong(self: *Self) !void {
        var message = Message{ .allocator = self._private.allocator };
        try message.writePong();
        const testdata = message.get().*.?;
        try self._private.stream.?.writeAll(testdata);
    }

    fn deinit(self: *Self) void {
        self._private.closeConn = true;
        if (self._private.stream != null) {
            self._private.stream.?.close();
            self._private.stream = null;
        }
        self._private.connClosed = true;
    }
};

pub fn handshake(self: *Client) !void {
    if (self._private.allocator == undefined) {
        return error.MissingAllocator;
    }
    if (self._private.stream == null) {
        return error.MissingStream;
    }

    //std.debug.print("=== handshake ===\n", .{});

    var headers = std.StringHashMap([]const u8).init(self._private.allocator.*);
    defer headers.clearAndFree();

    var method: []const u8 = undefined;
    var uri: []const u8 = undefined;
    var version: []const u8 = undefined;

    var header_line: []u8 = undefined;
    var first_header_line: bool = true;
    while (true) {
        header_line = try self._private.stream.?.reader().readUntilDelimiterAlloc(self._private.allocator.*, '\n', std.math.maxInt(usize));
        header_line = header_line[0..(header_line.len - 1)];

        // End of header
        if (header_line.len == 0) {
            break;
        }

        if (first_header_line == true) {
            var header_line_iter = std.mem.split(u8, header_line, " ");
            first_header_line = false;
            method = header_line_iter.next().?;
            uri = header_line_iter.next().?;
            version = header_line_iter.next().?;
            continue;
        }
        var header_line_iter = std.mem.split(u8, header_line, ": ");
        const key = header_line_iter.next().?;
        const value = header_line_iter.next().?;

        //std.debug.print("header: {s}({d}):{s}({d})\n", .{ key, key.len, value, value.len });

        try headers.put(key, value);
    }

    const header_key = headers.get("Sec-WebSocket-Key").?;

    var sha1_out: [20]u8 = undefined;
    var sha1_key = std.crypto.hash.Sha1.init(.{});
    sha1_key.update(header_key);
    sha1_key.update(MAGIC_STRING);
    sha1_key.final(&sha1_out);

    const base64 = std.base64.Base64Encoder.init(ENCODER_ALPHABETE.*, '=');
    const base64_out_len = base64.calcSize(sha1_out.len);
    const base64_out = try self._private.allocator.alloc(u8, base64_out_len);
    defer self._private.allocator.free(base64_out);
    const base64_result = base64.encode(base64_out, sha1_out[0..]);

    const header_result_basic = " 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ";
    const header_result = try self._private.allocator.alloc(u8, version.len + header_result_basic.len + base64_result.len + 4);
    defer self._private.allocator.free(header_result);
    var dest_pos: usize = 0;
    var src_pos: usize = version.len;
    @memcpy(header_result[dest_pos..src_pos], version);
    dest_pos = src_pos;
    src_pos = dest_pos + header_result_basic.len;
    @memcpy(header_result[dest_pos..src_pos], header_result_basic);
    dest_pos = src_pos;
    src_pos = dest_pos + base64_result.len;
    @memcpy(header_result[dest_pos..src_pos], base64_result);
    dest_pos = src_pos;
    src_pos = dest_pos + 4;
    @memcpy(header_result[dest_pos..src_pos], "\r\n\r\n");

    //std.debug.print("=== send header ===\n{s}\n", .{header_result});
    try self._private.stream.?.writer().writeAll(header_result);
}

pub fn handle(self: *Client, onMsg: Callbacks.ServerOnMessage, onClose: Callbacks.ServerOnClose, onPing: Callbacks.ServerOnPing, onPong: Callbacks.ServerOnPong) !void {
    var message: ?Message = null;

    while (self._private.closeConn == false) {
        var buffer: [65535]u8 = undefined;
        const buffer_len = self._private.stream.?.read(&buffer) catch |err| {
            std.debug.print("Failed to read buffer: {any}\n", .{err});
            break;
        }; // buffer_size

        message = Message{ .allocator = self._private.allocator };
        message.?.read(buffer[0..buffer_len]) catch |err| {
            std.debug.print("message.read() failed: {any}\n", .{err});
            message.?.deinit();
            message = null;
            continue;
        };
        if (message.?.isReady() == false) {
            continue;
        }
        if (message.?.isClose() == true) {
            if (onClose != null) {
                onClose.?(self) catch |err| {
                    std.debug.print("onClose() failed: {any}\n", .{err});
                };
            }
            break;
        }
        if (message.?.isPing() == true) {
            if (onPing != null) {
                onPing.?(self) catch |err| {
                    std.debug.print("onPing() failed: {any}\n", .{err});
                };
            }
        } else if (message.?.isPong() == true) {
            if (onPong != null) {
                onPong.?(self) catch |err| {
                    std.debug.print("onPong() failed: {any}\n", .{err});
                };
            }
        }

        const message_data = message.?.get().*;
        if (onMsg != null and message_data != null and message_data.?.len > 0) {
            onMsg.?(self, message_data.?) catch |err| {
                std.debug.print("onMessage() failed: {any}\n", .{err});
            };
        }

        message.?.deinit();
        message = null;
    }

    if (message != null) {
        message.?.deinit();
        message = null;
    }

    if (self._private.closeConn == false) {
        self.deinit();
    }
}

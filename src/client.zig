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
const net = std.net;
const Allocator = std.mem.Allocator;

const FrameFile = @import("./frame.zig");
const Frame = FrameFile.Frame;
const FrameOpcode = FrameFile.Opcode;
const Message = @import("./message.zig").Message;
const Callbacks = @import("./callbacks.zig");

const MAGIC_STRING = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const ENCODER_ALPHABETE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub const Client = struct {
    allocator: *const Allocator = undefined,
    stream: ?net.Stream = null,

    _closeConn: bool = false,
    _connClosed: bool = false,

    const Self = @This();

    fn _validate(self: *const Self) !void {
        if (self.allocator == undefined) {
            return error.MissingAllocator;
        }
        if (self.stream == null) {
            return error.MissingStream;
        }
    }

    pub fn closeConn(self: *Self) void {
        self._closeConn = true;
        self.deinit();
        self._connClosed = true;
    }

    pub fn handshake(self: *const Self) !void {
        try self._validate();

        //std.debug.print("=== handshake ===\n", .{});

        var headers = std.StringHashMap([]const u8).init(self.allocator.*);

        var method: []const u8 = undefined;
        var uri: []const u8 = undefined;
        var version: []const u8 = undefined;

        var header_line: []u8 = undefined;
        var first_header_line: bool = true;
        while (true) {
            header_line = try self.stream.?.reader().readUntilDelimiterAlloc(self.allocator.*, '\n', std.math.maxInt(usize));
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
        const base64_out = try self.allocator.alloc(u8, base64_out_len);
        defer self.allocator.free(base64_out);
        const base64_result = base64.encode(base64_out, sha1_out[0..]);

        const header_result_basic = " 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ";
        const header_result = try self.allocator.alloc(u8, version.len + header_result_basic.len + base64_result.len + 4);
        defer self.allocator.free(header_result);
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
        try self.stream.?.writer().writeAll(header_result);
    }

    pub fn handle(self: *Self, cb: Callbacks.ServerOnMessage) !void {
        var message: Message = undefined;

        while (self._closeConn == false) {
            var buffer: [1024]u8 = undefined;
            _ = self.stream.?.read(&buffer) catch |err| {
                std.debug.print("Failed to read buffer: {any}\n", .{err});
                break;
            }; // buffer_size

            message = Message{ .allocator = self.allocator };
            message.read(&buffer) catch |err| {
                std.debug.print("message.read() failed: {any}\n", .{err});
                message.deinit();
                message = undefined;
                continue;
            };
            if (message.isReady() == false) {
                continue;
            }

            if (cb != undefined) {
                cb(self, message.get().*.?) catch |err| {
                    std.debug.print("onMessage() failed: {any}\n", .{err});
                };
            }

            message.deinit();
            message = undefined;
        }

        if (self._closeConn == false) {
            self.closeConn();
        }
    }

    pub fn sendText(self: *Self, data: []const u8) !void {
        var message = Message{ .allocator = self.allocator };
        try message.writeText(data);
        const testdata = message.get().*.?;
        try self.stream.?.writeAll(testdata);
    }

    fn deinit(self: *Self) void {
        if (self.stream != null) {
            self.stream.?.close();
            self.stream = null;
        }
    }
};

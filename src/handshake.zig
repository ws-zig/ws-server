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
// => HANDSHAKE <=
// Handshake is part of “Client”. Due to the long source code, we moved it to its own file.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Client = @import("./client.zig").Client;
const Callbacks = @import("./callbacks.zig");

const MAGIC_STRING = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const ENCODER_ALPHABETE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const RESPONSE_BASIC = " 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ";
const RESPONSE_BASIC_COMPRESS = " 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Extensions: permessage-deflate\r\nSec-WebSocket-Accept: ";

pub fn handle(self: *Client, compression: bool, cbs: *const Callbacks.ClientCallbacks) anyerror!bool {
    //std.debug.print("=== handshake ===\n", .{});

    var headers = try _getHeaders(self._private.allocator, &self._private.connection.stream);
    defer headers.deinit();

    if (cbs.handshake.handle(self, &headers) == false) {
        return false;
    }

    const header_version: []const u8 = headers.get("version").?;
    const header_key: []const u8 = headers.get("Sec-WebSocket-Key") orelse return error.Handshake_MissingSecWebSocketKey;

    const sha1_out: [20]u8 = _getSha1(header_key);
    const base64_out: []const u8 = try _getBase64(self._private.allocator, sha1_out);
    defer self._private.allocator.free(base64_out);

    var response: []u8 = undefined;
    if (compression == true) {
        const response_size: usize = header_version.len + RESPONSE_BASIC_COMPRESS.len + base64_out.len + 4;
        response = try self._private.allocator.alloc(u8, response_size);
    } else {
        const response_size: usize = header_version.len + RESPONSE_BASIC.len + base64_out.len + 4;
        response = try self._private.allocator.alloc(u8, response_size);
    }
    defer self._private.allocator.free(response);

    var dest_pos: usize = 0;
    var src_pos: usize = header_version.len;
    @memcpy(response[dest_pos..src_pos], header_version);
    dest_pos = src_pos;
    if (compression == true) {
        src_pos += RESPONSE_BASIC_COMPRESS.len;
        @memcpy(response[dest_pos..src_pos], RESPONSE_BASIC_COMPRESS);
    } else {
        src_pos += RESPONSE_BASIC.len;
        @memcpy(response[dest_pos..src_pos], RESPONSE_BASIC);
    }
    dest_pos = src_pos;
    src_pos += base64_out.len;
    @memcpy(response[dest_pos..src_pos], base64_out);
    dest_pos = src_pos;
    src_pos += 4;
    @memcpy(response[dest_pos..src_pos], "\r\n\r\n");

    //std.debug.print("=== send header ===\n{s}\n", .{response});
    try self._private.connection.stream.writer().writeAll(response);

    return true;
}

fn _getHeaders(allocator: *const Allocator, stream: *const std.net.Stream) anyerror!std.StringHashMap([]const u8) {
    var result = std.StringHashMap([]const u8).init(allocator.*);

    var first_header_line: bool = true;
    while (true) {
        var header_line_array = std.ArrayList(u8).init(allocator.*);
        defer header_line_array.deinit();
        try stream.reader().streamUntilDelimiter(header_line_array.writer(), '\n', std.math.maxInt(usize));
        var header_line: []u8 = try header_line_array.toOwnedSlice();
        header_line = header_line[0..(header_line.len - 1)];

        // End of header
        if (header_line.len == 0) {
            break;
        }

        if (first_header_line == true) {
            first_header_line = false;

            var header_line_iter = std.mem.split(u8, header_line, " ");
            const method: []const u8 = header_line_iter.next() orelse return error.Handshake_MissingMethod;
            const uri: []const u8 = header_line_iter.next() orelse return error.Handshake_MissingUri;
            const version: []const u8 = header_line_iter.next() orelse return error.Handshake_MissingVersion;

            //std.debug.print("header: {s} {s} {s}\n", .{ method, uri, version });

            try result.put("method", method);
            try result.put("uri", uri);
            try result.put("version", version);
        } else {
            var header_line_iter = std.mem.split(u8, header_line, ": ");
            const key: []const u8 = header_line_iter.next().?;
            const value: []const u8 = header_line_iter.next().?;

            //std.debug.print("header: {s}({d}):{s}({d})\n", .{ key, key.len, value, value.len });

            try result.put(key, value);
        }
    }

    return result;
}

inline fn _getSha1(header_key: []const u8) [20]u8 {
    var sha1_out: [20]u8 = undefined;
    var sha1_key = std.crypto.hash.Sha1.init(.{});
    sha1_key.update(header_key);
    sha1_key.update(MAGIC_STRING);
    sha1_key.final(&sha1_out);
    return sha1_out;
}

inline fn _getBase64(allocator: *const Allocator, sha1_out: [20]u8) anyerror![]const u8 {
    const base64 = std.base64.Base64Encoder.init(ENCODER_ALPHABETE.*, '=');
    const base64_out_len: usize = base64.calcSize(sha1_out.len);
    const base64_out: []u8 = try allocator.alloc(u8, base64_out_len);
    _ = base64.encode(base64_out, &sha1_out);
    return base64_out;
}

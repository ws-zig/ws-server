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

const MAGIC_STRING = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const ENCODER_ALPHABETE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn handle(self: *Client) !void {
    if (self._private.allocator == undefined) {
        return error.MissingAllocator;
    }
    if (self._private.stream == null) {
        return error.MissingStream;
    }

    //std.debug.print("=== handshake ===\n", .{});

    var headers = try getHeaders(self._private.allocator, self._private.stream.?);
    defer headers.clearAndFree();

    const header_version = headers.get("version").?;
    const header_key = headers.get("Sec-WebSocket-Key").?;

    const sha1_out = getSha1(header_key);
    const base64_out = try getBase64(self._private.allocator, sha1_out);
    defer self._private.allocator.free(base64_out);

    const header_result_basic = " 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ";
    const header_result = try self._private.allocator.alloc(u8, header_version.len + header_result_basic.len + base64_out.len + 4);
    defer self._private.allocator.free(header_result);
    var dest_pos: usize = 0;
    var src_pos: usize = header_version.len;
    @memcpy(header_result[dest_pos..src_pos], header_version);
    dest_pos = src_pos;
    src_pos = dest_pos + header_result_basic.len;
    @memcpy(header_result[dest_pos..src_pos], header_result_basic);
    dest_pos = src_pos;
    src_pos = dest_pos + base64_out.len;
    @memcpy(header_result[dest_pos..src_pos], base64_out);
    dest_pos = src_pos;
    src_pos = dest_pos + 4;
    @memcpy(header_result[dest_pos..src_pos], "\r\n\r\n");

    //std.debug.print("=== send header ===\n{s}\n", .{header_result});
    try self._private.stream.?.writer().writeAll(header_result);
}

fn getHeaders(allocator: *const Allocator, stream: std.net.Stream) !std.StringHashMap([]const u8) {
    var result = std.StringHashMap([]const u8).init(allocator.*);

    var header_line: []u8 = undefined;
    var first_header_line: bool = true;
    while (true) {
        header_line = try stream.reader().readUntilDelimiterAlloc(allocator.*, '\n', std.math.maxInt(usize));
        header_line = header_line[0..(header_line.len - 1)];

        // End of header
        if (header_line.len == 0) {
            break;
        }

        if (first_header_line == true) {
            var header_line_iter = std.mem.split(u8, header_line, " ");
            first_header_line = false;
            const method = header_line_iter.next().?;
            try result.put("method", method);
            const uri = header_line_iter.next().?;
            try result.put("uri", uri);
            const version = header_line_iter.next().?;
            try result.put("version", version);
            continue;
        }
        var header_line_iter = std.mem.split(u8, header_line, ": ");
        const key = header_line_iter.next().?;
        const value = header_line_iter.next().?;

        //std.debug.print("header: {s}({d}):{s}({d})\n", .{ key, key.len, value, value.len });

        try result.put(key, value);
    }

    return result;
}

fn getSha1(header_key: []const u8) [20]u8 {
    var sha1_out: [20]u8 = undefined;
    var sha1_key = std.crypto.hash.Sha1.init(.{});
    sha1_key.update(header_key);
    sha1_key.update(MAGIC_STRING);
    sha1_key.final(&sha1_out);
    return sha1_out;
}

fn getBase64(allocator: *const Allocator, sha1_out: [20]u8) ![]const u8 {
    const base64 = std.base64.Base64Encoder.init(ENCODER_ALPHABETE.*, '=');
    const base64_out_len = base64.calcSize(sha1_out.len);
    const base64_out = try allocator.alloc(u8, base64_out_len);
    _ = base64.encode(base64_out, &sha1_out);
    return base64_out;
}

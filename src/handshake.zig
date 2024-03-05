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

const Utils = @import("./utils/lib.zig");
const Client = @import("./client.zig").Client;
const Callbacks = @import("./callbacks.zig");

const MAGIC_STRING = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const ENCODER_ALPHABETE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const HEADER_SPLIT = "\r\n";

const HeaderResult = struct {
    upgrade: [1][]const u8 = .{"websocket"},
    connection: [1][]const u8 = .{"Upgrade"},
    extensions: u8 = 0b00000000,
    key: []const u8,
};

fn _create_response_header(self: *Client, headers: HeaderResult) anyerror![]u8 {
    var result = std.ArrayList(u8).init(self._private.allocator.*);
    defer result.deinit();

    try result.appendSlice("HTTP/1.1 101 Switching Protocols\r\n");

    try result.appendSlice("Upgrade: ");
    for (headers.upgrade, 0..) |v, idx| {
        if (idx > 0) {
            try result.appendSlice("; ");
        }
        try result.appendSlice(v);
    }
    try result.appendSlice(HEADER_SPLIT);

    try result.appendSlice("Connection: ");
    for (headers.connection, 0..) |v, idx| {
        if (idx > 0) {
            try result.appendSlice("; ");
        }
        try result.appendSlice(v);
    }
    try result.appendSlice(HEADER_SPLIT);

    if (headers.extensions != 0b00000000) {
        try result.appendSlice("Sec-WebSocket-Extensions: ");
        if ((headers.extensions & 0b10000000) != 0) {
            try result.appendSlice("permessage-deflate");
        }
        try result.appendSlice(HEADER_SPLIT);
    }

    try result.appendSlice("Sec-WebSocket-Accept: ");
    try result.appendSlice(headers.key);
    try result.appendSlice(HEADER_SPLIT);

    try result.appendSlice(HEADER_SPLIT); // End

    return result.toOwnedSlice();
}

fn _cancel(self: *Client) void {
    // TODO
    self._private.connection.stream.writer().writeAll("HTTP/1.1 400 Bad Request\r\n\r\n") catch return;
}

pub fn handle(self: *Client, compression: bool, cbs: *const Callbacks.ClientCallbacks) bool {
    //std.debug.print("=== handshake ===\n", .{});

    var headers = _getHeaders(self._private.allocator, &self._private.connection.stream) catch {
        _cancel(self);
        return false;
    };
    defer {
        var headers_iter = headers.iterator();
        while (headers_iter.next()) |kv| {
            self._private.allocator.free(kv.key_ptr.*);
            self._private.allocator.free(kv.value_ptr.*);
        }
        headers.deinit();
    }

    if (cbs.handshake.handle(self, &headers) == false) {
        _cancel(self);
        return false;
    }

    var header_extensions: u8 = 0b00000000;
    if (headers.get("Sec-WebSocket-Extensions")) |extensions| {
        if (compression == true) {
            if (Utils.str.contains(extensions, "permessage-deflate") == false) {
                _cancel(self);
                return false;
            }

            header_extensions |= 0b10000000;
        }
    } else if (compression == true) {
        _cancel(self);
        return false;
    }
    const header_key: []const u8 = headers.get("Sec-WebSocket-Key") orelse {
        _cancel(self);
        return false;
    };

    const sha1_out: [20]u8 = _getSha1(header_key);
    const base64_out: []const u8 = _getBase64(self._private.allocator, sha1_out) catch {
        _cancel(self);
        return false;
    };
    defer self._private.allocator.free(base64_out);

    const response_header_result: HeaderResult = .{ .extensions = header_extensions, .key = base64_out };
    const response: []u8 = _create_response_header(self, response_header_result) catch {
        _cancel(self);
        return false;
    };

    self._private.connection.stream.writer().writeAll(response) catch return false;
    return true;
}

fn _getHeaders(allocator: *const Allocator, stream: *const std.net.Stream) anyerror!std.StringHashMap([]const u8) {
    var result = std.StringHashMap([]const u8).init(allocator.*);

    var first_header_line: bool = true;
    while (true) {
        const line: []u8 = try stream.reader().readUntilDelimiterAlloc(allocator.*, '\n', std.math.maxInt(usize));
        defer allocator.free(line);

        if (line.len <= 5) {
            break;
        }

        if (first_header_line == true) {
            first_header_line = false;
            continue;
        }

        var line_iter = std.mem.split(u8, line[0..(line.len - 1)], ": ");
        const key: []const u8 = line_iter.next() orelse continue;
        const value: []const u8 = line_iter.next() orelse continue;

        const key_cpy: []u8 = try allocator.alloc(u8, key.len);
        @memcpy(key_cpy, key);
        const value_cpy: []u8 = try allocator.alloc(u8, value.len);
        @memcpy(value_cpy, value);

        try result.put(key_cpy, value_cpy);
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

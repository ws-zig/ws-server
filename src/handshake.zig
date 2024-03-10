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

const Utils = @import("./utils/lib.zig");
const ClientFile = @import("./client.zig");
const Client = ClientFile.Client;
const CallbacksFile = @import("./callbacks.zig");
const Callbacks = CallbacksFile.Callbacks;

const MAGIC_STRING = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const ENCODER_ALPHABETE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const HEADER_SPLIT = "\r\n";

const Headers = struct {
    allocator: *const Allocator,

    _map: ?std.StringHashMap([]const u8) = null,
    _extensions: u8 = 0b00000000,

    const Self = @This();

    pub inline fn getMap(self: *const Self) ?std.StringHashMap([]const u8) {
        return self._map;
    }

    pub inline fn getExtensions(self: *const Self) u8 {
        return self._extensions;
    }

    pub fn init(allocator: *const Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn read(self: *Self, line: []const u8) error{ LineSplittingFailed, OutOfMemory }!void {
        if (self._map == null) {
            self._map = std.StringHashMap([]const u8).init(self.allocator.*);
        }

        var line_iter = std.mem.split(u8, line, ": ");
        const key: []const u8 = line_iter.next() orelse return error.LineSplittingFailed;
        const value: []const u8 = line_iter.next() orelse return error.LineSplittingFailed;

        if (std.mem.eql(u8, key, "Sec-WebSocket-Extensions") == true) {
            if (Utils.str.contains(value, "permessage-deflate") == true) {
                self._extensions |= 0b10000000;
            }
        }

        // We need to copy the data because after this function call every `line` will be freed.
        const key_cpy: []u8 = try self.allocator.alloc(u8, key.len);
        @memcpy(key_cpy, key);
        const value_cpy: []u8 = try self.allocator.alloc(u8, value.len);
        @memcpy(value_cpy, value);

        try self._map.?.put(key_cpy, value_cpy);
    }

    pub fn generateKey(self: *const Self) error{ MapHasNotBeenInitialized, MissingWebSocketKey, OutOfMemory }![]const u8 {
        if (self._map == null) {
            return error.MapHasNotBeenInitialized;
        }

        const header_key = self._map.?.get("Sec-WebSocket-Key") orelse {
            return error.MissingWebSocketKey;
        };
        var sha1_out: [20]u8 = undefined;
        var sha1 = std.crypto.hash.Sha1.init(.{});
        sha1.update(header_key);
        sha1.update(MAGIC_STRING);
        sha1.final(&sha1_out);
        const base64 = std.base64.Base64Encoder.init(ENCODER_ALPHABETE.*, '=');
        const base64_out_len = base64.calcSize(sha1_out.len);
        const base64_out = try self.allocator.alloc(u8, base64_out_len);
        return base64.encode(base64_out, &sha1_out);
    }

    pub fn createResponse(self: *const Self, key: []const u8) error{OutOfMemory}![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator.*);
        defer result.deinit();

        try result.appendSlice("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n");

        if (self._extensions != 0b00000000) {
            try result.appendSlice("Sec-WebSocket-Extensions: ");
            if ((self._extensions & 0b10000000) != 0) {
                try result.appendSlice("permessage-deflate");
            }
            try result.appendSlice(HEADER_SPLIT);
        }

        try result.appendSlice("Sec-WebSocket-Accept: ");
        try result.appendSlice(key);
        try result.appendSlice(HEADER_SPLIT);

        try result.appendSlice(HEADER_SPLIT); // End

        return result.toOwnedSlice();
    }

    pub fn deinit(self: *Self) void {
        if (self._map != null) {
            var headers_iter = self._map.?.iterator();
            while (headers_iter.next()) |kv| {
                self.allocator.free(kv.key_ptr.*);
                self.allocator.free(kv.value_ptr.*);
            }
            self._map.?.deinit();
        }
        self.* = undefined;
    }
};

pub const Handshake = struct {
    client: *Client,
    cbs: *const Callbacks,

    const Self = @This();

    pub fn handle(self: *Self) anyerror!bool {
        defer self._deinit();

        const allocator = self.client._private.allocator;
        const stream = &self.client._private.connection.stream;

        var headers = Headers.init(allocator);
        defer headers.deinit();
        var first_header_line = true;
        while (true) {
            const line: []u8 = stream.reader().readUntilDelimiterAlloc(allocator.*, '\n', 128) catch |err| {
                if (err == error.ConnectionResetByPeer) {
                    return false;
                }
                return err;
            };
            defer allocator.free(line);

            if (first_header_line == true) {
                first_header_line = false;
                continue;
            }

            if (line.len <= 5) {
                break;
            }

            headers.read(line[0..(line.len - 1)]) catch |err| {
                if (err == error.LineSplittingFailed) {
                    stream.writer().writeAll("HTTP/1.1 400 Bad Request\r\n\r\n") catch {};
                    return false;
                }
                return err;
            };
        }

        if (self.client._private.compression == true) {
            if ((headers.getExtensions() & 0b10000000) == 0) {
                stream.writer().writeAll("HTTP/1.1 400 Bad Request\r\n\r\n") catch {};
                return false;
            }
        }

        const key: []const u8 = headers.generateKey() catch |err| {
            switch (err) {
                error.MapHasNotBeenInitialized, error.MissingWebSocketKey => {
                    stream.writer().writeAll("HTTP/1.1 400 Bad Request\r\n\r\n") catch {};
                    return false;
                },
                else => return err,
            }
        };
        defer allocator.free(key);
        const response: []const u8 = try headers.createResponse(key);
        defer allocator.free(response);

        stream.writeAll(response) catch |err| {
            if (err == error.ConnectionResetByPeer) {
                return false;
            }
            return err;
        };

        return self.cbs.handshake.handle(self.client, &headers.getMap().?);
    }

    fn _deinit(self: *Self) void {
        self.* = undefined;
    }
};

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

const PrivateFields = struct {
    allocator: *const std.mem.Allocator = undefined,
    stream: ?std.net.Stream = null,

    close_conn: bool = false,
    conn_closed: bool = false,
};

pub const Client = struct {
    /// Private data that should not be touched.
    _private: PrivateFields = undefined,

    const Self = @This();

    pub fn sendText(self: *Self, data: []const u8) !void {
        var message = Message{ .allocator = self._private.allocator };
        defer message.deinit();
        try message.writeText(data);
        const message_result = message.get().*.?;
        try self._private.stream.?.writeAll(message_result);
    }

    pub fn sendClose(self: *Self) !void {
        var message = Message{ .allocator = self._private.allocator };
        defer message.deinit();
        try message.writeClose();
        const message_result = message.get().*.?;
        try self._private.stream.?.writeAll(message_result);
    }

    pub fn sendPing(self: *Self) !void {
        var message = Message{ .allocator = self._private.allocator };
        defer message.deinit();
        try message.writePing();
        const message_result = message.get().*.?;
        try self._private.stream.?.writeAll(message_result);
    }

    pub fn sendPong(self: *Self) !void {
        var message = Message{ .allocator = self._private.allocator };
        defer message.deinit();
        try message.writePong();
        const message_result = message.get().*.?;
        try self._private.stream.?.writeAll(message_result);
    }

    pub fn closeImmediately(self: *Self) void {
        self.deinit();
    }

    fn deinit(self: *Self) void {
        self._private.close_conn = true;
        if (self._private.stream != null) {
            self._private.stream.?.close();
            self._private.stream = null;
        }
        self._private.conn_closed = true;
    }
};

pub const handshake = @import("./handshake.zig").handle;

pub fn handle(self: *Client, onMsg: Callbacks.ServerOnMessage, onClose: Callbacks.ServerOnClose, onPing: Callbacks.ServerOnPing, onPong: Callbacks.ServerOnPong) !void {
    var message: ?Message = null;

    while (self._private.close_conn == false) {
        var buffer: [65535]u8 = undefined;
        const buffer_len = self._private.stream.?.read(&buffer) catch |err| {
            std.debug.print("Failed to read buffer: {any}\n", .{err});
            break;
        };

        var recreate_message = true;
        if (message != null) {
            if (message.?.isReady() == true) {
                message.?.deinit();
                message = null;
            } else {
                message.?.read(buffer[0..buffer_len]) catch |err| {
                    std.debug.print("message.read() failed: {any}\n", .{err});
                    break;
                };

                if (message.?.isReady() == false) {
                    continue;
                } else {
                    recreate_message = false;
                }
            }
        }

        if (recreate_message == true) {
            message = Message{ .allocator = self._private.allocator };
            message.?.read(buffer[0..buffer_len]) catch |err| {
                std.debug.print("message.read() failed: {any}\n", .{err});
                continue;
            };
            if (message.?.isReady() == false) {
                continue;
            }
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
            continue;
        }
        if (message.?.isPong() == true) {
            if (onPong != null) {
                onPong.?(self) catch |err| {
                    std.debug.print("onPong() failed: {any}\n", .{err});
                };
            }
            continue;
        }

        const message_data = message.?.get().*;
        if (onMsg != null and message_data != null) {
            onMsg.?(self, message_data.?) catch |err| {
                std.debug.print("onMessage() failed: {any}\n", .{err});
            };
        }
    }

    if (message != null) {
        message.?.deinit();
        message = null;
    }

    if (self._private.close_conn == false) {
        self.deinit();
    }
}

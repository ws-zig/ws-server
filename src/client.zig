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
const Stream = std.net.Stream;
const Address = std.net.Address;
const Allocator = std.mem.Allocator;

const Message = @import("./message.zig").Message;
const Callbacks = @import("./callbacks.zig");

const PrivateFields = struct {
    allocator: *const std.mem.Allocator = undefined,
    stream: ?Stream = null,
    address: ?Address = null,

    close_conn: bool = false,
    conn_closed: bool = false,
};

pub const Client = struct {
    /// Private data that should not be touched.
    _private: PrivateFields = undefined,

    const Self = @This();

    pub fn getAddress(self: *Self) ?Address {
        return self._private.address;
    }

    /// Send a "text" message to this client.
    ///
    /// **IMPORTANT:** The message cannot contain more than 65531 bytes!
    pub fn sendText(self: *Self, data: []const u8) !void {
        var message = Message{ .allocator = self._private.allocator };
        defer message.deinit();
        try message.writeText(data);
        const message_result = message.get().*.?;
        try self._private.stream.?.writeAll(message_result);
    }

    /// Send a "close" message to this client.
    ///
    /// **IMPORTANT:** The connection will only be closed when the client sends this message back.
    pub fn sendClose(self: *Self) !void {
        var message = Message{ .allocator = self._private.allocator };
        defer message.deinit();
        try message.writeClose();
        const message_result = message.get().*.?;
        try self._private.stream.?.writeAll(message_result);
    }

    /// Send a "ping" message to this client. (A "pong" message should come back)
    pub fn sendPing(self: *Self) !void {
        var message = Message{ .allocator = self._private.allocator };
        defer message.deinit();
        try message.writePing();
        const message_result = message.get().*.?;
        try self._private.stream.?.writeAll(message_result);
    }

    /// Send a "pong" message to this client. (Send this pong message if you received a "ping" message from this client)
    pub fn sendPong(self: *Self) !void {
        var message = Message{ .allocator = self._private.allocator };
        defer message.deinit();
        try message.writePong();
        const message_result = message.get().*.?;
        try self._private.stream.?.writeAll(message_result);
    }

    /// Close the connection from this client immediately. (No "close" message is sent to the client!)
    pub fn closeImmediately(self: *Self) void {
        self._deinit();
    }

    fn _deinit(self: *Self) void {
        self._private.close_conn = true;
        if (self._private.stream != null) {
            self._private.stream.?.close();
            self._private.stream = null;
        }
        self._private.conn_closed = true;
    }
};

pub const handshake = @import("./handshake.zig").handle;

pub fn handle(self: *Client, cbs: *const Callbacks.ClientCallbacks) !void {
    var message: ?Message = null;
    defer if (message != null) {
        message.?.deinit();
        message = null;
    };

    while (self._private.close_conn == false) {
        var buffer: [65535]u8 = undefined;
        const buffer_len = self._private.stream.?.read(&buffer) catch |err| {
            cbs.error_.handle(self, err, null);
            break;
        };

        if (message == null) {
            message = Message{ .allocator = self._private.allocator };
        }
        message.?.read(buffer[0..buffer_len]) catch |err| {
            cbs.error_.handle(self, err, null);
            break;
        };

        // Tells us if the message has all the data and can now be processed.
        if (message.?.isReady() == false) {
            continue;
        }

        // The client sends us a "close" message, so he wants to disconnect properly.
        if (message.?.isClose() == true) {
            cbs.close.handle(self);
            break;
        }
        // "Hello server, are you there?"
        if (message.?.isPing() == true) {
            cbs.ping.handle(self);
        }
        // "Hello server, here I am"
        else if (message.?.isPong() == true) {
            cbs.pong.handle(self);
        }
        // Process received message...
        else {
            cbs.text.handle(self, message.?.get().*.?);
        }

        // We need to deinitialize the message and set the value to `null`,
        // otherwise the next loop will not create a new message and write the new data into the old message.
        message.?.deinit();
        message = null;
    }

    cbs.disconnect.handle(self);

    if (self._private.close_conn == false) {
        self._deinit();
    }
}

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
const OsReadError = std.os.ReadError;

const MessageFile = @import("./message.zig");
const Message = MessageFile.Message;
const MessageType = MessageFile.Type;
const CallbacksFile = @import("./callbacks.zig");

const PrivateFields = struct {
    allocator: *const std.mem.Allocator,
    connection: std.net.Server.Connection,
    compression: bool,
    max_msg_size: usize,

    // true = Connection is closed by the server. Breaks the message loop.
    close_conn: bool = false,
};

pub const Client = struct {
    /// Private data that should not be touched.
    _private: PrivateFields,

    const Self = @This();

    // Get the clients address.
    pub inline fn getAddress(self: *const Self) std.net.Address {
        return self._private.connection.address;
    }

    fn _writeAll(self: *const Self, data: []const u8) anyerror!bool {
        self._private.connection.stream.writeAll(data) catch |err| {
            // The connection was closed by the client.
            if (err == error.ConnectionResetByPeer) {
                return false;
            }
            return err;
        };
        return true;
    }

    fn _sendAll(self: *const Self, comptime type_: MessageType, comptime last_msg: bool, data: []const u8) anyerror!bool {
        var message: Message = .{ .allocator = self._private.allocator };
        defer message.deinit();

        message.setType(type_);
        message.setLastMessage(last_msg);
        try message.write(data, self._private.compression);
        return try self._writeAll(message.get().?);
    }

    fn _send(self: *const Self, comptime type_: MessageType, data: []const u8) anyerror!void {
        if (data.len <= 65531) {
            _ = try self._sendAll(type_, true, data);
            return;
        }

        var message_idx: usize = 0;
        while (true) {
            var message_result = false;

            if (message_idx > 0) {
                const data_left: usize = data.len - message_idx;
                const start_message_idx = message_idx;

                if (data_left > 65531) {
                    message_idx += 65531;
                    message_result = try self._sendAll(MessageType.Continue, false, data[start_message_idx..message_idx]);
                } else {
                    message_idx += data_left;
                    message_result = try self._sendAll(MessageType.Continue, true, data[start_message_idx..message_idx]);
                }
            } else {
                message_idx += 65531;
                message_result = try self._sendAll(type_, false, data[0..message_idx]);
            }

            // The message could not be sent.
            // Stop here as the result will only be
            // `false` if the client is disconnected.
            if (message_result == false) {
                break;
            }

            // All data has been sent.
            if (data.len <= message_idx) {
                break;
            }
        }
    }

    /// Send a "text" message to this client.
    pub fn textAll(self: *const Self, data: []const u8) anyerror!void {
        _ = try self._sendAll(MessageType.Text, true, data);
    }

    /// Send a "text" message to this client in 65535 byte chunks.
    pub fn text(self: *const Self, data: []const u8) anyerror!void {
        try self._send(MessageType.Text, data);
    }

    /// Send a "binary" message to this client.
    pub fn binaryAll(self: *const Self, data: []const u8) anyerror!void {
        _ = try self._sendAll(MessageType.Binary, true, data);
    }

    /// Send a "binary" message to this client in 65535 byte chunks.
    pub fn binary(self: *const Self, data: []const u8) anyerror!void {
        try self._send(MessageType.Binary, data);
    }

    /// Send a "close" message to this client.
    ///
    /// **IMPORTANT:** The connection will only be closed when the client sends this message back.
    pub fn close(self: *const Self) anyerror!void {
        _ = try self._sendAll(MessageType.Close, true, "");
    }

    /// Send a "ping" message to this client. (A "pong" message should come back)
    pub fn ping(self: *const Self) anyerror!void {
        _ = try self._sendAll(MessageType.Ping, true, "");
    }

    /// Send a "pong" message to this client. (Send this pong message if you received a "ping" message from this client)
    pub fn pong(self: *const Self) anyerror!void {
        _ = try self._sendAll(MessageType.Pong, true, "");
    }

    /// Close the connection from this client immediately. (No "close" message is sent to the client!)
    pub fn closeImmediately(self: *Self) void {
        self._private.close_conn = true;
    }

    fn _deinit(self: *Self) void {
        self._private.connection.stream.close();
        self.* = undefined;
    }
};

pub fn handle(self: *Client, msg_buffer_size: usize, cbs: *const CallbacksFile.Callbacks) anyerror!void {
    var message: ?Message = null;
    defer {
        if (message != null) {
            message.?.deinit();
            message = null;
        }
        cbs.disconnect.handle(self);
        self._deinit();
    }

    while (self._private.close_conn == false) {
        var buffer: []u8 = try self._private.allocator.alloc(u8, msg_buffer_size);
        defer self._private.allocator.free(buffer);
        const buffer_len = self._private.connection.stream.read(buffer) catch |err| {
            switch (err) {
                // The connection was not closed properly by this client.
                OsReadError.ConnectionResetByPeer, OsReadError.ConnectionTimedOut, OsReadError.SocketNotConnected => return,
                // Something went wrong ...
                else => return err,
            }
        };

        if (message == null) {
            message = .{ .allocator = self._private.allocator, .max_msg_size = self._private.max_msg_size };
        }
        try message.?.read(buffer[0..buffer_len]);

        // Check whether the message is now complete.
        if (message.?.isLastMessage() == false) {
            switch (message.?.getType().?) {
                // Should contain no data and therefore be the last message.
                MessageType.Continue, MessageType.Close, MessageType.Ping, MessageType.Pong => return error.LastMessageExpected,
                inline else => {},
            }
            continue;
        }

        switch (message.?.getType().?) {
            MessageType.Continue => { // Should never happen.
                // The message type should not be "Continue".
                return error.MessageTypeContinue;
            },
            MessageType.Text => { // Process received text message...
                cbs.text.handle(self, message.?.get());
            },
            MessageType.Binary => { // Process received binary message...
                cbs.binary.handle(self, message.?.get());
            },
            MessageType.Close => { // The client sends us a "close" message, so he wants to disconnect properly.
                cbs.close.handle(self);
                return;
            },
            MessageType.Ping => { // "Hello server, are you there?"
                cbs.ping.handle(self);
            },
            MessageType.Pong => { // "Hello server, here I am"
                cbs.pong.handle(self);
            },
        }

        // We need to deinitialize the message and set the value to `null`,
        // otherwise the next loop will not create a new message and write the new data into the old message.
        message.?.deinit();
        message = null;
    }
}

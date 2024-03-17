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
const Callbacks = CallbacksFile.Callbacks;

pub const CloseCodes = enum(u16) {
    Normal = 1000,
    GoingAway = 1001,
    ProtocolError = 1002,
    Unsupported = 1003,
    _Reserved1 = 1004,
    NoStatus = 1005,
    Abnormal = 1006,
    UnsupportedPayload = 1007,
    PolicyViolation = 1008,
    TooLarge = 1009,
    MandatoryExtension = 1010,
    ServerError = 1011,
    ServiceRestart = 1012,
    TryAgainLater = 1013,
    BadGateway = 1014,
    TlsHandshakeFail = 1015,
};

const PrivateFields = struct {
    allocator: *const std.mem.Allocator,
    connection: std.net.Server.Connection,
    // This value was set by the server configuration.
    // true = Send data compressed; false = Send data uncompressed
    compression: bool,
    // This value was set by the server configuration.
    max_msg_size: usize,

    messages: std.ArrayList(?Message) = undefined,

    // true = Stop the message receiving loop
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

    fn _sendAll(
        self: *const Self,
        type_: MessageType,
        last_msg: bool,
        compression: bool,
        data: []const u8,
    ) anyerror!bool {
        var message: Message = .{ .allocator = self._private.allocator };
        defer message.deinit();

        message.setType(type_);
        message.setLastMessage(last_msg);
        try message.write(data, compression);
        return try self._writeAll(message.get().?);
    }

    fn _send(self: *const Self, type_: MessageType, data: []const u8) anyerror!bool {
        if (data.len <= 65531) {
            return try self._sendAll(type_, true, self._private.compression, data);
        }

        var data_iter = std.mem.window(u8, data, 65531, 65531);
        while (data_iter.next()) |item| {
            const item_type = if (data_iter.index == 65531) type_ else MessageType.Continue;
            const last_item = data_iter.index == null;

            const send_result = try self._sendAll(
                item_type,
                last_item,
                self._private.compression,
                item,
            );

            if (send_result == false) {
                // Stop here as the result will only be
                // `false` if the client is disconnected.
                return false;
            }
        }

        return true;
    }

    /// Send a "text" message to this client.
    pub fn textAll(self: *const Self, data: []const u8) anyerror!bool {
        return try self._sendAll(MessageType.Text, true, self._private.compression, data);
    }

    /// Send a "text" message to this client in 65535 byte chunks.
    pub fn text(self: *const Self, data: []const u8) anyerror!bool {
        return try self._send(MessageType.Text, data);
    }

    /// Send a "binary" message to this client.
    pub fn binaryAll(self: *const Self, data: []const u8) anyerror!bool {
        return try self._sendAll(MessageType.Binary, true, self._private.compression, data);
    }

    /// Send a "binary" message to this client in 65535 byte chunks.
    pub fn binary(self: *const Self, data: []const u8) anyerror!bool {
        return try self._send(MessageType.Binary, data);
    }

    /// Send a "close" message to this client.
    ///
    /// **IMPORTANT:** The connection will only be closed when the client sends this message back.
    pub fn close(self: *const Self) anyerror!bool {
        return try self.closeExpanded(CloseCodes.Normal, null);
    }

    /// Send a custom "close" message to this client.
    ///
    /// **IMPORTANT:** The connection will only be closed when the client sends this message back.
    pub fn closeExpanded(self: *const Self, code: CloseCodes, msg: ?[]const u8) anyerror!bool {
        var data: ?[]u8 = null;
        defer {
            if (data != null) {
                self._private.allocator.free(data.?);
            }
        }

        if (msg != null) {
            data = try self._private.allocator.alloc(u8, (2 + msg.?.len));
            @memcpy(data.?[2..], msg.?);
        } else {
            data = try self._private.allocator.alloc(u8, 2);
        }
        const code_val: u16 = @intFromEnum(code);
        data.?[0] = @intCast((code_val >> 8) & 0b11111111);
        data.?[1] = @intCast(code_val & 0b11111111);

        return try self._sendAll(MessageType.Close, true, false, data.?);
    }

    /// Close the connection from this client immediately. (No "close" message is sent to the client!)
    pub fn closeImmediately(self: *Self) void {
        self._private.close_conn = true;
    }

    /// Send a "ping" message to this client. (A "pong" message should come back)
    pub fn ping(self: *const Self) anyerror!bool {
        return try self._sendAll(MessageType.Ping, true, false, "");
    }

    /// Send a "pong" message to this client. (Send this pong message if you received a "ping" message from this client)
    pub fn pong(self: *const Self) anyerror!bool {
        return try self._sendAll(MessageType.Pong, true, false, "");
    }

    fn _deinit(self: *Self) void {
        self._private.connection.stream.close();
        self._private.messages.deinit();
    }
};

pub fn handle(self: *Client, msg_buffer_size: usize, cbs: *const Callbacks) anyerror!void {
    defer {
        cbs.disconnect.handle(self);
        self._deinit();
    }

    const allocator = self._private.allocator;
    const stream = &self._private.connection.stream;
    const messages = &self._private.messages;

    messages.* = std.ArrayList(?Message).init(allocator.*);

    while (self._private.close_conn == false) {
        var buffer: []u8 = try allocator.alloc(u8, msg_buffer_size);
        defer allocator.free(buffer);
        const buffer_len = stream.read(buffer) catch |err| {
            switch (err) {
                // The connection was not closed properly by this client.
                OsReadError.ConnectionResetByPeer, OsReadError.ConnectionTimedOut, OsReadError.SocketNotConnected => return,
                // Something went wrong ...
                else => return err,
            }
        };

        _bytesToMessage(allocator, buffer[0..buffer_len], messages, self._private.max_msg_size) catch |err| {
            cbs.error_.handle(self, &.{ ._error = err, ._location = @src() });
            return;
        };

        _handleMessages(self, messages, cbs) catch |err| {
            if (err != error.BreakLoop) {
                cbs.error_.handle(self, &.{ ._error = err, ._location = @src() });
            }
            return;
        };
    }
}

fn _bytesToMessage(allocator: *const Allocator, buffer: []u8, message_list: *std.ArrayList(?Message), max_msg_size: usize) anyerror!void {
    var temp_message: ?Message = null;
    var bytes_read_from: usize = 0;
    while (true) {
        if (temp_message == null) {
            temp_message = .{ .allocator = allocator, .max_msg_size = max_msg_size };
        }
        try temp_message.?.read(buffer[bytes_read_from..]);
        if (temp_message.?.isLastMessage() == false) {
            switch (temp_message.?.getType().?) {
                // Should contain no data and therefore be the last message.
                MessageType.Continue, MessageType.Close, MessageType.Ping, MessageType.Pong => return error.LastMessageExpected,
                // TODO: ?
                inline else => return error.MessageContinuationNotImplemented,
            }
        }

        try message_list.append(temp_message);

        if (temp_message.?.getBytesLeft() == 0) {
            break;
        }
        bytes_read_from = buffer.len - temp_message.?.getBytesLeft();
        temp_message = null;
    }
}

fn _handleMessages(self: *Client, message_list: *std.ArrayList(?Message), cbs: *const Callbacks) anyerror!void {
    defer {
        for (0..message_list.items.len) |idx| {
            if (message_list.items[idx] != null) {
                message_list.items[idx].?.deinit();
            }
        }
        message_list.clearAndFree();
    }

    for (0..message_list.items.len) |idx| {
        const message = &message_list.items[idx];

        switch (message.*.?.getType().?) {
            MessageType.Continue => { // Should never happen.
                // The message type should not be "Continue".
                return error.MessageTypeContinue;
            },
            MessageType.Text => { // Process received text message...
                cbs.text.handle(self, message.*.?.get());
            },
            MessageType.Binary => { // Process received binary message...
                cbs.binary.handle(self, message.*.?.get());
            },
            MessageType.Close => { // The client sends us a "close" message, so he wants to disconnect properly.
                cbs.close.handle(self);
                return error.BreakLoop;
            },
            MessageType.Ping => { // "Hello server, are you there?"
                cbs.ping.handle(self);
            },
            MessageType.Pong => { // "Hello server, here I am"
                cbs.pong.handle(self);
            },
        }

        message.*.?.deinit();
        message.* = null;
    }
}

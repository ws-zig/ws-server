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
const Callbacks = @import("./callbacks.zig");

const PrivateFields = struct {
    allocator: *const std.mem.Allocator,
    connection: std.net.StreamServer.Connection,

    // Breaks the message loop if this is true.
    close_conn: bool = false,
    // Prevent sending messages to the disconnected client.
    conn_closed: bool = false,
};

pub const Client = struct {
    /// Private data that should not be touched.
    _private: PrivateFields,

    const Self = @This();

    // Get the clients address.
    pub inline fn getAddress(self: *const Self) std.net.Address {
        return self._private.connection.address;
    }

    fn _sendAll(self: *const Self, comptime type_: MessageType, data: []const u8) anyerror!void {
        var message = Message{ .allocator = self._private.allocator };
        defer message.deinit();

        try message.write(type_, true, data);
        const message_result = message.get().?;

        // TODO: Find a way to check whether the stream is available or not
        if (self._private.conn_closed == false) {
            try self._private.connection.stream.writeAll(message_result);
        }
    }

    fn _send(self: *const Self, comptime type_: MessageType, data: []const u8) anyerror!void {
        if (data.len <= 65531) {
            return try self._sendAll(type_, data);
        }

        var message_idx: usize = 0;
        while (true) {
            const data_left: usize = data.len - message_idx;
            var message = Message{ .allocator = self._private.allocator };
            defer message.deinit();

            if (message_idx > 0) {
                if (data_left > 65531) {
                    try message.write(MessageType.Continue, false, data[message_idx..(message_idx + 65531)]);
                } else {
                    try message.write(MessageType.Continue, true, data[message_idx..(message_idx + data_left)]);
                }
            } else {
                try message.write(type_, false, data[0..65531]);
            }
            const message_result = message.get().?;

            // TODO: Find a way to check whether the stream is available or not
            if (self._private.conn_closed == false) {
                try self._private.connection.stream.writeAll(message_result);
            }

            message_idx += 65531;
            if (data.len <= message_idx) {
                break;
            }
        }
    }

    /// Send a "text" message to this client.
    pub fn textAll(self: *const Self, data: []const u8) anyerror!void {
        try self._sendAll(MessageType.Text, data);
    }

    /// Send a "text" message to this client in 65535 byte chunks.
    pub fn text(self: *const Self, data: []const u8) anyerror!void {
        try self._send(MessageType.Text, data);
    }

    /// Send a "binary" message to this client.
    pub fn binaryAll(self: *const Self, data: []const u8) anyerror!void {
        try self._sendAll(MessageType.Binary, data);
    }

    /// Send a "binary" message to this client in 65535 byte chunks.
    pub fn binary(self: *const Self, data: []const u8) anyerror!void {
        try self._send(MessageType.Binary, data);
    }

    /// Send a "close" message to this client.
    ///
    /// **IMPORTANT:** The connection will only be closed when the client sends this message back.
    pub fn close(self: *const Self) anyerror!void {
        try self._send(MessageType.Close, "");
    }

    /// Send a "ping" message to this client. (A "pong" message should come back)
    pub fn ping(self: *const Self) anyerror!void {
        try self._send(MessageType.Ping, "");
    }

    /// Send a "pong" message to this client. (Send this pong message if you received a "ping" message from this client)
    pub fn pong(self: *const Self) anyerror!void {
        try self._send(MessageType.Pong, "");
    }

    /// Close the connection from this client immediately. (No "close" message is sent to the client!)
    pub fn closeImmediately(self: *Self) void {
        self._private.close_conn = true;
    }

    fn _deinit(self: *Self) void {
        self._private.connection.stream.close();

        self._private.conn_closed = true;
    }
};

pub const handshake = @import("./handshake.zig").handle;

pub fn handle(self: *Client, buffer_size: usize, cbs: *const Callbacks.ClientCallbacks) void {
    var message: ?Message = null;
    defer if (message != null) {
        message.?.deinit();
        message = null;
    };

    message_loop: while (self._private.close_conn == false) {
        var buffer: []u8 = self._private.allocator.alloc(u8, buffer_size) catch |err| {
            cbs.error_.handle(self, err, @src());
            break :message_loop;
        };
        defer self._private.allocator.free(buffer);
        const buffer_len = self._private.connection.stream.read(buffer) catch |err| {
            switch (err) {
                // The connection was not closed properly by this client.
                OsReadError.NetNameDeleted, OsReadError.ConnectionTimedOut, OsReadError.ConnectionResetByPeer => {
                    // There is currently no way to check if the stream is closed,
                    // so we set this variable to `true` and prevent an error from being thrown.
                    self._private.conn_closed = true;
                },
                // Something went wrong ...
                else => cbs.error_.handle(self, err, @src()),
            }
            break :message_loop;
        };

        if (message == null) {
            message = Message{ .allocator = self._private.allocator };
        }
        message.?.read(buffer[0..buffer_len]) catch |err| {
            cbs.error_.handle(self, err, @src());
            break :message_loop;
        };

        // Tells us if the message has all the data and can now be processed.
        if (message.?.isReady() == false) {
            continue :message_loop;
        }

        switch (message.?.getType()) {
            MessageType.Continue => { // We are waiting for more data...
                continue :message_loop;
            },
            MessageType.Text => { // Process received text message...
                cbs.text.handle(self, message.?.get());
            },
            MessageType.Binary => { // Process received binary message...
                cbs.binary.handle(self, message.?.get());
            },
            MessageType.Close => { // The client sends us a "close" message, so he wants to disconnect properly.
                cbs.close.handle(self);
                break :message_loop;
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

    self._deinit();
    cbs.disconnect.handle(self);
}

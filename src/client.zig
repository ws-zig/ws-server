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
const Mutex = std.Thread.Mutex;
const Stream = std.net.Stream;
const Address = std.net.Address;
const Allocator = std.mem.Allocator;

const MessageFile = @import("./message.zig");
const Message = MessageFile.Message;
const MessageType = MessageFile.Type;
const Callbacks = @import("./callbacks.zig");

const PrivateFields = struct {
    allocator: *const std.mem.Allocator = undefined,
    stream: ?Stream = null,
    address: ?Address = null,

    // A security measure.
    mutex: Mutex = Mutex{},

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
    pub fn sendText(self: *Self, data: []const u8) anyerror!void {
        var message = Message{ .allocator = self._private.allocator };
        defer message.deinit();
        try message.writeText(data);
        const message_result = message.get().*.?;

        self._private.mutex.lock();
        defer self._private.mutex.unlock();

        if (self._private.stream) |stream| {
            try stream.writeAll(message_result);
        }
    }

    /// Send a "close" message to this client.
    ///
    /// **IMPORTANT:** The connection will only be closed when the client sends this message back.
    pub fn sendClose(self: *Self) anyerror!void {
        var message = Message{ .allocator = self._private.allocator };
        defer message.deinit();
        try message.writeClose();
        const message_result = message.get().*.?;

        self._private.mutex.lock();
        defer self._private.mutex.unlock();

        if (self._private.stream) |stream| {
            try stream.writeAll(message_result);
        }
    }

    /// Send a "ping" message to this client. (A "pong" message should come back)
    pub fn sendPing(self: *Self) anyerror!void {
        var message = Message{ .allocator = self._private.allocator };
        defer message.deinit();
        try message.writePing();
        const message_result = message.get().*.?;

        self._private.mutex.lock();
        defer self._private.mutex.unlock();

        if (self._private.stream) |stream| {
            try stream.writeAll(message_result);
        }
    }

    /// Send a "pong" message to this client. (Send this pong message if you received a "ping" message from this client)
    pub fn sendPong(self: *Self) anyerror!void {
        var message = Message{ .allocator = self._private.allocator };
        defer message.deinit();
        try message.writePong();
        const message_result = message.get().*.?;

        self._private.mutex.lock();
        defer self._private.mutex.unlock();

        if (self._private.stream) |stream| {
            try stream.writeAll(message_result);
        }
    }

    /// Close the connection from this client immediately. (No "close" message is sent to the client!)
    pub fn closeImmediately(self: *Self) void {
        self._deinit();
    }

    fn _deinit(self: *Self) void {
        self._private.close_conn = true;
        self._private.mutex.lock();
        defer self._private.mutex.unlock();
        if (self._private.stream != null) {
            self._private.stream.?.close();
            self._private.stream = null;
        }
        self._private.conn_closed = true;
    }
};

pub const handshake = @import("./handshake.zig").handle;

pub fn handle(self: *Client, buffer_size: u32, cbs: *const Callbacks.ClientCallbacks) anyerror!void {
    var message: ?Message = null;
    defer if (message != null) {
        message.?.deinit();
        message = null;
    };

    messageLoop: while (self._private.close_conn == false) {
        var buffer: []u8 = try self._private.allocator.alloc(u8, buffer_size);
        defer self._private.allocator.free(buffer);
        const buffer_len = self._private.stream.?.read(buffer) catch |err| {
            cbs.error_.handle(self, err, @src());
            break;
        };

        if (message == null) {
            message = Message{ .allocator = self._private.allocator };
        }
        message.?.read(buffer[0..buffer_len]) catch |err| {
            cbs.error_.handle(self, err, @src());
            break;
        };

        // Tells us if the message has all the data and can now be processed.
        if (message.?.isReady() == false) {
            continue;
        }

        switch (message.?.getType()) {
            MessageType.Unknown => {
                cbs.error_.handle(self, error.UnkownMessageType, @src());
                break :messageLoop;
            },
            MessageType.Continue => { // We are waiting for more data...
                continue :messageLoop;
            },
            MessageType.Text => { // Process received text message...
                cbs.text.handle(self, message.?.get().*.?);
            },
            MessageType.Binary => { // Process received binary message...
                cbs.text.handle(self, message.?.get().*.?);
            },
            MessageType.Close => { // The client sends us a "close" message, so he wants to disconnect properly.
                cbs.close.handle(self);
                break :messageLoop;
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

    cbs.disconnect.handle(self);

    if (self._private.conn_closed == false) {
        self._deinit();
    }
}

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
const net = std.net;
const Allocator = std.mem.Allocator;

const ClientFile = @import("./client.zig");
const Callbacks = @import("./callbacks.zig");

const PrivateFields = struct {
    allocator: *const Allocator = undefined,
    addr: ?[]const u8 = null,
    port: u16 = 8080,

    onMessage: Callbacks.ServerOnMessage = null,
    onClose: Callbacks.ServerOnClose = null,
    onPing: Callbacks.ServerOnPing = null,
    onPong: Callbacks.ServerOnPong = null,
};

pub const Server = struct {
    /// Private data that should not be touched.
    _private: PrivateFields = undefined,

    const Self = @This();

    pub fn create(allocator: *const Allocator, addr: []const u8, port: u16) Self {
        return Self{ ._private = .{ .allocator = allocator, .addr = addr, .port = port } };
    }

    pub fn listen(self: *Self) !void {
        if (self._private.allocator == undefined) {
            return error.MissingAllocator;
        }
        if (self._private.addr == null) {
            return error.MissingAddress;
        }

        const address = try net.Address.parseIp(self._private.addr.?, self._private.port);
        var server = net.StreamServer.init(.{});
        defer server.deinit();
        try server.listen(address);
        std.debug.print("Listen at {any}\n", .{address.in});

        while (true) {
            const connection = try server.accept();
            const thread = try std.Thread.spawn(.{}, _handleClient, .{ self, connection.stream });
            thread.detach();
        }
    }

    fn _handleClient(self: *Self, stream: net.Stream) void {
        var client = ClientFile.Client{ ._private = .{ .allocator = self._private.allocator, .stream = stream } };
        ClientFile.handshake(&client) catch |err| {
            std.debug.print("Handshake failed: {any}\n", .{err});
            client.closeImmediately();
            return;
        };
        ClientFile.handle(&client, self._private.onMessage, self._private.onClose, self._private.onPing, self._private.onPong) catch |err| {
            std.debug.print("something went wrong: {any}\n", .{err});
        };
    }

    /// Set a callback when a "text" message is received from the client.
    ///
    /// ### Example
    /// ```zig
    /// fn _onMessage(client: *Client, data: []const u8) anyerror!void {
    ///     // ...
    /// }
    /// // ...
    /// server.onMessage(&_onMessage);
    /// // ...
    /// ```
    pub fn onMessage(self: *Self, cb: Callbacks.ServerOnMessage) void {
        self._private.onMessage = cb;
    }

    /// Set a callback when a "close" message is received from the client.
    ///
    /// ### Example
    /// ```zig
    /// fn _onClose(client: *Client) anyerror!void {
    ///     // ...
    /// }
    /// // ...
    /// server.onClose(&_onClose);
    /// // ...
    /// ```
    pub fn onClose(self: *Self, cb: Callbacks.ServerOnClose) void {
        self._private.onClose = cb;
    }

    /// Set a callback when a "ping" message is received from the client.
    ///
    /// ### Example
    /// ```zig
    /// fn _onPing(client: *Client) anyerror!void {
    ///     // ...
    /// }
    /// // ...
    /// server.onPing(&_onPing);
    /// // ...
    /// ```
    pub fn onPing(self: *Self, cb: Callbacks.ServerOnPing) void {
        self._private.onPing = cb;
    }

    /// Set a callback when a "pong" message is received from the client.
    ///
    /// ### Example
    /// ```zig
    /// fn _onPong(_: *Client) anyerror!void {
    ///     // ...
    /// }
    /// // ...
    /// server.onPong(&_onPong);
    /// // ...
    /// ```
    pub fn onPong(self: *Self, cb: Callbacks.ServerOnPong) void {
        self._private.onPong = cb;
    }
};

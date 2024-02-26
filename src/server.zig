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

    config: ServerConfig = ServerConfig{},

    clientCallbacks: Callbacks.ClientCallbacks = Callbacks.ClientCallbacks{},
};

pub const ServerConfig = struct {
    buffer_size: u32 = 65535,
};

pub const Server = struct {
    /// Private data that should not be touched.
    _private: PrivateFields = undefined,

    const Self = @This();

    pub fn create(allocator: *const Allocator, addr: []const u8, port: u16) Self {
        return Self{ ._private = .{ .allocator = allocator, .addr = addr, .port = port } };
    }

    pub fn setConfig(self: *Self, config: ServerConfig) void {
        self._private.config = config;
    }

    pub fn listen(self: *Self) anyerror!void {
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

        while (true) {
            const connection = try server.accept();
            const thread = try std.Thread.spawn(.{}, _handleConnection, .{ self, connection });
            thread.detach();
        }
    }

    fn _handleConnection(self: *const Self, connection: net.StreamServer.Connection) void {
        var client = ClientFile.Client{ ._private = .{ .allocator = self._private.allocator, .stream = connection.stream, .address = connection.address } };
        const handshake_result = ClientFile.handshake(&client, &self._private.clientCallbacks) catch |err| {
            self._private.clientCallbacks.error_.handle(&client, err, @src());
            client.closeImmediately();
            return;
        };
        if (handshake_result == false) {
            client.closeImmediately();
            return;
        }
        ClientFile.handle(&client, self._private.config.buffer_size, &self._private.clientCallbacks) catch |err| {
            std.debug.print("something went wrong: {any}\n", .{err});
        };
    }

    /// This function is called whenever a new connection to the server is established.
    ///
    /// **IMPORTANT:** Return `false` and the connection will be closed immediately.
    ///
    /// ### Example
    /// ```zig
    /// fn _onHandshake(client: *Client, headers: *std.StringHashMap([]const u8)) anyerror!bool {
    ///     // ...
    /// }
    /// // ...
    /// server.onHandshake(&_onHandshake);
    /// // ...
    /// ```
    pub fn onHandshake(self: *Self, cb: Callbacks.ClientHandshakeFn) void {
        self._private.clientCallbacks.handshake.handler = cb;
    }

    /// This function is always called shortly before the connection to the client is closed.
    ///
    /// ### Example
    /// ```zig
    /// fn _onDisconnect(client: *Client) anyerror!void {
    ///     // ...
    /// }
    /// // ...
    /// server.onDisconnect(&_onDisconnect);
    /// // ...
    /// ```
    pub fn onDisconnect(self: *Self, cb: Callbacks.ClientDisconnectFn) void {
        self._private.clientCallbacks.disconnect.handler = cb;
    }

    /// This function is called whenever an unexpected error occurs.
    ///
    /// ### Example
    /// ```zig
    /// fn _onError(client: *Client, type_: anyerror, data: ?[]const u8) anyerror!void {
    ///     // ...
    /// }
    /// // ...
    /// server.onError(&_onError);
    /// // ...
    /// ```
    pub fn onError(self: *Self, cb: Callbacks.ClientErrorFn) void {
        self._private.clientCallbacks.error_.handler = cb;
    }

    /// Set a callback when a "text" message is received from the client.
    ///
    /// ### Example
    /// ```zig
    /// fn _onText(client: *Client, data: []const u8) anyerror!void {
    ///     // ...
    /// }
    /// // ...
    /// server.onText(&_onText);
    /// // ...
    /// ```
    pub fn onText(self: *Self, cb: Callbacks.ClientTextFn) void {
        self._private.clientCallbacks.text.handler = cb;
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
    pub fn onClose(self: *Self, cb: Callbacks.ClientCloseFn) void {
        self._private.clientCallbacks.close.handler = cb;
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
    pub fn onPing(self: *Self, cb: Callbacks.ClientPingFn) void {
        self._private.clientCallbacks.ping.handler = cb;
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
    pub fn onPong(self: *Self, cb: Callbacks.ClientPongFn) void {
        self._private.clientCallbacks.pong.handler = cb;
    }
};

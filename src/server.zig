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

const Utils = @import("./utils/lib.zig");
const ConfigFile = @import("./config.zig");
const Config = ConfigFile.Config;
const ClientFile = @import("./client.zig");
const Client = ClientFile.Client;
const HandshakeFile = @import("./handshake.zig");
const Handshake = HandshakeFile.Handshake;
const CallbacksFile = @import("./callbacks.zig");
const Callbacks = CallbacksFile.Callbacks;

const PrivateFields = struct {
    allocator: *const Allocator,
    addr: []const u8,
    port: u16,

    config: Config = .{},

    callbacks: Callbacks = .{},
};

pub const Server = struct {
    /// Private data that should not be touched.
    _private: PrivateFields,

    const Self = @This();

    /// Create a new server to connect to.
    pub fn create(allocator: *const Allocator, addr: []const u8, port: u16) Self {
        return .{ ._private = .{ .allocator = allocator, .addr = addr, .port = port } };
    }

    /// Set advanced settings.
    pub fn setConfig(self: *Self, config: Config) void {
        self._private.config = config;
    }

    /// Listen (run) the server.
    pub fn listen(self: *Self) anyerror!void {
        if (self._private.config.read_buffer_size > 65535) {
            if (Utils.CPU.is64bit() == false) {
                // On non-64-bit architectures,
                // you cannot process messages larger than 65535 bytes.
                // To prevent unexpected behavior, the size of the buffer should be reduced.
                return error.MsgBufferSizeExceeded;
            }
        }
        if (self._private.config.max_msg_size < self._private.config.read_buffer_size) {
            // The `max_msg_size` must equal to or be larger than `read_buffer_size`.
            return error.MaxMsgSizeTooLow;
        }

        const address: net.Address = try net.Address.parseIp(self._private.addr, self._private.port);
        var server: net.Server = try address.listen(.{});
        defer server.deinit();

        while (true) {
            const connection: net.Server.Connection = server.accept() catch |e| {
                self._private.callbacks.err.handle(null, &.{ ._error = e, ._location = @src() });
                continue;
            };
            const thread: std.Thread = std.Thread.spawn(.{}, _handleConnection, .{ self, connection }) catch |e| {
                self._private.callbacks.err.handle(null, &.{ ._error = e, ._location = @src() });
                continue;
            };
            thread.detach();
        }
    }

    fn _handleConnection(self: *const Self, connection: net.Server.Connection) void {
        var client: Client = .{
            ._private = .{
                .allocator = self._private.allocator,
                .connection = connection,
                .compression = self._private.config.experimental.compression,
                .max_msg_size = self._private.config.max_msg_size,
            },
        };
        var handshake: Handshake = .{
            .client = &client,
            .cbs = &self._private.callbacks,
        };
        const handshake_result = handshake.handle() catch |e| {
            self._private.callbacks.err.handle(&client, &.{ ._error = e, ._location = @src() });
            return;
        };
        if (handshake_result == true) {
            ClientFile.handle(&client, self._private.config.read_buffer_size, &self._private.callbacks) catch |e| {
                self._private.callbacks.err.handle(&client, &.{ ._error = e, ._location = @src() });
                return;
            };
        }
    }

    /// This function is called whenever a new connection to the server is established.
    ///
    /// **IMPORTANT:** Return `false` and the connection will be closed immediately.
    ///
    /// ### Example
    /// ```zig
    /// fn _onHandshake(client: *Client, headers: *const std.StringHashMap([]const u8)) anyerror!bool {
    ///     // ...
    /// }
    /// // ...
    /// server.onHandshake(&_onHandshake);
    /// // ...
    /// ```
    pub fn onHandshake(self: *Self, cb: CallbacksFile.HandshakeFn) void {
        self._private.callbacks.handshake.handler = cb;
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
    pub fn onDisconnect(self: *Self, cb: CallbacksFile.Fn) void {
        self._private.callbacks.disconnect.handler = cb;
    }

    /// This function is called whenever an unexpected error occurs.
    ///
    /// ### Example
    /// ```zig
    /// fn _onError(client: ?*Client, info: *const Error) anyerror!void {
    ///     // ...
    /// }
    /// // ...
    /// server.onError(&_onError);
    /// // ...
    /// ```
    pub fn onError(self: *Self, cb: CallbacksFile.ErrorFn) void {
        self._private.callbacks.err.handler = cb;
    }

    /// Set a callback when a "text" message is received from the client.
    ///
    /// ### Example
    /// ```zig
    /// fn _onText(client: *Client, data: &[]const u8) anyerror!void {
    ///     // ...
    /// }
    /// // ...
    /// server.onText(&_onText);
    /// // ...
    /// ```
    pub fn onText(self: *Self, cb: CallbacksFile.OStrFn) void {
        self._private.callbacks.text.handler = cb;
    }

    /// Set a callback when a "binary" message is received from the client.
    ///
    /// ### Example
    /// ```zig
    /// fn _onBinary(client: *Client, data: &[]const u8) anyerror!void {
    ///     // ...
    /// }
    /// // ...
    /// server.onBinary(&_onBinary);
    /// // ...
    /// ```
    pub fn onBinary(self: *Self, cb: CallbacksFile.OStrFn) void {
        self._private.callbacks.binary.handler = cb;
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
    pub fn onClose(self: *Self, cb: CallbacksFile.Fn) void {
        self._private.callbacks.close.handler = cb;
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
    pub fn onPing(self: *Self, cb: CallbacksFile.Fn) void {
        self._private.callbacks.ping.handler = cb;
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
    pub fn onPong(self: *Self, cb: CallbacksFile.Fn) void {
        self._private.callbacks.pong.handler = cb;
    }
};

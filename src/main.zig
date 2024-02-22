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
const Thread = std.Thread;

pub const Client = @import("./client.zig").Client;
const Message = @import("./message.zig").Message;
const Callbacks = @import("./callbacks.zig");

pub const Server = struct {
    /// @SELFONLY
    _allocator: *const Allocator = undefined,
    /// @SELFONLY
    _addr: []const u8 = undefined,
    /// @SELFONLY
    _port: u16 = 8080,

    /// @SELFONLY
    _onMessage: Callbacks.ServerOnMessage = undefined,

    const Self = @This();

    pub fn create(allocator: *const Allocator, addr: []const u8, port: u16) Self {
        return Self{ ._allocator = allocator, ._addr = addr, ._port = port };
    }

    pub fn listen(self: *Self) !void {
        const address = try net.Address.parseIp(self._addr, self._port);
        var server = net.StreamServer.init(.{});
        defer server.deinit();
        try server.listen(address);
        std.debug.print("Listen at {any}\n", .{address.in});

        while (true) {
            const connection = try server.accept();
            const thread = try Thread.spawn(.{}, _handleClient, .{ self, connection.stream, self._onMessage });
            thread.detach();
        }
    }

    fn _handleClient(self: *Self, stream: net.Stream, cb: Callbacks.ServerOnMessage) void {
        var client = Client{ .allocator = self._allocator, .stream = stream };
        client.handshake() catch |err| {
            std.debug.print("Handshake failed: {any}\n", .{err});
            client.closeConn();
            return;
        };
        client.handle(cb) catch |err| {
            std.debug.print("something went wrong: {any}\n", .{err});
        };
    }

    pub fn onMessage(self: *Self, cb: Callbacks.ServerOnMessage) void {
        self._onMessage = cb;
    }
};

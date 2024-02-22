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
const Message = @import("./message.zig").Message;
const Callbacks = @import("./callbacks.zig");

const PrivateFields = struct {
    allocator: *const Allocator = undefined,
    addr: ?[]const u8 = null,
    port: u16 = 8080,

    onMessage: Callbacks.ServerOnMessage = null,
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
            const thread = try std.Thread.spawn(.{}, _handleClient, .{ self, connection.stream, self._private.onMessage });
            thread.detach();
        }
    }

    fn _handleClient(self: *Self, stream: net.Stream, cb: Callbacks.ServerOnMessage) void {
        var client = ClientFile.Client{ ._private = .{ .allocator = self._private.allocator, .stream = stream } };
        ClientFile.handshake(&client) catch |err| {
            std.debug.print("Handshake failed: {any}\n", .{err});
            client.closeConn();
            return;
        };
        ClientFile.handle(&client, cb) catch |err| {
            std.debug.print("something went wrong: {any}\n", .{err});
        };
    }

    pub fn onMessage(self: *Self, cb: Callbacks.ServerOnMessage) void {
        self._private.onMessage = cb;
    }
};

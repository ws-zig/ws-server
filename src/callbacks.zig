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
const SourceLocation = std.builtin.SourceLocation;

const Client = @import("./client.zig").Client;

pub const ClientHandshakeFn = ?*const fn (client: *Client, headers: *const std.StringHashMap([]const u8)) anyerror!bool;
pub const ClientDisconnectFn = ?*const fn (client: *Client) anyerror!void;
pub const ClientErrorFn = ?*const fn (client: *Client, type_: anyerror, loc: SourceLocation) anyerror!void;

pub const ClientTextFn = ?*const fn (client: *Client, data: ?[]const u8) anyerror!void;
pub const ClientBinaryFn = ?*const fn (client: *Client, data: ?[]const u8) anyerror!void;
pub const ClientCloseFn = ?*const fn (client: *Client) anyerror!void;
pub const ClientPingFn = ?*const fn (client: *Client) anyerror!void;
pub const ClientPongFn = ?*const fn (client: *Client) anyerror!void;

pub const ClientCallbacks = struct {
    handshake: ClientHandshake = .{},
    disconnect: ClientDisconnect = .{},
    error_: ClientError = .{},

    text: ClientText = .{},
    binary: ClientBinary = .{},
    close: ClientClose = .{},
    ping: ClientPing = .{},
    pong: ClientPong = .{},
};

const ClientHandshake = struct {
    handler: ClientHandshakeFn = null,

    const Self = @This();

    pub fn handle(self: *const Self, client: *Client, headers: *const std.StringHashMap([]const u8)) bool {
        if (self.handler != null) {
            const cb_result = self.handler.?(client, headers) catch |err| {
                std.debug.print("Handshake callback failed: {any}\n", .{err});
                return false;
            };
            return cb_result;
        }
        return true;
    }
};

const ClientDisconnect = struct {
    handler: ClientDisconnectFn = null,

    const Self = @This();

    pub fn handle(self: *const Self, client: *Client) void {
        if (self.handler != null) {
            self.handler.?(client) catch |err| {
                std.debug.print("Disconnect callback failed: {any}\n", .{err});
            };
        }
    }
};

const ClientError = struct {
    handler: ClientErrorFn = null,

    const Self = @This();

    pub fn handle(self: *const Self, client: *Client, type_: anyerror, loc: SourceLocation) void {
        if (self.handler != null) {
            self.handler.?(client, type_, loc) catch |err| {
                std.debug.print("Error callback failed: {any}\n", .{err});
            };
        }
    }
};

const ClientText = struct {
    handler: ClientTextFn = null,

    const Self = @This();

    pub fn handle(self: *const Self, client: *Client, data: ?[]const u8) void {
        if (self.handler != null) {
            self.handler.?(client, data) catch |err| {
                std.debug.print("Text callback failed: {any}\n", .{err});
            };
        }
    }
};

const ClientBinary = struct {
    handler: ClientBinaryFn = null,

    const Self = @This();

    pub fn handle(self: *const Self, client: *Client, data: ?[]const u8) void {
        if (self.handler != null) {
            self.handler.?(client, data) catch |err| {
                std.debug.print("Binary callback failed: {any}\n", .{err});
            };
        }
    }
};

const ClientClose = struct {
    handler: ClientCloseFn = null,

    const Self = @This();

    pub fn handle(self: *const Self, client: *Client) void {
        if (self.handler != null) {
            self.handler.?(client) catch |err| {
                std.debug.print("Close callback failed: {any}\n", .{err});
            };
        }
    }
};

const ClientPing = struct {
    handler: ClientPingFn = null,

    const Self = @This();

    pub fn handle(self: *const Self, client: *Client) void {
        if (self.handler != null) {
            self.handler.?(client) catch |err| {
                std.debug.print("Ping callback failed: {any}\n", .{err});
            };
        }
    }
};

const ClientPong = struct {
    handler: ClientPongFn = null,

    const Self = @This();

    pub fn handle(self: *const Self, client: *Client) void {
        if (self.handler != null) {
            self.handler.?(client) catch |err| {
                std.debug.print("Pong callback failed: {any}\n", .{err});
            };
        }
    }
};

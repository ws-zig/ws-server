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

pub const ClientHandshakeFn = ?*const fn (client: *Client, headers: *std.StringHashMap([]const u8)) anyerror!bool;
pub const ClientDisconnectFn = ?*const fn (client: *Client) anyerror!void;
pub const ClientErrorFn = ?*const fn (client: *Client, type_: anyerror, loc: SourceLocation) anyerror!void;

pub const ClientTextFn = ?*const fn (client: *Client, data: []const u8) anyerror!void;
pub const ClientCloseFn = ?*const fn (client: *Client) anyerror!void;
pub const ClientPingFn = ?*const fn (client: *Client) anyerror!void;
pub const ClientPongFn = ?*const fn (client: *Client) anyerror!void;

pub const ClientCallbacks = struct {
    handshake: ClientHandshake = ClientHandshake{},
    disconnect: ClientDisconnect = ClientDisconnect{},
    error_: ClientError = ClientError{},

    text: ClientText = ClientText{},
    close: ClientClose = ClientClose{},
    ping: ClientPing = ClientPing{},
    pong: ClientPong = ClientPong{},
};

const ClientHandshake = struct {
    handler: ClientHandshakeFn = null,

    const Self = @This();

    pub fn handle(self: *const Self, client: *Client, headers: *std.StringHashMap([]const u8)) bool {
        if (self.handler != null) {
            const cb_result = self.handler.?(client, headers) catch |err| {
                std.debug.print("onHandshake() failed: {any}", .{err});
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
                std.debug.print("onDisconnect() failed: {any}", .{err});
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
                std.debug.print("onError() failed: {any}", .{err});
            };
        }
    }
};

const ClientText = struct {
    handler: ClientTextFn = null,

    const Self = @This();

    pub fn handle(self: *const Self, client: *Client, data: []const u8) void {
        if (self.handler != null) {
            self.handler.?(client, data) catch |err| {
                std.debug.print("onText() failed: {any}", .{err});
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
                std.debug.print("onClose() failed: {any}", .{err});
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
                std.debug.print("onPing() failed: {any}", .{err});
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
                std.debug.print("onPong() failed: {any}", .{err});
            };
        }
    }
};

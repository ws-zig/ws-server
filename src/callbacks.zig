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
const Client = @import("./client.zig").Client;

pub const ClientHandshake = ?*const fn (client: *Client, headers: *std.StringHashMap([]const u8)) anyerror!bool;
pub const ClientDisconnect = ?*const fn (client: *Client) anyerror!void;

pub const ClientText = ?*const fn (client: *Client, data: []const u8) anyerror!void;
pub const ClientClose = ?*const fn (client: *Client) anyerror!void;
pub const ClientPing = ?*const fn (client: *Client) anyerror!void;
pub const ClientPong = ?*const fn (client: *Client) anyerror!void;

pub const ClientCallbacks = struct {
    handshake: ClientHandshake = null,
    disconnect: ClientDisconnect = null,

    text: ClientText = null,
    close: ClientClose = null,
    ping: ClientPing = null,
    pong: ClientPong = null,
};

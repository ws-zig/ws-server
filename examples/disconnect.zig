const std = @import("std");

const ws = @import("ws-server");
const Server = ws.Server;
const Client = ws.Client;

fn _onText(client: *Client, data: ?[]const u8) anyerror!void {
    if (data) |data_result| {
        if (data_result[0] == 'a') {
            // The client should now receive a "close" message, send the same message back to us and the connection should be closed.
            try client.close();
        } else if (data_result[0] == 'b') {
            // The connection is closed immediately without sending a "close" message to the client.
            client.closeImmediately();
        } else {
            // We send a "close" message to the client and without waiting for a response we close the connection.
            try client.close();
            client.closeImmediately();
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var server = Server.create(&allocator, "127.0.0.1", 8080);
    server.onText(&_onText);
    try server.listen();
}

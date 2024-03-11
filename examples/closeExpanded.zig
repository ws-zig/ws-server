const std = @import("std");

const ws = @import("ws-server");
const Server = ws.Server;
const Client = ws.Client;
const CloseCodes = ws.CloseCodes;

// When a text message has been received from the client, this function is called.
fn _onText(client: *Client, data: ?[]const u8) anyerror!void {
    if (data) |data_result| {
        std.debug.print("MESSAGE RECEIVED: {s}\n", .{data_result});
    }
    _ = try client.closeExpanded(CloseCodes.Normal, "Bye :(");
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var server = Server.create(&allocator, "127.0.0.1", 8080);
    server.setConfig(.{
        .msg_buffer_size = 1024,
    });
    server.onText(&_onText);
    try server.listen();
}

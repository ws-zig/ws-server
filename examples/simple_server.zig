const std = @import("std");
const SourceLocation = std.builtin.SourceLocation;

const ws = @import("ws-server");
const Server = ws.Server;
const Client = ws.Client;

// When we have a new client, this function will be called before we can receive a message
// like "text" from this client.
fn _onHandshake(client: *Client, headers: *std.StringHashMap([]const u8)) anyerror!bool {
    std.debug.print("Handshake from ({any}): {s} {s} {s}\n", .{ client.getAddress().?, headers.*.get("method").?, headers.*.get("uri").?, headers.*.get("version").? });
    // Set the return value to false to abort the
    // handshake and immediately disconnect from the client.
    return true;
}

// If something went wrong unexpectedly, you can use this function to view some details of the error.
// After this function call, the connection to the client is immediately terminated.
fn _onError(client: *Client, type_: anyerror, loc: SourceLocation) anyerror!void {
    std.debug.print("[{any}] from `{any}`: {s}({s}):{d}:{d}", .{ type_, client.getAddress().?, loc.file, loc.fn_name, loc.line, loc.column });
}

// When the incoming message loop breaks and the client disconnects, this function is called.
fn _onDisconnect(client: *Client) anyerror!void {
    std.debug.print("Client ({any}) disconnected!\n", .{client.getAddress().?});
}

// When a text message has been received from the client, this function is called.
fn _onText(client: *Client, data: []const u8) anyerror!void {
    std.debug.print("MESSAGE RECEIVED: {s}\n", .{data});
    try client.sendText("Hello client! :)");
}

// When the client has properly closed the connection with a message, this function is called.
fn _onClose(client: *Client) anyerror!void {
    std.debug.print("CLOSE RECEIVED!\n", .{});
    try client.sendClose();
}

// When the client pings this server, this function is called.
fn _onPing(client: *Client) anyerror!void {
    std.debug.print("PING RECEIVED!\n", .{});
    try client.sendPong();
}

// When we get a pong back from the client after a ping, this function is called.
fn _onPong(_: *Client) anyerror!void {
    std.debug.print("PONG RECEIVED!\n", .{});
    // There's nothing to do here.
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var server = Server.create(&allocator, "127.0.0.1", 8080);
    server.setConfig(.{
        .buffer_size = 1024,
    });
    server.onHandshake(&_onHandshake);
    server.onDisconnect(&_onDisconnect);
    server.onError(&_onError);
    server.onText(&_onText);
    server.onClose(&_onClose);
    server.onPing(&_onPing);
    server.onPong(&_onPong);
    try server.listen();
}

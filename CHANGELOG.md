# Changelog
## [v0.2.0](https://github.com/ws-zig/ws-server/tree/v0.2.0) (2024-02-29 UTC+1)
> [!NOTE]
> The current Zig(-lang) version [**0.11.0**](https://github.com/ziglang/zig/releases/tag/0.11.0) is supported.

**Changed**
- `sendText()`
- - This function is now called `text()`. The data is now sent in chunks (65535 bytes each).
- `sendBinary()`
- - This function is now called `binary()`. The data is now sent in chunks (65535 bytes each).
- `sendClose()`
- - This function is now called `close()`.
- `sendPing()`
- - This function is now called `ping()`.
- `sendPong()`
- - This function is now called `pong()`.

**Added**
- Support for sending large messages as multiple small ones.
- - Data longer than 65531 bytes is sent as "chunks", meaning the server sends multiple messages containing parts of the large message with a maximum of 65535 bytes (the client processes the messages as one complete once the last one is received).
- `textAll()`
- - This function replaces the previous `sendText()`.
- `binaryAll()`
- - This function replaces the previous `sendBinary()`.

**Fixed**
- Compiling for 32-bit architectures was not possible and resulted in an error.
- - The `text()` or `binary()` function should be used for 32-bit architectures with more than 65531 bytes of data. Also make sure that no more than 65535 bytes (65531 bytes + frame) are sent from the client at once. Anything over 65535 bytes (65531 bytes + frame) of data requires 64-bit architecture (u64 data type).

**Other**
- General improvements.

## [v0.1.0](https://github.com/ws-zig/ws-server/tree/v0.1.0) (2024-02-27 UTC+1)
> [!NOTE]
> The current Zig(-lang) version [**0.11.0**](https://github.com/ziglang/zig/releases/tag/0.11.0) is supported.

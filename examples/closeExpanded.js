const { WebSocket } = require('ws');
const client = new WebSocket("ws://127.0.0.1:8080", {
    perMessageDeflate: false,
});

client.on('close', (code, msg) => {
    console.log(code); // 1000
    console.log(msg.toString()); // "Bye :("
});

client.on('open', () => {
    client.send("Hello server!");
});
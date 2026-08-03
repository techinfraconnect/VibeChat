const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);

const io = new Server(server, {
  cors: { origin: "*", methods: ["GET", "POST"] }
});

io.on('connection', (socket) => {
  console.log(`🟢 Socket connected: ${socket.id}`);

  socket.on('send_message', (data) => {
    socket.broadcast.emit('receive_message', data);
  });

  // --- CALL HANDSHAKE ---
  socket.on('call_invite', (data) => {
    console.log(`🔔 Call invite from: ${data.callerName}`);
    socket.broadcast.emit('incoming_call', data);
  });

  socket.on('call_accepted', (data) => {
    console.log(`✅ Call accepted`);
    socket.broadcast.emit('call_ready_for_offer', data);
  });

  socket.on('call_rejected', () => {
    console.log(`❌ Call rejected`);
    socket.broadcast.emit('call_rejected');
  });

  // --- WEBRTC RELAYS ---
  socket.on('offer', (data) => {
    socket.broadcast.emit('offer', data);
  });

  socket.on('answer', (data) => {
    socket.broadcast.emit('answer', data);
  });

  socket.on('ice-candidate', (data) => {
    socket.broadcast.emit('ice-candidate', data);
  });

  socket.on('end-call', () => {
    console.log(`📴 Call ended`);
    socket.broadcast.emit('end-call');
  });

  socket.on('disconnect', () => {
    console.log(`🔴 Socket disconnected: ${socket.id}`);
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 VibeChat Server running on port ${PORT}`);
});
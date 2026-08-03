const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: "*" }
});

io.on('connection', (socket) => {
  console.log(`🟢 User connected: ${socket.id}`);

  // Join a unique room based on username or role
  socket.on('register_user', (username) => {
    socket.data.username = username;
    socket.join(username);
    console.log(`👤 User registered and joined room: ${username} (${socket.id})`);
  });

  socket.on('send_message', (data) => {
    io.emit('receive_message', data);
  });

  // Call Handshake (Targeted to specific user or broadcasted reliably)
  socket.on('call_invite', (data) => {
    console.log(`🔔 Call invite received from ${data.callerName} targeting ${data.targetUser}`);
    if (data.targetUser) {
      io.to(data.targetUser).emit('incoming_call', data);
    } else {
      socket.broadcast.emit('incoming_call', data);
    }
  });

  socket.on('call_accepted', (data) => {
    console.log('✅ Call accepted by target');
    socket.broadcast.emit('call_ready_for_offer', data);
  });

  socket.on('call_rejected', (data) => {
    console.log('❌ Call rejected');
    socket.broadcast.emit('call_rejected', data);
  });

  // WebRTC Signaling Relays
  socket.on('offer', (data) => {
    console.log('📦 Relaying WebRTC Offer');
    socket.broadcast.emit('offer', data);
  });

  socket.on('answer', (data) => {
    console.log('📦 Relaying WebRTC Answer');
    socket.broadcast.emit('answer', data);
  });

  socket.on('ice-candidate', (data) => {
    socket.broadcast.emit('ice-candidate', data);
  });

  socket.on('end-call', () => {
    console.log('📴 Call ended');
    socket.broadcast.emit('end-call');
  });

  socket.on('disconnect', () => {
    console.log(`🔴 User disconnected: ${socket.id}`);
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 VibeChat Server running on port ${PORT}`);
});
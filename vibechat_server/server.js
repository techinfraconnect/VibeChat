const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
  }
});

io.on('connection', (socket) => {
  console.log(`🟢 User connected: ${socket.id}`);

  socket.on('send_message', (data) => {
    io.emit('receive_message', data);
  });

  // WebRTC Signaling Events
  socket.on('offer', (data) => {
    console.log('📞 Offer received, broadcasting to peer...');
    socket.broadcast.emit('offer', data);
  });

  socket.on('answer', (data) => {
    console.log('📞 Answer received, broadcasting to peer...');
    socket.broadcast.emit('answer', data);
  });

  socket.on('ice-candidate', (data) => {
    socket.broadcast.emit('ice-candidate', data);
  });

  socket.on('end-call', () => {
    console.log('📴 Call ended by a user');
    socket.broadcast.emit('end-call');
  });

  socket.on('disconnect', () => {
    console.log(`🔴 User disconnected: ${socket.id}`);
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 VibeChat WebSocket Server running on port ${PORT}`);
});
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*", // Allows connections from any device or emulator
  }
});

io.on('connection', (socket) => {
  console.log(`🟢 User connected: ${socket.id}`);

  // Listen for messages sent from either Client or Admin
  socket.on('send_message', (data) => {
    console.log('💬 Message received:', data);
    
    // Broadcast the message back out to everyone connected
    io.emit('receive_message', data);
  });

  socket.on('disconnect', () => {
    console.log(`🔴 User disconnected: ${socket.id}`);
  });
});

const PORT = 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 VibeChat WebSocket Server running on port ${PORT}`);
});
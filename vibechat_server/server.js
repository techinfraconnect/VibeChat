const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// Map to keep track of active users and their socket IDs
const activeUsers = new Map();

io.on('connection', (socket) => {
  console.log(`User connected: ${socket.id}`);

  // Register user with their ID (e.g. 'admin' or 'client_123')
  socket.on('register', (data) => {
    activeUsers.set(data.userId, socket.id);
    console.log(`User registered: ${data.userId} -> Socket ID: ${socket.id}`);
  });

  // Relay Call Event
  socket.on('call_user', (data) => {
    const receiverSocketId = activeUsers.get(data.receiverId);
    
    if (receiverSocketId) {
      // Send notification directly to the receiver's socket
      io.to(receiverSocketId).emit('incoming_call', {
        callerId: data.callerId,
        isVideoCall: data.isVideoCall
      });
      console.log(`Call forwarded from ${data.callerId} to ${data.receiverId}`);
    } else {
      console.log(`User ${data.receiverId} is not online.`);
      // Optionally emit a 'user_offline' event back to caller
      socket.emit('user_offline', { message: 'The user you are calling is offline.' });
    }
  });

  socket.on('disconnect', () => {
    console.log(`User disconnected: ${socket.id}`);
    // Remove user from active Map on disconnect
    for (let [userId, sockId] of activeUsers.entries()) {
      if (sockId === socket.id) {
        activeUsers.delete(userId);
        break;
      }
    }
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`VibeChat signaling server running on port ${PORT}`);
});
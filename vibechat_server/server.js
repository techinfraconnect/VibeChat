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

// Track connected users to route calls cleanly by name/ID if needed
const activeUsers = new Map();

io.on('connection', (socket) => {
  console.log(`🟢 User connected: ${socket.id}`);

  // Register user mapping
  socket.on('register_user', (username) => {
    if (username) {
      activeUsers.set(username.toLowerCase(), socket.id);
      console.log(`👤 User registered: ${username} -> ${socket.id}`);
    }
  });

  // Chat Messages
  socket.on('send_message', (data) => {
    io.emit('receive_message', data);
  });

  // ---------------------------------------------------------
  // PRO CALL HANDSHAKE (Ringing & Accepting)
  // ---------------------------------------------------------
  
  // 1. Caller starts ringing the receiver
  socket.on('call_invite', (data) => {
    console.log(`🔔 Incoming call invite from: ${data.callerName} to target: ${data.targetUser}`);
    // Broadcast to everyone or target specific user
    socket.broadcast.emit('incoming_call', data);
  });

  // 2. Receiver accepts the call
  socket.on('call_accepted', (data) => {
    console.log('✅ Call accepted by receiver. Triggering offer generation...');
    socket.broadcast.emit('call_ready_for_offer', data);
  });

  // 3. Receiver rejects the call
  socket.on('call_rejected', (data) => {
    console.log('❌ Call rejected by receiver.');
    socket.broadcast.emit('call_rejected', data);
  });

  // ---------------------------------------------------------
  // STANDARD WEBRTC SIGNALING 
  // ---------------------------------------------------------
  socket.on('offer', (data) => {
    console.log('📞 Offer received, routing to peer...');
    socket.broadcast.emit('offer', data);
  });

  socket.on('answer', (data) => {
    console.log('📞 Answer received, routing back to caller...');
    socket.broadcast.emit('answer', data);
  });

  socket.on('ice-candidate', (data) => {
    console.log('❄️ ICE candidate received, relaying...');
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
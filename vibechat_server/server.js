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

io.on('connection', (socket) => {
  console.log(`🟢 Socket connected: ${socket.id}`);

  // Register user into their own room named after their lowercase username
  socket.on('register_user', (username) => {
    if (username) {
      const roomName = username.toLowerCase();
      socket.join(roomName);
      socket.data.username = roomName;
      console.log(`👤 User registered: "${username}" in room: "${roomName}" (${socket.id})`);
    }
  });

  // Chat messaging
  socket.on('send_message', (data) => {
    io.emit('receive_message', data);
  });

  // -------------------------------------------------------------
  // CALL HANDSHAKE EVENTS
  // -------------------------------------------------------------

  // 1. Caller invites receiver
  socket.on('call_invite', (data) => {
    const targetRoom = data.targetUser ? data.targetUser.toLowerCase() : null;
    console.log(`🔔 Call invite from "${data.callerName}" to "${data.targetUser}" (Video: ${data.isVideoCall})`);
    
    if (targetRoom) {
      // Send directly to the target user's room and broadcast as fallback
      io.to(targetRoom).emit('incoming_call', data);
      socket.broadcast.emit('incoming_call', data);
    } else {
      socket.broadcast.emit('incoming_call', data);
    }
  });

  // 2. Receiver accepts call -> Notify caller to generate WebRTC offer
  socket.on('call_accepted', (data) => {
    console.log(`✅ Call accepted by "${data.callerName || 'Receiver'}"`);
    socket.broadcast.emit('call_ready_for_offer', data);
  });

  // 3. Receiver declines call
  socket.on('call_rejected', (data) => {
    console.log(`❌ Call rejected`);
    socket.broadcast.emit('call_rejected', data);
  });

  // -------------------------------------------------------------
  // WEBRTC SIGNALING RELAYS
  // -------------------------------------------------------------
  socket.on('offer', (data) => {
    console.log(`📦 Relaying WebRTC Offer`);
    socket.broadcast.emit('offer', data);
  });

  socket.on('answer', (data) => {
    console.log(`📦 Relaying WebRTC Answer`);
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
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');

const app = express();
app.use(cors());

const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST']
  }
});

const connectedUsers = new Map();

io.on('connection', (socket) => {
  console.log(`[Socket.io] Connected: ${socket.id}`);

  // 1. Register User Room
  socket.on('register', (userId) => {
    if (!userId) return;
    socket.userId = userId;
    socket.join(userId);
    connectedUsers.set(userId, socket.id);
    console.log(`[Socket.io] Registered User: ${userId} on Socket: ${socket.id}`);
  });

  // 2. Real-Time Text Messaging
  socket.on('send_message', (data) => {
    console.log(`[Chat] ${data.senderId} -> ${data.receiverId}: ${data.text}`);
    io.to(data.receiverId).emit('receive_message', data);
    io.to(data.senderId).emit('receive_message', data);
  });

  // 3. WebRTC Signaling - Initiate Call
  socket.on('make_call', (data) => {
    console.log(`[Call] Initiate from ${data.callerId} to ${data.receiverId} (Video: ${data.isVideoCall})`);
    io.to(data.receiverId).emit('incoming_call', {
      callerId: data.callerId,
      receiverId: data.receiverId,
      isVideoCall: data.isVideoCall,
      callerName: data.callerName || data.callerId,
    });
  });

  // 4. WebRTC Signaling - Accept Call
  socket.on('accept_call', (data) => {
    console.log(`[Call] Accepted by ${data.receiverId} for ${data.callerId}`);
    io.to(data.callerId).emit('call_accepted', {
      callerId: data.callerId,
      receiverId: data.receiverId,
    });
  });

  // 5. WebRTC Signaling - Reject / End Call
  socket.on('reject_call', (data) => {
    console.log(`[Call] Rejected by ${data.receiverId}`);
    io.to(data.callerId).emit('call_rejected', data);
  });

  socket.on('end_call', (data) => {
    console.log(`[Call] Ended by ${socket.userId} for ${data.targetUser}`);
    if (data.targetUser) {
      io.to(data.targetUser).emit('call_ended', { from: socket.userId });
    }
  });

  // 6. WebRTC SDP & ICE Candidate Exchange
  socket.on('offer', (data) => {
    console.log(`[WebRTC] Offer from ${socket.userId} -> ${data.targetUser}`);
    io.to(data.targetUser).emit('offer', {
      from: socket.userId,
      offer: data.offer,
    });
  });

  socket.on('answer', (data) => {
    console.log(`[WebRTC] Answer from ${socket.userId} -> ${data.targetUser}`);
    io.to(data.targetUser).emit('answer', {
      from: socket.userId,
      answer: data.answer,
    });
  });

  socket.on('ice_candidate', (data) => {
    io.to(data.targetUser).emit('ice_candidate', {
      from: socket.userId,
      candidate: data.candidate,
    });
  });

  socket.on('disconnect', () => {
    if (socket.userId) {
      connectedUsers.delete(socket.userId);
      console.log(`[Socket.io] Disconnected: ${socket.userId}`);
    }
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
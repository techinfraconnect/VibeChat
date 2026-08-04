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

// Map of userId -> socket.id
const activeUsers = new Map();

io.on('connection', (socket) => {
  console.log(`[Socket] Connected: ${socket.id}`);

  // Register user (e.g., 'admin' or 'client')
  socket.on('register', (data) => {
    const userId = data.userId || data;
    activeUsers.set(userId, socket.id);
    socket.userId = userId;
    console.log(`[Register] User '${userId}' registered on socket '${socket.id}'`);
    console.log(`[Active Users]`, Array.from(activeUsers.keys()));
  });

  // Call Initiation
  socket.on('call_user', (data) => {
    console.log(`[Call] Incoming call request from ${data.callerId} to ${data.receiverId}`);
    const receiverSocketId = activeUsers.get(data.receiverId);

    if (receiverSocketId) {
      io.to(receiverSocketId).emit('incoming_call', {
        callerId: data.callerId,
        callerName: data.callerName || data.callerId,
        isVideoCall: data.isVideoCall,
      });
      console.log(`[Call] Dispatched 'incoming_call' to ${data.receiverId} (${receiverSocketId})`);
    } else {
      console.log(`[Call] Target user '${data.receiverId}' is OFFLINE`);
      socket.emit('user_offline', { receiverId: data.receiverId });
    }
  });

  // Call Response
  socket.on('answer_call', (data) => {
    const callerSocketId = activeUsers.get(data.callerId);
    if (callerSocketId) {
      io.to(callerSocketId).emit('call_answered', data);
    }
  });

  socket.on('reject_call', (data) => {
    const callerSocketId = activeUsers.get(data.callerId);
    if (callerSocketId) {
      io.to(callerSocketId).emit('call_rejected', data);
    }
  });

  socket.on('end_call', (data) => {
    const targetSocketId = activeUsers.get(data.targetUser);
    if (targetSocketId) {
      io.to(targetSocketId).emit('call_ended', data);
    }
  });

  // WebRTC Signaling
  socket.on('offer', (data) => {
    const targetSocketId = activeUsers.get(data.targetUser);
    if (targetSocketId) {
      io.to(targetSocketId).emit('offer', data);
    }
  });

  socket.on('answer', (data) => {
    const targetSocketId = activeUsers.get(data.targetUser);
    if (targetSocketId) {
      io.to(targetSocketId).emit('answer', data);
    }
  });

  socket.on('ice_candidate', (data) => {
    const targetSocketId = activeUsers.get(data.targetUser);
    if (targetSocketId) {
      io.to(targetSocketId).emit('ice_candidate', data);
    }
  });

  socket.on('disconnect', () => {
    if (socket.userId) {
      activeUsers.delete(socket.userId);
      console.log(`[Disconnect] User '${socket.userId}' unregistered`);
    }
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`VibeChat Signaling Server listening on port ${PORT}`);
});
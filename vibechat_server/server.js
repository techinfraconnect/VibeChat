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

  // Chat Messages
  socket.on('send_message', (data) => {
    io.emit('receive_message', data);
  });

  // ---------------------------------------------------------
  // PRO CALL HANDSHAKE (Ringing & Accepting)
  // ---------------------------------------------------------
  
  // 1. Caller starts ringing the receiver
  socket.on('call_invite', (data) => {
    console.log(`🔔 Incoming call invite from: ${data.callerName}. Routing to receiver...`);
    socket.broadcast.emit('incoming_call', data);
  });

  // 2. Receiver accepts the call (Signals the Caller to finally send the WebRTC Offer)
  socket.on('call_accepted', () => {
    console.log('✅ Call accepted by receiver. Triggering offer generation...');
    socket.broadcast.emit('call_ready_for_offer');
  });

  // 3. Receiver rejects the call
  socket.on('call_rejected', () => {
    console.log('❌ Call rejected by receiver.');
    socket.broadcast.emit('call_rejected');
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
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

// Persistent state for the admin's mute setting preference
let clientCanMute = true; 

io.on('connection', (socket) => {
  console.log(`🟢 DEVICE CONNECTED: ${socket.id}`);

  // Send current admin setting to newly connected clients/admin
  socket.emit('update_settings', { clientCanMute });

  // --- ADMIN SETTINGS SYNC ---
  socket.on('update_settings', (data) => {
    clientCanMute = data.clientCanMute;
    console.log(`⚙️ Settings updated by admin: clientCanMute = ${clientCanMute}`);
    // Broadcast setting change instantly to all other connected apps
    socket.broadcast.emit('update_settings', { clientCanMute });
  });

  // --- CHAT MESSAGES ---
  socket.on('send_message', (data) => {
    console.log(`✉️ Message sent by ${data.sender}`);
    socket.broadcast.emit('receive_message', data);
  });

  socket.on('edit_message', (data) => {
    console.log(`✏️ Message edited at index ${data.index}`);
    socket.broadcast.emit('edit_message', data);
  });

  // --- CALL HANDSHAKE ---
  socket.on('call_invite', (data) => {
    console.log(`🔔 Call invite triggered by: ${data.callerName}`);
    // Ensure the invite passes along the active mute setting state
    data.clientCanMute = clientCanMute;
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

  // --- WEBRTC SIGNALING ---
  socket.on('offer', (data) => {
    console.log(`📦 Relaying Offer`);
    socket.broadcast.emit('offer', data);
  });

  socket.on('answer', (data) => {
    console.log(`📦 Relaying Answer`);
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
    console.log(`🔴 DEVICE DISCONNECTED: ${socket.id}`);
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 VibeChat Server is RUNNING on port ${PORT}`);
});
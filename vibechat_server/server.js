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

let clientCanMute = true;
let showCallLogsToClient = true;
let chatHistory = [];       
let callLogs = [];          
let offlineMessages = [];   

io.on('connection', (socket) => {
  console.log(`🟢 DEVICE CONNECTED: ${socket.id}`);

  // Send current states & history to newly connected device
  socket.emit('update_settings', { clientCanMute, showCallLogsToClient });
  socket.emit('chat_history', chatHistory);
  socket.emit('call_logs', callLogs);

  // Deliver any pending offline messages
  if (offlineMessages.length > 0) {
    offlineMessages.forEach(msg => {
      socket.emit('receive_message', msg);
    });
    offlineMessages = [];
  }

  socket.on('update_settings', (data) => {
    if (data.clientCanMute !== undefined) clientCanMute = data.clientCanMute;
    if (data.showCallLogsToClient !== undefined) showCallLogsToClient = data.showCallLogsToClient;
    socket.broadcast.emit('update_settings', { clientCanMute, showCallLogsToClient });
  });

  socket.on('send_message', (data) => {
    console.log(`✉️ Message sent by ${data.sender}`);
    chatHistory.push(data);
    
    if (io.engine.clientsCount < 2) {
      offlineMessages.push(data);
    } else {
      socket.broadcast.emit('receive_message', data);
    }
  });

  socket.on('edit_message', (data) => {
    if (data.index < chatHistory.length) {
      chatHistory[data.index].message = data.message;
    }
    socket.broadcast.emit('edit_message', data);
  });

  // Call Logs & Invites
  socket.on('call_invite', (data) => {
    data.clientCanMute = clientCanMute;
    data.showCallLogsToClient = showCallLogsToClient;
    
    const now = new Date();
    const formattedDate = `${now.getDate().toString().padStart(2, '0')}/${(now.getMonth() + 1).toString().padStart(2, '0')}/${now.getFullYear()}`;
    const formattedTime = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

    const logEntry = {
      caller: data.callerName,
      type: data.isVideoCall ? 'WhatsApp Video' : 'WhatsApp Audio',
      status: 'Missed',
      dateTime: `${formattedDate}, ${formattedTime}`
    };
    callLogs.unshift(logEntry);
    
    socket.broadcast.emit('incoming_call', data);
    io.emit('call_logs_update', callLogs);
  });

  socket.on('call_accepted', (data) => {
    if (callLogs.length > 0) callLogs[0].status = 'Connected';
    socket.broadcast.emit('call_ready_for_offer', data);
    io.emit('call_logs_update', callLogs);
  });

  socket.on('call_rejected', () => {
    if (callLogs.length > 0) callLogs[0].status = 'Declined';
    socket.broadcast.emit('call_rejected');
    io.emit('call_logs_update', callLogs);
  });

  socket.on('offer', (data) => socket.broadcast.emit('offer', data));
  socket.on('answer', (data) => socket.broadcast.emit('answer', data));
  socket.on('ice-candidate', (data) => socket.broadcast.emit('ice-candidate', data));
  socket.on('end-call', () => socket.broadcast.emit('end-call'));

  socket.on('disconnect', () => {
    console.log(`🔴 DEVICE DISCONNECTED: ${socket.id}`);
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 VibeChat Server RUNNING on port ${PORT}`);
});
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const admin = require('firebase-admin');
const { cert } = require('firebase-admin/app');

// Automatically picks up the Secret File mounted by Render or local file
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: cert(serviceAccount)
});

console.log("🔥 Firebase initialized successfully via Secret File.");

const app = express();
const server = http.createServer(app);

const io = new Server(server, {
  cors: { origin: "*", methods: ["GET", "POST"] }
});

let clientCanMute = true;
let showCallLogsToClient = true;
let adminName = "Admin";
let clientName = "Client";
let chatHistory = [];             
let callLogs = [];                  
let offlineMessages = [];   
let registeredTokens = {}; // PRO FIX: Restored dual-storage (Topic + Token map) for bulletproof delivery

io.on('connection', (socket) => {
  console.log(`🟢 DEVICE CONNECTED: ${socket.id}`);

  socket.emit('update_settings', { clientCanMute, showCallLogsToClient });
  socket.emit('update_names', { adminName, clientName });
  socket.emit('chat_history', chatHistory);
  socket.emit('call_logs', callLogs);

  if (offlineMessages.length > 0) {
    offlineMessages.forEach(msg => socket.emit('receive_message', msg));
    offlineMessages = [];
  }

  // PRO FIX: Register device token alongside topics
  socket.on('register_fcm_token', (data) => {
    if (data.role && data.token) {
      registeredTokens[data.role] = data.token;
      console.log(`📱 FCM Token registered for role: ${data.role}`);
    }
  });

  socket.on('update_settings', (data) => {
    if (data.clientCanMute !== undefined) clientCanMute = data.clientCanMute;
    if (data.showCallLogsToClient !== undefined) showCallLogsToClient = data.showCallLogsToClient;
    socket.broadcast.emit('update_settings', { clientCanMute, showCallLogsToClient });
  });

  socket.on('update_names', (data) => {
    if (data.adminName !== undefined) adminName = data.adminName;
    if (data.clientName !== undefined) clientName = data.clientName;
    io.emit('update_names', { adminName, clientName });
  });

  socket.on('send_message', (data) => {
    data.id = data.id || Date.now().toString();
    data.timestamp = data.timestamp || Date.now();

    chatHistory.push(data);
    if (io.engine.clientsCount < 2) {
      offlineMessages.push(data);
      const targetRole = (data.sender === adminName) ? 'client' : 'admin';
      sendPushNotification(targetRole, `Message from ${data.sender}`, data.message, { type: 'chat', sender: data.sender });
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

  socket.on('call_invite', (data) => {
    data.clientCanMute = clientCanMute;
    data.showCallLogsToClient = showCallLogsToClient;
    
    const now = new Date();
    const formattedDate = `${now.getDate().toString().padStart(2, '0')}/${(now.getMonth() + 1).toString().padStart(2, '0')}/${now.getFullYear()}`;
    const formattedTime = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

    const logEntry = {
      id: Date.now().toString(),
      caller: data.callerName,
      type: data.isVideoCall ? 'WhatsApp Video' : 'WhatsApp Audio',
      status: 'Missed',
      dateTime: `${formattedDate}, ${formattedTime}`
    };
    callLogs.unshift(logEntry);
    
    socket.broadcast.emit('incoming_call', data);
    io.emit('call_logs_update', callLogs);

    const targetRole = (data.callerName === adminName) ? 'client' : 'admin';
    sendPushNotification(targetRole, "Incoming Call", `${data.callerName} is calling you...`, {
      type: 'call', callerName: data.callerName, isVideoCall: data.isVideoCall ? 'true' : 'false'
    });
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

  socket.on('cancel_call', () => {
    if (callLogs.length > 0 && callLogs[0].status === 'Missed') callLogs[0].status = 'Cancelled';
    socket.broadcast.emit('cancel_call');
    io.emit('call_logs_update', callLogs);

    sendPushNotification('client', 'Call Cancelled', 'Missed Call', { type: 'cancel_call' });
    sendPushNotification('admin', 'Call Cancelled', 'Missed Call', { type: 'cancel_call' });
  });

  socket.on('clear_call_logs', () => {
    callLogs = [];
    io.emit('call_logs_update', callLogs);
  });

  socket.on('offer', (data) => socket.broadcast.emit('offer', data));
  socket.on('answer', (data) => socket.broadcast.emit('answer', data));
  socket.on('ice-candidate', (data) => socket.broadcast.emit('ice-candidate', data));
  
  socket.on('end-call', () => {
    if (callLogs.length > 0 && callLogs[0].status === 'Connected') callLogs[0].status = 'Completed';
    socket.broadcast.emit('end-call');
    io.emit('call_logs_update', callLogs);
  });

  socket.on('disconnect', () => {
    console.log(`🔴 DEVICE DISCONNECTED: ${socket.id}`);
  });
});

// PRO FIX: Validated FCM Payload structure for both Token and Topic fallback delivery
function sendPushNotification(role, title, body, additionalData = {}) {
  const token = registeredTokens[role];
  const isCallEvent = additionalData.type === 'call' || additionalData.type === 'cancel_call';

  // Convert all data entries to strings (Firebase requirement)
  const stringifiedData = {};
  for (const key in additionalData) {
    stringifiedData[key] = String(additionalData[key]);
  }
  stringifiedData.title = String(title || 'VibeChat');
  stringifiedData.body = String(body || 'New Notification');

  let message = {
    data: stringifiedData,
    android: {
      priority: 'high',
      ttl: isCallEvent ? 0 : 3600000 // 0 TTL for instant call drops, 1 hr for chat
    }
  };

  // If a direct token exists, send to token. Otherwise, fan out to the topic.
  if (token) {
    message.token = token;
  } else {
    message.topic = role; // 'admin' or 'client'
  }

  admin.messaging().send(message)
    .then((response) => console.log(`📩 FCM successfully sent to [${role}]:`, response))
    .catch((error) => console.log('❌ FCM Sending Error:', error));
}

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 VibeChat Server RUNNING on port ${PORT}`);
});
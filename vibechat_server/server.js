const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const admin = require('firebase-admin');

// Initialize Firebase Admin securely via environment variables or local key file
let serviceAccount;
if (process.env.FIREBASE_CONFIG_JSON) {
  serviceAccount = JSON.parse(process.env.FIREBASE_CONFIG_JSON);
} else {
  serviceAccount = require('./serviceAccountKey.json');
}

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

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
let registeredTokens = {}; // Stores FCM device tokens by role ('admin' or 'client')

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

  // Register device FCM token for push notifications
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
    chatHistory.push(data);
    if (io.engine.clientsCount < 2) {
      offlineMessages.push(data);
      // Send Push Notification if recipient is offline
      const targetRole = (data.sender === adminName) ? 'client' : 'admin';
      sendPushNotification(targetRole, `New Message from ${data.sender}`, data.message);
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
      caller: data.callerName,
      type: data.isVideoCall ? 'WhatsApp Video' : 'WhatsApp Audio',
      status: 'Missed',
      dateTime: `${formattedDate}, ${formattedTime}`
    };
    callLogs.unshift(logEntry);
    
    socket.broadcast.emit('incoming_call', data);
    io.emit('call_logs_update', callLogs);

    // Send Push Notification for incoming call
    const targetRole = (data.callerName === adminName) ? 'client' : 'admin';
    sendPushNotification(targetRole, "Incoming Call", `${data.callerName} is calling you...`);
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

  socket.on('clear_call_logs', () => {
    callLogs = [];
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

// Helper function to dispatch FCM push notifications
function sendPushNotification(role, title, body) {
  const token = registeredTokens[role];
  if (!token) return;

  const message = {
    notification: { title, body },
    token: token
  };

  admin.messaging().send(message)
    .then((response) => console.log('📩 Successfully sent FCM message:', response))
    .catch((error) => console.log('❌ Error sending FCM message:', error));
}

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 VibeChat Server RUNNING on port ${PORT}`);
});
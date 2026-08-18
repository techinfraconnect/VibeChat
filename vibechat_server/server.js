const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const mediasoup = require('mediasoup');
const os = require('os');

// Firebase Admin SDK
const { initializeApp, cert } = require('firebase-admin/app');
const { getMessaging } = require('firebase-admin/messaging'); 
const { v4: uuidv4 } = require('uuid');

try {
  const serviceAccount = require('./serviceAccountKey.json');
  initializeApp({ credential: cert(serviceAccount) });
  console.log("🔥 Firebase initialized successfully via Secret File.");
} catch (e) {
  console.error("❌ Firebase Initialization Error:", e.message);
}

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*", methods: ["GET", "POST"] } });

let clientCanMute = true;
let showCallLogsToClient = true;
let adminName = "Admin";
let clientName = "Client";
let chatHistory = [];             
let callLogs = [];                  
let offlineMessages = [];   
let registeredTokens = {}; 

// ==========================================
// DYNAMIC IP DETECTION FOR LOCAL NETWORK
// ==========================================
function getLocalIp() {
  const ifaces = os.networkInterfaces();
  for (const name of Object.keys(ifaces)) {
    for (const iface of ifaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return '127.0.0.1';
}

// ==========================================
// MEDIASOUP SFU CONFIGURATION
// ==========================================
let mediasoupWorker;
let mediasoupRouter;

const mediaCodecs = [
  { kind: 'audio', mimeType: 'audio/opus', clockRate: 48000, channels: 2 },
  { kind: 'video', mimeType: 'video/VP8', clockRate: 90000, parameters: { 'x-google-start-bitrate': 1000 } },
  { kind: 'video', mimeType: 'video/H264', clockRate: 90000, parameters: { 'packetization-mode': 1, 'profile-level-id': '42e01f', 'level-asymmetry-allowed': 1 } }
];

const transports = new Map();
const producers = new Map();  
const consumers = new Map();  

async function startMediasoup() {
  mediasoupWorker = await mediasoup.createWorker({ rtcMinPort: 20000, rtcMaxPort: 29999, logLevel: 'warn' });
  mediasoupWorker.on('died', () => {
    console.error('❌ Mediasoup Worker died...');
    setTimeout(() => process.exit(1), 2000);
  });
  mediasoupRouter = await mediasoupWorker.createRouter({ mediaCodecs });
  console.log('🚀 Mediasoup Router initialized successfully.');
}

startMediasoup().catch((err) => console.error('❌ Error initializing Mediasoup:', err));

async function createWebRtcTransport(socketId) {
  const announcedAddress = process.env.ANNOUNCED_IP || getLocalIp();

  const transport = await mediasoupRouter.createWebRtcTransport({
    listenIps: [{ ip: '0.0.0.0', announcedIp: announcedAddress }],
    enableUdp: true, enableTcp: true, preferUdp: true, initialAvailableOutgoingBitrate: 1000000
  });

  if (!transports.has(socketId)) transports.set(socketId, new Map());
  transports.get(socketId).set(transport.id, transport);

  transport.on('dtlsstatechange', (dtlsState) => { if (dtlsState === 'closed') transport.close(); });
  transport.on('close', () => { if (transports.has(socketId)) transports.get(socketId).delete(transport.id); });

  return {
    transport,
    params: { id: transport.id, iceParameters: transport.iceParameters, iceCandidates: transport.iceCandidates, dtlsParameters: transport.dtlsParameters }
  };
}

function cleanSocketMediasoup(socketId) {
  if (transports.has(socketId)) { for (const t of transports.get(socketId).values()) t.close(); transports.delete(socketId); }
  if (producers.has(socketId)) { for (const p of producers.get(socketId).values()) p.close(); producers.delete(socketId); }
  if (consumers.has(socketId)) { for (const c of consumers.get(socketId).values()) c.close(); consumers.delete(socketId); }
}

// ==========================================
// SOCKET.IO HANDLERS
// ==========================================
io.on('connection', (socket) => {
  console.log(`🟢 DEVICE CONNECTED: ${socket.id}`);

  socket.emit('update_settings', { clientCanMute, showCallLogsToClient });
  socket.emit('update_names', { adminName, clientName });
  socket.emit('chat_history', chatHistory);
  socket.emit('call_logs', callLogs);

  if (offlineMessages.length > 0) { offlineMessages.forEach(msg => socket.emit('receive_message', msg)); offlineMessages = []; }

  socket.on('register_fcm_token', (data) => { if (data.role && data.token) registeredTokens[data.role] = data.token; });
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
    data.id = data.id || Date.now().toString(); data.timestamp = data.timestamp || Date.now(); chatHistory.push(data);
    if (io.engine.clientsCount < 2) {
      offlineMessages.push(data);
      const targetRole = (data.sender === adminName) ? 'client' : 'admin';
      sendPushNotification(targetRole, `Message from ${data.sender}`, data.message, { type: 'chat', sender: data.sender });
    } else {
      socket.broadcast.emit('receive_message', data);
    }
  });

  socket.on('edit_message', (data) => { if (data.index < chatHistory.length) chatHistory[data.index].message = data.message; socket.broadcast.emit('edit_message', data); });

  socket.on('call_invite', (data) => {
    data.clientCanMute = clientCanMute; data.showCallLogsToClient = showCallLogsToClient; data.callId = data.callId || uuidv4();
    const now = new Date(); const formattedDate = `${now.getDate().toString().padStart(2, '0')}/${(now.getMonth() + 1).toString().padStart(2, '0')}/${now.getFullYear()}`;
    const formattedTime = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    callLogs.unshift({ id: data.callId, caller: data.callerName, type: data.isVideoCall ? 'WhatsApp Video' : 'WhatsApp Audio', status: 'Missed', dateTime: `${formattedDate}, ${formattedTime}` });
    
    socket.broadcast.emit('incoming_call', data); io.emit('call_logs_update', callLogs);
    const targetRole = (data.callerName === adminName) ? 'client' : 'admin';
    sendPushNotification(targetRole, "Incoming Call", `${data.callerName} is calling you...`, { type: 'call', callId: data.callId, callerName: data.callerName, isVideoCall: data.isVideoCall ? 'true' : 'false' });
  });

  socket.on('call_accepted', (data) => { if (callLogs.length > 0) callLogs[0].status = 'Connected'; socket.broadcast.emit('call_ready_for_offer', data); io.emit('call_logs_update', callLogs); });
  socket.on('call_rejected', () => { if (callLogs.length > 0) callLogs[0].status = 'Declined'; socket.broadcast.emit('call_rejected'); io.emit('call_logs_update', callLogs); });
  socket.on('cancel_call', (data) => {
    if (callLogs.length > 0 && callLogs[0].status === 'Missed') callLogs[0].status = 'Cancelled'; socket.broadcast.emit('cancel_call'); io.emit('call_logs_update', callLogs);
    const callId = (data && data.callId) ? data.callId : '';
    sendPushNotification('client', 'Call Cancelled', 'Missed Call', { type: 'cancel_call', callId }); sendPushNotification('admin', 'Call Cancelled', 'Missed Call', { type: 'cancel_call', callId });
  });
  socket.on('clear_call_logs', () => { callLogs = []; io.emit('call_logs_update', callLogs); });

  socket.on('end-call', () => {
    if (callLogs.length > 0 && callLogs[0].status === 'Connected') callLogs[0].status = 'Completed';
    cleanSocketMediasoup(socket.id); socket.broadcast.emit('end-call'); io.emit('call_logs_update', callLogs);
  });

  // ==========================================
  // MEDIASOUP SFU
  // ==========================================
  
  // FIX: Properly accept (data, callback) to prevent "TypeError: callback is not a function"
  socket.on('getRouterRtpCapabilities', (data, callback) => { 
    const cb = typeof data === 'function' ? data : callback;
    if (cb) cb(mediasoupRouter.rtpCapabilities); 
  });
  
  // FIX: Properly accept (data, callback) 
  socket.on('getProducers', (data, callback) => {
    const cb = typeof data === 'function' ? data : callback;
    let existingProducers = [];
    for (let [peerId, peerProducers] of producers.entries()) {
      if (peerId !== socket.id) {
        for (let [prodId, prod] of peerProducers.entries()) {
          existingProducers.push({ producerId: prodId, kind: prod.kind });
        }
      }
    }
    if (cb) cb(existingProducers);
  });

  socket.on('createWebRtcTransport', async (data, callback) => {
    const cb = typeof data === 'function' ? data : callback;
    try { const { params } = await createWebRtcTransport(socket.id); cb(params); } catch (err) { cb({ error: err.message }); }
  });

  socket.on('connectTransport', async ({ transportId, dtlsParameters }, callback) => {
    try { await transports.get(socket.id).get(transportId).connect({ dtlsParameters }); callback({ connected: true }); } catch (err) { callback({ error: err.message }); }
  });

  socket.on('produce', async ({ transportId, kind, rtpParameters, appData }, callback) => {
    try {
      const producer = await transports.get(socket.id).get(transportId).produce({ kind, rtpParameters, appData });
      if (!producers.has(socket.id)) producers.set(socket.id, new Map());
      producers.get(socket.id).set(producer.id, producer);
      producer.on('transportclose', () => { if (producers.has(socket.id)) producers.get(socket.id).delete(producer.id); });
      
      socket.broadcast.emit('newProducer', { producerId: producer.id, socketId: socket.id, kind });
      callback({ id: producer.id });
    } catch (err) { callback({ error: err.message }); }
  });

  socket.on('consume', async ({ transportId, producerId, rtpCapabilities }, callback) => {
    try {
      if (!mediasoupRouter.canConsume({ producerId, rtpCapabilities })) return callback({ error: 'Cannot consume' });
      const consumer = await transports.get(socket.id).get(transportId).consume({ producerId, rtpCapabilities, paused: true });
      if (!consumers.has(socket.id)) consumers.set(socket.id, new Map());
      consumers.get(socket.id).set(consumer.id, consumer);
      consumer.on('transportclose', () => { if (consumers.has(socket.id)) consumers.get(socket.id).delete(consumer.id); });
      consumer.on('producerclose', () => { socket.emit('producerClosed', { consumerId: consumer.id }); });
      
      callback({ id: consumer.id, producerId, kind: consumer.kind, rtpParameters: consumer.rtpParameters });
    } catch (err) { callback({ error: err.message }); }
  });

  socket.on('resumeConsumer', async ({ consumerId }, callback) => {
    try { const consumer = consumers.get(socket.id)?.get(consumerId); if (consumer) await consumer.resume(); if (callback) callback({ resumed: true }); } catch (err) {}
  });

  socket.on('disconnect', () => { console.log(`🔴 DISCONNECTED: ${socket.id}`); cleanSocketMediasoup(socket.id); });
});

function sendPushNotification(role, title, body, additionalData = {}) {
  const token = registeredTokens[role];
  const isCallEvent = additionalData.type === 'call' || additionalData.type === 'cancel_call';
  const stringifiedData = {}; for (const key in additionalData) stringifiedData[key] = String(additionalData[key]);
  let message = {};
  if (isCallEvent) {
    message = { data: stringifiedData, android: { priority: 'high', ttl: 0 }, apns: { payload: { aps: { 'content-available': 1 } } } };
  } else {
    message = { notification: { title: String(title), body: String(body) }, data: stringifiedData, android: { priority: 'high' } };
  }
  if (token) message.token = token; else message.topic = role;
  getMessaging().send(message).catch(() => {});
}

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => console.log(`🚀 Server RUNNING on port ${PORT}`));
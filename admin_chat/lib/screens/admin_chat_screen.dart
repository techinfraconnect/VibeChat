import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class ChatScreen extends StatefulWidget {
  final String senderName; // Pass 'Client' or 'Admin'
  const ChatScreen({super.key, required this.senderName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late IO.Socket _socket;
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadStoredMessages();
    _connectSocket();
  }

  // Load saved chat history from local device storage
  Future<void> _loadStoredMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final String storageKey =
        '${widget.senderName.toLowerCase()}_chat_messages';
    final String? storedData = prefs.getString(storageKey);
    if (storedData != null) {
      final List decodedList = jsonDecode(storedData);
      setState(() {
        _messages = decodedList
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    }
  }

  // Save chat history to local device storage
  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final String storageKey =
        '${widget.senderName.toLowerCase()}_chat_messages';
    prefs.setString(storageKey, jsonEncode(_messages));
  }

  void _connectSocket() {
    _socket = IO.io(
      'https://vibechat-server-vo3f.onrender.com',
      <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
      },
    );

    _socket.connect();

    _socket.onConnect((_) {
      print('🟢 Connected to server');
    });

    // Listen for incoming messages broadcasted from the server
    _socket.on('receive_message', (data) {
      final incomingMessage = Map<String, dynamic>.from(data);
      setState(() {
        // Prevent duplicate entries if already present
        bool exists = _messages.any(
          (m) =>
              m['timestamp'] == incomingMessage['timestamp'] &&
              m['text'] == incomingMessage['text'] &&
              m['sender'] == incomingMessage['sender'],
        );

        if (!exists) {
          _messages.insert(0, incomingMessage);
          _saveMessages();
        }
      });
    });

    _socket.onDisconnect((_) => print('🔴 Disconnected'));
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;

    final messageData = {
      'text': _controller.text,
      'sender': widget.senderName,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Send message to the Node.js backend.
    // Removed local setState to prevent double-sending; the server echo handles insertion cleanly.
    _socket.emit('send_message', messageData);

    _controller.clear();
  }

  @override
  void dispose() {
    _socket.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70.0),
        child: AppBar(
          elevation: 10,
          shadowColor: Colors.black.withOpacity(0.3),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.senderName == 'Admin'
                    ? [const Color(0xFF11998e), const Color(0xFF38ef7d)]
                    : [const Color(0xFF4A00E0), const Color(0xFF8E2DE2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(25),
              ),
            ),
          ),
          backgroundColor: Colors.transparent,
          title: Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: Text(
              'VibeChat - ${widget.senderName}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 22,
                letterSpacing: 0.5,
                color: Colors.white,
              ),
            ),
          ),
          centerTitle: true,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                      child: Text(
                        "No messages yet. Start chatting!",
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isMe = msg['sender'] == widget.senderName;
                        return Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 16,
                            ),
                            padding: const EdgeInsets.all(12),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75,
                            ),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? (widget.senderName == 'Admin'
                                        ? const Color(0xFF11998e)
                                        : const Color(0xFF6C63FF))
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 5,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg['sender'] ?? '',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                    color: isMe ? Colors.white70 : Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  msg['text'] ?? '',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isMe ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              margin: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                bottom: 12.0,
                top: 8.0,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const SizedBox(width: 20),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: Color(0xFFB0B0B0)),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.all(6.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.senderName == 'Admin'
                            ? [const Color(0xFF11998e), const Color(0xFF38ef7d)]
                            : [
                                const Color(0xFF4A00E0),
                                const Color(0xFF8E2DE2),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

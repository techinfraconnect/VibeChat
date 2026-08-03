import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final String senderName;
  const ChatScreen({super.key, required this.senderName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late IO.Socket _socket;
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _messages = [];

  bool _isCallDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _loadStoredMessages();
    _connectSocket();
  }

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
        'autoConnect': true,
      },
    );

    _socket.onConnect((_) {
      print('🟢 Connected to server');
    });

    _socket.on('receive_message', (payload) {
      try {
        final incomingMessage = Map<String, dynamic>.from(
          payload is List ? payload.first : payload,
        );

        if (incomingMessage['sender'] == 'SYSTEM_SIGNAL') {
          if (incomingMessage['fromDevice'] == widget.senderName) return;

          String type = incomingMessage['signalType'] ?? '';
          if (type == 'call_invite') {
            if (!mounted || _isCallDialogOpen) return;

            Map<String, dynamic> data = incomingMessage['data'] != null
                ? Map<String, dynamic>.from(incomingMessage['data'])
                : <String, dynamic>{};

            _showIncomingCallDialog(data);
          } else if (type == 'end-call') {
            if (_isCallDialogOpen && mounted) {
              Navigator.pop(context);
            }
          }
          return;
        }

        setState(() {
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
      } catch (e) {
        print('Message parsing error: $e');
      }
    });

    _socket.onDisconnect((_) => print('🔴 Disconnected'));
    _socket.connect();
  }

  void _showIncomingCallDialog(Map<String, dynamic> data) {
    final String caller = data['callerName'] ?? 'Unknown';
    final bool isVideo = data['isVideoCall'] ?? false;

    _isCallDialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 20,
          backgroundColor: const Color(0xFF1F1F1F),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: widget.senderName == 'Admin'
                          ? [const Color(0xFF11998e), const Color(0xFF38ef7d)]
                          : [const Color(0xFF4A00E0), const Color(0xFF8E2DE2)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (widget.senderName == 'Admin'
                                    ? const Color(0xFF11998e)
                                    : const Color(0xFF8E2DE2))
                                .withOpacity(0.5),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Incoming Call',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  caller,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FloatingActionButton(
                      heroTag: 'decline_btn_admin',
                      backgroundColor: const Color(0xFFD32F2F),
                      onPressed: () {
                        _socket.emit('send_message', {
                          'sender': 'SYSTEM_SIGNAL',
                          'fromDevice': widget.senderName,
                          'signalType': 'call_rejected',
                          'data': <String, dynamic>{},
                          'timestamp': DateTime.now().toIso8601String(),
                        });
                        Navigator.pop(context);
                      },
                      child: const Icon(
                        Icons.call_end_rounded,
                        color: Colors.white,
                      ),
                    ),
                    FloatingActionButton(
                      heroTag: 'accept_btn_admin',
                      backgroundColor: const Color(0xFF38ef7d),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CallScreen(
                              callerName: caller,
                              isVideoCall: isVideo,
                              isCaller: false,
                              socket: _socket,
                            ),
                          ),
                        );
                      },
                      child: const Icon(
                        Icons.call_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _isCallDialogOpen = false;
    });
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;

    final messageData = {
      'text': _controller.text,
      'sender': widget.senderName,
      'timestamp': DateTime.now().toIso8601String(),
    };

    _socket.emit('send_message', messageData);
    _controller.clear();
  }

  void _startAudioCall() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          callerName: widget.senderName == 'Admin' ? 'Client' : 'Admin',
          isVideoCall: false,
          isCaller: true,
          socket: _socket,
        ),
      ),
    );
  }

  void _startVideoCall() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          callerName: widget.senderName == 'Admin' ? 'Client' : 'Admin',
          isVideoCall: true,
          isCaller: true,
          socket: _socket,
        ),
      ),
    );
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
                fontSize: 20,
                letterSpacing: 0.5,
                color: Colors.white,
              ),
            ),
          ),
          centerTitle: false,
          actions: [
            Padding(
              padding: const EdgeInsets.only(top: 10.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.call_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: _startAudioCall,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.videocam_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: _startVideoCall,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.settings_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: () {},
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ],
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

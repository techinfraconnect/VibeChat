import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'call_screen.dart';

class AdminChatScreen extends StatefulWidget {
  final String senderName;
  final io.Socket socket;

  const AdminChatScreen({
    super.key,
    required this.senderName,
    required this.socket,
  });

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];

  int? _editingIndex;
  bool _clientCanMute = true; // Admin setting state

  @override
  void initState() {
    super.initState();
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    widget.socket.off('receive_message');
    widget.socket.off('edit_message');
    widget.socket.off('incoming_call');

    widget.socket.on('receive_message', (data) {
      if (!mounted) return;
      setState(() {
        _messages.add(Map<String, dynamic>.from(data));
      });
    });

    widget.socket.on('edit_message', (data) {
      if (!mounted) return;
      setState(() {
        int index = data['index'];
        if (index < _messages.length) {
          _messages[index]['message'] = data['message'];
        }
      });
    });

    widget.socket.on('incoming_call', (data) {
      if (!mounted) return;
      if (data['callerName'] == widget.senderName) return;
      _showIncomingCallDialog(Map<String, dynamic>.from(data));
    });
  }

  void _showIncomingCallDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text(
          "Incoming Call from ${data['callerName']}",
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          "Type: ${data['isVideoCall'] == true ? 'Video Call' : 'Audio Call'}",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.socket.emit('call_rejected');
            },
            child: const Text(
              "Decline",
              style: TextStyle(color: Color(0xFFFF3B30)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CallScreen(
                    callerName: data['callerName'],
                    targetUser: data['callerName'],
                    isVideoCall: data['isVideoCall'] ?? false,
                    isCaller: false,
                    socket: widget.socket,
                    clientCanMute: _clientCanMute,
                    isAdmin: true,
                  ),
                ),
              );
            },
            child: const Text("Accept", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _handleSubmit() {
    if (_messageController.text.trim().isEmpty) return;

    if (_editingIndex != null) {
      setState(() {
        _messages[_editingIndex!]['message'] = _messageController.text.trim();
      });
      widget.socket.emit('edit_message', {
        'index': _editingIndex,
        'message': _messageController.text.trim(),
      });
      _editingIndex = null;
    } else {
      final messageData = {
        'sender': widget.senderName,
        'message': _messageController.text.trim(),
      };
      widget.socket.emit('send_message', messageData);
      setState(() {
        _messages.add(messageData);
      });
    }

    _messageController.clear();
  }

  void _startEditing(int index) {
    if (_messages[index]['sender'] == widget.senderName) {
      setState(() {
        _editingIndex = index;
        _messageController.text = _messages[index]['message'];
      });
    }
  }

  void _initiateCall(bool isVideo) {
    widget.socket.emit('call_invite', {
      'callerName': widget.senderName,
      'isVideoCall': isVideo,
      'clientCanMute': _clientCanMute,
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          callerName: widget.senderName,
          targetUser: "Client",
          isVideoCall: isVideo,
          isCaller: true,
          socket: widget.socket,
          clientCanMute: _clientCanMute,
          isAdmin: true,
        ),
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Admin Settings",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Enable Client Mute Button",
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      Switch(
                        value: _clientCanMute,
                        activeThumbColor: Colors.blue,
                        onChanged: (val) {
                          setModalState(() {
                            _clientCanMute = val;
                          });
                          setState(() {});
                          // Emit setting change to server so client updates instantly
                          widget.socket.emit('update_settings', {
                            'clientCanMute': val,
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
        title: const Text(
          "Admin",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_rounded),
            onPressed: () => _initiateCall(false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_rounded),
            onPressed: () => _initiateCall(true),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                bool isMe = msg['sender'] == widget.senderName;
                return GestureDetector(
                  onLongPress: () => _startEditing(index),
                  child: Align(
                    alignment: isMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: isMe
                            ? const Color(0xFF0A84FF)
                            : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        msg['message'] ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        maxLines: 5,
                        minLines: 1,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: _editingIndex != null
                              ? "Edit message..."
                              : "Type a message...",
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _handleSubmit,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF0A84FF),
                      ),
                      child: Icon(
                        _editingIndex != null
                            ? Icons.check
                            : Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

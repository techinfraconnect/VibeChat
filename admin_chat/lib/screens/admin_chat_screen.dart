import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'call_screen.dart';
import 'call_logs_screen.dart';

class AdminChatScreen extends StatefulWidget {
  final io.Socket socket;

  const AdminChatScreen({super.key, required this.socket});

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _adminNameController = TextEditingController();
  final TextEditingController _clientNameController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _callLogs = [];

  int? _editingIndex;
  bool _clientCanMute = true;
  bool _showCallLogsToClient = true;

  String _adminName = "Admin";
  String _clientName = "Client";
  BuildContext? _activeCallDialogContext;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    _setupSocketListeners();
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _adminName = prefs.getString('admin_name') ?? "Admin";
      _clientName = prefs.getString('client_name') ?? "Client";
      _adminNameController.text = _adminName;
      _clientNameController.text = _clientName;
    });

    final String? cachedMessages = prefs.getString('admin_chat_history');
    if (cachedMessages != null) {
      try {
        List<dynamic> decoded = jsonDecode(cachedMessages);
        setState(() {
          _messages = decoded
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        });
        _scrollToBottom();
      } catch (_) {}
    }
  }

  Future<void> _saveLocalMessages() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('admin_chat_history', jsonEncode(_messages));
  }

  Future<void> _saveNames(String admin, String client) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_name', admin);
    await prefs.setString('client_name', client);
    setState(() {
      _adminName = admin;
      _clientName = client;
    });
    widget.socket.emit('update_names', {
      'adminName': admin,
      'clientName': client,
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _setupSocketListeners() {
    widget.socket.off('chat_history');
    widget.socket.off('receive_message');
    widget.socket.off('edit_message');
    widget.socket.off('call_logs');
    widget.socket.off('call_logs_update');
    widget.socket.off('update_names');
    widget.socket.off('incoming_call');
    widget.socket.off('call_rejected');
    widget.socket.off('cancel_call');

    widget.socket.on('chat_history', (data) {
      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(data);
      });
      _saveLocalMessages();
      _scrollToBottom();
    });

    widget.socket.on('receive_message', (data) {
      if (!mounted) return;
      setState(() {
        _messages.add(Map<String, dynamic>.from(data));
      });
      _saveLocalMessages();
      _scrollToBottom();
    });

    widget.socket.on('edit_message', (data) {
      if (!mounted) return;
      setState(() {
        int index = data['index'];
        if (index < _messages.length) {
          _messages[index]['message'] = data['message'];
        }
      });
      _saveLocalMessages();
    });

    widget.socket.on('call_logs', (data) {
      if (!mounted) return;
      setState(() {
        _callLogs = List<Map<String, dynamic>>.from(data);
      });
    });

    widget.socket.on('call_logs_update', (data) {
      if (!mounted) return;
      setState(() {
        _callLogs = List<Map<String, dynamic>>.from(data);
      });
    });

    widget.socket.on('update_names', (data) async {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        if (data['adminName'] != null) {
          _adminName = data['adminName'];
          prefs.setString('admin_name', _adminName);
        }
        if (data['clientName'] != null) {
          _clientName = data['clientName'];
          prefs.setString('client_name', _clientName);
        }
      });
    });

    widget.socket.on('call_rejected', (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Call Declined.."),
          backgroundColor: Colors.red,
        ),
      );
    });

    widget.socket.on('cancel_call', (_) {
      if (_activeCallDialogContext != null) {
        Navigator.of(_activeCallDialogContext!).pop();
        _activeCallDialogContext = null;
      }
    });

    widget.socket.on('incoming_call', (data) {
      if (!mounted) return;
      if (data['callerName'] == _adminName) return;

      if (data['clientCanMute'] != null) _clientCanMute = data['clientCanMute'];
      if (data['showCallLogsToClient'] != null)
        _showCallLogsToClient = data['showCallLogsToClient'];

      _showFaceTimeCallDialog(Map<String, dynamic>.from(data));
    });
  }

  void _showFaceTimeCallDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _activeCallDialogContext = ctx;
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.zero,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF2C2C2E),
                    Color(0xFF1C1C1E),
                    Color(0xFF0C0C0E),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  CircleAvatar(
                    radius: 55,
                    backgroundColor: Colors.grey[800],
                    child: Text(
                      data['callerName'][0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    data['callerName'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data['isVideoCall'] == true
                        ? "Incoming Video Call..."
                        : "Incoming Audio Call...",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 50,
                      vertical: 60,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        FloatingActionButton(
                          heroTag: "decline_call_admin",
                          backgroundColor: const Color(0xFFFF3B30),
                          onPressed: () {
                            _activeCallDialogContext = null;
                            Navigator.pop(ctx);
                            widget.socket.emit('call_rejected');
                          },
                          child: const Icon(
                            Icons.call_end,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        FloatingActionButton(
                          heroTag: "accept_call_admin",
                          backgroundColor: const Color(0xFF34C759),
                          onPressed: () {
                            _activeCallDialogContext = null;
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CallScreen(
                                  callerName: _adminName,
                                  targetUser: _clientName,
                                  isVideoCall: data['isVideoCall'] ?? false,
                                  isCaller: false,
                                  socket: widget.socket,
                                  clientCanMute: _clientCanMute,
                                  isAdmin: true,
                                ),
                              ),
                            );
                          },
                          child: const Icon(
                            Icons.call,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      _activeCallDialogContext = null;
    });
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
        'sender': _adminName,
        'message': _messageController.text.trim(),
      };
      widget.socket.emit('send_message', messageData);
      setState(() {
        _messages.add(messageData);
      });
    }
    _saveLocalMessages();
    _messageController.clear();
    _scrollToBottom();
  }

  void _startEditing(int index) {
    if (_messages[index]['sender'] == _adminName) {
      setState(() {
        _editingIndex = index;
        _messageController.text = _messages[index]['message'];
      });
    }
  }

  void _initiateCall(bool isVideo) {
    widget.socket.emit('call_invite', {
      'callerName': _adminName,
      'isVideoCall': isVideo,
      'clientCanMute': _clientCanMute,
      'showCallLogsToClient': _showCallLogsToClient,
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          callerName: _adminName,
          targetUser: _clientName,
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
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: SingleChildScrollView(
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
                            setModalState(() => _clientCanMute = val);
                            setState(() {});
                            widget.socket.emit('update_settings', {
                              'clientCanMute': val,
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Show Call Logs to Client",
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        Switch(
                          value: _showCallLogsToClient,
                          activeThumbColor: Colors.blue,
                          onChanged: (val) {
                            setModalState(() => _showCallLogsToClient = val);
                            setState(() {});
                            widget.socket.emit('update_settings', {
                              'showCallLogsToClient': val,
                            });
                          },
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 30),
                    const Text(
                      "Client Name",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _clientNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF2C2C2E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        _saveNames(
                          _adminNameController.text.trim(),
                          val.trim(),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Admin Name",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _adminNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF2C2C2E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        _saveNames(
                          val.trim(),
                          _clientNameController.text.trim(),
                        );
                      },
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
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
        title: Text(
          _adminName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CallLogsScreen(
                  callLogs: _callLogs,
                  onClearLogs: () => widget.socket.emit('clear_call_logs'),
                ),
              ),
            ),
          ),
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
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                bool isMe = msg['sender'] == _adminName;
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
                        decoration: InputDecoration(
                          hintText: _editingIndex != null
                              ? "Edit message..."
                              : "Type a message...",
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                          border: InputBorder.none,
                          isDense: true,
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

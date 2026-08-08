import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'call_screen.dart';
import 'call_logs_screen.dart';

class ClientChatScreen extends StatefulWidget {
  final io.Socket socket;

  const ClientChatScreen({super.key, required this.socket});

  @override
  State<ClientChatScreen> createState() => _ClientChatScreenState();
}

class _ClientChatScreenState extends State<ClientChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _callLogs = [];

  int? _editingIndex;
  bool _clientCanMute = true;
  bool _showCallLogsToClient = true;

  String _clientName = "Client";
  String _adminName = "Admin";
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
      _clientName = prefs.getString('client_name') ?? "Client";
      _adminName = prefs.getString('admin_name') ?? "Admin";
    });

    final String? cachedMessages = prefs.getString('client_chat_history');
    if (cachedMessages != null) {
      try {
        List<dynamic> decoded = jsonDecode(cachedMessages);
        setState(() {
          _messages = decoded
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        });
        _scrollToBottom();
      } catch (_) {}
    }

    final String? cachedLogs = prefs.getString('client_call_logs');
    if (cachedLogs != null) {
      try {
        List<dynamic> decodedLogs = jsonDecode(cachedLogs);
        setState(() {
          _callLogs = decodedLogs
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        });
      } catch (_) {}
    }
  }

  Future<void> _saveLocalMessages() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('client_chat_history', jsonEncode(_messages));
  }

  Future<void> _saveLocalCallLogs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('client_call_logs', jsonEncode(_callLogs));
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
    widget.socket.off('update_settings');
    widget.socket.off('update_names');
    widget.socket.off('incoming_call');
    widget.socket.off('call_rejected');
    widget.socket.off('cancel_call');

    widget.socket.on('chat_history', (data) {
      if (!mounted || data == null) return;

      List<dynamic> serverData = [];
      if (data is List) {
        serverData = (data.isNotEmpty && data.first is List)
            ? data.first
            : data;
      }
      if (serverData.isEmpty) return;

      bool addedNew = false;
      setState(() {
        for (var item in serverData) {
          if (item == null) continue;
          final rawItem = item is List
              ? (item.isNotEmpty ? item.first : {})
              : item;
          final Map<String, dynamic> sm = Map<String, dynamic>.from(
            rawItem as Map,
          );

          bool exists = _messages.any(
            (m) => m['id'] != null && m['id'] == sm['id'],
          );
          if (!exists) {
            _messages.add(sm);
            addedNew = true;
          }
        }
        _messages.sort(
          (a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0),
        );
      });

      if (addedNew) {
        _saveLocalMessages();
        _scrollToBottom();
      }
    });

    widget.socket.on('receive_message', (data) {
      if (!mounted || data == null) return;

      final rawData = data is List ? (data.isNotEmpty ? data.first : {}) : data;
      final Map<String, dynamic> newMsg = Map<String, dynamic>.from(
        rawData as Map,
      );

      setState(() {
        bool exists = _messages.any(
          (m) => m['id'] != null && m['id'] == newMsg['id'],
        );
        if (!exists) {
          _messages.add(newMsg);
        }
      });
      _saveLocalMessages();
      _scrollToBottom();
    });

    widget.socket.on('edit_message', (data) {
      if (!mounted || data == null) return;

      final rawData = data is List ? (data.isNotEmpty ? data.first : {}) : data;
      final Map<String, dynamic> mapData = Map<String, dynamic>.from(
        rawData as Map,
      );

      setState(() {
        int? index = mapData['index'] as int?;
        if (index != null && index < _messages.length) {
          _messages[index]['message'] = mapData['message'];
        }
      });
      _saveLocalMessages();
    });

    widget.socket.on('call_logs', (data) {
      if (!mounted || data == null) return;

      List<dynamic> serverData = [];
      if (data is List) {
        serverData = (data.isNotEmpty && data.first is List)
            ? data.first
            : data;
      }
      if (serverData.isEmpty) return;

      setState(() {
        for (var item in serverData) {
          if (item == null) continue;
          final rawItem = item is List
              ? (item.isNotEmpty ? item.first : {})
              : item;
          final Map<String, dynamic> log = Map<String, dynamic>.from(
            rawItem as Map,
          );

          int index = _callLogs.indexWhere((l) => l['id'] == log['id']);
          if (index != -1) {
            _callLogs[index] = log;
          } else {
            _callLogs.add(log);
          }
        }
        _callLogs.sort((a, b) => (b['id'] ?? "").compareTo(a['id'] ?? ""));
      });
      _saveLocalCallLogs();
    });

    widget.socket.on('call_logs_update', (data) {
      if (!mounted || data == null) return;

      List<dynamic> serverData = [];
      if (data is List) {
        serverData = (data.isNotEmpty && data.first is List)
            ? data.first
            : data;
      }

      if (serverData.isEmpty) {
        setState(() => _callLogs.clear());
        _saveLocalCallLogs();
        return;
      }

      setState(() {
        for (var item in serverData) {
          if (item == null) continue;
          final rawItem = item is List
              ? (item.isNotEmpty ? item.first : {})
              : item;
          final Map<String, dynamic> log = Map<String, dynamic>.from(
            rawItem as Map,
          );

          int index = _callLogs.indexWhere((l) => l['id'] == log['id']);
          if (index != -1) {
            _callLogs[index] = log;
          } else {
            _callLogs.add(log);
          }
        }
        _callLogs.sort((a, b) => (b['id'] ?? "").compareTo(a['id'] ?? ""));
      });
      _saveLocalCallLogs();
    });

    widget.socket.on('update_names', (data) async {
      if (!mounted || data == null) return;

      final rawData = data is List ? (data.isNotEmpty ? data.first : {}) : data;
      final Map<String, dynamic> mapData = Map<String, dynamic>.from(
        rawData as Map,
      );

      final prefs = await SharedPreferences.getInstance();
      setState(() {
        if (mapData['clientName'] != null) {
          _clientName = mapData['clientName'].toString();
          prefs.setString('client_name', _clientName);
        }
        if (mapData['adminName'] != null) {
          _adminName = mapData['adminName'].toString();
          prefs.setString('admin_name', _adminName);
        }
      });
    });

    widget.socket.on('update_settings', (data) {
      if (!mounted || data == null) return;

      final rawData = data is List ? (data.isNotEmpty ? data.first : {}) : data;
      final Map<String, dynamic> mapData = Map<String, dynamic>.from(
        rawData as Map,
      );

      setState(() {
        if (mapData['clientCanMute'] != null) {
          _clientCanMute = mapData['clientCanMute'] as bool;
        }
        if (mapData['showCallLogsToClient'] != null) {
          _showCallLogsToClient = mapData['showCallLogsToClient'] as bool;
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
      if (!mounted || data == null) return;

      final rawData = data is List ? (data.isNotEmpty ? data.first : {}) : data;
      final Map<String, dynamic> mapData = Map<String, dynamic>.from(
        rawData as Map,
      );

      if (mapData['callerName'] == _clientName) return;

      setState(() {
        if (mapData['clientCanMute'] != null) {
          _clientCanMute = mapData['clientCanMute'] as bool;
        }
        if (mapData['showCallLogsToClient'] != null) {
          _showCallLogsToClient = mapData['showCallLogsToClient'] as bool;
        }
      });

      _showFaceTimeCallDialog(mapData);
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
                      (data['callerName'] as String)[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    data['callerName'] as String,
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
                          heroTag: "decline_call_client",
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
                          heroTag: "accept_call_client",
                          backgroundColor: const Color(0xFF34C759),
                          onPressed: () {
                            _activeCallDialogContext = null;
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CallScreen(
                                  callerName: _clientName,
                                  targetUser: _adminName,
                                  isVideoCall: data['isVideoCall'] ?? false,
                                  isCaller: false,
                                  socket: widget.socket,
                                  clientCanMute: _clientCanMute,
                                  isAdmin: false,
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
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'sender': _clientName,
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
    if (_messages[index]['sender'] == _clientName) {
      setState(() {
        _editingIndex = index;
        _messageController.text = _messages[index]['message'];
      });
    }
  }

  void _initiateCall(bool isVideo) {
    widget.socket.emit('call_invite', {
      'callerName': _clientName,
      'isVideoCall': isVideo,
      'clientCanMute': _clientCanMute,
      'showCallLogsToClient': _showCallLogsToClient,
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          callerName: _clientName,
          targetUser: _adminName,
          isVideoCall: isVideo,
          isCaller: true,
          socket: widget.socket,
          clientCanMute: _clientCanMute,
          isAdmin: false,
        ),
      ),
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
          _clientName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_showCallLogsToClient)
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
                bool isMe = msg['sender'] == _clientName;
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

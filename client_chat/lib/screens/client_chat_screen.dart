import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';

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
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final List<Map<String, dynamic>> _messages = [];
  final List<Map<String, dynamic>> _callLogs = [];

  int? _editingIndex;
  bool _clientCanMute = true;
  bool _showCallLogsToClient = true;
  String _clientName = "Client";
  String _adminName = "Admin";

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    _setupSocketListeners();
    _setupCallKitListener();
  }

  void _setupCallKitListener() {
    FlutterCallkitIncoming.onEvent.listen((dynamic eventObj) {
      if (!mounted || eventObj == null) {
        return;
      }

      String eventName = '';
      try {
        eventName = eventObj.event.toString();
      } catch (_) {}

      if (eventName.contains('CallAccept')) {
        bool isVideo = false;
        try {
          final dynamic extra = eventObj.body['extra'];
          isVideo = extra['isVideoCall']?.toString() == 'true';
        } catch (_) {}

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CallScreen(
              callerName: _clientName,
              targetUser: _adminName,
              isVideoCall: isVideo,
              isCaller: false,
              socket: widget.socket,
              clientCanMute: _clientCanMute,
              isAdmin: false,
            ),
          ),
        );
      } else if (eventName.contains('CallDecline') ||
          eventName.contains('CallTimeout')) {
        widget.socket.emit('call_rejected');
      }
    });
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _clientName = prefs.getString('client_name') ?? "Client";
      _adminName = prefs.getString('admin_name') ?? "Admin";
    });

    final cachedMessages = prefs.getString('client_chat_history');
    if (cachedMessages != null) {
      try {
        List<dynamic> decoded = jsonDecode(cachedMessages);
        setState(() {
          _messages.clear();
          _messages.addAll(
            decoded.map((item) => Map<String, dynamic>.from(item as Map)),
          );
        });
        _scrollToBottom();
      } catch (_) {}
    }
  }

  Future<void> _saveLocalMessages() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('client_chat_history', jsonEncode(_messages));
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
    widget.socket.on('chat_history', (data) {
      if (!mounted || data == null) {
        return;
      }
      List<dynamic> serverData = data is List
          ? (data.isNotEmpty && data.first is List ? data.first : data)
          : [];
      if (serverData.isEmpty) {
        return;
      }

      bool addedNew = false;
      setState(() {
        for (var item in serverData) {
          if (item == null) {
            continue;
          }
          final sm = Map<String, dynamic>.from(
            item is List ? item.first as Map : item as Map,
          );
          if (!_messages.any((m) => m['id'] == sm['id'])) {
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
      if (!mounted || data == null) {
        return;
      }
      final newMsg = Map<String, dynamic>.from(
        data is List ? data.first as Map : data as Map,
      );
      setState(() {
        if (!_messages.any((m) => m['id'] == newMsg['id'])) {
          _messages.add(newMsg);
        }
      });
      _saveLocalMessages();
      _scrollToBottom();
    });

    widget.socket.on('update_names', (data) async {
      if (!mounted || data == null) {
        return;
      }
      final mapData = Map<String, dynamic>.from(
        data is List ? data.first as Map : data as Map,
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
      if (!mounted || data == null) {
        return;
      }
      final mapData = Map<String, dynamic>.from(
        data is List ? data.first as Map : data as Map,
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

    widget.socket.on('cancel_call', (_) async {
      if (!mounted) {
        return;
      }
      await FlutterCallkitIncoming.endAllCalls();
    });

    widget.socket.on('incoming_call', (data) async {
      if (!mounted || data == null) {
        return;
      }
      final mapData = Map<String, dynamic>.from(
        data is List ? data.first as Map : data as Map,
      );
      if (mapData['callerName'] == _clientName) {
        return;
      }

      setState(() {
        if (mapData['clientCanMute'] != null) {
          _clientCanMute = mapData['clientCanMute'] as bool;
        }
        if (mapData['showCallLogsToClient'] != null) {
          _showCallLogsToClient = mapData['showCallLogsToClient'] as bool;
        }
      });

      var callKitParams = CallKitParams(
        id:
            mapData['callId'] ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        nameCaller: mapData['callerName'] ?? 'Caller',
        appName: 'VibeChat Client',
        avatar: 'https://i.pravatar.cc/100',
        handle: mapData['isVideoCall']?.toString() == 'true'
            ? 'Video Call'
            : 'Audio Call',
        type: mapData['isVideoCall']?.toString() == 'true' ? 1 : 0,
        duration: 30000,
        extra: <String, dynamic>{
          'isVideoCall': mapData['isVideoCall']?.toString(),
          'callId': mapData['callId'],
        },
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0955fa',
          actionColor: '#4CAF50',
        ),
        ios: const IOSParams(
          iconName: 'CallKitLogo',
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 2,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          audioSessionPreferredSampleRate: 44100.0,
          audioSessionPreferredIOBufferDuration: 0.005,
          supportsDTMF: true,
          supportsHolding: true,
          supportsGrouping: false,
          supportsUngrouping: false,
          ringtonePath: 'system_ringtone_default',
        ),
      );
      await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
    });
  }

  void _handleSubmit() {
    if (_messageController.text.trim().isEmpty) {
      return;
    }

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
    final String callId = DateTime.now().millisecondsSinceEpoch.toString();
    widget.socket.emit('call_invite', {
      'callerName': _clientName,
      'isVideoCall': isVideo,
      'clientCanMute': _clientCanMute,
      'showCallLogsToClient': _showCallLogsToClient,
      'callId': callId,
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
        title: Text(_clientName, style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_rounded, color: Colors.white),
            onPressed: () => _initiateCall(false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_rounded, color: Colors.white),
            onPressed: () => _initiateCall(true),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                bool isMe = msg['sender'] == _clientName;
                return Align(
                  alignment: isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isMe
                          ? const Color(0xFF0A84FF)
                          : const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      msg['message'] ?? '',
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: _editingIndex != null
                              ? "Edit message..."
                              : "Type a message...",
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _handleSubmit,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF0A84FF),
                      ),
                      child: const Icon(Icons.send, color: Colors.white),
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

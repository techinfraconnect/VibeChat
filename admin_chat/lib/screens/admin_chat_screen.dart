import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';

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
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final List<Map<String, dynamic>> _messages = [];
  final List<Map<String, dynamic>> _callLogs = [];

  int? _editingIndex;
  bool _clientCanMute = true;
  bool _showCallLogsToClient = true;
  String _adminName = "Admin";
  String _clientName = "Client";

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
              isVideoCall: isVideo,
              isCaller: false,
              socket: widget.socket,
            ),
          ),
        );
      } else if (eventName.contains('CallDecline') ||
          eventName.contains('CallTimeout')) {
        widget.socket.emit('call_rejected');
      }
    });
  }

  void _showIncomingCallDialog(String caller, bool isVideo) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isVideo ? Icons.videocam_rounded : Icons.call_rounded,
              color: const Color(0xFF0A84FF),
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              isVideo ? "Incoming Video Call" : "Incoming Call",
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          "$caller is calling you...",
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          IconButton(
            iconSize: 44,
            style: IconButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.all(10),
            ),
            icon: const Icon(Icons.call_end_rounded, color: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              widget.socket.emit('call_rejected');
            },
          ),
          IconButton(
            iconSize: 44,
            style: IconButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.all(10),
            ),
            icon: const Icon(Icons.call_rounded, color: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CallScreen(
                    callerName: caller,
                    isVideoCall: isVideo,
                    isCaller: false,
                    socket: widget.socket,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
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

    widget.socket.on('edit_message', (data) {
      if (!mounted || data == null) {
        return;
      }
      final mapData = Map<String, dynamic>.from(
        data is List ? data.first as Map : data as Map,
      );
      setState(() {
        int? index = mapData['index'] as int?;
        if (index != null && index < _messages.length) {
          _messages[index]['message'] = mapData['message'];
        }
      });
      _saveLocalMessages();
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
        if (mapData['adminName'] != null) {
          _adminName = mapData['adminName'].toString();
          prefs.setString('admin_name', _adminName);
        }
        if (mapData['clientName'] != null) {
          _clientName = mapData['clientName'].toString();
          prefs.setString('client_name', _clientName);
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
      if (mapData['callerName'] == _adminName) {
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

      bool isVideo = mapData['isVideoCall']?.toString() == 'true';
      String caller = mapData['callerName'] ?? 'Client';

      // Show foreground in-app alert dialog so you can test easily on emulators
      _showIncomingCallDialog(caller, isVideo);

      var callKitParams = CallKitParams(
        id:
            mapData['callId'] ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        nameCaller: caller,
        appName: 'VibeChat Admin',
        avatar: 'https://i.pravatar.cc/100',
        handle: isVideo ? 'Video Call' : 'Audio Call',
        type: isVideo ? 1 : 0,
        duration: 30000,
        extra: <String, dynamic>{
          'isVideoCall': isVideo.toString(),
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
    final String callId = DateTime.now().millisecondsSinceEpoch.toString();
    widget.socket.emit('call_invite', {
      'callerName': _adminName,
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
          isVideoCall: isVideo,
          isCaller: true,
          socket: widget.socket,
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
                        msg['message']?.toString() ?? '',
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

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../services/mediasoup_call_service.dart';

class CallScreen extends StatefulWidget {
  final String callerName;
  final bool isVideoCall;
  final bool isCaller;
  final io.Socket socket;

  const CallScreen({
    super.key,
    required this.callerName,
    required this.isVideoCall,
    required this.isCaller,
    required this.socket,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  late MediasoupCallService _callService;

  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isConnecting = true;

  @override
  void initState() {
    super.initState();
    _initRenderersAndCall();
  }

  Future<void> _initRenderersAndCall() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _callService = MediasoupCallService(socket: widget.socket);

    _callService.onLocalStream = (stream) {
      if (mounted) {
        setState(() {
          _localRenderer.srcObject = stream;
        });
      }
    };

    _callService.onRemoteStream = (stream) {
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
          _isConnecting = false;
        });
      }
    };

    // Socket listener for remote end-call
    widget.socket.on('end-call', (_) {
      if (mounted) {
        _endCall(shouldEmit: false);
      }
    });

    try {
      await _callService.initCall(isVideo: widget.isVideoCall);
    } catch (e) {
      debugPrint('Error initializing Mediasoup call: $e');
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _callService.localStream?.getAudioTracks().forEach((track) {
        track.enabled = !_isMuted;
      });
    });
  }

  void _toggleVideo() {
    setState(() {
      _isVideoOff = !_isVideoOff;
      _callService.localStream?.getVideoTracks().forEach((track) {
        track.enabled = !_isVideoOff;
      });
    });
  }

  void _endCall({bool shouldEmit = true}) {
    if (shouldEmit) {
      widget.socket.emit('end-call');
    }
    _callService.endCall();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _callService.endCall();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote Video or Audio Avatar
            if (widget.isVideoCall && !_isVideoOff)
              Positioned.fill(
                child: RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              )
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.blueAccent,
                      child: Text(
                        widget.callerName.isNotEmpty
                            ? widget.callerName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 40,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.callerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isConnecting ? 'Connecting via SFU...' : 'Connected',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),

            // Local Preview (Top Right Thumbnail)
            if (widget.isVideoCall && !_isVideoOff)
              Positioned(
                top: 20,
                right: 20,
                width: 110,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),

            // Bottom Call Controls
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    iconSize: 32,
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: _isMuted
                          ? Colors.redAccent
                          : Colors.white24,
                      padding: const EdgeInsets.all(12),
                    ),
                    icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                    onPressed: _toggleMute,
                  ),
                  IconButton(
                    iconSize: 36,
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.all(14),
                    ),
                    icon: const Icon(Icons.call_end),
                    onPressed: () => _endCall(shouldEmit: true),
                  ),
                  if (widget.isVideoCall)
                    IconButton(
                      iconSize: 32,
                      color: Colors.white,
                      style: IconButton.styleFrom(
                        backgroundColor: _isVideoOff
                            ? Colors.redAccent
                            : Colors.white24,
                        padding: const EdgeInsets.all(12),
                      ),
                      icon: Icon(
                        _isVideoOff ? Icons.videocam_off : Icons.videocam,
                      ),
                      onPressed: _toggleVideo,
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

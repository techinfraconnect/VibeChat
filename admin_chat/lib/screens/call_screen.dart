import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class CallScreen extends StatefulWidget {
  final String callerName;
  final String targetUser;
  final bool isVideoCall;
  final bool isCaller;
  final io.Socket socket;
  final bool clientCanMute;
  final bool isAdmin;

  const CallScreen({
    super.key,
    required this.callerName,
    required this.targetUser,
    required this.isVideoCall,
    required this.isCaller,
    required this.socket,
    this.clientCanMute = true,
    this.isAdmin = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _isConnecting = true;
  bool _isMuted = false;
  bool _isSpeakerOn = false; // Tracks speaker vs earpiece state
  bool _isFrontCamera = true;
  late bool _canMute;

  double _pipTop = 60.0;
  double _pipLeft = -1.0;

  bool _isRemoteDescriptionSet = false;
  final List<RTCIceCandidate> _remoteCandidatesQueue = [];
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _canMute = widget.clientCanMute;
    _initRenderers();
    _initWebRTC();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _initWebRTC() async {
    // 1. Audio routing configuration: 
    // Audio calls default to earpiece (false), video calls default to speakerphone (true)
    _isSpeakerOn = widget.isVideoCall;
    await Helper.setSpeakerphoneOn(_isSpeakerOn);

    // 2. Video constraints optimization to prevent video lagging
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.isVideoCall
          ? {
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '30',
                'maxWidth': '1280',
                'maxHeight': '720',
                'maxFrameRate': '30',
              },
              'facingMode': 'user',
            }
          : false,
    });
    _localRenderer.srcObject = _localStream;

    Map<String, dynamic> configuration = {
      "iceServers": [
        {"urls": "stun:stun.l.google.com:19302"},
        {
          "urls": "turn:openrelay.metered.ca:80",
          "username": "openrelayproject",
          "credential": "openrelayproject",
        },
        {
          "urls": "turn:openrelay.metered.ca:443",
          "username": "openrelayproject",
          "credential": "openrelayproject",
        },
      ],
    };

    _peerConnection = await createPeerConnection(configuration);

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty && mounted && !_isDisposed) {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
          _isConnecting = false;
        });
      }
    };

    _peerConnection?.onAddStream = (MediaStream stream) {
      if (mounted && !_isDisposed) {
        setState(() {
          _remoteRenderer.srcObject = stream;
          _isConnecting = false;
        });
      }
    };

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      widget.socket.emit('ice-candidate', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        if (mounted && !_isDisposed) setState(() => _isConnecting = false);
      }
    };

    _setupSocketListeners();

    if (!widget.isCaller) {
      widget.socket.emit('call_accepted');
    }
  }

  void _setupSocketListeners() {
    widget.socket.on('call_ready_for_offer', (_) async {
      if (widget.isCaller && _peerConnection != null) {
        RTCSessionDescription offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);
        widget.socket.emit('offer', {'sdp': offer.sdp, 'type': offer.type});
      }
    });

    widget.socket.on('offer', (data) async {
      if (!widget.isCaller && _peerConnection != null) {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data['sdp'], data['type']),
        );
        _isRemoteDescriptionSet = true;
        _processCandidateQueue();

        RTCSessionDescription answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        widget.socket.emit('answer', {'sdp': answer.sdp, 'type': answer.type});
      }
    });

    widget.socket.on('answer', (data) async {
      if (widget.isCaller && _peerConnection != null) {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data['sdp'], data['type']),
        );
        _isRemoteDescriptionSet = true;
        _processCandidateQueue();
      }
    });

    widget.socket.on('ice-candidate', (data) async {
      if (data['candidate'] != null && _peerConnection != null) {
        RTCIceCandidate candidate = RTCIceCandidate(
          data['candidate'],
          data['sdpMid'],
          data['sdpMLineIndex'],
        );

        if (_isRemoteDescriptionSet) {
          await _peerConnection!.addCandidate(candidate);
        } else {
          _remoteCandidatesQueue.add(candidate);
        }
      }
    });

    widget.socket.on('update_settings', (data) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _canMute = data['clientCanMute'] ?? true;
        if (!widget.isAdmin && !_canMute && _isMuted) {
          _toggleMute();
        }
      });
    });

    widget.socket.on('end-call', (_) => _endCallLocally());
    widget.socket.on('call_rejected', (_) => _endCallLocally());
    widget.socket.on('cancel_call', (_) => _endCallLocally());
  }

  void _processCandidateQueue() {
    for (var candidate in _remoteCandidatesQueue) {
      _peerConnection!.addCandidate(candidate);
    }
    _remoteCandidatesQueue.clear();
  }

  Future<void> _toggleMute() async {
    if (!widget.isAdmin && !_canMute) return;

    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      bool newState = !_isMuted;
      _localStream!.getAudioTracks()[0].enabled = !newState;

      var senders = await _peerConnection!.getSenders();
      for (var sender in senders) {
        if (sender.track?.kind == 'audio') {
          sender.track?.enabled = !newState;
        }
      }

      if (mounted && !_isDisposed) {
        setState(() {
          _isMuted = newState;
        });
      }
    }
  }

  // Toggle between Earpiece and Speakerphone
  Future<void> _toggleSpeaker() async {
    bool newSpeakerState = !_isSpeakerOn;
    await Helper.setSpeakerphoneOn(newSpeakerState);
    if (mounted && !_isDisposed) {
      setState(() {
        _isSpeakerOn = newSpeakerState;
      });
    }
  }

  void _toggleCamera() async {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      final videoTrack = _localStream!.getVideoTracks().first;
      await Helper.switchCamera(videoTrack);
      if (mounted && !_isDisposed) {
        setState(() {
          _isFrontCamera = !_isFrontCamera;
        });
      }
    }
  }

  void _endCall() {
    // Fixes ringing sync bug when caller hangs up before pickup
    widget.socket.emit('cancel_call');
    widget.socket.emit('end-call');
    _endCallLocally();
  }

  void _endCallLocally() {
    if (_isDisposed) return;
    _isDisposed = true;

    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      _peerConnection?.close();
    } catch (_) {}

    widget.socket.off('call_ready_for_offer');
    widget.socket.off('offer');
    widget.socket.off('answer');
    widget.socket.off('ice-candidate');
    widget.socket.off('update_settings');
    widget.socket.off('end-call');
    widget.socket.off('call_rejected');
    widget.socket.off('cancel_call');

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      _peerConnection?.close();
    } catch (_) {}

    widget.socket.off('call_ready_for_offer');
    widget.socket.off('offer');
    widget.socket.off('answer');
    widget.socket.off('ice-candidate');
    widget.socket.off('update_settings');
    widget.socket.off('end-call');
    widget.socket.off('call_rejected');
    widget.socket.off('cancel_call');

    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    if (_pipLeft == -1.0) {
      _pipLeft = screenWidth - 130.0;
    }

    bool showMuteButton = widget.isAdmin || _canMute;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0E),
      body: Stack(
        children: [
          if (!_isConnecting && widget.isVideoCall)
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
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 1.5,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 55,
                      backgroundColor: const Color(0xFF1C1C1E),
                      child: Text(
                        widget.targetUser.isNotEmpty
                            ? widget.targetUser[0].toUpperCase()
                            : "U",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.targetUser,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isConnecting
                        ? "Connecting..."
                        : (widget.isVideoCall
                            ? "Video Paused"
                            : "Secure Audio Call"),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),

          if (!_isConnecting && widget.isVideoCall)
            Positioned(
              left: _pipLeft,
              top: _pipTop,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _pipLeft += details.delta.dx;
                    _pipTop += details.delta.dy;
                    _pipLeft = _pipLeft.clamp(16.0, screenWidth - 126.0);
                    _pipTop = _pipTop.clamp(40.0, screenHeight - 200.0);
                  });
                },
                child: Container(
                  width: 110,
                  height: 160,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: _isFrontCamera,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            ),

          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(35),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2E).withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(35),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.isVideoCall) ...[
                          _buildGlassButton(
                            icon: Icons.cameraswitch_rounded,
                            onPressed: _toggleCamera,
                            isActive: false,
                          ),
                          const SizedBox(width: 16),
                        ],

                        // Speaker / Earpiece Toggle Button
                        _buildGlassButton(
                          icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
                          onPressed: _toggleSpeaker,
                          isActive: _isSpeakerOn,
                        ),
                        const SizedBox(width: 16),

                        if (showMuteButton) ...[
                          _buildGlassButton(
                            icon: _isMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            onPressed: _toggleMute,
                            isActive: _isMuted,
                          ),
                          const SizedBox(width: 16),
                        ],

                        _buildGlassButton(
                          icon: Icons.call_end_rounded,
                          onPressed: _endCall,
                          isDestructive: true,
                          isActive: false,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassButton({
    required IconData icon,
    required VoidCallback onPressed,
    required bool isActive,
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDestructive
              ? const Color(0xFFFF3B30)
              : (isActive
                  ? Colors.white
                  : const Color(0xFF3A3A3C).withValues(alpha: 0.8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: isDestructive
              ? Colors.white
              : (isActive ? Colors.black : Colors.white),
          size: 24,
        ),
      ),
    );
  }
}
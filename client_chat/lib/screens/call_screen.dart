import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class CallScreen extends StatefulWidget {
  final String callerName;
  final bool isVideoCall;
  final bool isCaller;
  final IO.Socket socket;

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
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;
  bool _isRemoteConnected = false;

  String _callStatus = "Connecting...";

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  // Helper to determine the device's own name
  String get myName => widget.callerName == 'Admin' ? 'Client' : 'Admin';

  @override
  void initState() {
    super.initState();
    _initCallSession();
  }

  Future<void> _initCallSession() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    await _startLocalStream();
    _setupSignalingListeners();
  }

  // ---------------------------------------------------------
  // PIGGYBACK PROTOCOL EMITTER
  // ---------------------------------------------------------
  void _sendSignal(String type, Map<String, dynamic> data) {
    widget.socket.emit('send_message', {
      'sender': 'SYSTEM_SIGNAL',
      'fromDevice': myName,
      'signalType': type,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ---------------------------------------------------------
  // PIGGYBACK PROTOCOL RECEIVER
  // ---------------------------------------------------------
  void _onSignalReceived(dynamic payload) async {
    if (!mounted) return;
    try {
      final msg = Map<String, dynamic>.from(
        payload is List ? payload.first : payload,
      );

      // We only care about SYSTEM_SIGNAL
      if (msg['sender'] != 'SYSTEM_SIGNAL') return;
      // We ignore echoes of our own signals
      if (msg['fromDevice'] == myName) return;

      final type = msg['signalType'];
      final data = msg['data'] != null
          ? Map<String, dynamic>.from(msg['data'])
          : {};

      if (type == 'call_accepted' && widget.isCaller) {
        if (mounted)
          setState(() => _callStatus = "Establishing Secure Call...");
        RTCSessionDescription offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);
        _sendSignal('offer', {'type': offer.type, 'sdp': offer.sdp});
      } else if (type == 'call_rejected') {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Call was declined')));
        Navigator.pop(context);
      } else if (type == 'offer' && !widget.isCaller) {
        if (_peerConnection == null) await _createPeerConnection();
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data['sdp'], data['type']),
        );
        RTCSessionDescription answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        _sendSignal('answer', {'type': answer.type, 'sdp': answer.sdp});
      } else if (type == 'answer' && widget.isCaller) {
        await _peerConnection?.setRemoteDescription(
          RTCSessionDescription(data['sdp'], data['type']),
        );
      } else if (type == 'ice-candidate') {
        if (_peerConnection != null) {
          RTCIceCandidate candidate = RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );
          await _peerConnection!.addCandidate(candidate);
        }
      } else if (type == 'end-call') {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      print('Signal Parse Error: $e');
    }
  }

  void _setupSignalingListeners() async {
    print(
      '🟢 CallScreen Active (isCaller: ${widget.isCaller}) using Shared Socket via Piggyback',
    );
    await _createPeerConnection();

    // Attach listener for all incoming signals
    widget.socket.on('receive_message', _onSignalReceived);

    if (widget.isCaller) {
      setState(() => _callStatus = "Ringing...");
      _sendSignal('call_invite', {
        'callerName': myName,
        'isVideoCall': widget.isVideoCall,
      });
    } else {
      setState(() => _callStatus = "Connecting secure line...");
      // Receiver tells Caller "I am ready"
      _sendSignal('call_accepted', {});
    }
  }

  Future<void> _startLocalStream() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': widget.isVideoCall
          ? {'facingMode': _isFrontCamera ? 'user' : 'environment'}
          : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );
      _localRenderer.srcObject = _localStream;
      setState(() {});
    } catch (e) {
      print('Error accessing media devices: $e');
    }
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceServers);

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
    }

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
          _isRemoteConnected = true;
          _callStatus = "Connected Live";
        });
      }
    };

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate != null) {
        _sendSignal('ice-candidate', {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };
  }

  @override
  void dispose() {
    _sendSignal('end-call', {});

    // Specifically unbind the Piggyback listener so it doesn't leak
    widget.socket.off('receive_message', _onSignalReceived);

    _localStream?.dispose();
    _peerConnection?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();

    super.dispose();
  }

  void _toggleMic() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
  }

  void _toggleVideo() {
    setState(() {
      _isVideoOff = !_isVideoOff;
    });
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = !_isVideoOff;
    });
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    Helper.setSpeakerphoneOn(_isSpeakerOn);
  }

  Future<void> _toggleCameraDirection() async {
    if (_localStream != null && widget.isVideoCall) {
      final videoTrack = _localStream!.getVideoTracks().first;
      await Helper.switchCamera(videoTrack);
      setState(() {
        _isFrontCamera = !_isFrontCamera;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
      body: SafeArea(
        child: Stack(
          children: [
            widget.isVideoCall && _isRemoteConnected
                ? Stack(
                    children: [
                      Positioned.fill(
                        child: RTCVideoView(_remoteRenderer, mirror: false),
                      ),
                      Positioned(
                        top: 20,
                        right: 20,
                        child: Container(
                          width: 100,
                          height: 150,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24, width: 2),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: RTCVideoView(_localRenderer, mirror: true),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 20,
                        left: 20,
                        child: IconButton(
                          icon: const Icon(
                            Icons.flip_camera_ios_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: _toggleCameraDirection,
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2)],
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 45,
                            backgroundColor: Colors.grey.shade800,
                            child: Text(
                              widget.callerName.isNotEmpty
                                  ? widget.callerName
                                        .substring(0, 2)
                                        .toUpperCase()
                                  : 'VM',
                              style: const TextStyle(
                                fontSize: 28,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.callerName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _callStatus,
                          style: TextStyle(
                            fontSize: 14,
                            color: _isRemoteConnected
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                          ),
                        ),
                      ],
                    ),
                  ),

            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2C),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildControlButton(
                          icon: _isMuted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          label: _isMuted ? 'Muted' : 'Mic On',
                          isActive: _isMuted,
                          onPressed: _toggleMic,
                        ),
                        if (widget.isVideoCall)
                          _buildControlButton(
                            icon: _isVideoOff
                                ? Icons.videocam_off_rounded
                                : Icons.videocam_rounded,
                            label: _isVideoOff ? 'Video Off' : 'Video On',
                            isActive: _isVideoOff,
                            onPressed: _toggleVideo,
                          ),
                        _buildControlButton(
                          icon: _isSpeakerOn
                              ? Icons.volume_up_rounded
                              : Icons.hearing_rounded,
                          label: 'Speaker',
                          isActive: false,
                          onPressed: _toggleSpeaker,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.call_end_rounded,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'End call',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
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

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isActive ? Colors.white : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.black : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

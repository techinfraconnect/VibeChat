import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class CallScreen extends StatefulWidget {
  final String callerName;
  final bool isVideoCall;
  final bool
  isCaller; // true if this device initiated the call, false if receiving
  final IO.Socket socket; // <--- The shared socket passed from ChatScreen

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

  // Dynamic status to show the user exactly what is happening
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

  void _setupSignalingListeners() async {
    print(
      '🟢 CallScreen Active (isCaller: ${widget.isCaller}) using Shared Socket',
    );

    await _createPeerConnection();

    // Since the socket is ALREADY connected from ChatScreen,
    // we execute the caller logic immediately.
    if (widget.isCaller) {
      setState(() => _callStatus = "Ringing...");

      // Determine my own name based on the target callerName
      String myName = widget.callerName == 'Admin' ? 'Client' : 'Admin';

      // 1. Send the ring invite to the other device
      widget.socket.emit('call_invite', {
        'callerName': myName,
        'isVideoCall': widget.isVideoCall,
      });
    } else {
      setState(() => _callStatus = "Connecting secure line...");
    }

    // 2. The receiver accepted! NOW we generate and send the WebRTC offer.
    widget.socket.on('call_ready_for_offer', (_) async {
      if (mounted) setState(() => _callStatus = "Establishing Secure Call...");

      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      widget.socket.emit('offer', {'type': offer.type, 'sdp': offer.sdp});
    });

    // 3. The receiver declined the call.
    widget.socket.on('call_rejected', (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Call was declined')));
        Navigator.pop(context);
      }
    });

    // 4. Handle standard WebRTC exchanges
    widget.socket.on('offer', (data) async {
      if (_peerConnection == null) await _createPeerConnection();
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(data['sdp'], data['type']),
      );
      RTCSessionDescription answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      widget.socket.emit('answer', {'type': answer.type, 'sdp': answer.sdp});
    });

    widget.socket.on('answer', (data) async {
      await _peerConnection?.setRemoteDescription(
        RTCSessionDescription(data['sdp'], data['type']),
      );
    });

    widget.socket.on('ice-candidate', (data) async {
      if (data != null && _peerConnection != null) {
        RTCIceCandidate candidate = RTCIceCandidate(
          data['candidate'],
          data['sdpMid'],
          data['sdpMLineIndex'],
        );
        await _peerConnection!.addCandidate(candidate);
      }
    });

    widget.socket.on('end-call', (_) {
      if (mounted) Navigator.pop(context);
    });
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
        widget.socket.emit('ice-candidate', {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };
  }

  @override
  void dispose() {
    widget.socket.emit('end-call');

    // Clean up ONLY CallScreen listeners so the ChatScreen socket stays clean
    widget.socket.off('call_ready_for_offer');
    widget.socket.off('call_rejected');
    widget.socket.off('offer');
    widget.socket.off('answer');
    widget.socket.off('ice-candidate');
    widget.socket.off('end-call');

    _localStream?.dispose();
    _peerConnection?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();

    // DO NOT DISPOSE THE SOCKET HERE (It belongs to ChatScreen)
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

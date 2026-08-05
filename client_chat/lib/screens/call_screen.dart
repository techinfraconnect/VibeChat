import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class CallScreen extends StatefulWidget {
  final String callerName;
  final String targetUser;
  final bool isVideoCall;
  final bool isCaller;
  final io.Socket socket;

  const CallScreen({
    super.key,
    required this.callerName,
    required this.targetUser,
    required this.isVideoCall,
    required this.isCaller,
    required this.socket,
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

  // NEW: Camera state
  bool _isFrontCamera = true;

  // NEW: PIP Positioning state
  double _pipTop = 40.0;
  double _pipLeft = -1.0; // -1 acts as an uninitialized flag

  bool _isRemoteDescriptionSet = false;
  final List<RTCIceCandidate> _remoteCandidatesQueue = [];

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _initWebRTC();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _initWebRTC() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.isVideoCall ? {'facingMode': 'user'} : false,
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
      debugPrint("📺 TRACK RECEIVED: ${event.track.kind}");
      if (event.streams.isNotEmpty && mounted) {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
          _isConnecting = false;
        });
      }
    };

    _peerConnection?.onAddStream = (MediaStream stream) {
      debugPrint("📺 STREAM RECEIVED");
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
          _isConnecting = false;
        });
      }
    };

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      debugPrint("🧊 Sending Local ICE Candidate");
      widget.socket.emit('ice-candidate', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('📶 ICE Connection State: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        if (mounted) setState(() => _isConnecting = false);
      }
    };

    _setupSocketListeners();

    if (!widget.isCaller) {
      widget.socket.emit('call_accepted');
    }
  }

  void _setupSocketListeners() {
    widget.socket.on('call_ready_for_offer', (_) async {
      debugPrint("📞 Receiver is ready. Creating Offer...");
      if (widget.isCaller && _peerConnection != null) {
        RTCSessionDescription offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);
        widget.socket.emit('offer', {'sdp': offer.sdp, 'type': offer.type});
      }
    });

    widget.socket.on('offer', (data) async {
      debugPrint("📦 Received Offer. Creating Answer...");
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
      debugPrint("📦 Received Answer.");
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

    widget.socket.on('end-call', (_) => _endCallLocally());
    widget.socket.on('call_rejected', (_) => _endCallLocally());
  }

  void _processCandidateQueue() {
    for (var candidate in _remoteCandidatesQueue) {
      _peerConnection!.addCandidate(candidate);
    }
    _remoteCandidatesQueue.clear();
  }

  void _toggleMute() {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      bool isCurrentlyEnabled = _localStream!.getAudioTracks()[0].enabled;
      _localStream!.getAudioTracks()[0].enabled = !isCurrentlyEnabled;

      setState(() {
        _isMuted = !isCurrentlyEnabled;
      });
    }
  }

  // NEW: Toggle between front and back camera
  void _toggleCamera() async {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      final videoTrack = _localStream!.getVideoTracks().first;
      await Helper.switchCamera(videoTrack);
      setState(() {
        _isFrontCamera = !_isFrontCamera;
      });
    }
  }

  void _endCall() {
    widget.socket.emit('end-call');
    _endCallLocally();
  }

  void _endCallLocally() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _peerConnection?.close();

    widget.socket.off('call_ready_for_offer');
    widget.socket.off('offer');
    widget.socket.off('answer');
    widget.socket.off('ice-candidate');
    widget.socket.off('end-call');
    widget.socket.off('call_rejected');

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Initialize PIP position to top-right on the first build
    if (_pipLeft == -1.0) {
      _pipLeft = screenWidth - 120.0; // 100 width + 20 padding
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote Media (Fullscreen)
          if (!_isConnecting && widget.isVideoCall)
            RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.indigo[200],
                    child: Icon(
                      Icons.person,
                      size: 50,
                      color: Colors.indigo[800],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.targetUser,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isConnecting
                        ? "Connecting WebRTC..."
                        : (widget.isVideoCall
                              ? "Video Paused"
                              : "Audio Call Active"),
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),

          // NEW: Draggable Local Media (Picture-in-Picture)
          if (!_isConnecting && widget.isVideoCall)
            Positioned(
              left: _pipLeft,
              top: _pipTop,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _pipLeft += details.delta.dx;
                    _pipTop += details.delta.dy;

                    // Clamping ensures the PIP doesn't get dragged off-screen
                    _pipLeft = _pipLeft.clamp(0.0, screenWidth - 100.0);
                    _pipTop = _pipTop.clamp(0.0, screenHeight - 150.0);
                  });
                },
                child: Container(
                  width: 100,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: RTCVideoView(
                      _localRenderer,
                      // Turn off mirroring when using the back camera so text is readable
                      mirror: _isFrontCamera,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            ),

          // Controls
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Camera Switch Button (Only visible during video calls)
                if (widget.isVideoCall)
                  FloatingActionButton(
                    heroTag: "camera_switch_btn",
                    backgroundColor: Colors.grey[800],
                    onPressed: _toggleCamera,
                    child: const Icon(Icons.cameraswitch, color: Colors.white),
                  ),

                // Mute Button
                FloatingActionButton(
                  heroTag: "mute_btn",
                  backgroundColor: _isMuted ? Colors.red : Colors.grey[800],
                  onPressed: _toggleMute,
                  child: Icon(
                    _isMuted ? Icons.mic_off : Icons.mic,
                    color: Colors.white,
                  ),
                ),

                // End Call Button
                FloatingActionButton(
                  heroTag: "end_btn",
                  backgroundColor: Colors.red,
                  onPressed: _endCall,
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

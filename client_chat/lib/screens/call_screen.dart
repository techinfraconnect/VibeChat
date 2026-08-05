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
    // 1. Get Local Media (Camera & Mic)
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.isVideoCall ? {'facingMode': 'user'} : false,
    });
    _localRenderer.srcObject = _localStream;

    // 2. Setup Peer Connection with Public Google STUN Servers
    // This is strictly required for the Emulator and Phone to find each other over the internet.
    Map<String, dynamic> configuration = {
      "iceServers": [
        {"urls": "stun:stun.l.google.com:19302"},
        {"urls": "stun:stun1.l.google.com:19302"},
        {"urls": "stun:stun2.l.google.com:19302"},
      ],
    };

    _peerConnection = await createPeerConnection(configuration);

    // 3. Add local tracks to WebRTC connection
    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    // 4. Listen for incoming remote media
    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
          _isConnecting = false; // Media stream established!
        });
      }
    };

    // 5. Send ICE network candidates to the other device
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      widget.socket.emit('ice-candidate', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // 6. Register Socket WebRTC Listeners
    _setupSocketListeners();

    // 7. PREVENT RACE CONDITION:
    // Now that we are fully listening, tell the server the receiver is actually ready.
    if (!widget.isCaller) {
      widget.socket.emit('call_accepted');
    }
  }

  void _setupSocketListeners() {
    // CALLER gets this to initiate the Offer
    widget.socket.on('call_ready_for_offer', (_) async {
      if (widget.isCaller && _peerConnection != null) {
        RTCSessionDescription offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);
        widget.socket.emit('offer', {'sdp': offer.sdp, 'type': offer.type});
      }
    });

    // RECEIVER gets Offer, creates Answer
    widget.socket.on('offer', (data) async {
      if (!widget.isCaller && _peerConnection != null) {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data['sdp'], data['type']),
        );
        RTCSessionDescription answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        widget.socket.emit('answer', {'sdp': answer.sdp, 'type': answer.type});
      }
    });

    // CALLER gets Answer
    widget.socket.on('answer', (data) async {
      if (widget.isCaller && _peerConnection != null) {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data['sdp'], data['type']),
        );
      }
    });

    // BOTH exchange network candidates
    widget.socket.on('ice-candidate', (data) async {
      if (data['candidate'] != null && _peerConnection != null) {
        await _peerConnection!.addCandidate(
          RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          ),
        );
      }
    });

    widget.socket.on('end-call', (_) => _endCallLocally());
    widget.socket.on('call_rejected', (_) => _endCallLocally());
  }

  void _endCall() {
    widget.socket.emit('end-call');
    _endCallLocally();
  }

  void _endCallLocally() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _peerConnection?.close();

    // Purge listeners so they don't fire multiple times on the next call
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

          // Local Media (Picture-in-Picture)
          if (!_isConnecting && widget.isVideoCall)
            Positioned(
              right: 20,
              top: 40,
              child: Container(
                width: 100,
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: RTCVideoView(_localRenderer, mirror: true),
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
                FloatingActionButton(
                  heroTag: "mute_btn",
                  backgroundColor: Colors.grey[800],
                  onPressed: () {
                    if (_localStream != null) {
                      bool enabled = _localStream!.getAudioTracks()[0].enabled;
                      _localStream!.getAudioTracks()[0].enabled = !enabled;
                    }
                  },
                  child: const Icon(Icons.mic, color: Colors.white),
                ),
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

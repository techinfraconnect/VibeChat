import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class CallScreen extends StatefulWidget {
  final String callerName;
  final String targetUser;
  final bool isVideoCall;
  final bool isCaller;
  final IO.Socket socket;

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
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _initCallFlow();
  }

  Future<void> _initCallFlow() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    await _setupPeerConnection();

    _setupSocketListeners();

    if (!widget.isCaller) {
      // Receiver emits acceptance signal to trigger caller's offer
      widget.socket.emit('call_accepted', {'targetUser': widget.targetUser});
    }
  }

  Future<void> _setupPeerConnection() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.isVideoCall
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
              }
            : false,
      });

      if (widget.isVideoCall) {
        _localRenderer.srcObject = _localStream;
      }

      _peerConnection = await createPeerConnection({
        'iceServers': [
          {
            'urls': [
              'stun:stun.l.google.com:19302',
              'stun:stun1.l.google.com:19302',
            ],
          },
        ],
      });

      _localStream?.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });

      _peerConnection?.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteRenderer.srcObject = event.streams[0];
          if (mounted) setState(() => _isConnected = true);
        }
      };

      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        widget.socket.emit('ice-candidate', candidate.toMap());
      };
    } catch (e) {
      print('❌ WebRTC Setup Error: $e');
    }
  }

  void _setupSocketListeners() {
    widget.socket.off('call_ready_for_offer');
    widget.socket.off('offer');
    widget.socket.off('answer');
    widget.socket.off('ice-candidate');
    widget.socket.off('call_rejected');
    widget.socket.off('end-call');

    // Triggered on Caller when Receiver clicks Accept
    widget.socket.on('call_ready_for_offer', (_) async {
      if (widget.isCaller) {
        await _createAndSendOffer();
      }
    });

    widget.socket.on('offer', (data) async {
      if (widget.isCaller) return;
      try {
        var offer = RTCSessionDescription(data['sdp'], data['type']);
        await _peerConnection?.setRemoteDescription(offer);

        RTCSessionDescription answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);

        widget.socket.emit('answer', answer.toMap());
      } catch (e) {
        print('❌ Offer Handling Error: $e');
      }
    });

    widget.socket.on('answer', (data) async {
      if (!widget.isCaller) return;
      try {
        var answer = RTCSessionDescription(data['sdp'], data['type']);
        await _peerConnection?.setRemoteDescription(answer);
        if (mounted) setState(() => _isConnected = true);
      } catch (e) {
        print('❌ Answer Handling Error: $e');
      }
    });

    widget.socket.on('ice-candidate', (data) async {
      if (data != null && _peerConnection != null) {
        try {
          var candidate = RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );
          await _peerConnection?.addCandidate(candidate);
        } catch (e) {
          print('❌ ICE Candidate Error: $e');
        }
      }
    });

    widget.socket.on('call_rejected', (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Call declined by user.')));
        _cleanUpAndExit();
      }
    });

    widget.socket.on('end-call', (_) {
      _cleanUpAndExit();
    });
  }

  Future<void> _createAndSendOffer() async {
    if (_peerConnection == null) return;
    try {
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      widget.socket.emit('offer', offer.toMap());
    } catch (e) {
      print('❌ Offer Creation Error: $e');
    }
  }

  void _endCall() {
    widget.socket.emit('end-call');
    _cleanUpAndExit();
  }

  void _cleanUpAndExit() {
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _peerConnection?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    widget.socket.off('call_ready_for_offer');
    widget.socket.off('offer');
    widget.socket.off('answer');
    widget.socket.off('ice-candidate');
    widget.socket.off('call_rejected');
    widget.socket.off('end-call');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (widget.isVideoCall)
              Positioned.fill(
                child: RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            if (widget.isVideoCall)
              Positioned(
                top: 20,
                right: 20,
                child: Container(
                  width: 110,
                  height: 160,
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            if (!widget.isVideoCall || !_isConnected)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.account_circle,
                      size: 100,
                      color: Colors.white54,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _isConnected
                          ? "In Call with ${widget.callerName}"
                          : "Calling ${widget.callerName}...",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: _endCall,
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

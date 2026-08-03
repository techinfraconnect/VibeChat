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
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _initRenderers().then((_) {
      _setupSocketListeners();
      _startCall();
    });
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.dispose();
    _peerConnection?.dispose();

    widget.socket.off('offer');
    widget.socket.off('answer');
    widget.socket.off('ice-candidate');
    widget.socket.off('call_ready_for_offer');
    widget.socket.off('end-call');
    super.dispose();
  }

  void _setupSocketListeners() {
    widget.socket.on('call_ready_for_offer', (_) async {
      if (widget.isCaller) {
        await _createAndSendOffer();
      }
    });

    widget.socket.on('offer', (data) async {
      if (widget.isCaller) return;

      var offer = RTCSessionDescription(data['sdp'], data['type']);
      await _peerConnection?.setRemoteDescription(offer);

      RTCSessionDescription answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      widget.socket.emit('answer', answer.toMap());
    });

    widget.socket.on('answer', (data) async {
      if (!widget.isCaller) return;

      var answer = RTCSessionDescription(data['sdp'], data['type']);
      await _peerConnection?.setRemoteDescription(answer);
      if (mounted) {
        setState(() => _isConnected = true);
      }
    });

    widget.socket.on('ice-candidate', (data) async {
      if (data != null) {
        var candidate = RTCIceCandidate(
          data['candidate'],
          data['sdpMid'],
          data['sdpMLineIndex'],
        );
        await _peerConnection?.addCandidate(candidate);
      }
    });

    widget.socket.on('end-call', (_) {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  Future<void> _startCall() async {
    await _setupPeerConnection();
    if (widget.isCaller) {
      await _createAndSendOffer();
    }
  }

  Future<void> _createAndSendOffer() async {
    if (_peerConnection == null) return;
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    widget.socket.emit('offer', offer.toMap());
  }

  Future<void> _setupPeerConnection() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.isVideoCall,
    });

    if (widget.isVideoCall) {
      _localRenderer.srcObject = _localStream;
    }

    _peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    _peerConnection?.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams[0];
        if (mounted) {
          setState(() => _isConnected = true);
        }
      }
    };

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      widget.socket.emit('ice-candidate', candidate.toMap());
    };

    if (mounted) {
      setState(() {});
    }
  }

  void _endCall() {
    widget.socket.emit('end-call');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
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
                  width: 100,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            if (!widget.isVideoCall)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person, size: 100, color: Colors.white54),
                    const SizedBox(height: 20),
                    Text(
                      _isConnected
                          ? "Connected to ${widget.callerName}"
                          : "Calling ${widget.callerName}...",
                      style: const TextStyle(color: Colors.white, fontSize: 20),
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
                    size: 30,
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

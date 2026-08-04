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
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isCallConnected = false;

  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _initRenderersAndWebRTC();
  }

  Future<void> _initRenderersAndWebRTC() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _setupSocketListeners();
    await _createMediaStream();
    await _createPeerConnection();

    if (widget.isCaller) {
      // Caller waits for receiver to accept call before emitting Offer
    } else {
      // Receiver notifies server call is accepted
      widget.socket.emit('accept_call', {
        'callerId': widget.targetUser,
        'receiverId': 'client_123',
      });
    }
  }

  void _setupSocketListeners() {
    widget.socket.on('call_accepted', (data) async {
      if (widget.isCaller) {
        debugPrint('[WebRTC] Call accepted by remote user. Creating offer...');
        await _createOffer();
      }
    });

    widget.socket.on('offer', (data) async {
      if (!widget.isCaller && _peerConnection != null) {
        debugPrint('[WebRTC] Offer received. Setting remote description...');
        final sdp = data['offer']['sdp'];
        final type = data['offer']['type'];
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(sdp, type),
        );
        await _createAnswer();
      }
    });

    widget.socket.on('answer', (data) async {
      if (widget.isCaller && _peerConnection != null) {
        debugPrint('[WebRTC] Answer received. Setting remote description...');
        final sdp = data['answer']['sdp'];
        final type = data['answer']['type'];
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(sdp, type),
        );
      }
    });

    widget.socket.on('ice_candidate', (data) async {
      if (_peerConnection != null) {
        final candidateData = data['candidate'];
        if (candidateData != null) {
          final candidate = RTCIceCandidate(
            candidateData['candidate'],
            candidateData['sdpMid'],
            candidateData['sdpMLineIndex'],
          );
          await _peerConnection!.addCandidate(candidate);
        }
      }
    });

    widget.socket.on('call_ended', (_) {
      _endCallLocally();
    });

    widget.socket.on('call_rejected', (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Call was rejected')));
        _endCallLocally();
      }
    });
  }

  Future<void> _createMediaStream() async {
    final mediaConstraints = {
      'audio': true,
      'video': widget.isVideoCall
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localRenderer.srcObject = _localStream;
    if (mounted) setState(() {});
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_configuration);

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    _peerConnection?.onIceCandidate = (candidate) {
      if (candidate != null) {
        widget.socket.emit('ice_candidate', {
          'targetUser': widget.targetUser,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        });
      }
    };

    _peerConnection?.onTrack = (event) {
      if (event.track.kind == 'video' || event.track.kind == 'audio') {
        if (event.streams.isNotEmpty) {
          _remoteRenderer.srcObject = event.streams[0];
          if (mounted) {
            setState(() {
              _isCallConnected = true;
            });
          }
        }
      }
    };
  }

  Future<void> _createOffer() async {
    if (_peerConnection == null) return;
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    widget.socket.emit('offer', {
      'targetUser': widget.targetUser,
      'offer': {'sdp': offer.sdp, 'type': offer.type},
    });
  }

  Future<void> _createAnswer() async {
    if (_peerConnection == null) return;
    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    widget.socket.emit('answer', {
      'targetUser': widget.targetUser,
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });
  }

  void _toggleMute() {
    if (_localStream != null) {
      final audioTrack = _localStream!.getAudioTracks().firstOrNull;
      if (audioTrack != null) {
        _isMuted = !_isMuted;
        audioTrack.enabled = !_isMuted;
        setState(() {});
      }
    }
  }

  void _toggleCamera() {
    if (_localStream != null && widget.isVideoCall) {
      final videoTrack = _localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        _isCameraOff = !_isCameraOff;
        videoTrack.enabled = !_isCameraOff;
        setState(() {});
      }
    }
  }

  void _hangUp() {
    widget.socket.emit('end_call', {'targetUser': widget.targetUser});
    _endCallLocally();
  }

  void _endCallLocally() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _peerConnection?.close();
    _peerConnection = null;

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.dispose();
    _peerConnection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote Video View
            if (widget.isVideoCall)
              Positioned.fill(
                child: _isCallConnected
                    ? RTCVideoView(
                        _remoteRenderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: Alignment.center,
                          children: [
                            const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Calling ${widget.targetUser}...',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
              )
            else
              Center(
                child: Column(
                  mainAxisAlignment: Alignment.center,
                  children: [
                    const CircleAvatar(
                      radius: 50,
                      child: Icon(Icons.person, size: 50),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.targetUser,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isCallConnected
                          ? 'Audio Call In Progress'
                          : 'Connecting...',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),

            // Local Video Preview (Picture in Picture)
            if (widget.isVideoCall && !_isCameraOff)
              Positioned(
                top: 20,
                right: 20,
                width: 120,
                height: 160,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),

            // Action Buttons
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FloatingActionButton(
                    heroTag: 'client_mute',
                    onPressed: _toggleMute,
                    backgroundColor: _isMuted ? Colors.white : Colors.white24,
                    child: Icon(
                      _isMuted ? Icons.mic_off : Icons.mic,
                      color: _isMuted ? Colors.black : Colors.white,
                    ),
                  ),
                  FloatingActionButton(
                    heroTag: 'client_hangup',
                    onPressed: _hangUp,
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.call_end, color: Colors.white),
                  ),
                  if (widget.isVideoCall)
                    FloatingActionButton(
                      heroTag: 'client_cam',
                      onPressed: _toggleCamera,
                      backgroundColor: _isCameraOff
                          ? Colors.white
                          : Colors.white24,
                      child: Icon(
                        _isCameraOff ? Icons.videocam_off : Icons.videocam,
                        color: _isCameraOff ? Colors.black : Colors.white,
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
}

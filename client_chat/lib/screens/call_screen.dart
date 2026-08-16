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
    required this.clientCanMute,
    required this.isAdmin,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _isMuted = false;
  bool _isVideoOff = false;
  late bool _isSpeakerOn;
  bool _isFrontCamera = true;
  bool _isRemoteConnected = false;

  String _callStatus = "Connecting...";

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  final List<RTCIceCandidate> _queuedRemoteCandidates = [];
  bool _isRemoteDescriptionSet = false;

  Offset _pipPosition = const Offset(20, 20);

  final Map<String, dynamic> _peerConnectionConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {
        'urls': 'turn:global.relay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:global.relay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  final Map<String, dynamic> _offerSdpConstraints = {
    "mandatory": {"OfferToReceiveAudio": true, "OfferToReceiveVideo": true},
    "optional": [],
  };

  String get myName => widget.isAdmin ? 'Admin' : 'Client';

  @override
  void initState() {
    super.initState();
    _isSpeakerOn = widget.isVideoCall;
    _initCallSession();
  }

  Future<void> _initCallSession() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      await _startLocalStream();
      _setupSignalingListeners();
    } catch (e) {
      debugPrint('❌ FATAL INIT ERROR: $e');
      if (mounted) {
        setState(() {
          _callStatus = "Hardware Error";
        });
      }
    }
  }

  Future<void> _startLocalStream() async {
    try {
      final Map<String, dynamic> mediaConstraints = {
        'audio': true,
        'video': widget.isVideoCall ? {'facingMode': 'user'} : false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );
      _localRenderer.srcObject = _localStream;

      await _createPeerConnection();

      if (!widget.isCaller) {
        _sendSignal('call_accepted', {});
      }
    } catch (e) {
      debugPrint("Media Error: $e");
      _endCallLocally();
    }
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_peerConnectionConfig);

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      _sendSignal('ice-candidate', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (mounted) {
          setState(() {
            _isRemoteConnected = true;
            _callStatus = "Connected Live";
          });
        }
      }
    };

    _peerConnection!.onAddStream = (MediaStream stream) {
      _remoteRenderer.srcObject = stream;
      if (mounted) {
        setState(() {
          _isRemoteConnected = true;
          _callStatus = "Connected Live";
        });
      }
    };

    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }
  }

  void _sendSignal(String type, Map<String, dynamic> data) {
    widget.socket.emit('send_message', {
      'sender': 'SYSTEM_SIGNAL',
      'fromDevice': myName,
      'signalType': type,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void _setupSignalingListeners() {
    widget.socket.on('receive_message', _onSignalReceived);
  }

  void _onSignalReceived(dynamic payload) async {
    if (!mounted) {
      return;
    }
    try {
      final msg = Map<String, dynamic>.from(
        payload is List ? payload.first : payload,
      );

      if (msg['sender'] != 'SYSTEM_SIGNAL') {
        return;
      }
      if (msg['fromDevice'] == myName) {
        return;
      }

      String type = msg['signalType'] ?? '';

      Map<String, dynamic> data = msg['data'] != null
          ? Map<String, dynamic>.from(msg['data'] as Map)
          : <String, dynamic>{};

      if (type == 'call_accepted' && widget.isCaller) {
        RTCSessionDescription offer = await _peerConnection!.createOffer(
          _offerSdpConstraints,
        );
        await _peerConnection!.setLocalDescription(offer);
        _sendSignal('offer', {'sdp': offer.sdp, 'type': offer.type});
      } else if (type == 'offer') {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data['sdp'], data['type']),
        );
        _isRemoteDescriptionSet = true;
        RTCSessionDescription answer = await _peerConnection!.createAnswer(
          _offerSdpConstraints,
        );
        await _peerConnection!.setLocalDescription(answer);
        _sendSignal('answer', {'sdp': answer.sdp, 'type': answer.type});
        _processIceQueue();
      } else if (type == 'answer') {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data['sdp'], data['type']),
        );
        _isRemoteDescriptionSet = true;
        _processIceQueue();
      } else if (type == 'ice-candidate') {
        RTCIceCandidate candidate = RTCIceCandidate(
          data['candidate'],
          data['sdpMid'],
          data['sdpMLineIndex'] != null
              ? int.tryParse(data['sdpMLineIndex'].toString())
              : null,
        );
        if (_isRemoteDescriptionSet) {
          await _peerConnection!.addCandidate(candidate);
        } else {
          _queuedRemoteCandidates.add(candidate);
        }
      } else if (type == 'end-call' || type == 'call_rejected') {
        _endCallLocally();
      }
    } catch (e) {
      debugPrint("Signaling process error: $e");
    }
  }

  void _processIceQueue() {
    for (var candidate in _queuedRemoteCandidates) {
      _peerConnection!.addCandidate(candidate);
    }
    _queuedRemoteCandidates.clear();
  }

  void _endCallLocally() {
    _sendSignal('end-call', {});
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    widget.socket.off('receive_message', _onSignalReceived);
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        track.stop();
      }
      _localStream!.dispose();
    }
    _peerConnection?.close();
    _peerConnection?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (widget.isVideoCall && _isRemoteConnected)
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
                      radius: 60,
                      backgroundColor: Colors.grey[800],
                      child: Text(
                        widget.targetUser.isNotEmpty
                            ? widget.targetUser[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          fontSize: 50,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _callStatus,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ],
                ),
              ),
            if (widget.isVideoCall && !_isVideoOff)
              Positioned(
                left: _pipPosition.dx,
                top: _pipPosition.dy,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _pipPosition = Offset(
                        (_pipPosition.dx + details.delta.dx).clamp(
                          0.0,
                          MediaQuery.of(context).size.width - 120.0,
                        ),
                        (_pipPosition.dy + details.delta.dy).clamp(
                          0.0,
                          MediaQuery.of(context).size.height - 180.0,
                        ),
                      );
                    });
                  },
                  child: Container(
                    width: 110,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
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
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 30),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FloatingActionButton(
                      heroTag: "mute",
                      backgroundColor: _isMuted
                          ? Colors.white
                          : Colors.grey[800],
                      onPressed: () {
                        setState(() {
                          _isMuted = !_isMuted;
                          if (_localStream != null) {
                            _localStream!.getAudioTracks()[0].enabled =
                                !_isMuted;
                          }
                        });
                      },
                      child: Icon(
                        _isMuted ? Icons.mic_off : Icons.mic,
                        color: _isMuted ? Colors.black : Colors.white,
                      ),
                    ),
                    FloatingActionButton(
                      heroTag: "end",
                      backgroundColor: Colors.red,
                      onPressed: _endCallLocally,
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    FloatingActionButton(
                      heroTag: "speaker",
                      backgroundColor: _isSpeakerOn
                          ? Colors.white
                          : Colors.grey[800],
                      onPressed: () async {
                        setState(() {
                          _isSpeakerOn = !_isSpeakerOn;
                        });
                        try {
                          await Helper.setSpeakerphoneOn(_isSpeakerOn);
                        } catch (_) {}
                      },
                      child: Icon(
                        _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                        color: _isSpeakerOn ? Colors.black : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.isVideoCall)
              Positioned(
                top: 10,
                right: 10,
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isVideoOff ? Icons.videocam_off : Icons.videocam,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          _isVideoOff = !_isVideoOff;
                          if (_localStream != null) {
                            _localStream!.getVideoTracks()[0].enabled =
                                !_isVideoOff;
                          }
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.flip_camera_ios,
                        color: Colors.white,
                      ),
                      onPressed: () async {
                        if (_localStream != null) {
                          final track = _localStream!.getVideoTracks()[0];
                          await Helper.switchCamera(track);
                          setState(() {
                            _isFrontCamera = !_isFrontCamera;
                          });
                        }
                      },
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

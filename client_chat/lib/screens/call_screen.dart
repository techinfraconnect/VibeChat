import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class CallScreen extends StatefulWidget {
  final String callerName;
  final bool isVideoCall;
  final bool isCaller;
  final IO.Socket socket; // Kept to ensure your app navigation doesn't break

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

  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initRenderers();
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
    _textController.dispose();
    super.dispose();
  }

  Future<void> _setupPeerConnection() async {
    // 1. Get access to camera and microphone
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.isVideoCall,
    });

    _localRenderer.srcObject = _localStream;

    // 2. Create the Peer Connection using Google's public STUN server
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });

    // 3. Add our local camera stream to the connection
    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    // 4. Listen for the other person's stream
    _peerConnection?.onTrack = (event) {
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams[0];
        setState(() {}); // Refresh UI to show their video
      }
    };

    setState(() {});
  }

  Future<void> _createOffer() async {
    await _setupPeerConnection();

    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    // Output the connection string for you to copy
    _textController.text = jsonEncode(offer.toMap());
  }

  Future<void> _setOfferAndCreateAnswer() async {
    await _setupPeerConnection();

    // Read the offer string pasted by the user
    var offerMap = jsonDecode(_textController.text);
    RTCSessionDescription offer = RTCSessionDescription(
      offerMap['sdp'],
      offerMap['type'],
    );

    await _peerConnection!.setRemoteDescription(offer);

    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    // Output the answer string for you to copy back
    _textController.text = jsonEncode(answer.toMap());
  }

  Future<void> _setAnswer() async {
    // Read the answer string pasted by the user
    var answerMap = jsonDecode(_textController.text);
    RTCSessionDescription answer = RTCSessionDescription(
      answerMap['sdp'],
      answerMap['type'],
    );

    await _peerConnection!.setRemoteDescription(answer);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
      appBar: AppBar(
        title: const Text(
          "WebRTC Local Test",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Video Boxes
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                    ),
                    child: RTCVideoView(_localRenderer, mirror: true),
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue),
                    ),
                    child: RTCVideoView(_remoteRenderer),
                  ),
                ),
              ],
            ),
          ),

          // Connection String Text Box
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _textController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white, fontSize: 10),
              decoration: const InputDecoration(
                hintText: "Copy/Paste SDP string here...",
                hintStyle: TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.black54,
                border: OutlineInputBorder(),
              ),
            ),
          ),

          // Manual Signaling Buttons
          Padding(
            padding: const EdgeInsets.only(bottom: 20.0),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _createOffer,
                  child: const Text("1. Create Offer"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  onPressed: _setOfferAndCreateAnswer,
                  child: const Text("2. Paste Offer & Create Answer"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  onPressed: _setAnswer,
                  child: const Text("3. Paste Answer & Connect"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

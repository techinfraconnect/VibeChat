import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallScreen extends StatefulWidget {
  final String callerName;
  final bool isVideoCall;

  const CallScreen({
    super.key,
    required this.callerName,
    required this.isVideoCall,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    if (widget.isVideoCall) {
      _initRenderers();
    }
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    // WebRTC stream initialization hooks go here for production WebRTC signaling
  }

  @override
  void dispose() {
    if (widget.isVideoCall) {
      _localRenderer.dispose();
      _remoteRenderer.dispose();
    }
    super.dispose();
  }

  void _toggleCameraDirection() {
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
    // Switch camera logic for flutter_webrtc
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F), // Dark charcoal MS Teams theme
      body: SafeArea(
        child: Stack(
          children: [
            // Video Stream View or Audio Avatar View
            widget.isVideoCall
                ? Stack(
                    children: [
                      // Remote Fullscreen Video Stream
                      Positioned.fill(
                        child: RTCVideoView(_remoteRenderer, mirror: false),
                      ),
                      // Local Participant Picture-in-Picture (PiP) Floating Frame
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
                      // Camera Flip Button
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
                        // Caller Identity Display with Gradient Ring
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
                        const Text(
                          "01:09", // Active call elapsed timer
                          style: TextStyle(fontSize: 14, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),

            // Streamlined Control Bar & End Call Button
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
                          onPressed: () => setState(() => _isMuted = !_isMuted),
                        ),
                        _buildControlButton(
                          icon: _isVideoOff
                              ? Icons.videocam_off_rounded
                              : Icons.videocam_rounded,
                          label: _isVideoOff ? 'Video Off' : 'Video On',
                          isActive: _isVideoOff,
                          onPressed: () =>
                              setState(() => _isVideoOff = !_isVideoOff),
                        ),
                        _buildControlButton(
                          icon: _isSpeakerOn
                              ? Icons.volume_up_rounded
                              : Icons.hearing_rounded,
                          label: 'Speaker',
                          isActive: false,
                          onPressed: () =>
                              setState(() => _isSpeakerOn = !_isSpeakerOn),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Distinctive Prominent Red End Call Button
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

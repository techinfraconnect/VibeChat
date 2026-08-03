import 'package:flutter/material.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
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
  final _jitsiMeet = JitsiMeet();
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    // Add a slight delay to allow the screen transition to finish
    // before launching the native Jitsi UI to prevent iOS Metal crashes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _joinJitsiMeeting();
        }
      });
    });
  }

  Future<void> _joinJitsiMeeting() async {
    setState(() => _isJoining = true);

    // Determine the user's display name
    final String localUserName = widget.callerName == 'Admin'
        ? 'Client'
        : 'Admin';

    var options = JitsiMeetConferenceOptions(
      // The shared room ID. Both Admin and Client will join this exact string to connect.
      room: "vibechat_secure_room_987654321",

      // Using Jitsi's 100% free, unlimited public server
      serverURL: "https://meet.ffmuc.net",

      configOverrides: {
        "startWithAudioMuted": false,
        "startWithVideoMuted": !widget.isVideoCall,
      },
      featureFlags: {
        "welcomepage.enabled": false,
        "prejoinpage.enabled":
            false, // Skips the waiting room, connects instantly
        "resolution": 360, // Optimize for mobile connections
      },
      userInfo: JitsiMeetUserInfo(displayName: localUserName),
    );

    // This launches the native iOS/Android Jitsi UI safely
    await _jitsiMeet.join(options);

    // Once the user hangs up and the Jitsi UI closes, pop this screen to return to chat
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF8E2DE2)),
            const SizedBox(height: 20),
            Text(
              _isJoining ? "Launching secure call..." : "Preparing...",
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

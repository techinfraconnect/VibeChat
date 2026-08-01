import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // TODO: Keep your existing TextEditingController and state variables here
  final TextEditingController _messageController = TextEditingController();

  // TODO: Keep your existing sendMessage function here
  void _sendMessage() {
    if (_messageController.text.trim().isNotEmpty) {
      // Your socket send logic goes here
      print("Sending: ${_messageController.text}");
      _messageController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(
        0xFFF4F7FC,
      ), // Soft, premium off-white background
      // By default, resizeToAvoidBottomInset is true, which automatically pushes the UI up when the keyboard opens.
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70.0),
        child: AppBar(
          elevation: 10,
          shadowColor: Colors.black.withOpacity(0.3),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF4A00E0),
                  Color(0xFF8E2DE2),
                ], // Vibrant iOS-style gradient
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(25), // Smooth rounded bottom edges
              ),
            ),
          ),
          backgroundColor: Colors.transparent,
          title: const Padding(
            padding: EdgeInsets.only(top: 10.0),
            child: Text(
              'VibeChat',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 24,
                letterSpacing: 0.5,
                color: Colors.white,
              ),
            ),
          ),
          centerTitle: true,
        ),
      ),
      // THE FIX: SafeArea prevents the Android navigation buttons from overlapping the text box
      body: SafeArea(
        child: Column(
          children: [
            // ---------------------------------------------------------
            // CHAT MESSAGES AREA
            // ---------------------------------------------------------
            Expanded(
              child: Container(
                // TODO: Replace this child with your existing ListView.builder for messages
                child: const Center(
                  child: Text(
                    "No messages yet...",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ),

            // ---------------------------------------------------------
            // GLOSSY FLOATING INPUT BAR
            // ---------------------------------------------------------
            Container(
              margin: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                bottom: 12.0,
                top: 8.0,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(40), // Perfect pill shape
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 5), // Soft floating shadow
                  ),
                ],
              ),
              child: Row(
                children: [
                  const SizedBox(width: 20),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: Color(0xFFB0B0B0)),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.all(6.0),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: _sendMessage,
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

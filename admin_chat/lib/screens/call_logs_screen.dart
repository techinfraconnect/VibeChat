import 'package:flutter/material.dart';

class CallLogsScreen extends StatelessWidget {
  final List<Map<String, dynamic>> callLogs;
  final VoidCallback onClearLogs;

  const CallLogsScreen({
    super.key,
    required this.callLogs,
    required this.onClearLogs,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text("Call Logs", style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (callLogs.isNotEmpty)
            IconButton(
              icon: const Icon(
                Icons.delete_sweep_rounded,
                color: Colors.redAccent,
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1C1C1E),
                    title: const Text(
                      "Clear Call Logs",
                      style: TextStyle(color: Colors.white),
                    ),
                    content: const Text(
                      "Are you sure you want to clear all call logs?",
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          "Cancel",
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          onClearLogs();
                        },
                        child: const Text(
                          "Clear",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: callLogs.isEmpty
          ? const Center(
              child: Text(
                "No call logs yet",
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              itemCount: callLogs.length,
              itemBuilder: (context, index) {
                final log = callLogs[index];
                bool isDeclined = log['status'] == 'Declined';
                bool isMissed = log['status'] == 'Missed';

                Color statusColor = Colors.green;
                if (isDeclined || isMissed) statusColor = Colors.red;

                // Clean display without WhatsApp prefix
                String callType = log['type'].contains('Video')
                    ? 'Video Call'
                    : 'Audio Call';

                return ListTile(
                  leading: Icon(
                    callType.contains('Video')
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    color: statusColor,
                  ),
                  title: Text(
                    log['caller'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    "$callType • ${log['dateTime']}",
                    style: const TextStyle(color: Colors.white54),
                  ),
                  trailing: Text(
                    log['status'],
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

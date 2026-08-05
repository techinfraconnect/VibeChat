import 'package:flutter/material.dart';

class CallLogsScreen extends StatelessWidget {
  final List<Map<String, dynamic>> callLogs;

  const CallLogsScreen({super.key, required this.callLogs});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text("Call Logs", style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
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

                return ListTile(
                  leading: Icon(
                    log['type'].contains('Video')
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
                    "${log['type']} • ${log['dateTime']}",
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

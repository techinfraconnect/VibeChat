class AdminMessage {
  final String senderId;
  final String text;
  final int timestamp;

  AdminMessage({
    required this.senderId,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'senderId': senderId,
    'text': text,
    'timestamp': timestamp,
  };

  factory AdminMessage.fromJson(Map<dynamic, dynamic> json) => AdminMessage(
    senderId: json['senderId'] ?? '',
    text: json['text'] ?? '',
    timestamp: json['timestamp'] ?? 0,
  );
}

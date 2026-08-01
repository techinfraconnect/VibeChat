class ClientMessage {
  final String senderId;
  final String text;
  final int timestamp;

  ClientMessage({
    required this.senderId,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'senderId': senderId,
    'text': text,
    'timestamp': timestamp,
  };

  factory ClientMessage.fromJson(Map<dynamic, dynamic> json) => ClientMessage(
    senderId: json['senderId'] ?? '',
    text: json['text'] ?? '',
    timestamp: json['timestamp'] ?? 0,
  );
}

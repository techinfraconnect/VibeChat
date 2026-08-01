import 'package:firebase_database/firebase_database.dart';
import '../models/client_message_model.dart';

class ClientFirebaseService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref().child(
    'messages',
  );

  Stream<List<ClientMessage>> getMessages() {
    return _dbRef.onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];
      return data.values.map((v) => ClientMessage.fromJson(v)).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });
  }

  Future<void> sendMessage(String text) async {
    final newMessage = ClientMessage(
      senderId: 'client',
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await _dbRef.push().set(newMessage.toJson());
  }
}

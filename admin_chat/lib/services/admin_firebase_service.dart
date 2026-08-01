import 'package:firebase_database/firebase_database.dart';
import '../models/admin_message_model.dart';

class AdminFirebaseService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref().child(
    'messages',
  );

  Stream<List<AdminMessage>> getMessages() {
    return _dbRef.onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];
      return data.values.map((v) => AdminMessage.fromJson(v)).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });
  }

  Future<void> sendMessage(String text) async {
    final newMessage = AdminMessage(
      senderId: 'admin',
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await _dbRef.push().set(newMessage.toJson());
  }
}

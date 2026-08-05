import 'package:flutter_test/flutter_test.dart';
import 'package:client_chat/main.dart';

void main() {
  testWidgets('ClientChatApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // FIX: Changed ClientApp() to ClientChatApp() to match main.dart
    await tester.pumpWidget(const ClientChatApp());
  });
}

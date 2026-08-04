import 'package:flutter_test/flutter_test.dart';
import 'package:client_chat/main.dart';

void main() {
  testWidgets('ClientApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ClientApp());
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:admin_chat/main.dart';

void main() {
  testWidgets('AdminApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AdminApp());
  });
}

import 'package:defendra/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app renders home shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: DefendraApp(showOnboarding: false)));
    await tester.pump();

    expect(find.text('SCAN'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
  });
}

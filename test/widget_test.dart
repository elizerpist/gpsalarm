import 'package:flutter_test/flutter_test.dart';

import 'package:gpsalarm/main.dart';

void main() {
  testWidgets('CrashApp renders startup errors', (WidgetTester tester) async {
    await tester.pumpWidget(const CrashApp(error: 'boom'));

    expect(find.text('GPS Alarm - Crash'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });
}

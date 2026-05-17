import 'package:flutter_test/flutter_test.dart';
import 'package:vantage/main.dart';

void main() {
  testWidgets('App starts test', (WidgetTester tester) async {
    await tester.pumpWidget(const VantageApp());
    expect(find.byType(VantageApp), findsOneWidget);
  });
}

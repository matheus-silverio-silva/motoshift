import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/app.dart';

void main() {
  testWidgets('App smoke test — login screen carrega', (WidgetTester tester) async {
    await tester.pumpWidget(const MotoShiftApp());
    await tester.pumpAndSettle();
    expect(find.text('Bem-vindo'), findsOneWidget);
  });
}

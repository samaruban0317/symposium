import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symposium/main.dart';

void main() {
  testWidgets('app boots to the empty chat state', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SymposiumApp()));
    await tester.pump();
    expect(find.text('Symposium'), findsOneWidget);
    expect(find.text('The floor is yours.'), findsOneWidget);
  });
}

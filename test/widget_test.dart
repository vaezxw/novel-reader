import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('InkShelf shell shows bookshelf tab', (tester) async {
    await tester.pumpWidget(const InkShelfRoot());
    await tester.pumpAndSettle();

    expect(find.text('墨架'), findsOneWidget);
    expect(find.text('书架'), findsWidgets);
    expect(find.text('还没有书'), findsOneWidget);
  });
}

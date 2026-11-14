import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taler/main.dart';
import 'package:taler/ui/theme/chat_tokens.dart';

void main() {
  group('ChatTokens', () {
    test('formats days, sizes and phones the way the chat shows them', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10).millisecondsSinceEpoch;
      final yesterday = DateTime(now.year, now.month, now.day - 1, 10).millisecondsSinceEpoch;
      expect(ChatTokens.dayLabel(today), 'Сегодня');
      expect(ChatTokens.dayLabel(yesterday), 'Вчера');
      expect(ChatTokens.sameDay(today, today + 1000), isTrue);
      expect(ChatTokens.sameDay(today, yesterday), isFalse);
      expect(ChatTokens.fileSize(4404019), '4,2 МБ');
      expect(ChatTokens.fileSize(2048), '2 КБ');
      expect(ChatTokens.fileSize(null), '');
      expect(ChatTokens.phone(79255330598), '+7 925 533-05-98');
      expect(ChatTokens.listTime(today), ChatTokens.time(today));
    });
  });

  testWidgets('desktop: direct chat profile has no members tab, group does', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const TalerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Демо'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть демо'));
    await tester.pumpAndSettle();

    // Nothing selected yet.
    expect(find.text('Выберите чат'), findsOneWidget);

    // Direct message: profile panel with media/files only.
    await tester.tap(find.text('Елена Соколова').first);
    await tester.pumpAndSettle();
    expect(find.text('Профиль'), findsOneWidget);
    expect(find.text('Медиа'), findsOneWidget);
    expect(find.text('Файлы'), findsOneWidget);
    expect(find.text('Участники'), findsNothing);

    // Group: members tab appears.
    await tester.tap(find.text('Taler & Komet Community').first);
    await tester.pumpAndSettle();
    expect(find.text('Группа'), findsOneWidget);
    expect(find.text('Участники'), findsWidgets);

    // Profile panel can be closed.
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.text('Группа'), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });
}

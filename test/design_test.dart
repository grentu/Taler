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

  testWidgets(
      'mobile: keyboard covers dock and exiting chat does not focus search',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TalerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Демо'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть демо'));
    await tester.pumpAndSettle();

    final dockLabel = find.text('Профиль');
    expect(dockLabel, findsOneWidget);
    final dockBottomBefore = tester.getBottomRight(dockLabel).dy;

    // Opening the software keyboard must not push the bottom dock upward.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(tester.getBottomRight(dockLabel).dy, dockBottomBefore);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();

    // Focus search, open a chat, and pop back to HomeScreen.
    final searchField = find.widgetWithText(TextField, 'Поиск');
    await tester.tap(searchField);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(searchField).focusNode?.hasFocus, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);

    await tester.tap(find.text('Елена Соколова'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();

    // Returning to HomeScreen must not focus the search field or keep IME open.
    expect(tester.widget<TextField>(searchField).focusNode?.hasFocus, isFalse);
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('EditableText'));
    expect(tester.testTextInput.hasAnyClients, isFalse);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'mobile: privacy and profile tabs use clean non-debug copy and icon edit button',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(380, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TalerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Демо'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть демо'));
    await tester.pumpAndSettle();

    // Privacy Shield tab has clean consumer copy without Opcode/Wire Audit clutter.
    await tester.tap(find.text('Защита'));
    await tester.pumpAndSettle();
    expect(find.text('Taler Shield'), findsOneWidget);
    expect(find.textContaining('Opcode'), findsNothing);
    expect(find.textContaining('Wire Audit'), findsNothing);

    // Profile tab uses compact pencil icon button instead of wide 'Изменить' label.
    await tester.tap(find.text('Профиль'));
    await tester.pumpAndSettle();
    expect(find.text('Аккаунт'), findsOneWidget);
    expect(find.text('Устройства'), findsOneWidget);
    expect(find.text('Активные сессии'), findsNothing);
    expect(find.textContaining('Opcode'), findsNothing);
    expect(find.byTooltip('Изменить имя'), findsOneWidget);
    expect(find.text('Изменить'), findsNothing);

    // Chat screen on mobile shows floating search and info actions cleanly.
    await tester.tap(find.text('Чаты').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Елена Соколова'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Поиск в чате'), findsOneWidget);
    expect(find.byTooltip('Профиль чата'), findsOneWidget);
    expect(find.byTooltip('Отправить'), findsOneWidget);
    await tester.tap(find.byTooltip('Поиск в чате'));
    await tester.pumpAndSettle();
    expect(find.text('Поиск по переписке'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть поиск'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });
}

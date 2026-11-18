import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taler/core/storage/app_preferences.dart';
import 'package:taler/core/storage/local_store.dart';
import 'package:taler/core/storage/taler_models.dart';
import 'package:taler/core/version.dart';
import 'package:taler/main.dart';
import 'package:taler/ui/icons/taler_icon.dart';
import 'package:taler/ui/widgets/message_bubble.dart';

void main() {
  group('AppPreferences & Cache', () {
    test('persists chat appearance, notifications and power saving settings', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = AppPreferences();
      await prefs.load();

      expect(prefs.themeMode, ThemeMode.dark);
      expect(prefs.messageFontSize, 15.0);
      expect(prefs.bubbleRadius, 20.0);
      expect(prefs.showChatWallpaper, isTrue);
      expect(prefs.compactChatList, isFalse);
      expect(prefs.showFolderBadges, isTrue);
      expect(prefs.showNotificationPreview, isTrue);
      expect(prefs.powerSavingMode, isFalse);
      expect(prefs.autoCheckUpdates, isTrue);
      expect(prefs.languageLabel, 'Русский');

      await prefs.setThemeMode(ThemeMode.light);
      await prefs.setMessageFontSize(17.0);
      await prefs.setBubbleRadius(12.0);
      await prefs.setShowChatWallpaper(false);
      await prefs.setCompactChatList(true);
      await prefs.setShowFolderBadges(false);
      await prefs.setShowNotificationPreview(false);
      await prefs.setPowerSavingMode(true);
      await prefs.setAutoCheckUpdates(false);

      final reloaded = AppPreferences();
      await reloaded.load();
      expect(reloaded.themeMode, ThemeMode.light);
      expect(reloaded.messageFontSize, 17.0);
      expect(reloaded.bubbleRadius, 12.0);
      expect(reloaded.showChatWallpaper, isFalse);
      expect(reloaded.compactChatList, isTrue);
      expect(reloaded.showFolderBadges, isFalse);
      expect(reloaded.showNotificationPreview, isFalse);
      expect(reloaded.powerSavingMode, isTrue);
      expect(reloaded.autoCheckUpdates, isFalse);
    });

    test('estimates cache stats and clears message cache without logging out', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = LocalStore();
      await store.init();
      await store.saveCredentials('tok_123', 42);
      await store.saveProfile(const TalerUserProfile(id: 42, firstName: 'Иван'));
      await store.saveChats([
        const TalerChat(id: 100, type: 'DIALOG', title: 'Анна'),
      ]);
      await store.saveMessagesBatch(100, const [
        TalerMessage(id: 'm1', chatId: 100, senderId: 2, text: 'Привет!', time: 1000),
        TalerMessage(id: 'm2', chatId: 100, senderId: 42, text: 'Как дела?', time: 2000),
      ]);
      await store.flush();

      final statsBefore = store.estimateCacheStats();
      expect(statsBefore.chatsCount, 1);
      expect(statsBefore.messagesCount, 2);
      expect(statsBefore.approxBytes, greaterThan(0));

      final removed = await store.clearMessageCache();
      expect(removed, 2);
      expect(store.getMessages(100), isEmpty);
      expect(store.authToken, 'tok_123');
      expect(store.profile?.id, 42);
      expect(store.chats[100]?.title, 'Анна');
      expect(store.estimateCacheStats().messagesCount, 0);
    });
  });

  testWidgets(
      'mobile 360px: 4-tab dock, Settings hub, search, subpages and Profile fit cleanly',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TalerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Демо'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть демо'));
    await tester.pumpAndSettle();

    // All 4 tabs fit on a narrow 360px screen with no overflow exceptions.
    expect(find.text('Чаты'), findsWidgets);
    expect(find.text('Защита'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Профиль'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Open Settings tab.
    await tester.tap(find.text('Настройки').last);
    await tester.pumpAndSettle();

    expect(find.text('Настройки Taler'), findsOneWidget);
    expect(find.text('Обновление Taler'), findsOneWidget);
    expect(find.text('Аккаунт'), findsOneWidget);
    expect(find.text('Настройки чатов'), findsOneWidget);
    expect(find.text('Конфиденциальность'), findsOneWidget);
    expect(find.text('Уведомления'), findsOneWidget);
    expect(find.text('Данные и память'), findsOneWidget);
    expect(find.text('Папки с чатами'), findsOneWidget);
    expect(find.text('Устройства'), findsOneWidget);
    expect(find.text('Энергосбережение'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
    // Без лишнего «нейрослопного» мусора на главном экране настроек
    expect(find.textContaining('модулей'), findsNothing);
    expect(find.textContaining('КБ'), findsNothing);
    expect(tester.takeException(), isNull);

    // Live search in Settings works cleanly.
    await tester.tap(find.byTooltip('Поиск в настройках'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Энерго');
    await tester.pumpAndSettle();
    expect(find.text('Энергосбережение'), findsOneWidget);
    expect(find.text('Папки с чатами'), findsNothing);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();

    // Open Chat Appearance sub-page and change settings.
    await tester.tap(find.text('Настройки чатов'));
    await tester.pumpAndSettle();
    expect(find.text('Тема оформления'), findsOneWidget);
    expect(find.text('Размер текста сообщений'), findsOneWidget);
    await tester.tap(find.text('Компакт'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();

    // Open Power Saving sub-page and toggle switch.
    await tester.tap(find.text('Энергосбережение'));
    await tester.pumpAndSettle();
    expect(find.text('Режим энергосбережения'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Откл'), findsWidgets);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();

    // Help section and footer appear on scroll.
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.text('Помощь'), findsOneWidget);
    expect(find.text('Возможности Taler'), findsOneWidget);
    expect(find.text('Политика конфиденциальности'), findsOneWidget);
    expect(find.text(kTalerVersionLabel), findsOneWidget);

    // Switch back to Profile tab from bottom dock.
    await tester.tap(find.text('Профиль').last);
    await tester.pumpAndSettle();
    expect(find.text('Мой профиль'), findsOneWidget);
    expect(find.text('Активные сессии'), findsOneWidget);
    expect(find.byTooltip('Изменить имя'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'mobile 360px: long press on message opens blurred floating overlay menu cleanly',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TalerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Демо'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть демо'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Елена Соколова'));
    await tester.pumpAndSettle();

    final firstBubble = find.byType(MessageBubble).first;
    expect(firstBubble, findsOneWidget);

    await tester.longPress(firstBubble);
    await tester.pumpAndSettle();

    expect(find.text('Ответить'), findsOneWidget);
    expect(find.text('Копировать текст'), findsOneWidget);
    expect(find.text('Удалить у себя'), findsOneWidget);
    expect(find.text('🎉'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('🎉'));
    await tester.pumpAndSettle();
    expect(find.text('Ответить'), findsNothing);
    expect(find.text('🎉'), findsOneWidget);

    await tester.longPress(find.byType(MessageBubble).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ответить'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Отменить'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Отменить'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'mobile 360px: dock sliding pill, settings gear morph and profile ring animate cleanly',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TalerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Демо'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть демо'));
    await tester.pumpAndSettle();

    // Initially settings uses outline gear.
    expect(
      find.byWidgetPredicate(
        (w) => w is TalerIcon && w.icon == TalerIcons.settings,
      ),
      findsOneWidget,
    );

    // Switch to Settings and pump intermediate animation frames.
    await tester.tap(find.text('Настройки').last);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (w) => w is TalerIcon && w.icon == TalerIcons.settingsActive,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // Switch to Profile (triggers sliding pill stretch + avatar pop/ring + halo).
    await tester.tap(find.text('Профиль').last);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();
    expect(find.text('Мой профиль'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Switch across to Protection and back to Chats.
    await tester.tap(find.text('Защита').last);
    await tester.pump(const Duration(milliseconds: 140));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Чаты').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taler/core/storage/app_preferences.dart';
import 'package:taler/core/storage/local_store.dart';
import 'package:taler/core/storage/taler_models.dart';
import 'package:taler/main.dart';

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
      expect(prefs.languageLabel, 'Русский');

      await prefs.setThemeMode(ThemeMode.light);
      await prefs.setMessageFontSize(17.0);
      await prefs.setBubbleRadius(12.0);
      await prefs.setShowChatWallpaper(false);
      await prefs.setCompactChatList(true);
      await prefs.setShowFolderBadges(false);
      await prefs.setShowNotificationPreview(false);
      await prefs.setPowerSavingMode(true);

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
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(find.text('Помощь'), findsOneWidget);
    expect(find.text('Возможности Taler'), findsOneWidget);
    expect(find.text('Политика конфиденциальности'), findsOneWidget);
    expect(find.text('Taler 1.2.8 (14)'), findsOneWidget);

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
}

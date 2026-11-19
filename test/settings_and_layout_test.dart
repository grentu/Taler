import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taler/backend/taler_client.dart';
import 'package:taler/core/platform/taler_native_bridge.dart';
import 'package:taler/core/privacy/privacy_firewall.dart';
import 'package:taler/core/privacy/privacy_settings.dart';
import 'package:taler/core/privacy/spoofing_service.dart';
import 'package:taler/core/storage/app_preferences.dart';
import 'package:taler/core/storage/local_store.dart';
import 'package:taler/core/storage/taler_models.dart';
import 'package:taler/core/version.dart';
import 'package:taler/main.dart';
import 'package:taler/ui/icons/taler_icon.dart';
import 'package:taler/ui/theme/taler_theme.dart';
import 'package:taler/ui/widgets/message_actions_overlay.dart';
import 'package:taler/ui/widgets/message_bubble.dart';
import 'package:taler/ui/widgets/settings_components.dart';
import 'package:taler/ui/widgets/taler_logo.dart';

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
    expect(find.text('Аккаунт'), findsOneWidget);
    expect(find.text('Идентификатор MAX'), findsOneWidget);
    expect(find.text('О себе'), findsOneWidget);
    expect(find.text('Редактировать'), findsOneWidget);
    expect(find.text('Устройства'), findsNothing);
    expect(find.text('Оформление чатов'), findsNothing);
    expect(find.text('Активные сессии'), findsNothing);
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
    expect(find.text('Идентификатор MAX'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Switch across to Protection and back to Chats.
    await tester.tap(find.text('Защита').last);
    await tester.pump(const Duration(milliseconds: 140));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Чаты').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('UI fixes, back navigation, device icons and photo viewer', () {
    test('talerDeviceIconForClient picks accurate icons without door icon', () {
      expect(talerDeviceIconForClient('MAX Android'), TalerIcons.smartphone);
      expect(talerDeviceIconForClient('Taler (Pixel 8 Pro)'), TalerIcons.smartphone);
      expect(talerDeviceIconForClient('MAX Web'), TalerIcons.settingsLanguage);
      expect(talerDeviceIconForClient('Taler Windows Desktop'), TalerIcons.settingsDevices);
      expect(talerDeviceIconForClient('Unknown Device'), TalerIcons.devicesOther);
    });

    test('TalerClient filters empty ghost chats and keeps active/saved dialogs', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = LocalStore();
      await store.init();
      await store.saveCredentials('tok', 10);
      await store.saveChats([
        const TalerChat(id: 1, type: 'DIALOG', title: 'Диалог #1'),
        const TalerChat(
          id: 2,
          type: 'DIALOG',
          title: 'Избранное',
          peerId: 10,
          lastMessageText: 'Заметка',
          lastMessageTime: 1000,
        ),
        const TalerChat(
          id: 3,
          type: 'DIALOG',
          title: 'Иван',
          peerId: 20,
          lastMessageText: 'Привет',
          lastMessageTime: 2000,
        ),
      ]);

      final client = TalerClient(
        privacySettings: PrivacySettings(),
        spoofingService: SpoofingService(),
        auditLog: WireAuditLog(),
        store: store,
      );
      addTearDown(client.dispose);

      expect(client.chats.map((c) => c.id).toList(), [3, 2]);
    });

    testWidgets(
      'mobile 360px: bottom sheets replace AlertDialog, back gesture switches to Chats tab, and photo opens fullscreen',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        // Prepare a valid 1x1 PNG file for photo viewer test.
        final tmpDir = Directory.systemTemp.createTempSync('taler_photo_test_');
        addTearDown(() {
          if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
        });
        final pngBytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        );
        final imgFile = File('${tmpDir.path}${Platform.pathSeparator}sample.png')
          ..writeAsBytesSync(pngBytes);

        final store = LocalStore();
        await store.init();
        final prefs = AppPreferences();
        await prefs.load();
        final client = TalerClient(
          privacySettings: PrivacySettings(),
          spoofingService: SpoofingService(),
          auditLog: WireAuditLog(),
          store: store,
          appPreferences: prefs,
        );
        await client.enterDemoMode();
        await store.saveMessagesBatch(5002, [
          ...store.getMessages(5002),
          TalerMessage(
            id: 'photo_1',
            chatId: 5002,
            senderId: 2001,
            text: 'Фото тест',
            time: DateTime.now().millisecondsSinceEpoch,
            attachments: [
              TalerAttachment(
                type: 'PHOTO',
                url: imgFile.path,
                width: 100,
                height: 100,
              ),
            ],
          ),
        ]);
        addTearDown(client.dispose);

        await tester.pumpWidget(TalerApp(client: client));
        await tester.pumpAndSettle();

        // Switch to Settings -> open "Вопросы о Taler" and verify styled bottom sheet (no AlertDialog).
        await tester.tap(find.text('Настройки').last);
        await tester.pumpAndSettle();

        await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -450));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Вопросы о Taler'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Понятно'), findsOneWidget);
        await tester.tap(find.text('Понятно'));
        await tester.pumpAndSettle();

        // System back gesture on Settings tab must return to Chats tab instead of closing app.
        final poppedSettings = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(poppedSettings, isTrue);
        expect(find.text('Елена Соколова'), findsOneWidget);

        // Switch to Profile -> edit profile page supports name & bio editing (no AlertDialog).
        await tester.tap(find.text('Профиль').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Изменить имя'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Редактировать профиль'), findsOneWidget);
        expect(find.text('Сохранить'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, 'Разработчик Taler');
        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();
        expect(find.text('Разработчик Taler'), findsOneWidget);

        // Back gesture from Profile returns to Chats tab.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Елена Соколова'), findsOneWidget);

        // Open direct chat and tap photo to open fullscreen viewer.
        await tester.tap(find.text('Елена Соколова'));
        await tester.pumpAndSettle();

        // Center-aligned header pill should use Alignment.center on mobile.
        final headerAlign = tester.widget<Align>(
          find.ancestor(
            of: find.text('Елена Соколова'),
            matching: find.byType(Align),
          ).first,
        );
        expect(headerAlign.alignment, Alignment.center);

        // Tap the photo attachment to open fullscreen viewer and close it via Back.
        final photoTapTarget = find.descendant(
          of: find.byType(MessageBubble),
          matching: find.byType(Image),
        );
        expect(photoTapTarget, findsWidgets);
        await tester.tap(photoTapTarget.first);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Сохранить'), findsOneWidget);

        await tester.tap(find.byTooltip('Назад').last);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Сохранить'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('v1.2.14 polish: folders, attachments, peer profile, borderless reactions & zero-jump overlay', () {
    testWidgets('animated folder switching updates list smoothly via tap and swipe', (tester) async {
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

      expect(find.byType(PageView), findsOneWidget);
      // Tap a folder tab and pump intermediate animation frames.
      await tester.tap(find.text('Каналы'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('Taler & Komet Community'), findsOneWidget);
      expect(find.text('Елена Соколова'), findsNothing);

      // Swipe back right to previous folder ('Приватные').
      await tester.drag(find.byType(PageView), const Offset(280, 0));
      await tester.pumpAndSettle();
      expect(find.text('Елена Соколова'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('VIDEO, SHARE and AUDIO attachments render native views instead of file icons', (tester) async {
      const videoMsg = TalerMessage(
        id: 'v1',
        chatId: 1,
        senderId: 2,
        text: '',
        time: 1700000000000,
        attachments: [
          TalerAttachment(
            type: 'VIDEO',
            previewText: 'Обзор Taler',
            durationMs: 84,
          ),
        ],
      );
      const shareMsg = TalerMessage(
        id: 's1',
        chatId: 1,
        senderId: 2,
        text: 'Смотри видео https://youtube.com/watch?v=123',
        time: 1700000001000,
        attachments: [
          TalerAttachment(
            type: 'SHARE',
            url: 'https://www.youtube.com/watch?v=123',
            previewText: 'Крутой ролик про Flutter',
            description: 'Подробный разбор интерфейса',
          ),
        ],
      );
      const audioMsg = TalerMessage(
        id: 'a1',
        chatId: 1,
        senderId: 2,
        text: '',
        time: 1700000002000,
        attachments: [
          TalerAttachment(
            type: 'VOICE',
            durationMs: 15000,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: TalerTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MessageBubble(
                    message: videoMsg,
                    isMine: false,
                    firstInRun: true,
                    showName: false,
                    senderName: 'Анна',
                    maxWidth: 300,
                  ),
                  MessageBubble(
                    message: shareMsg,
                    isMine: false,
                    firstInRun: false,
                    showName: false,
                    senderName: 'Анна',
                    maxWidth: 300,
                  ),
                  MessageBubble(
                    message: audioMsg,
                    isMine: false,
                    firstInRun: false,
                    showName: false,
                    senderName: 'Анна',
                    maxWidth: 300,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // None of VIDEO / SHARE / VOICE should render the document file icon.
      expect(
        find.byWidgetPredicate((w) => w is TalerIcon && w.icon == TalerIcons.file),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate((w) => w is TalerIcon && w.icon == TalerIcons.play),
        findsNWidgets(2),
      );
      expect(find.text('1:24'), findsOneWidget);
      expect(find.text('youtube.com'), findsOneWidget);
      expect(find.text('Крутой ролик про Flutter'), findsOneWidget);
      expect(find.text('Подробный разбор интерфейса'), findsOneWidget);
      expect(find.text('0:15'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reactions render cleanly without harsh border outline', (tester) async {
      const msg = TalerMessage(
        id: 'r1',
        chatId: 1,
        senderId: 2,
        text: 'Привет',
        time: 1700000000000,
        reactions: [
          TalerReactionCounter(emoji: '🔥', count: 3, isMine: true),
          TalerReactionCounter(emoji: '👍', count: 1, isMine: false),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: TalerTheme.dark(),
          home: Scaffold(
            body: MessageRow(
              message: msg,
              isMine: false,
              firstInRun: true,
              lastInRun: true,
              showSender: false,
              senderName: 'Анна',
              maxBubbleWidth: 300,
              onToggleReaction: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final reactionPills = tester.widgetList<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(reactionPills.length, 2);
      for (final pill in reactionPills) {
        final dec = pill.decoration as BoxDecoration?;
        expect(dec?.border, isNull);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('peer profile page uses pure settingsBg with no grey bar and compact top offset', (tester) async {
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
      await tester.tap(find.byTooltip('Меню чата'));
      await tester.pumpAndSettle();
      expect(find.text('Профиль'), findsOneWidget);
      await tester.tap(find.text('Профиль'));
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
      final palette = TalerTheme.paletteOf(tester.element(find.byType(Scaffold).last));
      expect(scaffold.backgroundColor, palette.settingsBg);

      // Avatar should sit high near the top (no 48px grey bar + 24px spacer).
      final avatarRect = tester.getRect(find.byType(TalerAvatar).last);
      expect(avatarRect.top, lessThan(24.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('context menu keeps bottom-edge message anchored in place and flips menu above', (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const msg = TalerMessage(
        id: 'm_bottom',
        chatId: 1,
        senderId: 2,
        text: 'Сообщение у самого нижнего края экрана',
        time: 1700000000000,
      );
      const anchor = Rect.fromLTWH(16, 636, 260, 56);

      await tester.pumpWidget(
        MaterialApp(
          theme: TalerTheme.dark(),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showTalerMessageActionsOverlay(
                      context: ctx,
                      message: msg,
                      isMine: false,
                      firstInRun: true,
                      showName: false,
                      senderName: 'Анна',
                      maxBubbleWidth: 280,
                      fontSize: 15,
                      cornerRadius: 20,
                      anchorRect: anchor,
                      actions: [
                        TalerMessageAction(icon: TalerIcons.reply, label: 'Ответить', onTap: () {}),
                        TalerMessageAction(icon: TalerIcons.copy, label: 'Копировать', onTap: () {}),
                        TalerMessageAction(icon: TalerIcons.pencil, label: 'Изменить', onTap: () {}),
                        TalerMessageAction(
                          icon: TalerIcons.trash,
                          label: 'Удалить',
                          destructive: true,
                          onTap: () {},
                        ),
                      ],
                      onToggleReaction: (_) {},
                    );
                  },
                  child: const Text('Open Overlay'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Overlay'));
      await tester.pumpAndSettle();

      final bubbleRect = tester.getRect(find.byType(MessageBubble));
      final replyRect = tester.getRect(find.text('Ответить'));
      final reactionRect = tester.getRect(find.text('🔥'));

      // Bubble stays pixel-locked at its original anchor position (no upward jump!).
      expect(bubbleRect.top, closeTo(anchor.top, 0.5));
      expect(bubbleRect.left, closeTo(anchor.left, 0.5));
      // Menu and reactions float cleanly above the bubble.
      expect(replyRect.bottom, lessThan(bubbleRect.top));
      expect(reactionRect.bottom, lessThan(replyRect.top));
      expect(tester.takeException(), isNull);
    });
  });

  group('v1.2.15 features: links, swipe-reply, double-tap reaction, multi-select forward, drafts & media', () {
    testWidgets('clickable links inside MessageBubble open URL via callback', (tester) async {
      final opened = <String>[];
      const msg = TalerMessage(
        id: 'link_1',
        chatId: 1,
        senderId: 2,
        text: 'Открой https://example.com/taler',
        time: 1700000000000,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: TalerTheme.dark(),
          home: Scaffold(
            body: MessageBubble(
              message: msg,
              isMine: false,
              firstInRun: true,
              showName: false,
              senderName: 'Анна',
              maxWidth: 320,
              onOpenLink: opened.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap right side of the bubble text where the URL sits.
      final textRect = tester.getRect(find.byType(RichText).first);
      await tester.tapAt(Offset(textRect.right - 45, textRect.center.dy));
      await tester.pumpAndSettle();
      expect(opened, ['https://example.com/taler']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('swipe left to reply and double-tap quick reaction work cleanly on MessageRow', (tester) async {
      var replied = false;
      var quickReacted = false;
      const msg = TalerMessage(
        id: 'gesture_1',
        chatId: 1,
        senderId: 2,
        text: 'Свайпни меня влево или тапни дважды',
        time: 1700000000000,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: TalerTheme.dark(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                child: MessageRow(
                  message: msg,
                  isMine: false,
                  firstInRun: true,
                  lastInRun: true,
                  showSender: false,
                  senderName: 'Анна',
                  maxBubbleWidth: 280,
                  onSwipeReply: () => replied = true,
                  onDoubleTapQuickReaction: () => quickReacted = true,
                  onToggleReaction: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Swipe left past threshold -> triggers reply callback.
      await tester.drag(find.byType(MessageBubble), const Offset(-110, 0));
      await tester.pumpAndSettle();
      expect(replied, isTrue);

      // Double tap -> triggers quick reaction callback.
      final center = tester.getCenter(find.byType(MessageBubble));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(quickReacted, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile 360px: drafts show in chat list, restore in chat, multi-select forwards & deletes', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final tmpDir = Directory.systemTemp.createTempSync('taler_file_test_');
      addTearDown(() {
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      });
      final docFile = File('${tmpDir.path}${Platform.pathSeparator}spec.txt')
        ..writeAsStringSync('hello taler');
      final openedFiles = <String>[];
      TalerNativeBridge.instance.testOpenFileHandler = (p) async {
        openedFiles.add(p);
        return true;
      };
      addTearDown(() => TalerNativeBridge.instance.testOpenFileHandler = null);

      final store = LocalStore();
      await store.init();
      final client = TalerClient(
        privacySettings: PrivacySettings(),
        spoofingService: SpoofingService(),
        auditLog: WireAuditLog(),
        store: store,
      );
      await client.enterDemoMode();
      await store.saveMessagesBatch(5002, [
        ...store.getMessages(5002),
        TalerMessage(
          id: 'doc_1',
          chatId: 5002,
          senderId: 2001,
          text: '',
          time: DateTime.now().millisecondsSinceEpoch,
          attachments: [
            TalerAttachment(
              type: 'FILE',
              url: docFile.path,
              fileName: 'spec.txt',
              fileSize: 11,
            ),
          ],
        ),
      ]);
      addTearDown(client.dispose);

      await tester.pumpWidget(TalerApp(client: client));
      await tester.pumpAndSettle();

      // Open Elena chat, tap file attachment -> opens local file.
      await tester.tap(find.text('Елена Соколова'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('spec.txt'));
      await tester.pumpAndSettle();
      expect(openedFiles, [docFile.path]);

      // Enter draft text and leave chat -> draft shows in chat list and restores on reopen.
      await tester.enterText(find.byType(TextField).last, 'Мой черновик');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(find.text('Черновик: '), findsOneWidget);
      expect(find.text('Мой черновик'), findsOneWidget);

      await tester.tap(find.text('Елена Соколова'));
      await tester.pumpAndSettle();
      expect(find.text('Мой черновик'), findsOneWidget);

      // Multi-select via long press -> 'Выбрать' -> tap second bubble -> forward to group.
      await tester.longPress(find.byType(MessageBubble).first);
      await tester.pumpAndSettle();
      expect(find.text('Переслать'), findsOneWidget);
      expect(find.text('Выбрать'), findsOneWidget);
      await tester.tap(find.text('Выбрать'));
      await tester.pumpAndSettle();
      expect(find.text('Выбрано: 1'), findsOneWidget);

      if (find.byType(MessageRow).evaluate().length >= 2) {
        await tester.tap(find.byType(MessageRow).at(1));
        await tester.pumpAndSettle();
        expect(find.text('Выбрано: 2'), findsOneWidget);
      }

      // Forward selected messages to 'Taler & Komet Community'.
      final beforeGroupCount = client.messagesForChat(5001).length;
      await tester.tap(find.text('Переслать'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Taler & Komet Community'));
      await tester.pumpAndSettle();
      expect(client.messagesForChat(5001).length, greaterThan(beforeGroupCount));
      expect(find.text('Выбрано: 1'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('v1.2.16 UI fixes: voice redesign, composer alignment, chat menu, tab parity & gradient logo', () {
    testWidgets('voice bubble with real waveform renders cleanly with exact duration and zero layout errors', (tester) async {
      const voiceMsg = TalerMessage(
        id: 'v_real',
        chatId: 1,
        senderId: 2,
        text: '',
        time: 1763544000000,
        attachments: [
          TalerAttachment(
            type: 'AUDIO',
            audioId: 5511,
            durationMs: 16400,
            waveform: [8, 22, 64, 118, 95, 40, 12, 85, 127, 60, 30, 14],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: TalerTheme.dark(),
          home: const Scaffold(
            body: Center(
              child: MessageBubble(
                message: voiceMsg,
                isMine: true,
                firstInRun: true,
                showName: false,
                senderName: 'Вы',
                maxWidth: 300,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0:16'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is TalerIcon && w.icon == TalerIcons.play),
        findsOneWidget,
      );
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile 360px: composer send button aligns with input pill, 3-dots opens chat menu, and Settings/Profile hero match', (tester) async {
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

      // Verify Settings and Profile share identical 92px hero avatar size and vertical position.
      await tester.tap(find.text('Настройки').last);
      await tester.pumpAndSettle();
      final settingsHero = find.byWidgetPredicate((w) => w is TalerAvatar && w.size == 92.0);
      expect(settingsHero, findsOneWidget);
      final settingsHeroTop = tester.getRect(settingsHero).top;

      await tester.tap(find.text('Профиль').last);
      await tester.pumpAndSettle();
      final profileHero = find.byWidgetPredicate((w) => w is TalerAvatar && w.size == 92.0);
      expect(profileHero, findsOneWidget);
      final profileHeroTop = tester.getRect(profileHero).top;
      expect((settingsHeroTop - profileHeroTop).abs(), lessThanOrEqualTo(1.0));

      // Open Elena chat and check Send button vertical alignment with the composer glass pill.
      await tester.tap(find.text('Чаты').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Елена Соколова'));
      await tester.pumpAndSettle();

      final sendBtnFinder = find.byTooltip('Отправить');
      final inputFieldFinder = find.byType(TextField).last;
      final sendRect = tester.getRect(sendBtnFinder);
      final inputRect = tester.getRect(inputFieldFinder);
      // Send button is 46x46 and vertically centered with the single-line input text box.
      expect(sendRect.height, closeTo(46.0, 0.5));
      expect((sendRect.center.dy - inputRect.center.dy).abs(), lessThanOrEqualTo(2.0));

      // Tap 3-dots menu -> full action list instead of jumping straight to profile.
      await tester.tap(find.byTooltip('Меню чата'));
      await tester.pumpAndSettle();
      expect(find.text('Профиль'), findsOneWidget);
      expect(find.text('Поиск по сообщениям'), findsOneWidget);
      expect(find.text('Выключить звук'), findsOneWidget);
      expect(find.text('Выбрать сообщения'), findsOneWidget);
      expect(find.text('Обновить историю'), findsOneWidget);
      expect(find.text('Очистить историю'), findsOneWidget);
      expect(find.text('Удалить чат'), findsOneWidget);

      // Tapping 'Очистить историю' shows styled confirmation bottom sheet (no AlertDialog).
      await tester.tap(find.text('Очистить историю'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Очистить'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('TalerLogo renders cleanly in squircle and circular modes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TalerTheme.dark(),
          home: const Scaffold(
            body: Row(
              children: [
                TalerLogo(size: 24, circular: false),
                TalerLogo(size: 40, circular: false),
                TalerLogo(size: 72, circular: true),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TalerLogo), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  });
}

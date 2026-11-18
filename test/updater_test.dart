import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taler/backend/taler_client.dart';
import 'package:taler/core/privacy/privacy_firewall.dart';
import 'package:taler/core/privacy/privacy_settings.dart';
import 'package:taler/core/privacy/spoofing_service.dart';
import 'package:taler/core/storage/app_preferences.dart';
import 'package:taler/core/storage/local_store.dart';
import 'package:taler/core/update/app_updater.dart';
import 'package:taler/ui/screens/home_screen.dart';
import 'package:taler/ui/theme/taler_theme.dart';

String _sampleReleaseJson({
  String tag = 'v1.3.0',
  String body = '• Добавлен OTA-апдейтер\n• Исправлены ошибки интерфейса',
}) {
  return jsonEncode({
    'tag_name': tag,
    'html_url': 'https://github.com/grentu/Taler/releases/tag/$tag',
    'body': body,
    'published_at': '2026-11-18T20:00:00Z',
    'assets': [
      {
        'name': 'Taler-Android-arm64-v8a.apk',
        'browser_download_url':
            'https://github.com/grentu/Taler/releases/download/$tag/Taler-Android-arm64-v8a.apk',
        'size': 20971520,
      },
      {
        'name': 'Taler-Android-armeabi-v7a.apk',
        'browser_download_url':
            'https://github.com/grentu/Taler/releases/download/$tag/Taler-Android-armeabi-v7a.apk',
        'size': 19922944,
      },
      {
        'name': 'Taler-Android-x86_64.apk',
        'browser_download_url':
            'https://github.com/grentu/Taler/releases/download/$tag/Taler-Android-x86_64.apk',
        'size': 22020096,
      },
      {
        'name': 'Taler-Windows-x64.exe',
        'browser_download_url':
            'https://github.com/grentu/Taler/releases/download/$tag/Taler-Windows-x64.exe',
        'size': 26214400,
      },
    ],
  });
}

http.Response _jsonResponse(String body, [int status = 200]) {
  return http.Response.bytes(
    utf8.encode(body),
    status,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  group('AppUpdater unit tests', () {
    test('parseSemVer & isVersionNewer compare release tags accurately', () {
      expect(AppUpdater.parseSemVer('v1.2.11'), [1, 2, 11]);
      expect(AppUpdater.parseSemVer('1.2.11+17'), [1, 2, 11]);
      expect(AppUpdater.parseSemVer('V2.0.1-beta.1'), [2, 0, 1]);

      expect(AppUpdater.isVersionNewer('v1.2.12', '1.2.11'), isTrue);
      expect(AppUpdater.isVersionNewer('v1.3.0', '1.2.11'), isTrue);
      expect(AppUpdater.isVersionNewer('v2.0.0', '1.9.99'), isTrue);
      expect(AppUpdater.isVersionNewer('v1.2.11', '1.2.11'), isFalse);
      expect(AppUpdater.isVersionNewer('1.2.10', '1.2.11'), isFalse);
      expect(AppUpdater.isVersionNewer('0.9.9', '1.0.0'), isFalse);
    });

    test('expectedAndroidAssetName & pickAssetFromList select per-ABI and platform assets', () {
      expect(
        AppUpdater.expectedAndroidAssetName('arm64-v8a'),
        'Taler-Android-arm64-v8a.apk',
      );
      expect(
        AppUpdater.expectedAndroidAssetName('armeabi-v7a'),
        'Taler-Android-armeabi-v7a.apk',
      );
      expect(
        AppUpdater.expectedAndroidAssetName('x86_64'),
        'Taler-Android-x86_64.apk',
      );

      final decoded = jsonDecode(_sampleReleaseJson()) as Map<String, dynamic>;
      final rawAssets = decoded['assets'] as List<dynamic>;

      final armV7 = AppUpdater.pickAssetFromList(
        rawAssets,
        isAndroid: true,
        isWindows: false,
        abi: 'armeabi-v7a',
      );
      expect(armV7?.name, 'Taler-Android-armeabi-v7a.apk');

      final arm64 = AppUpdater.pickAssetFromList(
        rawAssets,
        isAndroid: true,
        isWindows: false,
        abi: 'unknown-abi',
      );
      expect(arm64?.name, 'Taler-Android-arm64-v8a.apk');

      final win = AppUpdater.pickAssetFromList(
        rawAssets,
        isAndroid: false,
        isWindows: true,
      );
      expect(win?.name, 'Taler-Windows-x64.exe');
    });

    test('checkForUpdates transitions to available, upToDate, and error', () async {
      var mode = 'newer';
      final client = MockClient((req) async {
        expect(req.url.path, '/repos/grentu/Taler/releases/latest');
        if (mode == 'newer') {
          return _jsonResponse(_sampleReleaseJson(tag: 'v1.3.0'));
        }
        if (mode == 'same') {
          return _jsonResponse(_sampleReleaseJson(tag: 'v1.2.11'));
        }
        return _jsonResponse('rate limit', 503);
      });

      final updater = AppUpdater(
        httpClient: client,
        currentVersion: '1.2.11',
        isAndroidOverride: true,
        isWindowsOverride: false,
        androidAbiProvider: () async => 'arm64-v8a',
      );

      await updater.checkForUpdates(silent: false);
      expect(updater.status, UpdateStatus.available);
      expect(updater.hasUpdate, isTrue);
      expect(updater.release?.version, '1.3.0');
      expect(updater.release?.matchedAsset?.name, 'Taler-Android-arm64-v8a.apk');

      mode = 'same';
      await updater.checkForUpdates(silent: false);
      expect(updater.status, UpdateStatus.upToDate);
      expect(updater.hasUpdate, isFalse);
      expect(updater.release, isNull);

      mode = 'err';
      await updater.checkForUpdates(silent: true);
      expect(updater.status, UpdateStatus.upToDate);

      await updater.checkForUpdates(silent: false);
      expect(updater.status, UpdateStatus.error);
      expect(updater.errorMessage, contains('HTTP 503'));
      updater.dispose();
    });

    test('downloadAndInstall handles Android needs_permission then cached retry', () async {
      final tempDir = await Directory.systemTemp.createTemp('taler_ota_android_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      var binaryDownloads = 0;
      final apkBytes = utf8.encode('PK_FAKE_APK_PAYLOAD_v1.3.0');
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/releases/latest')) {
          return _jsonResponse(_sampleReleaseJson(tag: 'v1.3.0'));
        }
        binaryDownloads++;
        return http.Response.bytes(apkBytes, 200);
      });

      var installerCalls = 0;
      final installedPaths = <String>[];
      final updater = AppUpdater(
        httpClient: client,
        tempDirProvider: () async => tempDir,
        isAndroidOverride: true,
        isWindowsOverride: false,
        androidAbiProvider: () async => 'arm64-v8a',
        androidInstaller: (path) async {
          installerCalls++;
          installedPaths.add(path);
          return installerCalls == 1 ? 'needs_permission' : 'started';
        },
        currentVersion: '1.2.11',
      );

      await updater.checkForUpdates();
      expect(updater.status, UpdateStatus.available);

      await updater.downloadAndInstall();
      expect(updater.status, UpdateStatus.needsPermission);
      expect(binaryDownloads, 1);
      expect(installerCalls, 1);
      expect(File(installedPaths.single).existsSync(), isTrue);
      expect(File(installedPaths.single).readAsBytesSync(), apkBytes);

      // Retry after user grants permission must reuse cached APK without re-downloading.
      await updater.downloadAndInstall();
      expect(updater.status, UpdateStatus.readyToInstall);
      expect(binaryDownloads, 1);
      expect(installerCalls, 2);
      updater.dispose();
    });

    test('downloadAndInstall downloads and launches Windows installer', () async {
      final tempDir = await Directory.systemTemp.createTemp('taler_ota_win_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final exeBytes = List<int>.filled(4096, 0x5A);
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/releases/latest')) {
          return _jsonResponse(_sampleReleaseJson(tag: 'v1.4.0'));
        }
        return http.Response.bytes(exeBytes, 200);
      });

      String? launchedExe;
      final updater = AppUpdater(
        httpClient: client,
        tempDirProvider: () async => tempDir,
        isAndroidOverride: false,
        isWindowsOverride: true,
        windowsLauncher: (path) async {
          launchedExe = path;
        },
        currentVersion: '1.2.11',
      );

      await updater.checkForUpdates();
      await updater.downloadAndInstall();

      expect(updater.status, UpdateStatus.readyToInstall);
      expect(launchedExe, isNotNull);
      expect(launchedExe!, endsWith('Taler-Windows-x64.exe'));
      expect(File(launchedExe!).readAsBytesSync().length, exeBytes.length);
      updater.dispose();
    });

    test('cancelDownload stops stream cleanly and removes .part file', () async {
      final tempDir = await Directory.systemTemp.createTemp('taler_ota_cancel_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final chunkReceived = Completer<void>();
      final streamCtrl = StreamController<List<int>>();
      final client = MockClient.streaming((req, _) async {
        if (req.url.path.endsWith('/releases/latest')) {
          final jsonBytes = utf8.encode(_sampleReleaseJson(tag: 'v1.5.0'));
          return http.StreamedResponse(Stream.value(jsonBytes), 200);
        }
        return http.StreamedResponse(
          streamCtrl.stream,
          200,
          contentLength: 100000,
        );
      });

      final updater = AppUpdater(
        httpClient: client,
        tempDirProvider: () async => tempDir,
        isAndroidOverride: false,
        isWindowsOverride: true,
        windowsLauncher: (_) async {},
        currentVersion: '1.2.11',
      );

      await updater.checkForUpdates();
      final downloadFuture = updater.downloadAndInstall();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(updater.status, UpdateStatus.downloading);

      streamCtrl.add(const [1, 2, 3, 4]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (!chunkReceived.isCompleted) chunkReceived.complete();

      updater.cancelDownload();
      await downloadFuture.timeout(const Duration(seconds: 2));
      await streamCtrl.close();

      expect(updater.status, UpdateStatus.available);
      expect(updater.downloadedBytes, 0);
      expect(tempDir.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
      updater.dispose();
    });
  });

  group('OTA Update UI widget test', () {
    testWidgets(
      'mobile 360px: shows update badge in dock/settings and installs via _UpdatePage',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final tempDir = Directory.systemTemp.createTempSync('taler_ota_ui_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final downloaded = Completer<void>();
        final httpClient = MockClient((req) async {
          if (req.url.path.endsWith('/releases/latest')) {
            return _jsonResponse(
              _sampleReleaseJson(
                tag: 'v1.3.0',
                body: '• Добавлено обновление по воздуху',
              ),
            );
          }
          return http.Response.bytes(utf8.encode('TALER_UPDATE_BIN'), 200);
        });

        var installedCalled = false;
        final updater = AppUpdater(
          httpClient: httpClient,
          tempDirProvider: () async => tempDir,
          isAndroidOverride: false,
          isWindowsOverride: true,
          windowsLauncher: (_) async {
            installedCalled = true;
            if (!downloaded.isCompleted) downloaded.complete();
          },
          currentVersion: '1.2.11',
        );

        final prefs = AppPreferences();
        await prefs.load();
        final store = LocalStore();
        await store.init();
        final client = TalerClient(
          privacySettings: PrivacySettings(),
          spoofingService: SpoofingService(),
          auditLog: WireAuditLog(),
          store: store,
          appPreferences: prefs,
          updater: updater,
        );
        await client.enterDemoMode();
        addTearDown(client.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: TalerTheme.dark(),
            home: HomeScreen(
              client: client,
              themeMode: ThemeMode.dark,
              onThemeModeChanged: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to Settings tab and verify new version indicator appears cleanly.
        await tester.tap(find.text('Настройки').last);
        await tester.pumpAndSettle();

        expect(find.text('Обновление Taler'), findsOneWidget);
        expect(find.text('v1.3.0'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Open _UpdatePage and start download + install.
        await tester.tap(find.text('Обновление Taler'));
        await tester.pumpAndSettle();

        expect(find.text('Доступно обновление'), findsOneWidget);
        expect(find.textContaining('Добавлено обновление по воздуху'), findsOneWidget);
        expect(find.text('Скачать и установить'), findsOneWidget);
        expect(find.text('Проверять при запуске'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Скачать и установить'));
        await tester.pump();
        for (var i = 0; i < 100 && !downloaded.isCompleted; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(updater.errorMessage, isNull);
        expect(downloaded.isCompleted, isTrue);
        await tester.pumpAndSettle();

        expect(installedCalled, isTrue);
        expect(find.text('Готово к установке'), findsOneWidget);
        expect(find.text('Установить сейчас'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

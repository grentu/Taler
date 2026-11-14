import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taler/core/privacy/privacy_firewall.dart';
import 'package:taler/core/privacy/privacy_settings.dart';
import 'package:taler/core/privacy/spoof_profile.dart';
import 'package:taler/core/privacy/spoofing_service.dart';
import 'package:taler/core/protocol/lz4.dart';
import 'package:taler/core/protocol/msgpack.dart';
import 'package:taler/core/protocol/opcode.dart';
import 'package:taler/core/protocol/packet.dart';
import 'package:taler/core/storage/local_store.dart';
import 'package:taler/core/storage/taler_models.dart';
import 'package:taler/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TalerMsgpack', () {
    test('roundtrips maps, lists, integers, strings, floats, bools and binary',
        () {
      final original = <String, dynamic>{
        'nullVal': null,
        'boolTrue': true,
        'boolFalse': false,
        'smallPos': 42,
        'smallNeg': -17,
        'neg16': -12345,
        'pos64': 0x123456789ABCDEF0,
        'neg64': -9876543210123,
        'floatVal': 3.14159265,
        'cyrillic': 'Привет, Taler! Без телеметрии и слежки.',
        'list': <dynamic>[1, 'два', false, <String, dynamic>{'nested': 99}],
        'bytes': Uint8List.fromList(<int>[0, 1, 127, 128, 255]),
      };

      final encoded = TalerMsgpack.encode(original);
      final decoded = TalerMsgpack.decode(encoded) as Map;

      expect(decoded['nullVal'], isNull);
      expect(decoded['boolTrue'], isTrue);
      expect(decoded['boolFalse'], isFalse);
      expect(decoded['smallPos'], 42);
      expect(decoded['smallNeg'], -17);
      expect(decoded['neg16'], -12345);
      expect(decoded['pos64'], 0x123456789ABCDEF0);
      expect(decoded['neg64'], -9876543210123);
      expect(decoded['floatVal'], closeTo(3.14159265, 1e-7));
      expect(decoded['cyrillic'], 'Привет, Taler! Без телеметрии и слежки.');
      expect(decoded['list'], [
        1,
        'два',
        false,
        {'nested': 99},
      ]);
      expect(decoded['bytes'], orderedEquals(<int>[0, 1, 127, 128, 255]));
    });
  });

  group('TalerFraming', () {
    test('encodes 10-byte big-endian header and decodes payload accurately', () {
      final payload = <String, dynamic>{
        'chatId': 777001,
        'text': 'Сообщение без LOG и DEBUG',
      };

      final frame = TalerFraming.encode(
        cmd: CmdType.request,
        seq: 42,
        opcode: Opcode.msgSend,
        payload: payload,
      );

      expect(frame.length, greaterThan(TalerFraming.headerSize));
      expect(frame[0], TalerFraming.protocolVersion); // ver = 10
      expect(frame[1], CmdType.request); // cmd = 0
      expect((frame[2] << 8) | frame[3], 42); // seq = 42
      expect((frame[4] << 8) | frame[5], Opcode.msgSend); // opcode = 64
      expect(frame[6], 0); // compressionRatio = 0

      final declaredLen = (frame[7] << 16) | (frame[8] << 8) | frame[9];
      expect(declaredLen, frame.length - TalerFraming.headerSize);

      final decoded = TalerFraming.decode(frame);
      expect(decoded.ver, TalerFraming.protocolVersion);
      expect(decoded.cmd, CmdType.request);
      expect(decoded.seq, 42);
      expect(decoded.opcode, Opcode.msgSend);
      expect(decoded.payloadAsMap?['chatId'], 777001);
      expect(decoded.payloadAsMap?['text'], 'Сообщение без LOG и DEBUG');
    });

    test('TalerPacketReceiver reassembles concatenated and 2-byte fragmented frames', () {
      final f1 = TalerFraming.encode(
        cmd: CmdType.request,
        seq: 1,
        opcode: Opcode.ping,
        payload: const <String, dynamic>{'interactive': false},
      );
      final f2 = TalerFraming.encode(
        cmd: CmdType.ok,
        seq: 2,
        opcode: Opcode.sessionInit,
        payload: const <String, dynamic>{'callsSeed': 'seed123'},
      );

      final receiverConcat = TalerPacketReceiver();
      final combined = Uint8List.fromList([...f1, ...f2]);
      final outConcat = receiverConcat.feed(combined);
      expect(outConcat.length, 2);
      expect(outConcat[0].seq, 1);
      expect(outConcat[0].opcode, Opcode.ping);
      expect(outConcat[1].seq, 2);
      expect(outConcat[1].opcode, Opcode.sessionInit);
      expect(outConcat[1].payloadAsMap?['callsSeed'], 'seed123');

      final receiverFrag = TalerPacketReceiver();
      final reassembled = <TalerPacket>[];
      for (var i = 0; i < f2.length; i += 2) {
        final end = (i + 2 <= f2.length) ? i + 2 : f2.length;
        reassembled.addAll(receiverFrag.feed(f2.sublist(i, end)));
      }
      expect(reassembled.length, 1);
      expect(reassembled.first.seq, 2);
      expect(reassembled.first.payloadAsMap?['callsSeed'], 'seed123');
    });
  });

  group('Lz4Block', () {
    test('decompresses LZ4 block with overlapping matches and trailing literals',
        () {
      // Блок LZ4 для строки "ABCDABCDABCD!":
      // Токен 1: 0x44 -> 4 литерала ("ABCD"), затем совпадение offset=4, matchLen=4+4=8 ("ABCDABCD")
      // Токен 2: 0x10 -> 1 литерал ("!"), конец блока
      final compressed = Uint8List.fromList(<int>[
        0x44,
        0x41, 0x42, 0x43, 0x44,
        0x04, 0x00,
        0x10,
        0x21,
      ]);

      final decompressed = Lz4Block.decompress(compressed, 64);
      expect(utf8.decode(decompressed), 'ABCDABCDABCD!');
    });
  });

  group('PrivacyFirewall', () {
    test('hard-blocks telemetry/banners and enforces Ghost Mode toggles',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final settings = PrivacySettings();
      await settings.load();
      final auditLog = WireAuditLog();
      final firewall = PrivacyFirewall(settings: settings, auditLog: auditLog);

      expect(settings.blockTelemetry, isTrue);

      for (final op in <int>[
        Opcode.log,
        Opcode.debug,
        Opcode.bannersSync,
        Opcode.chatSuggest,
      ]) {
        final d = firewall.inspectOutgoing(op, <String, dynamic>{'x': 1});
        expect(d.allowed, isFalse);
        expect(d.verdict, AuditVerdict.blockedTelemetry);
      }

      expect(
        firewall.inspectIncoming(Opcode.notifBanners, <String, dynamic>{}),
        isFalse,
      );

      // Ghost Mode: скрытие набора текста
      await settings.setHideTyping(true);
      final typingBlocked = firewall.inspectOutgoing(
        Opcode.msgTyping,
        <String, dynamic>{'chatId': 1},
      );
      expect(typingBlocked.allowed, isFalse);
      expect(typingBlocked.verdict, AuditVerdict.blockedGhost);

      await settings.setHideTyping(false);
      final typingAllowed = firewall.inspectOutgoing(
        Opcode.msgTyping,
        <String, dynamic>{'chatId': 1},
      );
      expect(typingAllowed.allowed, isTrue);

      // Anti-Read: блокировка READ_MESSAGE
      await settings.setHideReadReceipts(true);
      final readBlocked = firewall.inspectOutgoing(
        Opcode.chatMark,
        <String, dynamic>{'type': 'READ_MESSAGE', 'chatId': 1},
      );
      expect(readBlocked.allowed, isFalse);
      expect(readBlocked.verdict, AuditVerdict.blockedGhost);

      // Обычное сообщение пропускается
      final sendAllowed = firewall.inspectOutgoing(
        Opcode.msgSend,
        <String, dynamic>{'chatId': 1, 'text': 'hello'},
      );
      expect(sendAllowed.allowed, isTrue);
      expect(sendAllowed.verdict, AuditVerdict.allowed);

      expect(settings.blockedPacketsCount, greaterThanOrEqualTo(7));
      expect(auditLog.entries, isNotEmpty);

      for (var i = 0; i < 65; i++) {
        firewall.inspectIncoming(
          Opcode.msgSend,
          <String, dynamic>{
            'chats': List<Map<String, dynamic>>.generate(
              20,
              (j) => <String, dynamic>{'id': j, 'title': 'chat-$j'},
            ),
          },
        );
      }
      expect(auditLog.entries.length, lessThanOrEqualTo(60));
    });
  });

  group('LocalStore Anti-Delete & Edit History', () {
    test('preserves deleted peer messages and tracks text revisions', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = LocalStore();
      await store.init();

      const chatId = 505;
      const original = TalerMessage(
        id: 'm1',
        chatId: chatId,
        senderId: 99,
        text: 'Первая версия текста',
        time: 1000,
      );
      await store.upsertMessage(original);

      final edited = original.copyWith(text: 'Изменённая версия текста');
      await store.upsertMessage(edited, trackEditHistory: true);

      var messages = store.getMessages(chatId);
      expect(messages.length, 1);
      expect(messages.first.text, 'Изменённая версия текста');
      expect(messages.first.status, 'edited');
      expect(messages.first.editHistory.length, 1);
      expect(messages.first.editHistory.first.text, 'Первая версия текста');

      final affected = await store.markMessagesDeletedByPeer(
        chatId,
        const <String>['m1'],
        antiDeleteEnabled: true,
      );
      expect(affected, 1);

      messages = store.getMessages(chatId);
      expect(messages.length, 1);
      expect(messages.first.deletedByPeer, isTrue);
      expect(messages.first.deletedAt, isNotNull);
      expect(messages.first.text, 'Изменённая версия текста');

      // Проверка обычного удаления при выключенном Anti-Delete
      await store.upsertMessage(
        const TalerMessage(
          id: 'm2',
          chatId: chatId,
          senderId: 99,
          text: 'Временное сообщение',
          time: 2000,
        ),
      );
      await store.markMessagesDeletedByPeer(
        chatId,
        const <String>['m2'],
        antiDeleteEnabled: false,
      );
      await store.flush();
      expect(store.getMessages(chatId).any((m) => m.id == 'm2'), isFalse);
    });
  });

  group('SpoofProfile & PrivacySettings', () {
    test('toHandshakeUserAgent normalizes ANDROID/IOS presets and respects forceWeb', () {
      const androidProfile = SpoofProfile(
        presetId: 'pixel_9',
        label: 'Pixel 9 Pro',
        deviceType: 'ANDROID',
        pushDeviceType: 'GCM',
        deviceName: 'Google Pixel 9 Pro',
        osVersion: 'Android 15',
        screen: '1280x2856',
        timezone: 'Europe/Moscow',
        locale: 'ru',
        userAgent: 'Mozilla/5.0',
        appVersion: '25.8.0',
        buildNumber: 250800,
        arch: 'arm64-v8a',
        deviceId: 'dev-1',
        instanceId: 'inst-1',
        clientSessionId: 101,
      );

      final iosPreset = SpoofingService.presets.firstWhere(
        (p) => p.deviceType == 'IOS',
      );
      final iosProfile = SpoofProfile(
        presetId: iosPreset.id,
        label: iosPreset.label,
        deviceType: iosPreset.deviceType,
        pushDeviceType: iosPreset.pushDeviceType,
        deviceName: iosPreset.deviceName,
        osVersion: iosPreset.osVersion,
        screen: iosPreset.screen,
        timezone: iosPreset.timezone,
        locale: iosPreset.locale,
        userAgent: iosPreset.userAgent,
        appVersion: iosPreset.appVersion,
        buildNumber: iosPreset.buildNumber,
        arch: 'arm64',
        deviceId: 'dev-2',
        instanceId: 'inst-2',
        clientSessionId: 102,
      );

      for (final profile in [androidProfile, iosProfile]) {
        final ua = profile.toHandshakeUserAgent();
        expect(ua['deviceType'], 'ANDROID');
        expect(ua['pushDeviceType'], 'GCM');
        expect(ua.containsKey('headerUserAgent'), isFalse);
        expect(ua.containsKey('isPwa'), isFalse);
      }

      final webUa = androidProfile.toHandshakeUserAgent(forceWeb: true);
      expect(webUa['deviceType'], 'WEB');
      expect(webUa['pushDeviceType'], 'WEBPUSH');
      expect(webUa['headerUserAgent'], androidProfile.userAgent);
      expect(webUa['isPwa'], isTrue);

      final webPayload = androidProfile.toSessionInitPayload(forceWeb: true);
      expect((webPayload['userAgent'] as Map)['deviceType'], 'WEB');
      final nativePayload = iosProfile.toSessionInitPayload();
      expect((nativePayload['userAgent'] as Map)['deviceType'], 'ANDROID');
    });
  });

  testWidgets('TalerApp enters Demo Mode and displays chats and Privacy Shield',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const TalerApp());
    await tester.pumpAndSettle();

    expect(find.text('Маскировка устройства активна'), findsOneWidget);
    expect(find.text('Демо'), findsOneWidget);

    await tester.tap(find.text('Демо'));
    await tester.pumpAndSettle();

    expect(find.text('Запустить демо-режим Taler'), findsOneWidget);
    await tester.tap(find.text('Запустить демо-режим Taler'));
    await tester.pumpAndSettle();

    expect(find.text('Чаты'), findsOneWidget);
    expect(find.text('Taler Shield'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });
}

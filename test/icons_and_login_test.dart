import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:taler/backend/taler_client.dart';
import 'package:taler/core/privacy/spoofing_service.dart';
import 'package:taler/core/protocol/packet.dart';
import 'package:taler/ui/icons/taler_icon.dart';

void main() {
  group('TalerIcons', () {
    test('every icon draws inside the 24x24 box', () {
      expect(TalerIcons.values, isNotEmpty);
      for (final icon in TalerIcons.values) {
        final bounds = icon.path.getBounds();
        expect(bounds.width + bounds.height, greaterThan(0), reason: icon.name);
        expect(bounds.left, greaterThanOrEqualTo(-0.5), reason: icon.name);
        expect(bounds.top, greaterThanOrEqualTo(-0.5), reason: icon.name);
        expect(bounds.right, lessThanOrEqualTo(24.5), reason: icon.name);
        expect(bounds.bottom, lessThanOrEqualTo(24.5), reason: icon.name);
      }
    });

    test('icon names are unique', () {
      final names = TalerIcons.values.map((i) => i.name).toList();
      expect(names.toSet().length, names.length);
    });
  });

  testWidgets('TalerIcon morphs from one glyph into another', (tester) async {
    Widget host(TalerIconData icon) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: TalerIcon(icon, size: 24)),
        );

    await tester.pumpWidget(host(TalerIcons.eye));
    await tester.pumpWidget(host(TalerIcons.eyeOff));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(TalerIcon), findsOneWidget);
    expect(tester.getSize(find.byType(TalerIcon)), const Size(24, 24));
  });

  group('login restriction', () {
    test('recognises the MAX no2fa error', () {
      const restricted = TalerPacketException(
        'Логин ограничен. Требуется установить 2FA',
        code: 'error.profile.active.session.no2fa',
      );
      expect(TalerClient.isNo2faError(restricted), isTrue);
      expect(
        TalerClient.isNo2faError(Exception(restricted.toString())),
        isTrue,
      );
    });

    test('does not treat other errors as no2fa', () {
      const wrongCode = TalerPacketException(
        'Неверный код',
        code: 'error.code.wrong',
      );
      expect(TalerClient.isNo2faError(wrongCode), isFalse);
    });
  });

  group('device profile without masking', () {
    test('keeps the identifiers it was given', () {
      final profile = SpoofingService.buildNative(
        deviceId: 'abcdef0123456789',
        instanceId: '00000000-0000-4000-8000-000000000000',
        clientSessionId: 42,
      );
      expect(profile.presetId, 'native');
      expect(profile.deviceId, 'abcdef0123456789');
      expect(profile.clientSessionId, 42);
      expect(profile.toSessionInitPayload()['deviceId'], 'abcdef0123456789');
    });

    test('maps UTC offsets to IANA zones', () {
      expect(SpoofingService.nativeTimezone(const Duration(hours: 3)), 'Europe/Moscow');
      expect(SpoofingService.nativeTimezone(const Duration(hours: 7)), 'Asia/Novosibirsk');
      expect(SpoofingService.nativeTimezone(const Duration(hours: -5)), 'Etc/GMT+5');
    });
  });
}

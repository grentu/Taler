import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'spoof_profile.dart';

/// Сервис спуфинга идентификаторов устройства.
///
/// Taler никогда не читает реальный серийный номер, IMEI, IDFV, Android ID
/// или имя хоста пользователя — вместо этого используется виртуальный профиль.
class SpoofingService extends ChangeNotifier {
  static const _kActiveProfile = 'taler_spoof_active_profile_v2';
  static final Random _rng = Random.secure();

  static const List<DevicePreset> presets = [
    DevicePreset(
      id: 'pixel_9_pro',
      label: 'Google Pixel 9 Pro',
      deviceType: 'ANDROID',
      pushDeviceType: 'GCM',
      deviceName: 'Google Pixel 9 Pro',
      osVersion: 'Android 15',
      screen: '480dpi 1080x2400',
      timezone: 'Europe/Moscow',
      locale: 'ru',
      userAgent:
          'Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
    ),
    DevicePreset(
      id: 'galaxy_s24_ultra',
      label: 'Samsung Galaxy S24 Ultra',
      deviceType: 'ANDROID',
      pushDeviceType: 'GCM',
      deviceName: 'Samsung Galaxy S24 Ultra',
      osVersion: 'Android 14',
      screen: '480dpi 1440x3120',
      timezone: 'Europe/Berlin',
      locale: 'ru',
      userAgent:
          'Mozilla/5.0 (Linux; Android 14; SM-S928B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
    ),
    DevicePreset(
      id: 'oneplus_12',
      label: 'OnePlus 12',
      deviceType: 'ANDROID',
      pushDeviceType: 'GCM',
      deviceName: 'OnePlus 12',
      osVersion: 'Android 14',
      screen: '480dpi 1440x3168',
      timezone: 'Europe/London',
      locale: 'ru',
      userAgent:
          'Mozilla/5.0 (Linux; Android 14; CPH2521) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
    ),
    DevicePreset(
      id: 'iphone_16_pro',
      label: 'iPhone 16 Pro (iOS)',
      deviceType: 'IOS',
      pushDeviceType: 'APNS',
      deviceName: 'iPhone 16 Pro',
      osVersion: 'iOS 18.1',
      screen: '1206x2622',
      timezone: 'Europe/Amsterdam',
      locale: 'ru',
      arch: 'arm64',
      userAgent:
          'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1',
    ),
    DevicePreset(
      id: 'safari_macos',
      label: 'Safari macOS (Desktop Web)',
      deviceType: 'WEB',
      pushDeviceType: 'WEBPUSH',
      deviceName: 'Safari',
      osVersion: 'macOS 14.5',
      screen: '2560x1600',
      timezone: 'Europe/Paris',
      locale: 'ru',
      appVersion: '26.8.8',
      arch: 'arm64',
      userAgent:
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15',
    ),
    DevicePreset(
      id: 'chrome_linux',
      label: 'Chrome Linux (Desktop Web)',
      deviceType: 'WEB',
      pushDeviceType: 'WEBPUSH',
      deviceName: 'Chrome',
      osVersion: 'Linux',
      screen: '1920x1080',
      timezone: 'Europe/Moscow',
      locale: 'ru',
      appVersion: '26.8.8',
      arch: 'x86_64',
      userAgent:
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    ),
  ];

  SharedPreferences? _prefs;
  SpoofProfile _activeProfile = buildFromPreset(presets.first);

  SpoofProfile get activeProfile => _activeProfile;

  Future<void> load([SharedPreferences? prefs]) async {
    _prefs = prefs ?? await SharedPreferences.getInstance();
    final raw = _prefs?.getString(_kActiveProfile);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final loaded = SpoofProfile.fromJson(decoded);
        if (loaded.deviceType == 'ANDROID' || loaded.deviceType == 'IOS') {
          _activeProfile = loaded;
          notifyListeners();
          return;
        }
      } catch (_) {}
    }
    _activeProfile = buildFromPreset(presets.first);
    await _save();
    notifyListeners();
  }

  /// Переключает профиль на выбранный [preset] с опциональной ротацией ID.
  Future<void> selectPreset(
    DevicePreset preset, {
    bool rotateIdentifiers = false,
  }) async {
    _activeProfile = buildFromPreset(
      preset,
      deviceId: rotateIdentifiers ? null : _activeProfile.deviceId,
      instanceId: rotateIdentifiers ? null : _activeProfile.instanceId,
    );
    notifyListeners();
    await _save();
  }

  /// Генерирует новые криптостойкие `deviceId`, `instanceId` и `clientSessionId`.
  Future<void> regenerateIdentifiers() async {
    _activeProfile = _activeProfile.copyWith(
      deviceId: generateDeviceId(),
      instanceId: generateUuidV4(),
      clientSessionId: _rng.nextInt(0x7FFFFFFF) + 1,
    );
    notifyListeners();
    await _save();
  }

  /// Выбирает случайный Android-пресет и генерирует свежие идентификаторы.
  Future<void> randomizeAll() async {
    final androidPresets =
        presets.where((p) => p.deviceType == 'ANDROID').toList();
    final candidates = androidPresets
        .where((p) => p.id != _activeProfile.presetId)
        .toList();
    final pool = candidates.isNotEmpty ? candidates : androidPresets;
    final chosen = pool[_rng.nextInt(pool.length)];
    _activeProfile = buildFromPreset(chosen);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    await _prefs?.setString(
      _kActiveProfile,
      jsonEncode(_activeProfile.toJson()),
    );
  }

  static SpoofProfile buildFromPreset(
    DevicePreset preset, {
    String? deviceId,
    String? instanceId,
    int? clientSessionId,
  }) {
    return SpoofProfile(
      presetId: preset.id,
      label: preset.label,
      deviceType: preset.deviceType,
      pushDeviceType: preset.pushDeviceType,
      deviceName: preset.deviceName,
      osVersion: preset.osVersion,
      screen: preset.screen,
      timezone: preset.timezone,
      locale: preset.locale,
      userAgent: preset.userAgent,
      appVersion: preset.appVersion,
      buildNumber: preset.buildNumber,
      arch: preset.arch,
      deviceId: deviceId ?? generateDeviceId(),
      instanceId: instanceId ?? generateUuidV4(),
      clientSessionId: clientSessionId ?? (_rng.nextInt(0x7FFFFFFF) + 1),
    );
  }

  static String generateDeviceId([int bytes = 8]) {
    final sb = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      sb.write(_rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static String generateUuidV4() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex(int v) => v.toRadixString(16).padLeft(2, '0');
    return '${hex(b[0])}${hex(b[1])}${hex(b[2])}${hex(b[3])}-'
        '${hex(b[4])}${hex(b[5])}-'
        '${hex(b[6])}${hex(b[7])}-'
        '${hex(b[8])}${hex(b[9])}-'
        '${hex(b[10])}${hex(b[11])}${hex(b[12])}${hex(b[13])}${hex(b[14])}${hex(b[15])}';
  }
}

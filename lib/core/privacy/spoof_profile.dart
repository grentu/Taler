/// Виртуальный профиль устройства для маскировки реального железа при хендшейке.
class SpoofProfile {
  final String presetId;
  final String label;
  final String deviceType;
  final String pushDeviceType;
  final String deviceName;
  final String osVersion;
  final String screen;
  final String timezone;
  final String locale;
  final String userAgent;
  final String appVersion;
  final int buildNumber;
  final String arch;
  final String deviceId;
  final String instanceId;
  final int clientSessionId;

  const SpoofProfile({
    required this.presetId,
    required this.label,
    required this.deviceType,
    required this.pushDeviceType,
    required this.deviceName,
    required this.osVersion,
    required this.screen,
    required this.timezone,
    required this.locale,
    required this.userAgent,
    required this.appVersion,
    required this.buildNumber,
    required this.arch,
    required this.deviceId,
    required this.instanceId,
    required this.clientSessionId,
  });

  SpoofProfile copyWith({
    String? presetId,
    String? label,
    String? deviceType,
    String? pushDeviceType,
    String? deviceName,
    String? osVersion,
    String? screen,
    String? timezone,
    String? locale,
    String? userAgent,
    String? appVersion,
    int? buildNumber,
    String? arch,
    String? deviceId,
    String? instanceId,
    int? clientSessionId,
  }) {
    return SpoofProfile(
      presetId: presetId ?? this.presetId,
      label: label ?? this.label,
      deviceType: deviceType ?? this.deviceType,
      pushDeviceType: pushDeviceType ?? this.pushDeviceType,
      deviceName: deviceName ?? this.deviceName,
      osVersion: osVersion ?? this.osVersion,
      screen: screen ?? this.screen,
      timezone: timezone ?? this.timezone,
      locale: locale ?? this.locale,
      userAgent: userAgent ?? this.userAgent,
      appVersion: appVersion ?? this.appVersion,
      buildNumber: buildNumber ?? this.buildNumber,
      arch: arch ?? this.arch,
      deviceId: deviceId ?? this.deviceId,
      instanceId: instanceId ?? this.instanceId,
      clientSessionId: clientSessionId ?? this.clientSessionId,
    );
  }

  /// Формирует объект `userAgent` для `Opcode.sessionInit (6)` без утечки
  /// реальных параметров устройства пользователя.
  ///
  /// На нативном TLS-сокете сервер MAX возвращает `callsSeed` только для
  /// не-WEB профилей с `deviceType: 'ANDROID'`, поэтому любые не-WEB пресеты
  /// (включая iOS и Desktop) на проводе представляются как `ANDROID`/`GCM`.
  /// При передаче [forceWeb] (резервный WebSocket-шлюз) используется формат `WEB`.
  Map<String, Object?> toHandshakeUserAgent({bool forceWeb = false}) {
    final shortLocale = locale.split(RegExp(r'[-_]')).first;
    final useWeb = forceWeb || deviceType == 'WEB';

    if (useWeb) {
      return <String, Object?>{
        'deviceType': 'WEB',
        'pushDeviceType': 'WEBPUSH',
        'locale': shortLocale,
        'deviceLocale': shortLocale,
        'osVersion': deviceType == 'WEB' ? osVersion : 'Windows',
        'deviceName': deviceType == 'WEB' ? deviceName : 'Chrome',
        'headerUserAgent': userAgent,
        'isPwa': true,
        'appVersion': deviceType == 'WEB' ? appVersion : '26.8.8',
        'screen': screen,
        'timezone': timezone,
      };
    }

    return <String, Object?>{
      'deviceType': 'ANDROID',
      'pushDeviceType': 'GCM',
      'locale': shortLocale,
      'deviceLocale': shortLocale,
      'osVersion': osVersion,
      'deviceName': deviceName,
      'appVersion': appVersion,
      'screen': screen,
      'timezone': timezone,
      'arch': arch.isEmpty ? 'arm64-v8a' : arch,
      'buildNumber': buildNumber == 0 ? 6779 : buildNumber,
    };
  }

  /// Формирует полный payload для `Opcode.sessionInit (6)` поверх TLS или WebSocket.
  Map<String, Object?> toSessionInitPayload({bool forceWeb = false}) {
    final ua = toHandshakeUserAgent(forceWeb: forceWeb);
    final isWeb = ua['deviceType'] == 'WEB';
    return <String, Object?>{
      if (!isWeb && instanceId.isNotEmpty) 'mt_instanceid': instanceId,
      'userAgent': ua,
      if (!isWeb && clientSessionId != 0) 'clientSessionId': clientSessionId,
      'deviceId': deviceId,
    };
  }

  Map<String, dynamic> toJson() => {
        'presetId': presetId,
        'label': label,
        'deviceType': deviceType,
        'pushDeviceType': pushDeviceType,
        'deviceName': deviceName,
        'osVersion': osVersion,
        'screen': screen,
        'timezone': timezone,
        'locale': locale,
        'userAgent': userAgent,
        'appVersion': appVersion,
        'buildNumber': buildNumber,
        'arch': arch,
        'deviceId': deviceId,
        'instanceId': instanceId,
        'clientSessionId': clientSessionId,
      };

  factory SpoofProfile.fromJson(Map<String, dynamic> json) {
    return SpoofProfile(
      presetId: json['presetId'] as String? ?? 'chrome_linux',
      label: json['label'] as String? ?? 'Chrome Linux (Desktop Web)',
      deviceType: json['deviceType'] as String? ?? 'WEB',
      pushDeviceType: json['pushDeviceType'] as String? ?? 'WEBPUSH',
      deviceName: json['deviceName'] as String? ?? 'Chrome',
      osVersion: json['osVersion'] as String? ?? 'Linux',
      screen: json['screen'] as String? ?? '1920x1080',
      timezone: json['timezone'] as String? ?? 'Europe/Moscow',
      locale: json['locale'] as String? ?? 'ru',
      userAgent: json['userAgent'] as String? ??
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      appVersion: json['appVersion'] as String? ?? '26.8.8',
      buildNumber: json['buildNumber'] as int? ?? 6779,
      arch: json['arch'] as String? ?? 'x86_64',
      deviceId: json['deviceId'] as String? ?? '0000000000000000',
      instanceId: json['instanceId'] as String? ?? '00000000-0000-4000-8000-000000000000',
      clientSessionId: json['clientSessionId'] as int? ?? 1,
    );
  }
}

/// Пресет маскировки устройства.
class DevicePreset {
  final String id;
  final String label;
  final String deviceType;
  final String pushDeviceType;
  final String deviceName;
  final String osVersion;
  final String screen;
  final String timezone;
  final String locale;
  final String userAgent;
  final String appVersion;
  final int buildNumber;
  final String arch;

  const DevicePreset({
    required this.id,
    required this.label,
    required this.deviceType,
    required this.pushDeviceType,
    required this.deviceName,
    required this.osVersion,
    required this.screen,
    required this.timezone,
    required this.locale,
    required this.userAgent,
    this.appVersion = '26.23.2',
    this.buildNumber = 6779,
    this.arch = 'arm64-v8a',
  });
}

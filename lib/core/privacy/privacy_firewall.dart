import 'package:flutter/foundation.dart';

import '../protocol/opcode.dart';
import 'privacy_settings.dart';

enum PacketDirection { outgoing, incoming }

enum AuditVerdict { allowed, blockedTelemetry, blockedGhost }

/// Запись в журнале инспекции трафика Taler WireAuditLog.
class WireAuditEntry {
  final DateTime timestamp;
  final PacketDirection direction;
  final int opcode;
  final String opcodeName;
  final int seq;
  final AuditVerdict verdict;
  final String summary;
  final Object? payload;

  const WireAuditEntry({
    required this.timestamp,
    required this.direction,
    required this.opcode,
    required this.opcodeName,
    required this.seq,
    required this.verdict,
    required this.summary,
    this.payload,
  });

  bool get isBlocked => verdict != AuditVerdict.allowed;
}

/// Кольцевой буфер последних 60 сетевых пакетов для аудита приватности в UI.
class WireAuditLog extends ChangeNotifier {
  static const int maxEntries = 60;
  final List<WireAuditEntry> _entries = [];

  List<WireAuditEntry> get entries => List.unmodifiable(_entries);

  /// Сокращает крупные структуры payload (например, ответ LOGIN с сотнями
  /// чатов и бинарными блоками), чтобы WireAuditLog не удерживал мегабайты ОЗУ.
  static Object? compactPayload(Object? payload, {int depth = 0}) {
    if (payload == null || payload is num || payload is bool) {
      return payload;
    }
    if (payload is Uint8List) {
      return '<binary ${payload.length} B>';
    }
    if (payload is String) {
      if (payload.length <= 200) return payload;
      return '${payload.substring(0, 200)}... (+${payload.length - 200} chars)';
    }
    if (payload is List) {
      if (depth >= 2) return '<List(${payload.length})>';
      final out = <Object?>[];
      final limit = payload.length < 4 ? payload.length : 4;
      for (var i = 0; i < limit; i++) {
        out.add(compactPayload(payload[i], depth: depth + 1));
      }
      if (payload.length > 4) {
        out.add('... (+${payload.length - 4} items)');
      }
      return out;
    }
    if (payload is Map) {
      if (depth >= 2) return '<Map(${payload.length} keys)>';
      final out = <String, Object?>{};
      var count = 0;
      for (final entry in payload.entries) {
        if (count >= 8) {
          out['__truncated__'] = '+${payload.length - 8} keys';
          break;
        }
        out[entry.key.toString()] =
            compactPayload(entry.value, depth: depth + 1);
        count++;
      }
      return out;
    }
    final text = payload.toString();
    return text.length <= 200 ? text : '${text.substring(0, 200)}...';
  }

  void record(WireAuditEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}

class FirewallDecision {
  final bool allowed;
  final AuditVerdict verdict;
  final String reason;

  const FirewallDecision._({
    required this.allowed,
    required this.verdict,
    required this.reason,
  });

  factory FirewallDecision.allow([String reason = 'Разрешён']) =>
      FirewallDecision._(
        allowed: true,
        verdict: AuditVerdict.allowed,
        reason: reason,
      );

  factory FirewallDecision.block(AuditVerdict verdict, String reason) =>
      FirewallDecision._(
        allowed: false,
        verdict: verdict,
        reason: reason,
      );
}

/// Транспортный файрвол Taler Privacy Shield.
///
/// Проверяет каждый исходящий и входящий пакет протокола MAX до его отправки
/// в сокет или обработки в приложении, а также фильтрует трекинговые URL и
/// санитизирует чувствительные поля (Ghost Mode, конфиги баннеров).
class PrivacyFirewall {
  /// Нейтральный User-Agent для HTTP-запросов медиа/загрузок (без утечки `Dart/3.x` или `Taler/...`).
  static const String defaultHttpUserAgent =
      'Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static const Set<String> _blockedTrackingHosts = {
    'top-fwz1.mail.ru',
    'counter.yadro.ru',
    'mc.yandex.ru',
    'appmetrica.yandex.net',
    'report.appmetrica.yandex.net',
    'mytracker.my.com',
    'tracker.my.com',
    'tracker-s2s.my.com',
    'stat.oneme.ru',
    'analytics.oneme.ru',
    'telemetry.oneme.ru',
    'metrics.oneme.ru',
    'google-analytics.com',
    'www.google-analytics.com',
    'googletagmanager.com',
    'doubleclick.net',
    'sentry.io',
    'crashlytics.com',
    'firebaselogging.googleapis.com',
    'app-measurement.com',
  };

  static const Set<String> _blockedConfigKeys = {
    'banners',
    'analytics',
    'telemetry',
    'tracking',
    'tracker',
    'mytracker',
    'abTests',
    'promo',
    'ads',
  };

  static const Set<String> _forbiddenHardwareKeys = {
    'imei',
    'imsi',
    'androidId',
    'android_id',
    'mac',
    'macAddress',
    'advertisingId',
    'gaid',
    'idfa',
    'idfv',
    'serial',
    'serialNumber',
  };

  /// Проверяет, ведёт ли URL на известный домен телеметрии, аналитики или трекера.
  static bool isTrackingUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    if (_blockedTrackingHosts.contains(host)) return true;
    for (final blocked in _blockedTrackingHosts) {
      if (host.endsWith('.$blocked')) return true;
    }
    if (host.startsWith('telemetry.') ||
        host.startsWith('metrics.') ||
        host.startsWith('analytics.') ||
        host.startsWith('tracker.')) {
      return true;
    }
    if ((host == 'vk.com' || host.endsWith('.vk.com')) &&
        uri.path.toLowerCase().startsWith('/rtrg')) {
      return true;
    }
    return false;
  }

  final PrivacySettings settings;
  final WireAuditLog auditLog;

  PrivacyFirewall({
    required this.settings,
    required this.auditLog,
  });

  /// Принудительно очищает исходящий payload:
  /// - в Ghost Mode гарантирует `interactive: false` в PING и LOGIN;
  /// - в SESSION_INIT удаляет любые аппаратные идентификаторы, если вдруг попали.
  Object? sanitizeOutgoingPayload(int opcode, Object? payload) {
    if (payload is! Map) return payload;
    if ((opcode == Opcode.ping || opcode == Opcode.login) &&
        settings.ghostModeOnline) {
      if (payload['interactive'] != false) {
        final copy = Map<dynamic, dynamic>.from(payload);
        copy['interactive'] = false;
        return copy;
      }
    }
    if (opcode == Opcode.sessionInit) {
      final copy = Map<dynamic, dynamic>.from(payload);
      for (final key in _forbiddenHardwareKeys) {
        copy.remove(key);
      }
      final ua = copy['userAgent'];
      if (ua is Map) {
        final uaCopy = Map<dynamic, dynamic>.from(ua);
        for (final key in _forbiddenHardwareKeys) {
          uaCopy.remove(key);
        }
        copy['userAgent'] = uaCopy;
      }
      return copy;
    }
    return payload;
  }

  /// Вырезает рекламные и телеметрийные поля из входящих конфигов и LOGIN.
  Object? sanitizeIncomingPayload(int opcode, Object? payload) {
    if (payload is! Map) return payload;
    if (opcode != Opcode.login &&
        opcode != Opcode.config &&
        opcode != Opcode.notifConfig) {
      return payload;
    }
    return _stripBlockedKeys(payload);
  }

  static Map<dynamic, dynamic> _stripBlockedKeys(Map<dynamic, dynamic> src) {
    var mutated = false;
    final out = <dynamic, dynamic>{};
    for (final entry in src.entries) {
      final key = entry.key.toString();
      if (_blockedConfigKeys.contains(key)) {
        mutated = true;
        continue;
      }
      if (entry.value is Map &&
          (key == 'config' || key == 'server' || key == 'user')) {
        final nested = _stripBlockedKeys(entry.value as Map<dynamic, dynamic>);
        if (!identical(nested, entry.value)) mutated = true;
        out[entry.key] = nested;
      } else {
        out[entry.key] = entry.value;
      }
    }
    return mutated ? out : src;
  }

  /// Инспектирует исходящий пакет. Возвращает решение о пропуске или блокировке.
  FirewallDecision inspectOutgoing(
    int opcode,
    Object? payload, {
    int seq = 0,
  }) {
    final opName = Opcode.name(opcode);

    if (Opcode.telemetryOpcodes.contains(opcode)) {
      settings.incrementBlockedCount();
      final reason = 'Заблокирована телеметрия/реклама ($opName #$opcode)';
      auditLog.record(
        WireAuditEntry(
          timestamp: DateTime.now(),
          direction: PacketDirection.outgoing,
          opcode: opcode,
          opcodeName: opName,
          seq: seq,
          verdict: AuditVerdict.blockedTelemetry,
          summary: reason,
          payload: WireAuditLog.compactPayload(payload),
        ),
      );
      return FirewallDecision.block(AuditVerdict.blockedTelemetry, reason);
    }

    if (opcode == Opcode.msgTyping && settings.hideTyping) {
      settings.incrementBlockedCount();
      const reason = 'Скрыт индикатор набора текста (Ghost Mode)';
      auditLog.record(
        WireAuditEntry(
          timestamp: DateTime.now(),
          direction: PacketDirection.outgoing,
          opcode: opcode,
          opcodeName: opName,
          seq: seq,
          verdict: AuditVerdict.blockedGhost,
          summary: reason,
          payload: WireAuditLog.compactPayload(payload),
        ),
      );
      return FirewallDecision.block(AuditVerdict.blockedGhost, reason);
    }

    if (opcode == Opcode.chatMark && settings.hideReadReceipts) {
      final typeStr = payload is Map ? payload['type']?.toString().toUpperCase() : null;
      final isReadReceipt = typeStr == null || typeStr.contains('READ');
      if (isReadReceipt) {
        settings.incrementBlockedCount();
        const reason = 'Скрыта отметка о прочтении (Anti-Read)';
        auditLog.record(
          WireAuditEntry(
            timestamp: DateTime.now(),
            direction: PacketDirection.outgoing,
            opcode: opcode,
            opcodeName: opName,
            seq: seq,
            verdict: AuditVerdict.blockedGhost,
            summary: reason,
            payload: WireAuditLog.compactPayload(payload),
          ),
        );
        return FirewallDecision.block(AuditVerdict.blockedGhost, reason);
      }
    }

    auditLog.record(
      WireAuditEntry(
        timestamp: DateTime.now(),
        direction: PacketDirection.outgoing,
        opcode: opcode,
        opcodeName: opName,
        seq: seq,
        verdict: AuditVerdict.allowed,
        summary: 'Отправлен запрос $opName',
        payload: WireAuditLog.compactPayload(payload),
      ),
    );
    return FirewallDecision.allow();
  }

  /// Инспектирует входящий пакет/пуш. Возвращает `false`, если пакет нужно отбросить.
  bool inspectIncoming(
    int opcode,
    Object? payload, {
    int seq = 0,
  }) {
    final opName = Opcode.name(opcode);
    if (Opcode.telemetryOpcodes.contains(opcode)) {
      settings.incrementBlockedCount();
      auditLog.record(
        WireAuditEntry(
          timestamp: DateTime.now(),
          direction: PacketDirection.incoming,
          opcode: opcode,
          opcodeName: opName,
          seq: seq,
          verdict: AuditVerdict.blockedTelemetry,
          summary: 'Отброшен входящий пакет слежки/баннеров ($opName)',
          payload: WireAuditLog.compactPayload(payload),
        ),
      );
      return false;
    }

    auditLog.record(
      WireAuditEntry(
        timestamp: DateTime.now(),
        direction: PacketDirection.incoming,
        opcode: opcode,
        opcodeName: opName,
        seq: seq,
        verdict: AuditVerdict.allowed,
        summary: 'Получен пакет $opName',
        payload: WireAuditLog.compactPayload(payload),
      ),
    );
    return true;
  }
}

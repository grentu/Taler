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
/// в сокет или обработки в приложении.
class PrivacyFirewall {
  final PrivacySettings settings;
  final WireAuditLog auditLog;

  PrivacyFirewall({
    required this.settings,
    required this.auditLog,
  });

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

    if (opcode == Opcode.chatMark &&
        settings.hideReadReceipts &&
        payload is Map &&
        payload['type'] == 'READ_MESSAGE') {
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

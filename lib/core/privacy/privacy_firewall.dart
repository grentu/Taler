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

/// Кольцевой буфер последних 200 сетевых пакетов для аудита приватности в UI.
class WireAuditLog extends ChangeNotifier {
  static const int maxEntries = 200;
  final List<WireAuditEntry> _entries = [];

  List<WireAuditEntry> get entries => List.unmodifiable(_entries);

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
          payload: payload,
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
          payload: payload,
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
          payload: payload,
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
        payload: payload,
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
          payload: payload,
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
        payload: payload,
      ),
    );
    return true;
  }
}

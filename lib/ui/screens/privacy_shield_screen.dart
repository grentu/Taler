import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../backend/taler_client.dart';
import '../../core/privacy/privacy_firewall.dart';
import '../../core/privacy/spoof_profile.dart';
import '../../core/privacy/spoofing_service.dart';
import '../theme/taler_theme.dart';

enum _LogFilter { all, blocked, allowed }

/// Центр управления приватностью Taler Privacy Shield и живой инспектор пакетов.
class PrivacyShieldScreen extends StatefulWidget {
  final TalerClient client;

  const PrivacyShieldScreen({super.key, required this.client});

  @override
  State<PrivacyShieldScreen> createState() => _PrivacyShieldScreenState();
}

class _PrivacyShieldScreenState extends State<PrivacyShieldScreen> {
  _LogFilter _filter = _LogFilter.all;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final privacy = widget.client.privacySettings;
    final spoof = widget.client.spoofingService;
    final audit = widget.client.auditLog;

    return ListenableBuilder(
      listenable: Listenable.merge([privacy, spoof, audit]),
      builder: (context, _) {
        final active = spoof.activeProfile;
        final filtered = audit.entries.where((e) {
          return switch (_filter) {
            _LogFilter.all => true,
            _LogFilter.blocked => e.isBlocked,
            _LogFilter.allowed => !e.isBlocked,
          };
        }).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Taler Privacy Shield'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.tonalIcon(
                  onPressed: () => widget.client.triggerTelemetryTestProbe(),
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: const Text('Тест блокировки'),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Сводка защиты от телеметрии
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: TalerTheme.shieldGreen.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.shield_rounded,
                          color: TalerTheme.shieldGreen,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Телеметрия MAX вырезана (100%)',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Опкоды LOG (5), DEBUG (2), BANNERS_SYNC (302), CHAT_SUGGEST (300) и NOTIF_BANNERS (292) жёстко блокируются до отправки в сокет.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${privacy.blockedPacketsCount}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: TalerTheme.shieldGreen,
                            ),
                          ),
                          Text(
                            'перехвачено',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Переключатели приватности
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Режим «Призрак» (скрыть онлайн)'),
                      subtitle: const Text(
                        'Отправляет interactive: false в LOGIN и PING — вас не видно в сети',
                      ),
                      value: privacy.ghostModeOnline,
                      onChanged: (v) {
                        privacy.setGhostModeOnline(v);
                        widget.client.session.sendPing();
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Скрывать «печатает...»'),
                      subtitle: const Text(
                        'Блокирует исходящие пакеты MSG_TYPING (65)',
                      ),
                      value: privacy.hideTyping,
                      onChanged: privacy.setHideTyping,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Anti-Read (скрыть прочтение)'),
                      subtitle: const Text(
                        'Блокирует CHAT_MARK READ_MESSAGE (50), оставляя локальный счётчик',
                      ),
                      value: privacy.hideReadReceipts,
                      onChanged: privacy.setHideReadReceipts,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Anti-Delete и история правок'),
                      subtitle: const Text(
                        'Сохраняет сообщения, удалённые собеседником, и все старые редакции',
                      ),
                      value: privacy.antiDelete,
                      onChanged: privacy.setAntiDelete,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Спуфинг устройства'),
                      subtitle: const Text(
                        'Подменяет модель, ОС, разрешение экрана и Device ID при подключении',
                      ),
                      value: privacy.spoofingEnabled,
                      onChanged: privacy.setSpoofingEnabled,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Панель Device Spoofing
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Профиль маскировки устройства',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: spoof.regenerateIdentifiers,
                            icon: const Icon(Icons.refresh_rounded, size: 17),
                            label: const Text('Новый ID'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: SpoofingService.presets
                                .any((p) => p.id == active.presetId)
                            ? active.presetId
                            : SpoofingService.presets.first.id,
                        decoration: const InputDecoration(
                          labelText: 'Пресет устройства',
                        ),
                        items: [
                          for (final DevicePreset p in SpoofingService.presets)
                            DropdownMenuItem(
                              value: p.id,
                              child: Text('${p.label} (${p.deviceType})'),
                            ),
                        ],
                        onChanged: (id) {
                          if (id == null) return;
                          final preset = SpoofingService.presets.firstWhere(
                            (p) => p.id == id,
                          );
                          spoof.selectPreset(preset);
                        },
                      ),
                      const SizedBox(height: 12),
                      _KvRow(label: 'Device ID', value: active.deviceId),
                      _KvRow(label: 'Instance UUID', value: active.instanceId),
                      _KvRow(label: 'ОС / Экран', value: '${active.osVersion} • ${active.screen}'),
                      _KvRow(label: 'Локаль / TZ', value: '${active.locale} • ${active.timezone}'),
                      _KvRow(label: 'User-Agent', value: active.userAgent),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Инспектор пакетов (Traffic Audit Log)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Инспектор трафика (Wire Audit Log)',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: audit.clear,
                            child: const Text('Очистить'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text('Все (${audit.entries.length})'),
                            selected: _filter == _LogFilter.all,
                            onSelected: (_) =>
                                setState(() => _filter = _LogFilter.all),
                          ),
                          ChoiceChip(
                            label: const Text('Заблокированные'),
                            selected: _filter == _LogFilter.blocked,
                            onSelected: (_) =>
                                setState(() => _filter = _LogFilter.blocked),
                          ),
                          ChoiceChip(
                            label: const Text('Разрешённые'),
                            selected: _filter == _LogFilter.allowed,
                            onSelected: (_) =>
                                setState(() => _filter = _LogFilter.allowed),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'Журнал пакетов пока пуст. Нажмите «Тест блокировки» или откройте чат.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = filtered[index];
                            return _AuditTile(
                              entry: entry,
                              onTap: () => _showPayloadDialog(entry),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPayloadDialog(WireAuditEntry entry) {
    String formatted;
    try {
      formatted = const JsonEncoder.withIndent('  ').convert(entry.payload);
    } catch (_) {
      formatted = entry.payload?.toString() ?? 'null';
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${entry.opcodeName} (#${entry.opcode})'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: SelectableText(
              formatted,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
}

class _KvRow extends StatelessWidget {
  final String label;
  final String value;

  const _KvRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  final WireAuditEntry entry;
  final VoidCallback onTap;

  const _AuditTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOut = entry.direction == PacketDirection.outgoing;
    final badgeColor = switch (entry.verdict) {
      AuditVerdict.blockedTelemetry => TalerTheme.dangerRed,
      AuditVerdict.blockedGhost => TalerTheme.warningAmber,
      AuditVerdict.allowed => TalerTheme.shieldGreen,
    };
    final badgeText = switch (entry.verdict) {
      AuditVerdict.blockedTelemetry => 'BLOCKED',
      AuditVerdict.blockedGhost => 'GHOST',
      AuditVerdict.allowed => 'OK',
    };

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(
        isOut ? Icons.north_east_rounded : Icons.south_west_rounded,
        size: 18,
        color: badgeColor,
      ),
      title: Row(
        children: [
          Text(
            '${entry.opcodeName} (#${entry.opcode})',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              fontSize: 12.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                color: badgeColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        entry.summary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        DateFormat('HH:mm:ss').format(entry.timestamp),
        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
      ),
    );
  }
}

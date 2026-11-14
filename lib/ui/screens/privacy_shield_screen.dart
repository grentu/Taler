import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/privacy/privacy_firewall.dart';
import '../../core/privacy/spoof_profile.dart';
import '../../core/privacy/spoofing_service.dart';
import '../theme/taler_theme.dart';

enum _LogFilter { all, blocked, allowed }

/// Центр управления приватностью Taler Privacy Shield и живой инспектор трафика.
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
    final p = TalerTheme.paletteOf(context);
    final privacy = widget.client.privacySettings;
    final spoof = widget.client.spoofingService;
    final audit = widget.client.auditLog;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 860;
    final isTwoCol = screenWidth >= 1040;

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

        final content = Column(
          children: [
            // Единая верхняя планка 56px
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: p.bg2,
                border: Border(bottom: BorderSide(color: p.line)),
              ),
              child: Row(
                children: [
                  TalerStatusDot(color: p.statusLive, size: 6),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Taler Privacy Shield',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.3,
                        color: p.fg,
                      ),
                    ),
                  ),
                  TalerTactileButton(
                    label: 'Тест блокировки',
                    icon: Icons.bolt_rounded,
                    compact: true,
                    onPressed: () => widget.client.triggerTelemetryTestProbe(),
                  ),
                ],
              ),
            ),

            // Основное содержимое
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  isWide ? 24 : 16,
                  20,
                  isWide ? 24 : 16,
                  isWide ? 24 : 96,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Полоса сводки (общая таблица без цветных квадратов)
                        _buildSummaryShell(
                          p,
                          blockedCount: privacy.blockedPacketsCount,
                          profile: active,
                          horizontal: screenWidth >= 740,
                        ),
                        const SizedBox(height: 16),

                        // Переключатели приватности и профиль спуфинга
                        if (isTwoCol)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 6,
                                child: _buildPrivacyToggles(p, privacy),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 5,
                                child: _buildSpoofingShell(p, spoof, active),
                              ),
                            ],
                          )
                        else ...[
                          _buildPrivacyToggles(p, privacy),
                          const SizedBox(height: 16),
                          _buildSpoofingShell(p, spoof, active),
                        ],
                        const SizedBox(height: 16),

                        // Живой журнал пакетов Wire Audit Log
                        _buildAuditShell(p, audit, filtered, isWide: isWide),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

        if (!isWide) {
          return SafeArea(bottom: false, child: content);
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                color: p.bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: p.line),
              ),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryShell(
    TalerPalette p, {
    required int blockedCount,
    required dynamic profile,
    required bool horizontal,
  }) {
    final blockedStat = _StatCell(
      label: 'Перехвачено пакетов',
      value: '$blockedCount',
      meta: 'Телеметрия MAX блокируется до сокета',
      dotColor: p.statusLive,
      largeNumber: true,
    );

    const opcodesStat = _StatCell(
      label: 'Жёстко заблокированные опкоды',
      value: '5',
      meta: 'LOG #5 · DEBUG #2 · BANNERS #302 · SUGGEST #300 · NOTIF #292',
      monoMeta: true,
      largeNumber: true,
    );

    final spoofStat = _StatCell(
      label: 'Активный профиль железа',
      value: '${profile.label}',
      meta: '${profile.deviceId}  ·  ${profile.osVersion}',
      monoMeta: true,
      largeNumber: false,
    );

    return TalerTableShell(
      child: horizontal
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 4, child: blockedStat),
                  VerticalDivider(width: 1, color: p.line),
                  const Expanded(flex: 5, child: opcodesStat),
                  VerticalDivider(width: 1, color: p.line),
                  Expanded(flex: 4, child: spoofStat),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                blockedStat,
                Divider(height: 1, color: p.line),
                opcodesStat,
                Divider(height: 1, color: p.line),
                spoofStat,
              ],
            ),
    );
  }

  Widget _buildPrivacyToggles(TalerPalette p, dynamic privacy) {
    return TalerTableShell(
      title: 'Фильтрация протокола и режим невидимости',
      child: Column(
        children: [
          _PrivacySwitchRow(
            title: 'Режим Призрак',
            subtitle: 'Отправляет interactive: false в LOGIN и PING',
            value: privacy.ghostModeOnline,
            onChanged: (v) {
              privacy.setGhostModeOnline(v);
              widget.client.session.sendPing();
            },
          ),
          Divider(height: 1, color: p.line),
          _PrivacySwitchRow(
            title: 'Скрывать набор текста',
            subtitle: 'Блокирует исходящие пакеты MSG_TYPING #65',
            value: privacy.hideTyping,
            onChanged: privacy.setHideTyping,
          ),
          Divider(height: 1, color: p.line),
          _PrivacySwitchRow(
            title: 'Anti-Read',
            subtitle: 'Блокирует отметки CHAT_MARK READ_MESSAGE #50',
            value: privacy.hideReadReceipts,
            onChanged: privacy.setHideReadReceipts,
          ),
          Divider(height: 1, color: p.line),
          _PrivacySwitchRow(
            title: 'Anti-Delete и история правок',
            subtitle: 'Сохраняет удалённые собеседником сообщения локально',
            value: privacy.antiDelete,
            onChanged: privacy.setAntiDelete,
          ),
          Divider(height: 1, color: p.line),
          _PrivacySwitchRow(
            title: 'Спуфинг устройства',
            subtitle: 'Подменяет модель, ОС, экран и Device ID при входе',
            value: privacy.spoofingEnabled,
            onChanged: privacy.setSpoofingEnabled,
          ),
        ],
      ),
    );
  }

  Widget _buildSpoofingShell(
    TalerPalette p,
    SpoofingService spoof,
    dynamic active,
  ) {
    final currentId = SpoofingService.presets.any((e) => e.id == active.presetId)
        ? active.presetId as String
        : SpoofingService.presets.first.id;

    return TalerTableShell(
      title: 'Профиль маскировки устройства',
      trailing: TalerTactileButton(
        label: 'Новый ID',
        icon: Icons.refresh_rounded,
        compact: true,
        onPressed: spoof.regenerateIdentifiers,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              key: ValueKey(currentId),
              initialValue: currentId,
              dropdownColor: p.bg3,
              style: TextStyle(fontSize: 13, color: p.fg),
              decoration: const InputDecoration(
                labelText: 'Пресет устройства',
                isDense: true,
              ),
              items: [
                for (final DevicePreset preset in SpoofingService.presets)
                  DropdownMenuItem(
                    value: preset.id,
                    child: Text('${preset.label} (${preset.deviceType})'),
                  ),
              ],
              onChanged: (id) {
                if (id == null) return;
                final preset = SpoofingService.presets.firstWhere(
                  (e) => e.id == id,
                );
                spoof.selectPreset(preset);
              },
            ),
          ),
          Divider(height: 1, color: p.line),
          _KvRow(label: 'Device ID', value: active.deviceId),
          Divider(height: 1, color: p.line),
          _KvRow(label: 'Instance UUID', value: active.instanceId),
          Divider(height: 1, color: p.line),
          _KvRow(label: 'ОС · Экран', value: '${active.osVersion} · ${active.screen}'),
          Divider(height: 1, color: p.line),
          _KvRow(label: 'Локаль · TZ', value: '${active.locale} · ${active.timezone}'),
          Divider(height: 1, color: p.line),
          _KvRow(label: 'User-Agent', value: active.userAgent),
        ],
      ),
    );
  }

  Widget _buildAuditShell(
    TalerPalette p,
    WireAuditLog audit,
    List<WireAuditEntry> filtered, {
    required bool isWide,
  }) {
    final filterPill = SizedBox(
      width: isWide ? 260 : double.infinity,
      child: TalerSlidingPillSwitch<_LogFilter>(
        value: _filter,
        height: 28,
        onChanged: (next) => setState(() => _filter = next),
        items: [
          TalerSegment(
            value: _LogFilter.all,
            label: 'Все',
            badge: '${audit.entries.length}',
          ),
          const TalerSegment(value: _LogFilter.blocked, label: 'Блок'),
          const TalerSegment(value: _LogFilter.allowed, label: 'Пропуск'),
        ],
      ),
    );

    return TalerTableShell(
      title: 'Инспектор трафика (Wire Audit)',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isWide) ...[
            filterPill,
            const SizedBox(width: 8),
          ],
          TalerTactileButton(
            label: 'Очистить',
            compact: true,
            onPressed: audit.entries.isEmpty ? null : audit.clear,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isWide)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: filterPill,
            ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sensors_off_outlined, size: 22, color: p.fg3),
                    const SizedBox(height: 8),
                    Text(
                      'Записей пока нет',
                      style: TextStyle(fontSize: 13, color: p.fg2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Нажмите «Тест блокировки» или откройте диалог',
                      style: TextStyle(fontSize: 12, color: p.fg3),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: p.line),
              itemBuilder: (context, index) {
                final entry = filtered[index];
                return _AuditRow(
                  entry: entry,
                  onTap: () => _showPayloadDialog(entry),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showPayloadDialog(WireAuditEntry entry) {
    final p = TalerTheme.paletteOf(context);
    String formatted;
    try {
      formatted = const JsonEncoder.withIndent('  ').convert(entry.payload);
    } catch (_) {
      formatted = entry.payload?.toString() ?? 'null';
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${entry.opcodeName} #${entry.opcode}',
          style: TalerTheme.monoStyle(
            size: 14,
            weight: FontWeight.w500,
            color: p.fg,
          ),
        ),
        content: SizedBox(
          width: 440,
          child: TalerTableShell(
            bodyPadding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: SelectableText(
                formatted,
                style: TalerTheme.monoStyle(size: 12, color: p.fg2),
              ),
            ),
          ),
        ),
        actions: [
          TalerTactileButton(
            label: 'Закрыть',
            compact: true,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final String meta;
  final Color? dotColor;
  final bool monoMeta;
  final bool largeNumber;

  const _StatCell({
    required this.label,
    required this.value,
    required this.meta,
    this.dotColor,
    this.monoMeta = false,
    required this.largeNumber,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (dotColor != null) ...[
                TalerStatusDot(color: dotColor!, size: 6),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.fg3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: largeNumber
                ? TalerTheme.tabularStyle(
                    size: 24,
                    weight: FontWeight.w500,
                    color: p.fg,
                  )
                : TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: p.fg,
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            meta,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: monoMeta
                ? TalerTheme.monoStyle(size: 11, color: p.fg2)
                : TextStyle(fontSize: 11.5, color: p.fg2),
          ),
        ],
      ),
    );
  }
}

class _PrivacySwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PrivacySwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: p.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: p.fg3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
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
    final p = TalerTheme.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: p.fg3),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TalerTheme.monoStyle(size: 12, color: p.fg2),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditRow extends StatefulWidget {
  final WireAuditEntry entry;
  final VoidCallback onTap;

  const _AuditRow({required this.entry, required this.onTap});

  @override
  State<_AuditRow> createState() => _AuditRowState();
}

class _AuditRowState extends State<_AuditRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final entry = widget.entry;
    final isOut = entry.direction == PacketDirection.outgoing;
    final statusColor = switch (entry.verdict) {
      AuditVerdict.blockedTelemetry => p.danger,
      AuditVerdict.blockedGhost => p.warning,
      AuditVerdict.allowed => p.statusLive,
    };
    final statusLabel = switch (entry.verdict) {
      AuditVerdict.blockedTelemetry => 'BLOCK',
      AuditVerdict.blockedGhost => 'GHOST',
      AuditVerdict.allowed => 'OK',
    };

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: _hovered ? p.surface : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              TalerStatusDot(color: statusColor, size: 6),
              const SizedBox(width: 8),
              Icon(
                isOut ? Icons.north_east_rounded : Icons.south_west_rounded,
                size: 14,
                color: p.fg3,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${entry.opcodeName} #${entry.opcode}',
                          style: TalerTheme.monoStyle(
                            size: 12,
                            weight: FontWeight.w500,
                            color: p.fg,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          statusLabel,
                          style: TalerTheme.monoStyle(
                            size: 10.5,
                            weight: FontWeight.w500,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.fg2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                DateFormat('HH:mm:ss').format(entry.timestamp),
                style: TalerTheme.monoStyle(size: 11.5, color: p.fg3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

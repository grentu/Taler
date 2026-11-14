import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/privacy/privacy_firewall.dart';
import '../../core/privacy/spoof_profile.dart';
import '../../core/privacy/spoofing_service.dart';
import '../theme/taler_theme.dart';
import '../icons/taler_icon.dart';

enum _LogFilter { all, blocked, allowed }

/// Экран фаервола приватности, подмены отпечатка и инспекции пакетов Wire Audit.
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

    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.client.privacySettings,
        widget.client.spoofingService,
        widget.client.auditLog,
      ]),
      builder: (context, _) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final isWide = screenWidth >= 820;
        final privacy = widget.client.privacySettings;
        final spoof = widget.client.spoofingService;
        final profile = spoof.activeProfile;
        final blockedCount = privacy.blockedPacketsCount;
        final allEntries = widget.client.auditLog.entries;
        final filteredEntries = allEntries.where((entry) {
          return switch (_filter) {
            _LogFilter.all => true,
            _LogFilter.blocked => entry.isBlocked,
            _LogFilter.allowed => !entry.isBlocked,
          };
        }).toList();

        return Container(
          color: p.settingsBg,
          child: Column(
            children: [
              // Верхняя панель 56px в стиле Telegram
              Container(
                color: p.bg2,
                child: SafeArea(
                  bottom: false,
                  top: !isWide,
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: p.bg2,
                      border: Border(bottom: BorderSide(color: p.line)),
                    ),
                    child: Row(
                      children: [
                        TelegramIconBadge(
                          icon: TalerIcons.shieldCheck,
                          color: p.statusLive,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Taler Shield',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                  color: p.fg,
                                ),
                              ),
                              Text(
                                'Активный фаервол телеметрии и подмена отпечатка',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: p.fg2),
                              ),
                            ],
                          ),
                        ),
                        if (isWide) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: p.statusLiveSurface,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Заблокировано: $blockedCount',
                              style: TalerTheme.tabularStyle(
                                size: 12,
                                weight: FontWeight.w600,
                                color: p.statusLive,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        TalerTactileButton(
                          label: isWide ? 'Тест перехвата' : 'Тест',
                          icon: TalerIcons.radar,
                          compact: true,
                          onPressed: () =>
                              widget.client.triggerTelemetryTestProbe(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Секции настроек Telegram-стиля
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSummaryCard(p, blockedCount, profile),
                          const SizedBox(height: 18),
                          _buildPrivacyTogglesCard(p, privacy),
                          const SizedBox(height: 18),
                          _buildSpoofingCard(p, profile),
                          const SizedBox(height: 18),
                          _buildAuditLogCard(
                            context,
                            p,
                            allEntries,
                            filteredEntries,
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard(
    TalerPalette p,
    int blockedCount,
    SpoofProfile profile,
  ) {
    return TalerTableShell(
      bodyPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 540;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryStat(
                  label: 'Перехвачено пакетов',
                  value: '$blockedCount',
                  valueColor: p.statusLive,
                  mono: false,
                ),
                Divider(height: 18, color: p.line),
                _SummaryStat(
                  label: 'Активный профиль',
                  value: profile.label,
                  valueColor: p.fg,
                  mono: false,
                ),
                Divider(height: 18, color: p.line),
                _SummaryStat(
                  label: 'Device ID',
                  value: profile.deviceId,
                  valueColor: p.accent,
                  mono: true,
                ),
              ],
            );
          }

          return IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _SummaryStat(
                    label: 'Перехвачено пакетов',
                    value: '$blockedCount',
                    valueColor: p.statusLive,
                    mono: false,
                  ),
                ),
                VerticalDivider(width: 28, thickness: 1, color: p.line),
                Expanded(
                  child: _SummaryStat(
                    label: 'Активный профиль',
                    value: profile.label,
                    valueColor: p.fg,
                    mono: false,
                  ),
                ),
                VerticalDivider(width: 28, thickness: 1, color: p.line),
                Expanded(
                  child: _SummaryStat(
                    label: 'Device ID',
                    value: profile.deviceId,
                    valueColor: p.accent,
                    mono: true,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPrivacyTogglesCard(TalerPalette p, dynamic privacy) {
    return TalerTableShell(
      title: 'Защита и невидимость',
      child: Column(
        children: [
          _PrivacySwitchRow(
            icon: TalerIcons.eyeOff,
            badgeColor: const Color(0xFF8E6CEF),
            title: 'Режим Призрака (Ghost Mode)',
            subtitle:
                'Скрывать статус «в сети» и отправлять inactive: true при пинге',
            value: privacy.ghostModeOnline as bool,
            onChanged: (v) {
              privacy.setGhostModeOnline(v);
              widget.client.session.sendPing();
            },
          ),
          Divider(height: 1, indent: 58, color: p.line),
          _PrivacySwitchRow(
            icon: TalerIcons.pencilOff,
            badgeColor: const Color(0xFF2AABEE),
            title: 'Скрыть индикатор набора текста',
            subtitle: 'Блокировать исходящий Opcode 65 (CHAT_TYPING)',
            value: privacy.hideTyping as bool,
            onChanged: privacy.setHideTyping,
          ),
          Divider(height: 1, indent: 58, color: p.line),
          _PrivacySwitchRow(
            icon: TalerIcons.checkCheck,
            badgeColor: const Color(0xFF26A69A),
            title: 'Скрыть прочтение сообщений',
            subtitle: 'Блокировать отправку READ-маркеров через Opcode 21',
            value: privacy.hideReadReceipts as bool,
            onChanged: privacy.setHideReadReceipts,
          ),
          Divider(height: 1, indent: 58, color: p.line),
          _PrivacySwitchRow(
            icon: TalerIcons.timerOff,
            badgeColor: const Color(0xFFF5A623),
            title: 'Anti-Delete (сохранять удалённые)',
            subtitle:
                'Оставлять сообщения собеседника в локальном кэше с меткой щита',
            value: privacy.antiDelete as bool,
            onChanged: privacy.setAntiDelete,
          ),
          Divider(height: 1, indent: 58, color: p.line),
          _PrivacySwitchRow(
            icon: TalerIcons.fingerprint,
            badgeColor: const Color(0xFF4ECC5E),
            title: 'Подмена отпечатка устройства',
            subtitle: 'Маскировать модель, ОС, экран и UUID в хендшейке Opcode 6',
            value: privacy.spoofingEnabled as bool,
            onChanged: privacy.setSpoofingEnabled,
          ),
        ],
      ),
    );
  }

  Widget _buildSpoofingCard(TalerPalette p, SpoofProfile profile) {
    return TalerTableShell(
      title: 'Маскировка устройства (Opcode 6)',
      trailing: TalerTactileButton(
        label: 'Новый ID',
        icon: TalerIcons.refresh,
        compact: true,
        onPressed: () => widget.client.spoofingService.regenerateIdentifiers(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in SpoofingService.presets)
                  _PresetChip(
                    preset: preset,
                    selected: preset.id == profile.presetId,
                    onTap: () =>
                        widget.client.spoofingService.selectPreset(preset),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: p.line),
          _SpecKeyValueRow(label: 'Пресет', value: profile.label),
          Divider(height: 1, indent: 14, color: p.line),
          _SpecKeyValueRow(label: 'Тип клиента', value: profile.deviceType),
          Divider(height: 1, indent: 14, color: p.line),
          _SpecKeyValueRow(label: 'Система', value: profile.osVersion),
          Divider(height: 1, indent: 14, color: p.line),
          _SpecKeyValueRow(label: 'Версия MAX', value: profile.appVersion),
          Divider(height: 1, indent: 14, color: p.line),
          _SpecKeyValueRow(label: 'Экран', value: profile.screen),
          Divider(height: 1, indent: 14, color: p.line),
          _SpecKeyValueRow(label: 'Локаль', value: profile.locale),
          Divider(height: 1, indent: 14, color: p.line),
          _SpecKeyValueRow(label: 'Часовой пояс', value: profile.timezone),
          Divider(height: 1, indent: 14, color: p.line),
          _SpecKeyValueRow(label: 'Device ID', value: profile.deviceId, mono: true),
        ],
      ),
    );
  }

  Widget _buildAuditLogCard(
    BuildContext context,
    TalerPalette p,
    List<WireAuditEntry> allEntries,
    List<WireAuditEntry> filteredEntries,
  ) {
    return TalerTableShell(
      title: 'Инспектор пакетов (Wire Audit)',
      trailing: TalerIconButton(
        icon: TalerIcons.listX,
        tooltip: 'Очистить журнал',
        size: 30,
        iconSize: 18,
        onPressed:
            allEntries.isEmpty ? null : () => widget.client.auditLog.clear(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TalerSlidingPillSwitch<_LogFilter>(
              value: _filter,
              height: 32,
              pillShape: true,
              onChanged: (next) => setState(() => _filter = next),
              items: const [
                TalerSegment(value: _LogFilter.all, label: 'Все'),
                TalerSegment(value: _LogFilter.blocked, label: 'Блок'),
                TalerSegment(value: _LogFilter.allowed, label: 'Пропуск'),
              ],
            ),
          ),
          Divider(height: 1, color: p.line),
          if (filteredEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
              child: Text(
                'Пока нет записанных пакетов. Откройте чат или нажмите «Тест перехвата».',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: p.fg2),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredEntries.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, indent: 14, color: p.line),
              itemBuilder: (context, index) {
                final entry = filteredEntries[index];
                return _AuditRow(
                  entry: entry,
                  onTap: () => _showPayloadDialog(context, p, entry),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showPayloadDialog(
    BuildContext context,
    TalerPalette p,
    WireAuditEntry entry,
  ) {
    String prettyPayload;
    if (entry.payload == null) {
      prettyPayload = '<empty payload>';
    } else {
      try {
        prettyPayload =
            const JsonEncoder.withIndent('  ').convert(entry.payload);
      } catch (_) {
        prettyPayload = entry.payload.toString();
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: entry.isBlocked ? p.dangerSurface : p.statusLiveSurface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                entry.isBlocked ? 'BLOCK' : 'PASS',
                style: TalerTheme.monoStyle(
                  size: 11,
                  weight: FontWeight.w600,
                  color: entry.isBlocked ? p.danger : p.statusLive,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${entry.opcodeName} (#${entry.opcode})',
                style: TalerTheme.monoStyle(
                  size: 14,
                  weight: FontWeight.w600,
                  color: p.fg,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${entry.direction == PacketDirection.outgoing ? 'OUTGOING' : 'INCOMING'} · seq=${entry.seq} · ${entry.summary}',
                  style: TextStyle(fontSize: 12.5, color: p.fg2),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.line),
                  ),
                  child: SelectableText(
                    prettyPayload,
                    style: TalerTheme.monoStyle(size: 11.5, color: p.fg),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: prettyPayload));
              Navigator.of(ctx).pop();
            },
            child: const Text('Копировать JSON'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool mono;

  const _SummaryStat({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.mono,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: p.fg2),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mono
              ? TalerTheme.monoStyle(
                  size: 13.5,
                  weight: FontWeight.w600,
                  color: valueColor,
                )
              : TalerTheme.tabularStyle(
                  size: 17,
                  weight: FontWeight.w600,
                  color: valueColor,
                ),
        ),
      ],
    );
  }
}

class _PrivacySwitchRow extends StatelessWidget {
  final TalerIconData icon;
  final Color badgeColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PrivacySwitchRow({
    required this.icon,
    required this.badgeColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            TelegramIconBadge(icon: icon, color: badgeColor, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: p.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: p.fg2, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Switch.adaptive(
              value: value,
              activeTrackColor: p.accent,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final DevicePreset preset;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: TalerTheme.fastDuration,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? p.accent.withValues(alpha: 0.16) : p.bg3,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? p.accent : p.line),
        ),
        child: Text(
          preset.label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? p.accent : p.fg,
          ),
        ),
      ),
    );
  }
}

class _SpecKeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _SpecKeyValueRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13.5, color: p.fg2),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono
                  ? TalerTheme.monoStyle(size: 12.5, color: p.fg)
                  : TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: p.fg,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  final WireAuditEntry entry;
  final VoidCallback onTap;

  const _AuditRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final timeStr = DateFormat('HH:mm:ss').format(entry.timestamp);
    final blocked = entry.isBlocked;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: blocked ? p.dangerSurface : p.statusLiveSurface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                blocked ? 'BLOCK' : 'PASS',
                style: TalerTheme.monoStyle(
                  size: 10.5,
                  weight: FontWeight.w600,
                  color: blocked ? p.danger : p.statusLive,
                ),
              ),
            ),
            const SizedBox(width: 10),
            TalerIcon(
              entry.direction == PacketDirection.outgoing
                  ? TalerIcons.arrowUpRight
                  : TalerIcons.arrowDownLeft,
              size: 15,
              color: p.fg2,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.opcodeName} (#${entry.opcode})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TalerTheme.monoStyle(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: p.fg,
                    ),
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
            const SizedBox(width: 10),
            Text(
              timeStr,
              style: TalerTheme.monoStyle(size: 11, color: p.fg3),
            ),
          ],
        ),
      ),
    );
  }
}

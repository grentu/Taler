import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/privacy/spoof_profile.dart';
import '../../core/privacy/spoofing_service.dart';
import '../icons/taler_icon.dart';
import '../theme/taler_theme.dart';

/// Экран настроек приватности и маскировки устройства (Taler Shield).
class PrivacyShieldScreen extends StatefulWidget {
  final TalerClient client;
  final double bottomInset;

  const PrivacyShieldScreen({
    super.key,
    required this.client,
    this.bottomInset = 12,
  });

  @override
  State<PrivacyShieldScreen> createState() => _PrivacyShieldScreenState();
}

class _PrivacyShieldScreenState extends State<PrivacyShieldScreen> {
  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.client.privacySettings,
        widget.client.spoofingService,
      ]),
      builder: (context, _) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final isWide = screenWidth >= 820;
        final privacy = widget.client.privacySettings;
        final spoof = widget.client.spoofingService;
        final profile = spoof.activeProfile;
        final activeProtections = [
          privacy.ghostModeOnline,
          privacy.hideTyping,
          privacy.hideReadReceipts,
          privacy.antiDelete,
          privacy.spoofingEnabled,
        ].where((v) => v).length;

        return Container(
          color: p.settingsBg,
          child: Column(
            children: [
              // Верхняя панель
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
                                'Приватность и маскировка устройства',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: p.fg2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Секции настроек приватности
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    widget.bottomInset + 12,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSummaryCard(
                            p,
                            activeProtections: activeProtections,
                            profile: profile,
                            spoofingEnabled: privacy.spoofingEnabled,
                          ),
                          const SizedBox(height: 18),
                          _buildPrivacyTogglesCard(p, privacy),
                          const SizedBox(height: 18),
                          _buildSpoofingCard(p, profile),
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
    TalerPalette p, {
    required int activeProtections,
    required SpoofProfile profile,
    required bool spoofingEnabled,
  }) {
    final activeLabel = activeProtections > 0
        ? 'Активно: $activeProtections из 5'
        : 'Выключено';
    final activeColor = activeProtections > 0 ? p.statusLive : p.fg2;
    final profileValue = spoofingEnabled ? profile.label : 'Реальное устройство';

    return TalerTableShell(
      bodyPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 460;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryStat(
                  label: 'Защита приватности',
                  value: activeLabel,
                  valueColor: activeColor,
                ),
                Divider(height: 18, color: p.line),
                _SummaryStat(
                  label: 'Профиль устройства',
                  value: profileValue,
                  valueColor: p.fg,
                ),
              ],
            );
          }

          return IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _SummaryStat(
                    label: 'Защита приватности',
                    value: activeLabel,
                    valueColor: activeColor,
                  ),
                ),
                VerticalDivider(width: 24, thickness: 1, color: p.line),
                Expanded(
                  child: _SummaryStat(
                    label: 'Профиль устройства',
                    value: profileValue,
                    valueColor: p.fg,
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
      title: 'Приватность',
      child: Column(
        children: [
          _PrivacySwitchRow(
            icon: TalerIcons.eyeOff,
            badgeColor: const Color(0xFF8E6CEF),
            title: 'Невидимый статус',
            subtitle: 'Не показывать другим пользователям, когда вы в сети',
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
            title: 'Скрыть набор текста',
            subtitle: 'Собеседники не увидят, что вы печатаете сообщение',
            value: privacy.hideTyping as bool,
            onChanged: privacy.setHideTyping,
          ),
          Divider(height: 1, indent: 58, color: p.line),
          _PrivacySwitchRow(
            icon: TalerIcons.checkCheck,
            badgeColor: const Color(0xFF26A69A),
            title: 'Не отправлять «Прочитано»',
            subtitle: 'Можно читать входящие сообщения без отметки о прочтении',
            value: privacy.hideReadReceipts as bool,
            onChanged: privacy.setHideReadReceipts,
          ),
          Divider(height: 1, indent: 58, color: p.line),
          _PrivacySwitchRow(
            icon: TalerIcons.timerOff,
            badgeColor: const Color(0xFFF5A623),
            title: 'Сохранять удалённые',
            subtitle: 'Оставлять сообщения, даже если собеседник удалит их у себя',
            value: privacy.antiDelete as bool,
            onChanged: privacy.setAntiDelete,
          ),
          Divider(height: 1, indent: 58, color: p.line),
          _PrivacySwitchRow(
            icon: TalerIcons.fingerprint,
            badgeColor: const Color(0xFF4ECC5E),
            title: 'Маскировка устройства',
            subtitle: 'Скрывать реальную модель устройства, систему и экран',
            value: privacy.spoofingEnabled as bool,
            onChanged: privacy.setSpoofingEnabled,
          ),
        ],
      ),
    );
  }

  Widget _buildSpoofingCard(TalerPalette p, SpoofProfile profile) {
    return TalerTableShell(
      title: 'Профиль устройства',
      trailing: TalerTactileButton(
        label: 'Обновить',
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
          _SpecKeyValueRow(label: 'Устройство', value: profile.label),
          Divider(height: 1, indent: 14, color: p.line),
          _SpecKeyValueRow(label: 'Система', value: profile.osVersion),
          Divider(height: 1, indent: 14, color: p.line),
          _SpecKeyValueRow(label: 'Версия клиента', value: profile.appVersion),
          Divider(height: 1, indent: 14, color: p.line),
          _SpecKeyValueRow(label: 'Экран', value: profile.screen),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _SummaryStat({
    required this.label,
    required this.value,
    required this.valueColor,
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
          style: TalerTheme.tabularStyle(
            size: 16,
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

  const _SpecKeyValueRow({
    required this.label,
    required this.value,
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
              style: TalerTheme.tabularStyle(
                size: 13.5,
                weight: FontWeight.w500,
                color: p.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

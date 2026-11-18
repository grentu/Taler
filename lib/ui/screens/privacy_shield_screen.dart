import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/privacy/spoof_profile.dart';
import '../../core/privacy/spoofing_service.dart';
import '../icons/taler_icon.dart';
import '../theme/taler_theme.dart';
import '../widgets/settings_components.dart';

/// Экран настроек приватности и маскировки устройства (Taler Shield)
/// в чёрном монохромном стиле `exteraless` с чёрными сквирклами и фейд-кромкой.
class PrivacyShieldScreen extends StatefulWidget {
  final TalerClient client;
  final double bottomInset;

  const PrivacyShieldScreen({
    super.key,
    required this.client,
    this.bottomInset = 16,
  });

  @override
  State<PrivacyShieldScreen> createState() => _PrivacyShieldScreenState();
}

class _PrivacyShieldScreenState extends State<PrivacyShieldScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  double _fadeFactor = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final next = (_scrollCtrl.offset / 32.0).clamp(0.0, 1.0);
    if ((next - _fadeFactor).abs() > 0.02 && mounted) {
      setState(() => _fadeFactor = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.client.privacySettings,
        widget.client.spoofingService,
        widget.client.appPreferences,
      ]),
      builder: (context, _) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final isWide = screenWidth >= 820;
        final statusTop = isWide ? 0.0 : MediaQuery.paddingOf(context).top;
        final privacy = widget.client.privacySettings;
        final spoof = widget.client.spoofingService;
        final profile = spoof.activeProfile;
        final powerSaving = widget.client.appPreferences.powerSavingMode;

        return ColoredBox(
          color: p.settingsBg,
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  padding: EdgeInsets.fromLTRB(
                    12,
                    statusTop + 56 + 8,
                    12,
                    widget.bottomInset + 18,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TalerSettingsGroup(
                            title: 'Приватность',
                            children: [
                              TalerSettingsTile(
                                icon: TalerIcons.ghost,
                                title: 'Невидимый статус',
                                subtitle: 'Скрыть статус «в сети» от собеседников',
                                trailing: Switch(
                                  value: privacy.ghostModeOnline,
                                  onChanged: (v) {
                                    unawaited(privacy.setGhostModeOnline(v));
                                    widget.client.session.sendPing();
                                  },
                                ),
                                onTap: () {
                                  final v = !privacy.ghostModeOnline;
                                  unawaited(privacy.setGhostModeOnline(v));
                                  widget.client.session.sendPing();
                                },
                              ),
                              TalerSettingsTile(
                                icon: TalerIcons.pencilOff,
                                title: 'Скрыть набор текста',
                                subtitle: 'Не показывать индикатор «печатает»',
                                trailing: Switch(
                                  value: privacy.hideTyping,
                                  onChanged: (v) => unawaited(privacy.setHideTyping(v)),
                                ),
                                onTap: () => unawaited(privacy.setHideTyping(!privacy.hideTyping)),
                              ),
                              TalerSettingsTile(
                                icon: TalerIcons.checkCheck,
                                title: 'Не отправлять «Прочитано»',
                                subtitle: 'Читать сообщения без отметки о прочтении',
                                trailing: Switch(
                                  value: privacy.hideReadReceipts,
                                  onChanged: (v) => unawaited(privacy.setHideReadReceipts(v)),
                                ),
                                onTap: () => unawaited(
                                  privacy.setHideReadReceipts(!privacy.hideReadReceipts),
                                ),
                              ),
                              TalerSettingsTile(
                                icon: TalerIcons.timerOff,
                                title: 'Сохранять удалённые',
                                subtitle: 'Не удалять сообщения, стёртые собеседником',
                                trailing: Switch(
                                  value: privacy.antiDelete,
                                  onChanged: (v) => unawaited(privacy.setAntiDelete(v)),
                                ),
                                onTap: () => unawaited(privacy.setAntiDelete(!privacy.antiDelete)),
                              ),
                              TalerSettingsTile(
                                icon: TalerIcons.fingerprint,
                                title: 'Маскировка устройства',
                                subtitle: 'Подменять модель устройства и параметры экрана',
                                trailing: Switch(
                                  value: privacy.spoofingEnabled,
                                  onChanged: (v) => unawaited(privacy.setSpoofingEnabled(v)),
                                ),
                                onTap: () => unawaited(
                                  privacy.setSpoofingEnabled(!privacy.spoofingEnabled),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildSpoofingGroup(p, profile),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (!isWide)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: TalerBottomFadeOverlay(
                    height: 72,
                    backgroundColor: p.settingsBg,
                  ),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: TalerTopFadeOverlay(
                  height: statusTop + 56 + 26,
                  backgroundColor: p.settingsBg,
                  factor: isWide ? 1.0 : _fadeFactor.clamp(0.75, 1.0),
                  powerSaving: powerSaving,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  top: !isWide,
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const TalerSettingsBadge(icon: TalerIcons.settingsGram),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Taler Shield',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              color: p.fg,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildSpoofingGroup(TalerPalette p, SpoofProfile profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Профиль устройства',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: p.accent,
                  ),
                ),
              ),
              TalerIconButton(
                icon: TalerIcons.refresh,
                tooltip: 'Обновить',
                size: 32,
                iconSize: 17,
                color: p.accent,
                onPressed: () => widget.client.spoofingService.regenerateIdentifiers(),
              ),
            ],
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.isDark ? const Color(0xFF121215) : p.surface,
            borderRadius: BorderRadius.circular(18),
            border: p.isDark ? null : Border.all(color: p.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in SpoofingService.presets)
                      _PresetChip(
                        preset: preset,
                        selected: preset.id == profile.presetId,
                        onTap: () => widget.client.spoofingService.selectPreset(preset),
                      ),
                  ],
                ),
              ),
              _SpecKeyValueRow(label: 'Устройство', value: profile.label),
              _SpecKeyValueRow(label: 'Система', value: profile.osVersion),
              _SpecKeyValueRow(label: 'Версия клиента', value: profile.appVersion),
              _SpecKeyValueRow(label: 'Экран', value: profile.screen),
            ],
          ),
        ),
      ],
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
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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
      padding: const EdgeInsets.fromLTRB(18, 10, 20, 10),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14.5, color: p.fg2),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TalerTheme.tabularStyle(
                size: 14.5,
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

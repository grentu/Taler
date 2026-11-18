import 'dart:async';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/storage/taler_models.dart';
import '../../core/transport/taler_session.dart';
import '../../core/version.dart';
import '../icons/taler_icon.dart';
import '../theme/chat_tokens.dart';
import '../theme/taler_theme.dart';
import '../widgets/settings_components.dart';

/// Экран профиля пользователя в чёрном стиле `exteraless`:
/// шапка с аватаром, сквирклы настроек профиля, активные сессии и верхний фейд-эффект.
class ProfileSettingsScreen extends StatefulWidget {
  final TalerClient client;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback? onOpenSettings;
  final double bottomInset;

  const ProfileSettingsScreen({
    super.key,
    required this.client,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.onOpenSettings,
    this.bottomInset = 16,
  });

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  double _fadeFactor = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.client.fetchActiveSessions();
    });
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
    final next = ((_scrollCtrl.offset - 24.0) / 88.0).clamp(0.0, 1.0);
    if ((next - _fadeFactor).abs() > 0.02 && mounted) {
      setState(() => _fadeFactor = next);
    }
  }

  Future<void> _editNameDialog() async {
    final user = widget.client.currentUser;
    if (user == null) return;

    final firstCtrl = TextEditingController(text: user.firstName);
    final lastCtrl = TextEditingController(text: user.lastName ?? '');
    final p = TalerTheme.paletteOf(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Изменить имя',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.fg),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstCtrl,
              autofocus: true,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Имя'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lastCtrl,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => Navigator.of(ctx).pop(true),
              decoration: const InputDecoration(labelText: 'Фамилия'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    final first = firstCtrl.text.trim();
    final last = lastCtrl.text.trim();
    firstCtrl.dispose();
    lastCtrl.dispose();

    if (confirmed == true && first.isNotEmpty) {
      await widget.client.updateProfileName(first, last.isEmpty ? null : last);
    }
  }

  String _formatPhone(String? raw) {
    final parsed = raw != null ? int.tryParse(raw.replaceAll(RegExp(r'\D'), '')) : null;
    if (parsed != null && parsed != 0) return ChatTokens.phone(parsed);
    return raw?.isNotEmpty == true ? raw! : 'Демо-аккаунт Taler';
  }

  void _openMyProfileSheet(TalerUserProfile? user) {
    final p = TalerTheme.paletteOf(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: p.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  'Мой профиль',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: p.fg),
                ),
              ),
              const SizedBox(height: 14),
              TalerSettingsGroup(
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.settingsAccount,
                    title: user?.fullName ?? 'Профиль Taler',
                    subtitle: 'Отображаемое имя',
                    trailing: TalerIconButton(
                      icon: TalerIcons.pencil,
                      tooltip: 'Изменить имя',
                      color: p.accent,
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _editNameDialog();
                      },
                    ),
                  ),
                  TalerSettingsTile(
                    icon: TalerIcons.phone,
                    title: _formatPhone(user?.phone),
                    subtitle: 'Телефон привязки MAX',
                  ),
                  if (user != null)
                    TalerSettingsTile(
                      icon: TalerIcons.qrCode,
                      title: 'ID: ${user.id}',
                      subtitle: 'Нажмите, чтобы скопировать',
                      onTap: () {
                        Navigator.of(ctx).pop();
                        Clipboard.setData(ClipboardData(text: '${user.id}'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('ID ${user.id} скопирован')),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.client, widget.client.appPreferences]),
      builder: (context, _) {
        final isWide = MediaQuery.sizeOf(context).width >= 820;
        final statusTop = isWide ? 0.0 : MediaQuery.paddingOf(context).top;
        final user = widget.client.currentUser;
        final sessions = widget.client.activeSessions;
        final sessionsText = sessions.isEmpty ? '1' : '${sessions.length}';
        final hasOthers = sessions.any((s) => !s.current);
        final powerSaving = widget.client.appPreferences.powerSavingMode;
        final scrollTopPad = isWide ? 24.0 : statusTop + 18.0;

        return ColoredBox(
          color: p.settingsBg,
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  padding: EdgeInsets.fromLTRB(
                    12,
                    scrollTopPad,
                    12,
                    widget.bottomInset + 18,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildProfileHero(p, user),
                          const SizedBox(height: 16),
                          TalerSettingsGroup(
                            children: [
                              TalerSettingsTile(
                                icon: TalerIcons.settingsAccount,
                                title: 'Мой профиль',
                                onTap: () => _openMyProfileSheet(user),
                              ),
                              if (widget.onOpenSettings != null)
                                TalerSettingsTile(
                                  icon: TalerIcons.settingsGram,
                                  title: 'Настройки',
                                  onTap: widget.onOpenSettings,
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TalerSettingsGroup(
                            title: 'Активные сессии',
                            accentTitle: true,
                            children: [
                              if (sessions.isEmpty)
                                TalerSettingsTile(
                                  icon: TalerIcons.settingsDevices,
                                  title: 'Текущая сессия',
                                  subtitle: widget.client.spoofingService.activeProfile.label,
                                  valueText: sessionsText,
                                )
                              else
                                for (final s in sessions) _buildSessionTile(s),
                              if (hasOthers)
                                TalerSettingsTile(
                                  icon: TalerIcons.trash,
                                  iconColor: p.danger,
                                  title: 'Завершить другие сессии',
                                  titleColor: p.danger,
                                  onTap: () => unawaited(widget.client.terminateOtherSessions()),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TalerSettingsGroup(
                            children: [
                              TalerSettingsTile(
                                icon: TalerIcons.logOut,
                                iconColor: p.danger,
                                title: 'Выйти',
                                titleColor: p.danger,
                                onTap: () => unawaited(widget.client.logout()),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Center(
                            child: Text(
                              kTalerVersionLabel,
                              style: TextStyle(fontSize: 13, color: p.fg3),
                            ),
                          ),
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
                  height: statusTop + 52 + 28,
                  backgroundColor: p.settingsBg,
                  factor: isWide ? 1.0 : _fadeFactor,
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
                  child: SizedBox(
                    height: 52,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          const SizedBox(width: 6),
                          Expanded(
                            child: Opacity(
                              opacity: isWide ? 1.0 : _fadeFactor,
                              child: Text(
                                user?.fullName ?? 'Профиль',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                  color: p.fg,
                                ),
                              ),
                            ),
                          ),
                          TalerIconButton(
                            icon: TalerIcons.pencil,
                            tooltip: 'Изменить имя',
                            size: 42,
                            iconSize: 20,
                            color: p.accent,
                            onPressed: _editNameDialog,
                          ),
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

  Widget _buildProfileHero(TalerPalette p, TalerUserProfile? user) {
    final isDemo = widget.client.isDemoMode;
    final online = isDemo || widget.client.connectionState == TalerConnectionState.online;
    final hasPhone = user?.phone != null && user!.phone!.trim().isNotEmpty;
    final subParts = <String>[
      if (hasPhone) _formatPhone(user.phone),
      if (isDemo) 'Демо-режим' else if (online) 'В сети' else 'Синхронизация',
    ];

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            TalerAvatar(
              seedId: user?.id ?? 0,
              initials: user?.initials ?? 'T',
              imageUrl: user?.avatarUrl,
              size: 90,
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: GestureDetector(
                onTap: () => _openMyProfileSheet(user),
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.settingsBg, width: 2.5),
                  ),
                  child: const TalerIcon(
                    TalerIcons.camera,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            user?.fullName ?? 'Пользователь Taler',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: p.fg,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subParts.join(' • '),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            color: online ? p.accent : p.fg3,
          ),
        ),
      ],
    );
  }

  Widget _buildSessionTile(TalerActiveSession s) {
    final lower = s.client.toLowerCase();
    final icon = lower.contains('android') || lower.contains('ios')
        ? TalerIcons.smartphone
        : lower.contains('windows') || lower.contains('desktop')
            ? TalerIcons.settingsDevices
            : TalerIcons.settingsLanguage;
    final timeStr = s.time > 0
        ? DateFormat('dd.MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(s.time))
        : null;
    final sub = [
      if (s.location.isNotEmpty) s.location,
      if (s.info.isNotEmpty) s.info,
      ?timeStr,
    ].join(' • ');

    return TalerSettingsTile(
      icon: icon,
      title: s.client,
      subtitle: sub.isEmpty ? null : sub,
      valueText: s.current ? 'Текущая' : null,
    );
  }
}

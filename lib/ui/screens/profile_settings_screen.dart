import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/storage/taler_models.dart';
import '../../core/transport/taler_session.dart';
import '../../core/version.dart';
import '../icons/taler_icon.dart';
import '../theme/chat_tokens.dart';
import '../theme/taler_theme.dart';
import '../widgets/settings_components.dart';
import 'settings_screen.dart';

/// Экран профиля пользователя в чёрном стиле `exteraless`:
/// шапка с аватаром, данные аккаунта, быстрые переходы и верхний фейд-эффект.
class ProfileSettingsScreen extends StatefulWidget {
  final TalerClient client;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenShield;
  final double bottomInset;

  const ProfileSettingsScreen({
    super.key,
    required this.client,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.onOpenSettings,
    this.onOpenShield,
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
    await showTalerEditNameSheet(
      context,
      initialFirstName: user.firstName,
      initialLastName: user.lastName,
      onSave: (first, last) => widget.client.updateProfileName(first, last),
    );
  }

  String _formatPhone(String? raw) {
    final parsed = raw != null ? int.tryParse(raw.replaceAll(RegExp(r'\D'), '')) : null;
    if (parsed != null && parsed != 0) return ChatTokens.phone(parsed);
    return raw?.isNotEmpty == true ? raw! : 'Демо-аккаунт Taler';
  }

  Future<void> _copyText(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _openMyProfileSheet(TalerUserProfile? user) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final p = TalerTheme.paletteOf(ctx);
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return Container(
          decoration: BoxDecoration(
            color: p.settingsBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(top: BorderSide(color: p.line2)),
          ),
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: p.fg.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Center(
                child: TalerAvatar(
                  seedId: user?.id ?? 0,
                  initials: user?.initials ?? 'T',
                  imageUrl: user?.avatarUrl,
                  size: 64,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                user?.fullName ?? 'Профиль Taler',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: p.fg),
              ),
              const SizedBox(height: 2),
              Text(
                _formatPhone(user?.phone),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: p.fg3),
              ),
              const SizedBox(height: 16),
              TalerSettingsGroup(
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.pencil,
                    title: 'Изменить имя',
                    subtitle: user?.fullName ?? 'Профиль Taler',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_editNameDialog());
                    },
                  ),
                  if (user != null)
                    TalerSettingsTile(
                      icon: TalerIcons.qrCode,
                      title: 'ID: ${user.id}',
                      subtitle: 'Нажмите, чтобы скопировать',
                      onTap: () {
                        Navigator.of(ctx).pop();
                        unawaited(_copyText('${user.id}', 'ID ${user.id} скопирован'));
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showTalerConfirmSheet(
      context,
      icon: TalerIcons.logOut,
      title: 'Выйти из аккаунта?',
      message: 'Текущая сессия и локальная история чатов на этом устройстве будут очищены.',
      confirmLabel: 'Выйти',
    );
    if (confirmed) {
      await widget.client.logout();
    }
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
        final powerSaving = widget.client.appPreferences.powerSavingMode;
        final scrollTopPad = isWide ? 24.0 : statusTop + 18.0;
        final bio = user?.description?.trim() ?? '';
        final hasPhone = user?.phone != null && user!.phone!.trim().isNotEmpty;

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
                          const SizedBox(height: 18),
                          TalerSettingsGroup(
                            title: 'Аккаунт',
                            accentTitle: true,
                            children: [
                              TalerSettingsTile(
                                icon: TalerIcons.phone,
                                title: hasPhone
                                    ? _formatPhone(user.phone)
                                    : 'Демо-аккаунт Taler',
                                subtitle: 'Телефон',
                                onTap: hasPhone
                                    ? () => unawaited(
                                          _copyText(
                                            _formatPhone(user.phone),
                                            'Номер телефона скопирован',
                                          ),
                                        )
                                    : null,
                              ),
                              if (user != null)
                                TalerSettingsTile(
                                  icon: TalerIcons.qrCode,
                                  title: 'ID: ${user.id}',
                                  subtitle: 'Идентификатор MAX',
                                  onTap: () => unawaited(
                                    _copyText('${user.id}', 'ID ${user.id} скопирован'),
                                  ),
                                ),
                              if (bio.isNotEmpty)
                                TalerSettingsTile(
                                  icon: TalerIcons.info,
                                  title: bio,
                                  subtitle: 'О себе',
                                ),
                              TalerSettingsTile(
                                icon: TalerIcons.pencil,
                                title: 'Изменить имя',
                                onTap: () => unawaited(_editNameDialog()),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TalerSettingsGroup(
                            children: [
                              TalerSettingsTile(
                                icon: TalerIcons.smartphone,
                                title: 'Устройства',
                                valueText: sessionsText,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => TalerDevicesPage(
                                      client: widget.client,
                                    ),
                                  ),
                                ),
                              ),
                              TalerSettingsTile(
                                icon: TalerIcons.settingsChat,
                                title: 'Оформление чатов',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => TalerChatAppearancePage(
                                      client: widget.client,
                                      themeMode: widget.themeMode,
                                      onThemeModeChanged: widget.onThemeModeChanged,
                                    ),
                                  ),
                                ),
                              ),
                              TalerSettingsTile(
                                icon: TalerIcons.settingsData,
                                title: 'Данные и память',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => TalerDataStoragePage(
                                      client: widget.client,
                                    ),
                                  ),
                                ),
                              ),
                              if (widget.onOpenShield != null)
                                TalerSettingsTile(
                                  icon: TalerIcons.settingsGram,
                                  title: 'Защита и приватность',
                                  onTap: widget.onOpenShield,
                                ),
                              if (widget.onOpenSettings != null)
                                TalerSettingsTile(
                                  icon: TalerIcons.settings,
                                  title: 'Настройки',
                                  onTap: widget.onOpenSettings,
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
                                onTap: () => unawaited(_confirmLogout()),
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
            GestureDetector(
              onTap: () => _openMyProfileSheet(user),
              child: TalerAvatar(
                seedId: user?.id ?? 0,
                initials: user?.initials ?? 'T',
                imageUrl: user?.avatarUrl,
                size: 92,
              ),
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
}

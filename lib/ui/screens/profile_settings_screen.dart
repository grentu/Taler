import 'dart:async';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/storage/taler_models.dart';
import '../../core/transport/taler_session.dart';
import '../icons/taler_icon.dart';
import '../theme/chat_tokens.dart';
import '../theme/taler_theme.dart';
import '../widgets/settings_components.dart';

/// Экран профиля пользователя: аватар, имя, данные аккаунта и активные сессии.
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
  bool _showBarTitle = false;

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
    final next = _scrollCtrl.hasClients && _scrollCtrl.offset > 68;
    if (next != _showBarTitle && mounted) {
      setState(() => _showBarTitle = next);
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
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: p.fg,
          ),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
              Text(
                'Мой профиль',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: p.fg),
              ),
              const SizedBox(height: 14),
              TalerSettingsGroup(
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.user,
                    badgeColor: p.accent,
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
                    showChevron: false,
                  ),
                  TalerSettingsTile(
                    icon: TalerIcons.phone,
                    badgeColor: const Color(0xFF22C55E),
                    title: _formatPhone(user?.phone),
                    subtitle: 'Телефон привязки MAX',
                    showChevron: false,
                  ),
                  if (user != null)
                    TalerSettingsTile(
                      icon: TalerIcons.qrCode,
                      badgeColor: const Color(0xFF8B5CF6),
                      title: 'ID: ${user.id}',
                      subtitle: 'Нажмите, чтобы скопировать идентификатор',
                      showChevron: false,
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
      listenable: widget.client,
      builder: (context, _) {
        final isWide = MediaQuery.sizeOf(context).width >= 820;
        final user = widget.client.currentUser;
        final sessions = widget.client.activeSessions;
        final sessionsText = sessions.isEmpty ? '1' : '${sessions.length}';
        final hasOthers = sessions.any((s) => !s.current);

        return Container(
          color: p.settingsBg,
          child: Column(
            children: [
              _buildTopBar(p, isWide, user),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    widget.bottomInset + 16,
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
                            children: [
                              TalerSettingsTile(
                                icon: TalerIcons.user,
                                badgeColor: const Color(0xFF2B87F3),
                                title: 'Мой профиль',
                                subtitle: _formatPhone(user?.phone),
                                onTap: () => _openMyProfileSheet(user),
                              ),
                              if (widget.onOpenSettings != null)
                                TalerSettingsTile(
                                  icon: TalerIcons.settings,
                                  badgeColor: const Color(0xFF6366F1),
                                  title: 'Настройки клиента',
                                  subtitle: 'Оформление чатов, память, уведомления',
                                  onTap: widget.onOpenSettings,
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TalerSettingsGroup(
                            title: 'Активные сессии',
                            accentTitle: true,
                            children: [
                              if (sessions.isEmpty)
                                TalerSettingsTile(
                                  icon: TalerIcons.monitor,
                                  badgeColor: p.statusLive,
                                  title: 'Текущая сессия',
                                  subtitle: widget.client.spoofingService.activeProfile.label,
                                  valueText: sessionsText,
                                  showChevron: false,
                                )
                              else
                                for (final s in sessions) _buildSessionTile(p, s),
                              if (hasOthers)
                                TalerSettingsTile(
                                  icon: TalerIcons.trash,
                                  badgeColor: p.danger,
                                  title: 'Завершить другие сессии',
                                  titleColor: p.danger,
                                  showChevron: false,
                                  onTap: () => unawaited(widget.client.terminateOtherSessions()),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TalerSettingsGroup(
                            children: [
                              TalerSettingsTile(
                                icon: TalerIcons.logOut,
                                badgeColor: p.danger,
                                title: 'Выйти',
                                titleColor: p.danger,
                                showChevron: false,
                                onTap: () => unawaited(widget.client.logout()),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: Text(
                              'Taler 1.2.7 (13)',
                              style: TextStyle(fontSize: 13, color: p.fg3),
                            ),
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

  Widget _buildTopBar(TalerPalette p, bool isWide, TalerUserProfile? user) {
    return Container(
      color: isWide ? p.bg2 : p.settingsBg,
      child: SafeArea(
        bottom: false,
        top: !isWide,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isWide ? p.bg2 : p.settingsBg,
            border: isWide ? Border(bottom: BorderSide(color: p.line)) : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: isWide || _showBarTitle ? 1.0 : 0.0,
                  child: Text(
                    user?.fullName ?? 'Профиль',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: p.fg,
                    ),
                  ),
                ),
              ),
              TalerIconButton(
                icon: TalerIcons.pencil,
                tooltip: 'Изменить имя',
                size: 40,
                iconSize: 19,
                color: p.accent,
                onPressed: _editNameDialog,
              ),
            ],
          ),
        ),
      ),
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
              size: 92,
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
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            user?.fullName ?? 'Пользователь Taler',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: p.fg,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subParts.join(' • '),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: online ? p.accent : p.fg2,
          ),
        ),
      ],
    );
  }

  Widget _buildSessionTile(TalerPalette p, TalerActiveSession s) {
    final lower = s.client.toLowerCase();
    final icon = lower.contains('android') || lower.contains('ios')
        ? TalerIcons.smartphone
        : lower.contains('windows') || lower.contains('desktop')
            ? TalerIcons.monitor
            : TalerIcons.globe;
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
      badgeColor: s.current ? p.statusLive : const Color(0xFF3B82F6),
      title: s.client,
      subtitle: sub.isEmpty ? null : sub,
      valueText: s.current ? 'Текущая' : null,
      showChevron: false,
    );
  }
}

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/storage/taler_models.dart';
import '../theme/taler_theme.dart';
import '../widgets/taler_logo.dart';
import '../icons/taler_icon.dart';

/// Экран профиля, оформления, активных сессий и информации о клиенте Taler.
class ProfileSettingsScreen extends StatefulWidget {
  final TalerClient client;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const ProfileSettingsScreen({
    super.key,
    required this.client,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  @override
  void initState() {
    super.initState();
    widget.client.fetchActiveSessions();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Изменить имя',
          style: TextStyle(
            fontSize: 16.5,
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
              decoration: const InputDecoration(labelText: 'Имя'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lastCtrl,
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

    if (confirmed == true && firstCtrl.text.trim().isNotEmpty) {
      await widget.client.updateProfileName(
        firstCtrl.text.trim(),
        lastCtrl.text.trim().isEmpty ? null : lastCtrl.text.trim(),
      );
    }

    firstCtrl.dispose();
    lastCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);

    return ListenableBuilder(
      listenable: widget.client,
      builder: (context, _) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final isWide = screenWidth >= 820;
        final user = widget.client.currentUser;
        final sessions = widget.client.activeSessions;
        final isDemo = widget.client.isDemoMode;

        return Container(
          color: p.settingsBg,
          child: Column(
            children: [
              // Верхняя панель 56px в стиле Telegram Settings
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
                          icon: TalerIcons.settings,
                          color: p.accent,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Настройки',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: p.fg,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: p.bg3,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: p.line),
                          ),
                          child: Text(
                            'v1.2.0',
                            style: TalerTheme.monoStyle(
                              size: 11.5,
                              weight: FontWeight.w600,
                              color: p.fg2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Секции настроек
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildProfileHeroCard(p, user, isDemo),
                          const SizedBox(height: 18),
                          _buildAppearanceCard(p),
                          const SizedBox(height: 18),
                          _buildSessionsCard(p, sessions),
                          const SizedBox(height: 18),
                          _buildAboutAndLogoutCard(p),
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

  Widget _buildProfileHeroCard(
    TalerPalette p,
    TalerUserProfile? user,
    bool isDemo,
  ) {
    final name = user?.fullName ?? 'Пользователь Taler';
    final phoneText = user?.phone != null && user!.phone!.isNotEmpty
        ? user.phone!
        : 'Телефон скрыт';

    return TalerTableShell(
      bodyPadding: const EdgeInsets.all(16),
      child: Row(
        children: [
          TalerAvatar(
            seedId: user?.id ?? 1,
            initials: user?.initials ?? 'T',
            imageUrl: user?.avatarUrl,
            size: 64,
            isOnline: true,
            onlineBorderColor: p.bg2,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w600,
                          color: p.fg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDemo
                            ? p.accentMuted
                            : p.statusLiveSurface,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isDemo ? 'Демо' : 'Live',
                        style: TalerTheme.monoStyle(
                          size: 10.5,
                          weight: FontWeight.w600,
                          color: isDemo ? p.accent : p.statusLive,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$phoneText · ID ${user?.id ?? '—'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TalerTheme.tabularStyle(size: 13, color: p.fg2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TalerTactileButton(
            label: 'Изменить',
            icon: TalerIcons.pencil,
            compact: true,
            onPressed: user == null ? null : _editNameDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceCard(TalerPalette p) {
    return TalerTableShell(
      title: 'Оформление',
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TelegramIconBadge(
                  icon: TalerIcons.palette,
                  color: p.accent,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Тема интерфейса',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: p.fg,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Тёмная тема Obsidian или светлая Alabaster',
                        style: TextStyle(fontSize: 12, color: p.fg2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TalerSlidingPillSwitch<ThemeMode>(
              value: widget.themeMode,
              height: 34,
              pillShape: true,
              onChanged: widget.onThemeModeChanged,
              items: const [
                TalerSegment(
                  value: ThemeMode.dark,
                  label: 'Ночная',
                  icon: TalerIcons.moon,
                ),
                TalerSegment(
                  value: ThemeMode.light,
                  label: 'Светлая',
                  icon: TalerIcons.sun,
                ),
                TalerSegment(
                  value: ThemeMode.system,
                  label: 'Система',
                  icon: TalerIcons.sunMoon,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionsCard(
    TalerPalette p,
    List<TalerActiveSession> sessions,
  ) {
    final hasOtherSessions = sessions.any((s) => !s.current);

    return TalerTableShell(
      title: 'Активные сессии (Opcode 96)',
      trailing: TalerIconButton(
        icon: TalerIcons.refresh,
        tooltip: 'Обновить сессии',
        size: 30,
        iconSize: 18,
        onPressed: () => widget.client.fetchActiveSessions(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Список сессий пуст или загружается...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: p.fg2),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sessions.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, indent: 56, color: p.line),
              itemBuilder: (context, index) {
                final s = sessions[index];
                final formattedTime = s.time > 0
                    ? DateFormat('dd.MM.yyyy HH:mm').format(
                        DateTime.fromMillisecondsSinceEpoch(s.time),
                      )
                    : '';
                final metaParts = [
                  if (s.location.isNotEmpty) s.location,
                  if (s.info.isNotEmpty) s.info,
                  if (formattedTime.isNotEmpty) formattedTime,
                ];

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      TelegramIconBadge(
                        icon: s.current
                            ? TalerIcons.shieldCheck
                            : TalerIcons.devices,
                        color: s.current ? p.statusLive : p.accent,
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    s.client,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: p.fg,
                                    ),
                                  ),
                                ),
                                if (s.current) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: p.statusLiveSurface,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'Текущая',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: p.statusLive,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (metaParts.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                metaParts.join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: p.fg2),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (hasOtherSessions) ...[
            Divider(height: 1, color: p.line),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TalerTactileButton(
                label: 'Завершить все остальные сессии',
                icon: TalerIcons.devicesOther,
                variant: TalerButtonVariant.danger,
                onPressed: () => widget.client.terminateOtherSessions(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAboutAndLogoutCard(TalerPalette p) {
    return TalerTableShell(
      title: 'О клиенте Taler',
      bodyPadding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const TalerLogo(size: 38, showShieldBadge: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Taler v1.2.0 — открытый клиент мессенджера MAX с нулевой телеметрией',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: p.fg,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'github.com/grentu/Taler · протокол KometTeam/Komet',
                      style: TalerTheme.monoStyle(size: 11.5, color: p.fg2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TalerTactileButton(
            label: widget.client.isDemoMode
                ? 'Выйти из демо-режима'
                : 'Выйти из аккаунта',
            icon: TalerIcons.logOut,
            variant: TalerButtonVariant.danger,
            onPressed: () => widget.client.logout(),
          ),
        ],
      ),
    );
  }
}

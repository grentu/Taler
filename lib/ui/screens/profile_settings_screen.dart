import 'dart:ui' as ui;

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
  final double bottomInset;

  const ProfileSettingsScreen({
    super.key,
    required this.client,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.bottomInset = 12,
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
    final next = _scrollCtrl.hasClients && _scrollCtrl.offset > 72;
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

        if (!isWide) {
          final topPad = MediaQuery.paddingOf(context).top;
          return Container(
            color: p.settingsBg,
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      topPad + 16,
                      16,
                      widget.bottomInset + 16,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildMobileProfileHero(p, user, isDemo),
                            const SizedBox(height: 18),
                            _buildMyProfileTile(p, user),
                            const SizedBox(height: 18),
                            _buildAppearanceCard(p),
                            const SizedBox(height: 18),
                            _buildSessionsCard(p, sessions),
                            const SizedBox(height: 18),
                            _buildAboutCard(p),
                            const SizedBox(height: 14),
                            _buildLogoutCard(p),
                            const SizedBox(height: 16),
                            Text(
                              'Taler · v1.2.5',
                              textAlign: TextAlign.center,
                              style: TalerTheme.tabularStyle(
                                size: 12,
                                color: p.fg3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Builder(
                    builder: (context) {
                      final bar = Container(
                        padding: EdgeInsets.only(top: topPad),
                        color: _showBarTitle
                            ? p.settingsBg.withValues(alpha: 0.78)
                            : Colors.transparent,
                        child: SizedBox(
                          height: 54,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                const SizedBox(width: 42),
                                Expanded(
                                  child: AnimatedOpacity(
                                    duration: TalerTheme.fastDuration,
                                    opacity: _showBarTitle ? 1 : 0,
                                    child: Text(
                                      'Настройки',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w600,
                                        color: p.fg,
                                      ),
                                    ),
                                  ),
                                ),
                                _GlassCircleAction(
                                  icon: TalerIcons.pencil,
                                  tooltip: 'Изменить имя',
                                  onPressed:
                                      user == null ? null : _editNameDialog,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      if (!_showBarTitle) return bar;
                      return ClipRect(
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: bar,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          color: p.settingsBg,
          child: Column(
            children: [
              // Верхняя панель 56px на широком экране
              Container(
                color: p.bg2,
                child: SafeArea(
                  bottom: false,
                  top: false,
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
                          size: 34,
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
                            color: p.surface2,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'v1.2.5',
                            style: TalerTheme.tabularStyle(
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
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    widget.bottomInset + 12,
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
                          _buildAboutCard(p),
                          const SizedBox(height: 14),
                          _buildLogoutCard(p),
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

  Widget _buildMobileProfileHero(
    TalerPalette p,
    TalerUserProfile? user,
    bool isDemo,
  ) {
    final name = user?.fullName ?? 'Пользователь Taler';
    final phoneText = user?.phone != null && user!.phone!.isNotEmpty
        ? user.phone!
        : 'Телефон скрыт';
    final online = isDemo || widget.client.isSessionReady;

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        children: [
          TalerAvatar(
            seedId: user?.id ?? 1,
            initials: user?.initials ?? 'T',
            imageUrl: user?.avatarUrl,
            size: 88,
            isOnline: online,
            onlineBorderColor: p.settingsBg,
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: p.fg,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            isDemo ? 'Демо-режим' : (online ? 'В сети' : 'Подключение…'),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: online ? p.accent : p.fg2,
            ),
          ),
          if (phoneText.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              phoneText,
              style: TalerTheme.tabularStyle(size: 13, color: p.fg2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMyProfileTile(TalerPalette p, TalerUserProfile? user) {
    return TalerTableShell(
      child: InkWell(
        onTap: user == null ? null : _editNameDialog,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const TelegramIconBadge(icon: TalerIcons.user, size: 34),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Мой профиль',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: p.fg,
                  ),
                ),
              ),
              TalerIcon(TalerIcons.chevronRight, size: 17, color: p.fg3),
            ],
          ),
        ),
      ),
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
            size: 60,
            isOnline: true,
            onlineBorderColor: p.bg2,
          ),
          const SizedBox(width: 14),
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
                    if (isDemo) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: p.accentMuted,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Демо',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: p.accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  phoneText.isNotEmpty ? phoneText : 'ID ${user?.id ?? '—'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TalerTheme.tabularStyle(size: 13, color: p.fg2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TalerIconButton(
            icon: TalerIcons.pencil,
            tooltip: 'Изменить имя',
            circle: true,
            size: 36,
            iconSize: 18,
            color: p.fg,
            backgroundColor: p.bg3,
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
                  size: 34,
                ),
                const SizedBox(width: 14),
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
      title: 'Активные сессии',
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
                  Divider(height: 1, indent: 62, color: p.line),
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
                        size: 34,
                      ),
                      const SizedBox(width: 14),
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

  Widget _buildAboutCard(TalerPalette p) {
    return TalerTableShell(
      title: 'О клиенте Taler',
      bodyPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const TalerLogo(size: 34, showShieldBadge: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Taler для MAX',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: p.fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'github.com/grentu/Taler',
                  style: TextStyle(fontSize: 12, color: p.fg2),
                ),
              ],
            ),
          ),
          Text(
            'v1.2.5',
            style: TalerTheme.tabularStyle(size: 13, color: p.fg3),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutCard(TalerPalette p) {
    return TalerTableShell(
      child: InkWell(
        onTap: () => widget.client.logout(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const TelegramIconBadge(
                icon: TalerIcons.logOut,
                size: 34,
                isDanger: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.client.isDemoMode
                      ? 'Выйти из демо-режима'
                      : 'Выйти из аккаунта',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: p.danger,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCircleAction extends StatelessWidget {
  final TalerIconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _GlassCircleAction({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final bg = p.isDark ? const Color(0xCC191B23) : const Color(0xDCFFFFFF);
    final border = (p.isDark ? Colors.white : Colors.black).withValues(alpha: 0.08);
    return Tooltip(
      message: tooltip,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Material(
            color: bg,
            shape: CircleBorder(side: BorderSide(color: border)),
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 42,
                height: 42,
                child: Center(
                  child: TalerIcon(
                    icon,
                    size: 19,
                    strokeWidth: 2.0,
                    color: p.fg,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

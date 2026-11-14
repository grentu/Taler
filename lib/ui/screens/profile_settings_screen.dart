import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../theme/taler_theme.dart';

/// Экран настроек профиля, активных сессий и темы оформления Taler.
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
    final firstCtrl = TextEditingController(text: user?.firstName ?? '');
    final lastCtrl = TextEditingController(text: user?.lastName ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Редактировать профиль',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstCtrl,
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
          TalerTactileButton(
            label: 'Отмена',
            compact: true,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          TalerTactileButton(
            label: 'Сохранить',
            compact: true,
            variant: TalerButtonVariant.primary,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (saved == true && firstCtrl.text.trim().isNotEmpty) {
      await widget.client.updateProfileName(firstCtrl.text, lastCtrl.text);
    }
    firstCtrl.dispose();
    lastCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 860;
    final isTwoCol = screenWidth >= 1040;

    return ListenableBuilder(
      listenable: widget.client,
      builder: (context, _) {
        final user = widget.client.currentUser;
        final sessions = widget.client.activeSessions;

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
                  Expanded(
                    child: Text(
                      'Профиль и сессии',
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
                  Text(
                    'v1.0.0',
                    style: TalerTheme.monoStyle(size: 11.5, color: p.fg3),
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
                    child: isTwoCol
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildProfileShell(p, user),
                                    const SizedBox(height: 16),
                                    _buildThemeShell(p),
                                    const SizedBox(height: 16),
                                    _buildAboutAndLogout(p),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 6,
                                child: _buildSessionsShell(p, sessions),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildProfileShell(p, user),
                              const SizedBox(height: 16),
                              _buildThemeShell(p),
                              const SizedBox(height: 16),
                              _buildSessionsShell(p, sessions),
                              const SizedBox(height: 16),
                              _buildAboutAndLogout(p),
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

  Widget _buildProfileShell(TalerPalette p, dynamic user) {
    return TalerTableShell(
      title: 'Учётная запись',
      trailing: TalerIconButton(
        icon: Icons.edit_outlined,
        size: 32,
        iconSize: 16,
        tooltip: 'Изменить имя',
        onPressed: _editNameDialog,
      ),
      bodyPadding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: p.line2),
            ),
            child: Text(
              user?.initials ?? 'T',
              style: TextStyle(
                color: p.fg,
                fontWeight: FontWeight.w500,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.fullName ?? 'Профиль Taler',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 15.5,
                    color: p.fg,
                  ),
                ),
                if (user?.phone != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    user!.phone!,
                    style: TalerTheme.tabularStyle(size: 12.5, color: p.fg2),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  widget.client.isDemoMode
                      ? 'Режим песочницы · локально'
                      : 'ID ${user?.id ?? 0}',
                  style: TalerTheme.monoStyle(size: 11.5, color: p.fg3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeShell(TalerPalette p) {
    return TalerTableShell(
      title: 'Тема оформления',
      bodyPadding: const EdgeInsets.all(12),
      child: TalerSlidingPillSwitch<ThemeMode>(
        value: widget.themeMode,
        height: 32,
        onChanged: widget.onThemeModeChanged,
        items: const [
          TalerSegment(
            value: ThemeMode.dark,
            label: 'Тёмная',
            icon: Icons.dark_mode_outlined,
          ),
          TalerSegment(
            value: ThemeMode.light,
            label: 'Светлая',
            icon: Icons.light_mode_outlined,
          ),
          TalerSegment(
            value: ThemeMode.system,
            label: 'Система',
            icon: Icons.brightness_auto_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsShell(TalerPalette p, List<dynamic> sessions) {
    return TalerTableShell(
      title: 'Активные сессии',
      trailing: TalerIconButton(
        icon: Icons.refresh_rounded,
        size: 32,
        iconSize: 16,
        tooltip: 'Обновить',
        onPressed: widget.client.fetchActiveSessions,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'Нет данных об активных сессиях',
                  style: TextStyle(fontSize: 12.5, color: p.fg3),
                ),
              ),
            )
          else
            for (var i = 0; i < sessions.length; i++) ...[
              if (i > 0) Divider(height: 1, color: p.line),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    TalerStatusDot(
                      color: sessions[i].current ? p.statusLive : p.fg3,
                      size: 6,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sessions[i].client,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: p.fg,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${sessions[i].location} ${sessions[i].info}'.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: p.fg2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      sessions[i].current
                          ? 'Текущая'
                          : DateFormat('dd.MM HH:mm').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                sessions[i].time,
                              ),
                            ),
                      style: TalerTheme.monoStyle(
                        size: 11.5,
                        color: sessions[i].current ? p.statusLive : p.fg3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          if (sessions.any((s) => !s.current)) ...[
            Divider(height: 1, color: p.line),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TalerTactileButton(
                label: 'Завершить остальные сессии',
                icon: Icons.logout_rounded,
                onPressed: widget.client.terminateOtherSessions,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAboutAndLogout(TalerPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TalerTableShell(
          title: 'О клиенте Taler',
          bodyPadding: const EdgeInsets.all(14),
          child: Text(
            'Открытый кроссплатформенный клиент MAX на Flutter/Dart. Репозиторий grentu/Taler, лицензия GPL-3.0. Телеметрия и проприетарные модули исключены на уровне протокола.',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: p.fg2),
          ),
        ),
        const SizedBox(height: 16),
        TalerTactileButton(
          label: widget.client.isDemoMode
              ? 'Выйти из демо-режима'
              : 'Выйти из аккаунта',
          icon: Icons.exit_to_app_rounded,
          variant: TalerButtonVariant.danger,
          onPressed: widget.client.logout,
        ),
      ],
    );
  }
}

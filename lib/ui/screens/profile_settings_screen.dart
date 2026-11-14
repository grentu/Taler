import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

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
        title: const Text('Редактировать профиль'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstCtrl,
              decoration: const InputDecoration(labelText: 'Имя'),
            ),
            const SizedBox(height: 10),
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

    if (saved == true && firstCtrl.text.trim().isNotEmpty) {
      await widget.client.updateProfileName(firstCtrl.text, lastCtrl.text);
    }
    firstCtrl.dispose();
    lastCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.client,
      builder: (context, _) {
        final user = widget.client.currentUser;
        final sessions = widget.client.activeSessions;

        return Scaffold(
          appBar: AppBar(title: const Text('Профиль и настройки')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Профиль
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.16),
                        child: Text(
                          user?.initials ?? 'T',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            if (user?.phone != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                user!.phone!,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                            Text(
                              widget.client.isDemoMode
                                  ? 'Режим песочницы (локальный)'
                                  : 'ID: ${user?.id ?? 0}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _editNameDialog,
                        tooltip: 'Изменить имя',
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Тема оформления
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Тема оформления',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Тёмная'),
                            icon: Icon(Icons.dark_mode_outlined, size: 18),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Светлая'),
                            icon: Icon(Icons.light_mode_outlined, size: 18),
                          ),
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('Система'),
                            icon: Icon(Icons.brightness_auto_outlined, size: 18),
                          ),
                        ],
                        selected: {widget.themeMode},
                        onSelectionChanged: (s) =>
                            widget.onThemeModeChanged(s.first),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Активные сессии
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Активные сессии',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: widget.client.fetchActiveSessions,
                            tooltip: 'Обновить',
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                          ),
                        ],
                      ),
                      if (sessions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Нет данных о сессиях',
                            style: theme.textTheme.bodySmall,
                          ),
                        )
                      else
                        for (final s in sessions)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              s.current
                                  ? Icons.verified_user_outlined
                                  : Icons.devices_other_outlined,
                              color: s.current
                                  ? TalerTheme.shieldGreen
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            title: Text(
                              s.client,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${s.location} ${s.info}'.trim(),
                              style: theme.textTheme.bodySmall,
                            ),
                            trailing: s.current
                                ? const Text(
                                    'Текущая',
                                    style: TextStyle(
                                      color: TalerTheme.shieldGreen,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : Text(
                                    DateFormat('dd.MM HH:mm').format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        s.time,
                                      ),
                                    ),
                                    style: theme.textTheme.bodySmall,
                                  ),
                          ),
                      if (sessions.any((s) => !s.current)) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: widget.client.terminateOtherSessions,
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: const Text('Завершить остальные сессии'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // О проекте Taler
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'О приложении Taler',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Открытый кроссплатформенный клиент MAX на чистом Flutter/Dart (организация grentu/Taler, лицензия GPL-3.0). Без проприетарных библиотек, трекеров и телеметрии.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              OutlinedButton.icon(
                onPressed: widget.client.logout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: TalerTheme.dangerRed,
                  side: BorderSide(
                    color: TalerTheme.dangerRed.withValues(alpha: 0.45),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.exit_to_app_rounded),
                label: Text(
                  widget.client.isDemoMode
                      ? 'Выйти из демо-режима'
                      : 'Выйти из аккаунта',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

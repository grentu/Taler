import 'dart:async';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/storage/app_preferences.dart';
import '../../core/storage/taler_models.dart';
import '../icons/taler_icon.dart';
import '../theme/chat_tokens.dart';
import '../theme/taler_theme.dart';
import '../widgets/message_bubble.dart';
import '../widgets/settings_components.dart';

/// Экран настроек клиента в стиле Solar / exteraGram с живым поиском и подэкранами.
class SettingsScreen extends StatefulWidget {
  final TalerClient client;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback? onOpenShield;
  final VoidCallback? onOpenProfile;
  final double bottomInset;

  const SettingsScreen({
    super.key,
    required this.client,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.onOpenShield,
    this.onOpenProfile,
    this.bottomInset = 16,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsItemSpec {
  final TalerIconData icon;
  final Color color;
  final String title;
  final String keywords;
  final String? valueText;
  final VoidCallback onTap;

  const _SettingsItemSpec({
    required this.icon,
    required this.color,
    required this.title,
    required this.keywords,
    required this.onTap,
    this.valueText,
  });
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();
  bool _searching = false;
  bool _showBarTitle = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.client.activeSessions.isEmpty) {
        widget.client.fetchActiveSessions();
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl
      ..removeListener(_onScroll)
      ..dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scrollCtrl.hasClients && _scrollCtrl.offset > 120;
    if (show != _showBarTitle && mounted) {
      setState(() => _showBarTitle = show);
    }
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchCtrl.clear();
        _searchFocus.unfocus();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _searchFocus.requestFocus();
        });
      }
    });
  }

  Future<void> _copyAndNotify(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatUserPhone(String? raw) {
    final parsed = raw != null ? int.tryParse(raw.replaceAll(RegExp(r'\D'), '')) : null;
    if (parsed != null && parsed != 0) return ChatTokens.phone(parsed);
    return raw?.isNotEmpty == true ? raw! : 'Демо-аккаунт Taler';
  }

  void _openQuickAccountSheet(BuildContext context) {
    if (widget.onOpenProfile != null) {
      widget.onOpenProfile!();
      return;
    }
    final user = widget.client.currentUser;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final p = TalerTheme.paletteOf(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: p.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                TalerAvatar(
                  seedId: user?.id ?? 0,
                  initials: user?.initials ?? 'T',
                  imageUrl: user?.avatarUrl,
                  size: 68,
                ),
                const SizedBox(height: 12),
                Text(
                  user?.fullName ?? 'Профиль Taler',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: p.fg,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatUserPhone(user?.phone),
                  style: TextStyle(fontSize: 13.5, color: p.fg2),
                ),
                if (user != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _copyAndNotify('${user.id}', 'ID ${user.id} скопирован');
                      },
                      child: Text('Скопировать ID: ${user.id}'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _openShield(BuildContext context) {
    if (widget.onOpenShield != null) {
      widget.onOpenShield!();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Перейдите на вкладку «Защита»')),
    );
  }

  void _openChatAppearance() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ChatAppearancePage(
          client: widget.client,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
        ),
      ),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _NotificationsPage(client: widget.client),
      ),
    );
  }

  void _openDataStorage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DataStoragePage(client: widget.client),
      ),
    );
  }

  void _openFolders() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FoldersPage(client: widget.client),
      ),
    );
  }

  void _openDevices() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DevicesPage(client: widget.client),
      ),
    );
  }

  void _openPowerSaving() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PowerSavingPage(client: widget.client),
      ),
    );
  }

  void _openLanguageDialog() {
    final p = TalerTheme.paletteOf(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Язык интерфейса',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.fg),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.accent.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Русский', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: p.fg)),
                        Text('Основной язык клиента', style: TextStyle(fontSize: 12.5, color: p.fg3)),
                      ],
                    ),
                  ),
                  TalerIcon(TalerIcons.check, size: 18, color: p.accent),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  void _openInfoSheet({
    required String title,
    required String body,
    String? copyText,
    String? copyButtonLabel,
  }) {
    final p = TalerTheme.paletteOf(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          title,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.fg),
        ),
        content: Text(
          body,
          style: TextStyle(fontSize: 14, height: 1.45, color: p.fg2),
        ),
        actions: [
          if (copyText != null && copyButtonLabel != null)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _copyAndNotify(copyText, 'Скопировано: $copyText');
              },
              child: Text(copyButtonLabel),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  List<_SettingsItemSpec> _buildAllItems(
    int sessionsCount,
    AppPreferences prefs,
  ) {
    return [
      _SettingsItemSpec(
        icon: TalerIcons.shieldCheck,
        color: const Color(0xFFE53935),
        title: 'Настройки Taler',
        keywords: 'защита приватность призрак anti delete маскировка shield taler',
        onTap: () => _openShield(context),
      ),
      _SettingsItemSpec(
        icon: TalerIcons.user,
        color: const Color(0xFF1E88E5),
        title: 'Аккаунт',
        keywords: 'аккаунт профиль имя телефон id выход',
        onTap: () => _openQuickAccountSheet(context),
      ),
      _SettingsItemSpec(
        icon: TalerIcons.messageCircle,
        color: const Color(0xFFF59E0B),
        title: 'Настройки чатов',
        keywords: 'тема ночная светлая шрифт размер пузыри скругление обои дизайн',
        onTap: _openChatAppearance,
      ),
      _SettingsItemSpec(
        icon: TalerIcons.key,
        color: const Color(0xFF22C55E),
        title: 'Конфиденциальность',
        keywords: 'конфиденциальность безопасность чтение печать онлайн скрыть',
        onTap: () => _openShield(context),
      ),
      _SettingsItemSpec(
        icon: TalerIcons.bell,
        color: const Color(0xFFEF4444),
        title: 'Уведомления',
        keywords: 'уведомления звук без звука бейджи превью',
        onTap: _openNotifications,
      ),
      _SettingsItemSpec(
        icon: TalerIcons.pieChart,
        color: const Color(0xFF4F6DF5),
        title: 'Данные и память',
        keywords: 'данные память кэш очистить хранилище трафик',
        onTap: _openDataStorage,
      ),
      _SettingsItemSpec(
        icon: TalerIcons.folder,
        color: const Color(0xFF2990FF),
        title: 'Папки с чатами',
        keywords: 'папки вкладки фильтры чаты личные группы каналы',
        onTap: _openFolders,
      ),
      _SettingsItemSpec(
        icon: TalerIcons.monitor,
        color: const Color(0xFF06B6D4),
        title: 'Устройства',
        keywords: 'устройства сессии вход завершить',
        valueText: '$sessionsCount',
        onTap: _openDevices,
      ),
      _SettingsItemSpec(
        icon: TalerIcons.battery,
        color: const Color(0xFFF97316),
        title: 'Энергосбережение',
        keywords: 'энергосбережение батарея блюр анимации оптимизация',
        onTap: _openPowerSaving,
      ),
      _SettingsItemSpec(
        icon: TalerIcons.globe,
        color: const Color(0xFF8B5CF6),
        title: 'Язык',
        keywords: 'язык русский локализация language',
        valueText: prefs.languageLabel,
        onTap: _openLanguageDialog,
      ),
      _SettingsItemSpec(
        icon: TalerIcons.askQuestion,
        color: const Color(0xFFF59E0B),
        title: 'Задать вопрос',
        keywords: 'поддержка вопрос баг github issues',
        onTap: () => _openInfoSheet(
          title: 'Поддержка и обратная связь',
          body: 'Нашли ошибку или хотите предложить улучшение? Создайте обращение в репозитории проекта Taler.',
          copyText: 'https://github.com/grentu/Taler/issues',
          copyButtonLabel: 'Скопировать ссылку',
        ),
      ),
      _SettingsItemSpec(
        icon: TalerIcons.info,
        color: const Color(0xFF2990FF),
        title: 'Вопросы о Taler',
        keywords: 'faq вопросы справка max клиент обновления',
        onTap: () => _openInfoSheet(
          title: 'Вопросы о Taler',
          body: 'Taler — независимый клиент для MAX на базе открытого протокола.\n\n• Переписка, группы и папки синхронизируются с вашей учётной записью MAX.\n• Все настройки защиты, Anti-Delete и кэш работают локально на устройстве.',
        ),
      ),
      _SettingsItemSpec(
        icon: TalerIcons.bulb,
        color: const Color(0xFFA855F7),
        title: 'Возможности Taler',
        keywords: 'функции возможности anti delete история правок призрак',
        onTap: () => _openInfoSheet(
          title: 'Возможности Taler',
          body: '• Режим «Призрак»: скрывает ваш статус онлайн, набор текста и отметки прочтения.\n• Защита истории: сохраняет удалённые и отредактированные сообщения.\n• Маскировка устройства: передаёт профиль выбранного устройства при подключении.\n• Гибкие настройки чатов, папок, кэша и энергосбережения.',
        ),
      ),
      _SettingsItemSpec(
        icon: TalerIcons.policy,
        color: const Color(0xFF22C55E),
        title: 'Политика конфиденциальности',
        keywords: 'политика конфиденциальность телеметрия приватность данные',
        onTap: () => _openInfoSheet(
          title: 'Политика конфиденциальности',
          body: 'Taler не собирает аналитику, не содержит рекламных SDK и блокирует отправку фоновой телеметрии до выхода из приложения.\n\nТокен сессии, локальный кэш чатов и настройки хранятся только в памяти вашего устройства.',
        ),
      ),
    ];
  }

  Widget _buildHeaderHero(TalerPalette p) {
    final user = widget.client.currentUser;
    final sub = _formatUserPhone(user?.phone);
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
                onTap: () => _openQuickAccountSheet(context),
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
          sub,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            color: p.fg3,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final isWide = MediaQuery.sizeOf(context).width >= 820;

    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.client,
        widget.client.appPreferences,
      ]),
      builder: (context, _) {
        final prefs = widget.client.appPreferences;
        final sessionsCount = widget.client.activeSessions.isEmpty
            ? 1
            : widget.client.activeSessions.length;

        final allItems = _buildAllItems(sessionsCount, prefs);
        final highlight = allItems.first;
        final mainItems = allItems.sublist(1, 10);
        final helpItems = allItems.sublist(10);

        final q = _query.trim().toLowerCase();
        final filtered = q.isEmpty
            ? const <_SettingsItemSpec>[]
            : allItems
                .where((item) =>
                    item.title.toLowerCase().contains(q) ||
                    item.keywords.contains(q))
                .toList();

        return Container(
          color: p.settingsBg,
          child: Column(
            children: [
              _buildTopBar(p, isWide),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    12,
                    4,
                    12,
                    widget.bottomInset + 16,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: q.isNotEmpty
                          ? _buildSearchResults(p, filtered)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildHeaderHero(p),
                                const SizedBox(height: 16),
                                TalerSettingsGroup(
                                  children: [_toTile(highlight)],
                                ),
                                const SizedBox(height: 12),
                                TalerSettingsGroup(
                                  children: [
                                    for (final item in mainItems) _toTile(item),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                TalerSettingsGroup(
                                  title: 'Помощь',
                                  accentTitle: true,
                                  children: [
                                    for (final item in helpItems) _toTile(item),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                Center(
                                  child: Text(
                                    'Taler 1.2.8 (14)',
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

  Widget _toTile(_SettingsItemSpec item) {
    return TalerSettingsTile(
      icon: item.icon,
      badgeColor: item.color,
      title: item.title,
      valueText: item.valueText,
      onTap: item.onTap,
    );
  }

  Widget _buildSearchResults(TalerPalette p, List<_SettingsItemSpec> items) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(
            'Ничего не найдено',
            style: TextStyle(fontSize: 14.5, color: p.fg3),
          ),
        ),
      );
    }
    return TalerSettingsGroup(
      title: 'Результаты поиска',
      accentTitle: true,
      children: [for (final item in items) _toTile(item)],
    );
  }

  Widget _buildTopBar(TalerPalette p, bool isWide) {
    return Container(
      color: isWide ? p.bg2 : p.settingsBg,
      child: SafeArea(
        bottom: false,
        top: !isWide,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isWide ? p.bg2 : p.settingsBg,
            border: isWide ? Border(bottom: BorderSide(color: p.line)) : null,
          ),
          child: _searching
              ? Row(
                  children: [
                    TalerIconButton(
                      icon: TalerIcons.arrowLeft,
                      tooltip: 'Назад',
                      size: 42,
                      iconSize: 20,
                      color: p.fg,
                      onPressed: _toggleSearch,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        onChanged: (v) => setState(() => _query = v),
                        style: TextStyle(fontSize: 15, color: p.fg),
                        decoration: InputDecoration(
                          hintText: 'Поиск по настройкам',
                          hintStyle: TextStyle(fontSize: 15, color: p.fg3),
                          filled: false,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      TalerIconButton(
                        icon: TalerIcons.close,
                        tooltip: 'Очистить',
                        size: 38,
                        iconSize: 17,
                        color: p.fg2,
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                  ],
                )
              : Row(
                  children: [
                    TalerIconButton(
                      icon: TalerIcons.qrCode,
                      tooltip: 'Профиль и ID',
                      size: 42,
                      iconSize: 21,
                      color: p.fg,
                      onPressed: () => _openQuickAccountSheet(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        opacity: (isWide || _showBarTitle) ? 1.0 : 0.0,
                        child: Text(
                          'Настройки',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: p.fg,
                          ),
                        ),
                      ),
                    ),
                    TalerIconButton(
                      icon: TalerIcons.search,
                      tooltip: 'Поиск в настройках',
                      size: 42,
                      iconSize: 21,
                      color: p.fg,
                      onPressed: _toggleSearch,
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Ещё',
                      color: p.bg2,
                      icon: TalerIcon(TalerIcons.more, size: 21, color: p.fg),
                      onSelected: (action) {
                        if (action == 'profile') _openQuickAccountSheet(context);
                        if (action == 'shield') _openShield(context);
                        if (action == 'storage') _openDataStorage();
                        if (action == 'logout') widget.client.logout();
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'profile', child: Text('Профиль')),
                        const PopupMenuItem(value: 'shield', child: Text('Taler Shield')),
                        const PopupMenuItem(value: 'storage', child: Text('Данные и память')),
                        PopupMenuItem(
                          value: 'logout',
                          child: Text('Выйти', style: TextStyle(color: p.danger)),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SettingsSubScaffold extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final Widget body;

  const _SettingsSubScaffold({
    required this.title,
    required this.body,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Scaffold(
      backgroundColor: p.settingsBg,
      appBar: AppBar(
        backgroundColor: p.bg2,
        leading: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: TalerIconButton(
            icon: TalerIcons.arrowLeft,
            tooltip: 'Назад',
            iconSize: 20,
            color: p.fg,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: Text(
          title,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: p.fg),
        ),
        actions: actions,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: p.line),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: body,
          ),
        ),
      ),
    );
  }
}

class _ChatAppearancePage extends StatelessWidget {
  final TalerClient client;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const _ChatAppearancePage({
    required this.client,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return ListenableBuilder(
      listenable: client.appPreferences,
      builder: (context, _) {
        final prefs = client.appPreferences;
        final now = DateTime.now().millisecondsSinceEpoch;
        final previewIn = TalerMessage(
          id: 'preview_in',
          chatId: 0,
          senderId: 2,
          time: now - 60000,
          text: 'Привет! Как выглядят новые пузыри?',
          status: 'read',
        );
        final previewOut = TalerMessage(
          id: 'preview_out',
          chatId: 0,
          senderId: 1,
          time: now,
          text: 'Отступы ровные, иконки чёткие 👍',
          status: 'read',
        );

        return _SettingsSubScaffold(
          title: 'Настройки чатов',
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: IntrinsicHeight(
                  child: TelegramChatBackground(
                    baseColor: ChatTokens.chatBackground(p),
                    showPattern: prefs.showChatWallpaper && !prefs.powerSavingMode,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: MessageBubble(
                              message: previewIn,
                              isMine: false,
                              firstInRun: true,
                              showName: false,
                              senderName: 'Собеседник',
                              maxWidth: 260,
                              fontSize: prefs.messageFontSize,
                              cornerRadius: prefs.bubbleRadius,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: MessageBubble(
                              message: previewOut,
                              isMine: true,
                              firstInRun: true,
                              showName: false,
                              senderName: 'Вы',
                              maxWidth: 260,
                              fontSize: prefs.messageFontSize,
                              cornerRadius: prefs.bubbleRadius,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TalerSettingsGroup(
                title: 'Тема оформления',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TalerSlidingPillSwitch<ThemeMode>(
                      value: prefs.themeMode,
                      onChanged: (next) => onThemeModeChanged(next),
                      items: const [
                        TalerSegment(value: ThemeMode.dark, label: 'Тёмная', icon: TalerIcons.moon),
                        TalerSegment(value: ThemeMode.light, label: 'Светлая', icon: TalerIcons.sun),
                        TalerSegment(value: ThemeMode.system, label: 'Авто', icon: TalerIcons.sunMoon),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TalerSettingsGroup(
                title: 'Размер текста и форма пузырей',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Размер текста сообщений',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: p.fg),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${prefs.messageFontSize.round()} px',
                              style: TalerTheme.tabularStyle(
                                size: 14,
                                weight: FontWeight.w600,
                                color: p.accent,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: prefs.messageFontSize,
                          min: 13,
                          max: 18,
                          divisions: 5,
                          activeColor: p.accent,
                          onChanged: (v) => unawaited(prefs.setMessageFontSize(v.roundToDouble())),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'Скругление углов сообщений',
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: p.fg),
                          ),
                        ),
                        TalerSlidingPillSwitch<double>(
                          value: prefs.bubbleRadius,
                          onChanged: (v) => unawaited(prefs.setBubbleRadius(v)),
                          items: const [
                            TalerSegment(value: 12.0, label: 'Компакт'),
                            TalerSegment(value: 16.0, label: 'Среднее'),
                            TalerSegment(value: 20.0, label: 'Мягкое'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TalerSettingsGroup(
                title: 'Отображение',
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.palette,
                    badgeColor: const Color(0xFF8B5CF6),
                    title: 'Узор на фоне чатов',
                    subtitle: 'Тонкий орнамент позади сообщений',
                    showChevron: false,
                    trailing: Switch(
                      value: prefs.showChatWallpaper,
                      onChanged: (v) => unawaited(prefs.setShowChatWallpaper(v)),
                    ),
                    onTap: () => unawaited(prefs.setShowChatWallpaper(!prefs.showChatWallpaper)),
                  ),
                  TalerSettingsTile(
                    icon: TalerIcons.messageCircle,
                    badgeColor: const Color(0xFF0EA5E9),
                    title: 'Компактный список чатов',
                    subtitle: 'Уменьшить высоту строк и аватаров',
                    showChevron: false,
                    trailing: Switch(
                      value: prefs.compactChatList,
                      onChanged: (v) => unawaited(prefs.setCompactChatList(v)),
                    ),
                    onTap: () => unawaited(prefs.setCompactChatList(!prefs.compactChatList)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NotificationsPage extends StatelessWidget {
  final TalerClient client;

  const _NotificationsPage({required this.client});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([client, client.appPreferences]),
      builder: (context, _) {
        final prefs = client.appPreferences;
        final mutedChats = client.chats.where((c) => c.isMuted).toList();
        return _SettingsSubScaffold(
          title: 'Уведомления',
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TalerSettingsGroup(
                title: 'Индикация',
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.bell,
                    badgeColor: const Color(0xFFEF4444),
                    title: 'Показывать текст в уведомлениях',
                    subtitle: 'Отображать фрагмент сообщения',
                    showChevron: false,
                    trailing: Switch(
                      value: prefs.showNotificationPreview,
                      onChanged: (v) => unawaited(prefs.setShowNotificationPreview(v)),
                    ),
                    onTap: () => unawaited(
                      prefs.setShowNotificationPreview(!prefs.showNotificationPreview),
                    ),
                  ),
                  TalerSettingsTile(
                    icon: TalerIcons.folder,
                    badgeColor: const Color(0xFF0EA5E9),
                    title: 'Счётчики на папках чатов',
                    subtitle: 'Показывать число непрочитанных на вкладках',
                    showChevron: false,
                    trailing: Switch(
                      value: prefs.showFolderBadges,
                      onChanged: (v) => unawaited(prefs.setShowFolderBadges(v)),
                    ),
                    onTap: () => unawaited(prefs.setShowFolderBadges(!prefs.showFolderBadges)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TalerSettingsGroup(
                title: 'Чаты без звука (${mutedChats.length})',
                children: mutedChats.isEmpty
                    ? [
                        const TalerSettingsTile(
                          icon: TalerIcons.bellOff,
                          badgeColor: Color(0xFF64748B),
                          title: 'Нет заглушённых чатов',
                          subtitle: 'Все диалоги и группы присылают уведомления',
                          showChevron: false,
                        ),
                      ]
                    : [
                        for (final chat in mutedChats)
                          TalerSettingsTile(
                            icon: TalerIcons.bellOff,
                            badgeColor: const Color(0xFF64748B),
                            title: chat.title,
                            subtitle: 'Нажмите, чтобы снова включить уведомления',
                            valueText: 'Включить',
                            showChevron: false,
                            onTap: () => unawaited(client.toggleChatMute(chat.id)),
                          ),
                      ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DataStoragePage extends StatelessWidget {
  final TalerClient client;

  const _DataStoragePage({required this.client});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([client, client.appPreferences]),
      builder: (context, _) {
        final prefs = client.appPreferences;
        final stats = client.store.estimateCacheStats();
        final sizeText = stats.approxBytes > 0
            ? ChatTokens.fileSize(stats.approxBytes)
            : '0 КБ';

        return _SettingsSubScaffold(
          title: 'Данные и память',
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TalerSettingsGroup(
                title: 'Использование хранилища',
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.pieChart,
                    badgeColor: const Color(0xFF4F6DF5),
                    title: 'Кэш сообщений и чатов',
                    subtitle: '${stats.chatsCount} чатов • ${stats.messagesCount} сообщений • ${stats.contactsCount} контактов',
                    valueText: sizeText,
                    showChevron: false,
                  ),
                  TalerSettingsTile(
                    icon: TalerIcons.trash,
                    badgeColor: p.danger,
                    title: 'Очистить кэш сообщений',
                    titleColor: p.danger,
                    subtitle: 'Аккаунт и список чатов останутся в сохранности',
                    showChevron: false,
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: p.bg2,
                          title: const Text('Очистить кэш?'),
                          content: const Text(
                            'История сообщений в локальном кэше будет удалена с устройства. Вы не выйдете из аккаунта.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Отмена'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Очистить'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true || !context.mounted) return;
                      final removed = await client.clearMessageCache();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Кэш очищен (удалено сообщений: $removed)')),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TalerSettingsGroup(
                title: 'Медиа и трафик',
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.image,
                    badgeColor: const Color(0xFF0EA5E9),
                    title: 'Автозагрузка медиа в чатах',
                    subtitle: 'Загружать изображения автоматически при открытии',
                    showChevron: false,
                    trailing: Switch(
                      value: prefs.autoDownloadMedia,
                      onChanged: (v) => unawaited(prefs.setAutoDownloadMedia(v)),
                    ),
                    onTap: () => unawaited(prefs.setAutoDownloadMedia(!prefs.autoDownloadMedia)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FoldersPage extends StatelessWidget {
  final TalerClient client;

  const _FoldersPage({required this.client});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([client, client.appPreferences]),
      builder: (context, _) {
        final prefs = client.appPreferences;
        final serverFolders = client.folders.where((f) => !f.isAllChats).toList();
        final rows = serverFolders.isNotEmpty
            ? [
                for (final f in serverFolders)
                  (
                    title: f.title,
                    count: client.chats.where((c) => f.chatIds.contains(c.id)).length,
                  ),
              ]
            : [
                (title: 'Личные', count: client.chats.where((c) => c.isDialog).length),
                (title: 'Группы', count: client.chats.where((c) => c.isGroup).length),
                (title: 'Каналы', count: client.chats.where((c) => c.isChannel).length),
              ];

        return _SettingsSubScaffold(
          title: 'Папки с чатами',
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TalerSettingsGroup(
                title: 'Активные вкладки',
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.folder,
                    badgeColor: const Color(0xFF0EA5E9),
                    title: 'Все чаты',
                    valueText: '${client.chats.length}',
                    showChevron: false,
                  ),
                  for (final r in rows)
                    TalerSettingsTile(
                      icon: TalerIcons.folder,
                      badgeColor: const Color(0xFF3B82F6),
                      title: r.title,
                      valueText: '${r.count}',
                      showChevron: false,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TalerSettingsGroup(
                title: 'Отображение',
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.bell,
                    badgeColor: const Color(0xFF22C55E),
                    title: 'Счётчики непрочитанных',
                    subtitle: 'Показывать бейдж с числом чатов на вкладках',
                    showChevron: false,
                    trailing: Switch(
                      value: prefs.showFolderBadges,
                      onChanged: (v) => unawaited(prefs.setShowFolderBadges(v)),
                    ),
                    onTap: () => unawaited(prefs.setShowFolderBadges(!prefs.showFolderBadges)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DevicesPage extends StatelessWidget {
  final TalerClient client;

  const _DevicesPage({required this.client});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return ListenableBuilder(
      listenable: client,
      builder: (context, _) {
        final sessions = client.activeSessions;
        final hasOthers = sessions.any((s) => !s.current);
        return _SettingsSubScaffold(
          title: 'Устройства',
          actions: [
            TalerIconButton(
              icon: TalerIcons.refresh,
              tooltip: 'Обновить',
              color: p.accent,
              onPressed: () => unawaited(client.fetchActiveSessions()),
            ),
          ],
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TalerSettingsGroup(
                title: 'Активные сеансы',
                children: sessions.isEmpty
                    ? [
                        TalerSettingsTile(
                          icon: TalerIcons.monitor,
                          badgeColor: const Color(0xFF06B6D4),
                          title: 'Текущее устройство',
                          subtitle: client.spoofingService.activeProfile.label,
                          valueText: 'Онлайн',
                          showChevron: false,
                        ),
                      ]
                    : [
                        for (final s in sessions) _sessionRow(p, s),
                      ],
              ),
              if (hasOthers) ...[
                const SizedBox(height: 16),
                TalerSettingsGroup(
                  children: [
                    TalerSettingsTile(
                      icon: TalerIcons.logOut,
                      badgeColor: p.danger,
                      title: 'Завершить все остальные сеансы',
                      titleColor: p.danger,
                      subtitle: 'Оставить активным только это устройство',
                      showChevron: false,
                      onTap: () => unawaited(client.terminateOtherSessions()),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sessionRow(TalerPalette p, TalerActiveSession s) {
    final lower = s.client.toLowerCase();
    final icon = lower.contains('android') || lower.contains('ios')
        ? TalerIcons.smartphone
        : lower.contains('windows') || lower.contains('desktop')
            ? TalerIcons.monitor
            : TalerIcons.globe;
    final dateStr = s.time > 0
        ? DateFormat('dd.MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(s.time))
        : null;
    final details = [
      if (s.location.isNotEmpty) s.location,
      if (s.info.isNotEmpty) s.info,
      ?dateStr,
    ].join(' • ');

    return TalerSettingsTile(
      icon: icon,
      badgeColor: s.current ? p.statusLive : const Color(0xFF3B82F6),
      title: s.client,
      subtitle: details.isEmpty ? null : details,
      valueText: s.current ? 'Текущая' : null,
      showChevron: false,
    );
  }
}

class _PowerSavingPage extends StatelessWidget {
  final TalerClient client;

  const _PowerSavingPage({required this.client});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: client.appPreferences,
      builder: (context, _) {
        final prefs = client.appPreferences;
        return _SettingsSubScaffold(
          title: 'Энергосбережение',
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TalerSettingsGroup(
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.battery,
                    badgeColor: const Color(0xFFF97316),
                    title: 'Режим энергосбережения',
                    subtitle: 'Отключает фоновое размытие (Blur) и узор обоев для экономии заряда',
                    showChevron: false,
                    trailing: Switch(
                      value: prefs.powerSavingMode,
                      onChanged: (v) => unawaited(prefs.setPowerSavingMode(v)),
                    ),
                    onTap: () => unawaited(prefs.setPowerSavingMode(!prefs.powerSavingMode)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TalerSettingsGroup(
                title: 'Что отключается при активации',
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.sunMoon,
                    badgeColor: const Color(0xFF6366F1),
                    title: 'Размытие панелей (BackdropFilter)',
                    valueText: prefs.powerSavingMode ? 'Откл' : 'Активно',
                    showChevron: false,
                  ),
                  TalerSettingsTile(
                    icon: TalerIcons.palette,
                    badgeColor: const Color(0xFF8B5CF6),
                    title: 'Декоративный паттерн фона чатов',
                    valueText: prefs.powerSavingMode ? 'Откл' : 'Активно',
                    showChevron: false,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

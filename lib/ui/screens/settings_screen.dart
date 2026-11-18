import 'dart:async';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/media/taler_media_cache.dart';
import '../../core/storage/app_preferences.dart';
import '../../core/storage/taler_models.dart';
import '../../core/update/app_updater.dart';
import '../../core/version.dart';
import '../icons/taler_icon.dart';
import '../theme/chat_tokens.dart';
import '../theme/taler_theme.dart';
import '../widgets/message_bubble.dart';
import '../widgets/settings_components.dart';
import 'profile_settings_screen.dart';

/// Экран настроек в стиле `exteraless` (`SettingsActivity` + `BaseFragmentSimpleGlass`),
/// адаптированный под строгий чёрный AMOLED-стиль с чёрными сквирклами и фейд-кромкой.
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
  final String title;
  final String keywords;
  final String? valueText;
  final VoidCallback onTap;

  const _SettingsItemSpec({
    required this.icon,
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
  double _fadeFactor = 0.0;
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
    if (!_scrollCtrl.hasClients) return;
    // Как updateActionBarVisible в SettingsActivity: плавно проявляем кромку при уходе аватара вверх.
    final next = ((_scrollCtrl.offset - 24.0) / 88.0).clamp(0.0, 1.0);
    if ((next - _fadeFactor).abs() > 0.02 && mounted) {
      setState(() => _fadeFactor = next);
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

  Future<void> _editNameDialog() async {
    if (widget.client.currentUser == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => TalerEditProfilePage(client: widget.client),
      ),
    );
  }

  void _openAccountSheet(BuildContext context) {
    final user = widget.client.currentUser;
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
                  size: 68,
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
                _formatUserPhone(user?.phone),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: p.fg3),
              ),
              const SizedBox(height: 16),
              TalerSettingsGroup(
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.pencil,
                    title: 'Редактировать профиль',
                    subtitle: 'Имя, фамилия и о себе',
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
                        unawaited(_copyAndNotify('${user.id}', 'ID ${user.id} скопирован'));
                      },
                    ),
                  TalerSettingsTile(
                    icon: TalerIcons.logOut,
                    iconColor: p.danger,
                    title: 'Выйти',
                    titleColor: p.danger,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(widget.client.logout());
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
        builder: (_) => TalerChatAppearancePage(
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
        builder: (_) => TalerDataStoragePage(client: widget.client),
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
        builder: (_) => TalerDevicesPage(client: widget.client),
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

  void _openUpdates() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _UpdatePage(client: widget.client),
      ),
    );
  }

  void _openLanguageDialog() {
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
              Row(
                children: [
                  const TalerSettingsBadge(
                    icon: TalerIcons.settingsLanguage,
                    size: 34,
                    iconSize: 21,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Язык интерфейса',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: p.fg,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TalerSettingsGroup(
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.globe,
                    title: 'Русский',
                    subtitle: 'Основной язык интерфейса',
                    trailing: TalerIcon(TalerIcons.check, size: 18, color: p.accent),
                    onTap: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Готово'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openInfoSheet({
    required TalerIconData icon,
    required String title,
    required String body,
    String? copyText,
    String? copyButtonLabel,
  }) {
    unawaited(
      showTalerInfoSheet(
        context,
        icon: icon,
        title: title,
        body: body,
        copyText: copyText,
        copyButtonLabel: copyButtonLabel,
        onCopied: (text) => _copyAndNotify(text, 'Скопировано: $text'),
      ),
    );
  }

  ({
    List<_SettingsItemSpec> highlight,
    List<_SettingsItemSpec> main,
    List<_SettingsItemSpec> help,
    List<_SettingsItemSpec> all,
  }) _buildSections(
    int sessionsCount,
    AppPreferences prefs,
    AppUpdater updater,
  ) {
    final highlight = [
      _SettingsItemSpec(
        icon: TalerIcons.settingsGram,
        title: 'Настройки Taler',
        keywords: 'защита приватность призрак anti delete маскировка shield taler',
        onTap: () => _openShield(context),
      ),
      _SettingsItemSpec(
        icon: TalerIcons.refresh,
        title: 'Обновление Taler',
        keywords: 'обновление ота ota update версия релиз скачать установить',
        valueText: updater.hasUpdate ? 'v${updater.release?.version ?? ''}' : null,
        onTap: _openUpdates,
      ),
    ];
    final main = [
      _SettingsItemSpec(
        icon: TalerIcons.settingsAccount,
        title: 'Аккаунт',
        keywords: 'аккаунт профиль имя телефон id выход',
        onTap: () => _openAccountSheet(context),
      ),
      _SettingsItemSpec(
        icon: TalerIcons.settingsChat,
        title: 'Настройки чатов',
        keywords: 'тема ночная светлая шрифт размер пузыри скругление обои дизайн',
        onTap: _openChatAppearance,
      ),
      _SettingsItemSpec(
        icon: TalerIcons.settingsPrivacy,
        title: 'Конфиденциальность',
        keywords: 'конфиденциальность безопасность чтение печать онлайн скрыть',
        onTap: () => _openShield(context),
      ),
      _SettingsItemSpec(
        icon: TalerIcons.settingsSounds,
        title: 'Уведомления',
        keywords: 'уведомления звук без звука бейджи превью',
        onTap: _openNotifications,
      ),
      _SettingsItemSpec(
        icon: TalerIcons.settingsData,
        title: 'Данные и память',
        keywords: 'данные память кэш очистить хранилище трафик',
        onTap: _openDataStorage,
      ),
      _SettingsItemSpec(
        icon: TalerIcons.settingsFolders,
        title: 'Папки с чатами',
        keywords: 'папки вкладки фильтры чаты личные группы каналы',
        onTap: _openFolders,
      ),
      _SettingsItemSpec(
        icon: TalerIcons.settingsDevices,
        title: 'Устройства',
        keywords: 'устройства сессии вход завершить',
        valueText: '$sessionsCount',
        onTap: _openDevices,
      ),
      _SettingsItemSpec(
        icon: TalerIcons.settingsPower,
        title: 'Энергосбережение',
        keywords: 'энергосбережение батарея блюр анимации оптимизация',
        onTap: _openPowerSaving,
      ),
      _SettingsItemSpec(
        icon: TalerIcons.settingsLanguage,
        title: 'Язык',
        keywords: 'язык русский локализация language',
        valueText: prefs.languageLabel,
        onTap: _openLanguageDialog,
      ),
    ];
    final help = [
      _SettingsItemSpec(
        icon: TalerIcons.settingsAsk,
        title: 'Задать вопрос',
        keywords: 'поддержка вопрос баг github issues',
        onTap: () => _openInfoSheet(
          icon: TalerIcons.settingsAsk,
          title: 'Поддержка и обратная связь',
          body: 'Нашли ошибку или хотите предложить улучшение? Создайте обращение в репозитории проекта Taler.',
          copyText: 'https://github.com/grentu/Taler/issues',
          copyButtonLabel: 'Скопировать ссылку',
        ),
      ),
      _SettingsItemSpec(
        icon: TalerIcons.settingsFaq,
        title: 'Вопросы о Taler',
        keywords: 'faq вопросы справка max клиент обновления',
        onTap: () => _openInfoSheet(
          icon: TalerIcons.settingsFaq,
          title: 'Вопросы о Taler',
          body: 'Taler — независимый клиент для MAX на базе открытого протокола.\n\nПереписка, группы и папки синхронизируются с вашей учётной записью MAX, а защита приватности и локальный кэш работают на устройстве.',
        ),
      ),
      _SettingsItemSpec(
        icon: TalerIcons.settingsFeatures,
        title: 'Возможности Taler',
        keywords: 'функции возможности anti delete история правок призрак',
        onTap: () => _openInfoSheet(
          icon: TalerIcons.settingsFeatures,
          title: 'Возможности Taler',
          body: 'Режим «Призрак», сохранение удалённых и изменённых сообщений, маскировка устройства, настройка оформления чатов, управление кэшем и энергосбережение.',
        ),
      ),
      _SettingsItemSpec(
        icon: TalerIcons.settingsPolicy,
        title: 'Политика конфиденциальности',
        keywords: 'политика конфиденциальность телеметрия приватность данные',
        onTap: () => _openInfoSheet(
          icon: TalerIcons.settingsPolicy,
          title: 'Политика конфиденциальности',
          body: 'Taler не собирает аналитику, не содержит рекламных SDK и блокирует отправку фоновой телеметрии до выхода из приложения.',
        ),
      ),
    ];
    return (
      highlight: highlight,
      main: main,
      help: help,
      all: [...highlight, ...main, ...help],
    );
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
                onTap: () => _openAccountSheet(context),
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
          style: TextStyle(fontSize: 13.5, color: p.fg3),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    final statusTop = isWide ? 0.0 : MediaQuery.paddingOf(context).top;

    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.client,
        widget.client.appPreferences,
        widget.client.updater,
      ]),
      builder: (context, _) {
        final prefs = widget.client.appPreferences;
        final updater = widget.client.updater;
        final sessionsCount = widget.client.activeSessions.isEmpty
            ? 1
            : widget.client.activeSessions.length;

        final sections = _buildSections(sessionsCount, prefs, updater);

        final q = _query.trim().toLowerCase();
        final filtered = q.isEmpty
            ? const <_SettingsItemSpec>[]
            : sections.all
                .where((item) =>
                    item.title.toLowerCase().contains(q) ||
                    item.keywords.contains(q))
                .toList();

        final scrollTopPad = _searching
            ? statusTop + 62.0
            : (isWide ? 24.0 : statusTop + 18.0);
        final overlayFactor = (_searching || isWide) ? 1.0 : _fadeFactor;

        return PopScope(
          canPop: !_searching,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _searching) {
              _toggleSearch();
            }
          },
          child: ColoredBox(
            color: p.settingsBg,
            child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    12,
                    scrollTopPad,
                    12,
                    widget.bottomInset + 18,
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
                                  children: [
                                    for (final item in sections.highlight)
                                      _toTile(item),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TalerSettingsGroup(
                                  children: [
                                    for (final item in sections.main)
                                      _toTile(item),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                TalerSettingsGroup(
                                  title: 'Помощь',
                                  accentTitle: true,
                                  children: [
                                    for (final item in sections.help)
                                      _toTile(item),
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
                  factor: overlayFactor,
                  powerSaving: prefs.powerSavingMode,
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
                      child: _buildBarContent(p, isWide, overlayFactor),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  Widget _toTile(_SettingsItemSpec item) {
    return TalerSettingsTile(
      icon: item.icon,
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

  Widget _buildBarContent(TalerPalette p, bool isWide, double titleFactor) {
    if (_searching) {
      return Row(
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
              style: TextStyle(fontSize: 15.5, color: p.fg),
              decoration: InputDecoration(
                hintText: 'Поиск по настройкам',
                hintStyle: TextStyle(fontSize: 15.5, color: p.fg3),
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
      );
    }

    return Row(
      children: [
        TalerIconButton(
          icon: TalerIcons.qrCode,
          tooltip: 'Профиль и ID',
          size: 42,
          iconSize: 21,
          color: p.fg,
          onPressed: () => _openAccountSheet(context),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Opacity(
            opacity: isWide ? 1.0 : titleFactor,
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
            if (action == 'profile') _openAccountSheet(context);
            if (action == 'shield') _openShield(context);
            if (action == 'storage') _openDataStorage();
            if (action == 'logout') widget.client.logout();
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(value: 'profile', child: Text('Аккаунт')),
            const PopupMenuItem(value: 'shield', child: Text('Taler Shield')),
            const PopupMenuItem(value: 'storage', child: Text('Данные и память')),
            PopupMenuItem(
              value: 'logout',
              child: Text('Выйти', style: TextStyle(color: p.danger)),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsSubScaffold extends StatefulWidget {
  final String title;
  final List<Widget> actions;
  final Widget Function(ScrollController controller, EdgeInsets padding) bodyBuilder;

  const _SettingsSubScaffold({
    required this.title,
    required this.bodyBuilder,
    this.actions = const [],
  });

  @override
  State<_SettingsSubScaffold> createState() => _SettingsSubScaffoldState();
}

class _SettingsSubScaffoldState extends State<_SettingsSubScaffold> {
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
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: p.settingsBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: widget.bodyBuilder(
                  _scrollCtrl,
                  EdgeInsets.fromLTRB(12, pad.top + 56 + 8, 12, pad.bottom + 24),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: TalerTopFadeOverlay(
              height: pad.top + 52 + 24,
              backgroundColor: p.settingsBg,
              factor: _fadeFactor.clamp(0.65, 1.0),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      TalerIconButton(
                        icon: TalerIcons.arrowLeft,
                        tooltip: 'Назад',
                        size: 42,
                        iconSize: 20,
                        color: p.fg,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            color: p.fg,
                          ),
                        ),
                      ),
                      ...widget.actions,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TalerChatAppearancePage extends StatelessWidget {
  final TalerClient client;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const TalerChatAppearancePage({
    super.key,
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
          text: 'Во сколько созвон?',
          status: 'read',
        );
        final previewOut = TalerMessage(
          id: 'preview_out',
          chatId: 0,
          senderId: 1,
          time: now,
          text: 'В 19:00, буду на месте',
          status: 'read',
        );

        return _SettingsSubScaffold(
          title: 'Настройки чатов',
          bodyBuilder: (controller, padding) => ListView(
            controller: controller,
            padding: padding,
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
                              senderName: 'Алексей',
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
              const SizedBox(height: 14),
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
              const SizedBox(height: 14),
              TalerSettingsGroup(
                title: 'Размер текста и форма пузырей',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
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
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: p.fg),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${prefs.messageFontSize.round()} px',
                              style: TalerTheme.tabularStyle(
                                size: 15,
                                weight: FontWeight.w500,
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
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'Скругление углов',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: p.fg),
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
              const SizedBox(height: 14),
              TalerSettingsGroup(
                title: 'Отображение',
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.settingsChat,
                    title: 'Узор на фоне чатов',
                    trailing: Switch(
                      value: prefs.showChatWallpaper,
                      onChanged: (v) => unawaited(prefs.setShowChatWallpaper(v)),
                    ),
                    onTap: () => unawaited(prefs.setShowChatWallpaper(!prefs.showChatWallpaper)),
                  ),
                  TalerSettingsTile(
                    icon: TalerIcons.settingsFolders,
                    title: 'Компактный список чатов',
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
          bodyBuilder: (controller, padding) => ListView(
            controller: controller,
            padding: padding,
            children: [
              TalerSettingsGroup(
                title: 'Индикация',
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.settingsSounds,
                    title: 'Показывать текст в уведомлениях',
                    trailing: Switch(
                      value: prefs.showNotificationPreview,
                      onChanged: (v) => unawaited(prefs.setShowNotificationPreview(v)),
                    ),
                    onTap: () => unawaited(
                      prefs.setShowNotificationPreview(!prefs.showNotificationPreview),
                    ),
                  ),
                  TalerSettingsTile(
                    icon: TalerIcons.settingsFolders,
                    title: 'Счётчики на папках чатов',
                    trailing: Switch(
                      value: prefs.showFolderBadges,
                      onChanged: (v) => unawaited(prefs.setShowFolderBadges(v)),
                    ),
                    onTap: () => unawaited(prefs.setShowFolderBadges(!prefs.showFolderBadges)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TalerSettingsGroup(
                title: 'Чаты без звука (${mutedChats.length})',
                children: mutedChats.isEmpty
                    ? [
                        const TalerSettingsTile(
                          icon: TalerIcons.bellOff,
                          title: 'Нет заглушённых чатов',
                        ),
                      ]
                    : [
                        for (final chat in mutedChats)
                          TalerSettingsTile(
                            icon: TalerIcons.bellOff,
                            title: chat.title,
                            valueText: 'Включить',
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

class TalerDataStoragePage extends StatelessWidget {
  final TalerClient client;

  const TalerDataStoragePage({super.key, required this.client});

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
          bodyBuilder: (controller, padding) => ListView(
            controller: controller,
            padding: padding,
            children: [
              TalerSettingsGroup(
                title: 'Хранилище',
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.settingsData,
                    title: 'Кэш сообщений и чатов',
                    subtitle: '${stats.chatsCount} чатов • ${stats.messagesCount} сообщений',
                    valueText: sizeText,
                  ),
                  TalerSettingsTile(
                    icon: TalerIcons.trash,
                    iconColor: p.danger,
                    title: 'Очистить кэш сообщений',
                    titleColor: p.danger,
                    onTap: () async {
                      final confirmed = await showTalerConfirmSheet(
                        context,
                        icon: TalerIcons.trash,
                        title: 'Очистить кэш?',
                        message:
                            'Локальная история сообщений будет удалена с устройства. Вы останетесь в аккаунте.',
                        confirmLabel: 'Очистить',
                      );
                      if (!confirmed || !context.mounted) return;
                      final removed = await client.clearMessageCache();
                      await TalerMediaCache.instance.clear();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Кэш очищен (удалено сообщений: $removed)')),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TalerSettingsGroup(
                title: 'Медиа',
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.image,
                    title: 'Автозагрузка изображений',
                    trailing: Switch(
                      value: prefs.autoDownloadMedia,
                      onChanged: (v) => unawaited(prefs.setAutoDownloadMedia(v)),
                    ),
                    onTap: () => unawaited(prefs.setAutoDownloadMedia(!prefs.autoDownloadMedia)),
                  ),
                  TalerSettingsTile(
                    icon: TalerIcons.trash,
                    title: 'Очистить кэш медиа и аватарок',
                    onTap: () async {
                      await TalerMediaCache.instance.clear();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Кэш изображений очищен')),
                      );
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
          bodyBuilder: (controller, padding) => ListView(
            controller: controller,
            padding: padding,
            children: [
              TalerSettingsGroup(
                title: 'Активные вкладки',
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.settingsFolders,
                    title: 'Все чаты',
                    valueText: '${client.chats.length}',
                  ),
                  for (final r in rows)
                    TalerSettingsTile(
                      icon: TalerIcons.settingsFolders,
                      title: r.title,
                      valueText: '${r.count}',
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TalerSettingsGroup(
                title: 'Отображение',
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.settingsSounds,
                    title: 'Счётчики непрочитанных',
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

class TalerDevicesPage extends StatelessWidget {
  final TalerClient client;

  const TalerDevicesPage({super.key, required this.client});

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
          bodyBuilder: (controller, padding) => ListView(
            controller: controller,
            padding: padding,
            children: [
              TalerSettingsGroup(
                title: 'Активные сеансы',
                children: sessions.isEmpty
                    ? [
                        TalerSettingsTile(
                          icon: TalerIcons.settingsDevices,
                          title: 'Текущее устройство',
                          subtitle: client.spoofingService.activeProfile.label,
                          valueText: 'Онлайн',
                        ),
                      ]
                    : [
                        for (final s in sessions) _sessionRow(s),
                      ],
              ),
              if (hasOthers) ...[
                const SizedBox(height: 14),
                TalerSettingsGroup(
                  children: [
                    TalerSettingsTile(
                      icon: TalerIcons.logOut,
                      iconColor: p.danger,
                      title: 'Завершить все остальные сеансы',
                      titleColor: p.danger,
                      onTap: () async {
                        final confirmed = await showTalerConfirmSheet(
                          context,
                          icon: TalerIcons.logOut,
                          title: 'Завершить сеансы?',
                          message:
                              'Все остальные устройства будут отключены от вашей учётной записи MAX.',
                          confirmLabel: 'Завершить',
                        );
                        if (confirmed) {
                          await client.terminateOtherSessions();
                        }
                      },
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

  Widget _sessionRow(TalerActiveSession s) {
    final icon = talerDeviceIconForClient(s.client);
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
      title: s.client,
      subtitle: details.isEmpty ? null : details,
      valueText: s.current ? 'Текущая' : null,
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
          bodyBuilder: (controller, padding) => ListView(
            controller: controller,
            padding: padding,
            children: [
              TalerSettingsGroup(
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.settingsPower,
                    title: 'Режим энергосбережения',
                    subtitle: 'Отключает размытие панелей и узор фона чатов',
                    trailing: Switch(
                      value: prefs.powerSavingMode,
                      onChanged: (v) => unawaited(prefs.setPowerSavingMode(v)),
                    ),
                    onTap: () => unawaited(prefs.setPowerSavingMode(!prefs.powerSavingMode)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TalerSettingsGroup(
                title: 'Параметры графики',
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.sunMoon,
                    title: 'Размытие верхней и нижней кромки',
                    valueText: prefs.powerSavingMode ? 'Откл' : 'Вкл',
                  ),
                  TalerSettingsTile(
                    icon: TalerIcons.palette,
                    title: 'Узор на фоне чатов',
                    valueText: prefs.powerSavingMode ? 'Откл' : 'Вкл',
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

class _UpdatePage extends StatefulWidget {
  final TalerClient client;

  const _UpdatePage({required this.client});

  @override
  State<_UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<_UpdatePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final updater = widget.client.updater;
      if (updater.status == UpdateStatus.idle) {
        unawaited(updater.checkForUpdates(silent: false));
      }
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 МБ';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} КБ';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  String _statusTitle(AppUpdater updater) {
    return switch (updater.status) {
      UpdateStatus.idle => 'Текущая версия',
      UpdateStatus.checking => 'Проверка обновлений...',
      UpdateStatus.upToDate => 'Установлена последняя версия',
      UpdateStatus.available => 'Доступно обновление',
      UpdateStatus.downloading => 'Скачивание обновления...',
      UpdateStatus.needsPermission => 'Требуется разрешение',
      UpdateStatus.readyToInstall => 'Готово к установке',
      UpdateStatus.error => 'Ошибка обновления',
    };
  }

  String _statusSubtitle(AppUpdater updater) {
    final release = updater.release;
    return switch (updater.status) {
      UpdateStatus.idle || UpdateStatus.upToDate => kTalerVersionLabel,
      UpdateStatus.checking => 'Подключение к GitHub Releases (grentu/Taler)',
      UpdateStatus.available => release?.matchedAsset != null
          ? '${release!.matchedAsset!.name} • ${_formatBytes(release.matchedAsset!.sizeBytes)}'
          : 'Доступен релиз ${release?.tag ?? ''}',
      UpdateStatus.downloading => updater.totalBytes > 0
          ? '${_formatBytes(updater.downloadedBytes)} / ${_formatBytes(updater.totalBytes)} • ${(updater.progress * 100).round()}%'
          : '${_formatBytes(updater.downloadedBytes)} загружено',
      UpdateStatus.needsPermission =>
        'Разрешите установку из этого источника в настройках Android и нажмите «Установить сейчас».',
      UpdateStatus.readyToInstall =>
        'Пакет загружен (${release?.tag ?? ''}). Нажмите «Установить сейчас».',
      UpdateStatus.error => updater.errorMessage ?? 'Не удалось выполнить обновление',
    };
  }

  TalerIconData _statusIcon(UpdateStatus status) {
    return switch (status) {
      UpdateStatus.available ||
      UpdateStatus.readyToInstall ||
      UpdateStatus.upToDate =>
        TalerIcons.badgeCheck,
      UpdateStatus.downloading => TalerIcons.arrowDownLeft,
      UpdateStatus.needsPermission || UpdateStatus.error => TalerIcons.alertCircle,
      UpdateStatus.checking => TalerIcons.refresh,
      UpdateStatus.idle => TalerIcons.info,
    };
  }

  void _copyLink(BuildContext context, String url) {
    unawaited(Clipboard.setData(ClipboardData(text: url)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ссылка на релиз скопирована'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final updater = widget.client.updater;
    final prefs = widget.client.appPreferences;
    return ListenableBuilder(
      listenable: Listenable.merge([updater, prefs]),
      builder: (context, _) {
        final p = TalerTheme.paletteOf(context);
        final status = updater.status;
        final release = updater.release;
        final isDownloading = status == UpdateStatus.downloading;
        final isChecking = status == UpdateStatus.checking;

        return _SettingsSubScaffold(
          title: 'Обновление Taler',
          bodyBuilder: (controller, padding) => ListView(
            controller: controller,
            padding: padding,
            children: [
              TalerSettingsGroup(
                children: [
                  TalerSettingsTile(
                    icon: _statusIcon(status),
                    title: _statusTitle(updater),
                    subtitle: _statusSubtitle(updater),
                    valueText: release != null ? 'v${release.version}' : null,
                  ),
                  if (isDownloading || isChecking)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(56, 2, 16, 14),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          value: isDownloading && updater.totalBytes > 0
                              ? updater.progress
                              : null,
                          backgroundColor: p.fg.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TalerSettingsGroup(
                children: [
                  if (isDownloading)
                    TalerSettingsTile(
                      icon: TalerIcons.close,
                      iconColor: p.danger,
                      title: 'Отменить загрузку',
                      titleColor: p.danger,
                      onTap: updater.cancelDownload,
                    )
                  else ...[
                    if (status == UpdateStatus.needsPermission ||
                        status == UpdateStatus.readyToInstall)
                      TalerSettingsTile(
                        icon: TalerIcons.check,
                        title: 'Установить сейчас',
                        valueText: release != null ? 'v${release.version}' : null,
                        onTap: () => unawaited(updater.downloadAndInstall()),
                      )
                    else if (status == UpdateStatus.available &&
                        release?.matchedAsset != null)
                      TalerSettingsTile(
                        icon: TalerIcons.arrowDownLeft,
                        title: 'Скачать и установить',
                        valueText: _formatBytes(release!.matchedAsset!.sizeBytes),
                        onTap: () => unawaited(updater.downloadAndInstall()),
                      ),
                    TalerSettingsTile(
                      icon: TalerIcons.refresh,
                      title: isChecking
                          ? 'Идёт проверка...'
                          : 'Проверить обновления',
                      onTap: isChecking
                          ? null
                          : () => unawaited(updater.checkForUpdates(silent: false)),
                    ),
                    if (release != null && release.htmlUrl.isNotEmpty)
                      TalerSettingsTile(
                        icon: TalerIcons.copy,
                        title: 'Скопировать ссылку на релиз',
                        onTap: () => _copyLink(context, release.htmlUrl),
                      ),
                  ],
                ],
              ),
              if (release != null && release.notes.isNotEmpty) ...[
                const SizedBox(height: 14),
                TalerSettingsGroup(
                  title: 'Что нового',
                  accentTitle: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: SelectableText(
                        release.notes,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: p.fg2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              TalerSettingsGroup(
                title: 'Параметры',
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.history,
                    title: 'Проверять при запуске',
                    subtitle: 'Фоновая проверка новых релизов на GitHub',
                    trailing: Switch(
                      value: prefs.autoCheckUpdates,
                      onChanged: (v) => unawaited(prefs.setAutoCheckUpdates(v)),
                    ),
                    onTap: () => unawaited(
                      prefs.setAutoCheckUpdates(!prefs.autoCheckUpdates),
                    ),
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

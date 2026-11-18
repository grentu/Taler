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
import '../widgets/photo_viewer_page.dart';
import '../widgets/settings_components.dart';

/// Экран профиля пользователя в чёрном стиле `exteraless`:
/// только личные данные аккаунта, описание «О себе» и быстрые действия профиля.
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

  Future<void> _openEditProfile({bool focusBio = false}) async {
    if (widget.client.currentUser == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => TalerEditProfilePage(
          client: widget.client,
          focusBio: focusBio,
        ),
      ),
    );
  }

  Future<void> _onTapAvatar(TalerUserProfile? user) async {
    final url = user?.avatarUrl;
    if (url != null && url.isNotEmpty) {
      await showTalerPhotoViewer(
        context,
        items: [
          TalerPhotoViewerItem(
            attachment: TalerAttachment(type: 'PHOTO', url: url),
            senderName: user?.fullName ?? 'Профиль',
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ),
        ],
      );
      return;
    }
    await _openEditProfile();
  }

  String _formatPhone(String? raw) {
    final parsed =
        raw != null ? int.tryParse(raw.replaceAll(RegExp(r'\D'), '')) : null;
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

  Future<void> _confirmLogout() async {
    final confirmed = await showTalerConfirmSheet(
      context,
      icon: TalerIcons.logOut,
      title: 'Выйти из аккаунта?',
      message:
          'Текущая сессия и локальная история чатов на этом устройстве будут очищены.',
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
      listenable:
          Listenable.merge([widget.client, widget.client.appPreferences]),
      builder: (context, _) {
        final isWide = MediaQuery.sizeOf(context).width >= 820;
        final statusTop = isWide ? 0.0 : MediaQuery.paddingOf(context).top;
        final user = widget.client.currentUser;
        final powerSaving = widget.client.appPreferences.powerSavingMode;
        final scrollTopPad = isWide ? 24.0 : statusTop + 14.0;
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
                          const SizedBox(height: 16),
                          _buildQuickActions(p, user),
                          const SizedBox(height: 16),
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
                              TalerSettingsTile(
                                icon: TalerIcons.info,
                                title: bio.isNotEmpty
                                    ? bio
                                    : 'Добавить описание',
                                titleColor: bio.isNotEmpty ? p.fg : p.fg3,
                                subtitle: 'О себе',
                                onTap: () => unawaited(
                                  _openEditProfile(focusBio: true),
                                ),
                              ),
                              if (user != null)
                                TalerSettingsTile(
                                  icon: TalerIcons.qrCode,
                                  title: 'ID: ${user.id}',
                                  subtitle: 'Идентификатор MAX',
                                  onTap: () => unawaited(
                                    _copyText(
                                      '${user.id}',
                                      'ID ${user.id} скопирован',
                                    ),
                                  ),
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
                  height: statusTop + 52 + 24,
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
                            onPressed: () => unawaited(_openEditProfile()),
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
    final online = isDemo ||
        widget.client.connectionState == TalerConnectionState.online;
    final statusText = isDemo
        ? 'Демо-режим'
        : (online ? 'В сети' : 'Синхронизация…');

    return Column(
      children: [
        GestureDetector(
          onTap: () => unawaited(_onTapAvatar(user)),
          child: TalerAvatar(
            seedId: user?.id ?? 0,
            initials: user?.initials ?? 'T',
            imageUrl: user?.avatarUrl,
            size: 96,
            isOnline: online,
            onlineBorderColor: p.settingsBg,
          ),
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
          statusText,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            color: online ? p.accent : p.fg3,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(TalerPalette p, TalerUserProfile? user) {
    return Row(
      children: [
        Expanded(
          child: _ProfileActionTile(
            icon: TalerIcons.pencil,
            label: 'Редактировать',
            onTap: () => unawaited(_openEditProfile()),
          ),
        ),
        if (user != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _ProfileActionTile(
              icon: TalerIcons.qrCode,
              label: 'Скопировать ID',
              onTap: () => unawaited(
                _copyText('${user.id}', 'ID ${user.id} скопирован'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ProfileActionTile extends StatelessWidget {
  final TalerIconData icon;
  final String label;
  final VoidCallback onTap;

  const _ProfileActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Material(
      color: p.isDark ? const Color(0xFF121215) : p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: p.isDark ? BorderSide.none : BorderSide(color: p.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: p.fg.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TalerIcon(icon, size: 20, color: p.accent),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: p.fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Полноэкранный редактор профиля в чёрном стиле `exteraless`:
/// позволяет изменить имя, фамилию и описание «О себе».
class TalerEditProfilePage extends StatefulWidget {
  final TalerClient client;
  final bool focusBio;

  const TalerEditProfilePage({
    super.key,
    required this.client,
    this.focusBio = false,
  });

  @override
  State<TalerEditProfilePage> createState() => _TalerEditProfilePageState();
}

class _TalerEditProfilePageState extends State<TalerEditProfilePage> {
  static const int _maxBioLength = 140;

  late final TextEditingController _firstCtrl;
  late final TextEditingController _lastCtrl;
  late final TextEditingController _bioCtrl;
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final user = widget.client.currentUser;
    _firstCtrl = TextEditingController(text: user?.firstName ?? '');
    _lastCtrl = TextEditingController(text: user?.lastName ?? '');
    _bioCtrl = TextEditingController(text: user?.description ?? '');
    _firstCtrl.addListener(_onFieldChanged);
    _lastCtrl.addListener(_onFieldChanged);
    _bioCtrl.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _firstCtrl
      ..removeListener(_onFieldChanged)
      ..dispose();
    _lastCtrl
      ..removeListener(_onFieldChanged)
      ..dispose();
    _bioCtrl
      ..removeListener(_onFieldChanged)
      ..dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) {
      setState(() {
        if (_errorText != null) _errorText = null;
      });
    }
  }

  String get _liveFullName {
    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    final combined = [first, last].where((s) => s.isNotEmpty).join(' ');
    return combined.isEmpty ? 'Без имени' : combined;
  }

  String get _liveInitials {
    final parts = _liveFullName
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'T';
    String firstRune(String s) => String.fromCharCode(s.runes.first).toUpperCase();
    if (parts.length == 1) return firstRune(parts.first);
    return '${firstRune(parts[0])}${firstRune(parts[1])}';
  }

  bool get _canSave => !_saving && _firstCtrl.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) return;
    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    final bio = _bioCtrl.text.trim();
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await widget.client.updateProfile(
        firstName: first,
        lastName: last.isEmpty ? null : last,
        description: bio.isEmpty ? null : bio,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = 'Не удалось сохранить изменения';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final user = widget.client.currentUser;
    final padTop = MediaQuery.paddingOf(context).top;
    final padBottom = MediaQuery.paddingOf(context).bottom;
    final powerSaving = widget.client.appPreferences.powerSavingMode;
    final bioRemaining = (_maxBioLength - _bioCtrl.text.characters.length)
        .clamp(0, _maxBioLength);

    return Scaffold(
      backgroundColor: p.settingsBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                14,
                padTop + 66,
                14,
                padBottom + 24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: TalerAvatar(
                          seedId: user?.id ?? 0,
                          initials: _liveInitials,
                          imageUrl: user?.avatarUrl,
                          size: 86,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _liveFullName,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: p.fg,
                        ),
                      ),
                      const SizedBox(height: 22),
                      TalerSettingsGroup(
                        title: 'Имя и фамилия',
                        accentTitle: true,
                        showDividers: true,
                        children: [
                          _EditFieldRow(
                            controller: _firstCtrl,
                            label: 'Имя',
                            hint: 'Введите имя',
                            autofocus: !widget.focusBio,
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 64,
                          ),
                          _EditFieldRow(
                            controller: _lastCtrl,
                            label: 'Фамилия',
                            hint: 'Необязательно',
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 64,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TalerSettingsGroup(
                        title: 'О себе',
                        accentTitle: true,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  controller: _bioCtrl,
                                  autofocus: widget.focusBio,
                                  minLines: 2,
                                  maxLines: 5,
                                  maxLength: _maxBioLength,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    height: 1.4,
                                    color: p.fg,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Расскажите немного о себе…',
                                    hintStyle: TextStyle(
                                      fontSize: 15.5,
                                      color: p.fg3,
                                    ),
                                    counterText: '',
                                    filled: false,
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (_bioCtrl.text.isNotEmpty)
                                      GestureDetector(
                                        onTap: _bioCtrl.clear,
                                        child: Text(
                                          'Очистить',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                            color: p.fg3,
                                          ),
                                        ),
                                      )
                                    else
                                      const SizedBox.shrink(),
                                    Text(
                                      '$bioRemaining',
                                      style: TalerTheme.tabularStyle(
                                        size: 12,
                                        color: bioRemaining <= 15
                                            ? p.danger
                                            : p.fg3,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          'Любые подробности о вас — например, город, род занятий или интересы.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: p.fg3,
                          ),
                        ),
                      ),
                      if (_errorText != null) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            _errorText!,
                            style: TextStyle(fontSize: 13.5, color: p.danger),
                          ),
                        ),
                      ],
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
            child: TalerTopFadeOverlay(
              height: padTop + 56 + 20,
              backgroundColor: p.settingsBg,
              factor: 1.0,
              powerSaving: powerSaving,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      TalerIconButton(
                        icon: TalerIcons.arrowLeft,
                        tooltip: 'Назад',
                        iconSize: 22,
                        color: p.fg,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Редактировать профиль',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: p.fg,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedOpacity(
                        opacity: _canSave ? 1.0 : 0.42,
                        duration: const Duration(milliseconds: 160),
                        child: Material(
                          color: p.accent,
                          borderRadius: BorderRadius.circular(999),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: _canSave ? () => unawaited(_save()) : null,
                            splashFactory: NoSplash.splashFactory,
                            child: SizedBox(
                              height: 34,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                child: Center(
                                  child: _saving
                                      ? const SizedBox(
                                          width: 15,
                                          height: 15,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Сохранить',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
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

class _EditFieldRow extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool autofocus;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final int maxLength;

  const _EditFieldRow({
    required this.controller,
    required this.label,
    required this.hint,
    required this.textInputAction,
    required this.textCapitalization,
    required this.maxLength,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                color: p.fg3,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              textInputAction: textInputAction,
              textCapitalization: textCapitalization,
              maxLength: maxLength,
              style: TextStyle(fontSize: 15.5, color: p.fg),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 15.5, color: p.fg3),
                counterText: '',
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            TalerIconButton(
              icon: TalerIcons.close,
              tooltip: 'Очистить',
              size: 32,
              iconSize: 14,
              color: p.fg3,
              onPressed: controller.clear,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

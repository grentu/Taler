import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/platform/taler_native_bridge.dart';
import '../../core/storage/taler_models.dart';
import '../../core/transport/taler_session.dart';
import '../../core/update/app_updater.dart';
import '../icons/taler_icon.dart';
import '../theme/chat_tokens.dart';
import '../theme/taler_theme.dart';
import '../widgets/chat_list_pane.dart';
import '../widgets/message_bubble.dart';
import 'chat_screen.dart';
import 'privacy_shield_screen.dart';
import 'profile_settings_screen.dart';
import 'settings_screen.dart';

/// Главный экран. Компьютер: узкое меню слева, список чатов, переписка и профиль.
/// Телефон: список чатов на весь экран и плавающее меню-островок снизу.
class HomeScreen extends StatefulWidget {
  final TalerClient client;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const HomeScreen({
    super.key,
    required this.client,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _dockSpace = 100;
  final _rootFocus = FocusNode(debugLabel: 'home_root');
  StreamSubscription<int>? _notifTapSub;

  int _tab = 0;
  int? _selectedChatId;

  @override
  void initState() {
    super.initState();
    _notifTapSub = TalerNativeBridge.instance.onNotificationTap.listen(
      _openChatById,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final client = widget.client;
      if (client.appPreferences.autoCheckUpdates &&
          client.updater.status == UpdateStatus.idle) {
        unawaited(client.updater.checkForUpdates(silent: true));
      }
      unawaited(_initNotifications());
    });
  }

  Future<void> _initNotifications() async {
    await TalerNativeBridge.instance.requestNotificationPermission();
    final initialChatId =
        await TalerNativeBridge.instance.consumeInitialNotificationChatId();
    if (initialChatId != null && mounted) {
      _openChatById(initialChatId);
    }
  }

  void _openChatById(int chatId) {
    if (!mounted) return;
    final chat = widget.client.store.chats[chatId];
    if (chat == null) return;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      setState(() {
        _tab = 0;
        _selectedChatId = chat.id;
      });
    } else {
      setState(() => _tab = 0);
      _openMobileChat(chat);
    }
  }

  @override
  void dispose() {
    _notifTapSub?.cancel();
    _rootFocus.dispose();
    super.dispose();
  }

  void _releaseKeyboardFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_rootFocus.canRequestFocus) {
      _rootFocus.requestFocus();
    }
  }

  void _toggleTheme(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    widget.onThemeModeChanged(dark ? ThemeMode.light : ThemeMode.dark);
  }

  void _openMobileChat(TalerChat chat) {
    _releaseKeyboardFocus();
    final client = widget.client;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (ctx) => Scaffold(
              backgroundColor: ChatTokens.chatBackground(TalerTheme.paletteOf(ctx)),
              body: ChatScreen(client: client, chat: chat, showBackButton: true),
            ),
          ),
        )
        .whenComplete(() {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _releaseKeyboardFocus();
          });
        });
  }

  void _selectTab(int index) {
    _releaseKeyboardFocus();
    setState(() => _tab = index);
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    return ListenableBuilder(
      listenable: Listenable.merge([
        client,
        client.privacySettings,
        client.updater,
      ]),
      builder: (context, _) {
        final p = TalerTheme.paletteOf(context);
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final unread = client.chats.where((c) => c.unreadCount > 0 && !c.isMuted).length;
        final online = client.isDemoMode || client.connectionState == TalerConnectionState.online;
        final hasUpdate = client.updater.hasUpdate;
        final settings = SettingsScreen(
          client: client,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onOpenShield: () => _selectTab(1),
          onOpenProfile: () => _selectTab(3),
          bottomInset: wide ? 24 : _dockSpace,
        );
        final profile = ProfileSettingsScreen(
          client: client,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onOpenSettings: () => _selectTab(2),
          onOpenShield: () => _selectTab(1),
          bottomInset: wide ? 24 : _dockSpace,
        );

        if (wide) {
          return PopScope(
            canPop: _tab == 0 && _selectedChatId == null,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (_tab != 0) {
                _selectTab(0);
              } else if (_selectedChatId != null) {
                setState(() => _selectedChatId = null);
              }
            },
            child: Scaffold(
              backgroundColor: p.bg,
              body: Row(
                children: [
                  _Rail(
                    selected: _tab,
                    unread: unread,
                    hasUpdate: hasUpdate,
                    isDark: p.isDark,
                    user: client.currentUser,
                    online: online,
                    onSelect: _selectTab,
                    onToggleTheme: () => _toggleTheme(context),
                    onLogout: () => client.logout(),
                  ),
                  Expanded(
                    child: switch (_tab) {
                      0 => _desktopChats(p),
                      1 => PrivacyShieldScreen(client: client, bottomInset: 24),
                      2 => settings,
                      _ => profile,
                    },
                  ),
                ],
              ),
            ),
          );
        }

        final bottom = MediaQuery.paddingOf(context).bottom;
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final listBottomInset = math.max(_dockSpace + bottom, keyboard + 12);
        return PopScope(
          canPop: _tab == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _tab != 0) {
              _selectTab(0);
            }
          },
          child: Focus(
            focusNode: _rootFocus,
            child: Scaffold(
              backgroundColor: p.settingsBg,
              resizeToAvoidBottomInset: false,
              body: Stack(
                children: [
                  Positioned.fill(
                    child: switch (_tab) {
                      0 => ChatListPane(
                          client: client,
                          compact: true,
                          bottomInset: listBottomInset,
                          onOpen: _openMobileChat,
                        ),
                      1 => PrivacyShieldScreen(
                          client: client,
                          bottomInset: _dockSpace + bottom,
                        ),
                      2 => SettingsScreen(
                          client: client,
                          themeMode: widget.themeMode,
                          onThemeModeChanged: widget.onThemeModeChanged,
                          onOpenShield: () => _selectTab(1),
                          onOpenProfile: () => _selectTab(3),
                          bottomInset: _dockSpace + bottom,
                        ),
                      _ => ProfileSettingsScreen(
                          client: client,
                          themeMode: widget.themeMode,
                          onThemeModeChanged: widget.onThemeModeChanged,
                          onOpenSettings: () => _selectTab(2),
                          onOpenShield: () => _selectTab(1),
                          bottomInset: _dockSpace + bottom,
                        ),
                    },
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12 + bottom,
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        client.appPreferences,
                        client.updater,
                      ]),
                      builder: (context, _) => _Dock(
                        selected: _tab,
                        unread: unread,
                        hasUpdate: client.updater.hasUpdate,
                        user: client.currentUser,
                        powerSaving: client.appPreferences.powerSavingMode,
                        onSelect: _selectTab,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _desktopChats(TalerPalette p) {
    final client = widget.client;
    TalerChat? selected;
    final id = _selectedChatId;
    if (id != null) selected = client.store.chats[id];
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(border: Border(right: BorderSide(color: p.line))),
          child: SizedBox(
            width: 360,
            child: ChatListPane(
              client: client,
              selectedChatId: _selectedChatId,
              onOpen: (chat) => setState(() => _selectedChatId = chat.id),
            ),
          ),
        ),
        Expanded(
          child: selected != null
              ? ChatScreen(key: ValueKey(selected.id), client: client, chat: selected)
              : ColoredBox(
                  color: ChatTokens.chatBackground(p),
                  child: const Center(child: ChatDayChip(label: 'Выберите чат')),
                ),
        ),
      ],
    );
  }
}

/// Узкое меню слева на компьютере.
class _Rail extends StatelessWidget {
  final int selected;
  final int unread;
  final bool hasUpdate;
  final bool isDark;
  final TalerUserProfile? user;
  final bool online;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggleTheme;
  final VoidCallback onLogout;

  const _Rail({
    required this.selected,
    required this.unread,
    this.hasUpdate = false,
    required this.isDark,
    required this.user,
    required this.online,
    required this.onSelect,
    required this.onToggleTheme,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Container(
      width: 68,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: p.settingsBg, border: Border(right: BorderSide(color: p.line))),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.fg, borderRadius: BorderRadius.circular(12)),
            child: Text('T', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.bg)),
          ),
          const SizedBox(height: 12),
          _RailButton(icon: selected == 0 ? TalerIcons.chatsActive : TalerIcons.messageCircle, label: 'Чаты', selected: selected == 0, badge: unread, onTap: () => onSelect(0)),
          _RailButton(icon: selected == 1 ? TalerIcons.shieldCheck : TalerIcons.shield, label: 'Защита', selected: selected == 1, onTap: () => onSelect(1)),
          _RailButton(
            icon: selected == 2 ? TalerIcons.settingsActive : TalerIcons.settings,
            iconWidget: _AnimatedSettingsIcon(
              selected: selected == 2,
              size: 20,
              color: selected == 2 ? p.fg : p.fg3,
            ),
            label: 'Настройки',
            selected: selected == 2,
            dotBadge: hasUpdate,
            onTap: () => onSelect(2),
          ),
          _RailButton(icon: TalerIcons.user, label: 'Профиль', selected: selected == 3, onTap: () => onSelect(3)),
          const Spacer(),
          _RailButton(
            icon: isDark ? TalerIcons.sun : TalerIcons.moon,
            label: isDark ? 'Светлая тема' : 'Тёмная тема',
            onTap: onToggleTheme,
          ),
          _RailButton(icon: TalerIcons.logOut, label: 'Выйти', onTap: onLogout),
          const SizedBox(height: 8),
          Tooltip(
            message: 'Профиль',
            child: InkWell(
              onTap: () => onSelect(3),
              borderRadius: BorderRadius.circular(999),
              child: TalerAvatar(
                seedId: user?.id ?? 0,
                initials: user?.initials ?? 'T',
                imageUrl: user?.avatarUrl,
                size: 36,
                isOnline: online,
                onlineBorderColor: p.settingsBg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final TalerIconData icon;
  final Widget? iconWidget;
  final String label;
  final bool selected;
  final int badge;
  final bool dotBadge;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconWidget,
    this.selected = false,
    this.badge = 0,
    this.dotBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 400),
        child: Material(
          color: selected ? ChatTokens.active(p) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            hoverColor: ChatTokens.hover(p),
            splashFactory: NoSplash.splashFactory,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(child: iconWidget ?? TalerIcon(icon, size: 20, color: selected ? p.fg : p.fg3)),
                  if (badge > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: _Badge(count: badge, ring: p.settingsBg),
                    )
                  else if (dotBadge)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: _UpdateDot(ring: p.settingsBg),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateDot extends StatelessWidget {
  final Color ring;

  const _UpdateDot({required this.ring});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: p.accent,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 1.5),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;
  final Color ring;

  const _Badge({required this.count, required this.ring});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.accent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ring, width: 2),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TalerTheme.tabularStyle(size: 10, weight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}

/// Плавающее меню-островок: почти чёрное стекло с размытием и пружинной пилюлей.
class _Dock extends StatefulWidget {
  final int selected;
  final int unread;
  final bool hasUpdate;
  final TalerUserProfile? user;
  final bool powerSaving;
  final ValueChanged<int> onSelect;

  const _Dock({
    required this.selected,
    required this.unread,
    this.hasUpdate = false,
    required this.user,
    required this.onSelect,
    this.powerSaving = false,
  });

  @override
  State<_Dock> createState() => _DockState();
}

class _DockState extends State<_Dock> with SingleTickerProviderStateMixin {
  late final AnimationController _pillCtrl;
  double _fromTab = 0;
  double _toTab = 0;

  @override
  void initState() {
    super.initState();
    _fromTab = widget.selected.toDouble();
    _toTab = widget.selected.toDouble();
    _pillCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
      value: 1.0,
    );
  }

  double _currentPos() {
    final raw = _pillCtrl.value;
    final t = const _DockSpringCurve().transform(raw);
    return ui.lerpDouble(_fromTab, _toTab, t) ?? _toTab;
  }

  @override
  void didUpdateWidget(covariant _Dock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      final reduceMotion =
          widget.powerSaving || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
      _fromTab = _currentPos();
      _toTab = widget.selected.toDouble();
      if (reduceMotion) {
        _fromTab = _toTab;
        _pillCtrl.value = 1.0;
      } else {
        _pillCtrl.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _pillCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final selected = widget.selected;
    final unread = widget.unread;
    final hasUpdate = widget.hasUpdate;
    final user = widget.user;
    final powerSaving = widget.powerSaving;
    final onSelect = widget.onSelect;
    final disableAnim =
        powerSaving || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

    final glass = p.isDark
        ? Color(powerSaving ? 0xF718181A : 0xE618181A)
        : Color(powerSaving ? 0xF7FAFAFA : 0xC7FAFAFA);
    final solid = p.isDark ? const Color(0xFF18181A) : const Color(0xFFF4F4F5);
    final border = p.isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.07);
    final pillFill = p.fg.withValues(alpha: p.isDark ? 0.095 : 0.085);
    final pillRim = p.fg.withValues(alpha: p.isDark ? 0.08 : 0.06);

    final inner = Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: glass,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final slotW = maxW / 4;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _pillCtrl,
                  builder: (context, _) {
                    final raw = _pillCtrl.value.clamp(0.0, 1.0);
                    final curved = _pillCtrl.isAnimating
                        ? const _DockSpringCurve().transform(raw)
                        : 1.0;
                    final pos = ui.lerpDouble(_fromTab, _toTab, curved) ?? _toTab;
                    final travel = (_toTab - _fromTab).abs();
                    final stretch = disableAnim || !_pillCtrl.isAnimating
                        ? 0.0
                        : math.sin(math.pi * raw) * math.min(18.0, travel * 6.5);
                    final pillW = math.max(0.0, slotW + stretch);
                    final maxLeft = math.max(0.0, maxW - pillW);
                    final left = (pos * slotW + slotW / 2 - pillW / 2).clamp(0.0, maxLeft);

                    return Stack(
                      children: [
                        Positioned(
                          left: left,
                          top: 0,
                          bottom: 0,
                          width: pillW,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: pillFill,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: pillRim, width: 0.75),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _DockItem(
                      label: 'Чаты',
                      selected: selected == 0,
                      disableAnimations: disableAnim,
                      onTap: () => onSelect(0),
                      badge: unread > 0 ? _Badge(count: unread, ring: solid) : null,
                      icon: TalerIcon(
                        selected == 0 ? TalerIcons.chatsActive : TalerIcons.messageCircle,
                        size: 24,
                        color: selected == 0 ? p.accent : p.fg,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _DockItem(
                      label: 'Защита',
                      selected: selected == 1,
                      disableAnimations: disableAnim,
                      onTap: () => onSelect(1),
                      icon: TalerIcon(
                        selected == 1 ? TalerIcons.shieldCheck : TalerIcons.shield,
                        size: 24,
                        color: selected == 1 ? p.accent : p.fg,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _DockItem(
                      label: 'Настройки',
                      selected: selected == 2,
                      disableAnimations: disableAnim,
                      onTap: () => onSelect(2),
                      badge: hasUpdate ? _UpdateDot(ring: solid) : null,
                      icon: _AnimatedSettingsIcon(
                        selected: selected == 2,
                        disableAnimations: disableAnim,
                        size: 24,
                        color: selected == 2 ? p.accent : p.fg,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _DockItem(
                      label: 'Профиль',
                      selected: selected == 3,
                      disableAnimations: disableAnim,
                      onTap: () => onSelect(3),
                      icon: _AnimatedProfileIcon(
                        selected: selected == 3,
                        disableAnimations: disableAnim,
                        accentColor: p.accent,
                        user: user,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 30, offset: Offset(0, 10), spreadRadius: -10)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: powerSaving
            ? inner
            : BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: inner,
              ),
      ),
    );
  }
}

class _DockItem extends StatefulWidget {
  final String label;
  final bool selected;
  final bool disableAnimations;
  final VoidCallback onTap;
  final Widget icon;
  final Widget? badge;

  const _DockItem({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.icon,
    this.disableAnimations = false,
    this.badge,
  });

  @override
  State<_DockItem> createState() => _DockItemState();
}

class _DockItemState extends State<_DockItem> with TickerProviderStateMixin {
  late final AnimationController _bounceCtrl;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void didUpdateWidget(covariant _DockItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.selected && widget.selected && !widget.disableAnimations) {
      _bounceCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final b = widget.badge;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        if (!widget.disableAnimations) setState(() => _pressed = true);
      },
      onTapUp: (_) {
        if (_pressed) setState(() => _pressed = false);
      },
      onTapCancel: () {
        if (_pressed) setState(() => _pressed = false);
      },
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          height: 54,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 28,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _bounceCtrl,
                      builder: (context, child) {
                        final raw = _bounceCtrl.value;
                        final pop = _bounceCtrl.isAnimating
                            ? 1.0 + math.sin(math.pi * raw) * 0.11 * (1.0 - raw * 0.35)
                            : 1.0;
                        return Transform.scale(scale: pop, child: child);
                      },
                      child: widget.icon,
                    ),
                    Positioned(
                      left: 16,
                      top: b is _UpdateDot ? 0 : -4,
                      child: AnimatedSwitcher(
                        duration: widget.disableAnimations
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: ScaleTransition(scale: anim, child: child),
                        ),
                        child: b == null
                            ? const SizedBox.shrink(key: ValueKey('no_badge'))
                            : KeyedSubtree(
                                key: ValueKey(b is _UpdateDot ? 'dot' : 'count'),
                                child: b,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: widget.disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: widget.selected ? p.accent : p.fg,
                ),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Анимированная шестерёнка настроек: морфинг контура -> заливка + пружинный поворот на зубец (60°).
class _AnimatedSettingsIcon extends StatefulWidget {
  final bool selected;
  final bool disableAnimations;
  final double size;
  final Color color;

  const _AnimatedSettingsIcon({
    required this.selected,
    required this.size,
    required this.color,
    this.disableAnimations = false,
  });

  @override
  State<_AnimatedSettingsIcon> createState() => _AnimatedSettingsIconState();
}

class _AnimatedSettingsIconState extends State<_AnimatedSettingsIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      value: widget.selected ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant _AnimatedSettingsIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      if (widget.disableAnimations ||
          (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
        _ctrl.value = widget.selected ? 1.0 : 0.0;
      } else if (widget.selected) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final raw = _ctrl.value;
        final curved = _ctrl.isAnimating
            ? const _DockSpringCurve().transform(raw)
            : raw;
        final angle = (math.pi / 3) * curved;
        final pulse = _ctrl.isAnimating ? 1.0 + 0.07 * math.sin(math.pi * raw) : 1.0;
        return Transform.rotate(
          angle: angle,
          child: Transform.scale(scale: pulse, child: child),
        );
      },
      child: TalerIcon(
        widget.selected ? TalerIcons.settingsActive : TalerIcons.settings,
        size: widget.size,
        color: widget.color,
      ),
    );
  }
}

/// Анимация вкладки «Профиль»: spring-pop + микро-наклон аватара, прорисовывающееся кольцо и волна.
class _AnimatedProfileIcon extends StatefulWidget {
  final bool selected;
  final bool disableAnimations;
  final Color accentColor;
  final TalerUserProfile? user;

  const _AnimatedProfileIcon({
    required this.selected,
    required this.accentColor,
    required this.user,
    this.disableAnimations = false,
  });

  @override
  State<_AnimatedProfileIcon> createState() => _AnimatedProfileIconState();
}

class _AnimatedProfileIconState extends State<_AnimatedProfileIcon>
    with TickerProviderStateMixin {
  late final AnimationController _ringCtrl;
  late final AnimationController _popCtrl;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      value: widget.selected ? 1.0 : 0.0,
    );
    _popCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
  }

  @override
  void didUpdateWidget(covariant _AnimatedProfileIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      final noAnim = widget.disableAnimations ||
          (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
      if (noAnim) {
        _ringCtrl.value = widget.selected ? 1.0 : 0.0;
        _popCtrl.value = 0.0;
      } else if (widget.selected) {
        _ringCtrl.forward();
        _popCtrl.forward(from: 0.0);
      } else {
        _ringCtrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    _popCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 27,
      height: 27,
      child: AnimatedBuilder(
        animation: Listenable.merge([_ringCtrl, _popCtrl]),
        builder: (context, avatarChild) {
          final ringProgress = Curves.easeOutCubic.transform(_ringCtrl.value);
          final popT = _popCtrl.value;
          final isPopping = _popCtrl.isAnimating;

          final avatarScale = isPopping
              ? 1.0 + math.sin(math.pi * popT) * 0.14 * (1.0 - popT * 0.3)
              : 1.0;
          final tilt = isPopping
              ? math.sin(2.0 * math.pi * popT) * math.exp(-4.0 * popT) * 0.14
              : 0.0;
          final waveScale = 1.0 + popT * 0.45;
          final waveAlpha = isPopping ? (1.0 - popT).clamp(0.0, 1.0) * 0.48 : 0.0;

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (waveAlpha > 0.01)
                Transform.scale(
                  scale: waveScale,
                  child: Container(
                    width: 27,
                    height: 27,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.accentColor.withValues(alpha: waveAlpha),
                        width: 1.5 * (1.0 - popT * 0.5),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _ProfileRingPainter(
                    progress: ringProgress,
                    color: widget.accentColor,
                  ),
                ),
              ),
              Transform.rotate(
                angle: tilt,
                child: Transform.scale(
                  scale: avatarScale,
                  child: avatarChild,
                ),
              ),
            ],
          );
        },
        child: TalerAvatar(
          seedId: widget.user?.id ?? 0,
          initials: widget.user?.initials ?? 'T',
          imageUrl: widget.user?.avatarUrl,
          size: 22,
        ),
      ),
    );
  }
}

class _ProfileRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _ProfileRingPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.01) return;
    final stroke = 1.8;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final paint = Paint()
      ..color = color.withValues(alpha: (progress * 1.4).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProfileRingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Упругая пружина (stiffness ~ 210, damping ~ 0.64) для островка и шестерёнки.
class _DockSpringCurve extends Curve {
  const _DockSpringCurve();

  static const double _zeta = 0.64;
  static const double _omega = 14.5;
  static const double _seconds = 0.46;

  @override
  double transformInternal(double t) {
    final omegaD = _omega * math.sqrt(1 - _zeta * _zeta);
    final s = t * _seconds;
    final decay = math.exp(-_zeta * _omega * s);
    return 1 -
        decay *
            (math.cos(omegaD * s) +
                (_zeta * _omega / omegaD) * math.sin(omegaD * s));
  }
}

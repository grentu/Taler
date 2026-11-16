import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/storage/taler_models.dart';
import '../../core/transport/taler_session.dart';
import '../icons/taler_icon.dart';
import '../theme/chat_tokens.dart';
import '../theme/taler_theme.dart';
import '../widgets/chat_list_pane.dart';
import '../widgets/message_bubble.dart';
import 'chat_screen.dart';
import 'privacy_shield_screen.dart';
import 'profile_settings_screen.dart';

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

  int _tab = 0;
  int? _selectedChatId;

  @override
  void dispose() {
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
              backgroundColor: TalerTheme.paletteOf(ctx).bg2,
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
      listenable: Listenable.merge([client, client.privacySettings]),
      builder: (context, _) {
        final p = TalerTheme.paletteOf(context);
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final unread = client.chats.where((c) => c.unreadCount > 0 && !c.isMuted).length;
        final online = client.isDemoMode || client.connectionState == TalerConnectionState.online;
        final settings = ProfileSettingsScreen(
          client: client,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
        );

        if (wide) {
          return Scaffold(
            backgroundColor: p.bg,
            body: Row(
              children: [
                _Rail(
                  selected: _tab,
                  unread: unread,
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
                    1 => PrivacyShieldScreen(client: client),
                    _ => settings,
                  },
                ),
              ],
            ),
          );
        }

        final bottom = MediaQuery.paddingOf(context).bottom;
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final listBottomInset = math.max(_dockSpace, keyboard + 12);
        return Focus(
          focusNode: _rootFocus,
          child: Scaffold(
            backgroundColor: p.bg2,
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
                    _ => ProfileSettingsScreen(
                        client: client,
                        themeMode: widget.themeMode,
                        onThemeModeChanged: widget.onThemeModeChanged,
                        bottomInset: _dockSpace + bottom,
                      ),
                  },
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12 + bottom,
                  child: _Dock(
                    selected: _tab,
                    unread: unread,
                    user: client.currentUser,
                    onSelect: _selectTab,
                  ),
                ),
              ],
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
  final bool isDark;
  final TalerUserProfile? user;
  final bool online;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggleTheme;
  final VoidCallback onLogout;

  const _Rail({
    required this.selected,
    required this.unread,
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
          _RailButton(icon: TalerIcons.messageCircle, label: 'Чаты', selected: selected == 0, badge: unread, onTap: () => onSelect(0)),
          _RailButton(icon: TalerIcons.shieldCheck, label: 'Защита', selected: selected == 1, onTap: () => onSelect(1)),
          _RailButton(icon: TalerIcons.settings, label: 'Настройки', selected: selected == 2, onTap: () => onSelect(2)),
          const Spacer(),
          _RailButton(
            icon: isDark ? TalerIcons.sun : TalerIcons.moon,
            label: isDark ? 'Светлая тема' : 'Тёмная тема',
            onTap: onToggleTheme,
          ),
          _RailButton(icon: TalerIcons.logOut, label: 'Выйти', onTap: onLogout),
          const SizedBox(height: 8),
          TalerAvatar(
            seedId: user?.id ?? 0,
            initials: user?.initials ?? 'T',
            imageUrl: user?.avatarUrl,
            size: 36,
            isOnline: online,
            onlineBorderColor: p.settingsBg,
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final TalerIconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.badge = 0,
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
                  Center(child: TalerIcon(icon, size: 20, color: selected ? p.fg : p.fg3)),
                  if (badge > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: _Badge(count: badge, ring: p.settingsBg),
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

/// Плавающее меню-островок: почти чёрное стекло с размытием, как в Telegram.
class _Dock extends StatelessWidget {
  final int selected;
  final int unread;
  final TalerUserProfile? user;
  final ValueChanged<int> onSelect;

  const _Dock({required this.selected, required this.unread, required this.user, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final glass = p.isDark ? const Color(0xE618181A) : const Color(0xC7FAFAFA);
    final solid = p.isDark ? const Color(0xFF18181A) : const Color(0xFFF4F4F5);
    final border = p.isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.07);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 30, offset: Offset(0, 10), spreadRadius: -10)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: glass,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _DockItem(
                    label: 'Чаты',
                    selected: selected == 0,
                    onTap: () => onSelect(0),
                    badge: unread > 0 ? _Badge(count: unread, ring: solid) : null,
                    icon: TalerIcon(TalerIcons.messageCircle, size: 26, color: selected == 0 ? p.accent : p.fg),
                  ),
                ),
                Expanded(
                  child: _DockItem(
                    label: 'Защита',
                    selected: selected == 1,
                    onTap: () => onSelect(1),
                    icon: TalerIcon(TalerIcons.shieldCheck, size: 26, color: selected == 1 ? p.accent : p.fg),
                  ),
                ),
                Expanded(
                  child: _DockItem(
                    label: 'Профиль',
                    selected: selected == 2,
                    onTap: () => onSelect(2),
                    icon: Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: selected == 2 ? p.accent : Colors.transparent, width: 1.5),
                      ),
                      child: TalerAvatar(
                        seedId: user?.id ?? 0,
                        initials: user?.initials ?? 'T',
                        imageUrl: user?.avatarUrl,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget icon;
  final Widget? badge;

  const _DockItem({required this.label, required this.selected, required this.onTap, required this.icon, this.badge});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final b = badge;
    return Material(
      color: selected ? p.fg.withValues(alpha: 0.08) : Colors.transparent,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        splashFactory: NoSplash.splashFactory,
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
                    icon,
                    if (b != null) Positioned(left: 16, top: -4, child: b),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: selected ? p.accent : p.fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

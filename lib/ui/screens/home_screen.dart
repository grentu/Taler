import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/storage/taler_models.dart';
import '../../core/transport/taler_session.dart';
import '../theme/taler_theme.dart';
import '../widgets/taler_logo.dart';
import 'chat_screen.dart';
import 'privacy_shield_screen.dart';
import 'profile_settings_screen.dart';

/// Главный адаптивный экран Taler в стиле Telegram Desktop (3 колонки)
/// и Telegram Mobile.
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
  final _searchCtrl = TextEditingController();
  int _navIndex = 0;
  String _selectedFolderId = 'all';
  String _searchQuery = '';
  int? _selectedChatId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.client,
        widget.client.privacySettings,
        widget.client.spoofingService,
      ]),
      builder: (context, _) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final isWide = screenWidth >= 820;
        final blockedCount = widget.client.privacySettings.blockedPacketsCount;
        final totalUnread = widget.client.chats.fold<int>(
          0,
          (sum, c) => sum + c.unreadCount,
        );
        final ghost = widget.client.privacySettings.ghostModeOnline;

        if (isWide) {
          return Scaffold(
            backgroundColor: p.bg,
            body: Row(
              children: [
                _TelegramDesktopRail(
                  selectedIndex: _navIndex,
                  blockedCount: blockedCount,
                  unreadCount: totalUnread,
                  ghostMode: ghost,
                  isDark: Theme.of(context).brightness == Brightness.dark,
                  connectionState: widget.client.connectionState,
                  isDemo: widget.client.isDemoMode,
                  onSelect: (idx) => setState(() => _navIndex = idx),
                  onToggleGhost: () {
                    widget.client.privacySettings.setGhostModeOnline(!ghost);
                    widget.client.session.sendPing();
                  },
                  onToggleTheme: () {
                    final next =
                        Theme.of(context).brightness == Brightness.dark
                            ? ThemeMode.light
                            : ThemeMode.dark;
                    widget.onThemeModeChanged(next);
                  },
                  onLogout: () => widget.client.logout(),
                ),
                VerticalDivider(width: 1, thickness: 1, color: p.line),
                Expanded(
                  child: switch (_navIndex) {
                    0 => _buildDesktopChatsLayout(context, p),
                    1 => PrivacyShieldScreen(client: widget.client),
                    _ => ProfileSettingsScreen(
                        client: widget.client,
                        themeMode: widget.themeMode,
                        onThemeModeChanged: widget.onThemeModeChanged,
                      ),
                  },
                ),
              ],
            ),
          );
        }

        // Мобильная адаптация (< 820px): классический Telegram iOS/Android
        return Scaffold(
          backgroundColor: p.bg2,
          body: switch (_navIndex) {
            0 => _buildChatListColumn(context, p, isWide: false),
            1 => PrivacyShieldScreen(client: widget.client),
            _ => ProfileSettingsScreen(
                client: widget.client,
                themeMode: widget.themeMode,
                onThemeModeChanged: widget.onThemeModeChanged,
              ),
          },
          bottomNavigationBar: _TelegramMobileBottomBar(
            selectedIndex: _navIndex,
            unreadCount: totalUnread,
            blockedCount: blockedCount,
            onSelect: (idx) => setState(() => _navIndex = idx),
          ),
        );
      },
    );
  }

  Widget _buildDesktopChatsLayout(BuildContext context, TalerPalette p) {
    final chats = widget.client.chats;
    TalerChat? selectedChat;
    if (_selectedChatId != null) {
      selectedChat = chats.where((c) => c.id == _selectedChatId).firstOrNull;
    }

    return Row(
      children: [
        SizedBox(
          width: 340,
          child: _buildChatListColumn(context, p, isWide: true),
        ),
        VerticalDivider(width: 1, thickness: 1, color: p.line),
        Expanded(
          child: selectedChat != null
              ? ChatScreen(
                  key: ValueKey(selectedChat.id),
                  client: widget.client,
                  chat: selectedChat,
                )
              : TelegramChatBackground(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: p.isDark
                            ? const Color(0xCC17212B)
                            : const Color(0xD9FFFFFF),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: p.line),
                      ),
                      child: Text(
                        'Выберите чат для начала общения',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: p.fg,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildChatListColumn(
    BuildContext context,
    TalerPalette p, {
    required bool isWide,
  }) {
    final folders = widget.client.folders;
    final selectedFolder =
        folders.where((f) => f.id == _selectedFolderId).firstOrNull;

    final filteredChats = widget.client.chats.where((chat) {
      if (selectedFolder != null && !selectedFolder.isAllChats) {
        if (!selectedFolder.chatIds.contains(chat.id)) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final inTitle = chat.title.toLowerCase().contains(q);
        final inPreview =
            (chat.lastMessageText ?? '').toLowerCase().contains(q);
        if (!inTitle && !inPreview) return false;
      }
      return true;
    }).toList();

    return Container(
      color: p.bg2,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Шапка списка чатов + pill-поиск
            if (!isWide)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
                child: Row(
                  children: [
                    const TalerLogo(size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Taler',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                          color: p.fg,
                        ),
                      ),
                    ),
                    _ConnectionStatusChip(
                      isDemo: widget.client.isDemoMode,
                      state: widget.client.connectionState,
                    ),
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                isWide ? 10 : 4,
                12,
                folders.length > 1 ? 4 : 10,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) =>
                            setState(() => _searchQuery = v.trim()),
                        style: TextStyle(fontSize: 13.5, color: p.fg),
                        decoration: InputDecoration(
                          hintText: 'Поиск',
                          hintStyle: TextStyle(fontSize: 13.5, color: p.fg2),
                          filled: true,
                          fillColor: p.bg3,
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: p.fg2,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 38,
                            minHeight: 38,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: p.fg2,
                                  ),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(color: p.accent, width: 1.4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Вкладки папок с синей полоской Telegram
            if (folders.length > 1)
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: folders.length,
                  itemBuilder: (context, index) {
                    final f = folders[index];
                    final selected = f.id == _selectedFolderId;
                    return _TelegramFolderTab(
                      label: f.title,
                      selected: selected,
                      onTap: () => setState(() => _selectedFolderId = f.id),
                    );
                  },
                ),
              ),

            Divider(height: 1, thickness: 1, color: p.line),

            // Список чатов (высота строки 72px)
            Expanded(
              child: filteredChats.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 28,
                            color: p.fg3,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Чатов не найдено',
                            style: TextStyle(fontSize: 13.5, color: p.fg2),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filteredChats.length,
                      separatorBuilder: (_, idx) {
                        final prev = filteredChats[idx];
                        final next = filteredChats[idx + 1];
                        if (isWide &&
                            (_selectedChatId == prev.id ||
                                _selectedChatId == next.id)) {
                          return const SizedBox.shrink();
                        }
                        return Divider(
                          height: 1,
                          thickness: 0.7,
                          indent: 76,
                          color: p.line,
                        );
                      },
                      itemBuilder: (context, index) {
                        final chat = filteredChats[index];
                        final isSelected = isWide && _selectedChatId == chat.id;
                        final myId = widget.client.currentUser?.id ?? 1;
                        return _TelegramChatTile(
                          chat: chat,
                          selected: isSelected,
                          lastMsgIsMine: chat.lastMessageSenderId == myId,
                          onTap: () {
                            if (isWide) {
                              setState(() => _selectedChatId = chat.id);
                            } else {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => Scaffold(
                                    backgroundColor: p.bg,
                                    body: ChatScreen(
                                      client: widget.client,
                                      chat: chat,
                                      showBackButton: true,
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TelegramDesktopRail extends StatelessWidget {
  final int selectedIndex;
  final int blockedCount;
  final int unreadCount;
  final bool ghostMode;
  final bool isDark;
  final TalerConnectionState connectionState;
  final bool isDemo;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggleGhost;
  final VoidCallback onToggleTheme;
  final VoidCallback onLogout;

  const _TelegramDesktopRail({
    required this.selectedIndex,
    required this.blockedCount,
    required this.unreadCount,
    required this.ghostMode,
    required this.isDark,
    required this.connectionState,
    required this.isDemo,
    required this.onSelect,
    required this.onToggleGhost,
    required this.onToggleTheme,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final statusColor = isDemo
        ? p.accent
        : switch (connectionState) {
            TalerConnectionState.online => p.statusLive,
            TalerConnectionState.connecting ||
            TalerConnectionState.connected =>
              p.warning,
            TalerConnectionState.disconnected => p.danger,
          };

    return Container(
      width: 72,
      color: p.isDark ? p.bg : const Color(0xFFE7EDF3),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Tooltip(
            message: isDemo
                ? 'Taler · Демо-режим'
                : 'Taler · ${connectionState.name}',
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const TalerLogo(size: 38),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: p.isDark ? p.bg : const Color(0xFFE7EDF3),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _RailNavItem(
            icon: Icons.chat_bubble_rounded,
            inactiveIcon: Icons.chat_bubble_outline_rounded,
            label: 'Чаты',
            badge: unreadCount > 0 ? '$unreadCount' : null,
            selected: selectedIndex == 0,
            onTap: () => onSelect(0),
          ),
          const SizedBox(height: 6),
          _RailNavItem(
            icon: Icons.shield_rounded,
            inactiveIcon: Icons.shield_outlined,
            label: 'Taler Shield',
            badge: '$blockedCount',
            selected: selectedIndex == 1,
            onTap: () => onSelect(1),
          ),
          const SizedBox(height: 6),
          _RailNavItem(
            icon: Icons.settings_rounded,
            inactiveIcon: Icons.settings_outlined,
            label: 'Настройки',
            selected: selectedIndex == 2,
            onTap: () => onSelect(2),
          ),
          const Spacer(),
          TalerIconButton(
            icon: ghostMode
                ? Icons.visibility_off_rounded
                : Icons.visibility_off_outlined,
            tooltip: ghostMode
                ? 'Призрак включён (онлайн скрыт)'
                : 'Включить режим Призрака',
            color: ghostMode ? p.statusLive : p.fg2,
            backgroundColor:
                ghostMode ? p.statusLiveSurface : Colors.transparent,
            onPressed: onToggleGhost,
          ),
          const SizedBox(height: 6),
          TalerIconButton(
            icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            tooltip: isDark ? 'Светлая тема' : 'Ночная тема',
            onPressed: onToggleTheme,
          ),
          const SizedBox(height: 6),
          TalerIconButton(
            icon: Icons.logout_rounded,
            tooltip: 'Выйти из аккаунта',
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}

class _RailNavItem extends StatefulWidget {
  final IconData icon;
  final IconData inactiveIcon;
  final String label;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _RailNavItem({
    required this.icon,
    required this.inactiveIcon,
    required this.label,
    this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_RailNavItem> createState() => _RailNavItemState();
}

class _RailNavItemState extends State<_RailNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final fg = widget.selected
        ? p.accent
        : _hovered
            ? p.fg
            : p.fg2;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 62,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: widget.selected
                ? p.accent.withValues(alpha: 0.14)
                : _hovered
                    ? p.fg2.withValues(alpha: 0.08)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    widget.selected ? widget.icon : widget.inactiveIcon,
                    size: 22,
                    color: fg,
                  ),
                  if (widget.badge != null)
                    Positioned(
                      right: -12,
                      top: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: widget.selected ? p.accent : p.accentMuted,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          widget.badge!,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                widget.label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.15,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TelegramMobileBottomBar extends StatelessWidget {
  final int selectedIndex;
  final int unreadCount;
  final int blockedCount;
  final ValueChanged<int> onSelect;

  const _TelegramMobileBottomBar({
    required this.selectedIndex,
    required this.unreadCount,
    required this.blockedCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Container(
      decoration: BoxDecoration(
        color: p.bg2,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              _MobileTabButton(
                icon: Icons.chat_bubble_rounded,
                inactiveIcon: Icons.chat_bubble_outline_rounded,
                label: 'Чаты',
                badge: unreadCount > 0 ? '$unreadCount' : null,
                selected: selectedIndex == 0,
                onTap: () => onSelect(0),
              ),
              _MobileTabButton(
                icon: Icons.shield_rounded,
                inactiveIcon: Icons.shield_outlined,
                label: 'Taler Shield',
                badge: '$blockedCount',
                selected: selectedIndex == 1,
                onTap: () => onSelect(1),
              ),
              _MobileTabButton(
                icon: Icons.settings_rounded,
                inactiveIcon: Icons.settings_outlined,
                label: 'Настройки',
                selected: selectedIndex == 2,
                onTap: () => onSelect(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileTabButton extends StatelessWidget {
  final IconData icon;
  final IconData inactiveIcon;
  final String label;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _MobileTabButton({
    required this.icon,
    required this.inactiveIcon,
    required this.label,
    this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final fg = selected ? p.accent : p.fg2;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(selected ? icon : inactiveIcon, size: 22, color: fg),
                if (badge != null)
                  Positioned(
                    right: -14,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: p.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionStatusChip extends StatelessWidget {
  final bool isDemo;
  final TalerConnectionState state;

  const _ConnectionStatusChip({required this.isDemo, required this.state});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final (label, dotColor) = isDemo
        ? ('Демо', p.accent)
        : switch (state) {
            TalerConnectionState.online => ('Online', p.statusLive),
            TalerConnectionState.connecting ||
            TalerConnectionState.connected =>
              ('Сеть...', p.warning),
            TalerConnectionState.disconnected => ('Офлайн', p.fg3),
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: p.bg3,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TalerStatusDot(color: dotColor, size: 6),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: p.fg2,
            ),
          ),
        ],
      ),
    );
  }
}

class _TelegramFolderTab extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TelegramFolderTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_TelegramFolderTab> createState() => _TelegramFolderTabState();
}

class _TelegramFolderTabState extends State<_TelegramFolderTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final fg = widget.selected
        ? p.accent
        : _hovered
            ? p.fg
            : p.fg2;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 3),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                ),
              ),
              AnimatedContainer(
                duration: TalerTheme.fastDuration,
                curve: TalerTheme.easeOutCurve,
                height: 3,
                width: widget.selected ? 26 : 0,
                decoration: BoxDecoration(
                  color: p.accent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
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

class _TelegramChatTile extends StatefulWidget {
  final TalerChat chat;
  final bool selected;
  final bool lastMsgIsMine;
  final VoidCallback onTap;

  const _TelegramChatTile({
    required this.chat,
    required this.selected,
    required this.lastMsgIsMine,
    required this.onTap,
  });

  @override
  State<_TelegramChatTile> createState() => _TelegramChatTileState();
}

class _TelegramChatTileState extends State<_TelegramChatTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final chat = widget.chat;
    final sel = widget.selected;
    final timeStr = chat.lastMessageTime != null
        ? DateFormat('HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(chat.lastMessageTime!),
          )
        : '';

    final bg = sel
        ? p.surfaceHigh
        : _hovered
            ? p.surface.withValues(alpha: 0.7)
            : Colors.transparent;

    final titleColor = sel ? Colors.white : p.fg;
    final timeColor = sel ? Colors.white.withValues(alpha: 0.85) : p.fg2;
    final previewColor = sel
        ? Colors.white.withValues(alpha: 0.88)
        : chat.typingLabel != null
            ? p.accent
            : chat.lastMessageDeletedByPeer
                ? p.warning
                : p.fg2;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: TalerTheme.fastDuration,
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: bg,
          child: Row(
            children: [
              TalerAvatar(
                seedId: chat.peerId ?? chat.id,
                initials: chat.initials,
                size: 50,
                isOnline: chat.isOnline,
                onlineBorderColor: sel ? p.surfaceHigh : p.bg2,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (chat.isChannel)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.campaign_rounded,
                              size: 16,
                              color: sel ? Colors.white : p.fg2,
                            ),
                          )
                        else if (chat.isGroup)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.group_rounded,
                              size: 15,
                              color: sel ? Colors.white : p.fg2,
                            ),
                          ),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  chat.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14.5,
                                    color: titleColor,
                                  ),
                                ),
                              ),
                              if (chat.isOfficial) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.verified_rounded,
                                  size: 15,
                                  color: sel ? Colors.white : p.accent,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (widget.lastMsgIsMine && timeStr.isNotEmpty) ...[
                          Icon(
                            Icons.done_all_rounded,
                            size: 15,
                            color: sel ? Colors.white : p.accent,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Text(
                          timeStr,
                          style: TalerTheme.tabularStyle(
                            size: 12,
                            color: timeColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (chat.lastMessageDeletedByPeer &&
                            chat.typingLabel == null)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.shield_outlined,
                              size: 14,
                              color: sel ? Colors.white : p.warning,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            chat.typingLabel ??
                                (chat.lastMessageDeletedByPeer
                                    ? 'Удалено · сохранено: ${chat.lastMessageText ?? ''}'
                                    : (chat.lastMessageText ?? '')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: previewColor,
                            ),
                          ),
                        ),
                        if (chat.isPinned && chat.unreadCount == 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.push_pin_rounded,
                              size: 15,
                              color: sel
                                  ? Colors.white.withValues(alpha: 0.75)
                                  : p.fg3,
                            ),
                          ),
                        if (chat.unreadCount > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: sel
                                  ? Colors.white
                                  : chat.isMuted
                                      ? p.fg3
                                      : p.accent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${chat.unreadCount}',
                              style: TalerTheme.tabularStyle(
                                size: 11.5,
                                weight: FontWeight.w700,
                                color: sel ? p.surfaceHigh : Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

/// Главный адаптивный экран Taler в тёмном обсидианово-графитовом стиле (3 колонки на ПК).
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
                _ObsidianDesktopRail(
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
          bottomNavigationBar: _ObsidianMobileBottomBar(
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
          width: 312,
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
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: p.bg2,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: p.line2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TalerStatusDot(
                            color: widget.client.isDemoMode
                                ? p.accent
                                : p.statusLive,
                            size: 6,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Выберите чат для начала общения',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: p.fg2,
                            ),
                          ),
                        ],
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
    final allChats = widget.client.chats;
    final folders = widget.client.folders;
    final selectedFolder =
        folders.where((f) => f.id == _selectedFolderId).firstOrNull;

    final filteredChats = allChats.where((chat) {
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

    final blockedCount = widget.client.privacySettings.blockedPacketsCount;
    final ghost = widget.client.privacySettings.ghostModeOnline;

    return Container(
      color: p.bg2,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (!isWide)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 12, 4),
                child: Row(
                  children: [
                    const TalerLogo(size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Taler',
                        style: TextStyle(
                          fontSize: 18,
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

            // Строка поиска (капсула в стиле референса)
            Padding(
              padding: EdgeInsets.fromLTRB(
                10,
                isWide ? 10 : 6,
                10,
                folders.length > 1 ? 6 : 10,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) =>
                            setState(() => _searchQuery = v.trim()),
                        style: TextStyle(fontSize: 13.5, color: p.fg),
                        decoration: InputDecoration(
                          hintText: 'Поиск',
                          hintStyle: TextStyle(fontSize: 13, color: p.fg3),
                          filled: true,
                          fillColor: p.bg3,
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 17,
                            color: p.fg3,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 15,
                                    color: p.fg2,
                                  ),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: p.line),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: p.line),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: p.line2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isWide) ...[
                    const SizedBox(width: 8),
                    _ConnectionStatusChip(
                      isDemo: widget.client.isDemoMode,
                      state: widget.client.connectionState,
                    ),
                  ],
                ],
              ),
            ),

            // Горизонтальные вкладки папок со счётчиками в пилюлях (как на референсе)
            if (folders.length > 1)
              SizedBox(
                height: 36,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: folders.length,
                  itemBuilder: (context, index) {
                    final f = folders[index];
                    final count = f.isAllChats
                        ? allChats.length
                        : allChats
                            .where((c) => f.chatIds.contains(c.id))
                            .length;
                    final selected = f.id == _selectedFolderId;
                    return _FolderTabPill(
                      label: f.title,
                      count: count,
                      selected: selected,
                      onTap: () => setState(() => _selectedFolderId = f.id),
                    );
                  },
                ),
              ),

            Divider(height: 1, thickness: 1, color: p.line),

            // Компактная строка статуса защиты (по аналогии с Archived Chats на референсе)
            _ShieldQuickRow(
              blockedCount: blockedCount,
              ghost: ghost,
              onTap: () => setState(() => _navIndex = 1),
            ),
            Divider(height: 1, thickness: 0.7, indent: 64, color: p.line),

            // Плотный список чатов (64px строка)
            Expanded(
              child: filteredChats.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 26,
                            color: p.fg3,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Чатов не найдено',
                            style: TextStyle(fontSize: 13, color: p.fg2),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filteredChats.length,
                      itemBuilder: (context, index) {
                        final chat = filteredChats[index];
                        final isSelected = isWide && _selectedChatId == chat.id;
                        final myId = widget.client.currentUser?.id ?? 1;
                        return _ObsidianChatTile(
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

class _ObsidianDesktopRail extends StatelessWidget {
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

  const _ObsidianDesktopRail({
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
      width: 68,
      color: p.bg,
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
                const TalerLogo(size: 36),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.bg, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
            badge: blockedCount > 0 ? '$blockedCount' : null,
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
        ? p.fg
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
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
          decoration: BoxDecoration(
            color: widget.selected
                ? p.surfaceHigh
                : _hovered
                    ? p.surface
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: widget.selected
                ? Border.all(color: p.line2)
                : Border.all(color: Colors.transparent),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    widget.selected ? widget.icon : widget.inactiveIcon,
                    size: 20,
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
                          color: widget.selected ? p.bubbleOut : p.surface3,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          widget.badge!,
                          style: TalerTheme.tabularStyle(
                            size: 9.5,
                            weight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
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

class _ObsidianMobileBottomBar extends StatelessWidget {
  final int selectedIndex;
  final int unreadCount;
  final int blockedCount;
  final ValueChanged<int> onSelect;

  const _ObsidianMobileBottomBar({
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
          height: 56,
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
                badge: blockedCount > 0 ? '$blockedCount' : null,
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
    final fg = selected ? p.fg : p.fg2;

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
                Icon(
                  selected ? icon : inactiveIcon,
                  size: 21,
                  color: selected ? p.accent : p.fg2,
                ),
                if (badge != null)
                  Positioned(
                    right: -13,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: p.bubbleOut,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badge!,
                        style: TalerTheme.tabularStyle(
                          size: 9.5,
                          weight: FontWeight.w700,
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
              ('Сеть', p.warning),
            TalerConnectionState.disconnected => ('Офлайн', p.fg3),
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: p.bg3,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TalerStatusDot(color: dotColor, size: 6),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: p.fg2,
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderTabPill extends StatefulWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FolderTabPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_FolderTabPill> createState() => _FolderTabPillState();
}

class _FolderTabPillState extends State<_FolderTabPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final fg = widget.selected
        ? p.fg
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
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          widget.selected ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: widget.selected ? p.bubbleOut : p.bg3,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${widget.count}',
                      style: TalerTheme.tabularStyle(
                        size: 10.5,
                        weight: FontWeight.w600,
                        color: widget.selected ? Colors.white : p.fg2,
                      ),
                    ),
                  ),
                ],
              ),
              AnimatedContainer(
                duration: TalerTheme.fastDuration,
                curve: TalerTheme.easeOutCurve,
                height: 2.5,
                width: widget.selected ? 28 : 0,
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

class _ShieldQuickRow extends StatefulWidget {
  final int blockedCount;
  final bool ghost;
  final VoidCallback onTap;

  const _ShieldQuickRow({
    required this.blockedCount,
    required this.ghost,
    required this.onTap,
  });

  @override
  State<_ShieldQuickRow> createState() => _ShieldQuickRowState();
}

class _ShieldQuickRowState extends State<_ShieldQuickRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: _hovered ? p.surface : Colors.transparent,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.bg3,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.line),
                ),
                child: Icon(
                  Icons.shield_outlined,
                  size: 19,
                  color: p.fg2,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Taler Shield · Защита активна',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.fg,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Перехвачено: ${widget.blockedCount} · Призрак ${widget.ghost ? "вкл" : "выкл"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TalerTheme.tabularStyle(
                        size: 12,
                        color: p.fg3,
                      ),
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

class _ObsidianChatTile extends StatefulWidget {
  final TalerChat chat;
  final bool selected;
  final bool lastMsgIsMine;
  final VoidCallback onTap;

  const _ObsidianChatTile({
    required this.chat,
    required this.selected,
    required this.lastMsgIsMine,
    required this.onTap,
  });

  @override
  State<_ObsidianChatTile> createState() => _ObsidianChatTileState();
}

class _ObsidianChatTileState extends State<_ObsidianChatTile> {
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
            ? p.surface
            : Colors.transparent;

    final previewColor = chat.typingLabel != null
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
        child: Container(
          height: 64,
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              TalerAvatar(
                seedId: chat.peerId ?? chat.id,
                initials: chat.initials,
                size: 46,
                isOnline: chat.isOnline,
                onlineBorderColor: sel ? p.surfaceHigh : p.bg2,
              ),
              const SizedBox(width: 11),
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
                              Icons.campaign_outlined,
                              size: 15,
                              color: p.fg2,
                            ),
                          )
                        else if (chat.isGroup)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.group_outlined,
                              size: 14,
                              color: p.fg2,
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
                                    fontSize: 13.5,
                                    color: p.fg,
                                  ),
                                ),
                              ),
                              if (chat.isMuted) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.volume_off_rounded,
                                  size: 13,
                                  color: p.fg3,
                                ),
                              ],
                              if (chat.isOfficial) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.verified_rounded,
                                  size: 14,
                                  color: p.accent,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (widget.lastMsgIsMine && timeStr.isNotEmpty) ...[
                          Icon(
                            Icons.done_all_rounded,
                            size: 14,
                            color: p.accent,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Text(
                          timeStr,
                          style: TalerTheme.tabularStyle(
                            size: 11.5,
                            color: p.fg3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (chat.lastMessageDeletedByPeer &&
                            chat.typingLabel == null)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.shield_outlined,
                              size: 13,
                              color: p.warning,
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
                              fontSize: 12.5,
                              color: previewColor,
                            ),
                          ),
                        ),
                        if (chat.isPinned && chat.unreadCount == 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.push_pin_rounded,
                              size: 14,
                              color: p.fg3,
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
                              color: chat.isMuted ? p.surface3 : p.bubbleOut,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${chat.unreadCount}',
                              style: TalerTheme.tabularStyle(
                                size: 11,
                                weight: FontWeight.w700,
                                color: Colors.white,
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

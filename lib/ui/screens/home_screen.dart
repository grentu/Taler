import 'dart:ui';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/storage/taler_models.dart';
import '../../core/transport/taler_session.dart';
import '../theme/taler_theme.dart';
import 'chat_screen.dart';
import 'privacy_shield_screen.dart';
import 'profile_settings_screen.dart';

/// Главный адаптивный экран Taler: плавающий сайдбар на ПК и пилюльный док на телефоне.
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
  int _navIndex = 0;
  String _selectedFolderId = 'all';
  String _searchQuery = '';
  int? _selectedChatId;

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
        final isWide = MediaQuery.sizeOf(context).width >= 860;
        final blockedCount = widget.client.privacySettings.blockedPacketsCount;

        if (isWide) {
          return Scaffold(
            backgroundColor: p.bg,
            body: Row(
              children: [
                _DesktopSidebar(
                  selectedIndex: _navIndex,
                  blockedCount: blockedCount,
                  isDemo: widget.client.isDemoMode,
                  connectionState: widget.client.connectionState,
                  spoofLabel: widget.client.spoofingService.activeProfile.label,
                  spoofId: widget.client.spoofingService.activeProfile.deviceId,
                  onSelect: (idx) => setState(() => _navIndex = idx),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    switchInCurve: TalerTheme.easeOutCurve,
                    child: KeyedSubtree(
                      key: ValueKey('desktop_tab_$_navIndex'),
                      child: switch (_navIndex) {
                        0 => _buildSplitChatsLayout(context, p),
                        1 => PrivacyShieldScreen(client: widget.client),
                        _ => ProfileSettingsScreen(
                            client: widget.client,
                            themeMode: widget.themeMode,
                            onThemeModeChanged: widget.onThemeModeChanged,
                          ),
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Мобильная адаптация (Android / iOS): контент + плавающий пилюльный док
        return Scaffold(
          backgroundColor: p.bg,
          body: Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  switchInCurve: TalerTheme.easeOutCurve,
                  child: KeyedSubtree(
                    key: ValueKey('mobile_tab_$_navIndex'),
                    child: switch (_navIndex) {
                      0 => _buildChatListPane(context, p, isWide: false),
                      1 => PrivacyShieldScreen(client: widget.client),
                      _ => ProfileSettingsScreen(
                          client: widget.client,
                          themeMode: widget.themeMode,
                          onThemeModeChanged: widget.onThemeModeChanged,
                        ),
                    },
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Center(
                      child: _MobilePillDock(
                        selectedIndex: _navIndex,
                        blockedCount: blockedCount,
                        onSelect: (idx) => setState(() => _navIndex = idx),
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

  Widget _buildSplitChatsLayout(BuildContext context, TalerPalette p) {
    final chats = widget.client.chats;
    TalerChat? selectedChat;
    if (_selectedChatId != null) {
      selectedChat = chats.where((c) => c.id == _selectedChatId).firstOrNull;
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
          child: Row(
            children: [
              SizedBox(
                width: 332,
                child: _buildChatListPane(context, p, isWide: true),
              ),
              VerticalDivider(width: 1, color: p.line),
              Expanded(
                child: selectedChat != null
                    ? ChatScreen(
                        key: ValueKey(selectedChat.id),
                        client: widget.client,
                        chat: selectedChat,
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 24,
                              color: p.fg3,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Выберите диалог',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: p.fg,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Телеметрия и баннеры отключены на транспортном уровне',
                              style: TextStyle(fontSize: 13, color: p.fg3),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatListPane(
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

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // Верхняя планка высотой 56px — единый ритм на всех экранах
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  isWide ? 'Диалоги' : 'Taler',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.3,
                    color: p.fg,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${filteredChats.length}',
                  style: TalerTheme.monoStyle(size: 12, color: p.fg3),
                ),
                const Spacer(),
                if (!isWide) ...[
                  _ConnectionPill(
                    isDemo: widget.client.isDemoMode,
                    state: widget.client.connectionState,
                  ),
                  const SizedBox(width: 8),
                  _ShieldCounterButton(
                    count: widget.client.privacySettings.blockedPacketsCount,
                    onTap: () => setState(() => _navIndex = 1),
                  ),
                ],
              ],
            ),
          ),

          // Поле поиска (ровно 36px)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SizedBox(
              height: 36,
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                style: TextStyle(fontSize: 13, color: p.fg),
                decoration: InputDecoration(
                  hintText: 'Поиск',
                  prefixIcon: Icon(Icons.search_rounded, size: 17, color: p.fg3),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ),
          ),

          // Полоска папок
          if (folders.length > 1)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                itemCount: folders.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final f = folders[index];
                  final selected = f.id == _selectedFolderId;
                  return _FolderPill(
                    label: f.title,
                    selected: selected,
                    onTap: () => setState(() => _selectedFolderId = f.id),
                  );
                },
              ),
            ),

          Divider(height: 1, color: p.line),

          // Список чатов
          Expanded(
            child: filteredChats.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined, size: 24, color: p.fg3),
                        const SizedBox(height: 8),
                        Text(
                          'Чатов не найдено',
                          style: TextStyle(fontSize: 13, color: p.fg3),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      8,
                      8,
                      8,
                      isWide ? 12 : 92,
                    ),
                    itemCount: filteredChats.length,
                    itemBuilder: (context, index) {
                      final chat = filteredChats[index];
                      final isSelected = isWide && _selectedChatId == chat.id;
                      return _ChatRow(
                        chat: chat,
                        selected: isSelected,
                        onTap: () {
                          if (isWide) {
                            setState(() => _selectedChatId = chat.id);
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => Scaffold(
                                  backgroundColor: p.bg,
                                  body: SafeArea(
                                    child: ChatScreen(
                                      client: widget.client,
                                      chat: chat,
                                      showBackButton: true,
                                    ),
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
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  final int selectedIndex;
  final int blockedCount;
  final bool isDemo;
  final TalerConnectionState connectionState;
  final String spoofLabel;
  final String spoofId;
  final ValueChanged<int> onSelect;

  const _DesktopSidebar({
    required this.selectedIndex,
    required this.blockedCount,
    required this.isDemo,
    required this.connectionState,
    required this.spoofLabel,
    required this.spoofId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    const rowHeight = 36.0;
    const rowGap = 4.0;
    const stride = rowHeight + rowGap;

    return Container(
      width: 236,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.bg2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Taler',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.3,
                    color: p.fg,
                  ),
                ),
                const Spacer(),
                _ConnectionPill(isDemo: isDemo, state: connectionState),
              ],
            ),
          ),
          Divider(height: 1, color: p.line),
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              height: stride * 3 - rowGap,
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: TalerTheme.pillDuration,
                    curve: TalerTheme.springCurve,
                    top: selectedIndex * stride,
                    left: 0,
                    right: 0,
                    height: rowHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: p.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: p.line2),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      _SidebarNavRow(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Чаты',
                        selected: selectedIndex == 0,
                        onTap: () => onSelect(0),
                      ),
                      const SizedBox(height: rowGap),
                      _SidebarNavRow(
                        icon: Icons.shield_outlined,
                        label: 'Taler Shield',
                        badge: '$blockedCount',
                        selected: selectedIndex == 1,
                        onTap: () => onSelect(1),
                      ),
                      const SizedBox(height: rowGap),
                      _SidebarNavRow(
                        icon: Icons.tune_rounded,
                        label: 'Настройки',
                        selected: selectedIndex == 2,
                        onTap: () => onSelect(2),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Divider(height: 1, color: p.line),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TalerStatusDot(color: p.statusLive, size: 6),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        spoofLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: p.fg2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  spoofId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TalerTheme.monoStyle(size: 11, color: p.fg3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarNavRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarNavRow({
    required this.icon,
    required this.label,
    this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SidebarNavRow> createState() => _SidebarNavRowState();
}

class _SidebarNavRowState extends State<_SidebarNavRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final fg = widget.selected
        ? p.fg
        : _hovered
            ? p.fg2
            : p.fg3;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Icon(widget.icon, size: 17, color: fg),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        widget.selected ? FontWeight.w500 : FontWeight.w400,
                    color: fg,
                  ),
                ),
              ),
              if (widget.badge != null)
                Text(
                  widget.badge!,
                  style: TalerTheme.monoStyle(
                    size: 11,
                    color: widget.selected ? p.fg : p.fg3,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobilePillDock extends StatelessWidget {
  final int selectedIndex;
  final int blockedCount;
  final ValueChanged<int> onSelect;

  const _MobilePillDock({
    required this.selectedIndex,
    required this.blockedCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 52,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: p.glass,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: p.line2),
              boxShadow: [
                BoxShadow(
                  color: p.isDark
                      ? const Color(0x66000000)
                      : const Color(0x18000000),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final slotWidth = constraints.maxWidth / 3;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: TalerTheme.pillDuration,
                      curve: TalerTheme.springCurve,
                      left: selectedIndex * slotWidth,
                      top: 0,
                      bottom: 0,
                      width: slotWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          color: p.surface2,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: p.line2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        _DockItem(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: 'Чаты',
                          selected: selectedIndex == 0,
                          onTap: () => onSelect(0),
                        ),
                        _DockItem(
                          icon: Icons.shield_outlined,
                          label: 'Taler Shield',
                          badge: '$blockedCount',
                          selected: selectedIndex == 1,
                          onTap: () => onSelect(1),
                        ),
                        _DockItem(
                          icon: Icons.tune_rounded,
                          label: 'Настройки',
                          selected: selectedIndex == 2,
                          onTap: () => onSelect(2),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _DockItem({
    required this.icon,
    required this.label,
    this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final fg = selected ? p.fg : p.fg3;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                      color: fg,
                    ),
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    badge!,
                    style: TalerTheme.monoStyle(size: 10.5, color: fg),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  final bool isDemo;
  final TalerConnectionState state;

  const _ConnectionPill({required this.isDemo, required this.state});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final (label, dotColor) = isDemo
        ? ('Демо', p.fg2)
        : switch (state) {
            TalerConnectionState.online => ('Online', p.statusLive),
            TalerConnectionState.connecting ||
            TalerConnectionState.connected =>
              ('Сеть', p.warning),
            TalerConnectionState.disconnected => ('Офлайн', p.danger),
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TalerStatusDot(color: dotColor, size: 6),
          const SizedBox(width: 6),
          Text(
            label,
            style: TalerTheme.monoStyle(size: 11, color: p.fg2),
          ),
        ],
      ),
    );
  }
}

class _ShieldCounterButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ShieldCounterButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: p.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TalerStatusDot(color: p.statusLive, size: 6),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TalerTheme.monoStyle(size: 11, color: p.fg),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderPill extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FolderPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_FolderPill> createState() => _FolderPillState();
}

class _FolderPillState extends State<_FolderPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final bg = widget.selected
        ? p.solid
        : _hovered
            ? p.surface2
            : p.surface;
    final fg = widget.selected ? p.onSolid : p.fg2;
    final border = widget.selected ? p.solid : p.line;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: TalerTheme.fastDuration,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    widget.selected ? FontWeight.w500 : FontWeight.w400,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatRow extends StatefulWidget {
  final TalerChat chat;
  final bool selected;
  final VoidCallback onTap;

  const _ChatRow({
    required this.chat,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_ChatRow> createState() => _ChatRowState();
}

class _ChatRowState extends State<_ChatRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final chat = widget.chat;
    final timeStr = chat.lastMessageTime != null
        ? DateFormat('HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(chat.lastMessageTime!),
          )
        : '';

    final bg = widget.selected
        ? p.surface2
        : _hovered
            ? p.surface
            : Colors.transparent;
    final border = widget.selected ? p.line2 : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: TalerTheme.fastDuration,
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.line2),
                    ),
                    child: Text(
                      chat.initials,
                      style: TextStyle(
                        color: p.fg,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (chat.isOnline)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: p.statusLive,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.bg, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (chat.isPinned)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.push_pin_outlined,
                              size: 13,
                              color: p.fg3,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                              color: p.fg,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: TalerTheme.monoStyle(size: 11, color: p.fg3),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (chat.lastMessageDeletedByPeer &&
                            chat.typingLabel == null) ...[
                          TalerStatusDot(color: p.warning, size: 6),
                          const SizedBox(width: 6),
                        ],
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
                              color: chat.typingLabel != null
                                  ? p.statusLive
                                  : chat.lastMessageDeletedByPeer
                                      ? p.warning
                                      : p.fg2,
                            ),
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
                              color: p.solid,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${chat.unreadCount}',
                              style: TalerTheme.monoStyle(
                                size: 11,
                                weight: FontWeight.w500,
                                color: p.onSolid,
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

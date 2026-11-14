import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../backend/taler_client.dart';
import '../../core/storage/taler_models.dart';
import '../../core/transport/taler_session.dart';
import '../theme/taler_theme.dart';
import 'chat_screen.dart';
import 'privacy_shield_screen.dart';
import 'profile_settings_screen.dart';

/// Главный адаптивный экран Taler (Split View для Windows / NavigationBar для мобильных).
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
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.client,
        widget.client.privacySettings,
      ]),
      builder: (context, _) {
        final isWide = MediaQuery.sizeOf(context).width >= 820;

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _navIndex,
                  onDestinationSelected: (idx) =>
                      setState(() => _navIndex = idx),
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Icon(
                      Icons.shield_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 28,
                    ),
                  ),
                  destinations: [
                    const NavigationRailDestination(
                      icon: Icon(Icons.chat_bubble_outline_rounded),
                      selectedIcon: Icon(Icons.chat_bubble_rounded),
                      label: Text('Чаты'),
                    ),
                    NavigationRailDestination(
                      icon: Badge(
                        label: Text(
                          '${widget.client.privacySettings.blockedPacketsCount}',
                        ),
                        child: const Icon(Icons.security_outlined),
                      ),
                      selectedIcon: const Icon(Icons.security_rounded),
                      label: const Text('Shield'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: Text('Профиль'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: switch (_navIndex) {
                    0 => _buildSplitChatsLayout(context),
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

        // Мобильная версия (Android / iOS)
        return Scaffold(
          body: switch (_navIndex) {
            0 => _buildChatListPane(context, isWide: false),
            1 => PrivacyShieldScreen(client: widget.client),
            _ => ProfileSettingsScreen(
                client: widget.client,
                themeMode: widget.themeMode,
                onThemeModeChanged: widget.onThemeModeChanged,
              ),
          },
          bottomNavigationBar: NavigationBar(
            selectedIndex: _navIndex,
            onDestinationSelected: (idx) => setState(() => _navIndex = idx),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: Icon(Icons.chat_bubble_rounded),
                label: 'Чаты',
              ),
              NavigationDestination(
                icon: Badge(
                  label: Text(
                    '${widget.client.privacySettings.blockedPacketsCount}',
                  ),
                  child: const Icon(Icons.shield_outlined),
                ),
                selectedIcon: const Icon(Icons.shield_rounded),
                label: 'Taler Shield',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Настройки',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSplitChatsLayout(BuildContext context) {
    final chats = widget.client.chats;
    TalerChat? selectedChat;
    if (_selectedChatId != null) {
      selectedChat =
          chats.where((c) => c.id == _selectedChatId).firstOrNull;
    }

    return Row(
      children: [
        SizedBox(
          width: 340,
          child: _buildChatListPane(context, isWide: true),
        ),
        const VerticalDivider(width: 1),
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
                        size: 46,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Выберите чат для переписки',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Телеметрия MAX отключена на транспортном уровне',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildChatListPane(BuildContext context, {required bool isWide}) {
    final theme = Theme.of(context);
    final folders = widget.client.folders;
    final selectedFolder = folders
        .where((f) => f.id == _selectedFolderId)
        .firstOrNull;

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
      child: Column(
        children: [
          // Верхний заголовок + статус соединения + счётчик заблокированной телеметрии
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const Text(
                  'Taler',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                _ConnectionChip(
                  isDemo: widget.client.isDemoMode,
                  state: widget.client.connectionState,
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _navIndex = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: TalerTheme.shieldGreen.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.shield_rounded,
                          size: 14,
                          color: TalerTheme.shieldGreen,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.client.privacySettings.blockedPacketsCount}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: TalerTheme.shieldGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Поиск
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              decoration: const InputDecoration(
                hintText: 'Поиск чатов...',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                isDense: true,
              ),
            ),
          ),

          // Полоска папок
          if (folders.length > 1)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                itemCount: folders.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final f = folders[index];
                  final selected = f.id == _selectedFolderId;
                  return ChoiceChip(
                    label: Text(f.title),
                    selected: selected,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) =>
                        setState(() => _selectedFolderId = f.id),
                  );
                },
              ),
            ),

          const Divider(height: 1),

          // Список чатов
          Expanded(
            child: filteredChats.isEmpty
                ? Center(
                    child: Text(
                      'Чатов не найдено',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
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

class _ConnectionChip extends StatelessWidget {
  final bool isDemo;
  final TalerConnectionState state;

  const _ConnectionChip({required this.isDemo, required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color) = isDemo
        ? ('Демо', TalerTheme.accent)
        : switch (state) {
            TalerConnectionState.online => ('Online', TalerTheme.shieldGreen),
            TalerConnectionState.connecting ||
            TalerConnectionState.connected =>
              ('Подключение...', TalerTheme.warningAmber),
            TalerConnectionState.disconnected => ('Офлайн', TalerTheme.dangerRed),
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  final TalerChat chat;
  final bool selected;
  final VoidCallback onTap;

  const _ChatRow({
    required this.chat,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr = chat.lastMessageTime != null
        ? DateFormat('HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(chat.lastMessageTime!),
          )
        : '';

    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.16),
                    child: Text(
                      chat.initials,
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (chat.isOnline)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: TalerTheme.shieldGreen,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (chat.isPinned)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.push_pin_rounded,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        Text(
                          timeStr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.typingLabel ??
                                (chat.lastMessageDeletedByPeer
                                    ? '🛡 [Удалено, сохранено] ${chat.lastMessageText ?? ''}'
                                    : (chat.lastMessageText ?? '')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: chat.typingLabel != null
                                  ? TalerTheme.shieldGreen
                                  : chat.lastMessageDeletedByPeer
                                      ? TalerTheme.warningAmber
                                      : theme.colorScheme.onSurfaceVariant,
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
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${chat.unreadCount}',
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
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

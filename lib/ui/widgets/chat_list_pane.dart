import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/storage/taler_models.dart';
import '../../core/transport/taler_session.dart';
import '../icons/taler_icon.dart';
import '../theme/chat_tokens.dart';
import '../theme/taler_theme.dart';

/// Фильтр списка: папка с сервера MAX или встроенный тип чатов.
class _ChatFilter {
  final String id;
  final String label;
  final bool Function(TalerChat chat) test;

  const _ChatFilter(this.id, this.label, this.test);
}

/// Левая колонка (на телефоне — весь экран): заголовок, поиск, папки и чаты.
class ChatListPane extends StatefulWidget {
  final TalerClient client;
  final int? selectedChatId;
  final ValueChanged<TalerChat> onOpen;

  /// Телефон: строки на всю ширину с разделителями, крупный заголовок.
  final bool compact;

  /// Отступ снизу, чтобы последний чат не прятался под плавающим меню.
  final double bottomInset;

  const ChatListPane({
    super.key,
    required this.client,
    required this.onOpen,
    this.selectedChatId,
    this.compact = false,
    this.bottomInset = 0,
  });

  @override
  State<ChatListPane> createState() => _ChatListPaneState();
}

class _ChatListPaneState extends State<ChatListPane> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode(skipTraversal: true);
  String _query = '';
  String _filterId = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<_ChatFilter> _filters() {
    final serverFolders = widget.client.folders.where((f) => !f.isAllChats).toList();
    if (serverFolders.isNotEmpty) {
      return [
        _ChatFilter('all', 'Все', (_) => true),
        for (final f in serverFolders) _ChatFilter('f:${f.id}', f.title, (c) => f.chatIds.contains(c.id)),
      ];
    }
    return [
      _ChatFilter('all', 'Все', (_) => true),
      _ChatFilter('dm', 'Личные', (c) => c.isDialog),
      _ChatFilter('group', 'Группы', (c) => c.isGroup),
      _ChatFilter('channel', 'Каналы', (c) => c.isChannel),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final client = widget.client;
    final filters = _filters();
    final active = filters.firstWhere((f) => f.id == _filterId, orElse: () => filters.first);
    final q = _query.toLowerCase();
    final chats = client.chats.where((c) {
      if (!active.test(c)) return false;
      if (q.isEmpty) return true;
      return c.title.toLowerCase().contains(q) || (c.lastMessageText ?? '').toLowerCase().contains(q);
    }).toList();
    final online = client.isDemoMode || client.connectionState == TalerConnectionState.online;

    return Container(
      color: widget.compact ? p.settingsBg : p.bg2,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: widget.compact ? 60 : 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        online ? 'Чаты' : 'Подключение…',
                        style: TextStyle(
                          fontSize: widget.compact ? 28 : 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: widget.compact ? -0.5 : -0.2,
                          color: p.fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(widget.compact ? 16 : 12, 0, widget.compact ? 16 : 12, 12),
              child: _SearchField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: (v) => setState(() => _query = v.trim()),
                onClear: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                  _searchFocus.unfocus();
                },
              ),
            ),
            _FolderTabs(
              filters: filters,
              activeId: active.id,
              horizontalPadding: widget.compact ? 16 : 12,
              unreadIn: (f) => client.chats.where((c) => f.test(c) && c.unreadCount > 0 && !c.isMuted).length,
              onSelect: (id) {
                _searchFocus.unfocus();
                setState(() => _filterId = id);
              },
            ),
            Expanded(
              child: chats.isEmpty
                  ? Center(
                      child: Text(
                        q.isEmpty ? 'Здесь пока нет чатов' : 'Ничего не найдено',
                        style: TextStyle(fontSize: 14, color: p.fg3),
                      ),
                    )
                  : ListView.builder(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        widget.compact ? 0 : 6,
                        6,
                        widget.compact ? 0 : 6,
                        8 + widget.bottomInset,
                      ),
                      itemCount: chats.length,
                      itemBuilder: (context, i) {
                        final chat = chats[i];
                        return ChatRow(
                          client: client,
                          chat: chat,
                          compact: widget.compact,
                          selected: !widget.compact && chat.id == widget.selectedChatId,
                          onTap: () {
                            _searchFocus.unfocus();
                            FocusManager.instance.primaryFocus?.unfocus();
                            widget.onOpen(chat);
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

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Container(
      height: 38,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: p.isDark ? p.surface : p.bg3,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          TalerIcon(TalerIcons.search, size: 16, color: p.fg3),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => focusNode.unfocus(),
              onTapOutside: (_) => focusNode.unfocus(),
              style: TextStyle(fontSize: 14, color: p.fg),
              decoration: InputDecoration(
                hintText: 'Поиск',
                hintStyle: TextStyle(fontSize: 14, color: p.fg3),
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            TalerIconButton(
              icon: TalerIcons.close,
              tooltip: 'Очистить поиск',
              size: 28,
              iconSize: 14,
              color: p.fg3,
              onPressed: onClear,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// Вкладки с подчёркиванием: текст, счётчик непрочитанных и синяя линия у выбранной.
class _FolderTabs extends StatelessWidget {
  final List<_ChatFilter> filters;
  final String activeId;
  final double horizontalPadding;
  final int Function(_ChatFilter) unreadIn;
  final ValueChanged<String> onSelect;

  const _FolderTabs({
    required this.filters,
    required this.activeId,
    required this.horizontalPadding,
    required this.unreadIn,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final tabs = [
      for (final f in filters)
        _FolderTab(
          label: f.label,
          count: unreadIn(f),
          selected: f.id == activeId,
          onTap: () => onSelect(f.id),
        ),
    ];
    return Container(
      margin: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (_, index) => tabs[index],
      ),
    );
  }
}

class _FolderTab extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FolderTab({required this.label, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: selected ? p.fg : p.fg3,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? p.accent : p.bg3,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: TalerTheme.tabularStyle(
                          size: 11,
                          weight: FontWeight.w600,
                          color: selected ? Colors.white : p.fg2,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (selected)
            Positioned(
              left: 8,
              right: 8,
              bottom: 0,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: p.accent,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Строка чата: аватар, имя, превью последнего сообщения, время и счётчик.
class ChatRow extends StatelessWidget {
  final TalerClient client;
  final TalerChat chat;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;

  const ChatRow({
    super.key,
    required this.client,
    required this.chat,
    required this.compact,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final peer = chat.peerId != null ? client.contactById(chat.peerId!) : null;
    final avatarUrl = chat.avatarUrl ?? peer?.avatarUrl;
    final hasUnread = chat.unreadCount > 0;
    final timeColor = hasUnread && !chat.isMuted ? p.accent : p.fg3;

    final content = Row(
      children: [
        TalerAvatar(
          seedId: chat.peerId ?? chat.id,
          initials: chat.initials,
          imageUrl: avatarUrl,
          size: compact ? 52 : 48,
          isOnline: chat.isDialog && chat.isOnline,
          onlineBorderColor: selected ? p.bg3 : p.bg2,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: compact ? const EdgeInsets.only(top: 2, bottom: 10) : EdgeInsets.zero,
            decoration: compact ? BoxDecoration(border: Border(bottom: BorderSide(color: p.line))) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (chat.isGroup) ...[
                            TalerIcon(TalerIcons.users, size: 14, color: p.fg3, strokeWidth: 2),
                            const SizedBox(width: 6),
                          ],
                          if (chat.isChannel) ...[
                            TalerIcon(TalerIcons.megaphone, size: 14, color: p.fg3, strokeWidth: 2),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              chat.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: p.fg),
                            ),
                          ),
                          if (chat.isOfficial) ...[
                            const SizedBox(width: 4),
                            TalerIcon(TalerIcons.badgeCheck, size: 16, color: p.accent, strokeWidth: 2),
                          ],
                          if (chat.isMuted) ...[
                            const SizedBox(width: 4),
                            TalerIcon(TalerIcons.bellOff, size: 14, color: p.fg3, strokeWidth: 2),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ChatTokens.listTime(chat.lastMessageTime),
                      style: TalerTheme.tabularStyle(size: 12, color: timeColor),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(child: _Preview(client: client, chat: chat)),
                    const SizedBox(width: 8),
                    if (hasUnread)
                      Container(
                        constraints: const BoxConstraints(minWidth: 20),
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: chat.isMuted ? ChatTokens.badgeMuted(p) : p.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          chat.unreadCount > 999 ? '999+' : '${chat.unreadCount}',
                          style: TalerTheme.tabularStyle(size: 11, weight: FontWeight.w600, color: Colors.white),
                        ),
                      )
                    else if (chat.isPinned)
                      Transform.rotate(
                        angle: 0.78,
                        child: TalerIcon(TalerIcons.pin, size: 14, color: p.fg3, strokeWidth: 2),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : 2),
      child: Material(
        color: selected ? ChatTokens.active(p) : Colors.transparent,
        borderRadius: BorderRadius.circular(compact ? 0 : 12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: ChatTokens.hover(p),
          splashFactory: NoSplash.splashFactory,
          child: Padding(
            padding: compact ? const EdgeInsets.fromLTRB(16, 8, 16, 0) : const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final TalerClient client;
  final TalerChat chat;

  const _Preview({required this.client, required this.chat});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final typing = chat.typingLabel;
    if (typing != null && typing.isNotEmpty) {
      return Text(
        '$typing…',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14, color: p.accent),
      );
    }
    final myId = client.currentUser?.id;
    final senderId = chat.lastMessageSenderId;
    String? author;
    if (senderId != null && senderId == myId) {
      author = 'Вы';
    } else if (senderId != null && chat.isGroup) {
      author = client.senderDisplayName(senderId, chatId: chat.id).split(' ').first;
    }
    var text = chat.lastMessageText ?? '';
    if (text == '[Вложение]') text = 'Вложение';
    return Row(
      children: [
        if (author != null)
          Text('$author: ', style: TextStyle(fontSize: 14, color: p.fg)),
        if (chat.lastMessageDeletedByPeer) ...[
          TalerIcon(TalerIcons.trash, size: 13, color: p.fg3, strokeWidth: 2),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: p.fg2),
          ),
        ),
      ],
    );
  }
}

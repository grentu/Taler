import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/storage/taler_models.dart';
import '../theme/taler_theme.dart';
import '../icons/taler_icon.dart';

enum _InfoTab { members, media, files, shield }

/// Экран открытого диалога / группы / канала с правой панелью «Информация о чате».
class ChatScreen extends StatefulWidget {
  final TalerClient client;
  final TalerChat chat;
  final bool showBackButton;
  final VoidCallback? onBack;

  const ChatScreen({
    super.key,
    required this.client,
    required this.chat,
    this.showBackButton = false,
    this.onBack,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  TalerMessage? _replyingTo;
  TalerMessage? _editingMessage;
  bool _showChatInfo = true;
  bool _showSearchBar = false;
  String _searchQuery = '';
  _InfoTab _infoTab = _InfoTab.members;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _loadChatData();
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chat.id != widget.chat.id) {
      _replyingTo = null;
      _editingMessage = null;
      _showSearchBar = false;
      _searchQuery = '';
      _searchCtrl.clear();
      _inputCtrl.clear();
      _loadChatData();
    }
  }

  void _loadChatData() {
    widget.client.loadHistory(widget.chat.id);
    widget.client.markChatRead(widget.chat.id);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final editing = _editingMessage;
    final reply = _replyingTo;
    _inputCtrl.clear();
    setState(() {
      _editingMessage = null;
      _replyingTo = null;
    });

    if (editing != null) {
      await widget.client.editMessage(widget.chat.id, editing.id, text);
    } else {
      await widget.client.sendMessage(
        widget.chat.id,
        text,
        replyTo: reply,
      );
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: TalerTheme.easeOutCurve,
        );
      }
    });
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final path = file.path;
    if (path == null) return;

    final ext = (file.extension ?? '').toLowerCase();
    final isImage = {'png', 'jpg', 'jpeg', 'webp', 'gif'}.contains(ext);
    try {
      await widget.client.sendFileAttachment(
        widget.chat.id,
        filePath: path,
        fileName: file.name,
        isImage: isImage,
      );
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки файла: $e')),
      );
    }
  }

  void _onTextChanged(String value) {
    if (value.trim().isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastTypingSent) > const Duration(seconds: 4)) {
      _lastTypingSent = now;
      widget.client.sendTyping(widget.chat.id);
    }
  }

  void _openInfoSheet(BuildContext context, TalerChat liveChat, List<TalerMessage> messages) {
    final p = TalerTheme.paletteOf(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, _) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Container(
            color: p.bg2,
            child: _ChatInfoPanel(
              client: widget.client,
              chat: liveChat,
              messages: messages,
              subtitle: _subtitleForChat(liveChat),
              activeTab: _infoTab,
              onTabChanged: (tab) => setState(() => _infoTab = tab),
              onClose: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final myId = widget.client.currentUser?.id ?? 1;

    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.client,
        widget.client.privacySettings,
      ]),
      builder: (context, _) {
        final liveChat =
            widget.client.store.chats[widget.chat.id] ?? widget.chat;
        final allMessages = widget.client.messagesForChat(widget.chat.id);
        final messages = _searchQuery.isEmpty
            ? allMessages
            : allMessages
                .where(
                  (m) => m.text.toLowerCase().contains(_searchQuery.toLowerCase()),
                )
                .toList();
        final pinnedMsg = allMessages.isNotEmpty ? allMessages.first : null;
        final ghost = widget.client.privacySettings.ghostModeOnline;
        final canDockInfo = MediaQuery.sizeOf(context).width >= 1100;
        final showDockedInfo = canDockInfo && _showChatInfo;

        final centerColumn = Column(
          children: [
            // Шапка чата (56px, hairline border)
            Container(
              color: p.bg2,
              child: SafeArea(
                bottom: false,
                top: widget.showBackButton,
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: p.bg2,
                    border: Border(bottom: BorderSide(color: p.line)),
                  ),
                  child: Row(
                    children: [
                      if (widget.showBackButton) ...[
                        TalerIconButton(
                          icon: TalerIcons.arrowLeft,
                          tooltip: 'Назад',
                          onPressed:
                              widget.onBack ?? () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 4),
                      ],
                      TalerAvatar(
                        seedId: liveChat.peerId ?? liveChat.id,
                        initials: liveChat.initials,
                        size: 38,
                        isOnline: liveChat.isOnline,
                        onlineBorderColor: p.bg2,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    liveChat.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14.5,
                                      color: p.fg,
                                    ),
                                  ),
                                ),
                                if (liveChat.isOfficial) ...[
                                  const SizedBox(width: 5),
                                  TalerIcon(
                                    TalerIcons.badgeCheck,
                                    size: 14,
                                    color: p.accent,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 1),
                            Text(
                              _subtitleForChat(liveChat),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TalerTheme.tabularStyle(
                                size: 12,
                                color: liveChat.typingLabel != null
                                    ? p.accent
                                    : liveChat.isOnline
                                        ? p.statusLive
                                        : p.fg2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (ghost)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Tooltip(
                            message: 'Режим Призрака: статус онлайн скрыт',
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: p.statusLiveSurface,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TalerIcon(
                                    TalerIcons.eyeOff,
                                    size: 12,
                                    color: p.statusLive,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Призрак',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: p.statusLive,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      TalerIconButton(
                        icon: TalerIcons.search,
                        tooltip: 'Поиск в чате',
                        color: _showSearchBar ? p.accent : p.fg2,
                        onPressed: () {
                          setState(() {
                            _showSearchBar = !_showSearchBar;
                            if (!_showSearchBar) {
                              _searchQuery = '';
                              _searchCtrl.clear();
                            }
                          });
                        },
                      ),
                      TalerIconButton(
                        icon: TalerIcons.panelLeft,
                        tooltip: 'Информация о чате',
                        color: showDockedInfo ? p.fg : p.fg2,
                        onPressed: () {
                          if (canDockInfo) {
                            setState(() => _showChatInfo = !_showChatInfo);
                          } else {
                            _openInfoSheet(context, liveChat, allMessages);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Поиск по сообщениям чата
            if (_showSearchBar)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                decoration: BoxDecoration(
                  color: p.bg2,
                  border: Border(bottom: BorderSide(color: p.line)),
                ),
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    style: TextStyle(fontSize: 13, color: p.fg),
                    decoration: InputDecoration(
                      hintText: 'Поиск по истории чата...',
                      filled: true,
                      fillColor: p.bg3,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(17),
                        borderSide: BorderSide(color: p.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(17),
                        borderSide: BorderSide(color: p.line),
                      ),
                    ),
                  ),
                ),
              ),

            // Закреплённое сообщение (как на референсе 1)
            if (pinnedMsg != null && !_showSearchBar)
              GestureDetector(
                onTap: () {
                  if (_scrollCtrl.hasClients) {
                    _scrollCtrl.animateTo(
                      0,
                      duration: const Duration(milliseconds: 220),
                      curve: TalerTheme.easeOutCurve,
                    );
                  }
                },
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: p.bg2,
                    border: Border(bottom: BorderSide(color: p.line)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 2.5,
                        height: 26,
                        decoration: BoxDecoration(
                          color: p.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Закреплённое сообщение',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: p.accent,
                              ),
                            ),
                            Text(
                              pinnedMsg.text.isNotEmpty
                                  ? pinnedMsg.text
                                  : '[Вложение]',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: p.fg2),
                            ),
                          ],
                        ),
                      ),
                      TalerIcon(TalerIcons.pin, size: 15, color: p.fg3),
                    ],
                  ),
                ),
              ),

            // Лента сообщений на статическом точечном холсте
            Expanded(
              child: TelegramChatBackground(
                child: messages.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: p.bg2,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: p.line),
                          ),
                          child: Text(
                            _searchQuery.isEmpty
                                ? 'Сообщений пока нет'
                                : 'Совпадений не найдено',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: p.fg2,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          final isMine = msg.senderId == myId;
                          final senderName = widget.client.senderDisplayName(
                            msg.senderId,
                            chatId: liveChat.id,
                          );
                          return _ObsidianMessageRow(
                            message: msg,
                            isMine: isMine,
                            showPeerAvatar: !isMine && !liveChat.isDialog,
                            showSenderName: !isMine && !liveChat.isDialog,
                            senderName: senderName,
                            onTapMenu: () => _showMessageActions(msg, isMine),
                            onTapEdited: () => _showEditHistory(msg),
                            onToggleReaction: (emoji) => widget.client
                                .toggleReaction(liveChat.id, msg.id, emoji),
                          );
                        },
                      ),
              ),
            ),

            // Плашка ответа / редактирования
            if (_replyingTo != null || _editingMessage != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: p.bg2,
                  border: Border(top: BorderSide(color: p.line)),
                ),
                child: Row(
                  children: [
                    TalerIcon(
                      _editingMessage != null
                          ? TalerIcons.pencil
                          : TalerIcons.reply,
                      size: 18,
                      color: p.accent,
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 2.5,
                      height: 28,
                      decoration: BoxDecoration(
                        color: p.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _editingMessage != null
                                ? 'Редактирование сообщения'
                                : 'Ответ · ${widget.client.senderDisplayName(_replyingTo!.senderId, chatId: liveChat.id)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: p.accent,
                            ),
                          ),
                          Text(
                            (_editingMessage ?? _replyingTo)!.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: p.fg2),
                          ),
                        ],
                      ),
                    ),
                    TalerIconButton(
                      icon: TalerIcons.close,
                      size: 30,
                      iconSize: 17,
                      onPressed: () {
                        setState(() {
                          _replyingTo = null;
                          _editingMessage = null;
                          _inputCtrl.clear();
                        });
                      },
                    ),
                  ],
                ),
              ),

            // Нижняя плавающая капсула ввода (как на референсах 1 и 2)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: p.bg,
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: p.bg2,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: p.line2),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      TalerIconButton(
                        icon: TalerIcons.paperclip,
                        tooltip: 'Прикрепить файл',
                        size: 36,
                        iconSize: 19,
                        onPressed: _pickAttachment,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _inputCtrl,
                          onChanged: _onTextChanged,
                          minLines: 1,
                          maxLines: 5,
                          style: TextStyle(fontSize: 14, color: p.fg),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: widget.client.privacySettings.hideTyping
                                ? 'Сообщение (набор скрыт)...'
                                : 'Сообщение...',
                            hintStyle: TextStyle(fontSize: 13.5, color: p.fg3),
                            filled: false,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 9,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      TalerIconButton(
                        icon: TalerIcons.arrowUp,
                        tooltip: 'Отправить',
                        circle: true,
                        size: 36,
                        iconSize: 18,
                        backgroundColor: p.bubbleOut,
                        color: Colors.white,
                        onPressed: _send,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

        if (!showDockedInfo) return centerColumn;

        return Row(
          children: [
            Expanded(child: centerColumn),
            VerticalDivider(width: 1, thickness: 1, color: p.line),
            SizedBox(
              width: 288,
              child: _ChatInfoPanel(
                client: widget.client,
                chat: liveChat,
                messages: allMessages,
                subtitle: _subtitleForChat(liveChat),
                activeTab: _infoTab,
                onTabChanged: (tab) => setState(() => _infoTab = tab),
                onClose: () => setState(() => _showChatInfo = false),
              ),
            ),
          ],
        );
      },
    );
  }

  String _subtitleForChat(TalerChat chat) {
    if (chat.typingLabel != null && chat.typingLabel!.isNotEmpty) {
      return chat.typingLabel!;
    }
    if (chat.isChannel) return '${chat.participantsCount} подписчиков';
    if (chat.isGroup) return '${chat.participantsCount} участников';
    if (chat.isOnline) return 'в сети';
    if (chat.lastSeen != null && chat.lastSeen! > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(chat.lastSeen!);
      return 'был(а) в ${DateFormat('HH:mm').format(dt)}';
    }
    return 'был(а) недавно';
  }

  void _showEditHistory(TalerMessage msg) {
    final p = TalerTheme.paletteOf(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'История изменений',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        content: SizedBox(
          width: 400,
          child: TalerTableShell(
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Текущая версия',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: p.accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        msg.text,
                        style: TextStyle(fontSize: 13.5, color: p.fg),
                      ),
                    ],
                  ),
                ),
                for (final rev in msg.editHistory.reversed) ...[
                  Divider(height: 1, color: p.line),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('dd.MM.yyyy HH:mm:ss').format(
                            DateTime.fromMillisecondsSinceEpoch(rev.timestamp),
                          ),
                          style: TalerTheme.monoStyle(size: 11, color: p.fg2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          rev.text,
                          style: TextStyle(fontSize: 13, color: p.fg2),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TalerTactileButton(
            label: 'Закрыть',
            compact: true,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  void _showMessageActions(TalerMessage msg, bool isMine) {
    final p = TalerTheme.paletteOf(context);
    const quickEmojis = ['👍', '❤️', '🔥', '👀', '🛡️', '😂'];

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: p.fg4,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in quickEmojis)
                    GestureDetector(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        widget.client.toggleReaction(
                          widget.chat.id,
                          msg.id,
                          emoji,
                        );
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: p.bg3,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.line),
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 18)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TalerTableShell(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SheetActionRow(
                      icon: TalerIcons.reply,
                      label: 'Ответить',
                      onTap: () {
                        Navigator.of(ctx).pop();
                        setState(() {
                          _editingMessage = null;
                          _replyingTo = msg;
                        });
                      },
                    ),
                    if (msg.text.isNotEmpty) ...[
                      Divider(height: 1, color: p.line),
                      _SheetActionRow(
                        icon: TalerIcons.copy,
                        label: 'Копировать текст',
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: msg.text));
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ],
                    if (isMine && !msg.deletedByPeer) ...[
                      Divider(height: 1, color: p.line),
                      _SheetActionRow(
                        icon: TalerIcons.pencil,
                        label: 'Редактировать',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          setState(() {
                            _replyingTo = null;
                            _editingMessage = msg;
                            _inputCtrl.text = msg.text;
                          });
                        },
                      ),
                    ],
                    if (msg.isEdited) ...[
                      Divider(height: 1, color: p.line),
                      _SheetActionRow(
                        icon: TalerIcons.history,
                        label: 'История изменений',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showEditHistory(msg);
                        },
                      ),
                    ],
                    if (widget.client.isDemoMode && !msg.deletedByPeer) ...[
                      Divider(height: 1, color: p.line),
                      _SheetActionRow(
                        icon: TalerIcons.shield,
                        label: 'Симулировать удаление (Anti-Delete)',
                        color: p.warning,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          widget.client.simulatePeerDeleteInDemo(
                            widget.chat.id,
                            msg.id,
                          );
                        },
                      ),
                    ],
                    Divider(height: 1, color: p.line),
                    _SheetActionRow(
                      icon: TalerIcons.trash,
                      label: 'Удалить у себя',
                      color: p.danger,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        widget.client.deleteMessage(widget.chat.id, msg.id);
                      },
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

/// Правая панель «Информация о чате» по первому референсному скриншоту.
class _ChatInfoPanel extends StatelessWidget {
  final TalerClient client;
  final TalerChat chat;
  final List<TalerMessage> messages;
  final String subtitle;
  final _InfoTab activeTab;
  final ValueChanged<_InfoTab> onTabChanged;
  final VoidCallback onClose;

  const _ChatInfoPanel({
    required this.client,
    required this.chat,
    required this.messages,
    required this.subtitle,
    required this.activeTab,
    required this.onTabChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Container(
      color: p.bg2,
      child: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.line)),
            ),
            child: Row(
              children: [
                TalerIconButton(
                  icon: TalerIcons.close,
                  tooltip: 'Закрыть',
                  onPressed: onClose,
                ),
                const SizedBox(width: 6),
                Text(
                  'Информация',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: p.fg,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: TalerAvatar(
                    seedId: chat.peerId ?? chat.id,
                    initials: chat.initials,
                    size: 76,
                    isOnline: chat.isOnline,
                    onlineBorderColor: p.bg2,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        chat.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: p.fg,
                        ),
                      ),
                    ),
                    if (chat.isOfficial) ...[
                      const SizedBox(width: 5),
                      TalerIcon(TalerIcons.badgeCheck, size: 15, color: p.accent),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TalerTheme.tabularStyle(size: 12.5, color: p.fg2),
                ),
                const SizedBox(height: 16),

                // Карточка Уведомлений (Notifications toggle card со скриншота 1)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: p.bg3,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.line),
                  ),
                  child: Row(
                    children: [
                      TelegramIconBadge(
                        icon: chat.isMuted
                            ? TalerIcons.bellOff
                            : TalerIcons.bell,
                        size: 30,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Уведомления',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: p.fg,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: !chat.isMuted,
                        onChanged: (_) => client.toggleChatMute(chat.id),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Вкладки (Участники / Медиа / Файлы / Защита)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _InfoTabChip(
                        label: 'Участники',
                        selected: activeTab == _InfoTab.members,
                        onTap: () => onTabChanged(_InfoTab.members),
                      ),
                      _InfoTabChip(
                        label: 'Медиа',
                        selected: activeTab == _InfoTab.media,
                        onTap: () => onTabChanged(_InfoTab.media),
                      ),
                      _InfoTabChip(
                        label: 'Файлы',
                        selected: activeTab == _InfoTab.files,
                        onTap: () => onTabChanged(_InfoTab.files),
                      ),
                      _InfoTabChip(
                        label: 'Защита',
                        selected: activeTab == _InfoTab.shield,
                        onTap: () => onTabChanged(_InfoTab.shield),
                      ),
                    ],
                  ),
                ),
                Divider(height: 12, color: p.line),
                const SizedBox(height: 4),
                _buildTabContent(context, p),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, TalerPalette p) {
    switch (activeTab) {
      case _InfoTab.members:
        final myId = client.currentUser?.id;
        final seenIds = <int>{};
        final entries = <({int id, String name, String status, String? role, bool online})>[];

        void addParticipant(int id, String name, {bool online = false, String? role}) {
          if (id == 0 || seenIds.contains(id)) return;
          seenIds.add(id);
          entries.add((
            id: id,
            name: name,
            status: online ? 'в сети' : 'был(а) недавно',
            role: role,
            online: online,
          ));
        }

        if (myId != null && client.currentUser != null) {
          addParticipant(
            myId,
            client.currentUser!.fullName,
            online: !client.privacySettings.ghostModeOnline,
            role: 'Вы',
          );
        }
        if (chat.peerId != null) {
          final c = client.contactById(chat.peerId!);
          addParticipant(
            chat.peerId!,
            c?.displayName ?? chat.title,
            online: chat.isOnline,
          );
        }
        for (final msg in messages) {
          final c = client.contactById(msg.senderId);
          addParticipant(
            msg.senderId,
            client.senderDisplayName(msg.senderId, chatId: chat.id),
            online: c?.isOnline ?? false,
            role: (c?.isOfficial ?? false) ? 'Admin' : null,
          );
        }

        if (entries.isEmpty) {
          return Text(
            'Список участников недоступен',
            style: TextStyle(fontSize: 12.5, color: p.fg3),
          );
        }

        return Column(
          children: [
            for (final member in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    TalerAvatar(
                      seedId: member.id,
                      initials: _initialsFor(member.name),
                      size: 36,
                      isOnline: member.online,
                      onlineBorderColor: p.bg2,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: p.fg,
                            ),
                          ),
                          Text(
                            member.status,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: member.online ? p.accent : p.fg3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (member.role != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: member.role == 'Admin'
                              ? p.statusLiveSurface
                              : p.bg3,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          member.role!,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: member.role == 'Admin'
                                ? p.statusLive
                                : p.fg2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );

      case _InfoTab.media:
        final photos = [
          for (final m in messages)
            for (final att in m.attachments)
              if (att.type == 'PHOTO') att,
        ];
        if (photos.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'В этом чате пока нет изображений',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: p.fg3),
            ),
          );
        }
        return Column(
          children: [
            for (final photo in photos)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.bg3,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.line),
                ),
                child: Row(
                  children: [
                    TalerIcon(TalerIcons.image, size: 18, color: p.fg2),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        photo.fileName ?? 'Изображение',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: p.fg),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

      case _InfoTab.files:
        final docs = [
          for (final m in messages)
            for (final att in m.attachments)
              if (att.type != 'PHOTO' && att.type != 'CONTROL') att,
        ];
        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'В этом чате пока нет файлов',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: p.fg3),
            ),
          );
        }
        return Column(
          children: [
            for (final doc in docs)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.bg3,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.line),
                ),
                child: Row(
                  children: [
                    TalerIcon(TalerIcons.file, size: 18, color: p.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doc.fileName ?? doc.type,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: p.fg),
                          ),
                          if (doc.fileSize != null)
                            Text(
                              '${(doc.fileSize! / 1024).toStringAsFixed(1)} КБ',
                              style: TalerTheme.tabularStyle(
                                size: 11,
                                color: p.fg3,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

      case _InfoTab.shield:
        final ps = client.privacySettings;
        return Column(
          children: [
            _InfoStatRow(
              label: 'Режим Призрака',
              value: ps.ghostModeOnline ? 'Вкл' : 'Выкл',
              active: ps.ghostModeOnline,
            ),
            _InfoStatRow(
              label: 'Скрытие набора',
              value: ps.hideTyping ? 'Вкл' : 'Выкл',
              active: ps.hideTyping,
            ),
            _InfoStatRow(
              label: 'Скрытие прочтения',
              value: ps.hideReadReceipts ? 'Вкл' : 'Выкл',
              active: ps.hideReadReceipts,
            ),
            _InfoStatRow(
              label: 'Anti-Delete',
              value: ps.antiDelete ? 'Активен' : 'Выкл',
              active: ps.antiDelete,
            ),
          ],
        );
    }
  }

  static String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts[1].substring(0, 1)}'
        .toUpperCase();
  }
}

class _InfoTabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _InfoTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? p.accent : p.fg2,
              ),
            ),
            const SizedBox(height: 5),
            Container(
              height: 2,
              width: selected ? 26 : 0,
              decoration: BoxDecoration(
                color: p.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoStatRow extends StatelessWidget {
  final String label;
  final String value;
  final bool active;

  const _InfoStatRow({
    required this.label,
    required this.value,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: p.fg2),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: active ? p.statusLive : p.fg3,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetActionRow extends StatelessWidget {
  final TalerIconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _SheetActionRow({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final fg = color ?? p.fg;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            TalerIcon(icon, size: 19, color: color ?? p.fg2),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ObsidianMessageRow extends StatelessWidget {
  final TalerMessage message;
  final bool isMine;
  final bool showPeerAvatar;
  final bool showSenderName;
  final String senderName;
  final VoidCallback onTapMenu;
  final VoidCallback onTapEdited;
  final ValueChanged<String> onToggleReaction;

  const _ObsidianMessageRow({
    required this.message,
    required this.isMine,
    required this.showPeerAvatar,
    required this.showSenderName,
    required this.senderName,
    required this.onTapMenu,
    required this.onTapEdited,
    required this.onToggleReaction,
  });

  @override
  Widget build(BuildContext context) {
    final bubble = _ObsidianMessageBubble(
      message: message,
      isMine: isMine,
      showSenderName: showSenderName,
      senderName: senderName,
      onTapMenu: onTapMenu,
      onTapEdited: onTapEdited,
      onToggleReaction: onToggleReaction,
    );

    if (!showPeerAvatar) {
      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: bubble,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: TalerAvatar(
              seedId: message.senderId,
              initials: _ChatInfoPanel._initialsFor(senderName),
              size: 30,
            ),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }
}

class _ObsidianMessageBubble extends StatelessWidget {
  final TalerMessage message;
  final bool isMine;
  final bool showSenderName;
  final String senderName;
  final VoidCallback onTapMenu;
  final VoidCallback onTapEdited;
  final ValueChanged<String> onToggleReaction;

  const _ObsidianMessageBubble({
    required this.message,
    required this.isMine,
    required this.showSenderName,
    required this.senderName,
    required this.onTapMenu,
    required this.onTapEdited,
    required this.onToggleReaction,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final deleted = message.deletedByPeer;

    final bubbleColor = deleted
        ? (p.isDark ? const Color(0xFF241F17) : const Color(0xFFFFF6E5))
        : isMine
            ? p.bubbleOut
            : p.bubbleIn;

    final textColor = isMine ? p.bubbleOutText : p.bubbleInText;
    final metaColor = isMine ? const Color(0xCCFFFFFF) : p.fg3;
    final quoteAccent = isMine ? Colors.white : p.accent;

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(isMine ? 14 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 14),
    );

    final timeStr = DateFormat('HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(message.time),
    );

    return GestureDetector(
      onTap: onTapMenu,
      onSecondaryTap: onTapMenu,
      onLongPress: onTapMenu,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2.5),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: borderRadius,
          border: deleted
              ? Border.all(color: p.warningLine)
              : isMine
                  ? null
                  : Border.all(color: p.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (deleted)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: p.warningSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TalerIcon(TalerIcons.shield, size: 13, color: p.warning),
                    const SizedBox(width: 5),
                    Text(
                      'Удалено собеседником · сохранено',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: p.warning,
                      ),
                    ),
                  ],
                ),
              ),
            if (showSenderName)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  senderName,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: p.peerColorForId(message.senderId),
                  ),
                ),
              ),
            if (message.forwardedFromName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Переслано от ${message.forwardedFromName}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: quoteAccent,
                  ),
                ),
              ),
            if (message.replyTo != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(9, 4, 8, 4),
                decoration: BoxDecoration(
                  color: quoteAccent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border(
                    left: BorderSide(color: quoteAccent, width: 2.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.replyTo!.senderName ?? 'Ответ',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: quoteAccent,
                      ),
                    ),
                    Text(
                      message.replyTo!.text ?? 'Вложение',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            for (final att in message.attachments)
              _AttachmentView(attachment: att, isMine: isMine),
            if (message.text.isNotEmpty)
              SelectableText(
                message.text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.38,
                  color: textColor,
                ),
              ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (message.reactions.isNotEmpty)
                  Flexible(
                    child: Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        for (final r in message.reactions)
                          GestureDetector(
                            onTap: () => onToggleReaction(r.emoji),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: isMine
                                    ? const Color(0x2EFFFFFF)
                                    : r.isMine
                                        ? p.bubbleOut
                                        : p.bg3,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${r.emoji} ${r.count}',
                                style: TalerTheme.tabularStyle(
                                  size: 11.5,
                                  weight: FontWeight.w600,
                                  color: (r.isMine || isMine)
                                      ? Colors.white
                                      : textColor,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (message.reactions.isNotEmpty) const SizedBox(width: 8),
                if (message.isEdited) ...[
                  GestureDetector(
                    onTap: onTapEdited,
                    child: Text(
                      'изм.',
                      style: TextStyle(
                        fontSize: 11,
                        color: metaColor,
                        decoration: TextDecoration.underline,
                        decorationColor: metaColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  timeStr,
                  style: TalerTheme.tabularStyle(
                    size: 11,
                    color: metaColor,
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 3),
                  TalerIcon(
                    TalerIcons.checkCheck,
                    size: 14,
                    color: metaColor,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentView extends StatelessWidget {
  final TalerAttachment attachment;
  final bool isMine;

  const _AttachmentView({required this.attachment, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    if (attachment.type == 'PHOTO' && attachment.url != null) {
      final url = attachment.url!;
      final isHttp = url.startsWith('http://') || url.startsWith('https://');
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: isHttp
              ? Image.network(
                  url,
                  width: 260,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                )
              : Image.file(
                  File(url),
                  width: 260,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
        ),
      );
    }

    if (attachment.type == 'CONTROL') {
      return const SizedBox.shrink();
    }

    final sizeKb = attachment.fileSize != null
        ? '${(attachment.fileSize! / 1024).toStringAsFixed(1)} КБ'
        : attachment.type;
    final textColor = isMine ? p.bubbleOutText : p.bubbleInText;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isMine ? const Color(0x26FFFFFF) : p.bg3,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isMine ? Colors.white : p.bubbleOut,
              shape: BoxShape.circle,
            ),
            child: TalerIcon(
              TalerIcons.file,
              size: 17,
              color: isMine ? p.bubbleOut : Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName ??
                      attachment.previewText ??
                      attachment.type,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
                Text(
                  sizeKb,
                  style: TalerTheme.tabularStyle(
                    size: 11,
                    color: textColor.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

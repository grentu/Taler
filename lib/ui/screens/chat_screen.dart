import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/storage/taler_models.dart';
import '../theme/taler_theme.dart';

/// Экран открытого диалога / чата / канала в монохромной тактильной системе Taler.
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
  final _scrollCtrl = ScrollController();

  TalerMessage? _replyingTo;
  TalerMessage? _editingMessage;
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
          duration: const Duration(milliseconds: 220),
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
        final messages = widget.client.messagesForChat(widget.chat.id);
        final ghost = widget.client.privacySettings.ghostModeOnline;

        return Column(
          children: [
            // Единая шапка 56px
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: p.bg2,
                border: Border(bottom: BorderSide(color: p.line)),
              ),
              child: Row(
                children: [
                  if (widget.showBackButton) ...[
                    TalerIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Назад',
                      onPressed:
                          widget.onBack ?? () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.line2),
                    ),
                    child: Text(
                      liveChat.initials,
                      style: TextStyle(
                        color: p.fg,
                        fontWeight: FontWeight.w500,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
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
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14.5,
                                  color: p.fg,
                                ),
                              ),
                            ),
                            if (liveChat.isOfficial) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.verified_outlined,
                                size: 14,
                                color: p.fg2,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 1),
                        Row(
                          children: [
                            if (liveChat.isOnline ||
                                liveChat.typingLabel != null) ...[
                              TalerStatusDot(color: p.statusLive, size: 6),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                _subtitleForChat(liveChat),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TalerTheme.tabularStyle(
                                  size: 12,
                                  color: liveChat.typingLabel != null ||
                                          liveChat.isOnline
                                      ? p.statusLive
                                      : p.fg3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (ghost)
                    Tooltip(
                      message: 'Режим Призрака: статус онлайн скрыт',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: p.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: p.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.visibility_off_outlined,
                              size: 13,
                              color: p.fg2,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Призрак',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: p.fg2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Лента сообщений
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 24,
                            color: p.fg3,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Нет сообщений в локальном кэше',
                            style: TextStyle(fontSize: 13, color: p.fg3),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMine = msg.senderId == myId;
                        return _MessageBubble(
                          message: msg,
                          isMine: isMine,
                          showSenderName: !isMine && !liveChat.isDialog,
                          senderName: widget.client.senderDisplayName(
                            msg.senderId,
                            chatId: liveChat.id,
                          ),
                          onTapMenu: () => _showMessageActions(msg, isMine),
                          onTapEdited: () => _showEditHistory(msg),
                          onToggleReaction: (emoji) => widget.client
                              .toggleReaction(liveChat.id, msg.id, emoji),
                        );
                      },
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
                    Icon(
                      _editingMessage != null
                          ? Icons.edit_outlined
                          : Icons.reply_rounded,
                      size: 16,
                      color: p.fg2,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _editingMessage != null
                                ? 'Редактирование'
                                : 'Ответ · ${widget.client.senderDisplayName(_replyingTo!.senderId, chatId: liveChat.id)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: p.fg,
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
                      icon: Icons.close_rounded,
                      size: 32,
                      iconSize: 16,
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

            // Нижняя панель ввода
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: p.bg2,
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    TalerIconButton(
                      icon: Icons.attach_file_rounded,
                      tooltip: 'Прикрепить файл',
                      onPressed: _pickAttachment,
                    ),
                    const SizedBox(width: 8),
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
                              ? 'Сообщение · набор скрыт'
                              : 'Сообщение',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TalerIconButton(
                      icon: Icons.arrow_upward_rounded,
                      tooltip: 'Отправить',
                      circle: true,
                      size: 38,
                      iconSize: 18,
                      backgroundColor: p.solid,
                      color: p.onSolid,
                      onPressed: _send,
                    ),
                  ],
                ),
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
    return 'офлайн';
  }

  void _showEditHistory(TalerMessage msg) {
    final p = TalerTheme.paletteOf(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'История изменений',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
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
                        style: TextStyle(fontSize: 11.5, color: p.fg3),
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
                          style: TalerTheme.monoStyle(size: 11, color: p.fg3),
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
    const quickEmojis = ['👍', '❤️', '🔥', '👀', '✓', '😂'];

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ручка нижней шторки (44x4px)
              Container(
                width: 44,
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
                          color: p.surface,
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
                      icon: Icons.reply_rounded,
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
                        icon: Icons.copy_rounded,
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
                        icon: Icons.edit_outlined,
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
                        icon: Icons.history_rounded,
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
                        icon: Icons.shield_outlined,
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
                      icon: Icons.delete_outline_rounded,
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

class _SheetActionRow extends StatelessWidget {
  final IconData icon;
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
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color ?? p.fg2),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13.5, color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final TalerMessage message;
  final bool isMine;
  final bool showSenderName;
  final String senderName;
  final VoidCallback onTapMenu;
  final VoidCallback onTapEdited;
  final ValueChanged<String> onToggleReaction;

  const _MessageBubble({
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
        ? p.warningSurface
        : isMine
            ? p.surface2
            : p.bg2;

    final borderColor = deleted
        ? p.warningLine
        : isMine
            ? p.line2
            : p.line;

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMine ? 16 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 16),
    );

    final timeStr = DateFormat('HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(message.time),
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GestureDetector(
          onTap: onTapMenu,
          onSecondaryTap: onTapMenu,
          onLongPress: onTapMenu,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: borderRadius,
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (deleted)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.warningLine),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TalerStatusDot(color: p.warning, size: 6),
                        const SizedBox(width: 6),
                        Text(
                          'Удалено собеседником · сохранено',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: p.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (showSenderName)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      senderName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: p.fg2,
                      ),
                    ),
                  ),
                if (message.forwardedFromName != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: p.line2, width: 2),
                      ),
                    ),
                    child: Text(
                      'Переслано · ${message.forwardedFromName}',
                      style: TextStyle(fontSize: 11.5, color: p.fg2),
                    ),
                  ),
                if (message.replyTo != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: p.fg2, width: 2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.replyTo!.senderName ?? 'Ответ',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: p.fg,
                          ),
                        ),
                        Text(
                          message.replyTo!.text ?? 'Вложение',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: p.fg2),
                        ),
                      ],
                    ),
                  ),
                for (final att in message.attachments)
                  _AttachmentView(attachment: att),
                if (message.text.isNotEmpty)
                  SelectableText(
                    message.text,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: p.fg,
                    ),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final r in message.reactions)
                      GestureDetector(
                        onTap: () => onToggleReaction(r.emoji),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: r.isMine ? p.solid : p.surface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: r.isMine ? p.solid : p.line,
                            ),
                          ),
                          child: Text(
                            '${r.emoji} ${r.count}',
                            style: TalerTheme.monoStyle(
                              size: 11.5,
                              color: r.isMine ? p.onSolid : p.fg2,
                            ),
                          ),
                        ),
                      ),
                    if (message.isEdited)
                      GestureDetector(
                        onTap: onTapEdited,
                        child: Text(
                          'изменено',
                          style: TextStyle(
                            fontSize: 11,
                            color: p.fg2,
                            decoration: TextDecoration.underline,
                            decorationColor: p.fg3,
                          ),
                        ),
                      ),
                    Text(
                      timeStr,
                      style: TalerTheme.monoStyle(size: 11, color: p.fg3),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentView extends StatelessWidget {
  final TalerAttachment attachment;

  const _AttachmentView({required this.attachment});

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

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 18,
            color: p.fg2,
          ),
          const SizedBox(width: 8),
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
                    color: p.fg,
                  ),
                ),
                Text(
                  sizeKb,
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

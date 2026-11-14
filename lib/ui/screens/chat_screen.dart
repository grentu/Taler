import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../backend/taler_client.dart';
import '../../core/storage/taler_models.dart';
import '../theme/taler_theme.dart';

/// Экран открытого диалога/чата/канала.
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
          curve: Curves.easeOut,
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
    final theme = Theme.of(context);
    final myId = widget.client.currentUser?.id ?? 1;

    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.client,
        widget.client.privacySettings,
      ]),
      builder: (context, _) {
        final liveChat = widget.client.store.chats[widget.chat.id] ?? widget.chat;
        final messages = widget.client.messagesForChat(widget.chat.id);
        final ghost = widget.client.privacySettings.ghostModeOnline;

        return Column(
          children: [
            // Шапка чата
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  bottom: BorderSide(color: theme.dividerColor),
                ),
              ),
              child: Row(
                children: [
                  if (widget.showBackButton)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
                    ),
                  CircleAvatar(
                    radius: 19,
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.16),
                    child: Text(
                      liveChat.initials,
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (liveChat.isOfficial) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.verified,
                                size: 15,
                                color: theme.colorScheme.primary,
                              ),
                            ],
                          ],
                        ),
                        Text(
                          _subtitleForChat(liveChat),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: liveChat.typingLabel != null || liveChat.isOnline
                                ? TalerTheme.shieldGreen
                                : theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (ghost)
                    Tooltip(
                      message: 'Режим Призрака активен',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: TalerTheme.shieldGreen.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.visibility_off_outlined,
                              size: 14,
                              color: TalerTheme.shieldGreen,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Призрак',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
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

            // Лента сообщений
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Text(
                        'Нет сообщений в локальном кэше',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
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

            // Баннер ответа / редактирования
            if (_replyingTo != null || _editingMessage != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(top: BorderSide(color: theme.dividerColor)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _editingMessage != null
                          ? Icons.edit_outlined
                          : Icons.reply_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _editingMessage != null
                                ? 'Редактирование сообщения'
                                : 'Ответ: ${widget.client.senderDisplayName(_replyingTo!.senderId, chatId: liveChat.id)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            (_editingMessage ?? _replyingTo)!.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
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

            // Поле ввода
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _pickAttachment,
                      tooltip: 'Прикрепить фото или файл',
                      icon: const Icon(Icons.attach_file_rounded),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _inputCtrl,
                        onChanged: _onTextChanged,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: widget.client.privacySettings.hideTyping
                              ? 'Сообщение (набор скрыт)...'
                              : 'Написать сообщение...',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _send,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Icon(Icons.send_rounded, size: 20),
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
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('История изменений'),
        content: SizedBox(
          width: 380,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'Текущая версия:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(msg.text),
              const Divider(height: 20),
              for (final rev in msg.editHistory.reversed) ...[
                Text(
                  DateFormat('dd.MM.yyyy HH:mm:ss').format(
                    DateTime.fromMillisecondsSinceEpoch(rev.timestamp),
                  ),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(rev.text),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _showMessageActions(TalerMessage msg, bool isMine) {
    const quickEmojis = ['👍', '❤️', '🔥', '👀', '🛡️', '😂'];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final emoji in quickEmojis)
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          widget.client.toggleReaction(
                            widget.chat.id,
                            msg.id,
                            emoji,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(emoji, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Ответить'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() {
                    _editingMessage = null;
                    _replyingTo = msg;
                  });
                },
              ),
              if (msg.text.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Копировать текст'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: msg.text));
                    Navigator.of(ctx).pop();
                  },
                ),
              if (isMine && !msg.deletedByPeer)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Редактировать'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    setState(() {
                      _replyingTo = null;
                      _editingMessage = msg;
                      _inputCtrl.text = msg.text;
                    });
                  },
                ),
              if (msg.isEdited)
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: const Text('Посмотреть историю изменений'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showEditHistory(msg);
                  },
                ),
              if (widget.client.isDemoMode && !msg.deletedByPeer)
                ListTile(
                  leading: const Icon(
                    Icons.shield_outlined,
                    color: TalerTheme.warningAmber,
                  ),
                  title: const Text('Симулировать удаление собеседником'),
                  subtitle: const Text('Проверка режима Anti-Delete'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    widget.client.simulatePeerDeleteInDemo(
                      widget.chat.id,
                      msg.id,
                    );
                  },
                ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: TalerTheme.dangerRed,
                ),
                title: const Text(
                  'Удалить у себя',
                  style: TextStyle(color: TalerTheme.dangerRed),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.client.deleteMessage(widget.chat.id, msg.id);
                },
              ),
            ],
          ),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final deleted = message.deletedByPeer;

    final bubbleColor = deleted
        ? TalerTheme.warningAmber.withValues(alpha: isDark ? 0.14 : 0.10)
        : isMine
            ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.14)
            : theme.colorScheme.surface;

    final borderColor = deleted
        ? TalerTheme.warningAmber.withValues(alpha: 0.65)
        : isMine
            ? theme.colorScheme.primary.withValues(alpha: 0.35)
            : theme.dividerColor;

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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
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
                      color: TalerTheme.warningAmber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 13,
                          color: TalerTheme.warningAmber,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Удалено собеседником — сохранено Taler',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: TalerTheme.warningAmber,
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
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                if (message.forwardedFromName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Переслано от ${message.forwardedFromName}',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (message.replyTo != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.replyTo!.senderName ?? 'Ответ',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Text(
                          message.replyTo!.text ?? '[Вложение]',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                for (final att in message.attachments)
                  _AttachmentView(attachment: att),
                if (message.text.isNotEmpty)
                  SelectableText(
                    message.text,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.38),
                  ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final r in message.reactions)
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onToggleReaction(r.emoji),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: r.isMine
                                ? theme.colorScheme.primary
                                    .withValues(alpha: 0.2)
                                : theme.colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: r.isMine
                                  ? theme.colorScheme.primary
                                  : theme.dividerColor,
                            ),
                          ),
                          child: Text(
                            '${r.emoji} ${r.count}',
                            style: const TextStyle(fontSize: 12),
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
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    Text(
                      timeStr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
    final theme = Theme.of(context);
    if (attachment.type == 'PHOTO' && attachment.url != null) {
      final url = attachment.url!;
      final isHttp = url.startsWith('http://') || url.startsWith('https://');
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
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
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName ?? attachment.previewText ?? attachment.type,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  sizeKb,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/storage/taler_models.dart';
import '../icons/taler_icon.dart';
import '../theme/chat_tokens.dart';
import '../theme/taler_theme.dart';
import '../widgets/chat_info_panel.dart';
import '../widgets/message_bubble.dart';

/// Открытый диалог, группа или канал. На широком экране справа — профиль.
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

/// Элемент ленты: разделитель дня или сообщение с признаками склейки.
class _Entry {
  final TalerMessage? message;
  final int? day;
  final bool first;
  final bool last;

  const _Entry.day(this.day)
      : message = null,
        first = false,
        last = false;

  const _Entry.message(this.message, {required this.first, required this.last}) : day = null;
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();
  final _searchFocus = FocusNode();
  final _bottomBarKey = GlobalKey();

  TalerMessage? _replyingTo;
  TalerMessage? _editingMessage;
  bool _showInfo = true;
  bool _showSearch = false;
  bool _wasReady = false;
  String _query = '';
  double? _measuredBottomHeight;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _mobile => widget.showBackButton;

  @override
  void initState() {
    super.initState();
    _wasReady = widget.client.isSessionReady;
    widget.client.setActiveChat(widget.chat.id);
    widget.client.addListener(_onClientChanged);
    _scrollCtrl.addListener(_onScroll);
    _loadChatData();
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chat.id != widget.chat.id) {
      _replyingTo = null;
      _editingMessage = null;
      _showSearch = false;
      _query = '';
      _searchCtrl.clear();
      _inputCtrl.clear();
      widget.client.setActiveChat(widget.chat.id);
      _loadChatData();
    }
  }

  void _onClientChanged() {
    final ready = widget.client.isSessionReady;
    if (!_wasReady && ready) {
      _wasReady = true;
      _loadChatData();
    } else if (_wasReady && !ready) {
      _wasReady = false;
    }
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      unawaited(widget.client.loadMoreHistory(widget.chat.id));
    }
  }

  void _loadChatData() {
    final id = widget.chat.id;
    widget.client.loadHistory(id).then<void>(
      (_) {
        if (mounted) widget.client.resolveChatMembers(id);
      },
      onError: (Object _) {},
    );
    widget.client.markChatRead(id);
  }

  @override
  void dispose() {
    widget.client.removeListener(_onClientChanged);
    _scrollCtrl.removeListener(_onScroll);
    widget.client.clearActiveChat(widget.chat.id);
    _inputCtrl.dispose();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _showErrorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
      try {
        await widget.client.editMessage(widget.chat.id, editing.id, text);
      } catch (e) {
        if (mounted) {
          _inputCtrl.text = text;
        }
        _showErrorSnack('Не удалось изменить сообщение: $e');
        return;
      }
    } else {
      _scrollToBottom();
      try {
        await widget.client.sendMessage(widget.chat.id, text, replyTo: reply);
      } catch (e) {
        _showErrorSnack('Сообщение не отправлено: $e');
        return;
      }
    }
    _scrollToBottom();
  }

  Future<void> _retryMessage(TalerMessage msg) async {
    try {
      await widget.client.retrySendMessage(widget.chat.id, msg.id);
    } catch (e) {
      _showErrorSnack('Не удалось отправить повторно: $e');
    }
  }

  Future<void> _deleteMessage(TalerMessage msg, {bool forEveryone = false}) async {
    try {
      await widget.client.deleteMessage(
        widget.chat.id,
        msg.id,
        forEveryone: forEveryone,
      );
    } catch (e) {
      _showErrorSnack('Не удалось удалить сообщение: $e');
    }
  }

  Future<void> _toggleReaction(TalerMessage msg, String emoji) async {
    try {
      await widget.client.toggleReaction(widget.chat.id, msg.id, emoji);
    } catch (e) {
      _showErrorSnack('Не удалось обновить реакцию: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 200), curve: TalerTheme.easeOutCurve);
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
      await widget.client.sendFileAttachment(widget.chat.id, filePath: path, fileName: file.name, isImage: isImage);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось отправить файл: $e')));
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

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _query = '';
        _searchCtrl.clear();
        _searchFocus.unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  void _openSearch() {
    if (!_showSearch) _toggleSearch();
  }

  void _toggleInfo(bool canDock, TalerChat chat) {
    if (canDock) {
      setState(() => _showInfo = !_showInfo);
    } else {
      _openInfoPage(chat);
    }
  }

  void _openInfoPage(TalerChat chat) {
    FocusManager.instance.primaryFocus?.unfocus();
    final client = widget.client;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (ctx) {
              final p = TalerTheme.paletteOf(ctx);
              return Scaffold(
                backgroundColor: p.bg2,
                body: SafeArea(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            const SizedBox(width: 4),
                            TalerIconButton(
                              icon: TalerIcons.arrowLeft,
                              tooltip: 'Назад',
                              iconSize: 22,
                              color: p.accent,
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListenableBuilder(
                          listenable: Listenable.merge([client, client.privacySettings]),
                          builder: (ctx, _) => ChatInfoPanel(
                            client: client,
                            chat: client.store.chats[chat.id] ?? chat,
                            messages: client.messagesForChat(chat.id),
                            fullScreen: true,
                            onSearch: () {
                              Navigator.of(ctx).pop();
                              _openSearch();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        )
        .whenComplete(() {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_showSearch) {
              FocusManager.instance.primaryFocus?.unfocus();
            }
          });
        });
  }

  void _syncBottomHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _bottomBarKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final h = box.size.height;
      if (_measuredBottomHeight == null || (h - _measuredBottomHeight!).abs() > 1.0) {
        setState(() => _measuredBottomHeight = h);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.client, widget.client.privacySettings]),
      builder: (context, _) {
        final chat = widget.client.store.chats[widget.chat.id] ?? widget.chat;
        final all = widget.client.messagesForChat(widget.chat.id);
        final q = _query.toLowerCase();
        final messages = q.isEmpty ? all : all.where((m) => m.text.toLowerCase().contains(q)).toList();
        final canDock = !_mobile && MediaQuery.sizeOf(context).width >= 1100;
        final mediaPad = MediaQuery.paddingOf(context);
        final topInset = (_mobile ? mediaPad.top + 56.0 : 60.0) + (_showSearch ? 53.0 : 0.0);
        final fallbackBottom = (_mobile ? 62.0 + mediaPad.bottom : 74.0) +
            ((_replyingTo != null || _editingMessage != null) ? 48.0 : 0.0);
        final bottomInset = _measuredBottomHeight ?? fallbackBottom;
        final glassBg = p.bg2.withValues(alpha: p.isDark ? 0.78 : 0.84);
        final bottomGlassBg = (_mobile ? p.bg2 : ChatTokens.chatBackground(p)).withValues(
          alpha: p.isDark ? 0.76 : 0.84,
        );

        _syncBottomHeight();

        final stack = Stack(
          children: [
            Positioned.fill(
              child: _messageList(
                p,
                chat,
                messages,
                topInset: topInset,
                bottomInset: bottomInset,
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: ColoredBox(
                    color: glassBg,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _header(p, chat, canDock),
                        if (_showSearch) _searchBar(p),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: KeyedSubtree(
                key: _bottomBarKey,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: ColoredBox(
                      color: bottomGlassBg,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_replyingTo != null || _editingMessage != null) _replyBar(p, chat),
                          _composer(p),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

        final center = ColoredBox(color: ChatTokens.chatBackground(p), child: stack);
        final wrapped = _mobile
            ? PopScope(
                onPopInvokedWithResult: (didPop, _) {
                  if (didPop) {
                    FocusManager.instance.primaryFocus?.unfocus();
                  }
                },
                child: center,
              )
            : center;
        if (!(canDock && _showInfo)) return wrapped;
        return Row(
          children: [
            Expanded(child: wrapped),
            SizedBox(
              width: 340,
              child: ChatInfoPanel(
                key: ValueKey('info_${chat.id}'),
                client: widget.client,
                chat: chat,
                messages: all,
                onClose: () => setState(() => _showInfo = false),
                onSearch: _openSearch,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(TalerPalette p, TalerChat chat, bool canDock) {
    final peer = chat.peerId != null ? widget.client.contactById(chat.peerId!) : null;
    final offline = !widget.client.isDemoMode && !widget.client.isSessionReady;
    final live = !offline && (chat.isOnline || (chat.typingLabel?.isNotEmpty ?? false));
    final subtitle = offline ? 'Подключение…' : ChatTokens.chatStatus(chat);
    return SafeArea(
      bottom: false,
      top: _mobile,
      child: Container(
        height: _mobile ? 56 : 60,
        padding: EdgeInsets.only(left: _mobile ? 4 : 20, right: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
          child: Row(
            children: [
              if (_mobile) ...[
                TalerIconButton(
                  icon: TalerIcons.arrowLeft,
                  tooltip: 'Назад',
                  iconSize: 22,
                  color: p.accent,
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    (widget.onBack ?? () => Navigator.of(context).maybePop())();
                  },
                ),
                const SizedBox(width: 2),
              ],
              TalerAvatar(
                seedId: chat.peerId ?? chat.id,
                initials: chat.initials,
                imageUrl: chat.avatarUrl ?? peer?.avatarUrl,
                size: _mobile ? 36 : 40,
                onlineBorderColor: p.bg2,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleInfo(canDock, chat),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              chat.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.fg),
                            ),
                          ),
                          if (chat.isOfficial) ...[
                            const SizedBox(width: 4),
                            TalerIcon(TalerIcons.badgeCheck, size: 15, color: p.accent, strokeWidth: 2),
                          ],
                        ],
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: live ? p.accent : p.fg3),
                      ),
                    ],
                  ),
                ),
              ),
              TalerIconButton(
                icon: TalerIcons.search,
                tooltip: 'Поиск в чате',
                iconSize: 18,
                color: _showSearch ? p.fg : p.fg2,
                onPressed: _toggleSearch,
              ),
              if (!_mobile)
                TalerIconButton(
                  icon: TalerIcons.panelLeft,
                  tooltip: _showInfo && canDock ? 'Скрыть профиль' : 'Показать профиль',
                  iconSize: 18,
                  color: canDock && _showInfo ? p.fg : p.fg2,
                  onPressed: () => _toggleInfo(canDock, chat),
                ),
            ],
          ),
        ),
    );
  }

  Widget _searchBar(TalerPalette p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(color: p.bg3, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            TalerIcon(TalerIcons.search, size: 16, color: p.fg3),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => _query = v.trim()),
                onSubmitted: (_) => _searchFocus.unfocus(),
                style: TextStyle(fontSize: 14, color: p.fg),
                decoration: InputDecoration(
                  hintText: 'Поиск по переписке',
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
            TalerIconButton(icon: TalerIcons.close, tooltip: 'Закрыть поиск', size: 32, iconSize: 15, color: p.fg3, onPressed: _toggleSearch),
          ],
        ),
      ),
    );
  }

  List<_Entry> _entries(List<TalerMessage> messages) {
    final out = <_Entry>[];
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final prev = i > 0 ? messages[i - 1] : null;
      final next = i + 1 < messages.length ? messages[i + 1] : null;
      final newDay = prev == null || !ChatTokens.sameDay(prev.time, m.time);
      final nextNewDay = next == null || !ChatTokens.sameDay(m.time, next.time);
      if (newDay) out.add(_Entry.day(m.time));
      final first = prev == null || newDay || prev.senderId != m.senderId || prev.isControl;
      final last = next == null || nextNewDay || next.senderId != m.senderId || next.isControl;
      out.add(_Entry.message(m, first: first, last: last));
    }
    return out;
  }

  Widget _messageList(
    TalerPalette p,
    TalerChat chat,
    List<TalerMessage> messages, {
    required double topInset,
    required double bottomInset,
  }) {
    if (messages.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
        child: Center(child: ChatDayChip(label: _query.isEmpty ? 'Сообщений пока нет' : 'Ничего не найдено')),
      );
    }
    final myId = widget.client.currentUser?.id ?? 1;
    final entries = _entries(messages);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final side = _mobile ? 10.0 : math.max(24.0, (width - 760) / 2);
        final content = width - side * 2;
        final maxBubble = content * (_mobile ? 0.82 : 0.68);
        return ListView.builder(
          controller: _scrollCtrl,
          reverse: true,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(side, topInset + 12, side, bottomInset + 10),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final e = entries[entries.length - 1 - index];
            final day = e.day;
            if (day != null) return ChatDayChip(label: ChatTokens.dayLabel(day));
            final m = e.message!;
            final isMine = m.senderId == myId;
            final group = chat.isGroup;
            return MessageRow(
              key: ValueKey(m.id),
              message: m,
              isMine: isMine,
              firstInRun: e.first,
              lastInRun: e.last,
              showSender: group && !isMine,
              senderName: widget.client.senderDisplayName(m.senderId, chatId: chat.id),
              senderAvatarUrl: widget.client.contactById(m.senderId)?.avatarUrl,
              maxBubbleWidth: math.max(
                120.0,
                group && !isMine ? maxBubble - 44 : maxBubble,
              ),
              peerReadMark: chat.peerReadMark,
              onActions: () => _showMessageActions(m, isMine),
              onShowHistory: m.isEdited ? () => _showEditHistory(m) : null,
              onRetry: m.status == 'error' ? () => _retryMessage(m) : null,
              onToggleReaction: (emoji) => _toggleReaction(m, emoji),
            );
          },
        );
      },
    );
  }

  Widget _replyBar(TalerPalette p, TalerChat chat) {
    final editing = _editingMessage;
    final target = editing ?? _replyingTo!;
    final title = editing != null
        ? 'Изменение сообщения'
        : 'Ответ ${widget.client.senderDisplayName(target.senderId, chatId: chat.id)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
      child: Row(
        children: [
          TalerIcon(editing != null ? TalerIcons.pencil : TalerIcons.reply, size: 18, color: p.accent),
          const SizedBox(width: 12),
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.accent),
                ),
                Text(
                  target.text.isEmpty ? 'Вложение' : target.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: p.fg2),
                ),
              ],
            ),
          ),
          TalerIconButton(
            icon: TalerIcons.close,
            tooltip: 'Отменить',
            size: 32,
            iconSize: 16,
            color: p.fg3,
            onPressed: () => setState(() {
              if (_editingMessage != null) _inputCtrl.clear();
              _replyingTo = null;
              _editingMessage = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _composer(TalerPalette p) {
    final textField = TextField(
      controller: _inputCtrl,
      focusNode: _inputFocus,
      onChanged: _onTextChanged,
      minLines: 1,
      maxLines: 6,
      textCapitalization: TextCapitalization.sentences,
      keyboardType: TextInputType.multiline,
      style: TextStyle(fontSize: 15, color: p.fg),
      decoration: InputDecoration(
        hintText: 'Сообщение',
        hintStyle: TextStyle(fontSize: 15, color: p.fg3),
        isDense: true,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(vertical: 9),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );
    final field = _mobile
        ? textField
        : CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.enter): _send,
            },
            child: textField,
          );
    final box = Container(
      padding: EdgeInsets.all(_mobile ? 4 : 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(_mobile ? 22 : 16),
        border: Border.all(color: p.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TalerIconButton(
            icon: TalerIcons.paperclip,
            tooltip: 'Прикрепить файл',
            iconSize: 20,
            color: p.fg3,
            onPressed: _pickAttachment,
          ),
          const SizedBox(width: 2),
          Expanded(child: field),
          const SizedBox(width: 4),
          TalerIconButton(
            icon: _editingMessage != null ? TalerIcons.check : TalerIcons.send,
            tooltip: _editingMessage != null ? 'Сохранить' : 'Отправить',
            circle: true,
            iconSize: 17,
            color: Colors.white,
            backgroundColor: p.accent,
            onPressed: _send,
          ),
        ],
      ),
    );
    return Container(
      decoration: _mobile ? BoxDecoration(border: Border(top: BorderSide(color: p.line))) : null,
      padding: _mobile ? const EdgeInsets.fromLTRB(8, 6, 8, 8) : const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _mobile ? double.infinity : 760),
            child: box,
          ),
        ),
      ),
    );
  }

  void _showMessageActions(TalerMessage msg, bool isMine) {
    const quick = ['👍', '❤️', '🔥', '😂', '😮', '🙏'];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final p = TalerTheme.paletteOf(ctx);
        Widget action(TalerIconData icon, String label, VoidCallback onTap, {Color? color}) {
          return InkWell(
            onTap: () {
              Navigator.of(ctx).pop();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  TalerIcon(icon, size: 20, color: color ?? p.fg2),
                  const SizedBox(width: 16),
                  Text(label, style: TextStyle(fontSize: 15, color: color ?? p.fg)),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                decoration: BoxDecoration(color: p.fg4, borderRadius: BorderRadius.circular(999)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final emoji in quick)
                      GestureDetector(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _toggleReaction(msg, emoji);
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: p.bg3, shape: BoxShape.circle),
                          child: Text(emoji, style: const TextStyle(fontSize: 20)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: p.line),
              if (isMine && msg.status == 'error')
                action(
                  TalerIcons.refresh,
                  'Повторить отправку',
                  () => _retryMessage(msg),
                  color: p.accent,
                ),
              action(TalerIcons.reply, 'Ответить', () {
                setState(() {
                  _editingMessage = null;
                  _replyingTo = msg;
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _inputFocus.requestFocus();
                });
              }),
              if (msg.text.isNotEmpty)
                action(TalerIcons.copy, 'Копировать текст', () => Clipboard.setData(ClipboardData(text: msg.text))),
              if (isMine && !msg.deletedByPeer && msg.status != 'error' && !msg.id.startsWith('temp_'))
                action(TalerIcons.pencil, 'Изменить', () {
                  setState(() {
                    _replyingTo = null;
                    _editingMessage = msg;
                    _inputCtrl.text = msg.text;
                    _inputCtrl.selection = TextSelection.collapsed(
                      offset: _inputCtrl.text.length,
                    );
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _inputFocus.requestFocus();
                  });
                }),
              if (msg.isEdited) action(TalerIcons.history, 'История правок', () => _showEditHistory(msg)),
              if (widget.client.isDemoMode && !msg.deletedByPeer)
                action(
                  TalerIcons.shield,
                  'Симулировать удаление собеседником',
                  () => widget.client.simulatePeerDeleteInDemo(widget.chat.id, msg.id),
                  color: p.warning,
                ),
              if (isMine && !msg.deletedByPeer && msg.status != 'error' && !msg.id.startsWith('temp_'))
                action(
                  TalerIcons.trash,
                  'Удалить у всех',
                  () => _deleteMessage(msg, forEveryone: true),
                  color: p.danger,
                ),
              action(
                TalerIcons.trash,
                'Удалить у себя',
                () => _deleteMessage(msg, forEveryone: false),
                color: p.danger,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showEditHistory(TalerMessage msg) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final p = TalerTheme.paletteOf(ctx);
        Widget entry(String label, String text) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TalerTheme.tabularStyle(size: 12, color: p.fg3)),
                  const SizedBox(height: 4),
                  Text(text, style: TextStyle(fontSize: 14, color: p.fg)),
                ],
              ),
            );
        return AlertDialog(
          title: Text('История правок', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.fg)),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                entry('Сейчас', msg.text),
                for (final rev in msg.editHistory.reversed) ...[
                  Divider(height: 1, color: p.line),
                  entry(
                    DateFormat('dd.MM.yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(rev.timestamp)),
                    rev.text,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Закрыть')),
          ],
        );
      },
    );
  }
}

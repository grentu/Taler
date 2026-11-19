import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
  final PageController _pageCtrl = PageController();
  final ValueNotifier<double> _pagePosition = ValueNotifier<double>(0.0);
  String _query = '';
  String _filterId = 'all';
  bool _animatingToTab = false;

  @override
  void initState() {
    super.initState();
    _pageCtrl.addListener(_onPageScroll);
  }

  @override
  void dispose() {
    _pageCtrl
      ..removeListener(_onPageScroll)
      ..dispose();
    _pagePosition.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onPageScroll() {
    if (!_pageCtrl.hasClients) return;
    final page = _pageCtrl.page;
    if (page != null) {
      _pagePosition.value = page;
    }
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

  Future<void> _selectFilter(List<_ChatFilter> filters, int index, {bool powerSaving = false}) async {
    if (index < 0 || index >= filters.length) return;
    _searchFocus.unfocus();
    final targetId = filters[index].id;
    if (_filterId != targetId) {
      setState(() => _filterId = targetId);
    }
    if (!_pageCtrl.hasClients) {
      _pagePosition.value = index.toDouble();
      return;
    }
    final current = _pageCtrl.page ?? index.toDouble();
    if ((current - index).abs() < 0.01) return;
    if (powerSaving) {
      _pageCtrl.jumpToPage(index);
      _pagePosition.value = index.toDouble();
      return;
    }
    _animatingToTab = true;
    try {
      await _pageCtrl.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _animatingToTab = false;
    }
  }

  Widget _buildFolderPage(
    TalerPalette p,
    _ChatFilter filter,
    String q,
    bool compactDensity,
  ) {
    final client = widget.client;
    final chats = client.chats.where((c) {
      if (!filter.test(c)) return false;
      if (q.isEmpty) return true;
      return c.title.toLowerCase().contains(q) ||
          (c.lastMessageText ?? '').toLowerCase().contains(q);
    }).toList();

    if (chats.isEmpty) {
      return Center(
        child: Text(
          q.isEmpty ? 'Здесь пока нет чатов' : 'Ничего не найдено',
          style: TextStyle(fontSize: 14, color: p.fg3),
        ),
      );
    }

    return ListView.builder(
      key: PageStorageKey<String>('taler_folder_${filter.id}'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        widget.compact ? 0 : 8,
        6,
        widget.compact ? 0 : 8,
        8 + widget.bottomInset,
      ),
      itemCount: chats.length,
      itemBuilder: (context, i) {
        final chat = chats[i];
        return ChatRow(
          client: client,
          chat: chat,
          compact: widget.compact,
          compactDensity: compactDensity,
          selected: !widget.compact && chat.id == widget.selectedChatId,
          onTap: () {
            _searchFocus.unfocus();
            FocusManager.instance.primaryFocus?.unfocus();
            widget.onOpen(chat);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final client = widget.client;
    return ListenableBuilder(
      listenable: client.appPreferences,
      builder: (context, _) {
        final prefs = client.appPreferences;
        final filters = _filters();
        var activeIndex = filters.indexWhere((f) => f.id == _filterId);
        if (activeIndex < 0) activeIndex = 0;
        final active = filters[activeIndex];
        if (_pageCtrl.hasClients && !_animatingToTab) {
          final currentPage = _pageCtrl.page;
          if (currentPage != null && currentPage > filters.length - 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _pageCtrl.hasClients) {
                _pageCtrl.jumpToPage(activeIndex);
                _pagePosition.value = activeIndex.toDouble();
              }
            });
          }
        }
        final q = _query.toLowerCase();
        final online = client.isDemoMode || client.connectionState == TalerConnectionState.online;
        final hPad = widget.compact ? 16.0 : 12.0;

        return PopScope(
          canPop: _query.isEmpty && _filterId == 'all',
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_query.isNotEmpty) {
              _searchCtrl.clear();
              setState(() => _query = '');
              _searchFocus.unfocus();
            } else if (_filterId != 'all') {
              unawaited(
                _selectFilter(filters, 0, powerSaving: prefs.powerSavingMode),
              );
            }
          },
          child: Container(
            color: widget.compact ? p.settingsBg : p.bg2,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: widget.compact ? 56 : 54,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: hPad),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          online ? 'Чаты' : 'Подключение…',
                          style: TextStyle(
                            fontSize: widget.compact ? 26 : 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: widget.compact ? -0.4 : -0.2,
                            color: p.fg,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(hPad, 2, hPad, 10),
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
                    activeIndex: activeIndex,
                    activeId: active.id,
                    pagePosition: _pagePosition,
                    horizontalPadding: hPad,
                    unreadIn: (f) => prefs.showFolderBadges
                        ? client.chats
                            .where((c) => f.test(c) && c.unreadCount > 0 && !c.isMuted)
                            .length
                        : 0,
                    onSelectIndex: (idx) => unawaited(
                      _selectFilter(
                        filters,
                        idx,
                        powerSaving: prefs.powerSavingMode,
                      ),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageCtrl,
                      physics: const BouncingScrollPhysics(
                        parent: PageScrollPhysics(),
                      ),
                      itemCount: filters.length,
                      onPageChanged: (index) {
                        if (_animatingToTab) return;
                        if (index >= 0 && index < filters.length) {
                          final nextId = filters[index].id;
                          if (nextId != _filterId) {
                            _searchFocus.unfocus();
                            setState(() => _filterId = nextId);
                          }
                        }
                      },
                      itemBuilder: (context, index) => _buildFolderPage(
                        p,
                        filters[index],
                        q,
                        prefs.compactChatList,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

/// Вкладки папок с плавным скользящим индикатором и живой интерполяцией цвета при свайпе.
class _FolderTabs extends StatefulWidget {
  final List<_ChatFilter> filters;
  final int activeIndex;
  final String activeId;
  final ValueNotifier<double> pagePosition;
  final double horizontalPadding;
  final int Function(_ChatFilter) unreadIn;
  final ValueChanged<int> onSelectIndex;

  const _FolderTabs({
    required this.filters,
    required this.activeIndex,
    required this.activeId,
    required this.pagePosition,
    required this.horizontalPadding,
    required this.unreadIn,
    required this.onSelectIndex,
  });

  @override
  State<_FolderTabs> createState() => _FolderTabsState();
}

class _FolderTabsState extends State<_FolderTabs> {
  final GlobalKey _rowKey = GlobalKey();
  List<GlobalKey> _tabKeys = <GlobalKey>[];
  List<({double left, double width})> _metrics = const [];

  @override
  void initState() {
    super.initState();
    _syncKeys();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant _FolderTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final countChanged = oldWidget.filters.length != widget.filters.length;
    final labelsChanged = !countChanged &&
        Iterable<int>.generate(widget.filters.length).any(
          (i) =>
              oldWidget.filters[i].id != widget.filters[i].id ||
              oldWidget.filters[i].label != widget.filters[i].label,
        );
    if (countChanged || labelsChanged) {
      _syncKeys();
    }
    _scheduleMeasure();
    if (oldWidget.activeIndex != widget.activeIndex) {
      _scrollActiveTabIntoView();
    }
  }

  void _syncKeys() {
    _tabKeys = List<GlobalKey>.generate(
      widget.filters.length,
      (_) => GlobalKey(),
    );
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measure();
    });
  }

  void _measure() {
    final rowBox = _rowKey.currentContext?.findRenderObject() as RenderBox?;
    if (rowBox == null || !rowBox.hasSize) return;
    final next = <({double left, double width})>[];
    for (final key in _tabKeys) {
      final tabBox = key.currentContext?.findRenderObject() as RenderBox?;
      if (tabBox == null || !tabBox.hasSize) return;
      final offset = tabBox.localToGlobal(Offset.zero, ancestor: rowBox);
      next.add((left: offset.dx, width: tabBox.size.width));
    }
    var changed = next.length != _metrics.length;
    if (!changed) {
      for (var i = 0; i < next.length; i++) {
        if ((next[i].left - _metrics[i].left).abs() > 0.5 ||
            (next[i].width - _metrics[i].width).abs() > 0.5) {
          changed = true;
          break;
        }
      }
    }
    if (changed && mounted) {
      setState(() => _metrics = next);
    }
  }

  void _scrollActiveTabIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.activeIndex < 0 || widget.activeIndex >= _tabKeys.length) {
        return;
      }
      final ctx = _tabKeys[widget.activeIndex].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final sideInset = math.max(0.0, widget.horizontalPadding - 10.0);
    final hasMetrics = _metrics.length == widget.filters.length && _metrics.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
      child: SizedBox(
        height: 40,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: sideInset),
          child: ValueListenableBuilder<double>(
            valueListenable: widget.pagePosition,
            builder: (context, rawPage, _) {
              final maxIdx = math.max(0, widget.filters.length - 1);
              final page = rawPage.clamp(0.0, maxIdx.toDouble());
              double? indLeft;
              double? indWidth;
              if (hasMetrics) {
                final floor = page.floor().clamp(0, maxIdx);
                final ceil = page.ceil().clamp(0, maxIdx);
                final frac = (page - floor).clamp(0.0, 1.0);
                final a = _metrics[floor];
                final b = _metrics[ceil];
                // Пружинистое вытягивание индикатора при перелистывании папок.
                final tLeft = math.pow(frac, 1.35).toDouble();
                final tRight = math.pow(frac, 0.72).toDouble();
                final left = ui.lerpDouble(a.left + 8, b.left + 8, tLeft)!;
                final right = ui.lerpDouble(
                  a.left + a.width - 8,
                  b.left + b.width - 8,
                  tRight,
                )!;
                indLeft = left;
                indWidth = math.max(16.0, right - left);
              }

              return Stack(
                children: [
                  Row(
                    key: _rowKey,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < widget.filters.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        _FolderTab(
                          key: _tabKeys[i],
                          label: widget.filters[i].label,
                          count: widget.unreadIn(widget.filters[i]),
                          selectionProgress: (1.0 - (page - i).abs()).clamp(0.0, 1.0),
                          showFallbackIndicator: !hasMetrics && i == widget.activeIndex,
                          onTap: () => widget.onSelectIndex(i),
                        ),
                      ],
                    ],
                  ),
                  if (indLeft != null && indWidth != null)
                    Positioned(
                      left: indLeft,
                      width: indWidth,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: p.accent,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(2.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FolderTab extends StatelessWidget {
  final String label;
  final int count;
  final double selectionProgress;
  final bool showFallbackIndicator;
  final VoidCallback onTap;

  const _FolderTab({
    super.key,
    required this.label,
    required this.count,
    required this.selectionProgress,
    required this.showFallbackIndicator,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final t = selectionProgress;
    final textColor = Color.lerp(p.fg3, p.fg, t)!;
    final badgeBg = Color.lerp(p.bg3, p.accent, t)!;
    final badgeFg = Color.lerp(p.fg2, Colors.white, t)!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      splashFactory: NoSplash.splashFactory,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: t > 0.5 ? FontWeight.w600 : FontWeight.w500,
                      color: textColor,
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
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: TalerTheme.tabularStyle(
                          size: 11,
                          weight: FontWeight.w600,
                          color: badgeFg,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (showFallbackIndicator)
            Positioned(
              left: 8,
              right: 8,
              bottom: 0,
              child: Container(
                height: 2.5,
                decoration: BoxDecoration(
                  color: p.accent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2.5),
                  ),
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
  final bool compactDensity;
  final bool selected;
  final VoidCallback onTap;

  const ChatRow({
    super.key,
    required this.client,
    required this.chat,
    required this.compact,
    required this.selected,
    required this.onTap,
    this.compactDensity = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final peer = chat.peerId != null ? client.contactById(chat.peerId!) : null;
    final avatarUrl = chat.avatarUrl ?? peer?.avatarUrl;
    final hasUnread = chat.unreadCount > 0;
    final timeColor = hasUnread && !chat.isMuted ? p.accent : p.fg3;
    final avatarSize = compact ? (compactDensity ? 44.0 : 52.0) : (compactDensity ? 42.0 : 48.0);
    final vPad = compact ? (compactDensity ? 7.0 : 10.0) : (compactDensity ? 6.0 : 8.0);
    final dividerIndent = 16.0 + avatarSize + 12.0;

    final content = Row(
      children: [
        TalerAvatar(
          seedId: chat.peerId ?? chat.id,
          initials: chat.initials,
          imageUrl: avatarUrl,
          size: avatarSize,
          isOnline: chat.isDialog && chat.isOnline,
          onlineBorderColor: selected ? p.bg3 : p.bg2,
        ),
        const SizedBox(width: 12),
        Expanded(
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
      ],
    );

    final row = Material(
      color: selected ? ChatTokens.active(p) : Colors.transparent,
      borderRadius: BorderRadius.circular(compact ? 0 : 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: ChatTokens.hover(p),
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: compact
              ? EdgeInsets.fromLTRB(16, vPad, 16, vPad)
              : EdgeInsets.fromLTRB(10, vPad, 10, vPad),
          child: content,
        ),
      ),
    );

    if (!compact) {
      return Padding(padding: const EdgeInsets.only(bottom: 2), child: row);
    }

    return Stack(
      children: [
        row,
        Positioned(
          left: dividerIndent,
          right: 16,
          bottom: 0,
          child: Divider(height: 1, thickness: 1, color: p.line),
        ),
      ],
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
    final draft = client.draftForChat(chat.id);
    if (draft != null && !draft.isEmpty) {
      return Row(
        children: [
          Text(
            'Черновик: ',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: p.danger,
            ),
          ),
          Expanded(
            child: Text(
              draft.text.replaceAll('\n', ' ').trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: p.fg2),
            ),
          ),
        ],
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

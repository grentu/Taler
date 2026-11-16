import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/storage/taler_models.dart';
import '../icons/taler_icon.dart';
import '../theme/chat_tokens.dart';
import '../theme/taler_theme.dart';

enum _Tab { members, media, files }

/// Профиль собеседника или информация о группе / канале.
/// Во вкладках личной переписки нет «Участников».
class ChatInfoPanel extends StatefulWidget {
  final TalerClient client;
  final TalerChat chat;
  final List<TalerMessage> messages;
  final VoidCallback? onClose;
  final VoidCallback? onSearch;

  /// Телефон: панель занимает весь экран, без собственной шапки.
  final bool fullScreen;

  const ChatInfoPanel({
    super.key,
    required this.client,
    required this.chat,
    required this.messages,
    this.onClose,
    this.onSearch,
    this.fullScreen = false,
  });

  @override
  State<ChatInfoPanel> createState() => _ChatInfoPanelState();
}

class _ChatInfoPanelState extends State<ChatInfoPanel> {
  _Tab? _tab;

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final client = widget.client;
    final chat = widget.chat;
    final peer = chat.peerId != null ? client.contactById(chat.peerId!) : null;
    final tabs = <_Tab>[if (chat.isGroup) _Tab.members, _Tab.media, _Tab.files];
    final tab = (_tab != null && tabs.contains(_tab)) ? _tab! : tabs.first;
    final photos = <TalerAttachment>[
      for (final m in widget.messages.reversed)
        for (final a in m.attachments)
          if (a.type == 'PHOTO' && a.url != null) a,
    ];
    final files = <TalerAttachment>[
      for (final m in widget.messages.reversed)
        for (final a in m.attachments)
          if (a.type != 'PHOTO' && a.type != 'CONTROL') a,
    ];
    final title = chat.isDialog ? 'Профиль' : chat.isChannel ? 'Канал' : 'Группа';
    final status = ChatTokens.chatStatus(chat);
    final statusLive = chat.isOnline || (chat.typingLabel?.isNotEmpty ?? false);
    final anti = client.privacySettings.antiDelete;

    final body = ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        const SizedBox(height: 24),
        Center(
          child: TalerAvatar(
            seedId: chat.peerId ?? chat.id,
            initials: chat.initials,
            imageUrl: chat.avatarUrl ?? peer?.avatarUrl,
            size: widget.fullScreen ? 104 : 88,
            isOnline: chat.isDialog && chat.isOnline,
            onlineBorderColor: p.bg2,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            chat.title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: p.fg),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          status,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: statusLive ? p.accent : p.fg3),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _ActionTile(
                  icon: chat.isMuted ? TalerIcons.bellOff : TalerIcons.bell,
                  label: chat.isMuted ? 'Без звука' : 'Звук',
                  onTap: () => client.toggleChatMute(chat.id),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionTile(
                  icon: TalerIcons.search,
                  label: 'Поиск',
                  onTap: widget.onSearch,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.line),
          ),
          child: Column(
            children: [
              if (chat.isDialog && peer?.phone != null)
                _InfoRow(icon: TalerIcons.phone, value: ChatTokens.phone(peer!.phone), label: 'Телефон', mono: true),
              if (!chat.isDialog)
                _InfoRow(
                  icon: TalerIcons.users,
                  value: '${chat.participantsCount}',
                  label: chat.isChannel ? 'Подписчики' : 'Участники',
                  mono: true,
                ),
              _ToggleRow(
                title: 'Сохранять удалённые',
                subtitle: 'Сообщения, удалённые собеседником, останутся у вас',
                value: anti,
                onChanged: (v) => client.privacySettings.setAntiDelete(v),
                showTopBorder: (chat.isDialog && peer?.phone != null) || !chat.isDialog,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Flexible(
                  child: _TabButton(
                    label: switch (tabs[i]) {
                      _Tab.members => 'Участники',
                      _Tab.media => 'Медиа',
                      _Tab.files => 'Файлы',
                    },
                    selected: tabs[i] == tab,
                    isLast: i == tabs.length - 1,
                    onTap: () => setState(() => _tab = tabs[i]),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (tab == _Tab.members) ..._members(p),
        if (tab == _Tab.media)
          photos.isEmpty
              ? const _Empty(text: 'Фото пока нет')
              : Padding(
                  padding: const EdgeInsets.all(4),
                  child: GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                    children: [
                      for (final a in photos.take(60))
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: _thumb(a.url!, p),
                        ),
                    ],
                  ),
                ),
        if (tab == _Tab.files)
          files.isEmpty
              ? const _Empty(text: 'Файлов пока нет')
              : Column(
                  children: [
                    for (final f in files.take(60))
                      ListTile(
                        dense: true,
                        leading: TalerIcon(TalerIcons.file, size: 20, color: p.fg3),
                        title: Text(
                          f.fileName ?? f.previewText ?? 'Файл',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: p.fg),
                        ),
                        subtitle: Text(
                          ChatTokens.fileSize(f.fileSize),
                          style: TalerTheme.tabularStyle(size: 12, color: p.fg3),
                        ),
                      ),
                  ],
                ),
      ],
    );

    if (widget.fullScreen) {
      return ColoredBox(color: p.bg2, child: body);
    }
    return Container(
      decoration: BoxDecoration(color: p.bg2, border: Border(left: BorderSide(color: p.line))),
      child: Column(
        children: [
          Container(
            height: 60,
            padding: const EdgeInsets.only(left: 20, right: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.fg)),
                ),
                TalerIconButton(icon: TalerIcons.close, tooltip: 'Закрыть', iconSize: 18, onPressed: widget.onClose),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _thumb(String url, TalerPalette p) {
    final placeholder = Container(color: p.bg3);
    if (url.startsWith('http')) {
      return Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder);
    }
    return Image.file(File(url), fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder);
  }

  /// Участники: известные по переписке отправители и вы.
  List<Widget> _members(TalerPalette p) {
    final client = widget.client;
    final me = client.currentUser;
    final myId = me?.id;
    final myName = me == null || me.fullName.isEmpty ? 'Вы' : me.fullName;
    final ids = <int>[];
    if (myId != null) ids.add(myId);
    for (final m in widget.messages.reversed) {
      if (!ids.contains(m.senderId) && m.senderId != 0) ids.add(m.senderId);
      if (ids.length >= 50) break;
    }
    if (ids.isEmpty) return const [_Empty(text: 'Список участников появится после загрузки сообщений')];
    return [
      for (final id in ids)
        Builder(builder: (context) {
          final contact = client.contactById(id);
          final isMe = id == myId;
          final name = isMe ? myName : client.senderDisplayName(id, chatId: widget.chat.id);
          final online = contact?.isOnline ?? false;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                TalerAvatar(
                  seedId: id,
                  initials: isMe ? (me?.initials ?? '?') : (contact?.initials ?? '?'),
                  imageUrl: isMe ? me?.avatarUrl : contact?.avatarUrl,
                  size: 40,
                  isOnline: online,
                  onlineBorderColor: p.bg2,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMe ? '$name · вы' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.fg),
                      ),
                      Text(
                        online ? 'в сети' : 'был(а) недавно',
                        style: TextStyle(fontSize: 12, color: online ? p.accent : p.fg3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
    ];
  }
}

class _ActionTile extends StatelessWidget {
  final TalerIconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionTile({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.line)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: ChatTokens.hover(p),
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              TalerIcon(icon, size: 20, color: p.accent),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: p.accent)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final TalerIconData icon;
  final String value;
  final String label;
  final bool mono;

  const _InfoRow({required this.icon, required this.value, required this.label, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TalerIcon(icon, size: 18, color: p.fg3),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  value,
                  style: mono
                      ? TalerTheme.tabularStyle(size: 14, color: p.fg)
                      : TextStyle(fontSize: 14, color: p.fg),
                ),
                Text(label, style: TextStyle(fontSize: 12, color: p.fg3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showTopBorder;

  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.showTopBorder,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: showTopBorder ? BoxDecoration(border: Border(top: BorderSide(color: p.line))) : null,
      child: Row(
        children: [
          TalerIcon(TalerIcons.shieldCheck, size: 18, color: p.statusLive),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14, color: p.fg)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: p.fg3)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isLast;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
        margin: EdgeInsets.only(right: isLast ? 0 : 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: selected ? p.accent : Colors.transparent, width: 2)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: selected ? p.fg : p.fg3),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;

  const _Empty({required this.text});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.fg3)),
    );
  }
}

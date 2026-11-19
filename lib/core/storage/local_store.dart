import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'taler_models.dart';

/// Снимок объёма локального кэша.
class CacheStats {
  final int chatsCount;
  final int contactsCount;
  final int messagesCount;
  final int approxBytes;

  const CacheStats({
    required this.chatsCount,
    required this.contactsCount,
    required this.messagesCount,
    required this.approxBytes,
  });
}

/// Локальное хранилище аккаунта, кэша чатов/сообщений, Anti-Delete и истории правок.
class LocalStore {
  static const _kAuthToken = 'taler_auth_token';
  static const _kAccountId = 'taler_account_id';
  static const _kProfile = 'taler_profile_v1';
  static const _kChats = 'taler_chats_v1';
  static const _kContacts = 'taler_contacts_v1';
  static const _kFolders = 'taler_folders_v1';
  static const _kDrafts = 'taler_drafts_v1';
  static String _msgKey(int chatId) => 'taler_messages_${chatId}_v1';

  SharedPreferences? _prefs;

  String? _authToken;
  int? _accountId;
  TalerUserProfile? _profile;
  final Map<int, TalerChat> _chats = {};
  final Map<int, TalerContact> _contacts = {};
  final List<TalerFolder> _folders = [];
  final Map<int, List<TalerMessage>> _messages = {};
  final Map<int, TalerDraft> _drafts = {};

  Timer? _chatsSaveTimer;
  Timer? _contactsSaveTimer;
  final Map<int, Timer> _msgSaveTimers = {};

  String? get authToken => _authToken;
  int? get accountId => _accountId;
  TalerUserProfile? get profile => _profile;
  Map<int, TalerChat> get chats => Map.unmodifiable(_chats);
  Map<int, TalerContact> get contacts => Map.unmodifiable(_contacts);
  List<TalerFolder> get folders => List.unmodifiable(_folders);
  Map<int, TalerDraft> get drafts => Map.unmodifiable(_drafts);

  TalerDraft? draftFor(int chatId) => _drafts[chatId];

  Future<void> saveDraft(int chatId, TalerDraft? draft) async {
    if (draft == null || draft.isEmpty) {
      if (_drafts.remove(chatId) == null) return;
    } else {
      _drafts[chatId] = draft;
    }
    await _persistDraftsNow();
  }

  Future<void> _persistDraftsNow() async {
    final encoded = <String, dynamic>{
      for (final entry in _drafts.entries) '${entry.key}': entry.value.toJson(),
    };
    await _prefs?.setString(_kDrafts, jsonEncode(encoded));
  }

  Future<void> init([SharedPreferences? prefs]) async {
    _prefs = prefs ?? await SharedPreferences.getInstance();
    _authToken = _prefs?.getString(_kAuthToken);
    _accountId = _prefs?.getInt(_kAccountId);

    final rawProfile = _prefs?.getString(_kProfile);
    if (rawProfile != null && rawProfile.isNotEmpty) {
      try {
        _profile = TalerUserProfile.fromJson(
          jsonDecode(rawProfile) as Map<String, dynamic>,
        );
      } catch (_) {}
    }

    final rawChats = _prefs?.getString(_kChats);
    if (rawChats != null && rawChats.isNotEmpty) {
      try {
        final list = jsonDecode(rawChats) as List;
        for (final item in list.whereType<Map>()) {
          final chat = TalerChat.fromJson(Map<String, dynamic>.from(item));
          _chats[chat.id] = chat;
        }
      } catch (_) {}
    }

    final rawContacts = _prefs?.getString(_kContacts);
    if (rawContacts != null && rawContacts.isNotEmpty) {
      try {
        final list = jsonDecode(rawContacts) as List;
        for (final item in list.whereType<Map>()) {
          final contact =
              TalerContact.fromJson(Map<String, dynamic>.from(item));
          _contacts[contact.id] = contact;
        }
      } catch (_) {}
    }

    final rawFolders = _prefs?.getString(_kFolders);
    if (rawFolders != null && rawFolders.isNotEmpty) {
      try {
        final list = jsonDecode(rawFolders) as List;
        for (final item in list.whereType<Map>()) {
          _folders.add(TalerFolder.fromJson(Map<String, dynamic>.from(item)));
        }
      } catch (_) {}
    }

    final rawDrafts = _prefs?.getString(_kDrafts);
    if (rawDrafts != null && rawDrafts.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawDrafts);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final cid = int.tryParse(entry.key.toString());
            if (cid != null && entry.value is Map) {
              final d = TalerDraft.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              );
              if (!d.isEmpty) _drafts[cid] = d;
            }
          }
        }
      } catch (_) {}
    }
  }

  Future<void> saveCredentials(String token, int accountId) async {
    _authToken = token;
    _accountId = accountId;
    await _prefs?.setString(_kAuthToken, token);
    await _prefs?.setInt(_kAccountId, accountId);
  }

  Future<void> saveProfile(TalerUserProfile profile) async {
    _profile = profile;
    _accountId = profile.id;
    await _prefs?.setInt(_kAccountId, profile.id);
    await _prefs?.setString(_kProfile, jsonEncode(profile.toJson()));
  }

  Future<void> saveChats(Iterable<TalerChat> items) async {
    for (final c in items) {
      _chats[c.id] = c;
    }
    await _persistChats();
  }

  Future<void> removeChat(int chatId) async {
    _chats.remove(chatId);
    _messages.remove(chatId);
    await _persistChats();
    await _prefs?.remove(_msgKey(chatId));
  }

  Future<void> saveContacts(Iterable<TalerContact> items) async {
    for (final c in items) {
      _contacts[c.id] = c;
    }
    _scheduleContactsPersist();
  }

  Future<void> saveFolders(List<TalerFolder> folders) async {
    _folders
      ..clear()
      ..addAll(folders);
    await _prefs?.setString(
      _kFolders,
      jsonEncode(_folders.map((f) => f.toJson()).toList()),
    );
  }

  static void _sortMessages(List<TalerMessage> list) {
    list.sort((a, b) {
      final byTime = a.time.compareTo(b.time);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  }

  List<TalerMessage> getMessages(int chatId) {
    final cached = _messages[chatId];
    if (cached != null) return List.unmodifiable(cached);

    final raw = _prefs?.getString(_msgKey(chatId));
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        final parsed = list
            .whereType<Map>()
            .map((e) => TalerMessage.fromJson(Map<String, dynamic>.from(e)))
            .map(
              (m) => (m.status == 'sending' || m.status == 'pending')
                  ? m.copyWith(status: 'error')
                  : m,
            )
            .toList();
        _sortMessages(parsed);
        _messages[chatId] = parsed;
        return List.unmodifiable(parsed);
      } catch (_) {}
    }
    return const [];
  }

  Future<void> saveMessagesBatch(
    int chatId,
    List<TalerMessage> incoming, {
    bool trackEditHistory = true,
  }) async {
    if (incoming.isEmpty) return;
    getMessages(chatId); // подгрузить с диска если ещё не в памяти
    final list = _messages.putIfAbsent(chatId, () => <TalerMessage>[]);
    for (final msg in incoming) {
      _upsertIntoList(list, msg, trackEditHistory: trackEditHistory);
    }
    _sortMessages(list);
    await _persistMessages(chatId);
  }

  /// Добавляет или обновляет сообщение. Если текст изменился — сохраняет старую
  /// версию в `editHistory`.
  Future<TalerMessage> upsertMessage(
    TalerMessage incoming, {
    bool trackEditHistory = true,
  }) async {
    getMessages(incoming.chatId);
    final list = _messages.putIfAbsent(incoming.chatId, () => <TalerMessage>[]);
    final result = _upsertIntoList(
      list,
      incoming,
      trackEditHistory: trackEditHistory,
    );
    _sortMessages(list);
    await _persistMessages(incoming.chatId);
    return result;
  }

  TalerMessage _upsertIntoList(
    List<TalerMessage> list,
    TalerMessage incoming, {
    required bool trackEditHistory,
  }) {
    var idx = list.indexWhere((m) => m.id == incoming.id);
    if (idx < 0 && incoming.cid != null) {
      idx = list.indexWhere((m) => m.cid != null && m.cid == incoming.cid);
    }
    if (idx < 0) {
      list.add(incoming);
      return incoming;
    }

    final existing = list[idx];
    var nextHistory = List<TalerEditRevision>.from(existing.editHistory);
    var nextStatus = incoming.status;
    if (existing.status == 'read' && nextStatus == 'sent') {
      nextStatus = 'read';
    }

    if (trackEditHistory &&
        existing.text != incoming.text &&
        existing.text.isNotEmpty) {
      final lastSaved = nextHistory.isNotEmpty ? nextHistory.last.text : null;
      if (lastSaved != existing.text) {
        nextHistory.add(
          TalerEditRevision(
            text: existing.text,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
      if (nextStatus != 'read') {
        nextStatus = 'edited';
      }
    }

    final merged = incoming.copyWith(
      editHistory: nextHistory.isNotEmpty ? nextHistory : incoming.editHistory,
      status: nextStatus,
      deletedByPeer: existing.deletedByPeer || incoming.deletedByPeer,
      deletedAt: existing.deletedAt ?? incoming.deletedAt,
      reactions: (incoming.reactions.isEmpty &&
              existing.reactions.isNotEmpty &&
              incoming.status == 'edited')
          ? existing.reactions
          : incoming.reactions,
      replyTo: incoming.replyTo ?? existing.replyTo,
      cid: incoming.cid ?? existing.cid,
    );
    list[idx] = merged;
    return merged;
  }

  /// Заменяет временное сообщение ([tempId]) подтверждённым серверным сообщением.
  Future<void> replaceTempMessage(
    int chatId,
    String tempId,
    TalerMessage confirmed,
  ) async {
    getMessages(chatId);
    final list = _messages.putIfAbsent(chatId, () => <TalerMessage>[]);
    list.removeWhere(
      (m) =>
          m.id == tempId ||
          m.id == confirmed.id ||
          (confirmed.cid != null && m.cid == confirmed.cid),
    );
    list.add(confirmed);
    _sortMessages(list);
    await _persistMessages(chatId);
  }

  /// Удаляет конкретное локальное сообщение (например, неудачную отправку).
  Future<bool> removeMessage(int chatId, String messageId) async {
    getMessages(chatId);
    final list = _messages[chatId];
    if (list == null || list.isEmpty) return false;
    final before = list.length;
    list.removeWhere((m) => m.id == messageId);
    if (list.length == before) return false;
    await _persistMessages(chatId);
    _refreshChatPreviewAfterRemove(chatId, list);
    return true;
  }

  /// Anti-Delete: вместо удаления сообщений собеседника помечает их
  /// флагом `deletedByPeer = true`, сохраняя весь текст и вложения локально.
  Future<int> markMessagesDeletedByPeer(
    int chatId,
    List<String> messageIds, {
    bool antiDeleteEnabled = true,
  }) async {
    if (messageIds.isEmpty) return 0;
    getMessages(chatId);
    final list = _messages[chatId];
    if (list == null || list.isEmpty) return 0;

    final idSet = messageIds.toSet();
    final now = DateTime.now().millisecondsSinceEpoch;
    var affected = 0;
    final wasLastAffected = list.isNotEmpty && idSet.contains(list.last.id);

    if (!antiDeleteEnabled) {
      final before = list.length;
      list.removeWhere((m) => idSet.contains(m.id));
      affected = before - list.length;
    } else {
      for (var i = 0; i < list.length; i++) {
        final msg = list[i];
        if (idSet.contains(msg.id)) {
          if (!msg.deletedByPeer) {
            list[i] = msg.copyWith(
              deletedByPeer: true,
              deletedAt: msg.deletedAt ?? now,
            );
            affected++;
          }
        }
      }
    }

    if (affected > 0) {
      await _persistMessages(chatId);
      final chat = _chats[chatId];
      if (chat != null) {
        if (antiDeleteEnabled) {
          if (wasLastAffected) {
            _chats[chatId] = chat.copyWith(lastMessageDeletedByPeer: true);
            await _persistChats();
          }
        } else if (wasLastAffected) {
          _refreshChatPreviewAfterRemove(chatId, list);
          await _persistChats();
        }
      }
    }
    return affected;
  }

  /// Помечает/удаляет сообщения в диапазоне времени (`Opcode.notifMsgDeleteRange`).
  Future<int> markMessagesDeletedByTimeRange(
    int chatId, {
    required int startTime,
    required int endTime,
    bool antiDeleteEnabled = true,
  }) async {
    getMessages(chatId);
    final list = _messages[chatId];
    if (list == null || list.isEmpty) return 0;
    final ids = <String>[
      for (final m in list)
        if (!m.id.startsWith('temp_') &&
            m.status != 'sending' &&
            m.status != 'error' &&
            m.time >= startTime &&
            m.time <= endTime)
          m.id,
    ];
    return markMessagesDeletedByPeer(
      chatId,
      ids,
      antiDeleteEnabled: antiDeleteEnabled,
    );
  }

  void _refreshChatPreviewAfterRemove(int chatId, List<TalerMessage> list) {
    final chat = _chats[chatId];
    if (chat == null) return;
    if (list.isEmpty) {
      _chats[chatId] = TalerChat(
        id: chat.id,
        type: chat.type,
        title: chat.title,
        avatarUrl: chat.avatarUrl,
        peerId: chat.peerId,
        unreadCount: chat.unreadCount,
        isOnline: chat.isOnline,
        lastSeen: chat.lastSeen,
        favIndex: chat.favIndex,
        isMuted: chat.isMuted,
        participantsCount: chat.participantsCount,
        isOfficial: chat.isOfficial,
        typingLabel: chat.typingLabel,
        peerReadMark: chat.peerReadMark,
      );
    } else {
      final last = list.last;
      final preview = last.text.isNotEmpty
          ? last.text
          : (last.attachments.isNotEmpty ? '[Вложение]' : '');
      _chats[chatId] = chat.copyWith(
        lastMessageText: preview,
        lastMessageTime: last.time,
        lastMessageSenderId: last.senderId,
        lastMessageDeletedByPeer: last.deletedByPeer,
      );
    }
  }

  Future<void> clearAccountData() async {
    _chatsSaveTimer?.cancel();
    _chatsSaveTimer = null;
    _contactsSaveTimer?.cancel();
    _contactsSaveTimer = null;
    for (final t in _msgSaveTimers.values) {
      t.cancel();
    }
    _msgSaveTimers.clear();

    final chatIds = _chats.keys.toList();
    _authToken = null;
    _accountId = null;
    _profile = null;
    _chats.clear();
    _contacts.clear();
    _folders.clear();
    _messages.clear();
    _drafts.clear();

    await _prefs?.remove(_kAuthToken);
    await _prefs?.remove(_kAccountId);
    await _prefs?.remove(_kProfile);
    await _prefs?.remove(_kChats);
    await _prefs?.remove(_kContacts);
    await _prefs?.remove(_kFolders);
    await _prefs?.remove(_kDrafts);
    for (final id in chatIds) {
      await _prefs?.remove(_msgKey(id));
    }
  }

  /// Оценивает размер локально сохранённого кэша чатов, контактов и сообщений.
  CacheStats estimateCacheStats() {
    var msgCount = 0;
    var bytes = 0;

    final chatsJson = _prefs?.getString(_kChats);
    if (chatsJson != null) {
      bytes += chatsJson.length * 2;
    } else if (_chats.isNotEmpty) {
      bytes += _chats.length * 320;
    }

    final contactsJson = _prefs?.getString(_kContacts);
    if (contactsJson != null) {
      bytes += contactsJson.length * 2;
    } else if (_contacts.isNotEmpty) {
      bytes += _contacts.length * 240;
    }

    final seenChatIds = <int>{};
    if (_prefs != null) {
      for (final key in _prefs!.getKeys()) {
        if (key.startsWith('taler_messages_') && key.endsWith('_v1')) {
          final raw = _prefs!.getString(key);
          if (raw != null) {
            bytes += raw.length * 2;
          }
          final idStr = key.substring(
            'taler_messages_'.length,
            key.length - '_v1'.length,
          );
          final chatId = int.tryParse(idStr);
          if (chatId != null) {
            seenChatIds.add(chatId);
            msgCount += _messages[chatId]?.length ??
                getMessages(chatId).length;
          }
        }
      }
    }
    for (final entry in _messages.entries) {
      if (!seenChatIds.contains(entry.key)) {
        msgCount += entry.value.length;
        bytes += entry.value.length * 280;
      }
    }

    return CacheStats(
      chatsCount: _chats.length,
      contactsCount: _contacts.length,
      messagesCount: msgCount,
      approxBytes: bytes,
    );
  }

  /// Очищает кэш сообщений с диска и из памяти, сохраняя токен входа, профиль и список чатов.
  Future<int> clearMessageCache() async {
    for (final t in _msgSaveTimers.values) {
      t.cancel();
    }
    _msgSaveTimers.clear();

    var removedMessages = 0;
    for (final list in _messages.values) {
      removedMessages += list.length;
    }
    _messages.clear();

    if (_prefs != null) {
      final msgKeys = _prefs!
          .getKeys()
          .where((k) => k.startsWith('taler_messages_') && k.endsWith('_v1'))
          .toList();
      for (final key in msgKeys) {
        if (removedMessages == 0) {
          final raw = _prefs!.getString(key);
          if (raw != null && raw.isNotEmpty) {
            try {
              removedMessages += (jsonDecode(raw) as List).length;
            } catch (_) {}
          }
        }
        await _prefs!.remove(key);
      }
    }
    return removedMessages;
  }

  /// Немедленно сбрасывает отложенные буферы чатов, контактов и сообщений на диск.
  Future<void> flush() async {
    _chatsSaveTimer?.cancel();
    _chatsSaveTimer = null;
    _contactsSaveTimer?.cancel();
    _contactsSaveTimer = null;
    final pendingChatIds = _msgSaveTimers.keys.toList();
    for (final t in _msgSaveTimers.values) {
      t.cancel();
    }
    _msgSaveTimers.clear();

    await _writeChatsNow();
    await _writeContactsNow();
    for (final id in pendingChatIds) {
      await _writeMessagesNow(id);
    }
  }

  Future<void> _persistChats() async {
    if (_prefs == null) return;
    _chatsSaveTimer?.cancel();
    _chatsSaveTimer = Timer(const Duration(milliseconds: 350), () {
      _chatsSaveTimer = null;
      _writeChatsNow();
    });
  }

  void _scheduleContactsPersist() {
    if (_prefs == null) return;
    _contactsSaveTimer?.cancel();
    _contactsSaveTimer = Timer(const Duration(milliseconds: 350), () {
      _contactsSaveTimer = null;
      _writeContactsNow();
    });
  }

  Future<void> _persistMessages(int chatId) async {
    if (_prefs == null) return;
    _msgSaveTimers[chatId]?.cancel();
    _msgSaveTimers[chatId] = Timer(const Duration(milliseconds: 350), () {
      _msgSaveTimers.remove(chatId);
      _writeMessagesNow(chatId);
    });
  }

  Future<void> _writeChatsNow() async {
    await _prefs?.setString(
      _kChats,
      jsonEncode(_chats.values.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> _writeContactsNow() async {
    await _prefs?.setString(
      _kContacts,
      jsonEncode(_contacts.values.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> _writeMessagesNow(int chatId) async {
    final list = _messages[chatId];
    if (list == null) return;
    final trimmed =
        list.length > 500 ? list.sublist(list.length - 500) : list;
    await _prefs?.setString(
      _msgKey(chatId),
      jsonEncode(trimmed.map((m) => m.toJson()).toList()),
    );
  }
}

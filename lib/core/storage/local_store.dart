import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'taler_models.dart';

/// Локальное хранилище аккаунта, кэша чатов/сообщений, Anti-Delete и истории правок.
class LocalStore {
  static const _kAuthToken = 'taler_auth_token';
  static const _kAccountId = 'taler_account_id';
  static const _kProfile = 'taler_profile_v1';
  static const _kChats = 'taler_chats_v1';
  static const _kContacts = 'taler_contacts_v1';
  static const _kFolders = 'taler_folders_v1';
  static String _msgKey(int chatId) => 'taler_messages_${chatId}_v1';

  SharedPreferences? _prefs;

  String? _authToken;
  int? _accountId;
  TalerUserProfile? _profile;
  final Map<int, TalerChat> _chats = {};
  final Map<int, TalerContact> _contacts = {};
  final List<TalerFolder> _folders = [];
  final Map<int, List<TalerMessage>> _messages = {};

  String? get authToken => _authToken;
  int? get accountId => _accountId;
  TalerUserProfile? get profile => _profile;
  Map<int, TalerChat> get chats => Map.unmodifiable(_chats);
  Map<int, TalerContact> get contacts => Map.unmodifiable(_contacts);
  List<TalerFolder> get folders => List.unmodifiable(_folders);

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
    await _prefs?.setString(
      _kContacts,
      jsonEncode(_contacts.values.map((c) => c.toJson()).toList()),
    );
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
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time));
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
    list.sort((a, b) => a.time.compareTo(b.time));
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
    list.sort((a, b) => a.time.compareTo(b.time));
    await _persistMessages(incoming.chatId);
    return result;
  }

  TalerMessage _upsertIntoList(
    List<TalerMessage> list,
    TalerMessage incoming, {
    required bool trackEditHistory,
  }) {
    final idx = list.indexWhere((m) => m.id == incoming.id);
    if (idx < 0) {
      list.add(incoming);
      return incoming;
    }

    final existing = list[idx];
    var nextHistory = List<TalerEditRevision>.from(existing.editHistory);
    var nextStatus = incoming.status;

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
      nextStatus = 'edited';
    }

    final merged = incoming.copyWith(
      editHistory: nextHistory.isNotEmpty ? nextHistory : incoming.editHistory,
      status: nextStatus,
      deletedByPeer: existing.deletedByPeer || incoming.deletedByPeer,
      deletedAt: existing.deletedAt ?? incoming.deletedAt,
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
    list.removeWhere((m) => m.id == tempId || m.id == confirmed.id);
    list.add(confirmed);
    list.sort((a, b) => a.time.compareTo(b.time));
    await _persistMessages(chatId);
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

    if (!antiDeleteEnabled) {
      final before = list.length;
      list.removeWhere((m) => idSet.contains(m.id));
      affected = before - list.length;
    } else {
      for (var i = 0; i < list.length; i++) {
        final msg = list[i];
        if (idSet.contains(msg.id)) {
          list[i] = msg.copyWith(
            deletedByPeer: true,
            deletedAt: msg.deletedAt ?? now,
          );
          affected++;
        }
      }
    }

    if (affected > 0) {
      await _persistMessages(chatId);
      final chat = _chats[chatId];
      if (chat != null && list.isNotEmpty) {
        final last = list.last;
        if (idSet.contains(last.id) && antiDeleteEnabled) {
          _chats[chatId] = chat.copyWith(lastMessageDeletedByPeer: true);
          await _persistChats();
        }
      }
    }
    return affected;
  }

  Future<void> clearAccountData() async {
    final chatIds = _chats.keys.toList();
    _authToken = null;
    _accountId = null;
    _profile = null;
    _chats.clear();
    _contacts.clear();
    _folders.clear();
    _messages.clear();

    await _prefs?.remove(_kAuthToken);
    await _prefs?.remove(_kAccountId);
    await _prefs?.remove(_kProfile);
    await _prefs?.remove(_kChats);
    await _prefs?.remove(_kContacts);
    await _prefs?.remove(_kFolders);
    for (final id in chatIds) {
      await _prefs?.remove(_msgKey(id));
    }
  }

  Future<void> _persistChats() async {
    await _prefs?.setString(
      _kChats,
      jsonEncode(_chats.values.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> _persistMessages(int chatId) async {
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

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/privacy/privacy_firewall.dart';
import '../core/privacy/privacy_settings.dart';
import '../core/privacy/spoofing_service.dart';
import '../core/protocol/fingerprint.dart';
import '../core/protocol/opcode.dart';
import '../core/protocol/packet.dart';
import '../core/storage/local_store.dart';
import '../core/storage/taler_models.dart';
import '../core/transport/taler_session.dart';

enum OtpVerifyStatus { authenticated, needs2fa, needsRegistration }

class OtpVerifyOutcome {
  final OtpVerifyStatus status;
  final String? trackId;
  final String? hint;
  final String? registerToken;

  const OtpVerifyOutcome._({
    required this.status,
    this.trackId,
    this.hint,
    this.registerToken,
  });

  factory OtpVerifyOutcome.authenticated() =>
      const OtpVerifyOutcome._(status: OtpVerifyStatus.authenticated);

  factory OtpVerifyOutcome.needs2fa({
    required String trackId,
    String? hint,
  }) =>
      OtpVerifyOutcome._(
        status: OtpVerifyStatus.needs2fa,
        trackId: trackId,
        hint: hint,
      );

  factory OtpVerifyOutcome.needsRegistration(String registerToken) =>
      OtpVerifyOutcome._(
        status: OtpVerifyStatus.needsRegistration,
        registerToken: registerToken,
      );
}

/// Главный контроллер доменной логики и состояния мессенджера Taler.
class TalerClient extends ChangeNotifier {
  final PrivacySettings privacySettings;
  final SpoofingService spoofingService;
  final WireAuditLog auditLog;
  final LocalStore store;

  late final PrivacyFirewall firewall;
  late final TalerSession session;

  StreamSubscription<TalerConnectionState>? _connSub;
  StreamSubscription<TalerPacket>? _pushSub;

  bool _isAuthenticated = false;
  bool _isDemoMode = false;
  bool _isLoading = false;
  String? _errorMessage;
  TalerConnectionState _connectionState = TalerConnectionState.disconnected;
  List<TalerActiveSession> _activeSessions = const [];
  final Map<int, Timer> _typingClearTimers = {};
  List<TalerChat>? _cachedSortedChats;
  int _otpSessionEpoch = -1;
  String? _lastOtpPhone;
  String? _lastTempToken;

  TalerClient({
    required this.privacySettings,
    required this.spoofingService,
    required this.auditLog,
    required this.store,
  }) {
    firewall = PrivacyFirewall(
      settings: privacySettings,
      auditLog: auditLog,
    );
    session = TalerSession(
      firewall: firewall,
      privacySettings: privacySettings,
      spoofingService: spoofingService,
    );
    session.onReconnected = () async {
      final token = store.authToken;
      if (token != null && token.isNotEmpty && !_isDemoMode) {
        await _sendLogin(token);
      }
    };
    _connSub = session.stateStream.listen((s) {
      _connectionState = s;
      notifyListeners();
    });
    _pushSub = session.pushStream.listen(_handleServerPush);
  }

  bool get isAuthenticated => _isAuthenticated;
  bool get isDemoMode => _isDemoMode;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  TalerConnectionState get connectionState => _connectionState;
  TalerUserProfile? get currentUser => store.profile;
  List<TalerFolder> get folders => store.folders;
  List<TalerActiveSession> get activeSessions => _activeSessions;
  String? get lastTempToken => _lastTempToken;

  @override
  void notifyListeners() {
    _cachedSortedChats = null;
    super.notifyListeners();
  }

  List<TalerChat> get chats {
    final cached = _cachedSortedChats;
    if (cached != null) return cached;
    final list = store.chats.values.toList()
      ..sort((a, b) {
        final ap = a.favIndex > 0 ? 0 : 1;
        final bp = b.favIndex > 0 ? 0 : 1;
        if (ap != bp) return ap.compareTo(bp);
        if (ap == 0 && a.favIndex != b.favIndex) {
          return a.favIndex.compareTo(b.favIndex);
        }
        return (b.lastMessageTime ?? 0).compareTo(a.lastMessageTime ?? 0);
      });
    final frozen = List<TalerChat>.unmodifiable(list);
    _cachedSortedChats = frozen;
    return frozen;
  }

  List<TalerMessage> messagesForChat(int chatId) => store.getMessages(chatId);

  TalerContact? contactById(int id) => store.contacts[id];

  String senderDisplayName(int senderId, {int? chatId}) {
    if (senderId == currentUser?.id) {
      return currentUser?.fullName ?? 'Вы';
    }
    final contact = store.contacts[senderId];
    if (contact != null) return contact.displayName;
    if (chatId != null) {
      final chat = store.chats[chatId];
      if (chat != null && chat.isDialog) return chat.title;
    }
    return 'Пользователь #$senderId';
  }

  /// Инициализирует хранилища и восстанавливает сохранённую сессию.
  Future<void> initialize() async {
    await privacySettings.load();
    await spoofingService.load();
    await store.init();

    final savedToken = store.authToken;
    if (savedToken != null && savedToken.isNotEmpty) {
      _isAuthenticated = true;
      notifyListeners();
      unawaited(_reconnectSavedSession(savedToken));
    }
  }

  Future<void> _reconnectSavedSession(String token) async {
    try {
      await loginWithToken(token);
    } on TalerPacketException catch (e) {
      if (e.isSessionExpired) {
        _errorMessage = 'Сессия истекла. Войдите заново.';
        _isAuthenticated = false;
        await store.clearAccountData();
        notifyListeners();
      }
    } catch (_) {
      // В офлайне остаёмся на локальном кэше, TalerSession продолжит авто-реконнект.
    }
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  /// Запрос SMS/OTP кода авторизации (`Opcode.authRequest`).
  Future<String> requestOtp(String phone, {bool isResend = false}) async {
    _setBusy(true);
    try {
      return await _requestOtpInternal(phone, isResend: isResend);
    } finally {
      _setBusy(false);
    }
  }

  /// Повторный запрос SMS-кода для активного номера (`type: 'RESEND'`).
  Future<String> resendOtp([String? phone]) {
    final target = (phone != null && phone.trim().isNotEmpty)
        ? phone
        : (_lastOtpPhone ?? '');
    return requestOtp(target, isResend: true);
  }

  Future<String> _requestOtpInternal(
    String phone, {
    required bool isResend,
  }) async {
    if (!session.isOnline || session.callsSeed == null) {
      await session.connect(
        forceReconnect: session.isOnline && session.callsSeed == null,
      );
    }

    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      throw const TalerPacketException('Укажите номер телефона');
    }
    final normalized = '+$digits';
    final shortLocale =
        spoofingService.activeProfile.locale.split(RegExp(r'[-_]')).first;

    final payload = <String, dynamic>{
      'phone': normalized,
      'type': isResend ? 'RESEND' : 'START_AUTH',
      'language': shortLocale.isNotEmpty ? shortLocale : 'ru',
    };
    final seed = session.callsSeed;
    final deviceId =
        session.activeDeviceId ?? spoofingService.activeProfile.deviceId;
    if (seed != null && deviceId.isNotEmpty) {
      payload['mode'] = ChatCacheFingerprint.compute(seed, deviceId);
    }

    final packet = await session.request(Opcode.authRequest, payload);
    final data = packet.payloadAsMap ?? const {};
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const TalerPacketException('Сервер не вернул временный токен OTP');
    }

    _otpSessionEpoch = session.sessionEpoch;
    _lastOtpPhone = normalized;
    _lastTempToken = token;
    return token;
  }

  /// Проверка OTP-кода (`Opcode.auth`).
  Future<OtpVerifyOutcome> verifyOtp(String tempToken, String code) async {
    _setBusy(true);
    try {
      await _ensureSessionOnline();
      if (_otpSessionEpoch != -1 &&
          session.sessionEpoch != _otpSessionEpoch) {
        if (_lastOtpPhone != null && _lastOtpPhone!.isNotEmpty) {
          await _requestOtpInternal(_lastOtpPhone!, isResend: false);
        }
        throw const TalerPacketException(
          'Соединение обновилось — мы автоматически отправили новый SMS-код, введите его.',
          code: 'session.stale',
        );
      }

      final digitsOnly = code.replaceAll(RegExp(r'\D'), '');
      final cleanCode = digitsOnly.isNotEmpty ? digitsOnly : code.trim();
      final activeToken =
          tempToken.isNotEmpty ? tempToken : (_lastTempToken ?? '');

      final TalerPacket packet;
      try {
        packet = await session.request(Opcode.auth, {
          'token': activeToken,
          'verifyCode': cleanCode,
          'authTokenType': 'CHECK_CODE',
        });
      } on TalerPacketException catch (e) {
        final rawCode = e.code?.toLowerCase() ?? '';
        final rawMsg = e.message.toLowerCase();
        if (rawCode.contains('code.attempt.limit') ||
            rawMsg.contains('expired') ||
            rawMsg.contains('attempt')) {
          throw const TalerPacketException(
            'Срок действия кода истёк или превышен лимит попыток. Нажмите «Отправить новый код».',
            code: 'error.code.attempt.limit',
          );
        }
        rethrow;
      }

      final data = packet.payloadAsMap ?? const {};

      final challenge = data['passwordChallenge'];
      if (challenge is Map) {
        final trackId = challenge['trackId']?.toString() ?? '';
        final hint = challenge['hint']?.toString();
        return OtpVerifyOutcome.needs2fa(trackId: trackId, hint: hint);
      }

      final attrs = data['tokenAttrs'];
      if (attrs is Map) {
        final loginMap = attrs['LOGIN'];
        if (loginMap is Map && loginMap['token'] is String) {
          final loginToken = loginMap['token'] as String;
          await _finishTokenAuth(loginToken, initialPayload: data);
          return OtpVerifyOutcome.authenticated();
        }
        final regMap = attrs['REGISTER'];
        if (regMap is Map && regMap['token'] is String) {
          return OtpVerifyOutcome.needsRegistration(regMap['token'] as String);
        }
      }

      throw const TalerPacketException('Не удалось получить токен авторизации');
    } finally {
      _setBusy(false);
    }
  }

  /// Проверка облачного пароля 2FA (`Opcode.authLoginCheckPassword`).
  Future<void> verify2faPassword(String trackId, String password) async {
    _setBusy(true);
    try {
      await _ensureSessionOnline();
      final packet = await session.request(Opcode.authLoginCheckPassword, {
        'trackId': trackId,
        'password': password,
      });
      final data = packet.payloadAsMap ?? const {};
      final attrs = data['tokenAttrs'];
      final loginToken =
          attrs is Map && attrs['LOGIN'] is Map ? attrs['LOGIN']['token'] : null;
      if (loginToken is! String || loginToken.isEmpty) {
        throw const TalerPacketException('Неверный пароль 2FA');
      }
      await _finishTokenAuth(loginToken, initialPayload: data);
    } finally {
      _setBusy(false);
    }
  }

  /// Завершение регистрации нового аккаунта (`Opcode.authConfirm`).
  Future<void> completeRegistration(
    String registerToken,
    String firstName, {
    String? lastName,
  }) async {
    _setBusy(true);
    try {
      await _ensureSessionOnline();
      final payload = <String, dynamic>{
        'token': registerToken,
        'tokenType': 'REGISTER',
        'firstName': firstName.trim(),
      };
      if (lastName != null && lastName.trim().isNotEmpty) {
        payload['lastName'] = lastName.trim();
      }
      final packet = await session.request(Opcode.authConfirm, payload);
      final data = packet.payloadAsMap ?? const {};
      await _finishTokenAuth(registerToken, initialPayload: data);
    } finally {
      _setBusy(false);
    }
  }

  /// Прямой вход по сохранённому или введённому токену сессии (`Opcode.login`).
  Future<void> loginWithToken(String token) async {
    _setBusy(true);
    try {
      _isDemoMode = false;
      await _ensureSessionOnline();
      await _sendLogin(token.trim());
      _isAuthenticated = true;
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _finishTokenAuth(
    String loginToken, {
    Map<String, dynamic>? initialPayload,
  }) async {
    if (initialPayload != null && initialPayload['profile'] is Map) {
      final p = TalerUserProfile.fromServerProfile(
        initialPayload['profile'] as Map,
      );
      await store.saveProfile(p);
      await store.saveCredentials(loginToken, p.id);
    }
    await _sendLogin(loginToken);
    _isDemoMode = false;
    _isAuthenticated = true;
    notifyListeners();
  }

  Future<void> _sendLogin(String token) async {
    final payload = <String, dynamic>{
      'token': token,
      'interactive': !privacySettings.ghostModeOnline,
      'exp': {
        'chatsCountGroups': Uint8List.fromList([0x0b, 0x32]),
      },
      'presenceSync': -1,
      'chatsSync': -1,
    };

    final seed = session.callsSeed;
    final deviceId = session.activeDeviceId;
    if (seed != null && deviceId != null) {
      payload['chatCacheFingerprint'] =
          ChatCacheFingerprint.compute(seed, deviceId);
    }

    final packet = await session.request(Opcode.login, payload);
    final data = packet.payloadAsMap ?? const {};

    final updatedToken = data['token'] as String? ?? token;
    TalerUserProfile? profile;
    if (data['profile'] is Map) {
      profile = TalerUserProfile.fromServerProfile(data['profile'] as Map);
      await store.saveProfile(profile);
    }
    final accountId = profile?.id ?? store.accountId ?? 0;
    await store.saveCredentials(updatedToken, accountId);

    // Контакты
    final contactsMap = <int, TalerContact>{};
    final rawContacts = data['contacts'];
    if (rawContacts is List) {
      for (final item in rawContacts.whereType<Map>()) {
        final contact = TalerContact.fromServerMap(item);
        if (contact.id != 0) {
          contactsMap[contact.id] = contact;
        }
      }
    }

    // Статусы присутствия
    final presenceMap = data['presence'] is Map ? data['presence'] as Map : const {};
    for (final entry in presenceMap.entries) {
      final uid = int.tryParse(entry.key.toString());
      if (uid != null && entry.value is Map) {
        final p = entry.value as Map;
        final online = (p['status'] as num?)?.toInt() == 1;
        final seen = (p['seen'] as num?)?.toInt();
        final existing = contactsMap[uid];
        if (existing != null) {
          contactsMap[uid] = existing.copyWith(isOnline: online, lastSeen: seen);
        }
      }
    }
    if (contactsMap.isNotEmpty) {
      await store.saveContacts(contactsMap.values);
    }

    // Конфиг папок и мута
    final config = data['config'] is Map ? data['config'] as Map : const {};
    final chatsConfig =
        config['chats'] is Map ? config['chats'] as Map : const {};

    // Чаты
    final rawChats = data['chats'];
    if (rawChats is List) {
      await _ingestServerChats(
        rawChats,
        accountId: accountId,
        chatsConfig: chatsConfig,
        presenceMap: presenceMap,
      );
    }

    // Догрузка папок
    unawaited(_syncFolders(config));

    // Пагинация оставшихся чатов
    final chatMarker = data['chatMarker'];
    if (chatMarker is num && chatMarker.toInt() > 0) {
      unawaited(_paginateChats(chatMarker.toInt(), accountId));
    }

    notifyListeners();
  }

  Future<void> _ingestServerChats(
    List<dynamic> rawChats, {
    required int accountId,
    Map<dynamic, dynamic> chatsConfig = const {},
    Map<dynamic, dynamic> presenceMap = const {},
  }) async {
    final parsed = <TalerChat>[];
    for (final item in rawChats.whereType<Map>()) {
      final chat = _parseServerChat(
        item,
        accountId: accountId,
        chatsConfig: chatsConfig,
        presenceMap: presenceMap,
      );
      if (chat != null) parsed.add(chat);
    }
    if (parsed.isNotEmpty) {
      await store.saveChats(parsed);
    }
  }

  TalerChat? _parseServerChat(
    Map<dynamic, dynamic> map, {
    required int accountId,
    Map<dynamic, dynamic> chatsConfig = const {},
    Map<dynamic, dynamic> presenceMap = const {},
  }) {
    final id = (map['id'] as num?)?.toInt();
    if (id == null) return null;

    final type = map['type']?.toString().toUpperCase() ?? 'DIALOG';
    String title = (map['title'] as String?)?.trim() ?? '';
    String? avatarUrl = map['baseIconUrl'] as String?;
    int? peerId;
    bool isOnline = false;
    int? lastSeen;
    bool isOfficial = false;

    final participants = map['participants'];
    if (type == 'DIALOG' && participants is Map) {
      for (final key in participants.keys) {
        final uid = int.tryParse(key.toString());
        if (uid != null && uid != accountId) {
          peerId = uid;
          break;
        }
      }
      if (peerId != null) {
        final contact = store.contacts[peerId];
        if (contact != null) {
          if (title.isEmpty) title = contact.displayName;
          avatarUrl ??= contact.avatarUrl;
          isOnline = contact.isOnline;
          lastSeen = contact.lastSeen;
          isOfficial = contact.isOfficial;
        }
        final pres = presenceMap[peerId] ?? presenceMap['$peerId'];
        if (pres is Map) {
          isOnline = (pres['status'] as num?)?.toInt() == 1;
          lastSeen = (pres['seen'] as num?)?.toInt() ?? lastSeen;
        }
      }
    }

    if (title.isEmpty) {
      title = type == 'DIALOG' ? 'Диалог #$id' : 'Чат #$id';
    }

    String? lastText;
    int? lastTime;
    int? lastSenderId;
    final lastMsg = map['lastMessage'];
    if (lastMsg is Map) {
      lastText = lastMsg['text']?.toString();
      if ((lastText == null || lastText.isEmpty) &&
          lastMsg['attaches'] is List &&
          (lastMsg['attaches'] as List).isNotEmpty) {
        lastText = '[Вложение]';
      }
      lastTime = (lastMsg['time'] as num?)?.toInt();
      lastSenderId = (lastMsg['sender'] as num?)?.toInt();
    } else {
      lastTime = (map['lastEventTime'] as num?)?.toInt();
    }

    final cfg = chatsConfig[id] ?? chatsConfig['$id'];
    var favIndex = 0;
    var isMuted = false;
    if (cfg is Map) {
      favIndex = (cfg['favIndex'] as num?)?.toInt() ?? 0;
      final dnd = (cfg['dontDisturbUntil'] as num?)?.toInt() ?? 0;
      isMuted = dnd < 0 || dnd > DateTime.now().millisecondsSinceEpoch;
    }

    final options = map['options'];
    if (options is List && options.any((e) => e.toString() == 'OFFICIAL')) {
      isOfficial = true;
    }

    final existing = store.chats[id];
    return TalerChat(
      id: id,
      type: type,
      title: title,
      avatarUrl: avatarUrl,
      peerId: peerId,
      lastMessageText: lastText ?? existing?.lastMessageText,
      lastMessageTime: lastTime ?? existing?.lastMessageTime,
      lastMessageSenderId: lastSenderId ?? existing?.lastMessageSenderId,
      lastMessageDeletedByPeer: existing?.lastMessageDeletedByPeer ?? false,
      unreadCount: (map['newMessages'] as num?)?.toInt() ??
          (map['unread'] as num?)?.toInt() ??
          0,
      isOnline: isOnline,
      lastSeen: lastSeen,
      favIndex: favIndex,
      isMuted: isMuted,
      participantsCount: (map['participantsCount'] as num?)?.toInt() ??
          (participants is Map ? participants.length : 2),
      isOfficial: isOfficial,
    );
  }

  Future<void> _paginateChats(int startMarker, int accountId) async {
    var marker = startMarker;
    for (var page = 0; page < 10; page++) {
      try {
        final packet = await session.request(Opcode.chatsList, {
          'marker': marker,
          'count': 50,
        });
        final data = packet.payloadAsMap;
        if (data == null) break;
        final list = data['chats'];
        if (list is! List || list.isEmpty) break;
        await _ingestServerChats(list, accountId: accountId);
        notifyListeners();
        final next = (data['marker'] as num?)?.toInt();
        if (next == null || next == marker || list.length < 50) break;
        marker = next;
      } catch (_) {
        break;
      }
    }
  }

  Future<void> _syncFolders(Map<dynamic, dynamic> config) async {
    try {
      final packet = await session.request(
        Opcode.foldersGet,
        {'folderSync': 0},
        throwOnError: false,
      );
      final data = packet.payloadAsMap;
      final raw = data?['folders'];
      if (raw is List && raw.isNotEmpty) {
        final parsed = <TalerFolder>[];
        for (final f in raw.whereType<Map>()) {
          final id = f['id']?.toString() ?? 'all';
          final title = f['title']?.toString() ?? 'Все';
          final include = (f['include'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toSet() ??
              const <int>{};
          final favs = (f['favorites'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toList() ??
              const <int>[];
          parsed.add(
            TalerFolder(
              id: id,
              title: title,
              chatIds: include,
              favorites: favs,
              isAllChats: id == '0' || id == 'all' || title == 'Все',
            ),
          );
        }
        await store.saveFolders(parsed);
        notifyListeners();
        return;
      }
    } catch (_) {}

    if (store.folders.isEmpty) {
      await store.saveFolders(const [
        TalerFolder(id: 'all', title: 'Все', isAllChats: true),
      ]);
      notifyListeners();
    }
  }

  /// Загружает историю сообщений чата (`Opcode.chatHistory`).
  Future<List<TalerMessage>> loadHistory(int chatId, {int count = 50}) async {
    if (_isDemoMode || !session.isOnline) {
      return store.getMessages(chatId);
    }

    final packet = await session.request(Opcode.chatHistory, {
      'chatId': chatId,
      'from': DateTime.now().millisecondsSinceEpoch + 86400000,
      'forward': 0,
      'backward': count,
      'getMessages': true,
    });
    final data = packet.payloadAsMap;
    final rawMsgs = data?['messages'];
    if (rawMsgs is! List) return store.getMessages(chatId);

    final parsed = <TalerMessage>[];
    for (final m in rawMsgs.whereType<Map>()) {
      final msg = _parseServerMessage(m, chatId);
      if (msg != null) parsed.add(msg);
    }

    await store.saveMessagesBatch(chatId, parsed);
    notifyListeners();
    return store.getMessages(chatId);
  }

  TalerMessage? _parseServerMessage(Map<dynamic, dynamic> m, int chatId) {
    final id = m['id']?.toString();
    if (id == null || id.isEmpty) return null;

    final rawAttaches = m['attaches'];
    final attaches = <TalerAttachment>[];
    var isControl = false;
    if (rawAttaches is List) {
      for (final a in rawAttaches.whereType<Map>()) {
        final att = TalerAttachment.fromServerAttach(a);
        if (att.type == 'CONTROL') isControl = true;
        attaches.add(att);
      }
    }

    TalerReplyPreview? replyTo;
    String? forwardedFrom;
    final link = m['link'];
    if (link is Map) {
      final lType = link['type']?.toString().toUpperCase();
      final linkedMsg = link['message'];
      if (lType == 'REPLY' && linkedMsg is Map) {
        final sender = (linkedMsg['sender'] as num?)?.toInt() ?? 0;
        replyTo = TalerReplyPreview(
          messageId: linkedMsg['id']?.toString(),
          senderId: sender,
          senderName: senderDisplayName(sender, chatId: chatId),
          text: linkedMsg['text']?.toString(),
        );
      } else if (lType == 'FORWARD' && linkedMsg is Map) {
        final sender = (linkedMsg['sender'] as num?)?.toInt() ?? 0;
        forwardedFrom = link['chatName']?.toString() ??
            senderDisplayName(sender, chatId: chatId);
      }
    }

    final reactions = <TalerReactionCounter>[];
    final reactionInfo = m['reactionInfo'];
    if (reactionInfo is Map) {
      final your = reactionInfo['yourReaction']?.toString();
      final counters = reactionInfo['counters'];
      if (counters is List) {
        for (final c in counters.whereType<Map>()) {
          final emoji = c['reaction']?.toString();
          final count = (c['count'] as num?)?.toInt() ?? 0;
          if (emoji != null && emoji.isNotEmpty && count > 0) {
            reactions.add(
              TalerReactionCounter(
                emoji: emoji,
                count: count,
                isMine: emoji == your,
              ),
            );
          }
        }
      }
    }

    return TalerMessage(
      id: id,
      chatId: chatId,
      senderId: (m['sender'] as num?)?.toInt() ?? 0,
      text: m['text']?.toString() ?? '',
      time: (m['time'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      status: m['status']?.toString().toLowerCase() ?? 'sent',
      replyTo: replyTo,
      attachments: attaches,
      reactions: reactions,
      isControl: isControl,
      forwardedFromName: forwardedFrom,
    );
  }

  /// Отмечает чат прочитанным. При включённом `hideReadReceipts` пакет
  /// блокируется в [PrivacyFirewall] и не уходит на сервер.
  Future<void> markChatRead(int chatId) async {
    final chat = store.chats[chatId];
    if (chat == null || chat.unreadCount == 0) return;

    final msgs = store.getMessages(chatId);
    final lastMsg = msgs.isNotEmpty ? msgs.last : null;
    final msgIdNum = int.tryParse(lastMsg?.id ?? '');
    final markTime = lastMsg?.time ?? DateTime.now().millisecondsSinceEpoch;

    await store.saveChats([chat.copyWith(unreadCount: 0)]);
    notifyListeners();

    if (!_isDemoMode && session.isOnline && msgIdNum != null) {
      await session.request(
        Opcode.chatMark,
        {
          'type': 'READ_MESSAGE',
          'chatId': chatId,
          'messageId': msgIdNum,
          'mark': markTime,
        },
        throwOnError: false,
      );
    }
  }

  /// Переключает звук уведомлений для чата [chatId].
  Future<void> toggleChatMute(int chatId) async {
    final chat = store.chats[chatId];
    if (chat == null) return;
    final nextMuted = !chat.isMuted;
    await store.saveChats([chat.copyWith(isMuted: nextMuted)]);
    notifyListeners();

    if (!_isDemoMode && session.isOnline) {
      await session.request(
        Opcode.chatPersonalConfig,
        {
          'chatId': chatId,
          'dontDisturbUntil': nextMuted ? -1 : 0,
        },
        throwOnError: false,
      );
    }
  }

  /// Отправка индикатора набора текста. При включённом `hideTyping`
  /// пакет блокируется в [PrivacyFirewall].
  Future<void> sendTyping(int chatId) async {
    if (_isDemoMode || !session.isOnline) return;
    await session.request(
      Opcode.msgTyping,
      {'chatId': chatId, 'type': 'TEXT'},
      throwOnError: false,
    );
  }

  /// Отправляет текстовое сообщение (`Opcode.msgSend`).
  Future<void> sendMessage(
    int chatId,
    String text, {
    TalerMessage? replyTo,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp_$now';
    final myId = currentUser?.id ?? 1;

    final optimistic = TalerMessage(
      id: tempId,
      chatId: chatId,
      senderId: myId,
      text: trimmed,
      time: now,
      status: _isDemoMode ? 'sent' : 'sending',
      replyTo: replyTo == null
          ? null
          : TalerReplyPreview(
              messageId: replyTo.id,
              senderId: replyTo.senderId,
              senderName: senderDisplayName(replyTo.senderId, chatId: chatId),
              text: replyTo.text,
            ),
    );

    await store.upsertMessage(optimistic);
    final chat = store.chats[chatId];
    if (chat != null) {
      await store.saveChats([
        chat.copyWith(
          lastMessageText: trimmed,
          lastMessageTime: now,
          lastMessageSenderId: myId,
          lastMessageDeletedByPeer: false,
        ),
      ]);
    }
    notifyListeners();

    if (_isDemoMode) {
      auditLog.record(
        WireAuditEntry(
          timestamp: DateTime.now(),
          direction: PacketDirection.outgoing,
          opcode: Opcode.msgSend,
          opcodeName: Opcode.name(Opcode.msgSend),
          seq: auditLog.entries.length + 1,
          verdict: AuditVerdict.allowed,
          summary: 'Отправлено сообщение в чат #$chatId',
          payload: {'chatId': chatId, 'text': trimmed},
        ),
      );
      return;
    }

    final messageMap = <String, dynamic>{
      'text': trimmed,
      'cid': -now,
      'elements': const <dynamic>[],
      'attaches': const <dynamic>[],
    };
    if (replyTo != null) {
      final replyNumId = int.tryParse(replyTo.id);
      if (replyNumId != null) {
        messageMap['link'] = {
          'type': 'REPLY',
          'chatId': chatId,
          'messageId': replyNumId,
        };
      }
    }

    final packet = await session.request(Opcode.msgSend, {
      'chatId': chatId,
      'message': messageMap,
      'notify': true,
    });
    final data = packet.payloadAsMap;
    final msgObj = data?['message'];
    if (msgObj is Map) {
      final confirmed = _parseServerMessage(msgObj, chatId) ??
          optimistic.copyWith(
            id: msgObj['id']?.toString() ?? tempId,
            status: 'sent',
          );
      await store.replaceTempMessage(chatId, tempId, confirmed);
      notifyListeners();
    }
  }

  /// Загрузка и отправка фото (`Opcode.photoUpload`) или файла (`Opcode.fileUpload`).
  Future<void> sendFileAttachment(
    int chatId, {
    required String filePath,
    required String fileName,
    required bool isImage,
    String? caption,
  }) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final now = DateTime.now().millisecondsSinceEpoch;
    final myId = currentUser?.id ?? 1;

    if (_isDemoMode) {
      final msg = TalerMessage(
        id: 'demo_file_$now',
        chatId: chatId,
        senderId: myId,
        text: caption?.trim() ?? '',
        time: now,
        status: 'sent',
        attachments: [
          TalerAttachment(
            type: isImage ? 'PHOTO' : 'FILE',
            url: filePath,
            fileName: fileName,
            fileSize: bytes.length,
          ),
        ],
      );
      await store.upsertMessage(msg);
      final chat = store.chats[chatId];
      if (chat != null) {
        await store.saveChats([
          chat.copyWith(
            lastMessageText: isImage ? '📷 Фото: $fileName' : '📎 $fileName',
            lastMessageTime: now,
            lastMessageSenderId: myId,
          ),
        ]);
      }
      notifyListeners();
      return;
    }

    if (isImage) {
      final urlResp = await session.request(Opcode.photoUpload, {'count': 1});
      final uploadUrl = urlResp.payloadAsMap?['url'] as String?;
      if (uploadUrl == null || uploadUrl.isEmpty) {
        throw const TalerPacketException('Не получен URL для загрузки фото');
      }
      final req = http.MultipartRequest('POST', Uri.parse(uploadUrl))
        ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: fileName),
        );
      final streamed = await req.send();
      final body = await streamed.stream.bytesToString();
      final tokenMatch = RegExp(r'"token"\s*:\s*"([^"]+)"').firstMatch(body);
      final photoToken = tokenMatch?.group(1);
      if (photoToken == null) {
        throw const TalerPacketException('Сервер не вернул photoToken');
      }

      final sendResp = await session.request(Opcode.msgSend, {
        'chatId': chatId,
        'message': {
          'cid': -now,
          if (caption != null && caption.trim().isNotEmpty)
            'text': caption.trim(),
          'attaches': [
            {'_type': 'PHOTO', 'photoToken': photoToken},
          ],
        },
        'notify': true,
      });
      final msgMap = sendResp.payloadAsMap?['message'];
      if (msgMap is Map) {
        final parsed = _parseServerMessage(msgMap, chatId);
        if (parsed != null) {
          await store.upsertMessage(parsed);
          notifyListeners();
        }
      }
    } else {
      final urlResp = await session.request(Opcode.fileUpload, {'count': 1});
      final infoList = urlResp.payloadAsMap?['info'] as List?;
      final first =
          infoList != null && infoList.isNotEmpty && infoList.first is Map
              ? infoList.first as Map
              : null;
      final uploadUrl = first?['url'] as String?;
      final fileToken = first?['token'] as String?;
      final fileId = (first?['fileId'] as num?)?.toInt();
      if (uploadUrl == null || fileToken == null) {
        throw const TalerPacketException('Не получен URL для загрузки файла');
      }
      final req = http.MultipartRequest('POST', Uri.parse(uploadUrl))
        ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: fileName),
        );
      await req.send();

      final sendResp = await session.request(Opcode.msgSend, {
        'chatId': chatId,
        'message': {
          'cid': now,
          'elements': const <dynamic>[],
          'attaches': [
            {'_type': 'FILE', 'token': fileToken, 'fileId': ?fileId},
          ],
        },
        'notify': true,
      });
      final msgMap = sendResp.payloadAsMap?['message'];
      if (msgMap is Map) {
        final parsed = _parseServerMessage(msgMap, chatId);
        if (parsed != null) {
          await store.upsertMessage(parsed);
          notifyListeners();
        }
      }
    }
  }

  /// Редактирование сообщения (`Opcode.msgEdit`) с сохранением старой версии в истории правок.
  Future<void> editMessage(
    int chatId,
    String messageId,
    String newText,
  ) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;
    final list = store.getMessages(chatId);
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      await store.upsertMessage(list[idx].copyWith(text: trimmed));
      notifyListeners();
    }

    if (!_isDemoMode && session.isOnline) {
      final mid = int.tryParse(messageId);
      if (mid != null) {
        await session.request(Opcode.msgEdit, {
          'messageId': mid,
          'chatId': chatId,
          'elements': const <dynamic>[],
          'text': trimmed,
        });
      }
    }
  }

  /// Удаление сообщения (`Opcode.msgDelete`).
  Future<void> deleteMessage(
    int chatId,
    String messageId, {
    bool forEveryone = false,
  }) async {
    await store.markMessagesDeletedByPeer(
      chatId,
      [messageId],
      antiDeleteEnabled: false,
    );
    notifyListeners();

    if (!_isDemoMode && session.isOnline) {
      final mid = int.tryParse(messageId);
      if (mid != null) {
        await session.request(Opcode.msgDelete, {
          'messageIds': [mid],
          'chatId': chatId,
          'forMe': !forEveryone,
          'itemType': 'REGULAR',
        });
      }
    }
  }

  /// Тест работы Anti-Delete на любом сообщении в демо-режиме.
  Future<void> simulatePeerDeleteInDemo(int chatId, String messageId) async {
    await store.markMessagesDeletedByPeer(
      chatId,
      [messageId],
      antiDeleteEnabled: privacySettings.antiDelete,
    );
    auditLog.record(
      WireAuditEntry(
        timestamp: DateTime.now(),
        direction: PacketDirection.incoming,
        opcode: Opcode.notifMsgDelete,
        opcodeName: Opcode.name(Opcode.notifMsgDelete),
        seq: 0,
        verdict: AuditVerdict.allowed,
        summary: privacySettings.antiDelete
            ? 'Anti-Delete: перехвачено удаление #$messageId, сообщение сохранено'
            : 'Удалено сообщение #$messageId',
        payload: {'chatId': chatId, 'messageIds': [messageId]},
      ),
    );
    notifyListeners();
  }

  /// Отправка / снятие реакции (`Opcode.msgReaction` / `Opcode.msgCancelReaction`).
  Future<void> toggleReaction(
    int chatId,
    String messageId,
    String emoji,
  ) async {
    final msgs = store.getMessages(chatId);
    final idx = msgs.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;

    final target = msgs[idx];
    final currentMine = target.reactions.where((r) => r.isMine).firstOrNull;
    final removeCurrent = currentMine?.emoji == emoji;

    final nextReactions = <TalerReactionCounter>[];
    var added = false;
    for (final r in target.reactions) {
      if (r.isMine && r.emoji == emoji && removeCurrent) {
        if (r.count > 1) {
          nextReactions.add(
            TalerReactionCounter(emoji: r.emoji, count: r.count - 1),
          );
        }
        continue;
      }
      if (r.isMine) {
        if (r.count > 1) {
          nextReactions.add(
            TalerReactionCounter(emoji: r.emoji, count: r.count - 1),
          );
        }
        continue;
      }
      if (!removeCurrent && r.emoji == emoji) {
        nextReactions.add(
          TalerReactionCounter(emoji: r.emoji, count: r.count + 1, isMine: true),
        );
        added = true;
      } else {
        nextReactions.add(r);
      }
    }
    if (!removeCurrent && !added) {
      nextReactions.add(
        TalerReactionCounter(emoji: emoji, count: 1, isMine: true),
      );
    }

    await store.upsertMessage(
      target.copyWith(reactions: nextReactions),
      trackEditHistory: false,
    );
    notifyListeners();

    if (!_isDemoMode && session.isOnline) {
      final mid = int.tryParse(messageId);
      if (mid != null) {
        if (removeCurrent) {
          await session.request(Opcode.msgCancelReaction, {
            'chatId': chatId,
            'messageId': mid,
          });
        } else {
          await session.request(Opcode.msgReaction, {
            'chatId': chatId,
            'messageId': mid,
            'reaction': {'reactionType': 'EMOJI', 'id': emoji},
          });
        }
      }
    }
  }

  /// Обновляет имя и фамилию в профиле (`Opcode.profile`).
  Future<void> updateProfileName(String firstName, String? lastName) async {
    final current = store.profile;
    if (current == null) return;
    final trimmedFirst = firstName.trim();
    final trimmedLast = lastName?.trim();
    if (trimmedFirst.isEmpty) return;

    await store.saveProfile(
      current.copyWith(
        firstName: trimmedFirst,
        lastName: (trimmedLast == null || trimmedLast.isEmpty) ? null : trimmedLast,
      ),
    );
    notifyListeners();

    if (!_isDemoMode && session.isOnline) {
      await session.request(Opcode.profile, {
        'firstName': trimmedFirst,
        if (trimmedLast != null && trimmedLast.isNotEmpty) 'lastName': trimmedLast,
      });
    }
  }

  /// Запрашивает список активных сессий (`Opcode.sessionsInfo`).
  Future<void> fetchActiveSessions() async {
    if (_isDemoMode) {
      final spoof = spoofingService.activeProfile;
      _activeSessions = [
        TalerActiveSession(
          id: 1,
          client: 'Taler (${spoof.label})',
          location: 'Замаскировано • ${spoof.timezone}',
          current: true,
          time: DateTime.now().millisecondsSinceEpoch,
          info: spoof.osVersion,
        ),
        TalerActiveSession(
          id: 2,
          client: 'MAX Web',
          location: 'Moscow, RU',
          current: false,
          time: DateTime.now()
              .subtract(const Duration(days: 2))
              .millisecondsSinceEpoch,
          info: 'Chrome Desktop',
        ),
      ];
      notifyListeners();
      return;
    }

    if (!session.isOnline) return;
    final packet = await session.request(Opcode.sessionsInfo, {});
    final raw = packet.payloadAsMap?['sessions'];
    if (raw is List) {
      _activeSessions = raw
          .whereType<Map>()
          .map(TalerActiveSession.fromMap)
          .toList();
      notifyListeners();
    }
  }

  /// Завершает все остальные сессии (`Opcode.sessionsClose`).
  Future<void> terminateOtherSessions() async {
    if (_isDemoMode) {
      _activeSessions = _activeSessions.where((s) => s.current).toList();
      notifyListeners();
      return;
    }
    if (!session.isOnline) return;
    await session.request(Opcode.sessionsClose, {});
    await fetchActiveSessions();
  }

  /// Пробная отправка телеметрии через [PrivacyFirewall] для демонстрации
  /// в Traffic Audit Log, что пакеты гарантированно режутся до сокета.
  Future<void> triggerTelemetryTestProbe() async {
    await session.request(Opcode.log, {
      'events': [
        {'type': 'SCREEN_VIEW', 'screen': 'CHATS_LIST'},
      ],
    });
    await session.request(Opcode.bannersSync, {'sync': 0});
    await session.request(Opcode.debug, {'probe': 'telemetry_audit'});
  }

  void _handleServerPush(TalerPacket packet) {
    final data = packet.payloadAsMap;
    if (data == null) return;

    switch (packet.opcode) {
      case Opcode.notifMessage:
        final chatId = (data['chatId'] as num?)?.toInt();
        final msgMap = data['message'];
        if (chatId != null && msgMap is Map) {
          final parsed = _parseServerMessage(msgMap, chatId);
          if (parsed != null) {
            unawaited(_applyIncomingMessage(chatId, parsed));
          }
        }
      case Opcode.notifMsgDelete:
      case Opcode.notifMsgDeleteRange:
        final chatId = (data['chatId'] as num?)?.toInt();
        final idsRaw = data['messageIds'];
        if (chatId != null && idsRaw is List) {
          final ids = idsRaw.map((e) => e.toString()).toList();
          unawaited(() async {
            await store.markMessagesDeletedByPeer(
              chatId,
              ids,
              antiDeleteEnabled: privacySettings.antiDelete,
            );
            notifyListeners();
          }());
        }
      case Opcode.notifTyping:
        final chatId = (data['chatId'] as num?)?.toInt();
        final userId = (data['user'] as num?)?.toInt();
        if (chatId != null) {
          final name = userId != null
              ? senderDisplayName(userId, chatId: chatId)
              : 'Собеседник';
          final chat = store.chats[chatId];
          if (chat != null) {
            unawaited(
              store.saveChats([chat.copyWith(typingLabel: '$name печатает...')]),
            );
            notifyListeners();
            _typingClearTimers[chatId]?.cancel();
            _typingClearTimers[chatId] = Timer(const Duration(seconds: 5), () {
              final cur = store.chats[chatId];
              if (cur != null) {
                unawaited(store.saveChats([cur.copyWith(clearTyping: true)]));
                notifyListeners();
              }
            });
          }
        }
      case Opcode.notifPresence:
        final presence = data['presence'];
        if (presence is Map) {
          unawaited(_applyPresencePush(presence));
        }
      case Opcode.notifMark:
        final chatId = (data['chatId'] as num?)?.toInt();
        final unread = (data['unread'] as num?)?.toInt();
        if (chatId != null && unread != null) {
          final chat = store.chats[chatId];
          if (chat != null) {
            unawaited(store.saveChats([chat.copyWith(unreadCount: unread)]));
            notifyListeners();
          }
        }
    }
  }

  Future<void> _applyIncomingMessage(int chatId, TalerMessage msg) async {
    await store.upsertMessage(msg);
    final chat = store.chats[chatId];
    if (chat != null) {
      final isMine = msg.senderId == currentUser?.id;
      await store.saveChats([
        chat.copyWith(
          lastMessageText: msg.text.isNotEmpty ? msg.text : '[Вложение]',
          lastMessageTime: msg.time,
          lastMessageSenderId: msg.senderId,
          lastMessageDeletedByPeer: false,
          unreadCount: isMine ? chat.unreadCount : chat.unreadCount + 1,
          clearTyping: true,
        ),
      ]);
    }
    notifyListeners();
  }

  Future<void> _applyPresencePush(Map<dynamic, dynamic> presence) async {
    var changed = false;
    for (final entry in presence.entries) {
      final uid = int.tryParse(entry.key.toString());
      if (uid == null || entry.value is! Map) continue;
      final p = entry.value as Map;
      final online = (p['status'] as num?)?.toInt() == 1;
      final seen = (p['seen'] as num?)?.toInt();
      final contact = store.contacts[uid];
      if (contact != null) {
        await store.saveContacts([
          contact.copyWith(isOnline: online, lastSeen: seen),
        ]);
        changed = true;
      }
      for (final chat in store.chats.values) {
        if (chat.peerId == uid) {
          await store.saveChats([
            chat.copyWith(isOnline: online, lastSeen: seen),
          ]);
          changed = true;
        }
      }
    }
    if (changed) notifyListeners();
  }

  /// Запускает локальный демо-режим с примерами чатов, Anti-Delete и аудита пакетов.
  Future<void> enterDemoMode() async {
    _setBusy(true);
    try {
      await store.clearAccountData();
      _isDemoMode = true;

      final now = DateTime.now().millisecondsSinceEpoch;
      const myProfile = TalerUserProfile(
        id: 1001,
        firstName: 'Алексей',
        lastName: 'Громов',
        phone: '+7 900 555-01-42',
      );
      await store.saveProfile(myProfile);

      await store.saveContacts(const [
        TalerContact(id: 2001, firstName: 'Елена', lastName: 'Соколова', isOnline: true),
        TalerContact(id: 2002, firstName: 'Дмитрий', lastName: 'Dev', isOnline: false),
        TalerContact(id: 3001, firstName: 'Komet', lastName: 'Team', isOfficial: true),
      ]);

      await store.saveChats([
        TalerChat(
          id: 5001,
          type: 'CHAT',
          title: 'Taler & Komet Community',
          lastMessageText: 'Протокол MsgPack + LZ4 полностью на чистом Dart',
          lastMessageTime: now - 120000,
          lastMessageSenderId: 3001,
          unreadCount: 2,
          favIndex: 1,
          participantsCount: 418,
          isOfficial: true,
        ),
        TalerChat(
          id: 5002,
          type: 'DIALOG',
          title: 'Елена Соколова',
          peerId: 2001,
          lastMessageText: 'Встречаемся в 19:00 у офиса, код от двери 4812#',
          lastMessageTime: now - 300000,
          lastMessageSenderId: 2001,
          lastMessageDeletedByPeer: true,
          unreadCount: 1,
          isOnline: true,
        ),
        TalerChat(
          id: 5003,
          type: 'DIALOG',
          title: 'Дмитрий Dev',
          peerId: 2002,
          lastMessageText: 'Залил билд под Windows и IPA для iPhone',
          lastMessageTime: now - 3600000,
          lastMessageSenderId: 2002,
          unreadCount: 0,
        ),
        TalerChat(
          id: 5004,
          type: 'CHANNEL',
          title: 'OpenSource Privacy',
          lastMessageText: 'Как Taler вырезает телеметрию MAX на уровне сокета',
          lastMessageTime: now - 7200000,
          lastMessageSenderId: 3001,
          unreadCount: 0,
          participantsCount: 12900,
          isOfficial: true,
        ),
      ]);

      await store.saveFolders(const [
        TalerFolder(id: 'all', title: 'Все', isAllChats: true),
        TalerFolder(id: 'private', title: 'Приватные', chatIds: {5002, 5003}),
        TalerFolder(id: 'channels', title: 'Каналы', chatIds: {5001, 5004}),
      ]);

      await store.saveMessagesBatch(5001, [
        TalerMessage(
          id: '101',
          chatId: 5001,
          senderId: 3001,
          text:
              'Добро пожаловать в Taler! Клиент работает с MAX по открытому протоколу без проприетарных SDK и без телеметрии.',
          time: now - 600000,
          reactions: const [
            TalerReactionCounter(emoji: '🔥', count: 14, isMine: true),
            TalerReactionCounter(emoji: '🛡️', count: 9),
          ],
        ),
        TalerMessage(
          id: '102',
          chatId: 5001,
          senderId: 2002,
          text: 'Протокол MsgPack + LZ4 полностью на чистом Dart',
          time: now - 120000,
          replyTo: const TalerReplyPreview(
            messageId: '101',
            senderId: 3001,
            senderName: 'Komet Team',
            text: 'Добро пожаловать в Taler!',
          ),
        ),
      ]);

      await store.saveMessagesBatch(5002, [
        TalerMessage(
          id: '201',
          chatId: 5002,
          senderId: 2001,
          text: 'Привет! Ты уже поставил Taler с вырезанной телеметрией?',
          time: now - 900000,
        ),
        TalerMessage(
          id: '202',
          chatId: 5002,
          senderId: 1001,
          text: 'Да, и включил Ghost Mode + подмену Device ID на Pixel 8 Pro.',
          time: now - 720000,
          status: 'edited',
          editHistory: [
            TalerEditRevision(
              text: 'Да, только что собрал из исходников grentu/Taler.',
              timestamp: now - 700000,
            ),
          ],
        ),
        TalerMessage(
          id: '203',
          chatId: 5002,
          senderId: 2001,
          text: 'Встречаемся в 19:00 у офиса, код от двери 4812#',
          time: now - 300000,
          deletedByPeer: true,
          deletedAt: now - 180000,
          reactions: const [TalerReactionCounter(emoji: '👀', count: 1)],
        ),
      ]);

      await store.saveMessagesBatch(5003, [
        TalerMessage(
          id: '301',
          chatId: 5003,
          senderId: 2002,
          text: 'Залил билд под Windows и IPA для iPhone',
          time: now - 3600000,
          attachments: const [
            TalerAttachment(
              type: 'FILE',
              fileName: 'taler-protocol-spec.pdf',
              fileSize: 482304,
            ),
          ],
        ),
      ]);

      await store.saveMessagesBatch(5004, [
        TalerMessage(
          id: '401',
          chatId: 5004,
          senderId: 3001,
          text:
              'Как Taler вырезает телеметрию MAX на уровне сокета:\n'
              '1. Жёсткая блокировка опкодов LOG (5), DEBUG (2), BANNERS_SYNC (302).\n'
              '2. Замена реальных параметров устройства на виртуальный профиль.\n'
              '3. Режим Призрака: скрытие онлайна, набора текста и прочтения.',
          time: now - 7200000,
          reactions: const [
            TalerReactionCounter(emoji: '🛡️', count: 42, isMine: true),
            TalerReactionCounter(emoji: '❤️', count: 18),
          ],
        ),
      ]);

      // Симулируем перехват телеметрии, чтобы сразу заполнить Audit Log
      await triggerTelemetryTestProbe();

      _isAuthenticated = true;
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  /// Выход из аккаунта (`Opcode.logout`) и очистка локальной базы.
  Future<void> logout() async {
    _setBusy(true);
    try {
      if (!_isDemoMode && session.isOnline) {
        try {
          await session.request(Opcode.logout, <String, dynamic>{});
        } catch (_) {}
      }
      await session.disconnect();
      await store.clearAccountData();
      _activeSessions = const [];
      _isDemoMode = false;
      _isAuthenticated = false;
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _ensureSessionOnline() async {
    if (!session.isOnline) {
      await session.connect();
    }
  }

  void _setBusy(bool value) {
    _isLoading = value;
    if (value) _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _pushSub?.cancel();
    for (final t in _typingClearTimers.values) {
      t.cancel();
    }
    _typingClearTimers.clear();
    unawaited(session.dispose());
    super.dispose();
  }
}

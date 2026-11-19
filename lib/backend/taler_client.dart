import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../core/media/taler_media_cache.dart';
import '../core/platform/taler_native_bridge.dart';
import '../core/privacy/privacy_firewall.dart';
import '../core/privacy/privacy_settings.dart';
import '../core/privacy/spoofing_service.dart';
import '../core/protocol/fingerprint.dart';
import '../core/protocol/opcode.dart';
import '../core/protocol/packet.dart';
import '../core/storage/app_preferences.dart';
import '../core/storage/local_store.dart';
import '../core/storage/taler_models.dart';
import '../core/transport/taler_session.dart';
import '../core/update/app_updater.dart';

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
  final AppPreferences appPreferences;
  final AppUpdater updater;
  final bool _ownsUpdater;

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
  final Map<int, Timer> _draftSyncTimers = {};
  final Map<String, double> _downloadProgress = {};
  final Map<String, String> _downloadedPaths = {};
  final Map<String, String> _sendErrors = {};
  final Map<int, bool> _chatHasMore = {};
  final Set<int> _loadingMoreChats = {};
  List<TalerChat>? _cachedSortedChats;
  int _otpSessionEpoch = -1;
  int _loggedInSessionEpoch = -1;
  int _cidSeed = 0;
  int? _activeChatId;
  bool _appInForeground = true;
  Future<void>? _loginInFlight;
  String? _lastOtpPhone;
  String? _lastTempToken;

  TalerClient({
    required this.privacySettings,
    required this.spoofingService,
    required this.auditLog,
    required this.store,
    AppPreferences? appPreferences,
    AppUpdater? updater,
  })  : appPreferences = appPreferences ?? AppPreferences(),
        _ownsUpdater = updater == null,
        updater = updater ?? AppUpdater() {
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
      if (token != null &&
          token.isNotEmpty &&
          !_isDemoMode &&
          _isAuthenticated) {
        await _ensureLoggedInWithToken(token);
        final activeId = _activeChatId;
        if (activeId != null) {
          unawaited(
            loadHistory(activeId).catchError((_) => const <TalerMessage>[]),
          );
        }
      }
    };
    _connSub = session.stateStream.listen((s) {
      _connectionState = s;
      if (s == TalerConnectionState.disconnected) {
        _loggedInSessionEpoch = -1;
      }
      notifyListeners();
    });
    _pushSub = session.pushStream.listen(_handleServerPush);
  }

  bool get isAuthenticated => _isAuthenticated;
  bool get isDemoMode => _isDemoMode;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  TalerConnectionState get connectionState => _connectionState;
  bool get isSessionReady =>
      _isDemoMode ||
      (session.isOnline && _loggedInSessionEpoch == session.sessionEpoch);
  TalerUserProfile? get currentUser => store.profile;
  List<TalerFolder> get folders => store.folders;
  List<TalerActiveSession> get activeSessions => _activeSessions;
  String? get lastTempToken => _lastTempToken;
  String? sendErrorFor(String messageId) => _sendErrors[messageId];
  bool canLoadMoreHistory(int chatId) => _chatHasMore[chatId] ?? true;
  bool isLoadingMoreHistory(int chatId) => _loadingMoreChats.contains(chatId);
  TalerDraft? draftForChat(int chatId) => store.draftFor(chatId);
  double? downloadProgressFor(String key) => _downloadProgress[key];
  String? downloadedPathFor(String key) => _downloadedPaths[key];

  static String attachmentKey(String messageId, TalerAttachment attach) =>
      '$messageId:${attach.fileId ?? attach.videoId ?? attach.audioId ?? attach.url ?? attach.fileName ?? attach.type}';

  void setAppForeground(bool value) {
    _appInForeground = value;
    final activeId = _activeChatId;
    if (value && activeId != null) {
      unawaited(TalerNativeBridge.instance.cancelChatNotification(activeId));
    }
  }

  void setActiveChat(int? chatId) {
    _activeChatId = chatId;
    if (chatId != null) {
      unawaited(TalerNativeBridge.instance.cancelChatNotification(chatId));
    }
  }

  /// Сохраняет черновик локально и синхронизирует с сервером (`Opcode.draftSave` / `Opcode.draftDiscard`).
  Future<void> saveDraft(
    int chatId,
    String text, {
    String? replyToMessageId,
    bool syncRemote = true,
  }) async {
    final trimmed = text.trim();
    final current = store.draftFor(chatId);
    if (trimmed.isEmpty) {
      if (current != null) {
        await store.saveDraft(chatId, null);
        notifyListeners();
      }
    } else if (current == null ||
        current.text != text ||
        current.replyToMessageId != replyToMessageId) {
      await store.saveDraft(
        chatId,
        TalerDraft(
          text: text,
          replyToMessageId: replyToMessageId,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      notifyListeners();
    }

    if (!syncRemote || _isDemoMode || !isSessionReady) return;
    _draftSyncTimers[chatId]?.cancel();
    _draftSyncTimers[chatId] = Timer(const Duration(milliseconds: 900), () {
      _draftSyncTimers.remove(chatId);
      if (!_isAuthenticated || _isDemoMode || !isSessionReady) return;
      final latest = store.draftFor(chatId);
      if (latest == null || latest.isEmpty) {
        unawaited(
          session
              .request(
                Opcode.draftDiscard,
                {'chatId': chatId},
                throwOnError: false,
              )
              .catchError((_) => const TalerPacket(cmd: CmdType.ok, seq: 0, opcode: Opcode.draftDiscard)),
        );
      } else {
        final replyId = int.tryParse(latest.replyToMessageId ?? '');
        unawaited(
          session
              .request(
                Opcode.draftSave,
                {
                  'chatId': chatId,
                  'draft': {
                    'text': latest.text,
                    if (replyId != null)
                      'link': {
                        'type': 'REPLY',
                        'chatId': chatId,
                        'messageId': replyId,
                      },
                  },
                },
                throwOnError: false,
              )
              .catchError((_) => const TalerPacket(cmd: CmdType.ok, seq: 0, opcode: Opcode.draftSave)),
        );
      }
    });
  }

  void clearActiveChat(int chatId) {
    if (_activeChatId == chatId) {
      _activeChatId = null;
    }
  }

  void wakeUp() {
    if (_isDemoMode || !_isAuthenticated) return;
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    session.wakeUp();
    final token = store.authToken;
    if (token != null &&
        token.isNotEmpty &&
        session.isOnline &&
        _loggedInSessionEpoch != session.sessionEpoch) {
      unawaited(
        _ensureLoggedInWithToken(token).catchError((_) {}),
      );
    }
  }

  int _nextCid() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now <= _cidSeed) {
      _cidSeed++;
    } else {
      _cidSeed = now;
    }
    return -_cidSeed;
  }

  Future<void> _ensureLoggedInWithToken(String token) {
    if (_loggedInSessionEpoch == session.sessionEpoch && session.isOnline) {
      return Future<void>.value();
    }
    final inFlight = _loginInFlight;
    if (inFlight != null) return inFlight;
    final run = _sendLogin(token);
    _loginInFlight = run;
    return run.whenComplete(() {
      if (identical(_loginInFlight, run)) _loginInFlight = null;
    });
  }

  /// Гарантирует, что сокет онлайн и авторизация по токену (`Opcode.login`) завершена.
  Future<void> ensureReady() async {
    if (_isDemoMode) return;
    if (!session.isOnline) {
      await session.connect(enableReconnect: true);
    }
    final token = store.authToken;
    if (token != null &&
        token.isNotEmpty &&
        _loggedInSessionEpoch != session.sessionEpoch) {
      await _ensureLoggedInWithToken(token);
    }
  }

  @override
  void notifyListeners() {
    _cachedSortedChats = null;
    super.notifyListeners();
  }

  List<TalerChat> get chats {
    final cached = _cachedSortedChats;
    if (cached != null) return cached;
    final list = store.chats.values.where((c) {
      if (_isDemoMode) return true;
      final hasActivity = (c.lastMessageTime ?? 0) > 0 ||
          (c.lastMessageText != null && c.lastMessageText!.trim().isNotEmpty) ||
          c.unreadCount > 0 ||
          c.favIndex > 0 ||
          store.getMessages(c.id).isNotEmpty;
      return hasActivity;
    }).toList()
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

  final Set<int> _resolvingContacts = <int>{};

  /// Подтягивает имена и аватарки людей, которых нет в контактах
  /// (Opcode.contactInfo), и переименовывает «Диалог #id» в настоящие имена.
  Future<void> resolveContacts(Iterable<int> ids) async {
    if (_isDemoMode || !isSessionReady) return;
    final missing = ids
        .where((id) => id > 0 && store.contacts[id] == null && !_resolvingContacts.contains(id))
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    _resolvingContacts.addAll(missing);
    final resolved = <TalerContact>[];
    try {
      for (var i = 0; i < missing.length; i += 100) {
        final end = i + 100 < missing.length ? i + 100 : missing.length;
        try {
          final packet = await session.request(Opcode.contactInfo, <String, dynamic>{
            'contactIds': missing.sublist(i, end),
          });
          final list = packet.payloadAsMap?['contacts'];
          if (list is List) {
            for (final item in list.whereType<Map>()) {
              final contact = TalerContact.fromServerMap(item);
              if (contact.id != 0) resolved.add(contact);
            }
          }
        } catch (_) {}
      }
    } finally {
      _resolvingContacts.removeAll(missing);
    }
    if (resolved.isEmpty) return;
    await store.saveContacts(resolved);
    await _reconcileDialogTitles();
    TalerMediaCache.instance.prefetchUrls(resolved.take(25).map((c) => c.avatarUrl));
    notifyListeners();
  }

  Future<void> _reconcileDialogTitles() async {
    final myId = store.accountId ?? currentUser?.id;
    final updated = <TalerChat>[];
    for (final chat in store.chats.values) {
      if (!chat.isDialog) continue;
      final peer = chat.peerId;
      final placeholder = chat.title.trim().isEmpty || chat.title.startsWith('Диалог #');
      if (peer != null && myId != null && peer == myId) {
        if (placeholder || (chat.avatarUrl == null && currentUser?.avatarUrl != null)) {
          updated.add(chat.copyWith(
            title: placeholder ? 'Избранное' : null,
            avatarUrl: chat.avatarUrl ?? currentUser?.avatarUrl,
          ));
        }
        continue;
      }
      if (peer == null) continue;
      final contact = store.contacts[peer];
      if (contact == null) continue;
      final needsAvatar = chat.avatarUrl == null && contact.avatarUrl != null;
      if ((placeholder && !contact.displayName.startsWith('ID ')) || needsAvatar) {
        updated.add(chat.copyWith(
          title: placeholder ? contact.displayName : null,
          avatarUrl: chat.avatarUrl ?? contact.avatarUrl,
        ));
      }
    }
    if (updated.isNotEmpty) {
      await store.saveChats(updated);
    }
  }

  /// Отправители сообщений открытого чата, которых нет в контактах.
  Future<void> resolveChatMembers(int chatId) =>
      resolveContacts(store.getMessages(chatId).map((m) => m.senderId));

  void _resolveDialogPeers() {
    unawaited(_reconcileDialogTitles());
    final myId = store.accountId;
    final missingContactIds = <int>{};
    final unknownChatIds = <int>[];
    for (final c in store.chats.values) {
      if (c.isDialog && c.peerId != null && c.peerId != myId) {
        final contact = store.contacts[c.peerId!];
        final isPlaceholder = c.title.isEmpty || c.title.startsWith('Диалог #');
        if (contact == null || (isPlaceholder && contact.displayName.startsWith('ID '))) {
          missingContactIds.add(c.peerId!);
        }
      } else if (c.title.isEmpty || c.title.startsWith('Диалог #') || c.title.startsWith('Чат #')) {
        unknownChatIds.add(c.id);
      }
    }
    if (missingContactIds.isNotEmpty) {
      unawaited(resolveContacts(missingContactIds));
    }
    if (unknownChatIds.isNotEmpty) {
      unawaited(_resolveUnknownChats(unknownChatIds));
    }
    TalerMediaCache.instance.prefetchUrls(chats.take(25).map((c) => c.avatarUrl));
  }

  Future<void> _resolveUnknownChats(List<int> chatIds) async {
    if (_isDemoMode || !isSessionReady || chatIds.isEmpty) return;
    final accountId = store.accountId ?? 0;
    try {
      for (var i = 0; i < chatIds.length; i += 50) {
        final end = i + 50 < chatIds.length ? i + 50 : chatIds.length;
        final packet = await session.request(
          Opcode.chatInfo,
          <String, dynamic>{'chatIds': chatIds.sublist(i, end)},
          throwOnError: false,
        );
        final list = packet.payloadAsMap?['chats'];
        if (list is List && list.isNotEmpty) {
          await _ingestServerChats(list, accountId: accountId);
        }
      }
    } catch (_) {}
  }

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
    await appPreferences.load();
    await store.init();
    if (appPreferences.autoCheckUpdates) {
      unawaited(updater.checkForUpdates(silent: true));
    }

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
        _loggedInSessionEpoch = -1;
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

  /// Код ошибки MAX, когда у аккаунта есть активная сессия, а пароль
  /// для входа (2FA) не задан: сервер не пускает новые устройства.
  static const String no2faErrorCode = 'error.profile.active.session.no2fa';

  /// Распознаёт ограничение входа "нужно установить 2FA" в любой обёртке.
  static bool isNo2faError(Object error) {
    if (error is TalerPacketException && error.code == no2faErrorCode) {
      return true;
    }
    return error.toString().toLowerCase().contains('no2fa');
  }

  /// Заранее поднимает соединение с MAX, пока пользователь вводит номер,
  /// чтобы запрос кода не ждал подключения.
  void warmUpConnection() {
    if (_isDemoMode || session.isOnline) return;
    // Widget-тесты не должны ходить в сеть.
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    session.connect().then<void>((_) {}, onError: (Object _) {});
  }

  /// Включает или выключает маскировку устройства перед входом и сразу
  /// переподключается, чтобы следующий запрос кода ушёл с новым профилем.
  Future<void> setLoginSpoofing(bool enabled) async {
    if (privacySettings.spoofingEnabled == enabled) return;
    await privacySettings.setSpoofingEnabled(enabled);
    notifyListeners();
    if (_isDemoMode || _isAuthenticated) return;
    session.connect(forceReconnect: true).then<void>((_) {}, onError: (Object _) {});
  }

  /// Подключение через веб-шлюз MAX (deviceType WEB) вместо прямого TLS.
  bool get preferWebGateway => session.preferWebGateway;

  Future<void> setPreferWebGateway(bool value) async {
    if (session.preferWebGateway == value) return;
    session.preferWebGateway = value;
    notifyListeners();
    if (_isDemoMode || _isAuthenticated) return;
    session.connect(forceReconnect: true).then<void>((_) {}, onError: (Object _) {});
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
    // Переподключаемся только когда это действительно нужно: TLS-сессия без
    // callsSeed не примет запрос кода, а веб-шлюз seed не выдаёт вовсе.
    final needsSeed = session.isOnline &&
        session.transport == TalerTransport.tls &&
        session.callsSeed == null;
    if (!session.isOnline || needsSeed) {
      await session.connect(forceReconnect: needsSeed);
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

    final packet = await session.request(
      Opcode.authRequest,
      payload,
      timeout: const Duration(seconds: 15),
    );
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
      await _ensureLoggedInWithToken(token.trim());
      _isAuthenticated = true;
      notifyListeners();
      final activeId = _activeChatId;
      if (activeId != null) {
        unawaited(
          loadHistory(activeId).catchError((_) => const <TalerMessage>[]),
        );
      }
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
    await _ensureLoggedInWithToken(loginToken);
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
    _loggedInSessionEpoch = session.sessionEpoch;
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
        final seen = normalizeEpochMs((p['seen'] as num?)?.toInt());
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
      final id = (item['id'] as num?)?.toInt();
      final status = item['status']?.toString().toUpperCase();
      if (id != null &&
          (status == 'REMOVED' ||
              status == 'LEFT' ||
              status == 'CLOSED' ||
              status == 'DELETED')) {
        if (store.chats.containsKey(id)) {
          await store.removeChat(id);
        }
        continue;
      }
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
    _resolveDialogPeers();
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
    bool sawSelfParticipant = false;

    final participants = map['participants'];
    final Iterable<dynamic>? participantKeys = participants is Map
        ? participants.keys
        : (participants is List ? participants : null);
    if (type == 'DIALOG' && participantKeys != null) {
      for (final key in participantKeys) {
        final uid = key is num ? key.toInt() : int.tryParse(key.toString());
        if (uid == null) continue;
        if (uid == accountId) {
          sawSelfParticipant = true;
        } else {
          peerId = uid;
          break;
        }
      }
      if (peerId == null) {
        final owner = (map['owner'] as num?)?.toInt();
        if (owner != null && owner != accountId) {
          peerId = owner;
        } else if (sawSelfParticipant && accountId != 0) {
          peerId = accountId;
          if (title.isEmpty) title = 'Избранное';
          avatarUrl ??= store.profile?.avatarUrl;
        }
      }
      if (peerId != null && peerId != accountId) {
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
          lastSeen = normalizeEpochMs((pres['seen'] as num?)?.toInt()) ?? lastSeen;
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
    int? peerReadMark = existing?.peerReadMark;
    if (participants is Map) {
      for (final entry in participants.entries) {
        final uid = int.tryParse(entry.key.toString());
        final mark = (entry.value as num?)?.toInt();
        if (uid != null && uid != accountId && mark != null && mark > 0) {
          if (peerReadMark == null || mark > peerReadMark) {
            peerReadMark = mark;
          }
        }
      }
    }

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
      peerReadMark: peerReadMark,
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
    if (_isDemoMode || !isSessionReady) {
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
    _chatHasMore[chatId] = rawMsgs.length >= count;

    if (parsed.isNotEmpty) {
      await _reconcileDeletedFromFetch(chatId, parsed);
    }

    final serverChat = data?['chat'];
    if (serverChat is Map) {
      final accountId = currentUser?.id ?? store.accountId ?? 0;
      final parsedChat = _parseServerChat(serverChat, accountId: accountId);
      if (parsedChat != null) {
        await store.saveChats([parsedChat]);
      }
    }

    notifyListeners();
    return store.getMessages(chatId);
  }

  /// Догружает более старые сообщения при прокрутке ленты вверх.
  Future<int> loadMoreHistory(int chatId, {int count = 50}) async {
    if (_isDemoMode || !isSessionReady) return 0;
    if (!canLoadMoreHistory(chatId) || _loadingMoreChats.contains(chatId)) {
      return 0;
    }
    final existing = store.getMessages(chatId);
    if (existing.isEmpty) return 0;

    _loadingMoreChats.add(chatId);
    try {
      final oldestTime = existing.first.time;
      final packet = await session.request(Opcode.chatHistory, {
        'chatId': chatId,
        'from': oldestTime > 0 ? oldestTime - 1 : 0,
        'forward': 0,
        'backward': count,
        'getMessages': true,
      });
      final data = packet.payloadAsMap;
      final rawMsgs = data?['messages'];
      if (rawMsgs is! List || rawMsgs.isEmpty) {
        _chatHasMore[chatId] = false;
        return 0;
      }

      final beforeCount = store.getMessages(chatId).length;
      final parsed = <TalerMessage>[];
      for (final m in rawMsgs.whereType<Map>()) {
        final msg = _parseServerMessage(m, chatId);
        if (msg != null) parsed.add(msg);
      }

      if (parsed.isNotEmpty) {
        await store.saveMessagesBatch(chatId, parsed);
        await _reconcileDeletedFromFetch(chatId, parsed);
      }
      _chatHasMore[chatId] = rawMsgs.length >= count;
      final added = store.getMessages(chatId).length - beforeCount;
      notifyListeners();
      return added;
    } catch (_) {
      return 0;
    } finally {
      _loadingMoreChats.remove(chatId);
    }
  }

  Future<void> _reconcileDeletedFromFetch(
    int chatId,
    List<TalerMessage> serverMessages,
  ) async {
    if (serverMessages.isEmpty) return;
    final serverIds = <String>{};
    var minTime = serverMessages.first.time;
    var maxTime = serverMessages.first.time;
    for (final m in serverMessages) {
      serverIds.add(m.id);
      if (m.time < minTime) minTime = m.time;
      if (m.time > maxTime) maxTime = m.time;
    }

    final cached = store.getMessages(chatId);
    final missing = <String>[];
    for (final m in cached) {
      if (m.id.startsWith('temp_')) continue;
      if (m.status == 'sending' || m.status == 'pending' || m.status == 'error') {
        continue;
      }
      if (m.deletedByPeer) continue;
      if (m.time < minTime || m.time > maxTime) continue;
      if (!serverIds.contains(m.id)) {
        missing.add(m.id);
      }
    }

    if (missing.isNotEmpty) {
      await _applyDeletedMessages(chatId, missing, recordAudit: true);
    }
  }

  TalerMessage? _parseServerMessage(
    Map<dynamic, dynamic> m,
    int chatId, {
    int? fallbackSenderId,
    int? fallbackCid,
  }) {
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
        var replyText = linkedMsg['text']?.toString();
        if ((replyText == null || replyText.isEmpty) &&
            linkedMsg['attaches'] is List &&
            (linkedMsg['attaches'] as List).isNotEmpty) {
          replyText = '[Вложение]';
        }
        replyTo = TalerReplyPreview(
          messageId: linkedMsg['id']?.toString(),
          senderId: sender,
          senderName: senderDisplayName(sender, chatId: chatId),
          text: replyText,
        );
      } else if (lType == 'REPLY' && link['messageId'] != null) {
        final targetId = link['messageId'].toString();
        final cached = store
            .getMessages(chatId)
            .where((item) => item.id == targetId)
            .firstOrNull;
        if (cached != null) {
          replyTo = TalerReplyPreview(
            messageId: cached.id,
            senderId: cached.senderId,
            senderName: senderDisplayName(cached.senderId, chatId: chatId),
            text: cached.text.isNotEmpty ? cached.text : '[Вложение]',
          );
        }
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

    final rawStatus = m['status']?.toString().toUpperCase();
    final isRemoved = rawStatus == 'REMOVED';
    final rawSender = (m['sender'] as num?)?.toInt();
    final senderId =
        (rawSender != null && rawSender != 0) ? rawSender : (fallbackSenderId ?? 0);
    final cid = (m['cid'] as num?)?.toInt() ?? fallbackCid;

    return TalerMessage(
      id: id,
      chatId: chatId,
      senderId: senderId,
      text: m['text']?.toString() ?? '',
      time: (m['time'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      status: rawStatus?.toLowerCase() ?? 'sent',
      deletedByPeer: isRemoved,
      deletedAt: isRemoved ? DateTime.now().millisecondsSinceEpoch : null,
      replyTo: replyTo,
      attachments: attaches,
      reactions: reactions,
      isControl: isControl,
      forwardedFromName: forwardedFrom,
      cid: cid,
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

    if (!_isDemoMode && isSessionReady && msgIdNum != null) {
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

    if (!_isDemoMode && isSessionReady) {
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

  /// Очищает историю сообщений чата (`Opcode.chatClear = 54`).
  Future<void> clearChatHistory(int chatId, {bool forAll = false}) async {
    final chat = store.chats[chatId];
    final msgs = store.getMessages(chatId);
    final lastEventTime = chat?.lastMessageTime ??
        (msgs.isNotEmpty ? msgs.last.time : DateTime.now().millisecondsSinceEpoch);

    await store.clearChatMessages(chatId);
    if (chat != null) {
      await store.saveChats([
        chat.copyWith(
          lastMessageText: '',
          unreadCount: 0,
        ),
      ]);
    }
    _chatHasMore[chatId] = false;
    notifyListeners();

    if (!_isDemoMode) {
      await ensureReady();
      await session.request(
        Opcode.chatClear,
        {
          'chatId': chatId,
          'lastEventTime': lastEventTime,
          'forAll': forAll,
        },
        throwOnError: false,
      );
    }
  }

  /// Удаляет диалог (`Opcode.chatDelete = 52`) или покидает группу/канал (`Opcode.chatLeave = 58`).
  Future<void> deleteOrLeaveChat(TalerChat chat, {bool forAll = false}) async {
    final chatId = chat.id;
    final lastEventTime =
        chat.lastMessageTime ?? DateTime.now().millisecondsSinceEpoch;
    if (_activeChatId == chatId) {
      _activeChatId = null;
    }
    await store.removeChat(chatId);
    _chatHasMore.remove(chatId);
    notifyListeners();

    if (!_isDemoMode) {
      await ensureReady();
      if (chat.isGroup || chat.isChannel) {
        await session.request(
          Opcode.chatLeave,
          {'chatId': chatId},
          throwOnError: false,
        );
      } else {
        await session.request(
          Opcode.chatDelete,
          {
            'chatId': chatId,
            'lastEventTime': lastEventTime,
            'forAll': forAll,
          },
          throwOnError: false,
        );
      }
    }
  }

  /// Отправка индикатора набора текста. При включённом `hideTyping`
  /// пакет блокируется в [PrivacyFirewall].
  Future<void> sendTyping(int chatId) async {
    if (_isDemoMode || !isSessionReady) return;
    await session.request(
      Opcode.msgTyping,
      {'chatId': chatId, 'type': 'TEXT'},
      throwOnError: false,
    );
  }

  Future<TalerPacket> _sendWithNotReadyRetry(
    Map<String, dynamic> payload, {
    int maxAttempts = 4,
    Duration retryDelay = const Duration(milliseconds: 600),
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await session.request(Opcode.msgSend, payload);
      } on TalerPacketException catch (e) {
        final code = (e.code ?? '').toLowerCase();
        final msg = e.message.toLowerCase();
        final isNotReady = code.contains('not.ready') || msg.contains('not.ready');
        if (!isNotReady || attempt == maxAttempts - 1) {
          rethrow;
        }
        await Future<void>.delayed(retryDelay);
      }
    }
    throw const TalerPacketException('Превышено число попыток отправки');
  }

  /// Отправляет текстовое сообщение (`Opcode.msgSend`).
  Future<void> sendMessage(
    int chatId,
    String text, {
    TalerMessage? replyTo,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await store.saveDraft(chatId, null);
    _draftSyncTimers[chatId]?.cancel();
    _draftSyncTimers.remove(chatId);

    final cid = _nextCid();
    final now = -cid;
    final tempId = 'temp_$now';
    final myId = currentUser?.id ?? 1;

    final optimistic = TalerMessage(
      id: tempId,
      chatId: chatId,
      senderId: myId,
      text: trimmed,
      time: now,
      status: _isDemoMode ? 'sent' : 'sending',
      cid: cid,
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
      'cid': cid,
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

    try {
      await ensureReady();
      final packet = await _sendWithNotReadyRetry({
        'chatId': chatId,
        'message': messageMap,
        'notify': true,
      });
      final data = packet.payloadAsMap;
      final msgObj = data?['message'];
      final TalerMessage confirmed;
      if (msgObj is Map) {
        confirmed = _parseServerMessage(
              msgObj,
              chatId,
              fallbackSenderId: myId,
              fallbackCid: cid,
            ) ??
            optimistic.copyWith(
              id: msgObj['id']?.toString() ?? tempId,
              status: 'sent',
            );
      } else {
        confirmed = optimistic.copyWith(status: 'sent');
      }
      await store.replaceTempMessage(chatId, tempId, confirmed);
      _sendErrors.remove(tempId);
      final curChat = store.chats[chatId];
      if (curChat != null) {
        await store.saveChats([
          curChat.copyWith(
            lastMessageText: trimmed,
            lastMessageTime: confirmed.time,
            lastMessageSenderId: confirmed.senderId,
            lastMessageDeletedByPeer: false,
          ),
        ]);
      }
      notifyListeners();
    } catch (e) {
      final existing = store.getMessages(chatId);
      final stillTemp = existing.where((m) => m.id == tempId).firstOrNull;
      if (stillTemp != null) {
        await store.upsertMessage(
          stillTemp.copyWith(status: 'error'),
          trackEditHistory: false,
        );
        _sendErrors[tempId] = e.toString();
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Повторная отправка неудачного сообщения (`status == 'error'`).
  Future<void> retrySendMessage(int chatId, String messageId) async {
    final msgs = store.getMessages(chatId);
    final failed = msgs.where((m) => m.id == messageId).firstOrNull;
    if (failed == null) return;
    if (failed.text.trim().isEmpty) return;

    TalerMessage? replyTarget;
    final replyId = failed.replyTo?.messageId;
    if (replyId != null) {
      replyTarget = msgs.where((m) => m.id == replyId).firstOrNull;
    }

    await store.removeMessage(chatId, messageId);
    _sendErrors.remove(messageId);
    notifyListeners();

    await sendMessage(chatId, failed.text, replyTo: replyTarget);
  }

  http.Client _createMediaHttpClient() {
    final io = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) =>
              TalerMediaCache.isTrustedMaxMediaHost(host);
    return IOClient(io);
  }

  /// Загрузка бинарного потока на CDN MAX (`Content-Range` + `application/octet-stream`)
  /// с поддержкой сертификатов Минцифры для `*.oneme.ru`.
  Future<String> _uploadBinaryToMax(
    String uploadUrl,
    Uint8List bytes, {
    required String fileName,
  }) async {
    final uri = Uri.parse(uploadUrl);
    if (PrivacyFirewall.isTrackingUrl(uri)) {
      throw const TalerPacketException('URL заблокирован Taler Privacy Shield');
    }
    final client = _createMediaHttpClient();
    try {
      final safeName = Uri.encodeComponent(fileName);
      final req = http.Request('POST', uri)
        ..headers['User-Agent'] = session.effectiveProfile.userAgent
        ..headers['Content-Type'] = 'application/octet-stream'
        ..headers['Content-Disposition'] = 'attachment; filename=$safeName'
        ..headers['Content-Range'] = 'bytes 0-${bytes.length - 1}/${bytes.length}'
        ..headers['Connection'] = 'close'
        ..bodyBytes = bytes;
      final streamed = await client.send(req).timeout(const Duration(minutes: 2));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw TalerPacketException(
          'Ошибка HTTP при загрузке медиа (${streamed.statusCode})',
        );
      }
      if (body.contains('"error_code"') || body.contains('"error_msg"')) {
        throw TalerPacketException('Сервер отклонил загрузку медиа: $body');
      }
      return body;
    } finally {
      client.close();
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
    final cid = _nextCid();
    final now = -cid;
    final tempId = 'temp_$now';
    final myId = currentUser?.id ?? 1;
    final previewLabel = isImage ? '📷 Фото: $fileName' : '📎 $fileName';

    final optimistic = TalerMessage(
      id: tempId,
      chatId: chatId,
      senderId: myId,
      text: caption?.trim() ?? '',
      time: now,
      status: _isDemoMode ? 'sent' : 'sending',
      cid: cid,
      attachments: [
        TalerAttachment(
          type: isImage ? 'PHOTO' : 'FILE',
          url: filePath,
          fileName: fileName,
          fileSize: bytes.length,
        ),
      ],
    );
    await store.upsertMessage(optimistic);
    final chat = store.chats[chatId];
    if (chat != null) {
      await store.saveChats([
        chat.copyWith(
          lastMessageText: previewLabel,
          lastMessageTime: now,
          lastMessageSenderId: myId,
          lastMessageDeletedByPeer: false,
        ),
      ]);
    }
    notifyListeners();

    if (_isDemoMode) return;

    try {
      await ensureReady();

      final Map<String, dynamic> sendPayload;
      if (isImage) {
        final urlResp = await session.request(Opcode.photoUpload, {'count': 1});
        final uploadUrl = urlResp.payloadAsMap?['url'] as String?;
        if (uploadUrl == null || uploadUrl.isEmpty) {
          throw const TalerPacketException('Не получен URL для загрузки фото');
        }
        final httpClient = _createMediaHttpClient();
        final String body;
        final int statusCode;
        try {
          final req = http.MultipartRequest('POST', Uri.parse(uploadUrl))
            ..headers['User-Agent'] = session.effectiveProfile.userAgent
            ..files.add(
              http.MultipartFile.fromBytes('file', bytes, filename: fileName),
            );
          final streamed = await httpClient.send(req);
          statusCode = streamed.statusCode;
          body = await streamed.stream.bytesToString();
        } finally {
          httpClient.close();
        }
        if (statusCode < 200 || statusCode >= 300) {
          throw TalerPacketException(
            'Ошибка HTTP при загрузке фото ($statusCode)',
          );
        }
        final tokenMatch = RegExp(r'"token"\s*:\s*"([^"]+)"').firstMatch(body);
        final photoToken = tokenMatch?.group(1);
        if (photoToken == null || photoToken.isEmpty) {
          throw const TalerPacketException('Сервер не вернул photoToken');
        }

        sendPayload = {
          'chatId': chatId,
          'message': {
            'cid': cid,
            if (caption != null && caption.trim().isNotEmpty)
              'text': caption.trim(),
            'attaches': [
              {'_type': 'PHOTO', 'photoToken': photoToken},
            ],
          },
          'notify': true,
        };
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
        await _uploadBinaryToMax(uploadUrl, bytes, fileName: fileName);

        sendPayload = {
          'chatId': chatId,
          'message': {
            'cid': cid,
            'elements': const <dynamic>[],
            'attaches': [
              {
                '_type': 'FILE',
                'token': fileToken,
                'fileId': ?fileId,
              },
            ],
          },
          'notify': true,
        };
      }

      final sendResp = await _sendWithNotReadyRetry(
        sendPayload,
        maxAttempts: 15,
        retryDelay: const Duration(seconds: 1),
      );
      final msgMap = sendResp.payloadAsMap?['message'];
      final confirmed = msgMap is Map
          ? (_parseServerMessage(
                msgMap,
                chatId,
                fallbackSenderId: myId,
                fallbackCid: cid,
              ) ??
              optimistic.copyWith(status: 'sent'))
          : optimistic.copyWith(status: 'sent');
      await store.replaceTempMessage(chatId, tempId, confirmed);
      _sendErrors.remove(tempId);
      notifyListeners();
    } catch (e) {
      final existing = store.getMessages(chatId);
      final stillTemp = existing.where((m) => m.id == tempId).firstOrNull;
      if (stillTemp != null) {
        await store.upsertMessage(
          stillTemp.copyWith(status: 'error'),
          trackEditHistory: false,
        );
        _sendErrors[tempId] = e.toString();
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Загрузка и отправка видео (`Opcode.videoUpload = 82`).
  Future<void> sendVideoAttachment(
    int chatId, {
    required String filePath,
    required String fileName,
    String? caption,
    int? durationMs,
  }) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final cid = _nextCid();
    final now = -cid;
    final tempId = 'temp_$now';
    final myId = currentUser?.id ?? 1;

    await store.saveDraft(chatId, null);
    final optimistic = TalerMessage(
      id: tempId,
      chatId: chatId,
      senderId: myId,
      text: caption?.trim() ?? '',
      time: now,
      status: _isDemoMode ? 'sent' : 'sending',
      cid: cid,
      attachments: [
        TalerAttachment(
          type: 'VIDEO',
          url: filePath,
          fileName: fileName,
          fileSize: bytes.length,
          durationMs: durationMs,
        ),
      ],
    );
    await store.upsertMessage(optimistic);
    final chat = store.chats[chatId];
    if (chat != null) {
      await store.saveChats([
        chat.copyWith(
          lastMessageText: '🎬 Видео: $fileName',
          lastMessageTime: now,
          lastMessageSenderId: myId,
          lastMessageDeletedByPeer: false,
        ),
      ]);
    }
    notifyListeners();

    if (_isDemoMode) return;

    try {
      await ensureReady();
      final urlResp = await session.request(Opcode.videoUpload, {'count': 1});
      final infoList = urlResp.payloadAsMap?['info'] as List?;
      final first =
          infoList != null && infoList.isNotEmpty && infoList.first is Map
              ? infoList.first as Map
              : urlResp.payloadAsMap;
      final uploadUrl = first?['url'] as String?;
      final videoToken = first?['token'] as String?;
      final videoId = (first?['videoId'] as num?)?.toInt();
      if (uploadUrl == null || uploadUrl.isEmpty) {
        throw const TalerPacketException('Не получен URL для загрузки видео');
      }

      await _uploadBinaryToMax(uploadUrl, bytes, fileName: fileName);

      final sendPayload = {
        'chatId': chatId,
        'message': {
          'cid': cid,
          if (caption != null && caption.trim().isNotEmpty)
            'text': caption.trim(),
          'elements': const <dynamic>[],
          'attaches': [
            {
              '_type': 'VIDEO',
              'videoId': ?videoId,
              'token': ?videoToken,
            },
          ],
        },
        'notify': true,
      };

      final sendResp = await _sendWithNotReadyRetry(
        sendPayload,
        maxAttempts: 20,
        retryDelay: const Duration(seconds: 1),
      );
      final msgMap = sendResp.payloadAsMap?['message'];
      final confirmed = msgMap is Map
          ? (_parseServerMessage(
                msgMap,
                chatId,
                fallbackSenderId: myId,
                fallbackCid: cid,
              ) ??
              optimistic.copyWith(status: 'sent'))
          : optimistic.copyWith(status: 'sent');
      await store.replaceTempMessage(chatId, tempId, confirmed);
      _sendErrors.remove(tempId);
      notifyListeners();
    } catch (e) {
      final existing = store.getMessages(chatId);
      final stillTemp = existing.where((m) => m.id == tempId).firstOrNull;
      if (stillTemp != null) {
        await store.upsertMessage(
          stillTemp.copyWith(status: 'error'),
          trackEditHistory: false,
        );
        _sendErrors[tempId] = e.toString();
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Формирует 80-байтный массив амплитуд `wave` для протокола MAX (0..127).
  static Uint8List buildMaxWaveformBytes(List<double> samples) {
    const targetLen = 80;
    final out = Uint8List(targetLen);
    if (samples.isEmpty) {
      for (var i = 0; i < targetLen; i++) {
        out[i] = 16;
      }
      return out;
    }
    for (var i = 0; i < targetLen; i++) {
      final pos = (i / (targetLen - 1)) * (samples.length - 1);
      final lo = pos.floor().clamp(0, samples.length - 1);
      final hi = pos.ceil().clamp(0, samples.length - 1);
      final frac = pos - lo;
      final v = samples[lo] * (1.0 - frac) + samples[hi] * frac;
      out[i] = (v.clamp(0.0, 1.0) * 127).round().clamp(4, 127);
    }
    return out;
  }

  /// Загрузка и отправка голосового сообщения по протоколу MAX:
  /// `Opcode.videoUpload (82)` с `type: 2, uploaderType: 1` → бинарный POST → `AUDIO` attach с `wave`.
  Future<void> sendVoiceAttachment(
    int chatId, {
    required String filePath,
    required int durationMs,
    List<double> waveformSamples = const [],
  }) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final ext = filePath.toLowerCase().endsWith('.m4a') ? 'm4a' : 'ogg';
    final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final waveBytes = buildMaxWaveformBytes(waveformSamples);
    final cid = _nextCid();
    final now = -cid;
    final tempId = 'temp_$now';
    final myId = currentUser?.id ?? 1;

    final optimistic = TalerMessage(
      id: tempId,
      chatId: chatId,
      senderId: myId,
      text: '',
      time: now,
      status: _isDemoMode ? 'sent' : 'sending',
      cid: cid,
      attachments: [
        TalerAttachment(
          type: 'AUDIO',
          url: filePath,
          fileName: fileName,
          fileSize: bytes.length,
          durationMs: durationMs,
          waveform: List<int>.from(waveBytes),
        ),
      ],
    );
    await store.upsertMessage(optimistic);
    final chat = store.chats[chatId];
    if (chat != null) {
      await store.saveChats([
        chat.copyWith(
          lastMessageText: '🎤 Голосовое сообщение',
          lastMessageTime: now,
          lastMessageSenderId: myId,
          lastMessageDeletedByPeer: false,
        ),
      ]);
    }
    notifyListeners();

    if (_isDemoMode) return;

    try {
      await ensureReady();
      final uploadResp = await session.request(Opcode.videoUpload, {
        'count': 1,
        'type': 2,
        'uploaderType': 1,
      });

      final infoList = uploadResp.payloadAsMap?['info'] as List?;
      final first =
          infoList != null && infoList.isNotEmpty && infoList.first is Map
              ? infoList.first as Map
              : uploadResp.payloadAsMap;
      final uploadUrl = first?['url'] as String?;
      final token = first?['token'] as String?;
      final audioId = ((first?['videoId'] ?? first?['audioId']) as num?)?.toInt();
      if (uploadUrl == null || uploadUrl.isEmpty) {
        throw const TalerPacketException('Не получен URL для загрузки голосового');
      }

      final respBody = await _uploadBinaryToMax(
        uploadUrl,
        bytes,
        fileName: fileName,
      );
      final bodyToken = RegExp(r'"token"\s*:\s*"([^"]+)"')
          .firstMatch(respBody)
          ?.group(1);
      final resolvedToken =
          (token != null && token.isNotEmpty) ? token : bodyToken;

      final attachMap = <String, dynamic>{
        '_type': 'AUDIO',
        'duration': durationMs,
        'wave': waveBytes,
      };
      if (resolvedToken != null && resolvedToken.isNotEmpty) {
        attachMap['token'] = resolvedToken;
      } else if (audioId != null) {
        attachMap['audioId'] = audioId;
      }

      final sendPayload = {
        'chatId': chatId,
        'message': {
          'cid': cid,
          'isLive': false,
          'detectShare': false,
          'elements': const <dynamic>[],
          'attaches': [attachMap],
        },
        'notify': true,
      };

      final sendResp = await _sendWithNotReadyRetry(
        sendPayload,
        maxAttempts: 25,
        retryDelay: const Duration(seconds: 1),
      );
      final msgMap = sendResp.payloadAsMap?['message'];
      final confirmed = msgMap is Map
          ? (_parseServerMessage(
                msgMap,
                chatId,
                fallbackSenderId: myId,
                fallbackCid: cid,
              ) ??
              optimistic.copyWith(status: 'sent'))
          : optimistic.copyWith(status: 'sent');
      await store.replaceTempMessage(chatId, tempId, confirmed);
      _sendErrors.remove(tempId);
      notifyListeners();
    } catch (e) {
      final existing = store.getMessages(chatId);
      final stillTemp = existing.where((m) => m.id == tempId).firstOrNull;
      if (stillTemp != null) {
        await store.upsertMessage(
          stillTemp.copyWith(status: 'error'),
          trackEditHistory: false,
        );
        _sendErrors[tempId] = e.toString();
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Скачивает и открывает файл-вложение через `Opcode.fileDownload = 88`.
  Future<File?> downloadAndOpenFile(
    int chatId,
    TalerMessage message,
    TalerAttachment attach,
  ) async {
    final key = attachmentKey(message.id, attach);
    final cachedPath = _downloadedPaths[key];
    if (cachedPath != null && File(cachedPath).existsSync()) {
      await TalerNativeBridge.instance.openFile(cachedPath);
      return File(cachedPath);
    }

    final localUrl = attach.url;
    if (localUrl != null &&
        localUrl.isNotEmpty &&
        !localUrl.startsWith('http://') &&
        !localUrl.startsWith('https://')) {
      final localFile = File(localUrl);
      if (localFile.existsSync()) {
        _downloadedPaths[key] = localFile.path;
        await TalerNativeBridge.instance.openFile(localFile.path);
        return localFile;
      }
    }

    _downloadProgress[key] = 0.05;
    notifyListeners();
    try {
      String? downloadUrl = (localUrl != null &&
              (localUrl.startsWith('http://') ||
                  localUrl.startsWith('https://')))
          ? localUrl
          : null;

      if (downloadUrl == null && !_isDemoMode) {
        await ensureReady();
        final mid = int.tryParse(message.id);
        final payload = <String, dynamic>{
          'chatId': chatId,
          'messageId': ?mid,
          'fileId': ?attach.fileId,
          'token': ?attach.token,
        };
        final resp = await session.request(Opcode.fileDownload, payload);
        final map = resp.payloadAsMap;
        downloadUrl =
            (map?['url'] ?? map?['fileUrl'] ?? map?['downloadUrl'])?.toString();
      }

      if (downloadUrl == null || downloadUrl.isEmpty) {
        return null;
      }

      final fileName = attach.fileName ?? attach.previewText ?? 'document.bin';
      final file = await TalerMediaCache.instance.downloadNamedFile(
        downloadUrl,
        fileName: fileName,
        subDir: 'files',
        userAgent: session.effectiveProfile.userAgent,
        onProgress: (p) {
          _downloadProgress[key] = p;
          notifyListeners();
        },
      );
      if (file != null) {
        _downloadedPaths[key] = file.path;
        notifyListeners();
        await TalerNativeBridge.instance.openFile(file.path);
      }
      return file;
    } finally {
      _downloadProgress.remove(key);
      notifyListeners();
    }
  }

  /// Получает прямую ссылку на видеопоток через `Opcode.videoPlay = 83`.
  Future<String?> resolveVideoPlayUrl(
    int chatId,
    TalerMessage message,
    TalerAttachment attach,
  ) async {
    final direct = attach.url;
    if (direct != null &&
        direct.isNotEmpty &&
        !direct.startsWith('http://') &&
        !direct.startsWith('https://') &&
        await File(direct).exists()) {
      return direct;
    }

    if (!_isDemoMode) {
      try {
        await ensureReady();
        final mid = int.tryParse(message.id);
        final vid = attach.videoId ?? attach.fileId;
        if (vid != null || attach.token != null) {
          final resp = await session.request(
            Opcode.videoPlay,
            {
              'chatId': chatId,
              'messageId': ?mid,
              'videoId': ?vid,
              'token': ?attach.token,
            },
            throwOnError: false,
          );
          final map = resp.payloadAsMap;
          if (map != null) {
            const preferredKeys = [
              'MP4_1080',
              'MP4_720',
              'MP4_480',
              'MP4_360',
              'MP4_240',
              'MP4_144',
              'HLS',
              'url',
              'videoUrl',
              'EXTERNAL',
            ];
            for (final k in preferredKeys) {
              final val = map[k]?.toString();
              if (val != null && val.startsWith('http')) {
                return val;
              }
            }
            for (final entry in map.entries) {
              final val = entry.value?.toString();
              if (val != null && val.startsWith('http')) {
                return val;
              }
            }
          }
        }
      } catch (_) {}
    }

    if (direct != null &&
        (direct.startsWith('http://') || direct.startsWith('https://'))) {
      return direct;
    }
    return null;
  }

  static String _audioExtensionFor(TalerAttachment attach, String remoteUrl) {
    final candidates = <String?>[
      attach.fileName,
      Uri.tryParse(remoteUrl)?.path,
    ];
    for (final raw in candidates) {
      if (raw == null || raw.isEmpty) continue;
      final lower = raw.toLowerCase();
      for (final ext in const ['.ogg', '.opus', '.m4a', '.mp3', '.aac', '.wav', '.mp4']) {
        if (lower.endsWith(ext)) return ext.substring(1);
      }
    }
    // Голосовые MAX по умолчанию приходят в контейнере OGG/Opus.
    return 'ogg';
  }

  /// Получает локальный файл или поток аудио/ГС через `Opcode.audioPlay = 301`.
  Future<String?> resolveAudioPlaySource(
    int chatId,
    TalerMessage message,
    TalerAttachment attach,
  ) async {
    final direct = attach.url;
    if (direct != null &&
        direct.isNotEmpty &&
        !direct.startsWith('http://') &&
        !direct.startsWith('https://') &&
        File(direct).existsSync()) {
      return direct;
    }

    String? remoteUrl = (direct != null &&
            (direct.startsWith('http://') || direct.startsWith('https://')))
        ? direct
        : null;

    if (remoteUrl == null && !_isDemoMode) {
      try {
        await ensureReady();
        final mid = int.tryParse(message.id);
        final aid = attach.audioId ?? attach.fileId;
        final resp = await session.request(
          Opcode.audioPlay,
          {
            'chatId': chatId,
            'messageId': ?mid,
            'audioId': ?aid,
            'token': ?attach.token,
          },
          throwOnError: false,
        );
        final map = resp.payloadAsMap;
        remoteUrl =
            (map?['url'] ?? map?['audioUrl'] ?? map?['OGG'] ?? map?['MP3'])
                ?.toString();
        if ((remoteUrl == null || !remoteUrl.startsWith('http')) && map != null) {
          for (final v in map.values) {
            final s = v?.toString();
            if (s != null && s.startsWith('http')) {
              remoteUrl = s;
              break;
            }
          }
        }
      } catch (_) {}
    }

    if (remoteUrl == null || remoteUrl.isEmpty) return null;
    final ext = _audioExtensionFor(attach, remoteUrl);
    final fileName = (attach.fileName != null && attach.fileName!.contains('.'))
        ? attach.fileName!
        : 'audio_${attach.audioId ?? message.id}.$ext';
    final cached = await TalerMediaCache.instance.downloadNamedFile(
      remoteUrl,
      fileName: fileName,
      subDir: 'audio',
      userAgent: session.effectiveProfile.userAgent,
    );
    return cached?.path ?? remoteUrl;
  }

  /// Пересылает одно или несколько сообщений в другой чат (`Opcode.msgSend` с `FORWARD`).
  Future<void> forwardMessages({
    required int fromChatId,
    required int toChatId,
    required List<TalerMessage> messages,
  }) async {
    if (messages.isEmpty) return;
    final sorted = List<TalerMessage>.from(messages)
      ..sort((a, b) => a.time.compareTo(b.time));
    final myId = currentUser?.id ?? 1;

    for (final src in sorted) {
      final cid = _nextCid();
      final now = -cid;
      final tempId = 'temp_$now';
      final fromName = senderDisplayName(src.senderId, chatId: fromChatId);
      final optimistic = TalerMessage(
        id: tempId,
        chatId: toChatId,
        senderId: myId,
        text: src.text,
        time: now,
        status: _isDemoMode ? 'sent' : 'sending',
        cid: cid,
        attachments: src.attachments,
        forwardedFromName: fromName,
      );
      await store.upsertMessage(optimistic);
      final targetChat = store.chats[toChatId];
      if (targetChat != null) {
        final preview = src.text.trim().isNotEmpty ? src.text.trim() : '[Вложение]';
        await store.saveChats([
          targetChat.copyWith(
            lastMessageText: preview,
            lastMessageTime: now,
            lastMessageSenderId: myId,
            lastMessageDeletedByPeer: false,
          ),
        ]);
      }
      notifyListeners();

      if (_isDemoMode) continue;

      try {
        await ensureReady();
        final srcMid = int.tryParse(src.id);
        final msgPayload = <String, dynamic>{
          'cid': cid,
          'text': srcMid != null ? '' : src.text,
          'elements': const <dynamic>[],
          'attaches': const <dynamic>[],
          if (srcMid != null)
            'link': {
              'type': 'FORWARD',
              'chatId': fromChatId,
              'messageId': srcMid,
            },
        };
        final resp = await _sendWithNotReadyRetry({
          'chatId': toChatId,
          'message': msgPayload,
          'notify': true,
        });
        final msgObj = resp.payloadAsMap?['message'];
        final confirmed = msgObj is Map
            ? (_parseServerMessage(
                  msgObj,
                  toChatId,
                  fallbackSenderId: myId,
                  fallbackCid: cid,
                ) ??
                optimistic.copyWith(status: 'sent'))
            : optimistic.copyWith(status: 'sent');
        await store.replaceTempMessage(toChatId, tempId, confirmed);
        notifyListeners();
      } catch (e) {
        await store.upsertMessage(
          optimistic.copyWith(status: 'error'),
          trackEditHistory: false,
        );
        _sendErrors[tempId] = e.toString();
        notifyListeners();
      }
    }
  }

  /// Удаляет несколько сообщений одним запросом (`Opcode.msgDelete`).
  Future<void> deleteMessagesBatch(
    int chatId,
    List<String> messageIds, {
    bool forEveryone = false,
  }) async {
    if (messageIds.isEmpty) return;
    final unique = messageIds.toSet().toList();
    final numericIds = <int>[];
    for (final id in unique) {
      await store.removeMessage(chatId, id);
      _sendErrors.remove(id);
      final parsed = int.tryParse(id);
      if (parsed != null) numericIds.add(parsed);
    }
    notifyListeners();

    if (!_isDemoMode && numericIds.isNotEmpty) {
      await ensureReady();
      await session.request(Opcode.msgDelete, {
        'messageIds': numericIds,
        'chatId': chatId,
        'forMe': !forEveryone,
        'itemType': 'REGULAR',
      });
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
    final previous = idx >= 0 ? list[idx] : null;
    if (previous != null) {
      await store.upsertMessage(previous.copyWith(text: trimmed));
      notifyListeners();
    }

    if (!_isDemoMode) {
      final mid = int.tryParse(messageId);
      if (mid != null) {
        try {
          await ensureReady();
          await session.request(Opcode.msgEdit, {
            'messageId': mid,
            'chatId': chatId,
            'elements': const <dynamic>[],
            'text': trimmed,
          });
        } catch (_) {
          if (previous != null) {
            await store.upsertMessage(previous, trackEditHistory: false);
            notifyListeners();
          }
          rethrow;
        }
      }
    }
  }

  /// Удаление сообщения (`Opcode.msgDelete`).
  Future<void> deleteMessage(
    int chatId,
    String messageId, {
    bool forEveryone = false,
  }) async {
    final prevList = store.getMessages(chatId);
    final previous = prevList.where((m) => m.id == messageId).firstOrNull;

    await store.removeMessage(chatId, messageId);
    _sendErrors.remove(messageId);
    notifyListeners();

    if (!_isDemoMode) {
      final mid = int.tryParse(messageId);
      if (mid != null) {
        try {
          await ensureReady();
          await session.request(Opcode.msgDelete, {
            'messageIds': [mid],
            'chatId': chatId,
            'forMe': !forEveryone,
            'itemType': 'REGULAR',
          });
        } catch (_) {
          if (previous != null) {
            await store.upsertMessage(previous, trackEditHistory: false);
            notifyListeners();
          }
          rethrow;
        }
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

    if (!_isDemoMode) {
      final mid = int.tryParse(messageId);
      if (mid != null) {
        try {
          await ensureReady();
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
        } catch (_) {
          await store.upsertMessage(target, trackEditHistory: false);
          notifyListeners();
          rethrow;
        }
      }
    }
  }

  /// Обновляет имя, фамилию и описание («О себе») в профиле (`Opcode.profile`).
  Future<void> updateProfile({
    required String firstName,
    String? lastName,
    String? description,
  }) async {
    final current = store.profile;
    if (current == null) return;
    final trimmedFirst = firstName.trim();
    final trimmedLast = lastName?.trim();
    final trimmedDesc = description?.trim();
    if (trimmedFirst.isEmpty) return;

    await store.saveProfile(
      current.copyWith(
        firstName: trimmedFirst,
        lastName: (trimmedLast == null || trimmedLast.isEmpty) ? null : trimmedLast,
        clearLastName: trimmedLast == null || trimmedLast.isEmpty,
        description: description == null
            ? current.description
            : (trimmedDesc == null || trimmedDesc.isEmpty ? null : trimmedDesc),
        clearDescription: description != null && (trimmedDesc == null || trimmedDesc.isEmpty),
      ),
    );
    notifyListeners();

    if (!_isDemoMode && isSessionReady) {
      final payload = <String, dynamic>{
        'firstName': trimmedFirst,
        'lastName': trimmedLast ?? '',
        if (description != null) 'description': trimmedDesc ?? '',
      };
      final packet = await session.request(Opcode.profile, payload);
      final serverProfile = packet.payloadAsMap?['profile'];
      if (serverProfile is Map) {
        final updated = TalerUserProfile.fromServerProfile(serverProfile);
        if (updated.id != 0) {
          await store.saveProfile(updated);
          notifyListeners();
        }
      }
    }
  }

  /// Обновляет имя и фамилию в профиле (`Opcode.profile`).
  Future<void> updateProfileName(String firstName, String? lastName) =>
      updateProfile(firstName: firstName, lastName: lastName);

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

    if (!isSessionReady) return;
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
    if (!isSessionReady) return;
    await session.request(Opcode.sessionsClose, {});
    await fetchActiveSessions();
  }

  /// Очищает локальный кэш сообщений, сохраняя авторизацию и список чатов.
  Future<int> clearMessageCache() async {
    final removed = await store.clearMessageCache();
    _chatHasMore.clear();
    _loadingMoreChats.clear();
    notifyListeners();
    return removed;
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

  Future<void> _ensureChatLoaded(int chatId) async {
    if (store.chats[chatId] != null || _isDemoMode || !isSessionReady) {
      return;
    }
    try {
      final packet = await session.request(Opcode.chatInfo, {
        'chatIds': [chatId],
      });
      final chats = packet.payloadAsMap?['chats'];
      if (chats is List && chats.isNotEmpty && chats.first is Map) {
        final accountId = currentUser?.id ?? store.accountId ?? 0;
        final parsed = _parseServerChat(
          chats.first as Map,
          accountId: accountId,
        );
        if (parsed != null) {
          await store.saveChats([parsed]);
          _resolveDialogPeers();
        }
      }
    } catch (_) {}
  }

  void _handleServerPush(TalerPacket packet) {
    final data = packet.payloadAsMap;
    if (data == null) return;

    switch (packet.opcode) {
      case Opcode.notifMessage:
        final chatId = (data['chatId'] as num?)?.toInt();
        final msgMap = data['message'];
        if (chatId == null || msgMap is! Map) return;
        final msgLink = msgMap['link'];
        final isComment = data['postId'] is String ||
            msgMap['postId'] is String ||
            (msgLink is Map && msgLink['postId'] is String);
        if (isComment) return;
        final unread = (data['unread'] as num?)?.toInt();
        unawaited(_onNotifMessage(chatId, msgMap, unread));

      case Opcode.notifMsgDelete:
      case Opcode.notifMsgDeleteRange:
        final chatMap = data['chat'];
        final chatId =
            (chatMap is Map ? (chatMap['id'] as num?)?.toInt() : null) ??
                (data['chatId'] as num?)?.toInt();
        if (chatId == null) return;
        final unread = (data['unread'] as num?)?.toInt();
        if (chatMap is Map) {
          final accountId = currentUser?.id ?? store.accountId ?? 0;
          final parsed = _parseServerChat(chatMap, accountId: accountId);
          if (parsed != null) {
            unawaited(store.saveChats([parsed]));
          }
        }
        final idsRaw = data['messageIds'];
        if (idsRaw is List && idsRaw.isNotEmpty) {
          final ids = idsRaw.map((e) => e.toString()).toList();
          unawaited(
            _applyDeletedMessages(
              chatId,
              ids,
              unreadFromPayload: unread,
              recordAudit: true,
            ),
          );
        } else {
          final startTime =
              ((data['startTime'] ?? data['fromTime']) as num?)?.toInt();
          final endTime =
              ((data['endTime'] ?? data['toTime']) as num?)?.toInt();
          if (startTime != null && endTime != null) {
            unawaited(() async {
              final affected = await store.markMessagesDeletedByTimeRange(
                chatId,
                startTime: startTime,
                endTime: endTime,
                antiDeleteEnabled: privacySettings.antiDelete,
              );
              if (affected > 0 && privacySettings.antiDelete) {
                _recordAntiDeleteAudit(chatId, '$startTime..$endTime');
              }
              notifyListeners();
            }());
          }
        }

      case Opcode.notifMsgReactionsChanged:
      case Opcode.notifMsgYouReacted:
        final chatId = (data['chatId'] as num?)?.toInt();
        final messageId = data['messageId']?.toString();
        if (chatId != null && messageId != null && messageId.isNotEmpty) {
          unawaited(_applyReactionPush(chatId, messageId, data));
        }

      case Opcode.notifChat:
        final chatMap = data['chat'];
        if (chatMap is Map) {
          final accountId = currentUser?.id ?? store.accountId ?? 0;
          final parsed = _parseServerChat(chatMap, accountId: accountId);
          if (parsed != null) {
            unawaited(() async {
              await store.saveChats([parsed]);
              _resolveDialogPeers();
              notifyListeners();
            }());
          }
        }

      case Opcode.notifContact:
        final contactMap = data['contact'];
        if (contactMap is Map) {
          final contact = TalerContact.fromServerMap(contactMap);
          if (contact.id != 0) {
            unawaited(() async {
              await store.saveContacts([contact]);
              notifyListeners();
            }());
          }
        }

      case Opcode.notifTyping:
        final chatId = (data['chatId'] as num?)?.toInt();
        final userId = ((data['user'] ?? data['userId']) as num?)?.toInt();
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
        final userId = (data['userId'] as num?)?.toInt();
        if (presence is Map) {
          if (userId != null) {
            unawaited(_applyPresencePush({userId: presence}));
          } else {
            unawaited(_applyPresencePush(presence));
          }
        }

      case Opcode.notifMark:
        final chatId = (data['chatId'] as num?)?.toInt();
        if (chatId == null) return;
        final chat = store.chats[chatId];
        if (chat == null) return;
        final unread = (data['unread'] as num?)?.toInt();
        final userId = (data['userId'] as num?)?.toInt();
        final mark = (data['mark'] as num?)?.toInt();
        final setAsUnread = data['setAsUnread'] == true;

        var nextChat = chat;
        var changed = false;
        if (unread != null && unread != nextChat.unreadCount) {
          nextChat = nextChat.copyWith(unreadCount: unread);
          changed = true;
        }
        if (!setAsUnread &&
            userId != null &&
            userId != currentUser?.id &&
            mark != null &&
            mark > (nextChat.peerReadMark ?? 0)) {
          nextChat = nextChat.copyWith(peerReadMark: mark);
          changed = true;
        }
        if (changed) {
          unawaited(() async {
            await store.saveChats([nextChat]);
            notifyListeners();
          }());
        }

      case Opcode.notifDraft:
        final chatId = (data['chatId'] as num?)?.toInt();
        final draftObj = data['draft'];
        if (chatId != null && draftObj is Map) {
          final text = (draftObj['text'] as String?) ?? '';
          final link = draftObj['link'];
          final replyId =
              link is Map ? link['messageId']?.toString() : null;
          unawaited(
            saveDraft(
              chatId,
              text,
              replyToMessageId: replyId,
              syncRemote: false,
            ),
          );
        }

      case Opcode.notifDraftDiscard:
        final chatId = (data['chatId'] as num?)?.toInt();
        if (chatId != null) {
          unawaited(saveDraft(chatId, '', syncRemote: false));
        }
    }
  }

  Future<void> _onNotifMessage(
    int chatId,
    Map<dynamic, dynamic> msgMap,
    int? unreadFromPayload,
  ) async {
    await _ensureChatLoaded(chatId);

    final rawStatus = msgMap['status']?.toString().toUpperCase();
    final msgId = msgMap['id']?.toString();
    if (msgId == null || msgId.isEmpty) return;

    if (rawStatus == 'REMOVED') {
      await _applyDeletedMessages(
        chatId,
        [msgId],
        unreadFromPayload: unreadFromPayload,
        recordAudit: true,
      );
      return;
    }

    final parsed = _parseServerMessage(msgMap, chatId);
    if (parsed == null) return;

    if (parsed.senderId > 0 &&
        parsed.senderId != currentUser?.id &&
        store.contacts[parsed.senderId] == null) {
      unawaited(resolveContacts([parsed.senderId]));
    }

    await _applyIncomingMessage(
      chatId,
      parsed,
      isEditedPush: rawStatus == 'EDITED',
      unreadFromPayload: unreadFromPayload,
    );
  }

  Future<void> _applyDeletedMessages(
    int chatId,
    List<String> ids, {
    int? unreadFromPayload,
    bool recordAudit = false,
  }) async {
    if (ids.isEmpty) return;
    final affected = await store.markMessagesDeletedByPeer(
      chatId,
      ids,
      antiDeleteEnabled: privacySettings.antiDelete,
    );
    var chat = store.chats[chatId];
    if (chat != null && unreadFromPayload != null) {
      chat = chat.copyWith(unreadCount: unreadFromPayload);
      await store.saveChats([chat]);
    }
    if (recordAudit && affected > 0 && privacySettings.antiDelete) {
      _recordAntiDeleteAudit(chatId, ids.join(', '));
    }
    notifyListeners();
  }

  void _recordAntiDeleteAudit(int chatId, String target) {
    auditLog.record(
      WireAuditEntry(
        timestamp: DateTime.now(),
        direction: PacketDirection.incoming,
        opcode: Opcode.notifMsgDelete,
        opcodeName: Opcode.name(Opcode.notifMsgDelete),
        seq: 0,
        verdict: AuditVerdict.allowed,
        summary: 'Anti-Delete: перехвачено удаление #$target в чате #$chatId',
        payload: {'chatId': chatId, 'target': target},
      ),
    );
  }

  Future<void> _applyReactionPush(
    int chatId,
    String messageId,
    Map<String, dynamic> data,
  ) async {
    final existingList = store.getMessages(chatId);
    final idx = existingList.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;

    final existing = existingList[idx];
    final nextReactions = <TalerReactionCounter>[];
    final your = data['yourReaction']?.toString() ??
        (data['reactionInfo'] is Map
            ? (data['reactionInfo'] as Map)['yourReaction']?.toString()
            : null);
    final rawCounters = data['counters'] ??
        (data['reactionInfo'] is Map
            ? (data['reactionInfo'] as Map)['counters']
            : null);

    if (rawCounters is List) {
      for (final c in rawCounters.whereType<Map>()) {
        final emoji = c['reaction']?.toString();
        final count = (c['count'] as num?)?.toInt() ?? 0;
        if (emoji != null && emoji.isNotEmpty && count > 0) {
          final wasMine =
              existing.reactions.any((r) => r.emoji == emoji && r.isMine);
          nextReactions.add(
            TalerReactionCounter(
              emoji: emoji,
              count: count,
              isMine: your != null ? emoji == your : wasMine,
            ),
          );
        }
      }
      await store.upsertMessage(
        existing.copyWith(reactions: nextReactions),
        trackEditHistory: false,
      );
      notifyListeners();
    }
  }

  Future<void> _applyIncomingMessage(
    int chatId,
    TalerMessage msg, {
    bool isEditedPush = false,
    int? unreadFromPayload,
  }) async {
    final existingBefore = store.getMessages(chatId);
    final alreadyExists = existingBefore.any(
      (m) => m.id == msg.id || (msg.cid != null && m.cid == msg.cid),
    );

    if (msg.cid != null) {
      final tempMatch = existingBefore
          .where((m) => m.cid == msg.cid && m.id != msg.id)
          .firstOrNull;
      if (tempMatch != null) {
        await store.replaceTempMessage(chatId, tempMatch.id, msg);
        _sendErrors.remove(tempMatch.id);
      } else {
        await store.upsertMessage(msg);
      }
    } else {
      await store.upsertMessage(msg);
    }

    final chat = store.chats[chatId];
    if (chat != null) {
      final isMine = msg.senderId == currentUser?.id;
      final previewText = msg.text.isNotEmpty ? msg.text : '[Вложение]';
      final isLatest =
          !isEditedPush || msg.time >= (chat.lastMessageTime ?? 0);
      final nextUnread = unreadFromPayload ??
          (isEditedPush || isMine || alreadyExists
              ? chat.unreadCount
              : chat.unreadCount + 1);
      await store.saveChats([
        chat.copyWith(
          lastMessageText: isLatest ? previewText : null,
          lastMessageTime: isLatest ? msg.time : null,
          lastMessageSenderId: isLatest ? msg.senderId : null,
          lastMessageDeletedByPeer: isLatest ? false : null,
          unreadCount: nextUnread,
          clearTyping: !isEditedPush,
        ),
      ]);
      if (chatId == _activeChatId && _appInForeground && !isMine && !isEditedPush) {
        unawaited(markChatRead(chatId));
      } else if (!isMine &&
          !isEditedPush &&
          !alreadyExists &&
          !chat.isMuted &&
          !msg.isControl) {
        final shouldNotify = !_appInForeground || chatId != _activeChatId;
        if (shouldNotify) {
          final sender = senderDisplayName(msg.senderId, chatId: chatId);
          final rawBody = _notificationBodyForMessage(msg);
          final body = appPreferences.showNotificationPreview
              ? rawBody
              : 'Новое сообщение';
          unawaited(
            TalerNativeBridge.instance.showMessageNotification(
              chatId: chatId,
              title: chat.title,
              body: body,
              sender: chat.isDialog ? chat.title : sender,
            ),
          );
        }
      }
    }
    notifyListeners();
  }

  static String _notificationBodyForMessage(TalerMessage msg) {
    final text = msg.text.trim();
    if (text.isNotEmpty) return text;
    if (msg.attachments.isNotEmpty) {
      final first = msg.attachments.first;
      return switch (first.type) {
        'PHOTO' => '📷 Фото',
        'VIDEO' || 'VIDEO_MSG' || 'VIDEO_NOTE' => '🎬 Видео',
        'VOICE' || 'AUDIO' => '🎤 Голосовое сообщение',
        'STICKER' => 'Стикер',
        'FILE' => '📎 ${first.fileName ?? 'Файл'}',
        _ => 'Вложение',
      };
    }
    return 'Новое сообщение';
  }

  /// Вспомогательный метод для тестирования обработки серверных пушей.
  @visibleForTesting
  Future<void> debugHandlePush(TalerPacket packet) async {
    final data = packet.payloadAsMap;
    if (data == null) return;
    if (packet.opcode == Opcode.notifMessage) {
      final chatId = (data['chatId'] as num?)?.toInt();
      final msgMap = data['message'];
      if (chatId != null && msgMap is Map) {
        final unread = (data['unread'] as num?)?.toInt();
        await _onNotifMessage(chatId, msgMap, unread);
      }
      return;
    }
    _handleServerPush(packet);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> _applyPresencePush(Map<dynamic, dynamic> presence) async {
    var changed = false;
    for (final entry in presence.entries) {
      final uid = int.tryParse(entry.key.toString());
      if (uid == null || entry.value is! Map) continue;
      final p = entry.value as Map;
      final online = (p['status'] as num?)?.toInt() == 1;
      final seen = normalizeEpochMs((p['seen'] as num?)?.toInt());
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
      _loggedInSessionEpoch = -1;
      _activeChatId = null;
      _sendErrors.clear();
      _chatHasMore.clear();
      _loadingMoreChats.clear();
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
    for (final t in _draftSyncTimers.values) {
      t.cancel();
    }
    _draftSyncTimers.clear();
    if (_ownsUpdater) {
      updater.dispose();
    }
    unawaited(store.flush());
    unawaited(session.dispose());
    super.dispose();
  }
}

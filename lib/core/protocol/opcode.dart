/// Коды операций бинарного протокола MAX.
///
/// Основано на открытой спецификации протокола (KometTeam/Komet),
/// переписано с нуля на чистом Dart для Taler без закрытых библиотек.
abstract class Opcode {
  // ── Сессия и транспорт ───────────────────────────────────────────────────
  static const int ping = 1;
  static const int debug = 2;
  static const int reconnect = 3;
  static const int log = 5;
  static const int sessionInit = 6;
  static const int contactsGet = 8;

  // ── Профиль и авторизация ────────────────────────────────────────────────
  static const int profile = 16;
  static const int authRequest = 17;
  static const int auth = 18;
  static const int login = 19;
  static const int logout = 20;
  static const int sync = 21;
  static const int config = 22;
  static const int authConfirm = 23;

  // ── 2FA и восстановление ─────────────────────────────────────────────────
  static const int authLoginRestorePassword = 101;
  static const int auth2faDetails = 104;
  static const int authValidatePassword = 107;
  static const int authValidateHint = 108;
  static const int authVerifyEmail = 109;
  static const int authCheckEmail = 110;
  static const int authSet2fa = 111;
  static const int authCreateTrack = 112;
  static const int authCheckPassword = 113;
  static const int authLoginCheckPassword = 115;

  // ── Стикеры ──────────────────────────────────────────────────────────────
  static const int presetAvatars = 25;
  static const int assetsGet = 26;
  static const int assetsUpdate = 27;
  static const int assetsGetByIds = 28;
  static const int assetsAdd = 29;

  // ── Контакты ─────────────────────────────────────────────────────────────
  static const int contactInfo = 32;
  static const int contactAdd = 33;
  static const int contactUpdate = 34;
  static const int contactPresence = 35;
  static const int contactList = 36;
  static const int contactSearch = 37;
  static const int contactMutual = 38;
  static const int contactPhotos = 39;
  static const int contactAddByPhone = 41;
  static const int contactInfoByPhone = 46;

  // ── Чаты ─────────────────────────────────────────────────────────────────
  static const int chatInfo = 48;
  static const int chatHistory = 49;
  static const int chatMark = 50;
  static const int chatMedia = 51;
  static const int chatDelete = 52;
  static const int chatsList = 53;
  static const int chatClear = 54;
  static const int chatUpdate = 55;
  static const int chatCheckLink = 56;
  static const int chatJoin = 57;
  static const int chatLeave = 58;
  static const int chatMembers = 59;
  static const int publicSearch = 60;
  static const int chatPersonalConfig = 61;
  static const int chatCreate = 63;

  // ── Сообщения ────────────────────────────────────────────────────────────
  static const int msgSend = 64;
  static const int msgTyping = 65;
  static const int msgDelete = 66;
  static const int msgEdit = 67;
  static const int chatSearch = 68;
  static const int msgSharePreview = 70;
  static const int msgGet = 71;
  static const int msgSearchTouch = 72;
  static const int msgSearch = 73;
  static const int msgGetStat = 74;
  static const int chatSubscribe = 75;
  static const int msgDeleteRange = 92;

  // ── Медиа и файлы ────────────────────────────────────────────────────────
  static const int photoUpload = 80;
  static const int stickerUpload = 81;
  static const int videoUpload = 82;
  static const int videoPlay = 83;
  static const int fileUpload = 87;
  static const int fileDownload = 88;
  static const int linkInfo = 89;
  static const int audioPlay = 301;

  // ── Сессии ───────────────────────────────────────────────────────────────
  static const int sessionsInfo = 96;
  static const int sessionsClose = 97;

  // ── Входящие пуши от сервера ─────────────────────────────────────────────
  static const int notifMessage = 128;
  static const int notifTyping = 129;
  static const int notifMark = 130;
  static const int notifContact = 131;
  static const int notifPresence = 132;
  static const int notifConfig = 134;
  static const int notifChat = 135;
  static const int notifAttach = 136;
  static const int notifCallStart = 137;
  static const int notifMsgDeleteRange = 140;
  static const int notifMsgDelete = 142;
  static const int notifAssetsUpdate = 150;
  static const int notifDraft = 152;
  static const int notifDraftDiscard = 153;
  static const int notifMsgDelayed = 154;
  static const int notifMsgReactionsChanged = 155;
  static const int notifMsgYouReacted = 156;
  static const int notifProfile = 159;

  // ── Реакции и черновики ──────────────────────────────────────────────────
  static const int draftSave = 176;
  static const int draftDiscard = 177;
  static const int msgReaction = 178;
  static const int msgCancelReaction = 179;
  static const int msgGetReactions = 180;
  static const int msgGetDetailedReactions = 181;

  // ── Папки чатов ──────────────────────────────────────────────────────────
  static const int foldersGet = 272;
  static const int foldersGetById = 273;
  static const int foldersUpdate = 274;
  static const int foldersReorder = 275;
  static const int foldersDelete = 276;
  static const int notifFolders = 277;

  // ── Прочее и телеметрия / баннеры ────────────────────────────────────────
  static const int authQrApprove = 290;
  static const int notifBanners = 292;
  static const int chatSuggest = 300;
  static const int bannersSync = 302;

  /// Опкоды телеметрии, аналитики, отладки и рекламных баннеров,
  /// которые жёстко блокируются в Taler на уровне транспорта.
  static const Set<int> telemetryOpcodes = {
    log,
    debug,
    bannersSync,
    chatSuggest,
    notifBanners,
  };

  /// Читаемое имя опкода для Traffic Audit Log.
  static String name(int opcode) => _names[opcode] ?? 'UNKNOWN($opcode)';

  static const Map<int, String> _names = {
    ping: 'PING',
    debug: 'DEBUG',
    reconnect: 'RECONNECT',
    log: 'LOG_TELEMETRY',
    sessionInit: 'SESSION_INIT',
    contactsGet: 'CONTACTS_GET',
    profile: 'PROFILE',
    authRequest: 'AUTH_REQUEST',
    auth: 'AUTH',
    login: 'LOGIN',
    logout: 'LOGOUT',
    sync: 'SYNC',
    config: 'CONFIG',
    authConfirm: 'AUTH_CONFIRM',
    authLoginRestorePassword: 'AUTH_LOGIN_RESTORE_PASSWORD',
    auth2faDetails: 'AUTH_2FA_DETAILS',
    authValidatePassword: 'AUTH_VALIDATE_PASSWORD',
    authValidateHint: 'AUTH_VALIDATE_HINT',
    authVerifyEmail: 'AUTH_VERIFY_EMAIL',
    authCheckEmail: 'AUTH_CHECK_EMAIL',
    authSet2fa: 'AUTH_SET_2FA',
    authCreateTrack: 'AUTH_CREATE_TRACK',
    authCheckPassword: 'AUTH_CHECK_PASSWORD',
    authLoginCheckPassword: 'AUTH_LOGIN_CHECK_PASSWORD',
    presetAvatars: 'PRESET_AVATARS',
    assetsGet: 'ASSETS_GET',
    assetsUpdate: 'ASSETS_UPDATE',
    assetsGetByIds: 'ASSETS_GET_BY_IDS',
    assetsAdd: 'ASSETS_ADD',
    contactInfo: 'CONTACT_INFO',
    contactAdd: 'CONTACT_ADD',
    contactUpdate: 'CONTACT_UPDATE',
    contactPresence: 'CONTACT_PRESENCE',
    contactList: 'CONTACT_LIST',
    contactSearch: 'CONTACT_SEARCH',
    contactMutual: 'CONTACT_MUTUAL',
    contactPhotos: 'CONTACT_PHOTOS',
    contactAddByPhone: 'CONTACT_ADD_BY_PHONE',
    contactInfoByPhone: 'CONTACT_INFO_BY_PHONE',
    chatInfo: 'CHAT_INFO',
    chatHistory: 'CHAT_HISTORY',
    chatMark: 'CHAT_MARK',
    chatMedia: 'CHAT_MEDIA',
    chatDelete: 'CHAT_DELETE',
    chatsList: 'CHATS_LIST',
    chatClear: 'CHAT_CLEAR',
    chatUpdate: 'CHAT_UPDATE',
    chatCheckLink: 'CHAT_CHECK_LINK',
    chatJoin: 'CHAT_JOIN',
    chatLeave: 'CHAT_LEAVE',
    chatMembers: 'CHAT_MEMBERS',
    publicSearch: 'PUBLIC_SEARCH',
    chatPersonalConfig: 'CHAT_PERSONAL_CONFIG',
    chatCreate: 'CHAT_CREATE',
    msgSend: 'MSG_SEND',
    msgTyping: 'MSG_TYPING',
    msgDelete: 'MSG_DELETE',
    msgEdit: 'MSG_EDIT',
    chatSearch: 'CHAT_SEARCH',
    msgSharePreview: 'MSG_SHARE_PREVIEW',
    msgGet: 'MSG_GET',
    msgSearchTouch: 'MSG_SEARCH_TOUCH',
    msgSearch: 'MSG_SEARCH',
    msgGetStat: 'MSG_GET_STAT',
    chatSubscribe: 'CHAT_SUBSCRIBE',
    msgDeleteRange: 'MSG_DELETE_RANGE',
    photoUpload: 'PHOTO_UPLOAD',
    stickerUpload: 'STICKER_UPLOAD',
    videoUpload: 'VIDEO_UPLOAD',
    videoPlay: 'VIDEO_PLAY',
    fileUpload: 'FILE_UPLOAD',
    fileDownload: 'FILE_DOWNLOAD',
    linkInfo: 'LINK_INFO',
    audioPlay: 'AUDIO_PLAY',
    sessionsInfo: 'SESSIONS_INFO',
    sessionsClose: 'SESSIONS_CLOSE',
    notifMessage: 'NOTIF_MESSAGE',
    notifTyping: 'NOTIF_TYPING',
    notifMark: 'NOTIF_MARK',
    notifContact: 'NOTIF_CONTACT',
    notifPresence: 'NOTIF_PRESENCE',
    notifConfig: 'NOTIF_CONFIG',
    notifChat: 'NOTIF_CHAT',
    notifAttach: 'NOTIF_ATTACH',
    notifCallStart: 'NOTIF_CALL_START',
    notifMsgDeleteRange: 'NOTIF_MSG_DELETE_RANGE',
    notifMsgDelete: 'NOTIF_MSG_DELETE',
    notifAssetsUpdate: 'NOTIF_ASSETS_UPDATE',
    notifDraft: 'NOTIF_DRAFT',
    notifDraftDiscard: 'NOTIF_DRAFT_DISCARD',
    notifMsgDelayed: 'NOTIF_MSG_DELAYED',
    notifMsgReactionsChanged: 'NOTIF_MSG_REACTIONS_CHANGED',
    notifMsgYouReacted: 'NOTIF_MSG_YOU_REACTED',
    notifProfile: 'NOTIF_PROFILE',
    draftSave: 'DRAFT_SAVE',
    draftDiscard: 'DRAFT_DISCARD',
    msgReaction: 'MSG_REACTION',
    msgCancelReaction: 'MSG_CANCEL_REACTION',
    msgGetReactions: 'MSG_GET_REACTIONS',
    msgGetDetailedReactions: 'MSG_GET_DETAILED_REACTIONS',
    foldersGet: 'FOLDERS_GET',
    foldersGetById: 'FOLDERS_GET_BY_ID',
    foldersUpdate: 'FOLDERS_UPDATE',
    foldersReorder: 'FOLDERS_REORDER',
    foldersDelete: 'FOLDERS_DELETE',
    notifFolders: 'NOTIF_FOLDERS',
    authQrApprove: 'AUTH_QR_APPROVE',
    notifBanners: 'NOTIF_BANNERS',
    chatSuggest: 'CHAT_SUGGEST',
    bannersSync: 'BANNERS_SYNC',
  };
}

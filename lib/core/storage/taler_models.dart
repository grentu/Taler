/// Модели данных клиента Taler.
class TalerUserProfile {
  final int id;
  final String firstName;
  final String? lastName;
  final String? phone;
  final String? avatarUrl;
  final String? description;

  const TalerUserProfile({
    required this.id,
    required this.firstName,
    this.lastName,
    this.phone,
    this.avatarUrl,
    this.description,
  });

  String get fullName {
    final last = lastName?.trim();
    if (last == null || last.isEmpty) return firstName;
    return '$firstName $last';
  }

  String get initials {
    final f = firstName.isNotEmpty ? firstName.substring(0, 1).toUpperCase() : '';
    final l = (lastName != null && lastName!.isNotEmpty)
        ? lastName!.substring(0, 1).toUpperCase()
        : '';
    return '$f$l'.isEmpty ? 'T' : '$f$l';
  }

  TalerUserProfile copyWith({
    String? firstName,
    String? lastName,
    String? phone,
    String? avatarUrl,
    String? description,
  }) {
    return TalerUserProfile(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'avatarUrl': avatarUrl,
        'description': description,
      };

  factory TalerUserProfile.fromJson(Map<String, dynamic> json) {
    return TalerUserProfile(
      id: (json['id'] as num?)?.toInt() ?? 0,
      firstName: json['firstName'] as String? ?? 'Пользователь',
      lastName: json['lastName'] as String?,
      phone: json['phone'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      description: json['description'] as String?,
    );
  }

  factory TalerUserProfile.fromServerProfile(Map<dynamic, dynamic> profile) {
    final contact = profile['contact'] is Map ? profile['contact'] as Map : profile;
    final id = (contact['id'] as num?)?.toInt() ??
        (profile['id'] as num?)?.toInt() ??
        0;
    String firstName = 'Пользователь';
    String? lastName;
    final names = contact['names'];
    if (names is List && names.isNotEmpty) {
      Map? chosen;
      for (final n in names) {
        if (n is Map) {
          chosen ??= n;
          if (n['type'] == 'ONEME' || n['type'] == 'CUSTOM') {
            chosen = n;
            break;
          }
        }
      }
      if (chosen != null) {
        firstName = (chosen['firstName'] as String?) ?? firstName;
        lastName = chosen['lastName'] as String?;
      }
    }
    return TalerUserProfile(
      id: id,
      firstName: firstName,
      lastName: lastName,
      phone: contact['phone']?.toString(),
      avatarUrl: contact['baseUrl'] as String?,
      description: contact['description'] as String?,
    );
  }
}

class TalerContact {
  final int id;
  final String firstName;
  final String? lastName;
  final int? phone;
  final String? avatarUrl;
  final bool isOnline;
  final int? lastSeen;
  final bool isOfficial;

  const TalerContact({
    required this.id,
    required this.firstName,
    this.lastName,
    this.phone,
    this.avatarUrl,
    this.isOnline = false,
    this.lastSeen,
    this.isOfficial = false,
  });

  String get displayName {
    final last = lastName?.trim();
    if (last == null || last.isEmpty) {
      return firstName.isEmpty ? 'ID $id' : firstName;
    }
    return '$firstName $last'.trim();
  }

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts[1].substring(0, 1)}'
        .toUpperCase();
  }

  TalerContact copyWith({
    String? firstName,
    String? lastName,
    int? phone,
    String? avatarUrl,
    bool? isOnline,
    int? lastSeen,
    bool? isOfficial,
  }) {
    return TalerContact(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      isOfficial: isOfficial ?? this.isOfficial,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'avatarUrl': avatarUrl,
        'isOnline': isOnline,
        'lastSeen': lastSeen,
        'isOfficial': isOfficial,
      };

  factory TalerContact.fromJson(Map<String, dynamic> json) {
    return TalerContact(
      id: (json['id'] as num?)?.toInt() ?? 0,
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String?,
      phone: (json['phone'] as num?)?.toInt(),
      avatarUrl: json['avatarUrl'] as String?,
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeen: (json['lastSeen'] as num?)?.toInt(),
      isOfficial: json['isOfficial'] as bool? ?? false,
    );
  }

  factory TalerContact.fromServerMap(Map<dynamic, dynamic> map) {
    final id = (map['id'] as num?)?.toInt() ?? 0;
    String firstName = '';
    String? lastName;
    final names = map['names'];
    if (names is List && names.isNotEmpty) {
      Map? chosen;
      for (final n in names) {
        if (n is! Map) continue;
        chosen ??= n;
        if (n['type'] == 'CUSTOM') {
          chosen = n;
          break;
        }
        if (n['type'] == 'ONEME') {
          chosen = n;
        }
      }
      if (chosen != null) {
        firstName = (chosen['firstName'] as String?) ?? '';
        lastName = chosen['lastName'] as String?;
      }
    }
    final opts = map['options'];
    final isOfficial =
        opts is List && opts.any((e) => e.toString() == 'OFFICIAL');
    return TalerContact(
      id: id,
      firstName: firstName,
      lastName: lastName,
      phone: (map['phone'] as num?)?.toInt(),
      avatarUrl: map['baseUrl'] as String?,
      isOfficial: isOfficial,
    );
  }
}

class TalerFolder {
  final String id;
  final String title;
  final Set<int> chatIds;
  final List<int> favorites;
  final bool isAllChats;

  const TalerFolder({
    required this.id,
    required this.title,
    this.chatIds = const {},
    this.favorites = const [],
    this.isAllChats = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'chatIds': chatIds.toList(),
        'favorites': favorites,
        'isAllChats': isAllChats,
      };

  factory TalerFolder.fromJson(Map<String, dynamic> json) {
    return TalerFolder(
      id: json['id']?.toString() ?? 'all',
      title: json['title'] as String? ?? 'Все',
      chatIds: (json['chatIds'] as List?)
              ?.map((e) => (e as num).toInt())
              .toSet() ??
          const {},
      favorites: (json['favorites'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      isAllChats: json['isAllChats'] as bool? ?? false,
    );
  }
}

class TalerReactionCounter {
  final String emoji;
  final int count;
  final bool isMine;

  const TalerReactionCounter({
    required this.emoji,
    required this.count,
    this.isMine = false,
  });

  Map<String, dynamic> toJson() => {
        'emoji': emoji,
        'count': count,
        'isMine': isMine,
      };

  factory TalerReactionCounter.fromJson(Map<String, dynamic> json) {
    return TalerReactionCounter(
      emoji: json['emoji'] as String? ?? '👍',
      count: (json['count'] as num?)?.toInt() ?? 1,
      isMine: json['isMine'] as bool? ?? false,
    );
  }
}

class TalerAttachment {
  final String type;
  final String? url;
  final String? fileName;
  final int? fileSize;
  final int? fileId;
  final int? photoId;
  final String? token;
  final int? width;
  final int? height;
  final String? previewText;

  const TalerAttachment({
    required this.type,
    this.url,
    this.fileName,
    this.fileSize,
    this.fileId,
    this.photoId,
    this.token,
    this.width,
    this.height,
    this.previewText,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'url': url,
        'fileName': fileName,
        'fileSize': fileSize,
        'fileId': fileId,
        'photoId': photoId,
        'token': token,
        'width': width,
        'height': height,
        'previewText': previewText,
      };

  factory TalerAttachment.fromJson(Map<String, dynamic> json) {
    return TalerAttachment(
      type: json['type'] as String? ?? 'UNKNOWN',
      url: json['url'] as String?,
      fileName: json['fileName'] as String?,
      fileSize: (json['fileSize'] as num?)?.toInt(),
      fileId: (json['fileId'] as num?)?.toInt(),
      photoId: (json['photoId'] as num?)?.toInt(),
      token: json['token'] as String?,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      previewText: json['previewText'] as String?,
    );
  }

  factory TalerAttachment.fromServerAttach(Map<dynamic, dynamic> map) {
    final rawType = (map['_type'] ?? map['type'] ?? 'UNKNOWN')
        .toString()
        .toUpperCase();
    return TalerAttachment(
      type: rawType,
      url: (map['baseUrl'] ?? map['url'] ?? map['previewUrl'])?.toString(),
      fileName: (map['name'] ?? map['fileName'])?.toString(),
      fileSize: (map['size'] as num?)?.toInt(),
      fileId: (map['fileId'] as num?)?.toInt(),
      photoId: (map['photoId'] as num?)?.toInt(),
      token: (map['photoToken'] ?? map['token'])?.toString(),
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      previewText: (map['title'] ?? map['event'])?.toString(),
    );
  }
}

class TalerEditRevision {
  final String text;
  final int timestamp;

  const TalerEditRevision({
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'timestamp': timestamp,
      };

  factory TalerEditRevision.fromJson(Map<String, dynamic> json) {
    return TalerEditRevision(
      text: json['text'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }
}

class TalerReplyPreview {
  final String? messageId;
  final int senderId;
  final String? senderName;
  final String? text;

  const TalerReplyPreview({
    this.messageId,
    required this.senderId,
    this.senderName,
    this.text,
  });

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
      };

  factory TalerReplyPreview.fromJson(Map<String, dynamic> json) {
    return TalerReplyPreview(
      messageId: json['messageId']?.toString(),
      senderId: (json['senderId'] as num?)?.toInt() ?? 0,
      senderName: json['senderName'] as String?,
      text: json['text'] as String?,
    );
  }
}

class TalerMessage {
  final String id;
  final int chatId;
  final int senderId;
  final String text;
  final int time;
  final String status;
  final bool deletedByPeer;
  final int? deletedAt;
  final List<TalerEditRevision> editHistory;
  final TalerReplyPreview? replyTo;
  final List<TalerAttachment> attachments;
  final List<TalerReactionCounter> reactions;
  final bool isControl;
  final String? forwardedFromName;

  const TalerMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.time,
    this.status = 'sent',
    this.deletedByPeer = false,
    this.deletedAt,
    this.editHistory = const [],
    this.replyTo,
    this.attachments = const [],
    this.reactions = const [],
    this.isControl = false,
    this.forwardedFromName,
  });

  bool get isEdited => editHistory.isNotEmpty || status == 'edited';

  TalerMessage copyWith({
    String? id,
    int? chatId,
    int? senderId,
    String? text,
    int? time,
    String? status,
    bool? deletedByPeer,
    int? deletedAt,
    List<TalerEditRevision>? editHistory,
    TalerReplyPreview? replyTo,
    List<TalerAttachment>? attachments,
    List<TalerReactionCounter>? reactions,
    bool? isControl,
    String? forwardedFromName,
  }) {
    return TalerMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      time: time ?? this.time,
      status: status ?? this.status,
      deletedByPeer: deletedByPeer ?? this.deletedByPeer,
      deletedAt: deletedAt ?? this.deletedAt,
      editHistory: editHistory ?? this.editHistory,
      replyTo: replyTo ?? this.replyTo,
      attachments: attachments ?? this.attachments,
      reactions: reactions ?? this.reactions,
      isControl: isControl ?? this.isControl,
      forwardedFromName: forwardedFromName ?? this.forwardedFromName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'senderId': senderId,
        'text': text,
        'time': time,
        'status': status,
        'deletedByPeer': deletedByPeer,
        'deletedAt': deletedAt,
        'editHistory': editHistory.map((e) => e.toJson()).toList(),
        'replyTo': replyTo?.toJson(),
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'reactions': reactions.map((r) => r.toJson()).toList(),
        'isControl': isControl,
        'forwardedFromName': forwardedFromName,
      };

  factory TalerMessage.fromJson(Map<String, dynamic> json) {
    return TalerMessage(
      id: json['id']?.toString() ?? '',
      chatId: (json['chatId'] as num?)?.toInt() ?? 0,
      senderId: (json['senderId'] as num?)?.toInt() ?? 0,
      text: json['text'] as String? ?? '',
      time: (json['time'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'sent',
      deletedByPeer: json['deletedByPeer'] as bool? ?? false,
      deletedAt: (json['deletedAt'] as num?)?.toInt(),
      editHistory: (json['editHistory'] as List?)
              ?.whereType<Map>()
              .map((e) => TalerEditRevision.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      replyTo: json['replyTo'] is Map
          ? TalerReplyPreview.fromJson(
              Map<String, dynamic>.from(json['replyTo'] as Map),
            )
          : null,
      attachments: (json['attachments'] as List?)
              ?.whereType<Map>()
              .map((a) => TalerAttachment.fromJson(Map<String, dynamic>.from(a)))
              .toList() ??
          const [],
      reactions: (json['reactions'] as List?)
              ?.whereType<Map>()
              .map(
                (r) => TalerReactionCounter.fromJson(
                  Map<String, dynamic>.from(r),
                ),
              )
              .toList() ??
          const [],
      isControl: json['isControl'] as bool? ?? false,
      forwardedFromName: json['forwardedFromName'] as String?,
    );
  }
}

class TalerChat {
  final int id;
  final String type;
  final String title;
  final String? avatarUrl;
  final int? peerId;
  final String? lastMessageText;
  final int? lastMessageTime;
  final int? lastMessageSenderId;
  final bool lastMessageDeletedByPeer;
  final int unreadCount;
  final bool isOnline;
  final int? lastSeen;
  final int favIndex;
  final bool isMuted;
  final int participantsCount;
  final bool isOfficial;
  final String? typingLabel;

  const TalerChat({
    required this.id,
    required this.type,
    required this.title,
    this.avatarUrl,
    this.peerId,
    this.lastMessageText,
    this.lastMessageTime,
    this.lastMessageSenderId,
    this.lastMessageDeletedByPeer = false,
    this.unreadCount = 0,
    this.isOnline = false,
    this.lastSeen,
    this.favIndex = 0,
    this.isMuted = false,
    this.participantsCount = 2,
    this.isOfficial = false,
    this.typingLabel,
  });

  bool get isPinned => favIndex > 0;
  bool get isGroup => type == 'CHAT' || type == 'GROUP';
  bool get isChannel => type == 'CHANNEL';
  bool get isDialog => !isGroup && !isChannel;

  String get initials {
    final parts = title.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts[1].substring(0, 1)}'
        .toUpperCase();
  }

  TalerChat copyWith({
    String? type,
    String? title,
    String? avatarUrl,
    int? peerId,
    String? lastMessageText,
    int? lastMessageTime,
    int? lastMessageSenderId,
    bool? lastMessageDeletedByPeer,
    int? unreadCount,
    bool? isOnline,
    int? lastSeen,
    int? favIndex,
    bool? isMuted,
    int? participantsCount,
    bool? isOfficial,
    String? typingLabel,
    bool clearTyping = false,
  }) {
    return TalerChat(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      peerId: peerId ?? this.peerId,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageDeletedByPeer:
          lastMessageDeletedByPeer ?? this.lastMessageDeletedByPeer,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      favIndex: favIndex ?? this.favIndex,
      isMuted: isMuted ?? this.isMuted,
      participantsCount: participantsCount ?? this.participantsCount,
      isOfficial: isOfficial ?? this.isOfficial,
      typingLabel: clearTyping ? null : (typingLabel ?? this.typingLabel),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'avatarUrl': avatarUrl,
        'peerId': peerId,
        'lastMessageText': lastMessageText,
        'lastMessageTime': lastMessageTime,
        'lastMessageSenderId': lastMessageSenderId,
        'lastMessageDeletedByPeer': lastMessageDeletedByPeer,
        'unreadCount': unreadCount,
        'isOnline': isOnline,
        'lastSeen': lastSeen,
        'favIndex': favIndex,
        'isMuted': isMuted,
        'participantsCount': participantsCount,
        'isOfficial': isOfficial,
      };

  factory TalerChat.fromJson(Map<String, dynamic> json) {
    return TalerChat(
      id: (json['id'] as num?)?.toInt() ?? 0,
      type: json['type'] as String? ?? 'DIALOG',
      title: json['title'] as String? ?? 'Чат',
      avatarUrl: json['avatarUrl'] as String?,
      peerId: (json['peerId'] as num?)?.toInt(),
      lastMessageText: json['lastMessageText'] as String?,
      lastMessageTime: (json['lastMessageTime'] as num?)?.toInt(),
      lastMessageSenderId: (json['lastMessageSenderId'] as num?)?.toInt(),
      lastMessageDeletedByPeer:
          json['lastMessageDeletedByPeer'] as bool? ?? false,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeen: (json['lastSeen'] as num?)?.toInt(),
      favIndex: (json['favIndex'] as num?)?.toInt() ?? 0,
      isMuted: json['isMuted'] as bool? ?? false,
      participantsCount: (json['participantsCount'] as num?)?.toInt() ?? 2,
      isOfficial: json['isOfficial'] as bool? ?? false,
    );
  }
}

class TalerActiveSession {
  final int? id;
  final String client;
  final String location;
  final bool current;
  final int time;
  final String info;

  const TalerActiveSession({
    this.id,
    required this.client,
    required this.location,
    required this.current,
    required this.time,
    required this.info,
  });

  factory TalerActiveSession.fromMap(Map<dynamic, dynamic> map) {
    return TalerActiveSession(
      id: (map['id'] as num?)?.toInt(),
      client: map['client']?.toString() ?? 'Неизвестный клиент',
      location: map['location']?.toString() ?? '',
      current: map['current'] == true,
      time: (map['time'] as num?)?.toInt() ?? 0,
      info: map['info']?.toString() ?? '',
    );
  }
}

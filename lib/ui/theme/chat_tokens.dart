import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/storage/taler_models.dart';
import 'taler_theme.dart';

/// Цвета и форматирование, общие для списка чатов, переписки и профиля.
abstract final class ChatTokens {
  /// Фон ленты сообщений: глубокий OLED-тёмный или мягкий светлый под дудл-паттерн.
  static Color chatBackground(TalerPalette p) =>
      p.isDark ? const Color(0xFF07080B) : const Color(0xFFEDEFF3);

  static Color hover(TalerPalette p) => p.fg.withValues(alpha: 0.04);

  static Color active(TalerPalette p) => p.isDark
      ? p.fg.withValues(alpha: 0.07)
      : p.accent.withValues(alpha: 0.08);

  static Color accentSoft(TalerPalette p) =>
      p.accent.withValues(alpha: p.isDark ? 0.14 : 0.1);

  static Color badgeMuted(TalerPalette p) =>
      p.isDark ? const Color(0xFF3F3F46) : const Color(0xFFA1A1AA);

  /// Цвет имени отправителя в группах, стабильный для одного id.
  static Color peerColor(int id) =>
      kTalerPeerColors[id.abs() % kTalerPeerColors.length];

  static const List<String> _months = [
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];
  static const List<String> _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  static const List<String> _weekdaysFull = [
    'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье',
  ];

  static DateTime _date(int raw) =>
      DateTime.fromMillisecondsSinceEpoch(normalizeEpochMs(raw) ?? raw);

  static bool sameDay(int a, int b) {
    final x = _date(a);
    final y = _date(b);
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  static int _daysAgo(int ms) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = _date(ms);
    final day = DateTime(d.year, d.month, d.day);
    return today.difference(day).inDays;
  }

  /// Время сообщения: 19:16.
  static String time(int ms) => DateFormat('HH:mm').format(_date(ms));

  /// Время в списке чатов: сегодня — 19:16, на этой неделе — Пн, иначе 12.11.26.
  static String listTime(int? ms) {
    if (ms == null || ms <= 0) return '';
    final normalized = normalizeEpochMs(ms) ?? ms;
    final ago = _daysAgo(normalized);
    if (ago <= 0) return time(normalized);
    if (ago < 7) return _weekdays[_date(normalized).weekday - 1];
    return DateFormat('dd.MM.yy').format(_date(normalized));
  }

  /// Разделитель дат в переписке: Сегодня, Вчера, Понедельник, 3 ноября.
  static String dayLabel(int ms) {
    final normalized = normalizeEpochMs(ms) ?? ms;
    final ago = _daysAgo(normalized);
    if (ago <= 0) return 'Сегодня';
    if (ago == 1) return 'Вчера';
    final d = _date(normalized);
    if (ago < 7) return _weekdaysFull[d.weekday - 1];
    final now = DateTime.now();
    final base = '${d.day} ${_months[d.month - 1]}';
    return d.year == now.year ? base : '$base ${d.year}';
  }

  static String fileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} МБ';
  }

  /// "в сети", "был(а) в 17:40", "28 участников" и т. д.
  static String chatStatus(TalerChat chat) {
    final typing = chat.typingLabel;
    if (typing != null && typing.isNotEmpty) return typing;
    if (chat.isChannel) return '${chat.participantsCount} подписчиков';
    if (chat.isGroup) return '${chat.participantsCount} участников';
    if (chat.isOnline) return 'в сети';
    final seenMs = normalizeEpochMs(chat.lastSeen);
    if (seenMs != null && seenMs > 0) {
      final seenDate = DateTime.fromMillisecondsSinceEpoch(seenMs);
      // Защита от некорректных нулевых/эпохальных значений (< 2010 года).
      if (seenDate.year < 2010) return 'был(а) недавно';
      final diff = DateTime.now().difference(seenDate);
      if (diff.inSeconds >= -60 && diff.inMinutes < 2) {
        return 'был(а) только что';
      }
      final ago = _daysAgo(seenMs);
      if (ago <= 0) return 'был(а) в ${time(seenMs)}';
      if (ago == 1) return 'был(а) вчера в ${time(seenMs)}';
      if (seenDate.year == DateTime.now().year) {
        return 'был(а) ${seenDate.day} ${_months[seenDate.month - 1]}';
      }
      return 'был(а) ${DateFormat('dd.MM.yy').format(seenDate)}';
    }
    return 'был(а) недавно';
  }

  /// Телефон в читаемом виде: +7 925 533-05-98.
  static String phone(int? raw) {
    if (raw == null || raw <= 0) return '';
    final s = raw.toString();
    if (s.length == 11 && (s.startsWith('7') || s.startsWith('8'))) {
      return '+7 ${s.substring(1, 4)} ${s.substring(4, 7)}-${s.substring(7, 9)}-${s.substring(9)}';
    }
    return '+$s';
  }
}

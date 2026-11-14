import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Реактивные настройки приватности и защиты от телеметрии Taler Privacy Shield.
class PrivacySettings extends ChangeNotifier {
  static const _kSpoofingEnabled = 'taler_privacy_spoofing_enabled';
  static const _kGhostModeOnline = 'taler_privacy_ghost_online';
  static const _kHideTyping = 'taler_privacy_hide_typing';
  static const _kHideReadReceipts = 'taler_privacy_hide_read';
  static const _kAntiDelete = 'taler_privacy_anti_delete';
  static const _kBlockedCount = 'taler_privacy_blocked_count';

  bool _spoofingEnabled = true;
  bool _ghostModeOnline = false;
  bool _hideTyping = true;
  bool _hideReadReceipts = false;
  bool _antiDelete = true;
  int _blockedPacketsCount = 0;

  SharedPreferences? _prefs;

  /// Жёсткая блокировка телеметрии и аналитики всегда активна и не отключается.
  bool get blockTelemetry => true;

  bool get spoofingEnabled => _spoofingEnabled;
  bool get ghostModeOnline => _ghostModeOnline;
  bool get hideTyping => _hideTyping;
  bool get hideReadReceipts => _hideReadReceipts;
  bool get antiDelete => _antiDelete;
  int get blockedPacketsCount => _blockedPacketsCount;

  /// Загружает сохранённые настройки из [SharedPreferences].
  Future<void> load([SharedPreferences? prefs]) async {
    _prefs = prefs ?? await SharedPreferences.getInstance();
    _spoofingEnabled = _prefs?.getBool(_kSpoofingEnabled) ?? true;
    _ghostModeOnline = _prefs?.getBool(_kGhostModeOnline) ?? false;
    _hideTyping = _prefs?.getBool(_kHideTyping) ?? true;
    _hideReadReceipts = _prefs?.getBool(_kHideReadReceipts) ?? false;
    _antiDelete = _prefs?.getBool(_kAntiDelete) ?? true;
    _blockedPacketsCount = _prefs?.getInt(_kBlockedCount) ?? 0;
    notifyListeners();
  }

  Future<void> setSpoofingEnabled(bool value) async {
    if (_spoofingEnabled == value) return;
    _spoofingEnabled = value;
    notifyListeners();
    await _prefs?.setBool(_kSpoofingEnabled, value);
  }

  Future<void> setGhostModeOnline(bool value) async {
    if (_ghostModeOnline == value) return;
    _ghostModeOnline = value;
    notifyListeners();
    await _prefs?.setBool(_kGhostModeOnline, value);
  }

  Future<void> setHideTyping(bool value) async {
    if (_hideTyping == value) return;
    _hideTyping = value;
    notifyListeners();
    await _prefs?.setBool(_kHideTyping, value);
  }

  Future<void> setHideReadReceipts(bool value) async {
    if (_hideReadReceipts == value) return;
    _hideReadReceipts = value;
    notifyListeners();
    await _prefs?.setBool(_kHideReadReceipts, value);
  }

  Future<void> setAntiDelete(bool value) async {
    if (_antiDelete == value) return;
    _antiDelete = value;
    notifyListeners();
    await _prefs?.setBool(_kAntiDelete, value);
  }

  void incrementBlockedCount() {
    _blockedPacketsCount += 1;
    notifyListeners();
    _prefs?.setInt(_kBlockedCount, _blockedPacketsCount);
  }

  Future<void> resetBlockedCount() async {
    _blockedPacketsCount = 0;
    notifyListeners();
    await _prefs?.setInt(_kBlockedCount, 0);
  }
}

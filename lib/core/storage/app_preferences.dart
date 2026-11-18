import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Реактивные настройки интерфейса, чатов, уведомлений и энергосбережения.
class AppPreferences extends ChangeNotifier {
  static const _kThemeMode = 'taler_pref_theme_mode';
  static const _kMessageFontSize = 'taler_pref_msg_font_size';
  static const _kBubbleRadius = 'taler_pref_bubble_radius';
  static const _kShowChatWallpaper = 'taler_pref_chat_wallpaper';
  static const _kCompactChatList = 'taler_pref_compact_chats';
  static const _kShowFolderBadges = 'taler_pref_folder_badges';
  static const _kShowNotificationPreview = 'taler_pref_notif_preview';
  static const _kPowerSavingMode = 'taler_pref_power_saving';
  static const _kAutoDownloadMedia = 'taler_pref_auto_download_media';
  static const _kAutoCheckUpdates = 'taler_pref_auto_check_updates';

  SharedPreferences? _prefs;

  ThemeMode _themeMode = ThemeMode.dark;
  double _messageFontSize = 15.0;
  double _bubbleRadius = 20.0;
  bool _showChatWallpaper = true;
  bool _compactChatList = false;
  bool _showFolderBadges = true;
  bool _showNotificationPreview = true;
  bool _powerSavingMode = false;
  bool _autoDownloadMedia = true;
  bool _autoCheckUpdates = true;

  ThemeMode get themeMode => _themeMode;
  double get messageFontSize => _messageFontSize;
  double get bubbleRadius => _bubbleRadius;
  bool get showChatWallpaper => _showChatWallpaper;
  bool get compactChatList => _compactChatList;
  bool get showFolderBadges => _showFolderBadges;
  bool get showNotificationPreview => _showNotificationPreview;
  bool get powerSavingMode => _powerSavingMode;
  bool get autoDownloadMedia => _autoDownloadMedia;
  bool get autoCheckUpdates => _autoCheckUpdates;
  String get languageLabel => 'Русский';

  Future<void> load([SharedPreferences? prefs]) async {
    _prefs = prefs ?? await SharedPreferences.getInstance();
    _themeMode = switch (_prefs?.getString(_kThemeMode)) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    _messageFontSize =
        (_prefs?.getDouble(_kMessageFontSize) ?? 15.0).clamp(13.0, 18.0);
    _bubbleRadius =
        (_prefs?.getDouble(_kBubbleRadius) ?? 20.0).clamp(10.0, 22.0);
    _showChatWallpaper = _prefs?.getBool(_kShowChatWallpaper) ?? true;
    _compactChatList = _prefs?.getBool(_kCompactChatList) ?? false;
    _showFolderBadges = _prefs?.getBool(_kShowFolderBadges) ?? true;
    _showNotificationPreview = _prefs?.getBool(_kShowNotificationPreview) ?? true;
    _powerSavingMode = _prefs?.getBool(_kPowerSavingMode) ?? false;
    _autoDownloadMedia = _prefs?.getBool(_kAutoDownloadMedia) ?? true;
    _autoCheckUpdates = _prefs?.getBool(_kAutoCheckUpdates) ?? true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    if (_themeMode == value) return;
    _themeMode = value;
    notifyListeners();
    final encoded = switch (value) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    };
    await _prefs?.setString(_kThemeMode, encoded);
  }

  Future<void> setMessageFontSize(double value) async {
    final clamped = value.clamp(13.0, 18.0);
    if ((_messageFontSize - clamped).abs() < 0.01) return;
    _messageFontSize = clamped;
    notifyListeners();
    await _prefs?.setDouble(_kMessageFontSize, clamped);
  }

  Future<void> setBubbleRadius(double value) async {
    final clamped = value.clamp(10.0, 22.0);
    if ((_bubbleRadius - clamped).abs() < 0.01) return;
    _bubbleRadius = clamped;
    notifyListeners();
    await _prefs?.setDouble(_kBubbleRadius, clamped);
  }

  Future<void> setShowChatWallpaper(bool value) async {
    if (_showChatWallpaper == value) return;
    _showChatWallpaper = value;
    notifyListeners();
    await _prefs?.setBool(_kShowChatWallpaper, value);
  }

  Future<void> setCompactChatList(bool value) async {
    if (_compactChatList == value) return;
    _compactChatList = value;
    notifyListeners();
    await _prefs?.setBool(_kCompactChatList, value);
  }

  Future<void> setShowFolderBadges(bool value) async {
    if (_showFolderBadges == value) return;
    _showFolderBadges = value;
    notifyListeners();
    await _prefs?.setBool(_kShowFolderBadges, value);
  }

  Future<void> setShowNotificationPreview(bool value) async {
    if (_showNotificationPreview == value) return;
    _showNotificationPreview = value;
    notifyListeners();
    await _prefs?.setBool(_kShowNotificationPreview, value);
  }

  Future<void> setPowerSavingMode(bool value) async {
    if (_powerSavingMode == value) return;
    _powerSavingMode = value;
    notifyListeners();
    await _prefs?.setBool(_kPowerSavingMode, value);
  }

  Future<void> setAutoDownloadMedia(bool value) async {
    if (_autoDownloadMedia == value) return;
    _autoDownloadMedia = value;
    notifyListeners();
    await _prefs?.setBool(_kAutoDownloadMedia, value);
  }

  Future<void> setAutoCheckUpdates(bool value) async {
    if (_autoCheckUpdates == value) return;
    _autoCheckUpdates = value;
    notifyListeners();
    await _prefs?.setBool(_kAutoCheckUpdates, value);
  }
}

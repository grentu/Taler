import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'backend/taler_client.dart';
import 'core/privacy/privacy_firewall.dart';
import 'core/privacy/privacy_settings.dart';
import 'core/privacy/spoofing_service.dart';
import 'core/storage/local_store.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/taler_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TalerApp());
}

/// Корневой виджет мессенджера Taler.
class TalerApp extends StatefulWidget {
  final TalerClient? client;

  const TalerApp({super.key, this.client});

  @override
  State<TalerApp> createState() => _TalerAppState();
}

class _TalerAppState extends State<TalerApp> with WidgetsBindingObserver {
  late final TalerClient _client;
  late final bool _ownsClient;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.client != null) {
      _client = widget.client!;
      _ownsClient = false;
      _initialized = true;
    } else {
      _ownsClient = true;
      _client = TalerClient(
        privacySettings: PrivacySettings(),
        spoofingService: SpoofingService(),
        auditLog: WireAuditLog(),
        store: LocalStore(),
      );
      unawaited(_boot());
    }
  }

  Future<void> _boot() async {
    await _client.initialize();
    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _client.wakeUp();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsClient) {
      _client.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _client.appPreferences,
      builder: (context, _) {
        final themeMode = _client.appPreferences.themeMode;
        return MaterialApp(
          title: 'Taler',
          debugShowCheckedModeBanner: false,
          theme: TalerTheme.light(),
          darkTheme: TalerTheme.dark(),
          themeMode: themeMode,
          home: !_initialized
              ? const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                )
              : ListenableBuilder(
                  listenable: _client,
                  builder: (context, _) {
                    if (!_client.isAuthenticated) {
                      return AuthScreen(client: _client);
                    }
                    return HomeScreen(
                      client: _client,
                      themeMode: themeMode,
                      onThemeModeChanged: (next) =>
                          unawaited(_client.appPreferences.setThemeMode(next)),
                    );
                  },
                ),
        );
      },
    );
  }
}

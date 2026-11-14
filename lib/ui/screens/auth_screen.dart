import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/privacy/spoof_profile.dart';
import '../../core/transport/taler_session.dart';
import '../icons/taler_icon.dart';
import '../theme/taler_theme.dart';
import '../widgets/taler_logo.dart';

enum _AuthTab { phone, token, demo }

enum _PhoneStep { enterPhone, enterOtp, enter2fa, enterProfile }

class _CountryOption {
  final String name;
  final String code;

  const _CountryOption(this.name, this.code);
}

/// Экран входа: телефон и SMS-код, вход по токену или демо-режим.
class AuthScreen extends StatefulWidget {
  final TalerClient client;

  const AuthScreen({super.key, required this.client});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const List<_CountryOption> _countries = [
    _CountryOption('Россия', '+7'),
    _CountryOption('Беларусь', '+375'),
    _CountryOption('Казахстан', '+7'),
    _CountryOption('Узбекистан', '+998'),
    _CountryOption('Армения', '+374'),
    _CountryOption('Кыргызстан', '+996'),
    _CountryOption('Германия', '+49'),
    _CountryOption('США', '+1'),
  ];

  /// Через сколько секунд ожидания показать подсказку про медленный ответ.
  static const int _slowHintAfter = 8;

  _AuthTab _tab = _AuthTab.phone;
  _PhoneStep _phoneStep = _PhoneStep.enterPhone;
  _CountryOption _selectedCountry = _countries.first;
  bool _deviceDetailsExpanded = false;

  final _phoneCtrl = TextEditingController(text: '+7 ');
  final _otpCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();

  String? _tempToken;
  String? _twoFaTrackId;
  String? _twoFaHint;
  String? _registerToken;
  String? _localError;
  bool _loginRestricted = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  int _waitSeconds = 0;
  Timer? _waitTimer;

  @override
  void initState() {
    super.initState();
    // Поднимаем соединение заранее, пока пользователь вводит номер.
    widget.client.warmUpConnection();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _waitTimer?.cancel();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _passwordCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _selectCountry(_CountryOption country) {
    final rawDigits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    final oldCodeDigits = _selectedCountry.code.replaceAll('+', '');
    final subscriberDigits = rawDigits.startsWith(oldCodeDigits)
        ? rawDigits.substring(oldCodeDigits.length)
        : rawDigits;

    setState(() {
      _selectedCountry = country;
      _phoneCtrl.text = subscriberDigits.isEmpty
          ? '${country.code} '
          : '${country.code} $subscriberDigits';
      _phoneCtrl.selection = TextSelection.collapsed(
        offset: _phoneCtrl.text.length,
      );
    });
  }

  void _startResendCooldown([int seconds = 30]) {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  /// Считает секунды ожидания ответа, чтобы честно показывать, что происходит.
  Future<T> _track<T>(Future<T> Function() action) async {
    _waitTimer?.cancel();
    setState(() => _waitSeconds = 0);
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _waitSeconds += 1);
    });
    try {
      return await action();
    } finally {
      _waitTimer?.cancel();
      _waitTimer = null;
      if (mounted) setState(() => _waitSeconds = 0);
    }
  }

  void _showError(Object error) {
    final latestToken = widget.client.lastTempToken;
    setState(() {
      if (latestToken != null && latestToken.isNotEmpty) {
        _tempToken = latestToken;
      }
      if (TalerClient.isNo2faError(error)) {
        _loginRestricted = true;
        _localError = null;
      } else {
        _localError = _humanError(error);
      }
    });
  }

  static String _humanError(Object error) {
    final text = error.toString();
    final lower = text.toLowerCase();
    if (lower.contains('таймаут') || lower.contains('timeout')) {
      return 'Сервер MAX не ответил вовремя. Проверьте интернет и попробуйте ещё раз';
    }
    if (lower.contains('socketexception') ||
        lower.contains('нет подключения') ||
        lower.contains('handshake')) {
      return 'Не удалось подключиться к серверу MAX. Проверьте интернет или включите веб-шлюз в настройках устройства';
    }
    final colon = text.indexOf(': ');
    if (colon > 0 && text.substring(0, colon).contains('.')) {
      return text.substring(colon + 2);
    }
    return text;
  }

  Future<void> _submitPhone() async {
    setState(() {
      _localError = null;
      _loginRestricted = false;
    });
    try {
      switch (_phoneStep) {
        case _PhoneStep.enterPhone:
          final token = await _track(
            () => widget.client.requestOtp(_phoneCtrl.text),
          );
          if (!mounted) return;
          setState(() {
            _tempToken = token;
            _otpCtrl.clear();
            _phoneStep = _PhoneStep.enterOtp;
          });
          _startResendCooldown();
        case _PhoneStep.enterOtp:
          final token = widget.client.lastTempToken ?? _tempToken ?? '';
          final outcome = await _track(
            () => widget.client.verifyOtp(token, _otpCtrl.text),
          );
          if (!mounted) return;
          _resendTimer?.cancel();
          if (outcome.status == OtpVerifyStatus.needs2fa) {
            setState(() {
              _twoFaTrackId = outcome.trackId;
              _twoFaHint = outcome.hint;
              _phoneStep = _PhoneStep.enter2fa;
            });
          } else if (outcome.status == OtpVerifyStatus.needsRegistration) {
            setState(() {
              _registerToken = outcome.registerToken;
              _phoneStep = _PhoneStep.enterProfile;
            });
          }
        case _PhoneStep.enter2fa:
          await _track(
            () => widget.client.verify2faPassword(
              _twoFaTrackId ?? '',
              _passwordCtrl.text,
            ),
          );
        case _PhoneStep.enterProfile:
          await _track(
            () => widget.client.completeRegistration(
              _registerToken ?? '',
              _firstNameCtrl.text,
              lastName: _lastNameCtrl.text,
            ),
          );
      }
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _localError = null;
      _loginRestricted = false;
    });
    try {
      final token = await _track(
        () => widget.client.resendOtp(_phoneCtrl.text),
      );
      if (!mounted) return;
      setState(() {
        _tempToken = token;
        _otpCtrl.clear();
        _phoneStep = _PhoneStep.enterOtp;
      });
      _startResendCooldown();
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    }
  }

  Future<void> _submitToken() async {
    setState(() => _localError = null);
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      setState(() => _localError = 'Вставьте токен сессии MAX');
      return;
    }
    try {
      await _track(() => widget.client.loginWithToken(token));
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    }
  }

  void _backToPhone() {
    _resendTimer?.cancel();
    setState(() {
      _localError = null;
      _loginRestricted = false;
      _resendSeconds = 0;
      _otpCtrl.clear();
      _phoneStep = _PhoneStep.enterPhone;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final client = widget.client;

    return Scaffold(
      backgroundColor: p.bg,
      body: ListenableBuilder(
        listenable: Listenable.merge([
          client,
          client.spoofingService,
          client.privacySettings,
        ]),
        builder: (context, _) {
          final connection = client.connectionState;
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 880;
              final form = _buildFormColumn(p, connection, wide);
              if (!wide) {
                return SafeArea(child: form);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: (constraints.maxWidth * 0.42).clamp(380.0, 560.0),
                    child: const _BrandPanel(),
                  ),
                  Expanded(child: SafeArea(child: form)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFormColumn(
    TalerPalette p,
    TalerConnectionState connection,
    bool wide,
  ) {
    final busy = widget.client.isLoading;
    final err = _localError ?? widget.client.errorMessage;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: wide ? 48 : 20,
          vertical: wide ? 48 : 32,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: TalerLogo(size: 48),
                ),
                const SizedBox(height: 24),
              ],
              Text(
                _title(),
                style: TextStyle(
                  fontSize: 24,
                  height: 32 / 24,
                  fontWeight: FontWeight.w500,
                  color: p.fg,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _subtitle(),
                style: TextStyle(fontSize: 14, height: 20 / 14, color: p.fg2),
              ),
              const SizedBox(height: 24),
              TalerSlidingPillSwitch<_AuthTab>(
                value: _tab,
                height: 32,
                onChanged: busy
                    ? null
                    : (next) {
                        setState(() {
                          _tab = next;
                          _localError = null;
                          _loginRestricted = false;
                        });
                        widget.client.clearError();
                      },
                items: const [
                  TalerSegment(
                    value: _AuthTab.phone,
                    label: 'Телефон',
                    icon: TalerIcons.phone,
                  ),
                  TalerSegment(
                    value: _AuthTab.token,
                    label: 'Токен',
                    icon: TalerIcons.key,
                  ),
                  TalerSegment(
                    value: _AuthTab.demo,
                    label: 'Демо',
                    icon: TalerIcons.playCircle,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: TalerTheme.easeOutCurve,
                switchOutCurve: TalerTheme.easeOutCurve,
                child: KeyedSubtree(
                  key: ValueKey('auth_${_tab.name}_${_phoneStep.name}'),
                  child: switch (_tab) {
                    _AuthTab.phone => _buildPhoneForm(p, busy, err),
                    _AuthTab.token => _buildTokenForm(p, busy),
                    _AuthTab.demo => _buildDemoForm(p, busy),
                  },
                ),
              ),
              if (busy && _tab != _AuthTab.demo) ...[
                const SizedBox(height: 12),
                _WaitStatus(
                  connection: connection,
                  seconds: _waitSeconds,
                  slowAfter: _slowHintAfter,
                ),
              ],
              if (_loginRestricted && _tab == _AuthTab.phone) ...[
                const SizedBox(height: 16),
                _LoginRestrictedPanel(
                  busy: busy,
                  onResend: _resendOtp,
                  onUseToken: () => setState(() {
                    _tab = _AuthTab.token;
                    _loginRestricted = false;
                  }),
                ),
              ] else if (err != null && err.isNotEmpty) ...[
                const SizedBox(height: 16),
                _ErrorNote(message: err),
              ],
              if (_tab != _AuthTab.demo) ...[
                const SizedBox(height: 32),
                _buildDevicePanel(p, busy, connection),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _title() {
    if (_tab == _AuthTab.token) return 'Вход по токену';
    if (_tab == _AuthTab.demo) return 'Демо-режим';
    return switch (_phoneStep) {
      _PhoneStep.enterPhone => 'Вход в Taler',
      _PhoneStep.enterOtp => 'Код из SMS',
      _PhoneStep.enter2fa => 'Пароль для входа',
      _PhoneStep.enterProfile => 'Новый профиль',
    };
  }

  String _subtitle() {
    if (_tab == _AuthTab.token) {
      return 'Готовый токен сессии MAX, без повторного SMS';
    }
    if (_tab == _AuthTab.demo) {
      return 'Песочница с примерами чатов. Ничего не отправляется в сеть';
    }
    return switch (_phoneStep) {
      _PhoneStep.enterPhone => 'Номер телефона, привязанный к аккаунту MAX',
      _PhoneStep.enterOtp => 'Отправили на ${_phoneCtrl.text.trim()}',
      _PhoneStep.enter2fa => 'Тот, что задан в MAX в разделе «Пароль для входа»',
      _PhoneStep.enterProfile => 'Номер ещё не зарегистрирован в MAX',
    };
  }

  Widget _buildPhoneForm(TalerPalette p, bool busy, String? err) {
    final ctaLabel = switch (_phoneStep) {
      _PhoneStep.enterPhone => 'Получить код',
      _PhoneStep.enterOtp => 'Войти',
      _PhoneStep.enter2fa => 'Войти',
      _PhoneStep.enterProfile => 'Создать профиль',
    };
    final lowerErr = (err ?? '').toLowerCase();
    final hasExpiredErr = lowerErr.contains('expired') ||
        lowerErr.contains('attempt.limit') ||
        lowerErr.contains('истёк') ||
        lowerErr.contains('лимит');
    final canResend = !busy && (_resendSeconds == 0 || hasExpiredErr);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_phoneStep == _PhoneStep.enterPhone) ...[
          const _FieldLabel('Страна'),
          PopupMenuButton<_CountryOption>(
            enabled: !busy,
            color: p.bg3,
            tooltip: 'Выбрать страну',
            onSelected: _selectCountry,
            itemBuilder: (context) => [
              for (final c in _countries)
                PopupMenuItem(
                  value: c,
                  height: 36,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.name,
                          style: TextStyle(fontSize: 14, color: p.fg),
                        ),
                      ),
                      Text(
                        c.code,
                        style: TalerTheme.monoStyle(size: 12, color: p.fg2),
                      ),
                    ],
                  ),
                ),
            ],
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: p.bg3,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.line),
              ),
              child: Row(
                children: [
                  TalerIcon(TalerIcons.globe, size: 18, color: p.fg3),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedCountry.name,
                      style: TextStyle(fontSize: 14, color: p.fg),
                    ),
                  ),
                  Text(
                    _selectedCountry.code,
                    style: TalerTheme.monoStyle(size: 12, color: p.fg2),
                  ),
                  const SizedBox(width: 8),
                  TalerIcon(TalerIcons.chevronDown, size: 16, color: p.fg3),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Номер телефона'),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            enabled: !busy,
            autofocus: true,
            onSubmitted: (_) => _submitPhone(),
            style: TalerTheme.tabularStyle(size: 15, color: p.fg),
            decoration: InputDecoration(
              hintText: '+7 999 000 00 00',
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: TalerIcon(TalerIcons.phone, size: 18, color: p.fg3),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 38),
            ),
          ),
        ] else if (_phoneStep == _PhoneStep.enterOtp) ...[
          const _FieldLabel('Код'),
          TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            enabled: !busy,
            autofocus: true,
            onSubmitted: (_) => _submitPhone(),
            style: TalerTheme.monoStyle(size: 18, color: p.fg).copyWith(
              letterSpacing: 4,
            ),
            decoration: InputDecoration(
              hintText: '000000',
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: TalerIcon(TalerIcons.messageCode, size: 18, color: p.fg3),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 38),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _QuietLink(
                icon: TalerIcons.arrowLeft,
                label: 'Другой номер',
                onTap: busy ? null : _backToPhone,
              ),
              const Spacer(),
              _QuietLink(
                icon: TalerIcons.refresh,
                label: canResend
                    ? 'Отправить код снова'
                    : 'Повтор через $_resendSeconds с',
                onTap: canResend ? _resendOtp : null,
              ),
            ],
          ),
        ] else if (_phoneStep == _PhoneStep.enter2fa) ...[
          if (_twoFaHint != null && _twoFaHint!.isNotEmpty) ...[
            Text(
              'Подсказка: $_twoFaHint',
              style: TextStyle(fontSize: 13, height: 20 / 13, color: p.fg2),
            ),
            const SizedBox(height: 12),
          ],
          const _FieldLabel('Пароль'),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            enabled: !busy,
            autofocus: true,
            onSubmitted: (_) => _submitPhone(),
            decoration: InputDecoration(
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: TalerIcon(TalerIcons.lock, size: 18, color: p.fg3),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 38),
            ),
          ),
        ] else ...[
          const _FieldLabel('Имя'),
          TextField(
            controller: _firstNameCtrl,
            enabled: !busy,
            autofocus: true,
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Фамилия'),
          TextField(
            controller: _lastNameCtrl,
            enabled: !busy,
          ),
        ],
        const SizedBox(height: 20),
        TalerTactileButton(
          label: ctaLabel,
          variant: TalerButtonVariant.primary,
          loading: busy,
          onPressed: busy ? null : _submitPhone,
        ),
      ],
    );
  }

  Widget _buildTokenForm(TalerPalette p, bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel('Токен сессии'),
        TextField(
          controller: _tokenCtrl,
          minLines: 3,
          maxLines: 4,
          enabled: !busy,
          style: TalerTheme.monoStyle(size: 12, color: p.fg),
          decoration: const InputDecoration(
            hintText: 'Вставьте токен из другого клиента MAX',
          ),
        ),
        const SizedBox(height: 20),
        TalerTactileButton(
          label: 'Войти',
          variant: TalerButtonVariant.primary,
          loading: busy,
          onPressed: busy ? null : _submitToken,
        ),
      ],
    );
  }

  Widget _buildDemoForm(TalerPalette p, bool busy) {
    const features = [
      'Примеры диалогов и групп',
      'Сохранение удалённых сообщений',
      'История правок',
      'Журнал сетевых пакетов',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in features)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                TalerIcon(TalerIcons.check, size: 16, color: p.fg3),
                const SizedBox(width: 10),
                Text(f, style: TextStyle(fontSize: 14, color: p.fg2)),
              ],
            ),
          ),
        const SizedBox(height: 12),
        TalerTactileButton(
          label: 'Открыть демо',
          variant: TalerButtonVariant.primary,
          loading: busy,
          onPressed: busy ? null : () => widget.client.enterDemoMode(),
        ),
      ],
    );
  }

  Widget _buildDevicePanel(
    TalerPalette p,
    bool busy,
    TalerConnectionState connection,
  ) {
    final client = widget.client;
    final spoofOn = client.privacySettings.spoofingEnabled;
    final SpoofProfile profile = spoofOn
        ? client.spoofingService.activeProfile
        : client.spoofingService.nativeProfile;
    final canEdit = !busy && _phoneStep == _PhoneStep.enterPhone;

    return Container(
      decoration: BoxDecoration(
        color: p.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Маскировка устройства',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: p.fg,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        spoofOn
                            ? '${profile.label} · ID меняется по кнопке'
                            : 'Постоянный ID, реальные язык и часовой пояс',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.fg2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: spoofOn,
                  onChanged: canEdit ? (v) => client.setLoginSpoofing(v) : null,
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: p.line),
          InkWell(
            onTap: () => setState(
              () => _deviceDetailsExpanded = !_deviceDetailsExpanded,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: [
                  _ConnectionDot(state: connection),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _connectionLabel(connection),
                      style: TextStyle(fontSize: 12, color: p.fg2),
                    ),
                  ),
                  TalerIcon(
                    _deviceDetailsExpanded
                        ? TalerIcons.chevronUp
                        : TalerIcons.chevronDown,
                    size: 16,
                    color: p.fg3,
                  ),
                ],
              ),
            ),
          ),
          if (_deviceDetailsExpanded) ...[
            Divider(height: 1, thickness: 1, color: p.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SpecLine(label: 'Device ID', value: profile.deviceId),
                  const SizedBox(height: 6),
                  _SpecLine(
                    label: 'Язык · пояс',
                    value: '${profile.locale} · ${profile.timezone}',
                  ),
                  const SizedBox(height: 6),
                  const _SpecLine(
                    label: 'Блокируется',
                    value: 'LOG #5 · DEBUG #2 · BANNERS #302 · SUGGEST #300',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Веб-шлюз',
                              style: TextStyle(fontSize: 13, color: p.fg),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Подключаться как веб-версия MAX, если TLS недоступен',
                              style: TextStyle(fontSize: 12, color: p.fg3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Switch(
                        value: client.preferWebGateway,
                        onChanged: canEdit
                            ? (v) => client.setPreferWebGateway(v)
                            : null,
                      ),
                    ],
                  ),
                  if (spoofOn) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TalerTactileButton(
                        label: 'Новое устройство',
                        icon: TalerIcons.shuffle,
                        compact: true,
                        onPressed: canEdit
                            ? () => client.spoofingService.randomizeAll()
                            : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _connectionLabel(TalerConnectionState state) {
    final session = widget.client.session;
    return switch (state) {
      TalerConnectionState.online => session.transport == TalerTransport.webSocket
          ? 'Подключено к MAX через веб-шлюз'
          : 'Подключено к MAX',
      TalerConnectionState.connecting ||
      TalerConnectionState.connected => 'Подключение к MAX',
      TalerConnectionState.disconnected => 'Нет соединения с MAX',
    };
  }
}

/// Левая колонка на широких экранах: что это за клиент и что он блокирует.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  static const _blocked = [
    ('#5', 'LOG', 'журнал действий'),
    ('#2', 'DEBUG', 'отладочные отчёты'),
    ('#302', 'BANNERS_SYNC', 'рекламные баннеры'),
    ('#300', 'CHAT_SUGGEST', 'рекомендации'),
    ('#292', 'NOTIF_BANNERS', 'входящая реклама'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Container(
      decoration: BoxDecoration(
        color: p.settingsBg,
        border: Border(right: BorderSide(color: p.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(48, 40, 48, 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 72).clamp(0.0, double.infinity),
            ),
            child: IntrinsicHeight(child: _content(p)),
          ),
        ),
      ),
    );
  }

  Widget _content(TalerPalette p) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TalerLogo(size: 32),
              const SizedBox(width: 12),
              Text(
                'Taler',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: p.fg,
                ),
              ),
            ],
          ),
          const Spacer(flex: 2),
          Text(
            'MAX без телеметрии и рекламы',
            style: TextStyle(
              fontSize: 32,
              height: 40 / 32,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.6,
              color: p.fg,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Служебные пакеты аналитики отбрасываются до отправки, а реальные идентификаторы устройства не читаются',
            style: TextStyle(fontSize: 15, height: 24 / 15, color: p.fg2),
          ),
          const SizedBox(height: 40),
          Text(
            'Блокируется всегда',
            style: TextStyle(fontSize: 13, color: p.fg3),
          ),
          const SizedBox(height: 8),
          for (final (code, name, meaning) in _blocked)
            SizedBox(
              height: 32,
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      code,
                      style: TalerTheme.monoStyle(size: 12, color: p.accent),
                    ),
                  ),
                  SizedBox(
                    width: 136,
                    child: Text(
                      name,
                      style: TalerTheme.monoStyle(size: 12, color: p.fg),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      meaning,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: p.fg3),
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(flex: 3),
          Text(
            'Открытый исходный код · github.com/grentu/Taler',
            style: TalerTheme.monoStyle(size: 12, color: p.fg3),
          ),
        ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: p.fg2),
      ),
    );
  }
}

class _QuietLink extends StatelessWidget {
  final TalerIconData icon;
  final String label;
  final VoidCallback? onTap;

  const _QuietLink({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final color = onTap == null ? p.fg3 : p.fg2;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TalerIcon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TalerTheme.tabularStyle(size: 13, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  final String message;

  const _ErrorNote({required this.message});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.dangerSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.dangerLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TalerIcon(TalerIcons.alertCircle, size: 16, color: p.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, height: 20 / 13, color: p.fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Объяснение ограничения сервера MAX "error.profile.active.session.no2fa".
class _LoginRestrictedPanel extends StatelessWidget {
  final bool busy;
  final VoidCallback onResend;
  final VoidCallback onUseToken;

  const _LoginRestrictedPanel({
    required this.busy,
    required this.onResend,
    required this.onUseToken,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    const steps = [
      'Откройте MAX на телефоне, где вы уже вошли',
      'В профиле найдите «Приватность» или «Безопасность» и включите «Пароль для входа». Пункт появляется, если вы вошли на телефоне больше суток назад',
      'Вернитесь сюда и запросите код снова. После кода Taler спросит этот пароль',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.warningSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.warningLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TalerIcon(TalerIcons.shieldOff, size: 18, color: p.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'MAX не пускает новое устройство',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: p.fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'У аккаунта есть активная сессия, а пароль для входа не задан. В таком случае сервер MAX отклоняет вход с любого нового устройства, маскировка на это не влияет.',
            style: TextStyle(fontSize: 13, height: 20 / 13, color: p.fg2),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      '${i + 1}',
                      style: TalerTheme.monoStyle(size: 12, color: p.fg3),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: TextStyle(fontSize: 13, height: 20 / 13, color: p.fg),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              TalerTactileButton(
                label: 'Запросить код снова',
                icon: TalerIcons.refresh,
                compact: true,
                variant: TalerButtonVariant.primary,
                onPressed: busy ? null : onResend,
              ),
              const SizedBox(width: 8),
              TalerTactileButton(
                label: 'Войти по токену',
                compact: true,
                onPressed: busy ? null : onUseToken,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Строка под кнопкой: что именно сейчас происходит и сколько это длится.
class _WaitStatus extends StatelessWidget {
  final TalerConnectionState connection;
  final int seconds;
  final int slowAfter;

  const _WaitStatus({
    required this.connection,
    required this.seconds,
    required this.slowAfter,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final phase = connection == TalerConnectionState.online
        ? 'Ждём ответ сервера'
        : 'Подключаемся к MAX';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$phase · $seconds с',
          style: TalerTheme.tabularStyle(size: 12, color: p.fg3),
        ),
        if (seconds >= slowAfter) ...[
          const SizedBox(height: 4),
          Text(
            'Долго нет ответа. Если так каждый раз, включите веб-шлюз в блоке ниже',
            style: TextStyle(fontSize: 12, height: 16 / 12, color: p.fg3),
          ),
        ],
      ],
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  final TalerConnectionState state;

  const _ConnectionDot({required this.state});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final color = switch (state) {
      TalerConnectionState.online => p.statusLive,
      TalerConnectionState.disconnected => p.fg3,
      _ => p.warning,
    };
    return TalerStatusDot(color: color, size: 6);
  }
}

class _SpecLine extends StatelessWidget {
  final String label;
  final String value;

  const _SpecLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: TextStyle(fontSize: 12, color: p.fg3)),
        ),
        Expanded(
          child: Text(
            value,
            style: TalerTheme.monoStyle(size: 12, color: p.fg2),
          ),
        ),
      ],
    );
  }
}

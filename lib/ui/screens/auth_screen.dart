import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../../core/privacy/spoof_profile.dart';
import '../theme/taler_theme.dart';
import '../widgets/taler_logo.dart';

enum _AuthTab { phone, token, demo }

enum _PhoneStep { enterPhone, enterOtp, enter2fa, enterProfile }

class _CountryOption {
  final String name;
  final String code;

  const _CountryOption(this.name, this.code);
}

/// Экран авторизации Taler в стиле Telegram Desktop / Telegram Mobile.
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

  _AuthTab _tab = _AuthTab.phone;
  _PhoneStep _phoneStep = _PhoneStep.enterPhone;
  _CountryOption _selectedCountry = _countries.first;
  bool _spoofDetailsExpanded = false;

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

  @override
  void dispose() {
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

  Future<void> _submitPhone() async {
    setState(() => _localError = null);
    try {
      switch (_phoneStep) {
        case _PhoneStep.enterPhone:
          final token = await widget.client.requestOtp(_phoneCtrl.text);
          if (!mounted) return;
          setState(() {
            _tempToken = token;
            _phoneStep = _PhoneStep.enterOtp;
          });
        case _PhoneStep.enterOtp:
          final outcome = await widget.client.verifyOtp(
            _tempToken ?? '',
            _otpCtrl.text,
          );
          if (!mounted) return;
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
          await widget.client.verify2faPassword(
            _twoFaTrackId ?? '',
            _passwordCtrl.text,
          );
        case _PhoneStep.enterProfile:
          await widget.client.completeRegistration(
            _registerToken ?? '',
            _firstNameCtrl.text,
            lastName: _lastNameCtrl.text,
          );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _localError = e.toString());
    }
  }

  Future<void> _submitToken() async {
    setState(() => _localError = null);
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      setState(() => _localError = 'Укажите токен сессии MAX');
      return;
    }
    try {
      await widget.client.loginWithToken(token);
    } catch (e) {
      if (!mounted) return;
      setState(() => _localError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final spoof = widget.client.spoofingService;

    return Scaffold(
      backgroundColor: p.settingsBg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.client, spoof]),
          builder: (context, _) {
            final busy = widget.client.isLoading;
            final profile = spoof.activeProfile;
            final err = _localError ?? widget.client.errorMessage;

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 392),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(
                        child: TalerLogo(size: 92, showShieldBadge: true),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Вход в Taler',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                          color: p.fg,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Независимый клиент MAX без телеметрии,\nрекламных баннеров и сбора метаданных.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: p.fg2,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Карточка авторизации в стиле Telegram
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: p.bg2,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: p.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TalerSlidingPillSwitch<_AuthTab>(
                              value: _tab,
                              height: 32,
                              pillShape: true,
                              onChanged: busy
                                  ? null
                                  : (next) {
                                      setState(() {
                                        _tab = next;
                                        _localError = null;
                                      });
                                    },
                              items: const [
                                TalerSegment(
                                  value: _AuthTab.phone,
                                  label: 'Телефон',
                                  icon: Icons.phone_outlined,
                                ),
                                TalerSegment(
                                  value: _AuthTab.token,
                                  label: 'Токен',
                                  icon: Icons.key_outlined,
                                ),
                                TalerSegment(
                                  value: _AuthTab.demo,
                                  label: 'Демо',
                                  icon: Icons.play_circle_outline_rounded,
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              switchInCurve: TalerTheme.easeOutCurve,
                              child: KeyedSubtree(
                                key: ValueKey(
                                  'auth_${_tab.name}_${_phoneStep.name}',
                                ),
                                child: switch (_tab) {
                                  _AuthTab.phone => _buildPhoneForm(p, busy),
                                  _AuthTab.token => _buildTokenForm(p, busy),
                                  _AuthTab.demo => _buildDemoForm(p, busy),
                                },
                              ),
                            ),
                            if (err != null && err.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: p.dangerSurface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: p.dangerLine),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.error_outline_rounded,
                                      size: 16,
                                      color: p.danger,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        err,
                                        style: TextStyle(
                                          color: p.danger,
                                          fontSize: 12.5,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Компактная плашка маскировки устройства под формой входа
                      _buildSpoofBanner(p, profile, busy),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPhoneForm(TalerPalette p, bool busy) {
    final ctaLabel = switch (_phoneStep) {
      _PhoneStep.enterPhone => 'Запросить код',
      _PhoneStep.enterOtp => 'Подтвердить код',
      _PhoneStep.enter2fa => 'Войти с паролем',
      _PhoneStep.enterProfile => 'Создать профиль',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_phoneStep == _PhoneStep.enterPhone) ...[
          // Выбор страны как в Telegram
          PopupMenuButton<_CountryOption>(
            enabled: !busy,
            color: p.bg3,
            onSelected: _selectCountry,
            itemBuilder: (context) => [
              for (final c in _countries)
                PopupMenuItem(
                  value: c,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.name,
                          style: TextStyle(fontSize: 13.5, color: p.fg),
                        ),
                      ),
                      Text(
                        c.code,
                        style: TalerTheme.monoStyle(
                          size: 12.5,
                          color: p.accent,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: p.bg3,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.line2),
              ),
              child: Row(
                children: [
                  Icon(Icons.public_rounded, size: 18, color: p.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_selectedCountry.name} (${_selectedCountry.code})',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: p.fg,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: p.fg2,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            enabled: !busy,
            onSubmitted: (_) => _submitPhone(),
            style: TalerTheme.tabularStyle(
              size: 15,
              weight: FontWeight.w500,
              color: p.fg,
            ),
            decoration: const InputDecoration(
              labelText: 'Номер телефона',
              hintText: '+7 999 000 00 00',
              prefixIcon: Icon(Icons.phone_outlined, size: 18),
            ),
          ),
        ] else if (_phoneStep == _PhoneStep.enterOtp) ...[
          Text(
            'Мы отправили код подтверждения на ${_phoneCtrl.text.trim()}',
            style: TextStyle(fontSize: 13, color: p.fg2, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            enabled: !busy,
            onSubmitted: (_) => _submitPhone(),
            style: TalerTheme.monoStyle(
              size: 16,
              weight: FontWeight.w600,
              color: p.fg,
            ),
            decoration: const InputDecoration(
              labelText: 'Код из SMS',
              prefixIcon: Icon(Icons.sms_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy
                  ? null
                  : () => setState(() {
                        _localError = null;
                        _phoneStep = _PhoneStep.enterPhone;
                      }),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Изменить номер'),
            ),
          ),
        ] else if (_phoneStep == _PhoneStep.enter2fa) ...[
          Text(
            'Облачный пароль 2FA',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: p.fg,
            ),
          ),
          if (_twoFaHint != null && _twoFaHint!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Подсказка: $_twoFaHint',
              style: TextStyle(fontSize: 13, color: p.fg2),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            enabled: !busy,
            onSubmitted: (_) => _submitPhone(),
            decoration: const InputDecoration(
              labelText: 'Пароль 2FA',
              prefixIcon: Icon(Icons.lock_outline, size: 18),
            ),
          ),
        ] else ...[
          Text(
            'Регистрация профиля',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: p.fg,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _firstNameCtrl,
            enabled: !busy,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lastNameCtrl,
            enabled: !busy,
            decoration: const InputDecoration(labelText: 'Фамилия'),
          ),
        ],
        const SizedBox(height: 16),
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
        Text(
          'Вход по готовому токену сессии MAX без повторного запроса SMS-кода.',
          style: TextStyle(fontSize: 13, color: p.fg2, height: 1.4),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _tokenCtrl,
          maxLines: 3,
          enabled: !busy,
          style: TalerTheme.monoStyle(size: 12, color: p.fg),
          decoration: const InputDecoration(
            labelText: 'Login Token',
            hintText: 'Вставьте токен сессии MAX',
          ),
        ),
        const SizedBox(height: 16),
        TalerTactileButton(
          label: 'Подключиться и войти',
          variant: TalerButtonVariant.primary,
          loading: busy,
          onPressed: busy ? null : _submitToken,
        ),
      ],
    );
  }

  Widget _buildDemoForm(TalerPalette p, bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Локальная песочница с примерами диалогов, перехватом удалений Anti-Delete, историей правок и инспектором пакетов Wire Audit.',
          style: TextStyle(fontSize: 13, color: p.fg2, height: 1.45),
        ),
        const SizedBox(height: 16),
        TalerTactileButton(
          label: 'Запустить демо-режим Taler',
          icon: Icons.play_arrow_rounded,
          variant: TalerButtonVariant.primary,
          loading: busy,
          onPressed: busy ? null : () => widget.client.enterDemoMode(),
        ),
      ],
    );
  }

  Widget _buildSpoofBanner(
    TalerPalette p,
    SpoofProfile profile,
    bool busy,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: p.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () =>
                setState(() => _spoofDetailsExpanded = !_spoofDetailsExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                children: [
                  TalerStatusDot(color: p.statusLive, size: 7),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Маскировка устройства активна',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: p.fg,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${profile.label} · ${profile.osVersion}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: p.fg2),
                        ),
                      ],
                    ),
                  ),
                  TalerTactileButton(
                    label: 'Сменить',
                    icon: Icons.shuffle_rounded,
                    compact: true,
                    onPressed: busy
                        ? null
                        : () => widget.client.spoofingService.randomizeAll(),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _spoofDetailsExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: p.fg2,
                  ),
                ],
              ),
            ),
          ),
          if (_spoofDetailsExpanded) ...[
            Divider(height: 1, color: p.line),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SpoofSpecLine(
                    label: 'Device ID',
                    value: '${profile.deviceId} · ${profile.timezone}',
                  ),
                  const SizedBox(height: 6),
                  _SpoofSpecLine(
                    label: 'Экран · Локаль',
                    value: '${profile.screen} · ${profile.locale}',
                  ),
                  const SizedBox(height: 6),
                  const _SpoofSpecLine(
                    label: 'Блокировка',
                    value: 'LOG #5 · DEBUG #2 · BANNERS #302 · SUGGEST #300',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpoofSpecLine extends StatelessWidget {
  final String label;
  final String value;

  const _SpoofSpecLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(fontSize: 11.5, color: p.fg3),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TalerTheme.monoStyle(size: 11.5, color: p.fg2),
          ),
        ),
      ],
    );
  }
}

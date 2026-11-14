import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../theme/taler_theme.dart';

enum _AuthTab { phone, token, demo }

enum _PhoneStep { enterPhone, enterOtp, enter2fa, enterProfile }

/// Экран входа в Taler: асимметричный split на ПК и компактный стек на телефоне.
class AuthScreen extends StatefulWidget {
  final TalerClient client;

  const AuthScreen({super.key, required this.client});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _AuthTab _tab = _AuthTab.phone;
  _PhoneStep _phoneStep = _PhoneStep.enterPhone;

  final _phoneCtrl = TextEditingController(text: '+7');
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
      backgroundColor: p.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 860;

            return ListenableBuilder(
              listenable: Listenable.merge([widget.client, spoof]),
              builder: (context, _) {
                final busy = widget.client.isLoading;

                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(isDesktop ? 32 : 20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isDesktop ? 980 : 480,
                      ),
                      child: isDesktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  flex: 11,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildBrandHeader(p, isDesktop: true),
                                      const SizedBox(height: 24),
                                      _buildSpoofShell(
                                        p,
                                        spoof.activeProfile,
                                        busy,
                                        compact: false,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 32),
                                SizedBox(
                                  width: 420,
                                  child: _buildAuthPanel(p, busy),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildBrandHeader(p, isDesktop: false),
                                const SizedBox(height: 16),
                                _buildAuthPanel(p, busy),
                                const SizedBox(height: 12),
                                _buildSpoofShell(
                                  p,
                                  spoof.activeProfile,
                                  busy,
                                  compact: true,
                                ),
                              ],
                            ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildBrandHeader(TalerPalette p, {required bool isDesktop}) {
    return Row(
      children: [
        Container(
          width: isDesktop ? 44 : 40,
          height: isDesktop ? 44 : 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.line2),
          ),
          child: Icon(
            Icons.shield_outlined,
            color: p.fg,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Taler',
                style: TextStyle(
                  fontSize: isDesktop ? 26 : 22,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.6,
                  height: 1.1,
                  color: p.fg,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Независимый клиент MAX без телеметрии',
                style: TextStyle(
                  fontSize: 13,
                  color: p.fg2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpoofShell(
    TalerPalette p,
    dynamic profile,
    bool busy, {
    required bool compact,
  }) {
    return TalerTableShell(
      title: 'Маскировка устройства активна',
      titleLeading: TalerStatusDot(color: p.statusLive, size: 6),
      trailing: TalerTactileButton(
        label: 'Сменить',
        icon: Icons.shuffle_rounded,
        compact: true,
        onPressed: busy ? null : () => widget.client.spoofingService.randomizeAll(),
      ),
      child: Column(
        children: [
          _SpecRow(
            label: 'Модель',
            value: '${profile.label}  ·  ${profile.osVersion}',
            compact: compact,
          ),
          Divider(height: 1, color: p.line),
          _SpecRow(
            label: 'Device ID',
            value: '${profile.deviceId}  ·  ${profile.timezone}',
            monospace: true,
            compact: compact,
          ),
          if (!compact) ...[
            Divider(height: 1, color: p.line),
            _SpecRow(
              label: 'Экран · Локаль',
              value: '${profile.screen}  ·  ${profile.locale}',
              monospace: true,
              compact: compact,
            ),
            Divider(height: 1, color: p.line),
            const _SpecRow(
              label: 'Блокировка',
              value: 'LOG #5 · DEBUG #2 · BANNERS #302 · SUGGEST #300',
              monospace: true,
              compact: false,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAuthPanel(TalerPalette p, bool busy) {
    final err = _localError ?? widget.client.errorMessage;

    return TalerTableShell(
      bodyPadding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TalerSlidingPillSwitch<_AuthTab>(
            value: _tab,
            height: 32,
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
                icon: Icons.science_outlined,
              ),
            ],
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: TalerTheme.easeOutCurve,
            child: KeyedSubtree(
              key: ValueKey('auth_${_tab.name}_${_phoneStep.name}'),
              child: switch (_tab) {
                _AuthTab.phone => _buildPhoneForm(p, busy),
                _AuthTab.token => _buildTokenForm(p, busy),
                _AuthTab.demo => _buildDemoForm(p, busy),
              },
            ),
          ),
          if (err != null && err.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.dangerSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.dangerLine),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: TalerStatusDot(color: p.danger, size: 6),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      err,
                      style: TextStyle(color: p.danger, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
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
          Text(
            'Вход по номеру телефона',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 15,
              color: p.fg,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Прямое подключение WebSocket MAX с подменой отпечатка устройства.',
            style: TextStyle(fontSize: 13, color: p.fg2, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            enabled: !busy,
            style: TalerTheme.tabularStyle(size: 14, color: p.fg),
            decoration: const InputDecoration(
              labelText: 'Номер телефона',
              hintText: '+7 999 000 00 00',
              prefixIcon: Icon(Icons.phone_outlined, size: 18),
            ),
          ),
        ] else if (_phoneStep == _PhoneStep.enterOtp) ...[
          Text(
            'Код подтверждения',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 15,
              color: p.fg,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            enabled: !busy,
            style: TalerTheme.monoStyle(size: 15, color: p.fg),
            decoration: const InputDecoration(
              labelText: 'Код из SMS',
              prefixIcon: Icon(Icons.sms_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TalerTactileButton(
              label: 'Изменить номер',
              compact: true,
              onPressed: busy
                  ? null
                  : () => setState(() => _phoneStep = _PhoneStep.enterPhone),
            ),
          ),
        ] else if (_phoneStep == _PhoneStep.enter2fa) ...[
          Text(
            'Облачный пароль',
            style: TextStyle(
              fontWeight: FontWeight.w500,
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
            decoration: const InputDecoration(
              labelText: 'Пароль 2FA',
              prefixIcon: Icon(Icons.lock_outline, size: 18),
            ),
          ),
        ] else ...[
          Text(
            'Новый профиль',
            style: TextStyle(
              fontWeight: FontWeight.w500,
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
          'Вход по токену сессии',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 15,
            color: p.fg,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Перенос существующей авторизации без повторного SMS-кода.',
          style: TextStyle(fontSize: 13, color: p.fg2, height: 1.4),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _tokenCtrl,
          maxLines: 3,
          enabled: !busy,
          style: TalerTheme.monoStyle(size: 12, color: p.fg),
          decoration: const InputDecoration(
            labelText: 'Login Token',
            hintText: 'Токен сессии MAX',
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
          'Локальный режим песочницы',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 15,
            color: p.fg,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Открывает диалоги, перехваченные сообщения Anti-Delete, историю правок и журнал Wire Audit без подключения к аккаунту.',
          style: TextStyle(fontSize: 13, color: p.fg2, height: 1.4),
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
}

class _SpecRow extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;
  final bool compact;

  const _SpecRow({
    required this.label,
    required this.value,
    this.monospace = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: compact ? 8 : 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: p.fg3),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: monospace
                  ? TalerTheme.monoStyle(size: 12, color: p.fg2)
                  : TextStyle(
                      fontSize: 12.5,
                      color: p.fg,
                      fontWeight: FontWeight.w400,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

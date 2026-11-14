import 'package:material_ui/material_ui.dart';

import '../../backend/taler_client.dart';
import '../theme/taler_theme.dart';

enum _AuthTab { phone, token, demo }

enum _PhoneStep { enterPhone, enterOtp, enter2fa, enterProfile }

/// Экран входа в Taler с выбором способа авторизации и предпросмотром спуфинга.
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
      setState(() => _localError = 'Вставьте токен сессии MAX');
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
    final theme = Theme.of(context);
    final spoof = widget.client.spoofingService;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListenableBuilder(
                listenable: Listenable.merge([widget.client, spoof]),
                builder: (context, _) {
                  final profile = spoof.activeProfile;
                  final busy = widget.client.isLoading;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Icon(
                              Icons.shield_outlined,
                              color: theme.colorScheme.primary,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Taler',
                                  style:
                                      theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Независимый клиент MAX без телеметрии',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Карточка предпросмотра спуфинга до первого подключения
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.verified_user_outlined,
                                    size: 18,
                                    color: TalerTheme.shieldGreen,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Маскировка устройства активна',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: busy
                                        ? null
                                        : () => spoof.randomizeAll(),
                                    icon: const Icon(Icons.shuffle, size: 16),
                                    label: const Text('Сменить'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${profile.label} • ${profile.osVersion}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'deviceId: ${profile.deviceId}  •  TZ: ${profile.timezone}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      SegmentedButton<_AuthTab>(
                        segments: const [
                          ButtonSegment(
                            value: _AuthTab.phone,
                            label: Text('Телефон'),
                            icon: Icon(Icons.phone_outlined, size: 18),
                          ),
                          ButtonSegment(
                            value: _AuthTab.token,
                            label: Text('Токен'),
                            icon: Icon(Icons.key_outlined, size: 18),
                          ),
                          ButtonSegment(
                            value: _AuthTab.demo,
                            label: Text('Демо'),
                            icon: Icon(Icons.science_outlined, size: 18),
                          ),
                        ],
                        selected: {_tab},
                        onSelectionChanged: busy
                            ? null
                            : (next) {
                                setState(() {
                                  _tab = next.first;
                                  _localError = null;
                                });
                              },
                      ),
                      const SizedBox(height: 16),

                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: switch (_tab) {
                            _AuthTab.phone => _buildPhoneForm(busy, theme),
                            _AuthTab.token => _buildTokenForm(busy, theme),
                            _AuthTab.demo => _buildDemoForm(busy, theme),
                          },
                        ),
                      ),

                      if (_localError != null ||
                          widget.client.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: TalerTheme.dangerRed.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color:
                                  TalerTheme.dangerRed.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            _localError ?? widget.client.errorMessage ?? '',
                            style: const TextStyle(
                              color: TalerTheme.dangerRed,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneForm(bool busy, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_phoneStep == _PhoneStep.enterPhone) ...[
          const Text(
            'Вход по номеру телефона MAX',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            'Хендшейк выполняется напрямую по протоколу WebSocket MAX со спуфингом устройства и блокировкой телеметрии.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Номер телефона',
              hintText: '+7 999 000 00 00',
              prefixIcon: Icon(Icons.phone_android_outlined),
            ),
          ),
        ] else if (_phoneStep == _PhoneStep.enterOtp) ...[
          const Text(
            'Введите код подтверждения',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Код из SMS / MAX',
              prefixIcon: Icon(Icons.sms_outlined),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() => _phoneStep = _PhoneStep.enterPhone),
              child: const Text('Изменить номер'),
            ),
          ),
        ] else if (_phoneStep == _PhoneStep.enter2fa) ...[
          const Text(
            'Облачный пароль (2FA)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          if (_twoFaHint != null && _twoFaHint!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Подсказка: $_twoFaHint',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Пароль 2FA',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
        ] else ...[
          const Text(
            'Завершение регистрации',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _firstNameCtrl,
            enabled: !busy,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _lastNameCtrl,
            enabled: !busy,
            decoration: const InputDecoration(labelText: 'Фамилия (необязательно)'),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : _submitPhone,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(switch (_phoneStep) {
                  _PhoneStep.enterPhone => 'Запросить код',
                  _PhoneStep.enterOtp => 'Подтвердить код',
                  _PhoneStep.enter2fa => 'Войти с паролем',
                  _PhoneStep.enterProfile => 'Создать профиль',
                }),
        ),
      ],
    );
  }

  Widget _buildTokenForm(bool busy, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Вход по готовому токену сессии',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 6),
        Text(
          'Подходит для переноса существующей авторизации без повторного SMS-кода.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _tokenCtrl,
          maxLines: 3,
          enabled: !busy,
          decoration: const InputDecoration(
            labelText: 'Login Token',
            hintText: 'Вставьте токен сессии...',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : _submitToken,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Подключиться и войти'),
        ),
      ],
    );
  }

  Widget _buildDemoForm(bool busy, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Локальный режим песочницы',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 6),
        Text(
          'Открывает интерфейс Taler с предзаполненными диалогами, перехваченными сообщениями Anti-Delete, историей правок и живым аудитом заблокированной телеметрии — без подключения к аккаунту.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : () => widget.client.enterDemoMode(),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Запустить демо-режим Taler'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

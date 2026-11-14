# Taler

**Taler** — открытый кроссплатформенный клиент (Android, iOS, Windows) для мессенджера MAX (`api.oneme.ru`), написанный полностью **с нуля** на Flutter/Dart без использования, модификации или патчинга проприетарных библиотек оригинального приложения.

Репозиторий организации **grentu**: `https://github.com/grentu/Taler`  
Протокол взаимодействия основан на открытой спецификации протокола MAX, реверсированной проектом [`KometTeam/Komet`](https://github.com/KometTeam/Komet).

---

## Зачем нужен Taler?

Официальный клиент MAX содержит обширные механизмы сбора телеметрии, аналитики событий, трекинга действий пользователя, рекламных баннеров и снятия аппаратных отпечатков устройства.

**Taler** решает эту проблему на уровне чистого протокола и локального сетевого экрана (**Privacy Firewall**):
- Весь транспортный слой (`WebSocket` + `10-байтовый бинарный фрейминг` + `MessagePack` + `LZ4`) реализован открытым кодом на чистом Dart в `lib/core/protocol/`.
- Все телеметрийные, отладочные и рекламные опкоды жёстко блокируются на уровне исходящего и входящего шлюза (`PrivacyFirewall`) до выхода пакетов в сеть.
- Клиент никогда не читает реальные аппаратные идентификаторы устройства (`deviceId`, IMEI, серийный номер, MAC и т.д.).

---

## Заблокированные опкоды (Telemetry & Ads Kill Switch)

| Opcode | Имя | Направление | Действие в Taler |
| :--- | :--- | :--- | :--- |
| `2` | `DEBUG` | Outgoing | **Жёстко заблокирован** (`AuditVerdict.blockedTelemetry`) |
| `5` | `LOG` | Outgoing | **Жёстко заблокирован** (`AuditVerdict.blockedTelemetry`) |
| `300` | `CHAT_SUGGEST` | Outgoing | **Жёстко заблокирован** (аналитика/рекомендации) |
| `302` | `BANNERS_SYNC` | Outgoing | **Жёстко заблокирован** (синхронизация баннеров) |
| `292` | `NOTIF_BANNERS` | Incoming | **Жёстко отбрасывается** на входе |

Дополнительно в **Режиме Призрака (Ghost Mode)** опционально блокируются:
- `65` (`MSG_TYPING`) — отключает отправку статуса «печатает...»;
- `50` (`CHAT_MARK` / `READ_MESSAGE`) — **Anti-Read**, позволяет читать сообщения, не отправляя отчёт о прочтении на сервер;
- `interactive: false` в `PING` (`1`) — скрывает статус «в сети» при наличии активного соединения.

---

## Возможности Privacy Shield & Мода

- **Strict Telemetry Firewall** — постоянная неотключаемая блокировка `LOG`, `DEBUG`, `BANNERS_SYNC`, `CHAT_SUGGEST` и `NOTIF_BANNERS` со счётчиком перехваченных пакетов.
- **Device Spoofing** — генератор виртуальных профилей устройств (iPhone / Android / Windows / Web) с синтетическими `deviceId`, `instanceId`, `User-Agent`, версией ОС и часовым поясом.
- **Ghost Mode & Anti-Read** — скрытие статуса онлайн, отключение индикатора набора текста и блокировка уведомлений о прочтении.
- **Anti-Delete** — сохранение сообщений, удалённых собеседником (`NOTIF_MSG_DELETE` / `142`), в локальном хранилище с пометкой `deletedByPeer = true`.
- **Edit History** — локальное сохранение истории предыдущих редакций сообщений при их изменении собеседником.
- **Wire Audit Log** — встроенный инспектор сетевых пакетов в реальном времени (видно каждый разрешённый и заблокированный опкод).
- **Sandbox / Demo Mode** — автономный режим для тестирования интерфейса, локального анти-удаления, истории правок и фаервола без подключения к аккаунту MAX.

---

## Архитектура проекта

```text
lib/
├── core/
│   ├── protocol/          # Чистая Dart-реализация протокола MAX
│   │   ├── opcode.dart        # Карта опкодов (auth, chats, messages, telemetry)
│   │   ├── msgpack.dart       # Сериализатор/десериализатор MessagePack
│   │   ├── lz4.dart           # Декомпрессор LZ4-блоков
│   │   ├── packet.dart        # 10-байтовый big-endian фрейминг (ver=10)
│   │   └── fingerprint.dart   # Спуферный профиль устройства для LOGIN/SESSION_INIT
│   ├── privacy/           # Слой приватности и фильтрации
│   │   ├── privacy_settings.dart  # Хранимые настройки Ghost Mode, Anti-Read, Anti-Delete
│   │   ├── spoof_profile.dart     # Пресеты виртуальных устройств
│   │   ├── spoofing_service.dart  # Генерация и ротация виртуальных отпечатков
│   │   └── privacy_firewall.dart  # Шлюз перехвата пакетов + Wire Audit Log
│   ├── transport/         # WebSocket-сессия (wss://api.oneme.ru/websocket)
│   │   └── taler_session.dart
│   └── storage/           # Локальное хранилище чатов, сообщений, истории правок
│       ├── taler_models.dart
│       └── local_store.dart
├── backend/
│   └── taler_client.dart  # Высокоуровневый клиент (Auth, Chats, Messages, Demo)
└── ui/
    ├── theme/             # Тема оформления Taler
    └── screens/           # Экраны входа, чатов, Privacy Shield, профиля и сессий
```

---

## Сборка и запуск

### Требования
- Flutter SDK (`stable`, Dart >= 3.x)
- Для Windows: Visual Studio Build Tools (Desktop development with C++)
- Для Android: Android SDK + JDK 17
- Для iOS: macOS + Xcode (или GitHub Actions runner `macos-15`)

### Локальная разработка и тесты

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows   # или android / ios
```

### Локальная сборка релизов (Windows / Android)

В репозитории есть PowerShell-скрипт [scripts/build_local.ps1](scripts/build_local.ps1):

```powershell
# Сборка Windows-релиза и Android APK в каталог dist/
.\scripts\build_local.ps1

# Только одна платформа
.\scripts\build_local.ps1 -Android:$false
.\scripts\build_local.ps1 -Windows:$false

# Сборка и публикация GitHub Release через gh CLI
.\scripts\build_local.ps1 -ReleaseTag v1.0.0
```

### CI/CD через GitHub Actions (включая `.ipa` для iPhone)

Workflow описан в [.github/workflows/build.yml](.github/workflows/build.yml) и собирает артефакты при каждом `push` / `pull_request` / теге `v*`:
- **`build-windows`** (`windows-latest`): собирает Windows-приложение (`Taler-Windows-x64.zip`).
- **`build-android`** (`ubuntu-latest`): собирает релизные APK по ABI (`Taler-Android-arm64-v8a.apk`, `Taler-Android-armeabi-v7a.apk`).
- **`build-ios`** (`macos-latest`): собирает неподписанный `Taler-iOS-unsigned.ipa` (для установки через AltStore / SideStore / TrollStore).

При создании Git-тега формата `v*` (например, `v1.0.0`) автоматически создаётся GitHub Release с прикреплёнными архивами всех платформ.

---

## Лицензия

Проект распространяется под свободной лицензией **GNU General Public License v3.0 (GPL-3.0)** — см. файл [LICENSE](LICENSE).

import 'dart:math' as math;
import 'dart:typed_data';

import 'lz4.dart';
import 'msgpack.dart';
import 'opcode.dart';

/// Типы команд в 10-байтном заголовке кадра MAX.
abstract class CmdType {
  static const int request = 0;
  static const int push = 0;
  static const int ok = 1;
  static const int notFound = 2;
  static const int error = 3;
}

/// Декодированный кадр бинарного протокола MAX.
class TalerPacket {
  final int ver;
  final int cmd;
  final int seq;
  final int opcode;
  final Object? payload;

  const TalerPacket({
    this.ver = TalerFraming.protocolVersion,
    required this.cmd,
    required this.seq,
    required this.opcode,
    this.payload,
  });

  bool get isOk => cmd == CmdType.ok;
  bool get isError => cmd != CmdType.ok && cmd != CmdType.request;
  bool get isPush => cmd == CmdType.push;

  Map<String, dynamic>? get payloadAsMap {
    final p = payload;
    if (p is! Map) return null;
    return p.map((k, v) => MapEntry(k.toString(), v));
  }

  @override
  String toString() =>
      'TalerPacket(ver=$ver cmd=$cmd seq=$seq opcode=${Opcode.name(opcode)} payload=$payload)';
}

/// Кодек 10-байтных кадров протокола MAX поверх WebSocket.
abstract class TalerFraming {
  static const int protocolVersion = 10;
  static const int headerSize = 10;

  /// Кодирует пакет в 10-байтный заголовок + MessagePack тело.
  static Uint8List encode({
    int ver = protocolVersion,
    required int cmd,
    required int seq,
    required int opcode,
    Object? payload,
  }) {
    final body = payload == null ? Uint8List(0) : TalerMsgpack.encode(payload);
    final frame = Uint8List(headerSize + body.length);
    final view = ByteData.view(frame.buffer);

    view.setUint8(0, ver);
    view.setUint8(1, cmd);
    view.setInt16(2, seq, Endian.big);
    view.setInt16(4, opcode, Endian.big);
    view.setUint8(6, 0);
    view.setUint8(7, (body.length >> 16) & 0xFF);
    view.setUint8(8, (body.length >> 8) & 0xFF);
    view.setUint8(9, body.length & 0xFF);

    frame.setRange(headerSize, frame.length, body);
    return frame;
  }

  /// Декодирует 10-байтный заголовок и тело (с распаковкой LZ4 при необходимости).
  static TalerPacket decode(Uint8List frame) {
    if (frame.length < headerSize) {
      throw const FormatException('TalerFraming: кадр короче 10 байт');
    }
    final view = ByteData.view(frame.buffer, frame.offsetInBytes, frame.length);

    final ver = view.getUint8(0);
    final cmd = view.getUint8(1);
    final seq = view.getUint16(2, Endian.big);
    final opcode = view.getUint16(4, Endian.big);
    final compressionRatio = view.getUint8(6);
    final length =
        (view.getUint8(7) << 16) | (view.getUint8(8) << 8) | view.getUint8(9);

    if (length <= 0) {
      return TalerPacket(ver: ver, cmd: cmd, seq: seq, opcode: opcode);
    }

    if (headerSize + length > frame.length) {
      throw FormatException(
        'TalerFraming: длина тела ($length) превышает размер кадра (${frame.length})',
      );
    }

    var body = Uint8List.sublistView(frame, headerSize, headerSize + length);
    if (compressionRatio > 0) {
      body = Lz4Block.decompress(body);
    }

    return TalerPacket(
      ver: ver,
      cmd: cmd,
      seq: seq,
      opcode: opcode,
      payload: TalerMsgpack.decode(body),
    );
  }

  /// Возвращает ожидаемый полный размер кадра (заголовок + тело) в начале [buffer]
  /// или `null`, если в буфере ещё меньше [headerSize] байт.
  static int? packetTotalLength(Uint8List buffer, [int offset = 0]) {
    if (buffer.length - offset < headerSize) return null;
    final length = (buffer[offset + 7] << 16) |
        (buffer[offset + 8] << 8) |
        buffer[offset + 9];
    return headerSize + length;
  }
}

/// Потоковый сборщик бинарных кадров протокола MAX поверх TCP/TLS-сокета.
///
/// Использует плоский [Uint8List] без боксирования целых и копирования на
/// каждом фрагменте. Поддерживает извлечение сырых фреймов через [feedFrames].
class TalerPacketReceiver {
  static const int maxBufferSize = Lz4Block.defaultMaxOutputSize;
  static const int _initialCapacity = 4096;

  Uint8List _buffer = Uint8List(_initialCapacity);
  int _readOffset = 0;
  int _writeOffset = 0;

  int get bufferedLength => _writeOffset - _readOffset;

  /// Добавляет фрагмент байтов [chunk] и возвращает все полностью
  /// собранные сырые кадры `Uint8List`.
  List<Uint8List> feedFrames(List<int> chunk) {
    if (chunk.isNotEmpty) {
      final incomingLen = chunk.length;
      if (bufferedLength + incomingLen > maxBufferSize) {
        final overflow = bufferedLength + incomingLen;
        reset();
        throw FormatException(
          'TalerPacketReceiver: переполнение буфера ($overflow байт)',
        );
      }

      if (_writeOffset + incomingLen > _buffer.length) {
        if (_readOffset > 0 &&
            (_buffer.length - bufferedLength) >= incomingLen) {
          _compact();
        } else {
          final needed = bufferedLength + incomingLen;
          var nextCap = _buffer.length;
          while (nextCap < needed) {
            nextCap = math.min(maxBufferSize, nextCap * 2);
          }
          final next = Uint8List(nextCap);
          if (bufferedLength > 0) {
            next.setRange(0, bufferedLength, _buffer, _readOffset);
          }
          _buffer = next;
          _writeOffset = bufferedLength;
          _readOffset = 0;
        }
      }

      _buffer.setRange(_writeOffset, _writeOffset + incomingLen, chunk);
      _writeOffset += incomingLen;
    }

    final frames = <Uint8List>[];
    while (bufferedLength >= TalerFraming.headerSize) {
      final length = (_buffer[_readOffset + 7] << 16) |
          (_buffer[_readOffset + 8] << 8) |
          _buffer[_readOffset + 9];
      final totalLen = TalerFraming.headerSize + length;

      if (totalLen < TalerFraming.headerSize || totalLen > maxBufferSize) {
        reset();
        throw FormatException(
          'TalerPacketReceiver: некорректная длина кадра ($length)',
        );
      }

      if (bufferedLength < totalLen) {
        break;
      }

      final frameBytes = Uint8List(totalLen);
      frameBytes.setRange(0, totalLen, _buffer, _readOffset);
      frames.add(frameBytes);
      _readOffset += totalLen;
    }

    if (_readOffset >= _writeOffset) {
      _readOffset = 0;
      _writeOffset = 0;
      if (_buffer.length > 65536) {
        _buffer = Uint8List(_initialCapacity);
      }
    } else if (_readOffset >= 2048) {
      _compact();
    }

    return frames;
  }

  /// Добавляет фрагмент байтов [chunk] и декодирует все готовые пакеты.
  List<TalerPacket> feed(List<int> chunk) {
    final frames = feedFrames(chunk);
    if (frames.isEmpty) return const [];
    final packets = <TalerPacket>[];
    for (final raw in frames) {
      try {
        packets.add(TalerFraming.decode(raw));
      } catch (_) {
        // Изолируем ошибку декодирования отдельного кадра.
      }
    }
    return packets;
  }

  void _compact() {
    final len = bufferedLength;
    if (len > 0 && _readOffset > 0) {
      _buffer.setRange(0, len, _buffer, _readOffset);
    }
    _readOffset = 0;
    _writeOffset = len;
  }

  void reset() {
    _readOffset = 0;
    _writeOffset = 0;
    if (_buffer.length > 65536) {
      _buffer = Uint8List(_initialCapacity);
    }
  }
}

/// Исключение протокольного уровня MAX.
class TalerPacketException implements Exception {
  final String message;
  final String? code;
  final int? opcode;

  const TalerPacketException(this.message, {this.code, this.opcode});

  bool get isSessionExpired =>
      code == 'FAIL_LOGIN_TOKEN' ||
      code == 'FAIL_WRONG_PASSWORD' ||
      message.contains('FAIL_LOGIN_TOKEN');

  @override
  String toString() => code == null ? message : '$code: $message';

  static TalerPacketException fromFrame(TalerPacket packet) {
    final payload = packet.payload;
    if (payload is Map) {
      final rawMsg =
          payload['localizedMessage'] ?? payload['title'] ?? payload['message'];
      final rawCode = payload['error'] ?? payload['message'];
      final code = rawCode is String && rawCode.isNotEmpty ? rawCode : null;

      if (rawMsg is String &&
          rawMsg.trim().isNotEmpty &&
          !rawMsg.startsWith('Key: ') &&
          !rawMsg.startsWith('key: ')) {
        return TalerPacketException(
          rawMsg.trim(),
          code: code,
          opcode: packet.opcode,
        );
      }
      if (code != null) {
        return TalerPacketException(code, code: code, opcode: packet.opcode);
      }
    }
    return TalerPacketException(
      'Ошибка сервера (${Opcode.name(packet.opcode)}, cmd=${packet.cmd})',
      opcode: packet.opcode,
    );
  }
}

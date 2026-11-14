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
    final seq = view.getInt16(2, Endian.big);
    final opcode = view.getInt16(4, Endian.big);
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
      body = Lz4Block.decompress(body, length * compressionRatio * 16);
    }

    return TalerPacket(
      ver: ver,
      cmd: cmd,
      seq: seq,
      opcode: opcode,
      payload: TalerMsgpack.decode(body),
    );
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

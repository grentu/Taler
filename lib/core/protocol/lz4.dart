import 'dart:math' as math;
import 'dart:typed_data';

/// Распаковщик LZ4-блоков и LZ4-фреймов для сжатых кадров протокола MAX (`compressionRatio > 0`).
abstract class Lz4Block {
  /// Максимальный допустимый размер распакованного пакета (8 МБ).
  static const int defaultMaxOutputSize = 8 * 1024 * 1024;

  /// Распаковывает [source] (сырой LZ4 block или LZ4 frame с magic `04 22 4D 18`)
  /// в динамически расширяемый буфер с защитным лимитом [maxOutputSize] байт.
  static Uint8List decompress(
    Uint8List source, [
    int maxOutputSize = defaultMaxOutputSize,
  ]) {
    if (source.isEmpty) return Uint8List(0);

    // Проверка на стандартный заголовок LZ4 Frame (magic 0x184D2204 LE).
    if (source.length >= 7 &&
        source[0] == 0x04 &&
        source[1] == 0x22 &&
        source[2] == 0x4D &&
        source[3] == 0x18) {
      return _decompressFrame(source, maxOutputSize);
    }

    var capacity = math.min(maxOutputSize, math.max(256, source.length * 3));
    var output = Uint8List(capacity);
    var input = 0;
    var written = 0;

    void ensureCapacity(int additional) {
      final needed = written + additional;
      if (needed > maxOutputSize) {
        throw const FormatException('Lz4Block: превышен лимит распаковки');
      }
      if (needed <= capacity) return;
      var nextCap = capacity;
      while (nextCap < needed) {
        nextCap = math.min(maxOutputSize, nextCap * 2);
      }
      final next = Uint8List(nextCap);
      next.setRange(0, written, output);
      output = next;
      capacity = nextCap;
    }

    while (input < source.length) {
      final token = source[input++];

      var literalLength = token >> 4;
      if (literalLength == 15) {
        literalLength += _readLengthExtension(
          source,
          () => input,
          (v) => input = v,
        );
      }

      if (input + literalLength > source.length) {
        throw const FormatException('Lz4Block: неожиданный конец литералов');
      }

      if (literalLength > 0) {
        ensureCapacity(literalLength);
        output.setRange(
          written,
          written + literalLength,
          Uint8List.sublistView(source, input, input + literalLength),
        );
        written += literalLength;
        input += literalLength;
      }

      if (input >= source.length) break;
      if (input + 2 > source.length) {
        throw const FormatException('Lz4Block: неожиданный конец смещения');
      }

      final offset = source[input] | (source[input + 1] << 8);
      input += 2;
      if (offset == 0 || offset > written) {
        throw const FormatException('Lz4Block: неверное смещение совпадения');
      }

      var matchLength = token & 0x0F;
      if (matchLength == 15) {
        matchLength += _readLengthExtension(
          source,
          () => input,
          (v) => input = v,
        );
      }
      matchLength += 4;

      ensureCapacity(matchLength);
      var from = written - offset;
      for (var i = 0; i < matchLength; i++) {
        output[written++] = output[from++];
      }
    }

    return Uint8List.fromList(Uint8List.sublistView(output, 0, written));
  }

  static int _readLengthExtension(
    Uint8List source,
    int Function() get,
    void Function(int) set,
  ) {
    var cursor = get();
    var extra = 0;
    while (true) {
      if (cursor >= source.length) {
        throw const FormatException('Lz4Block: обрыв в расширении длины');
      }
      final byte = source[cursor++];
      extra += byte;
      if (byte != 255) break;
    }
    set(cursor);
    return extra;
  }

  static Uint8List _decompressFrame(Uint8List source, int maxOutputSize) {
    final flg = source[4];
    final hasContentSize = (flg & 0x08) != 0;
    final hasDictId = (flg & 0x01) != 0;
    var offset = 6; // magic(4) + FLG(1) + BD(1)
    if (hasContentSize) offset += 8;
    if (hasDictId) offset += 4;
    offset += 1; // HC byte

    final out = BytesBuilder(copy: false);
    var totalLen = 0;
    while (offset + 4 <= source.length) {
      final rawSize = source[offset] |
          (source[offset + 1] << 8) |
          (source[offset + 2] << 16) |
          (source[offset + 3] << 24);
      offset += 4;
      if (rawSize == 0) break; // EndMark
      final uncompressed = (rawSize & 0x80000000) != 0;
      final blockSize = rawSize & 0x7FFFFFFF;
      if (offset + blockSize > source.length) {
        throw const FormatException('Lz4Frame: обрыв блока данных');
      }
      final blockBytes = Uint8List.sublistView(source, offset, offset + blockSize);
      offset += blockSize;
      final chunk = uncompressed
          ? blockBytes
          : decompress(blockBytes, maxOutputSize - totalLen);
      totalLen += chunk.length;
      if (totalLen > maxOutputSize) {
        throw const FormatException('Lz4Frame: превышен лимит распаковки');
      }
      out.add(chunk);
      if ((flg & 0x10) != 0 && offset + 4 <= source.length) {
        offset += 4; // block checksum
      }
    }
    return out.takeBytes();
  }
}

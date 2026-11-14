import 'dart:typed_data';

/// Распаковщик LZ4-блоков для сжатых кадров протокола MAX (`compressionRatio > 0`).
abstract class Lz4Block {
  /// Распаковывает [source] в буфер размером не более [maxOutputSize] байт.
  static Uint8List decompress(Uint8List source, int maxOutputSize) {
    final output = Uint8List(maxOutputSize);
    var input = 0;
    var written = 0;

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

      if (written + literalLength > output.length) {
        throw const FormatException('Lz4Block: литералы не помещаются');
      }
      output.setRange(
        written,
        written + literalLength,
        Uint8List.sublistView(source, input, input + literalLength),
      );
      written += literalLength;
      input += literalLength;

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

      if (written + matchLength > output.length) {
        throw const FormatException('Lz4Block: совпадение не помещается');
      }

      var from = written - offset;
      for (var i = 0; i < matchLength; i++) {
        output[written++] = output[from++];
      }
    }

    return Uint8List.sublistView(output, 0, written);
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
}

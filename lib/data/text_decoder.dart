import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';

class TextDecoder {
  TextDecoder._();

  static Future<String> decodeBytes(Uint8List bytes) async {
    // Strip UTF-8 BOM.
    var data = bytes;
    if (data.length >= 3 &&
        data[0] == 0xEF &&
        data[1] == 0xBB &&
        data[2] == 0xBF) {
      data = data.sublist(3);
    }

    try {
      return utf8.decode(data);
    } on FormatException {
      // continue
    }

    for (final charset in ['gb18030', 'gbk', 'gb2312', 'big5']) {
      try {
        final text = await CharsetConverter.decode(charset, data);
        if (_looksMostlyReadable(text)) return text;
      } catch (_) {
        // try next
      }
    }

    return latin1.decode(data, allowInvalid: true);
  }

  static bool _looksMostlyReadable(String text) {
    if (text.isEmpty) return false;
    final sample = text.substring(0, text.length.clamp(0, 800));
    final replacement = '\uFFFD'.allMatches(sample).length;
    return replacement < sample.length * 0.02;
  }
}

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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

    final candidates = <String>[];

    try {
      candidates.add(utf8.decode(data));
    } on FormatException {
      // not utf-8
    }

    // Pure-Dart GBK — works on web (charset_converter is native-only).
    try {
      candidates.add(const GbkCodec(allowMalformed: true).decode(data));
    } catch (_) {}

    if (!kIsWeb) {
      for (final charset in ['gb18030', 'gbk', 'gb2312', 'big5']) {
        try {
          candidates.add(await CharsetConverter.decode(charset, data));
        } catch (_) {}
      }
    }

    candidates.add(latin1.decode(data, allowInvalid: true));
    return _pickBest(candidates);
  }

  /// Fix text that was wrongly stored as latin1 of GBK bytes (web import bug).
  static Future<String?> repairIfMojibake(String text) async {
    if (!_looksLikeMojibake(text)) return null;
    final bytes = Uint8List.fromList(latin1.encode(text));
    final fixed = await decodeBytes(bytes);
    if (_score(fixed) <= _score(text) + 5) return null;
    if (_cjkRatio(fixed) < 0.08) return null;
    return fixed;
  }

  static String _pickBest(List<String> candidates) {
    if (candidates.isEmpty) return '';
    candidates.sort((a, b) => _score(b).compareTo(_score(a)));
    return candidates.first;
  }

  static int _score(String text) {
    if (text.isEmpty) return -1000;
    final sampleLen = math.min(text.length, 2400);
    final sample = text.substring(0, sampleLen);
    final cjk = _countCjk(sample);
    final replacement = '\uFFFD'.allMatches(sample).length;
    final highLatin = _countHighLatin(sample);
    return cjk * 4 - replacement * 8 - highLatin;
  }

  static bool _looksLikeMojibake(String text) {
    if (text.isEmpty) return false;
    final sampleLen = math.min(text.length, 1600);
    final sample = text.substring(0, sampleLen);
    final cjk = _countCjk(sample);
    final highLatin = _countHighLatin(sample);
    return cjk < sampleLen * 0.05 && highLatin > sampleLen * 0.12;
  }

  static double _cjkRatio(String text) {
    if (text.isEmpty) return 0;
    final sampleLen = math.min(text.length, 2000);
    return _countCjk(text.substring(0, sampleLen)) / sampleLen;
  }

  static int _countCjk(String sample) {
    var n = 0;
    for (final unit in sample.codeUnits) {
      if (unit >= 0x4E00 && unit <= 0x9FFF) n++;
      if (unit >= 0x3400 && unit <= 0x4DBF) n++;
    }
    return n;
  }

  static int _countHighLatin(String sample) {
    var n = 0;
    for (final unit in sample.codeUnits) {
      if (unit >= 0x80 && unit <= 0xFF) n++;
    }
    return n;
  }
}

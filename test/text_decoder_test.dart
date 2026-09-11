import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/data/text_decoder.dart';

void main() {
  test('decodes GBK novel title bytes', () async {
    // GBK bytes for 「择日飞升」
    final bytes = Uint8List.fromList(
      latin1.encode('ÔñÈÕ·ÉÉý'),
    );
    final text = await TextDecoder.decodeBytes(bytes);
    expect(text, contains('择日'));
    expect(text, contains('飞升'));
  });

  test('repairs latin1 mojibake of GBK', () async {
    const garbled = '¡¶ÔñÈÕ·ÉÉý¡·µÚÒ»ÕÂ';
    final fixed = await TextDecoder.repairIfMojibake(garbled);
    expect(fixed, isNotNull);
    expect(fixed!, contains('择日飞升'));
  });
}

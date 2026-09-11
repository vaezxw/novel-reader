import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/reader/page_paginator.dart';

void main() {
  test('paginate splits long chapter without hanging', () {
    final buf = StringBuffer();
    for (var i = 0; i < 400; i++) {
      buf.writeln('第${i + 1}段。这是一段用于分页压测的中文正文，包含标点与换行。');
    }
    final text = buf.toString();
    final pages = PagePaginator.paginate(
      text: text,
      pageSize: const Size(360, 640),
      style: const TextStyle(fontSize: 19, height: 1.6),
    );
    expect(pages.length, greaterThan(5));
    expect(pages.every((p) => p.isNotEmpty), isTrue);
    expect(
      pages.join().replaceAll(RegExp(r'\s+'), ''),
      text.replaceAll(RegExp(r'\s+'), ''),
    );
  });
}

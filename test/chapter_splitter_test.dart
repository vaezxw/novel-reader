import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/data/chapter_splitter.dart';

void main() {
  test('splits chinese chapter headings', () {
    const text = '''
序言内容在这里。

第一章 启程
这是第一章正文。

第二章 风雨
这是第二章正文。
''';
    final chapters = ChapterSplitter.split(text);
    expect(chapters.length, greaterThanOrEqualTo(2));
    expect(chapters.any((c) => c.title.contains('第一章')), isTrue);
    expect(chapters.any((c) => c.title.contains('第二章')), isTrue);
  });

  test('falls back to whole book when no headings', () {
    const text = '没有章节标题的一段小说正文。';
    final chapters = ChapterSplitter.split(text);
    expect(chapters.length, 1);
    expect(chapters.first.title, '全文');
  });
}

/// Splits novel plain text into chapter ranges by common Chinese/English headings.
class ChapterSplitter {
  ChapterSplitter._();

  static final RegExp heading = RegExp(
    r'^[ \t　]*('
    r'第[0-9零一二三四五六七八九十百千万〇两]+[章节回卷部集话][^\n]{0,48}'
    r'|[Cc]hapter[\s\u3000]*[0-9]+[^\n]{0,48}'
    r'|楔子|序章|序言|引子|前言|终章|尾声|后记|番外[^\n]{0,24}'
    r')\s*$',
    multiLine: true,
  );

  static List<({String title, int start, int end})> split(String text) {
    if (text.trim().isEmpty) {
      return [(title: '全文', start: 0, end: 0)];
    }

    final matches = heading.allMatches(text).toList();
    if (matches.length < 2) {
      return [(title: '全文', start: 0, end: text.length)];
    }

    final chapters = <({String title, int start, int end})>[];

    // Keep prologue before first heading if substantial.
    final first = matches.first;
    if (first.start > 80) {
      chapters.add((
        title: '前言',
        start: 0,
        end: first.start,
      ));
    }

    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      final title = match.group(1)?.trim() ?? '章节 ${i + 1}';
      final start = match.start;
      final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
      if (end <= start) continue;
      chapters.add((title: title, start: start, end: end));
    }

    if (chapters.isEmpty) {
      return [(title: '全文', start: 0, end: text.length)];
    }
    return chapters;
  }
}

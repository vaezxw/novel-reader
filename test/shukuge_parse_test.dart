import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/data/rule_selector.dart';
import 'package:novel_reader/data/source_engine.dart';
import 'package:novel_reader/data/source_models.dart';

void main() {
  test('parses 365小说网 search HTML with legado chained rules', () {
    final file = File('tmp_shukuge.html');
    if (!file.existsSync()) {
      // Optional offline fixture; skip when not downloaded.
      return;
    }
    final html = file.readAsStringSync();
    final source = BookSource.fromLegadoJson({
      'bookSourceName': '365小说网',
      'bookSourceUrl': 'http://www.shukuge.com/',
      'searchUrl': 'Search?wd={{key}}',
      'ruleSearch': {
        'author': '.sp@span.0@text##作者：',
        'bookList': '.listitem',
        'bookUrl': '.bookdesc@a@href',
        'coverUrl': 'img@src',
        'intro': '.desc.1@text##简介：',
        'name': '.bookdesc@h2@text',
      },
    });

    final doc = RuleSelector.parseHtml(html);
    final nodes = RuleSelector.selectList(doc, '.listitem');
    expect(nodes.length, greaterThan(3));

    final first = nodes.first;
    final name = RuleSelector.readFromElement(first, '.bookdesc@h2@text');
    final url = RuleSelector.readFromElement(first, '.bookdesc@a@href');
    expect(name.isNotEmpty, isTrue);
    expect(url.startsWith('/book/'), isTrue);

    // Ensure engine filter fields would pass.
    expect(name.isNotEmpty && url.isNotEmpty, isTrue);
    expect(SourceEngine.isUnsupportedSearchUrl(source.searchUrl), isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/data/rule_selector.dart';

void main() {
  test('reads css text and href', () {
    final doc = RuleSelector.parseHtml('''
      <div class="item">
        <a class="title" href="/book/1">书名甲</a>
        <span class="author">作者乙</span>
      </div>
    ''');
    final item = doc.querySelector('.item')!;
    expect(
      RuleSelector.readFromElement(item, '.title@text'),
      '书名甲',
    );
    expect(
      RuleSelector.readFromElement(item, 'a@href'),
      '/book/1',
    );
    expect(
      RuleSelector.readFromElement(item, '.author@text'),
      '作者乙',
    );
  });

  test('normalizes legado class selector', () {
    expect(RuleSelector.normalizeCss('class.book-item'), '.book-item');
    expect(RuleSelector.normalizeCss('id.content'), '#content');
  });

  test('json path list and field', () {
    final root = {
      'data': {
        'list': [
          {'name': 'A', 'url': '/a'},
          {'name': 'B', 'url': '/b'},
        ],
      },
    };
    final list = RuleSelector.jsonList(root, '\$.data.list');
    expect(list.length, 2);
    expect(RuleSelector.jsonField(list.first, 'name'), 'A');
    expect(RuleSelector.jsonField(list.first, '\$.url'), '/a');
  });

  test('html to plain keeps paragraphs', () {
    final plain = RuleSelector.htmlToPlain('<p>第一段</p><p>第二段</p>');
    expect(plain.contains('第一段'), isTrue);
    expect(plain.contains('第二段'), isTrue);
  });
}

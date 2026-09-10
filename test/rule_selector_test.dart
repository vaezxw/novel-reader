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
    final list = RuleSelector.jsonList(root, r'$.data.list');
    expect(list.length, 2);
    expect(RuleSelector.jsonField(list.first, 'name'), 'A');
    expect(RuleSelector.jsonField(list.first, r'$.url'), '/a');
  });

  test('html to plain keeps paragraphs', () {
    final plain = RuleSelector.htmlToPlain('<p>第一段</p><p>第二段</p>');
    expect(plain.contains('第一段'), isTrue);
    expect(plain.contains('第二段'), isTrue);
  });

  test('reads meta content attribute', () {
    final doc = RuleSelector.parseHtml('''
      <html><head>
        <meta property="og:title" content="书名丙" />
        <meta property="og:novel:author" content="作者丁" />
      </head></html>
    ''');
    expect(
      RuleSelector.readFromDocument(
        doc,
        "meta[property='og:title']@content",
      ),
      '书名丙',
    );
    expect(
      RuleSelector.readFromDocument(
        doc,
        "meta[property='og:novel:author']@content",
      ),
      '作者丁',
    );
  });

  test('all-in-one ## regex strip on content rule', () {
    final doc = RuleSelector.parseHtml(
      '<div class="content">正文开始立即阅读更多精彩。结尾</div>',
    );
    final text = RuleSelector.readFromDocument(
      doc,
      r'div.content@text##立即阅读.*?精彩。##',
    );
    expect(text, '正文开始结尾');
  });

  test('resolveNextUrl from legado-like js snippet', () {
    final doc = RuleSelector.parseHtml('''
      <div class="btnW">
        <a class="btnYell" href="/c/1.html">上一页</a>
        <a class="btnYell" href="/c/2.html">下一页</a>
      </div>
    ''');
    const js = r'''
      var links = document.select('.btnW a.btnYell');
      for (var i = 0; i < links.size(); i++) {
        var link = links.get(i);
        if (link.text().indexOf('下一页') >= 0) {
          return link.attr('href');
        }
      }
    ''';
    expect(RuleSelector.resolveNextUrl(doc, js), '/c/2.html');
  });
}

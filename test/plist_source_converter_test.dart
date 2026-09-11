import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/data/plist_source_converter.dart';

void main() {
  test('converts 83zws-style plist to legado json', () {
    const plist = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>name</key><string>83中文网</string>
<key>url</key><string>https://www.83zws.com</string>
<key>search</key><dict>
<key>url</key><string>https://www.83zws.com/search.html?keyword={key}</string>
<key>list</key><string>//ul[@class='book-list clearfix']/li</string>
<key>title</key><string>.//h3/a/text()</string>
<key>author</key><string>.//p[@class='author']/text()</string>
<key>link</key><string>.//h3/a/@href</string>
</dict>
<key>chapters</key><dict>
<key>url</key><string>{link}</string>
<key>list</key><string>//div[@id='chapter-list']/div[2]/a</string>
<key>title</key><string>./text()</string>
<key>link</key><string>./@href</string>
</dict>
<key>content</key><dict>
<key>url</key><string>{link}</string>
<key>content</key><string>//div[@class='read-content']</string>
</dict>
</dict>
</plist>
''';
    final list = PlistSourceConverter.convert(plist);
    expect(list.length, 1);
    final src = list.first;
    expect(src['bookSourceName'], '83中文网');
    expect(src['searchUrl'], 'https://www.83zws.com/search.html?keyword={{key}}');
    final ruleSearch = src['ruleSearch'] as Map;
    expect(ruleSearch['bookList'], 'ul.book-list.clearfix li');
    expect(ruleSearch['name'], 'h3 a@text');
    expect(ruleSearch['bookUrl'], 'h3 a@href');
    expect(ruleSearch['author'], 'p.author@text');
    final ruleToc = src['ruleToc'] as Map;
    expect(ruleToc['chapterList'], '#chapter-list div:nth-child(2) a');
    expect(ruleToc['chapterName'], '@text');
    expect(ruleToc['chapterUrl'], '@href');
    final ruleContent = src['ruleContent'] as Map;
    expect(ruleContent['content'], 'div.read-content@html');
  });

  test('rejects serverList plist', () {
    const plist = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>serverList</key><array></array>
</dict></plist>
''';
    expect(
      () => PlistSourceConverter.convert(plist),
      throwsA(isA<FormatException>()),
    );
  });

  test('xpath helpers', () {
    expect(
      PlistSourceConverter.xpathToLegadoRule(
        "//ul[@class='book-list clearfix']/li",
      ),
      'ul.book-list.clearfix li',
    );
    expect(
      PlistSourceConverter.xpathToLegadoRule('.//h3/a/@href'),
      'h3 a@href',
    );
    expect(PlistSourceConverter.xpathToLegadoRule('./text()'), '@text');
  });
}

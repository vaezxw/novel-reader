import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/data/source_engine.dart';

void main() {
  group('SourceEngine.parseSearchTemplate', () {
    test('replaces key/page and resolves relative url', () {
      final spec = SourceEngine.parseSearchTemplate(
        base: 'https://example.com/',
        template: '/search?q={{key}}&p={{page}}',
        key: '斗罗',
        page: 2,
      );
      expect(spec.method, 'GET');
      expect(spec.url, contains('q=%E6%96%97%E7%BD%97'));
      expect(spec.url, contains('p=2'));
      expect(spec.url, startsWith('https://example.com/'));
    });

    test('parses POST options suffix', () {
      final spec = SourceEngine.parseSearchTemplate(
        base: 'http://www.shukuge.com/',
        template:
            'http://www.shukuge.com/search.php,{"method":"POST","body":"searchkey={{key}}&searchtype=articlename"}',
        key: '斗罗',
        page: 1,
      );
      expect(spec.method, 'POST');
      expect(spec.url, 'http://www.shukuge.com/search.php');
      expect(spec.body, contains('searchkey='));
      expect(spec.body, contains('%E6%96%97%E7%BD%97'));
    });
  });

  group('SourceEngine.applyWebProxy', () {
    test('wraps target url', () {
      final out = SourceEngine.applyWebProxy('http://www.shukuge.com/Search?wd=1');
      expect(out, startsWith('https://corsproxy.io/?url='));
      expect(out, contains(Uri.encodeComponent('http://www.shukuge.com/Search?wd=1')));
    });

    test('does not double wrap', () {
      final once = SourceEngine.applyWebProxy('https://a.com/x');
      expect(SourceEngine.applyWebProxy(once), once);
    });
  });
}

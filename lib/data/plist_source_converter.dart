import 'package:xml/xml.dart';

/// Converts simple Apple-plist book sources (XPath style, e.g. 83zws) into
/// Legado-compatible JSON maps. Rejects unrelated plist formats (e.g. serverList).
class PlistSourceConverter {
  PlistSourceConverter._();

  static bool looksLikePlist(String text) {
    final t = text.trimLeft();
    return t.startsWith('<plist') ||
        (t.startsWith('<?xml') && t.contains('<plist'));
  }

  /// Returns one or more Legado-style source maps.
  static List<Map<String, dynamic>> convert(String plistXml) {
    final doc = XmlDocument.parse(plistXml);
    final root = doc.rootElement;
    if (root.name.local != 'plist') {
      throw const FormatException('不是有效的 plist 书源');
    }
    XmlElement? dict;
    for (final e in root.childElements) {
      if (e.name.local == 'dict') {
        dict = e;
        break;
      }
    }
    if (dict == null) {
      throw const FormatException('plist 缺少根 dict');
    }

    final map = _dictToMap(dict);
    if (map.containsKey('serverList')) {
      throw const FormatException(
        '这是书单/服务器列表 plist，不是可搜索书源。请导入 Legado JSON，或 83zws 这类带 search/chapters/content 的站点 plist。',
      );
    }

    // Single source plist (83zws style).
    if (map.containsKey('search') || map.containsKey('url')) {
      return [_toLegado(map)];
    }

    // Array of sources under a key.
    for (final value in map.values) {
      if (value is List) {
        final out = <Map<String, dynamic>>[];
        for (final item in value) {
          if (item is Map<String, dynamic> &&
              (item.containsKey('search') || item.containsKey('url'))) {
            out.add(_toLegado(item));
          }
        }
        if (out.isNotEmpty) return out;
      }
    }

    throw const FormatException(
      '无法识别该 plist。墨架支持：Legado JSON，或含 search/chapters/content 的简单站点 plist。',
    );
  }

  static Map<String, dynamic> _toLegado(Map<String, dynamic> src) {
    final name = '${src['name'] ?? '未命名书源'}'.trim();
    final base = '${src['baseUrl'] ?? src['url'] ?? ''}'.trim();
    if (base.isEmpty) {
      throw FormatException('书源「$name」缺少 url/baseUrl');
    }

    final search = _asMap(src['search']);
    final chapters = _asMap(src['chapters']);
    final content = _asMap(src['content']);

    final searchUrlRaw = '${search['url'] ?? ''}'.trim();
    if (searchUrlRaw.isEmpty) {
      throw FormatException('书源「$name」缺少 search.url');
    }

    final searchUrl = searchUrlRaw
        .replaceAll('{key}', '{{key}}')
        .replaceAll('{page}', '{{page}}');

    final bookList = xpathToLegadoRule('${search['list'] ?? ''}');
    final nameRule = xpathToLegadoRule('${search['title'] ?? ''}');
    final authorRule = xpathToLegadoRule('${search['author'] ?? ''}');
    final bookUrlRule = xpathToLegadoRule('${search['link'] ?? ''}');

    final chapterList = xpathToLegadoRule('${chapters['list'] ?? ''}');
    const defaultChapterTitle = './text()';
    const defaultChapterLink = './@href';
    final chapterName = xpathToLegadoRule(
      '${chapters['title'] ?? defaultChapterTitle}',
    );
    final chapterUrl = xpathToLegadoRule(
      '${chapters['link'] ?? defaultChapterLink}',
    );

    final contentRule = xpathToLegadoRule('${content['content'] ?? ''}');
    final contentLegado = contentRule.contains('@')
        ? contentRule
        : (contentRule.isEmpty ? '' : '$contentRule@html');

    return {
      'bookSourceName': name,
      'bookSourceUrl': base.endsWith('/') ? base.substring(0, base.length - 1) : base,
      'bookSourceType': 0,
      'enabled': true,
      'searchUrl': searchUrl,
      'ruleSearch': {
        if (bookList.isNotEmpty) 'bookList': bookList,
        if (nameRule.isNotEmpty) 'name': nameRule,
        if (authorRule.isNotEmpty) 'author': authorRule,
        if (bookUrlRule.isNotEmpty) 'bookUrl': bookUrlRule,
      },
      'ruleToc': {
        if (chapterList.isNotEmpty) 'chapterList': chapterList,
        if (chapterName.isNotEmpty) 'chapterName': chapterName,
        if (chapterUrl.isNotEmpty) 'chapterUrl': chapterUrl,
      },
      'ruleContent': {
        if (contentLegado.isNotEmpty) 'content': contentLegado,
      },
    };
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return const {};
  }

  static Map<String, dynamic> _dictToMap(XmlElement dict) {
    final out = <String, dynamic>{};
    final children = dict.childElements.toList();
    for (var i = 0; i + 1 < children.length; i++) {
      final keyEl = children[i];
      final valEl = children[i + 1];
      if (keyEl.name.local != 'key') continue;
      final key = keyEl.innerText;
      out[key] = _value(valEl);
      i++; // skip value
    }
    return out;
  }

  static dynamic _value(XmlElement el) {
    switch (el.name.local) {
      case 'string':
        return el.innerText;
      case 'integer':
        return int.tryParse(el.innerText) ?? el.innerText;
      case 'real':
        return double.tryParse(el.innerText) ?? el.innerText;
      case 'true':
        return true;
      case 'false':
        return false;
      case 'dict':
        return _dictToMap(el);
      case 'array':
        return el.childElements.map(_value).toList();
      default:
        return el.innerText;
    }
  }

  /// Best-effort XPath → Legado CSS/@attr rule.
  static String xpathToLegadoRule(String xpath) {
    var s = xpath.trim();
    if (s.isEmpty) return '';

    String attr = '';
    if (s.endsWith('/text()')) {
      attr = 'text';
      s = s.substring(0, s.length - '/text()'.length);
    } else {
      final attrMatch = RegExp(r'/@([A-Za-z0-9_-]+)$').firstMatch(s);
      if (attrMatch != null) {
        attr = attrMatch.group(1)!;
        s = s.substring(0, attrMatch.start);
      }
    }

    s = s.replaceFirst(RegExp(r'^\.//'), '');
    s = s.replaceFirst(RegExp(r'^//'), '');
    s = s.replaceFirst(RegExp(r'^\./'), '');
    if (s == '.' || s.isEmpty) {
      return attr.isEmpty ? '' : '@$attr';
    }

    final segments = s.split('/').where((e) => e.isNotEmpty).toList();
    final cssParts = <String>[];
    for (final seg in segments) {
      cssParts.add(_xpathStepToCss(seg));
    }
    final css = cssParts.join(' ');
    if (attr.isEmpty) return css;
    return '$css@$attr';
  }

  static String _xpathStepToCss(String step) {
    // div[@id='chapter-list'] or div[@class='read-content'] or div[2]
    final idMatch =
        RegExp(r'''^([a-zA-Z0-9_-]+)\[@id=['"]([^'"]+)['"]\]$''').firstMatch(step);
    if (idMatch != null) {
      return '#${idMatch.group(2)}';
    }
    final classMatch = RegExp(
      r'''^([a-zA-Z0-9_-]+)\[@class=['"]([^'"]+)['"]\]$''',
    ).firstMatch(step);
    if (classMatch != null) {
      final tag = classMatch.group(1)!;
      final classes = classMatch.group(2)!.trim().split(RegExp(r'\s+'));
      return '$tag${classes.map((c) => '.$c').join()}';
    }
    final nth = RegExp(r'^([a-zA-Z0-9_-]+)\[(\d+)\]$').firstMatch(step);
    if (nth != null) {
      return '${nth.group(1)}:nth-child(${nth.group(2)})';
    }
    // plain tag or already css-ish
    if (step.startsWith('@')) return step.substring(1);
    return step;
  }
}

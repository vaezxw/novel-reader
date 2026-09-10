import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Subset of Legado-style selectors:
/// - CSS: `.item`, `div.list a`, `#content`, `meta[property='og:title']`
/// - Legado shortcuts: `class.item` → `.item`, `id.content` → `#content`
/// - Attrs: `a@href`, `.title@text`, `#c@html`, `meta@content`
/// - Inline replace: `rule##regex##` or `rule##regex##replacement`
/// - JSON: `$.data.list`, `$.name`, `name` (relative to object)
class RuleSelector {
  RuleSelector._();

  /// Splits Legado AllInOne suffix: `base##pat##repl##pat2##repl2`
  static (String base, List<(String pattern, String replacement)>) splitAllInOne(
    String rule,
  ) {
    final idx = rule.indexOf('##');
    if (idx < 0) return (rule.trim(), const []);
    final base = rule.substring(0, idx).trim();
    final parts = rule.substring(idx + 2).split('##');
    final replaces = <(String, String)>[];
    for (var i = 0; i < parts.length; i += 2) {
      final pattern = parts[i];
      if (pattern.isEmpty) continue;
      final replacement = i + 1 < parts.length ? parts[i + 1] : '';
      replaces.add((pattern, replacement));
    }
    return (base, replaces);
  }

  static String applyReplaces(
    String input,
    List<(String pattern, String replacement)> replaces,
  ) {
    var out = input;
    for (final (pattern, replacement) in replaces) {
      try {
        out = out.replaceAll(RegExp(pattern, dotAll: true), replacement);
      } catch (_) {
        out = out.replaceAll(pattern, replacement);
      }
    }
    return out;
  }

  static String normalizeCss(String rule) {
    var r = rule.trim();
    if (r.startsWith('@css:')) r = r.substring(5);
    if (r.startsWith('class.')) r = '.${r.substring(6)}';
    if (r.startsWith('id.')) r = '#${r.substring(3)}';
    if (r.startsWith('tag.')) r = r.substring(4);
    return r.trim();
  }

  static (String selector, String attr) splitRule(String rule) {
    final (base, _) = splitAllInOne(rule);
    final at = base.lastIndexOf('@');
    if (at <= 0) return (normalizeCss(base), 'text');
    final left = base.substring(0, at).trim();
    final right = base.substring(at + 1).trim().toLowerCase();
    if (left.isEmpty) return ('', right);
    return (normalizeCss(left), right);
  }

  static List<Element> selectList(Document doc, String? bookListRule) {
    if (bookListRule == null || bookListRule.trim().isEmpty) return const [];
    final (selector, _) = splitRule(bookListRule);
    if (selector.isEmpty) return const [];
    try {
      return doc.querySelectorAll(selector);
    } catch (_) {
      return const [];
    }
  }

  static String readFromElement(Element root, String? rule) {
    if (rule == null || rule.trim().isEmpty) return '';
    final (base, replaces) = splitAllInOne(rule);
    final (selector, attr) = splitRule(base);
    Element? node = root;
    if (selector.isNotEmpty) {
      try {
        node = root.querySelector(selector) ??
            (selector == 'text' ? root : null);
      } catch (_) {
        node = null;
      }
    }
    if (node == null) return '';
    return applyReplaces(_attr(node, attr), replaces);
  }

  static String readFromDocument(Document doc, String? rule) {
    if (rule == null || rule.trim().isEmpty) return '';
    final (base, replaces) = splitAllInOne(rule);
    final (selector, attr) = splitRule(base);
    Element? node;
    if (selector.isEmpty) {
      node = doc.body;
    } else {
      try {
        node = doc.querySelector(selector);
      } catch (_) {
        node = null;
      }
    }
    if (node == null) return '';
    return applyReplaces(_attr(node, attr), replaces);
  }

  static String _attr(Element node, String attr) {
    switch (attr) {
      case 'html':
        return node.innerHtml;
      case 'text':
      case 'textnodes':
        return node.text.trim();
      case 'owntext':
        return node.nodes
            .whereType<Text>()
            .map((t) => t.text)
            .join()
            .trim();
      default:
        // href / src / content / value / any HTML attribute
        return node.attributes[attr] ??
            node.attributes[attr.toLowerCase()] ??
            '';
    }
  }

  static Document parseHtml(String html) => html_parser.parse(html);

  static bool isJsonRule(String? rule) {
    if (rule == null) return false;
    final (base, _) = splitAllInOne(rule);
    final t = base.trim();
    return t.startsWith(r'$') || t.startsWith('[');
  }

  static bool looksLikeJs(String? rule) {
    if (rule == null) return false;
    final t = rule.trim();
    if (t.startsWith('@js:') || t.startsWith('<js>')) return true;
    return t.contains('document.select') ||
        t.contains('java.') ||
        (t.contains('function') && t.contains('return'));
  }

  /// Resolve next-page URL from Legado `nextContentUrl` (CSS or simple JS).
  static String? resolveNextUrl(Document doc, String? rule) {
    if (rule == null || rule.trim().isEmpty) return null;
    final raw = rule.trim();

    if (looksLikeJs(raw) || raw.contains('下一页') || raw.contains('下一章')) {
      final selectMatch = RegExp(
        r'''document\.select\(\s*['"]([^'"]+)['"]\s*\)''',
      ).firstMatch(raw);
      final keywordMatch = RegExp(
        r'''indexOf\(\s*['"]([^'"]+)['"]\s*\)''',
      ).firstMatch(raw);
      final keyword = keywordMatch?.group(1) ?? '下一页';
      Iterable<Element> links;
      if (selectMatch != null) {
        try {
          links = doc.querySelectorAll(selectMatch.group(1)!);
        } catch (_) {
          links = doc.querySelectorAll('a');
        }
      } else {
        links = doc.querySelectorAll('a');
      }
      for (final link in links) {
        if (link.text.contains(keyword)) {
          final href = link.attributes['href']?.trim() ?? '';
          if (href.isNotEmpty && href != '#' && !href.startsWith('javascript:')) {
            return href;
          }
        }
      }
      return null;
    }

    final href = readFromDocument(doc, raw);
    if (href.isEmpty) return null;
    return href;
  }

  static dynamic decodeBody(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static List<dynamic> jsonList(dynamic root, String? listRule) {
    if (listRule == null || listRule.trim().isEmpty) {
      if (root is List) return root;
      return const [];
    }
    final (base, _) = splitAllInOne(listRule);
    final value = jsonPath(root, base);
    if (value is List) return value;
    return const [];
  }

  static String jsonField(dynamic item, String? rule) {
    if (rule == null || rule.trim().isEmpty) return '';
    final (base, replaces) = splitAllInOne(rule);
    final value = jsonPath(item, base);
    if (value == null) return '';
    return applyReplaces('$value'.trim(), replaces);
  }

  /// Supports `$.a.b`, `$.a.b[*]`, `$.a[*]`, and relative `a.b` / `name`.
  static dynamic jsonPath(dynamic root, String rule) {
    var path = rule.trim();
    if (path.startsWith(r'$.')) path = path.substring(2);
    if (path.startsWith(r'$')) path = path.substring(1);
    if (path.startsWith('.')) path = path.substring(1);
    if (path.isEmpty) return root;

    dynamic current = root;
    final parts = path.split('.');
    for (final rawPart in parts) {
      if (current == null) return null;
      var part = rawPart;
      var wantAll = false;
      if (part.endsWith('[*]')) {
        wantAll = true;
        part = part.substring(0, part.length - 3);
      }
      if (part.isNotEmpty) {
        if (current is Map) {
          current = current[part];
        } else {
          return null;
        }
      }
      if (wantAll) {
        if (current is List) {
          continue;
        }
        return null;
      }
    }
    return current;
  }

  static String htmlToPlain(String html) {
    final doc = html_parser.parseFragment(html);
    final buffer = StringBuffer();
    void walk(Node node) {
      if (node is Text) {
        buffer.write(node.text);
        return;
      }
      if (node is Element) {
        final tag = node.localName?.toLowerCase();
        if (tag == 'br' || tag == 'p' || tag == 'div') {
          if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
            buffer.writeln();
          }
        }
        for (final child in node.nodes) {
          walk(child);
        }
        if (tag == 'p' || tag == 'div') {
          if (!buffer.toString().endsWith('\n')) buffer.writeln();
        }
      }
    }

    for (final node in doc.nodes) {
      walk(node);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}

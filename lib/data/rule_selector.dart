import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Subset of Legado-style selectors:
/// - CSS: `.item`, `div.list a`, `#content`
/// - Legado shortcuts: `class.item` → `.item`, `id.content` → `#content`
/// - Attrs: `a@href`, `.title@text`, `#c@html`
/// - JSON: `$.data.list`, `$.name`, `name` (relative to object)
class RuleSelector {
  RuleSelector._();

  static String normalizeCss(String rule) {
    var r = rule.trim();
    if (r.startsWith('@css:')) r = r.substring(5);
    if (r.startsWith('class.')) r = '.${r.substring(6)}';
    if (r.startsWith('id.')) r = '#${r.substring(3)}';
    if (r.startsWith('tag.')) r = r.substring(4);
    return r.trim();
  }

  static (String selector, String attr) splitRule(String rule) {
    final at = rule.lastIndexOf('@');
    if (at <= 0) return (normalizeCss(rule), 'text');
    final left = rule.substring(0, at).trim();
    final right = rule.substring(at + 1).trim().toLowerCase();
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
    final (selector, attr) = splitRule(rule);
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
    return _attr(node, attr);
  }

  static String readFromDocument(Document doc, String? rule) {
    if (rule == null || rule.trim().isEmpty) return '';
    final (selector, attr) = splitRule(rule);
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
    return _attr(node, attr);
  }

  static String _attr(Element node, String attr) {
    switch (attr) {
      case 'href':
      case 'src':
      case 'value':
        return node.attributes[attr] ?? '';
      case 'html':
        return node.innerHtml;
      case 'text':
      default:
        return node.text.trim();
    }
  }

  static Document parseHtml(String html) => html_parser.parse(html);

  static bool isJsonRule(String? rule) {
    if (rule == null) return false;
    final t = rule.trim();
    return t.startsWith('\$') || t.startsWith('[');
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
    final value = jsonPath(root, listRule);
    if (value is List) return value;
    return const [];
  }

  static String jsonField(dynamic item, String? rule) {
    if (rule == null || rule.trim().isEmpty) return '';
    final value = jsonPath(item, rule);
    if (value == null) return '';
    return '$value'.trim();
  }

  /// Supports `$.a.b`, `$.a.b[*]`, `$.a[*]`, and relative `a.b` / `name`.
  static dynamic jsonPath(dynamic root, String rule) {
    var path = rule.trim();
    if (path.startsWith('\$.')) path = path.substring(2);
    if (path.startsWith('\$')) path = path.substring(1);
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
          // Keep list as current for final return; if more segments follow,
          // flatten map fields later.
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

import 'dart:convert';

import 'package:dio/dio.dart';

import 'rule_selector.dart';
import 'source_models.dart';

class SourceEngine {
  SourceEngine({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 20),
                responseType: ResponseType.plain,
                followRedirects: true,
                validateStatus: (code) => code != null && code >= 200 && code < 400,
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                  'Accept':
                      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                  'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
                },
              ),
            );

  final Dio _dio;

  Future<List<SearchBookHit>> search({
    required BookSource source,
    required String keyword,
    int page = 1,
  }) async {
    final searchUrl = source.searchUrl;
    if (searchUrl == null || searchUrl.trim().isEmpty) {
      throw StateError('书源未配置 searchUrl');
    }
    final rule = source.ruleSearch;
    if (rule == null) {
      throw StateError('书源未配置 ruleSearch');
    }

    final url = _buildUrl(
      base: source.bookSourceUrl,
      template: searchUrl,
      key: keyword,
      page: page,
    );
    final body = await _getBody(url, source);
    final bookListRule = rule['bookList'] as String?;

    if (RuleSelector.isJsonRule(bookListRule) ||
        body.trimLeft().startsWith('{') ||
        body.trimLeft().startsWith('[')) {
      final root = RuleSelector.decodeBody(body);
      if (root == null) return const [];
      final items = RuleSelector.jsonList(root, bookListRule);
      return [
        for (final item in items)
          if (item is Map)
            SearchBookHit(
              sourceId: source.id,
              sourceName: source.bookSourceName,
              name: RuleSelector.jsonField(item, rule['name'] as String?),
              author: _nullIfEmpty(
                RuleSelector.jsonField(item, rule['author'] as String?),
              ),
              intro: _nullIfEmpty(
                RuleSelector.jsonField(item, rule['intro'] as String?),
              ),
              coverUrl: _absUrl(
                source.bookSourceUrl,
                RuleSelector.jsonField(item, rule['coverUrl'] as String?),
              ),
              bookUrl: _absUrl(
                    source.bookSourceUrl,
                    RuleSelector.jsonField(item, rule['bookUrl'] as String?),
                  ) ??
                  '',
            ),
      ].where((e) => e.name.isNotEmpty && e.bookUrl.isNotEmpty).toList();
    }

    final doc = RuleSelector.parseHtml(body);
    final nodes = RuleSelector.selectList(doc, bookListRule);
    return [
      for (final node in nodes)
        SearchBookHit(
          sourceId: source.id,
          sourceName: source.bookSourceName,
          name: RuleSelector.readFromElement(node, rule['name'] as String?),
          author: _nullIfEmpty(
            RuleSelector.readFromElement(node, rule['author'] as String?),
          ),
          intro: _nullIfEmpty(
            RuleSelector.readFromElement(node, rule['intro'] as String?),
          ),
          coverUrl: _absUrl(
            source.bookSourceUrl,
            RuleSelector.readFromElement(node, rule['coverUrl'] as String?),
          ),
          bookUrl: _absUrl(
                url,
                RuleSelector.readFromElement(node, rule['bookUrl'] as String?),
              ) ??
              '',
        ),
    ].where((e) => e.name.isNotEmpty && e.bookUrl.isNotEmpty).toList();
  }

  Future<List<RemoteChapter>> fetchToc({
    required BookSource source,
    required String bookUrl,
  }) async {
    var tocUrl = bookUrl;
    final infoRule = source.ruleBookInfo;
    if (infoRule != null && (infoRule['tocUrl'] as String?)?.isNotEmpty == true) {
      final body = await _getBody(bookUrl, source);
      if (RuleSelector.isJsonRule(infoRule['tocUrl'] as String?) ||
          body.trimLeft().startsWith('{')) {
        final root = RuleSelector.decodeBody(body);
        final next = RuleSelector.jsonField(root, infoRule['tocUrl'] as String?);
        tocUrl = _absUrl(bookUrl, next) ?? bookUrl;
      } else {
        final doc = RuleSelector.parseHtml(body);
        final next =
            RuleSelector.readFromDocument(doc, infoRule['tocUrl'] as String?);
        tocUrl = _absUrl(bookUrl, next) ?? bookUrl;
      }
    }

    final rule = source.ruleToc;
    if (rule == null) {
      throw StateError('书源未配置 ruleToc');
    }
    final body = await _getBody(tocUrl, source);
    final listRule = rule['chapterList'] as String?;

    if (RuleSelector.isJsonRule(listRule) ||
        body.trimLeft().startsWith('{') ||
        body.trimLeft().startsWith('[')) {
      final root = RuleSelector.decodeBody(body);
      final items = RuleSelector.jsonList(root, listRule);
      return [
        for (final item in items)
          if (item is Map)
            RemoteChapter(
              title: RuleSelector.jsonField(
                item,
                rule['chapterName'] as String?,
              ),
              url: _absUrl(
                    tocUrl,
                    RuleSelector.jsonField(item, rule['chapterUrl'] as String?),
                  ) ??
                  '',
            ),
      ].where((e) => e.title.isNotEmpty && e.url.isNotEmpty).toList();
    }

    final doc = RuleSelector.parseHtml(body);
    final nodes = RuleSelector.selectList(doc, listRule);
    return [
      for (final node in nodes)
        RemoteChapter(
          title: RuleSelector.readFromElement(
            node,
            rule['chapterName'] as String?,
          ),
          url: _absUrl(
                tocUrl,
                RuleSelector.readFromElement(
                  node,
                  rule['chapterUrl'] as String?,
                ),
              ) ??
              '',
        ),
    ].where((e) => e.title.isNotEmpty && e.url.isNotEmpty).toList();
  }

  Future<String> fetchContent({
    required BookSource source,
    required String chapterUrl,
  }) async {
    final rule = source.ruleContent;
    if (rule == null) {
      throw StateError('书源未配置 ruleContent');
    }

    final buffer = StringBuffer();
    final visited = <String>{};
    var url = chapterUrl;
    var pages = 0;
    const maxPages = 30;

    while (url.isNotEmpty && pages < maxPages && visited.add(url)) {
      pages++;
      final body = await _getBody(url, source);
      final pageText = _extractContent(body, rule['content'] as String?);
      if (pageText.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(pageText);
      }

      final nextRule = rule['nextContentUrl'] as String?;
      if (nextRule == null || nextRule.trim().isEmpty) break;

      String? next;
      if (RuleSelector.isJsonRule(nextRule) || body.trimLeft().startsWith('{')) {
        final root = RuleSelector.decodeBody(body);
        next = RuleSelector.jsonField(root, nextRule);
      } else {
        final doc = RuleSelector.parseHtml(body);
        next = RuleSelector.resolveNextUrl(doc, nextRule);
      }
      final abs = _absUrl(url, next);
      if (abs == null || abs == url) break;
      url = abs;
    }

    var content = buffer.toString();
    content = _applyReplaceRegex(content, rule['replaceRegex'] as String?);
    return content.trim();
  }

  String _extractContent(String body, String? contentRule) {
    if (contentRule == null || contentRule.trim().isEmpty) return '';

    if (RuleSelector.isJsonRule(contentRule) || body.trimLeft().startsWith('{')) {
      final root = RuleSelector.decodeBody(body);
      var content = RuleSelector.jsonField(root, contentRule);
      if (content.contains('<') && content.contains('>')) {
        content = RuleSelector.htmlToPlain(content);
      }
      return content;
    }

    final doc = RuleSelector.parseHtml(body);
    final (base, replaces) = RuleSelector.splitAllInOne(contentRule);
    final (selector, attr) = RuleSelector.splitRule(base);

    String extracted;
    if (attr == 'html') {
      String html;
      if (selector.isEmpty) {
        html = doc.body?.innerHtml ?? '';
      } else {
        try {
          html = doc.querySelector(selector)?.innerHtml ?? '';
        } catch (_) {
          html = '';
        }
      }
      extracted = RuleSelector.htmlToPlain(html);
    } else {
      extracted = RuleSelector.readFromDocument(doc, base);
    }
    return RuleSelector.applyReplaces(extracted, replaces);
  }

  String _applyReplaceRegex(String content, String? replace) {
    if (replace == null || replace.trim().isEmpty) return content;
    var out = content;
    // Legado: pattern or pattern##replacement or ##pat##repl chains
    if (replace.contains('##')) {
      final normalized =
          replace.startsWith('##') ? 'x$replace' : 'x##$replace';
      final (_, replaces) = RuleSelector.splitAllInOne(normalized);
      return RuleSelector.applyReplaces(out, replaces);
    }
    try {
      out = out.replaceAll(RegExp(replace, dotAll: true), '');
    } catch (_) {
      out = out.replaceAll(replace, '');
    }
    return out;
  }

  Future<String> _getBody(String url, BookSource source) async {
    final headers = <String, dynamic>{};
    if (source.headerJson != null && source.headerJson!.trim().isNotEmpty) {
      try {
        final map = jsonDecode(source.headerJson!) as Map<String, dynamic>;
        map.forEach((k, v) => headers[k] = '$v');
      } catch (_) {
        // ignore invalid header json
      }
    }
    final response = await _dio.get<String>(url, options: Options(headers: headers));
    return response.data ?? '';
  }

  String _buildUrl({
    required String base,
    required String template,
    required String key,
    required int page,
  }) {
    // Strip Legado option JSON suffix: url,{...}
    var tpl = template;
    final optionAt = tpl.indexOf(',{');
    if (optionAt > 0) {
      tpl = tpl.substring(0, optionAt);
    }
    tpl = tpl
        .replaceAll('{{key}}', Uri.encodeQueryComponent(key))
        .replaceAll('{{page}}', '$page');
    return _absUrl(base, tpl) ?? tpl;
  }

  String? _absUrl(String base, String? maybe) {
    if (maybe == null) return null;
    final value = maybe.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return value;
    final baseUri = Uri.tryParse(base);
    if (baseUri == null) return value;
    return baseUri.resolve(value).toString();
  }

  String? _nullIfEmpty(String value) => value.trim().isEmpty ? null : value.trim();
}

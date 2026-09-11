import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'rule_selector.dart';
import 'source_models.dart';

class SourceEngine {
  SourceEngine({Dio? dio, this.webCorsProxyPrefix})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 15),
                responseType: ResponseType.plain,
                followRedirects: true,
                validateStatus: (code) =>
                    code != null && code >= 200 && code < 400,
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

  /// Optional custom CORS proxy prefix for Flutter Web, e.g.
  /// `https://your-worker.example/proxy?url=`
  final String? webCorsProxyPrefix;

  final Dio _dio;

  /// Public proxies are often blocked in CN; prefer a self-hosted prefix.
  static const defaultWebCorsProxy = 'https://corsproxy.io/?url=';
  static const _fallbackWebProxies = <String>[
    'https://api.allorigins.win/raw?url=',
    'https://api.codetabs.com/v1/proxy?quest=',
  ];

  Future<List<SearchBookHit>> search({
    required BookSource source,
    required String keyword,
    int page = 1,
  }) async {
    final searchUrl = source.searchUrl;
    if (searchUrl == null || searchUrl.trim().isEmpty) {
      throw StateError('书源未配置 searchUrl');
    }
    if (isUnsupportedSearchUrl(searchUrl)) {
      throw StateError('书源搜索含 JS/复杂脚本，暂不支持');
    }
    final rule = source.ruleSearch;
    if (rule == null) {
      throw StateError('书源未配置 ruleSearch');
    }
    if (RuleSelector.looksLikeJs(rule['bookList'] as String?)) {
      throw StateError('搜索列表规则含 JS，暂不支持');
    }

    final spec = _buildRequest(
      base: source.bookSourceUrl,
      template: searchUrl,
      key: keyword,
      page: page,
    );
    final body = await _requestBody(
      spec,
      source,
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
    );
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
                spec.url,
                RuleSelector.readFromElement(node, rule['bookUrl'] as String?),
              ) ??
              '',
        ),
    ].where((e) => e.name.isNotEmpty && e.bookUrl.isNotEmpty).toList();
  }

  static bool isUnsupportedSearchUrl(String? searchUrl) {
    if (searchUrl == null) return true;
    final t = searchUrl.trim().toLowerCase();
    if (t.isEmpty) return true;
    return t.contains('@js') ||
        t.contains('<js>') ||
        t.contains('{{url()') ||
        t.contains('java.') ||
        (t.contains('<js') && t.contains('</js>'));
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

  Future<String> _getBody(String url, BookSource source) {
    return _requestBody(
      SearchRequestSpec(url: url, method: 'GET'),
      source,
    );
  }

  Future<String> _requestBody(
    SearchRequestSpec spec,
    BookSource source, {
    Duration? connectTimeout,
    Duration? receiveTimeout,
  }) async {
    final headers = <String, dynamic>{};
    if (source.headerJson != null && source.headerJson!.trim().isNotEmpty) {
      try {
        final map = jsonDecode(source.headerJson!) as Map<String, dynamic>;
        map.forEach((k, v) => headers[k] = '$v');
      } catch (_) {
        // ignore invalid header json
      }
    }
    headers.addAll(spec.headers);

    final urls = <String>[];
    if (kIsWeb) {
      // Direct first (rare APIs allow CORS), then short-lived public proxies.
      urls.add(spec.url);
      final custom = webCorsProxyPrefix;
      if (custom != null && custom.trim().isNotEmpty) {
        urls.add(applyWebProxy(spec.url, prefix: custom.trim()));
      }
      urls.add(applyWebProxy(spec.url, prefix: defaultWebCorsProxy));
      for (final p in _fallbackWebProxies) {
        urls.add(applyWebProxy(spec.url, prefix: p));
      }
    } else {
      urls.add(spec.url);
    }

    DioException? last;
    for (final fetchUrl in urls) {
      try {
        final future = _execute(
          fetchUrl,
          spec,
          headers,
          receiveTimeout: receiveTimeout ??
              (kIsWeb ? const Duration(seconds: 6) : const Duration(seconds: 15)),
        );
        final ceiling = kIsWeb
            ? const Duration(seconds: 7)
            : ((connectTimeout ?? const Duration(seconds: 8)) +
                (receiveTimeout ?? const Duration(seconds: 15)));
        return await future.timeout(ceiling);
      } on DioException catch (e) {
        last = e;
      } on TimeoutException {
        // try next candidate
      }
    }
    if (last != null) {
      throw StateError(_friendlyNetworkError(last, spec.url));
    }
    throw StateError(
      kIsWeb
          ? 'Web 跨域/代理不可用，请用 Android 或 Windows 客户端搜书'
          : '请求超时: ${spec.url}',
    );
  }

  Future<String> _execute(
    String fetchUrl,
    SearchRequestSpec spec,
    Map<String, dynamic> headers, {
    Duration? receiveTimeout,
  }) async {
    final options = Options(
      headers: headers,
      sendTimeout: const Duration(seconds: 6),
      receiveTimeout: receiveTimeout ?? const Duration(seconds: 20),
    );
    // Dio BaseOptions connectTimeout isn't overridable per-request on all
    // adapters; wrap with Future.timeout as a hard ceiling in the UI layer.
    final Response<String> response;
    if (spec.method == 'POST') {
      response = await _dio.post<String>(
        fetchUrl,
        data: spec.body,
        options: options.copyWith(
          contentType: headers['Content-Type'] as String? ??
              headers['content-type'] as String? ??
              Headers.formUrlEncodedContentType,
        ),
      );
    } else {
      response = await _dio.get<String>(fetchUrl, options: options);
    }
    return response.data ?? '';
  }

  String _friendlyNetworkError(DioException e, String url) {
    if (kIsWeb) {
      return 'Web 无法直连书源（跨域/代理超时）。请用 Android 或 Windows 客户端搜索。';
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return '连接超时';
    }
    if (e.response?.statusCode != null) {
      return 'HTTP ${e.response!.statusCode}';
    }
    return e.message ?? e.toString();
  }

  /// Visible for tests.
  static String applyWebProxy(String url, {String? prefix}) {
    final p = prefix ?? defaultWebCorsProxy;
    if (url.contains('corsproxy.io/') ||
        url.contains('allorigins.win/') ||
        url.contains('codetabs.com/')) {
      return url;
    }
    if (url.startsWith(p)) return url;
    return '$p${Uri.encodeComponent(url)}';
  }

  /// Parses Legado `url,{json options}` templates. Exposed for unit tests.
  static SearchRequestSpec parseSearchTemplate({
    required String base,
    required String template,
    required String key,
    required int page,
  }) {
    var tpl = template.trim();
    Map<String, dynamic> options = const {};
    final optMatch = RegExp(r',(\{[\s\S]*\})\s*$').firstMatch(tpl);
    if (optMatch != null) {
      final optRaw = optMatch.group(1)!;
      tpl = tpl.substring(0, optMatch.start).trim();
      try {
        final decoded = jsonDecode(optRaw);
        if (decoded is Map<String, dynamic>) {
          options = decoded;
        } else if (decoded is Map) {
          options = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // keep empty options
      }
    }

    String replaceVars(String input) {
      return input
          .replaceAll('{{key}}', Uri.encodeQueryComponent(key))
          .replaceAll('{{page}}', '$page');
    }

    tpl = replaceVars(tpl);
    final abs = _absUrlStatic(base, tpl) ?? tpl;

    final method = ('${options['method'] ?? 'GET'}').toUpperCase().trim();
    final headers = <String, String>{};
    final rawHeaders = options['headers'];
    if (rawHeaders is String && rawHeaders.trim().isNotEmpty) {
      try {
        final map = jsonDecode(rawHeaders) as Map<String, dynamic>;
        map.forEach((k, v) => headers[k] = '$v');
      } catch (_) {
        // ignore invalid headers json
      }
    } else if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) => headers['$k'] = '$v');
    }

    String? body;
    final rawBody = options['body'];
    if (rawBody != null) {
      body = replaceVars('$rawBody');
    }

    return SearchRequestSpec(
      url: abs,
      method: method == 'POST' ? 'POST' : 'GET',
      body: body,
      headers: headers,
    );
  }

  SearchRequestSpec _buildRequest({
    required String base,
    required String template,
    required String key,
    required int page,
  }) {
    return parseSearchTemplate(
      base: base,
      template: template,
      key: key,
      page: page,
    );
  }

  String? _absUrl(String base, String? maybe) => _absUrlStatic(base, maybe);

  static String? _absUrlStatic(String base, String? maybe) {
    if (maybe == null) return null;
    final value = maybe.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return value;
    final baseUri = Uri.tryParse(base);
    if (baseUri == null) return value;
    return baseUri.resolve(value).toString();
  }

  String? _nullIfEmpty(String value) =>
      value.trim().isEmpty ? null : value.trim();
}

class SearchRequestSpec {
  const SearchRequestSpec({
    required this.url,
    required this.method,
    this.body,
    this.headers = const {},
  });

  final String url;
  final String method;
  final String? body;
  final Map<String, String> headers;
}

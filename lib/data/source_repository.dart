import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'plist_source_converter.dart';
import 'source_models.dart';

class SourceRepository {
  SourceRepository({Dio? dio}) : _dio = dio ?? Dio();

  static const _key = 'inkshelf.sources';
  final _uuid = const Uuid();
  final Dio _dio;

  Future<List<BookSource>> loadSources() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => BookSource.fromStorageJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save(List<BookSource> sources) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(sources.map((s) => s.toStorageJson()).toList()),
    );
  }

  Future<List<BookSource>> importJsonText(String text) async {
    var payload = text.trim();
    if (_looksLikeUrl(payload)) {
      payload = await _fetchRemoteJson(payload);
    }
    if (payload.startsWith('\uFEFF')) {
      payload = payload.substring(1);
    }

    final items = <Map<String, dynamic>>[];

    if (PlistSourceConverter.looksLikePlist(payload)) {
      items.addAll(PlistSourceConverter.convert(payload));
    } else {
      dynamic decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        throw const FormatException(
          '不是合法的书源。请导入 Legado JSON，或含 search/chapters/content 的站点 plist。',
        );
      }
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            items.add(Map<String, dynamic>.from(item));
          }
        }
      } else if (decoded is Map) {
        items.add(Map<String, dynamic>.from(decoded));
      } else {
        throw const FormatException('书源 JSON 格式无效');
      }
    }

    if (items.isEmpty) {
      throw const FormatException('未解析到书源');
    }

    final existing = await loadSources();
    final byUrl = {
      for (final s in existing) s.bookSourceUrl: s,
    };

    for (final item in items) {
      final incoming = BookSource.fromLegadoJson(item, id: _uuid.v4());
      final old = byUrl[incoming.bookSourceUrl];
      if (old != null) {
        byUrl[incoming.bookSourceUrl] = BookSource.fromLegadoJson(
          item,
          id: old.id,
          enabled: old.enabled,
        );
      } else {
        byUrl[incoming.bookSourceUrl] = incoming;
      }
    }

    final next = byUrl.values.toList()
      ..sort((a, b) => a.bookSourceName.compareTo(b.bookSourceName));
    await _save(next);
    return next;
  }

  bool _looksLikeUrl(String text) {
    if (text.contains('\n') || text.contains('{') || text.contains('[')) {
      return false;
    }
    final uri = Uri.tryParse(text);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  String _toRawUrl(String url) {
    var u = url.trim();
    if (u.contains('gitee.com/') && u.contains('/blob/')) {
      u = u.replaceFirst('/blob/', '/raw/');
    }
    // Prefer CDN host to avoid an extra gitee.com → raw.giteeusercontent.com hop.
    final giteeRaw = RegExp(
      r'^https?://gitee\.com/([^/]+)/([^/]+)/raw/(.+)$',
    ).firstMatch(u);
    if (giteeRaw != null) {
      u =
          'https://raw.giteeusercontent.com/${giteeRaw.group(1)}/${giteeRaw.group(2)}/raw/${giteeRaw.group(3)}';
    }
    if (u.contains('github.com/') && u.contains('/blob/')) {
      u = u
          .replaceFirst(
            'https://github.com/',
            'https://raw.githubusercontent.com/',
          )
          .replaceFirst(
            'http://github.com/',
            'https://raw.githubusercontent.com/',
          )
          .replaceFirst('/blob/', '/');
    }
    return u;
  }

  Future<String> _fetchRemoteJson(String url) async {
    final rawUrl = _toRawUrl(url);
    final candidates = <String>[rawUrl];
    if (kIsWeb) {
      // Public proxies may help when origin hosts lack CORS (often flaky in CN).
      candidates.addAll([
        'https://corsproxy.io/?url=${Uri.encodeComponent(rawUrl)}',
        'https://api.allorigins.win/raw?url=${Uri.encodeComponent(rawUrl)}',
        'https://api.codetabs.com/v1/proxy?quest=${Uri.encodeComponent(rawUrl)}',
      ]);
    }

    Object? lastError;
    for (final fetchUrl in candidates) {
      try {
        final response = await _dio
            .get<String>(
              fetchUrl,
              options: Options(
                responseType: ResponseType.plain,
                followRedirects: true,
                sendTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15),
                validateStatus: (code) =>
                    code != null && code >= 200 && code < 400,
                // Web: avoid non-safelist headers (User-Agent triggers CORS preflight).
                headers: kIsWeb
                    ? const {'Accept': '*/*'}
                    : {
                        'Accept':
                            'application/json,text/plain,application/xml,*/*',
                        'User-Agent':
                            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                      },
              ),
            )
            .timeout(Duration(seconds: kIsWeb ? 8 : 20));

        final body = (response.data ?? '').trim();
        if (body.isEmpty) {
          lastError = '内容为空';
          continue;
        }
        if (body.startsWith('<!') && !body.contains('<plist')) {
          lastError = '拿到的是网页而不是书源文件';
          continue;
        }
        return body;
      } on DioException catch (e) {
        lastError = e.message ?? e.type;
      } on TimeoutException {
        lastError = '超时';
      } catch (e) {
        lastError = e;
      }
    }

    if (kIsWeb) {
      throw const FormatException(
        '浏览器无法直接下载该链接（跨域限制）。请打开链接复制全文后点「粘贴 JSON」，或改用 Android/Windows 客户端导入。',
      );
    }
    throw FormatException(
      '下载书源失败：$lastError。可改用粘贴 JSON/plist 正文。',
    );
  }

  Future<String> exportJsonText() async {
    final sources = await loadSources();
    if (sources.isEmpty) {
      throw const FormatException('没有可导出的书源');
    }
    final list = [
      for (final s in sources) Map<String, dynamic>.from(s.raw),
    ];
    return const JsonEncoder.withIndent('  ').convert(list);
  }

  Future<List<BookSource>> setEnabled(String id, bool enabled) async {
    final sources = await loadSources();
    final next = [
      for (final s in sources)
        if (s.id == id) s.copyWith(enabled: enabled) else s,
    ];
    await _save(next);
    return next;
  }

  Future<List<BookSource>> deleteSource(String id) async {
    final sources = await loadSources();
    sources.removeWhere((s) => s.id == id);
    await _save(sources);
    return sources;
  }

  Future<List<BookSource>> clearAll() async {
    await _save(const []);
    return const [];
  }
}

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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

    final decoded = jsonDecode(payload);
    final items = <Map<String, dynamic>>[];
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
    final response = await _dio.get<String>(
      rawUrl,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (code) => code != null && code >= 200 && code < 400,
        headers: {
          'Accept': 'application/json,text/plain,*/*',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        },
      ),
    );
    final body = (response.data ?? '').trim();
    if (body.isEmpty) {
      throw const FormatException('远程书源内容为空');
    }
    if (body.startsWith('<!') || body.startsWith('<html')) {
      throw const FormatException(
        '拿到的是网页而不是 JSON，请使用 raw 链接或粘贴 JSON 正文',
      );
    }
    return body;
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
}

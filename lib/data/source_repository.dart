import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'source_models.dart';

class SourceRepository {
  SourceRepository();

  static const _key = 'inkshelf.sources';
  final _uuid = const Uuid();

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
    final decoded = jsonDecode(text);
    final items = <Map<String, dynamic>>[];
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) items.add(item);
        if (item is Map) items.add(Map<String, dynamic>.from(item));
      }
    } else if (decoded is Map<String, dynamic>) {
      items.add(decoded);
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

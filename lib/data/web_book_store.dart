import 'package:hive_flutter/hive_flutter.dart';

/// Large book payloads for Flutter Web (IndexedDB via Hive).
/// Avoids localStorage QuotaExceededError for long novels.
class WebBookStore {
  WebBookStore._();

  static const _boxName = 'inkshelf_web_books';
  static Box<String>? _box;

  static Future<void> ensureReady() async {
    if (_box != null && _box!.isOpen) return;
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
  }

  static Future<Box<String>> _b() async {
    await ensureReady();
    return _box!;
  }

  static Future<void> put(String key, String value) async {
    final box = await _b();
    await box.put(key, value);
  }

  static Future<String?> get(String key) async {
    final box = await _b();
    return box.get(key);
  }

  static Future<void> delete(String key) async {
    final box = await _b();
    await box.delete(key);
  }

  static Future<void> deletePrefix(String prefix) async {
    final box = await _b();
    final keys = box.keys.whereType<String>().where((k) => k.startsWith(prefix));
    for (final key in keys.toList()) {
      await box.delete(key);
    }
  }
}

import 'dart:typed_data';

/// Native filesystem helpers (mobile / desktop).
Future<void> fsWriteString(String path, String content) async {
  throw UnsupportedError('fsWriteString unavailable');
}

Future<String?> fsReadString(String path) async => null;

Future<Uint8List?> fsReadBytes(String path) async => null;

Future<void> fsEnsureDir(String path) async {}

Future<void> fsDeleteRecursive(String path) async {}

Future<String> fsBooksRootPath() async {
  throw UnsupportedError('filesystem unavailable on this platform');
}

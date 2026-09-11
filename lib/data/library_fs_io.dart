import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> fsWriteString(String path, String content) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content, flush: true);
}

Future<String?> fsReadString(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsString();
}

Future<Uint8List?> fsReadBytes(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsBytes();
}

Future<void> fsEnsureDir(String path) async {
  final dir = Directory(path);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
}

Future<void> fsDeleteRecursive(String path) async {
  final dir = Directory(path);
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}

Future<String> fsBooksRootPath() async {
  final docs = await getApplicationDocumentsDirectory();
  final root = p.join(docs.path, 'inkshelf', 'books');
  await fsEnsureDir(root);
  return root;
}

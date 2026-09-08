import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'chapter_splitter.dart';
import 'models.dart';
import 'source_engine.dart';
import 'source_models.dart';
import 'source_repository.dart';
import 'text_decoder.dart';

class LibraryRepository {
  LibraryRepository({
    SourceEngine? sourceEngine,
    SourceRepository? sourceRepository,
  })  : _sourceEngine = sourceEngine ?? SourceEngine(),
        _sourceRepository = sourceRepository ?? SourceRepository();

  static const _booksKey = 'inkshelf.books';
  static const _prefsKey = 'inkshelf.reader_prefs';
  final _uuid = const Uuid();
  final SourceEngine _sourceEngine;
  final SourceRepository _sourceRepository;

  Future<Directory> _booksRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'inkshelf', 'books'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _bookDir(String id) async {
    final root = await _booksRoot();
    final dir = Directory(p.join(root.path, id));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<Book>> loadBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_booksKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    final books = list
        .map((e) => Book.fromJson(e as Map<String, dynamic>))
        .toList();
    books.sort((a, b) {
      final aTime = a.lastReadAt ?? a.addedAt;
      final bTime = b.lastReadAt ?? b.addedAt;
      return bTime.compareTo(aTime);
    });
    return books;
  }

  Future<void> _saveBooks(List<Book> books) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _booksKey,
      jsonEncode(books.map((b) => b.toJson()).toList()),
    );
  }

  Future<ReaderPrefs> loadReaderPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const ReaderPrefs();
    return ReaderPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveReaderPrefs(ReaderPrefs value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(value.toJson()));
  }

  Future<List<ChapterRef>> loadChapters(String bookId) async {
    final dir = await _bookDir(bookId);
    final file = File(p.join(dir.path, 'chapters.json'));
    if (!await file.exists()) return [];
    final list = jsonDecode(await file.readAsString()) as List<dynamic>;
    return list
        .map((e) => ChapterRef.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> loadChapterText(String bookId, ChapterRef chapter) async {
    final dir = await _bookDir(bookId);
    if (chapter.isRemote) {
      final cache = File(p.join(dir.path, 'cache', '${chapter.index}.txt'));
      if (await cache.exists()) {
        return (await cache.readAsString()).trim();
      }

      final books = await loadBooks();
      Book? book;
      for (final item in books) {
        if (item.id == bookId) {
          book = item;
          break;
        }
      }
      if (book == null || book.sourceId == null) {
        throw StateError('远程书籍缺少书源信息');
      }
      final sources = await _sourceRepository.loadSources();
      BookSource? source;
      for (final item in sources) {
        if (item.id == book.sourceId) {
          source = item;
          break;
        }
      }
      if (source == null) {
        throw StateError('找不到对应书源，可能已被删除');
      }

      final text = await _sourceEngine.fetchContent(
        source: source,
        chapterUrl: chapter.url!,
      );
      await cache.parent.create(recursive: true);
      await cache.writeAsString(text, flush: true);
      return text;
    }

    final file = File(p.join(dir.path, 'content.txt'));
    final text = await file.readAsString();
    final start = chapter.start.clamp(0, text.length);
    final end = chapter.end.clamp(start, text.length);
    return text.substring(start, end).trim();
  }

  Future<Book> importTxtFile({
    required String sourcePath,
    required String displayName,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    final text = await TextDecoder.decodeBytes(bytes);
    final splits = ChapterSplitter.split(text);

    final id = _uuid.v4();
    final dir = await _bookDir(id);
    final contentFile = File(p.join(dir.path, 'content.txt'));
    await contentFile.writeAsString(text, flush: true);

    final chapters = <ChapterRef>[
      for (var i = 0; i < splits.length; i++)
        ChapterRef(
          index: i,
          title: splits[i].title,
          start: splits[i].start,
          end: splits[i].end,
        ),
    ];
    await File(p.join(dir.path, 'chapters.json')).writeAsString(
      jsonEncode(chapters.map((c) => c.toJson()).toList()),
      flush: true,
    );

    final title =
        displayName.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '');
    final book = Book(
      id: id,
      title: title.isEmpty ? '未命名' : title,
      fileName: displayName,
      chapterCount: chapters.length,
      addedAt: DateTime.now(),
      origin: BookOrigin.local,
    );

    final books = await loadBooks();
    books.insert(0, book);
    await _saveBooks(books);
    return book;
  }

  Future<Book> addRemoteBook({
    required SearchBookHit hit,
    required BookSource source,
  }) async {
    final chaptersRemote = await _sourceEngine.fetchToc(
      source: source,
      bookUrl: hit.bookUrl,
    );
    if (chaptersRemote.isEmpty) {
      throw StateError('未解析到目录章节');
    }

    final id = _uuid.v4();
    final dir = await _bookDir(id);
    final chapters = <ChapterRef>[
      for (var i = 0; i < chaptersRemote.length; i++)
        ChapterRef(
          index: i,
          title: chaptersRemote[i].title,
          url: chaptersRemote[i].url,
        ),
    ];
    await File(p.join(dir.path, 'chapters.json')).writeAsString(
      jsonEncode(chapters.map((c) => c.toJson()).toList()),
      flush: true,
    );
    await File(p.join(dir.path, 'meta.json')).writeAsString(
      jsonEncode({
        'sourceId': source.id,
        'sourceName': source.bookSourceName,
        'bookUrl': hit.bookUrl,
      }),
      flush: true,
    );

    final book = Book(
      id: id,
      title: hit.name,
      author: hit.author,
      fileName: hit.bookUrl,
      chapterCount: chapters.length,
      addedAt: DateTime.now(),
      origin: BookOrigin.remote,
      sourceId: source.id,
      bookUrl: hit.bookUrl,
    );

    final books = await loadBooks();
    books.insert(0, book);
    await _saveBooks(books);
    return book;
  }

  Future<void> updateProgress({
    required String bookId,
    required int chapterIndex,
    required double scrollOffset,
  }) async {
    final books = await loadBooks();
    final index = books.indexWhere((b) => b.id == bookId);
    if (index < 0) return;
    books[index] = books[index].copyWith(
      lastChapterIndex: chapterIndex,
      lastScrollOffset: scrollOffset,
      lastReadAt: DateTime.now(),
    );
    await _saveBooks(books);
  }

  Future<void> deleteBook(String bookId) async {
    final books = await loadBooks();
    books.removeWhere((b) => b.id == bookId);
    await _saveBooks(books);
    final root = await _booksRoot();
    final dir = Directory(p.join(root.path, bookId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

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

  Future<Book?> getBook(String bookId) async {
    final books = await loadBooks();
    for (final book in books) {
      if (book.id == bookId) return book;
    }
    return null;
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

  String _bookmarksKey(String bookId) => 'inkshelf.bookmarks.$bookId';

  Future<List<Bookmark>> loadBookmarks(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_bookmarksKey(bookId));
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<Bookmark>> saveBookmarks(
    String bookId,
    List<Bookmark> bookmarks,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _bookmarksKey(bookId),
      jsonEncode(bookmarks.map((b) => b.toJson()).toList()),
    );
    return bookmarks;
  }

  Future<List<Bookmark>> addBookmark({
    required String bookId,
    required int chapterIndex,
    required String title,
    double scrollOffset = 0,
  }) async {
    final list = await loadBookmarks(bookId);
    final exists = list.any((b) => b.chapterIndex == chapterIndex);
    if (exists) return list;
    list.insert(
      0,
      Bookmark(
        id: _uuid.v4(),
        chapterIndex: chapterIndex,
        title: title,
        createdAt: DateTime.now(),
        scrollOffset: scrollOffset,
      ),
    );
    return saveBookmarks(bookId, list);
  }

  Future<List<Bookmark>> removeBookmark(String bookId, String bookmarkId) async {
    final list = await loadBookmarks(bookId);
    list.removeWhere((b) => b.id == bookmarkId);
    return saveBookmarks(bookId, list);
  }

  Future<List<Bookmark>> toggleBookmark({
    required String bookId,
    required int chapterIndex,
    required String title,
    double scrollOffset = 0,
  }) async {
    final list = await loadBookmarks(bookId);
    final existing = list.where((b) => b.chapterIndex == chapterIndex).toList();
    if (existing.isNotEmpty) {
      list.removeWhere((b) => b.chapterIndex == chapterIndex);
      return saveBookmarks(bookId, list);
    }
    return addBookmark(
      bookId: bookId,
      chapterIndex: chapterIndex,
      title: title,
      scrollOffset: scrollOffset,
    );
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

  Future<Map<String, dynamic>?> loadBookMeta(String bookId) async {
    final dir = await _bookDir(bookId);
    final file = File(p.join(dir.path, 'meta.json'));
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  Future<String> loadChapterText(String bookId, ChapterRef chapter) async {
    final dir = await _bookDir(bookId);
    if (chapter.isRemote) {
      final cache = File(p.join(dir.path, 'cache', '${chapter.index}.txt'));
      if (await cache.exists()) {
        return (await cache.readAsString()).trim();
      }

      final book = await getBook(bookId);
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
        'coverUrl': hit.coverUrl,
        'intro': hit.intro,
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
      coverUrl: hit.coverUrl,
      intro: hit.intro,
      sourceName: source.bookSourceName,
    );

    final books = await loadBooks();
    books.insert(0, book);
    await _saveBooks(books);
    return book;
  }

  Future<Book> refreshRemoteToc(String bookId) async {
    final book = await getBook(bookId);
    if (book == null) throw StateError('找不到书籍');
    if (!book.isRemote || book.sourceId == null || book.bookUrl == null) {
      throw StateError('本地书不支持章节刷新');
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

    final chaptersRemote = await _sourceEngine.fetchToc(
      source: source,
      bookUrl: book.bookUrl!,
    );
    if (chaptersRemote.isEmpty) {
      throw StateError('未解析到目录章节');
    }

    final dir = await _bookDir(bookId);
    final oldChapters = await loadChapters(bookId);
    final oldByIndex = {
      for (final c in oldChapters) c.index: c.url,
    };

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

    final cacheDir = Directory(p.join(dir.path, 'cache'));
    if (await cacheDir.exists()) {
      await for (final entity in cacheDir.list()) {
        if (entity is! File) continue;
        final name = p.basenameWithoutExtension(entity.path);
        final idx = int.tryParse(name);
        if (idx == null) continue;
        final newUrl = idx < chapters.length ? chapters[idx].url : null;
        final oldUrl = oldByIndex[idx];
        if (newUrl != oldUrl) {
          await entity.delete();
        }
      }
    }

    final books = await loadBooks();
    final index = books.indexWhere((b) => b.id == bookId);
    if (index < 0) throw StateError('找不到书籍');
    final clampedChapter =
        book.lastChapterIndex.clamp(0, chapters.length - 1);
    books[index] = books[index].copyWith(
      chapterCount: chapters.length,
      lastChapterIndex: clampedChapter,
      sourceName: source.bookSourceName,
    );
    await _saveBooks(books);
    return books[index];
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bookmarksKey(bookId));
    final root = await _booksRoot();
    final dir = Directory(p.join(root.path, bookId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

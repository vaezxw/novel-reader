import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'chapter_splitter.dart';
import 'library_fs_stub.dart' if (dart.library.io) 'library_fs_io.dart' as fs;
import 'models.dart';
import 'source_engine.dart';
import 'source_models.dart';
import 'source_repository.dart';
import 'text_decoder.dart';
import 'web_book_store.dart';

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

  String _contentKey(String bookId) => 'inkshelf.content.$bookId';
  String _chaptersKey(String bookId) => 'inkshelf.chapters.$bookId';
  String _metaKey(String bookId) => 'inkshelf.meta.$bookId';
  String _cacheKey(String bookId, int index) =>
      'inkshelf.cache.$bookId.$index';

  Future<String> _bookDirPath(String id) async {
    final root = await fs.fsBooksRootPath();
    final dir = p.join(root, id);
    await fs.fsEnsureDir(dir);
    return dir;
  }

  Future<void> _writeChapters(String bookId, List<ChapterRef> chapters) async {
    final raw = jsonEncode(chapters.map((c) => c.toJson()).toList());
    if (kIsWeb) {
      await WebBookStore.put(_chaptersKey(bookId), raw);
      return;
    }
    final dir = await _bookDirPath(bookId);
    await fs.fsWriteString(p.join(dir, 'chapters.json'), raw);
  }

  Future<void> _writeContent(String bookId, String text) async {
    if (kIsWeb) {
      await WebBookStore.put(_contentKey(bookId), text);
      return;
    }
    final dir = await _bookDirPath(bookId);
    await fs.fsWriteString(p.join(dir, 'content.txt'), text);
  }

  Future<void> _writeMeta(String bookId, Map<String, dynamic> meta) async {
    final raw = jsonEncode(meta);
    if (kIsWeb) {
      await WebBookStore.put(_metaKey(bookId), raw);
      return;
    }
    final dir = await _bookDirPath(bookId);
    await fs.fsWriteString(p.join(dir, 'meta.json'), raw);
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
    if (kIsWeb) {
      final raw = await WebBookStore.get(_chaptersKey(bookId));
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ChapterRef.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final dir = await _bookDirPath(bookId);
    final raw = await fs.fsReadString(p.join(dir, 'chapters.json'));
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => ChapterRef.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>?> loadBookMeta(String bookId) async {
    if (kIsWeb) {
      final raw = await WebBookStore.get(_metaKey(bookId));
      if (raw == null || raw.isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    }
    final dir = await _bookDirPath(bookId);
    final raw = await fs.fsReadString(p.join(dir, 'meta.json'));
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<String> loadChapterText(String bookId, ChapterRef chapter) async {
    if (chapter.isRemote) {
      if (kIsWeb) {
        final cached = await WebBookStore.get(_cacheKey(bookId, chapter.index));
        if (cached != null && cached.isNotEmpty) return cached.trim();
      } else {
        final dir = await _bookDirPath(bookId);
        final cached =
            await fs.fsReadString(p.join(dir, 'cache', '${chapter.index}.txt'));
        if (cached != null && cached.isNotEmpty) return cached.trim();
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
      if (kIsWeb) {
        await WebBookStore.put(_cacheKey(bookId, chapter.index), text);
      } else {
        final dir = await _bookDirPath(bookId);
        await fs.fsWriteString(
          p.join(dir, 'cache', '${chapter.index}.txt'),
          text,
        );
      }
      return text;
    }

    String? full;
    if (kIsWeb) {
      full = await WebBookStore.get(_contentKey(bookId));
    } else {
      final dir = await _bookDirPath(bookId);
      full = await fs.fsReadString(p.join(dir, 'content.txt'));
    }
    if (full == null) throw StateError('找不到书籍正文');
    final start = chapter.start.clamp(0, full.length);
    final end = chapter.end.clamp(start, full.length);
    return full.substring(start, end).trim();
  }

  Future<Book> importTxtFile({
    String? sourcePath,
    Uint8List? bytes,
    required String displayName,
  }) async {
    late final Uint8List data;
    if (bytes != null) {
      data = bytes;
    } else if (sourcePath != null && !kIsWeb) {
      final read = await fs.fsReadBytes(sourcePath);
      if (read == null) throw StateError('无法读取文件');
      data = read;
    } else {
      throw StateError('浏览器请选择本地文件（需读取文件内容）');
    }

    final text = await TextDecoder.decodeBytes(data);
    final splits = ChapterSplitter.split(text);

    final id = _uuid.v4();
    await _writeContent(id, text);

    final chapters = <ChapterRef>[
      for (var i = 0; i < splits.length; i++)
        ChapterRef(
          index: i,
          title: splits[i].title,
          start: splits[i].start,
          end: splits[i].end,
        ),
    ];
    await _writeChapters(id, chapters);

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
    final chapters = <ChapterRef>[
      for (var i = 0; i < chaptersRemote.length; i++)
        ChapterRef(
          index: i,
          title: chaptersRemote[i].title,
          url: chaptersRemote[i].url,
        ),
    ];
    await _writeChapters(id, chapters);
    await _writeMeta(id, {
      'sourceId': source.id,
      'sourceName': source.bookSourceName,
      'bookUrl': hit.bookUrl,
      'coverUrl': hit.coverUrl,
      'intro': hit.intro,
    });

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

    final oldChapters = await loadChapters(bookId);

    final chapters = <ChapterRef>[
      for (var i = 0; i < chaptersRemote.length; i++)
        ChapterRef(
          index: i,
          title: chaptersRemote[i].title,
          url: chaptersRemote[i].url,
        ),
    ];
    await _writeChapters(bookId, chapters);

    for (final old in oldChapters) {
      final newUrl =
          old.index < chapters.length ? chapters[old.index].url : null;
      if (newUrl != old.url) {
        if (kIsWeb) {
          await WebBookStore.delete(_cacheKey(bookId, old.index));
        } else {
          final dir = await _bookDirPath(bookId);
          await fs.fsDeleteRecursive(p.join(dir, 'cache'));
          break;
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
    if (kIsWeb) {
      await WebBookStore.delete(_contentKey(bookId));
      await WebBookStore.delete(_chaptersKey(bookId));
      await WebBookStore.delete(_metaKey(bookId));
      await WebBookStore.deletePrefix('inkshelf.cache.$bookId.');
    } else {
      final root = await fs.fsBooksRootPath();
      await fs.fsDeleteRecursive(p.join(root, bookId));
    }
  }
}

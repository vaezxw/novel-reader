import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

import '../data/library_repository.dart';
import '../data/models.dart';
import '../data/source_engine.dart';
import '../data/source_models.dart';
import '../data/source_repository.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(
    sourceEngine: ref.watch(sourceEngineProvider),
    sourceRepository: ref.watch(sourceRepositoryProvider),
  );
});

final sourceRepositoryProvider = Provider<SourceRepository>((ref) {
  return SourceRepository();
});

final sourceEngineProvider = Provider<SourceEngine>((ref) {
  return SourceEngine();
});

final booksProvider =
    AsyncNotifierProvider<BooksNotifier, List<Book>>(BooksNotifier.new);

class BooksNotifier extends AsyncNotifier<List<Book>> {
  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  @override
  Future<List<Book>> build() => _repo.loadBooks();

  Future<Book> importTxt({
    String? sourcePath,
    List<int>? bytes,
    required String displayName,
  }) async {
    final book = await _repo.importTxtFile(
      sourcePath: sourcePath,
      bytes: bytes == null ? null : Uint8List.fromList(bytes),
      displayName: displayName,
    );
    state = AsyncData(await _repo.loadBooks());
    return book;
  }

  Future<Book> addRemote(SearchBookHit hit, BookSource source) async {
    final book = await _repo.addRemoteBook(hit: hit, source: source);
    state = AsyncData(await _repo.loadBooks());
    return book;
  }

  Future<void> deleteBook(String id) async {
    await _repo.deleteBook(id);
    state = AsyncData(await _repo.loadBooks());
  }

  Future<void> refresh() async {
    state = AsyncData(await _repo.loadBooks());
  }

  Future<Book> refreshRemoteToc(String bookId) async {
    final book = await _repo.refreshRemoteToc(bookId);
    state = AsyncData(await _repo.loadBooks());
    ref.invalidate(chaptersProvider(bookId));
    return book;
  }

  Future<void> saveProgress({
    required String bookId,
    required int chapterIndex,
    required double scrollOffset,
  }) async {
    await _repo.updateProgress(
      bookId: bookId,
      chapterIndex: chapterIndex,
      scrollOffset: scrollOffset,
    );
    final current = state.value;
    if (current == null) {
      state = AsyncData(await _repo.loadBooks());
      return;
    }
    state = AsyncData([
      for (final book in current)
        if (book.id == bookId)
          book.copyWith(
            lastChapterIndex: chapterIndex,
            lastScrollOffset: scrollOffset,
            lastReadAt: DateTime.now(),
          )
        else
          book,
    ]);
  }
}

final readerPrefsProvider =
    AsyncNotifierProvider<ReaderPrefsNotifier, ReaderPrefs>(
  ReaderPrefsNotifier.new,
);

class ReaderPrefsNotifier extends AsyncNotifier<ReaderPrefs> {
  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  @override
  Future<ReaderPrefs> build() => _repo.loadReaderPrefs();

  Future<void> setPrefs(ReaderPrefs Function(ReaderPrefs) transform) async {
    final current = state.value ?? const ReaderPrefs();
    final next = transform(current);
    state = AsyncData(next);
    await _repo.saveReaderPrefs(next);
  }
}

final chaptersProvider =
    FutureProvider.family<List<ChapterRef>, String>((ref, bookId) async {
  return ref.read(libraryRepositoryProvider).loadChapters(bookId);
});

final bookmarksProvider =
    FutureProvider.family<List<Bookmark>, String>((ref, bookId) async {
  return ref.read(libraryRepositoryProvider).loadBookmarks(bookId);
});

Future<bool> toggleBookmarkForBook(
  WidgetRef ref, {
  required String bookId,
  required int chapterIndex,
  required String title,
  double scrollOffset = 0,
}) async {
  final before =
      await ref.read(libraryRepositoryProvider).loadBookmarks(bookId);
  final wasOn = before.any((b) => b.chapterIndex == chapterIndex);
  await ref.read(libraryRepositoryProvider).toggleBookmark(
        bookId: bookId,
        chapterIndex: chapterIndex,
        title: title,
        scrollOffset: scrollOffset,
      );
  ref.invalidate(bookmarksProvider(bookId));
  return !wasOn;
}

Future<void> removeBookmarkForBook(
  WidgetRef ref, {
  required String bookId,
  required String bookmarkId,
}) async {
  await ref.read(libraryRepositoryProvider).removeBookmark(bookId, bookmarkId);
  ref.invalidate(bookmarksProvider(bookId));
}

final sourcesProvider =
    AsyncNotifierProvider<SourcesNotifier, List<BookSource>>(
  SourcesNotifier.new,
);

class SourcesNotifier extends AsyncNotifier<List<BookSource>> {
  SourceRepository get _repo => ref.read(sourceRepositoryProvider);

  @override
  Future<List<BookSource>> build() => _repo.loadSources();

  Future<void> importJson(String text) async {
    state = AsyncData(await _repo.importJsonText(text));
  }

  Future<String> exportJson() => _repo.exportJsonText();

  Future<void> setEnabled(String id, bool enabled) async {
    state = AsyncData(await _repo.setEnabled(id, enabled));
  }

  Future<void> deleteSource(String id) async {
    state = AsyncData(await _repo.deleteSource(id));
  }
}

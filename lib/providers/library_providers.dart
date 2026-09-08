import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    required String sourcePath,
    required String displayName,
  }) async {
    final book = await _repo.importTxtFile(
      sourcePath: sourcePath,
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

  Future<void> setEnabled(String id, bool enabled) async {
    state = AsyncData(await _repo.setEnabled(id, enabled));
  }

  Future<void> deleteSource(String id) async {
    state = AsyncData(await _repo.deleteSource(id));
  }
}

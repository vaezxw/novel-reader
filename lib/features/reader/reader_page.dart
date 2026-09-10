import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../data/models.dart';
import '../../providers/library_providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../shelf/book_detail_page.dart';
import 'page_flip_view.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  final _scrollController = ScrollController();
  final _pageFlipKey = GlobalKey<PageFlipViewState>();
  final _tts = FlutterTts();

  bool _chromeVisible = false;
  int _chapterIndex = 0;
  String? _chapterText;
  bool _loadingChapter = true;
  String? _error;
  List<ChapterRef> _chapters = const [];
  Book? _book;
  bool _ttsSpeaking = false;
  Timer? _autoTimer;
  double? _systemBrightness;

  @override
  void initState() {
    super.initState();
    _initTts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.48);
      _tts.setCompletionHandler(() {
        if (!mounted) return;
        setState(() => _ttsSpeaking = false);
        _goChapter(_chapterIndex + 1).then((_) {
          if (mounted && _chapterText != null) _startTts();
        });
      });
    } catch (_) {
      // Web / unsupported platforms
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _persistProgress();
    _tts.stop();
    _restoreBrightness();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final books = await ref.read(booksProvider.future);
    Book? book;
    for (final item in books) {
      if (item.id == widget.bookId) {
        book = item;
        break;
      }
    }
    if (book == null) {
      setState(() {
        _error = '找不到这本书';
        _loadingChapter = false;
      });
      return;
    }
    final chapters =
        await ref.read(libraryRepositoryProvider).loadChapters(book.id);
    _book = book;
    _chapters = chapters;
    _chapterIndex =
        chapters.isEmpty ? 0 : book.lastChapterIndex.clamp(0, chapters.length - 1);
    await _loadChapter(restoreOffset: book.lastScrollOffset);
    await _applyBrightness(
      ref.read(readerPrefsProvider).value ?? const ReaderPrefs(),
    );
  }

  Future<void> _loadChapter({double restoreOffset = 0}) async {
    if (_chapters.isEmpty) {
      setState(() {
        _error = '没有章节';
        _loadingChapter = false;
      });
      return;
    }
    setState(() {
      _loadingChapter = true;
      _error = null;
    });
    try {
      final chapter = _chapters[_chapterIndex];
      final text = await ref
          .read(libraryRepositoryProvider)
          .loadChapterText(widget.bookId, chapter);
      setState(() {
        _chapterText = text;
        _loadingChapter = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final max = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(restoreOffset.clamp(0, max));
      });
      await _persistProgress();
    } catch (error) {
      setState(() {
        _error = '$error';
        _loadingChapter = false;
      });
    }
  }

  Future<void> _persistProgress() async {
    if (_book == null) return;
    final offset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    await ref.read(booksProvider.notifier).saveProgress(
          bookId: widget.bookId,
          chapterIndex: _chapterIndex,
          scrollOffset: offset,
        );
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    if (!_chromeVisible) _persistProgress();
  }

  Future<void> _goChapter(int index) async {
    if (index < 0 || index >= _chapters.length || index == _chapterIndex) {
      return;
    }
    await _persistProgress();
    if (_ttsSpeaking) await _tts.stop();
    setState(() {
      _chapterIndex = index;
      _ttsSpeaking = false;
    });
    await _loadChapter();
  }

  Future<void> _openToc() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return _TocBookmarkSheet(
          bookId: widget.bookId,
          chapters: _chapters,
          currentIndex: _chapterIndex,
          bookTitle: _book?.title ?? '',
        );
      },
    );
    if (selected != null) await _goChapter(selected);
  }

  Future<void> _openPrefs() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => _ReaderPrefsSheet(
        onBrightnessChanged: _applyBrightness,
      ),
    );
    final prefs = ref.read(readerPrefsProvider).value ?? const ReaderPrefs();
    _syncAutoRead(prefs);
  }

  Future<void> _toggleBookmark() async {
    if (_chapters.isEmpty) return;
    final chapter = _chapters[_chapterIndex];
    final offset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    await toggleBookmarkForBook(
      ref,
      bookId: widget.bookId,
      chapterIndex: _chapterIndex,
      title: chapter.title,
      scrollOffset: offset,
    );
    if (!mounted) return;
    final marks = ref.read(bookmarksProvider(widget.bookId)).value ?? [];
    final on = marks.any((b) => b.chapterIndex == _chapterIndex);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(on ? '已添加书签' : '已取消书签')),
    );
  }

  Future<void> _refreshToc() async {
    if (_book == null || !_book!.isRemote) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地书无需刷新目录')),
      );
      return;
    }
    try {
      final book =
          await ref.read(booksProvider.notifier).refreshRemoteToc(widget.bookId);
      _book = book;
      _chapters =
          await ref.read(libraryRepositoryProvider).loadChapters(widget.bookId);
      _chapterIndex = _chapterIndex.clamp(0, _chapters.length - 1);
      await _loadChapter();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('目录已刷新 · ${book.chapterCount} 章')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刷新失败：$error')),
      );
    }
  }

  Future<void> _openDetail() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookDetailPage(bookId: widget.bookId),
      ),
    );
    await ref.read(booksProvider.notifier).refresh();
    final books = ref.read(booksProvider).value ?? [];
    for (final b in books) {
      if (b.id == widget.bookId) _book = b;
    }
  }

  void _syncAutoRead(ReaderPrefs prefs) {
    _autoTimer?.cancel();
    if (!prefs.autoReadEnabled || _ttsSpeaking) return;
    final ms = (1800 / prefs.autoReadSpeed.clamp(0.4, 3.0)).round();
    _autoTimer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (!mounted || _loadingChapter) return;
      if (prefs.readMode == ReadMode.pageFlip) {
        _pageFlipKey.currentState?.nextPageOrChapter();
      } else {
        if (!_scrollController.hasClients) return;
        final next = _scrollController.offset + 120;
        final max = _scrollController.position.maxScrollExtent;
        if (next >= max - 4) {
          _goChapter(_chapterIndex + 1);
        } else {
          _scrollController.animateTo(
            next.clamp(0, max),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  Future<void> _toggleTts() async {
    if (_ttsSpeaking) {
      await _tts.stop();
      setState(() => _ttsSpeaking = false);
      return;
    }
    final prefs = ref.read(readerPrefsProvider).value ?? const ReaderPrefs();
    if (prefs.autoReadEnabled) {
      await ref.read(readerPrefsProvider.notifier).setPrefs(
            (p) => p.copyWith(autoReadEnabled: false),
          );
      _autoTimer?.cancel();
    }
    await _startTts();
  }

  Future<void> _startTts() async {
    final text = _chapterText;
    if (text == null || text.isEmpty) return;
    try {
      setState(() => _ttsSpeaking = true);
      await _tts.speak(text);
    } catch (error) {
      setState(() => _ttsSpeaking = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('听书不可用：$error')),
        );
      }
    }
  }

  Future<void> _applyBrightness(ReaderPrefs prefs) async {
    if (kIsWeb) return;
    try {
      if (prefs.followSystemBrightness) {
        await _restoreBrightness();
        return;
      }
      _systemBrightness ??= await ScreenBrightness.instance.system;
      await ScreenBrightness.instance
          .setApplicationScreenBrightness(prefs.brightness.clamp(0.05, 1.0));
    } catch (_) {}
  }

  Future<void> _restoreBrightness() async {
    if (kIsWeb) return;
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(readerPrefsProvider).value ?? const ReaderPrefs();
    ref.listen(readerPrefsProvider, (prev, next) {
      final p = next.value;
      if (p == null) return;
      _applyBrightness(p);
      _syncAutoRead(p);
    });

    final systemDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final dark = prefs.followSystemTheme ? systemDark : prefs.forceDark;

    final paper = dark ? AppColors.nightPaper : AppColors.paper;
    final ink = dark ? AppColors.nightInk : AppColors.ink;
    final muted = dark ? AppColors.nightMuted : AppColors.inkMuted;
    final lamp = dark ? AppColors.nightLamp : AppColors.lamp;
    final rule = dark ? AppColors.nightRule : AppColors.rule;

    final overlay = dark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: paper,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: paper,
          );

    final chapterTitle = _chapters.isEmpty
        ? ''
        : _chapters[_chapterIndex.clamp(0, _chapters.length - 1)].title;

    final bookmarks = ref.watch(bookmarksProvider(widget.bookId)).value ?? [];
    final bookmarked = bookmarks.any((b) => b.chapterIndex == _chapterIndex);

    final bodyStyle = AppTheme.readingBody(
      color: ink,
      fontSize: prefs.fontSize,
      height: prefs.lineHeight,
    );
    final titleStyle = GoogleFonts.notoSansSc(
      fontSize: prefs.fontSize + 2,
      fontWeight: FontWeight.w600,
      color: ink,
      height: 1.35,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: paper,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: _loadingChapter
                    ? Center(child: CircularProgressIndicator(color: lamp))
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _error!,
                                style: GoogleFonts.notoSansSc(color: ink),
                              ),
                            ),
                          )
                        : _buildBody(
                            prefs: prefs,
                            chapterTitle: chapterTitle,
                            bodyStyle: bodyStyle,
                            titleStyle: titleStyle,
                            muted: muted,
                            lamp: lamp,
                          ),
              ),
              if (_chromeVisible) ...[
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Material(
                    color: paper.withValues(alpha: 0.97),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 52,
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: () async {
                                  await _persistProgress();
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                  }
                                },
                                icon: Icon(Icons.chevron_left, color: ink),
                              ),
                              Expanded(
                                child: Text(
                                  _book?.title ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.notoSansSc(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: ink,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: bookmarked ? '取消书签' : '书签',
                                onPressed: _toggleBookmark,
                                icon: Icon(
                                  bookmarked
                                      ? Icons.bookmark
                                      : Icons.bookmark_border,
                                  color: bookmarked ? lamp : ink,
                                ),
                              ),
                              IconButton(
                                tooltip: _ttsSpeaking ? '停止听书' : '听书',
                                onPressed: _toggleTts,
                                icon: Icon(
                                  _ttsSpeaking
                                      ? Icons.stop_circle_outlined
                                      : Icons.headphones_outlined,
                                  color: _ttsSpeaking ? lamp : ink,
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_horiz, color: ink),
                                onSelected: (value) {
                                  switch (value) {
                                    case 'detail':
                                      _openDetail();
                                    case 'refresh':
                                      _refreshToc();
                                    case 'toc':
                                      _openToc();
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'detail',
                                    child: Text('书籍详情'),
                                  ),
                                  PopupMenuItem(
                                    value: 'refresh',
                                    enabled: _book?.isRemote == true,
                                    child: Text(
                                      _book?.isRemote == true
                                          ? '章节刷新'
                                          : '章节刷新（仅书源书）',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'toc',
                                    child: Text('目录 / 书签'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: rule),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: paper.withValues(alpha: 0.97),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Divider(height: 1, color: rule),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: '目录',
                                onPressed: _openToc,
                                icon: Icon(Icons.menu, color: ink),
                              ),
                              IconButton(
                                tooltip: '阅读设置',
                                onPressed: _openPrefs,
                                icon: Icon(Icons.text_fields, color: ink),
                              ),
                              Expanded(
                                child: Text(
                                  '${_chapterIndex + 1}/${_chapters.length}',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.notoSansSc(
                                    fontSize: 12,
                                    color: muted,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _chapterIndex > 0
                                    ? () => _goChapter(_chapterIndex - 1)
                                    : null,
                                child: Text(
                                  '上一章',
                                  style: GoogleFonts.notoSansSc(fontSize: 13),
                                ),
                              ),
                              TextButton(
                                onPressed: _chapterIndex < _chapters.length - 1
                                    ? () => _goChapter(_chapterIndex + 1)
                                    : null,
                                child: Text(
                                  '下一章',
                                  style: GoogleFonts.notoSansSc(
                                    fontSize: 13,
                                    color: lamp,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (prefs.autoReadEnabled)
                Positioned(
                  right: 16,
                  bottom: _chromeVisible ? 88 : 24,
                  child: FloatingActionButton.small(
                    heroTag: 'auto-read',
                    backgroundColor: lamp,
                    onPressed: () {
                      ref.read(readerPrefsProvider.notifier).setPrefs(
                            (p) => p.copyWith(autoReadEnabled: false),
                          );
                      _autoTimer?.cancel();
                    },
                    child: const Icon(Icons.pause, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody({
    required ReaderPrefs prefs,
    required String chapterTitle,
    required TextStyle bodyStyle,
    required TextStyle titleStyle,
    required Color muted,
    required Color lamp,
  }) {
    switch (prefs.readMode) {
      case ReadMode.pageFlip:
        return PageFlipView(
          key: _pageFlipKey,
          text: _chapterText ?? '',
          title: chapterTitle,
          style: bodyStyle,
          titleStyle: titleStyle,
          onTapCenter: _toggleChrome,
          // Chapter change is button-only; auto-read may still advance chapter.
          onPrevChapter: () => _goChapter(_chapterIndex - 1),
          onNextChapter: () => _goChapter(_chapterIndex + 1),
          allowGestureChapterChange: false,
        );
      case ReadMode.verticalScroll:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (_) => _toggleChrome(),
          child: _VerticalChapterContent(
            scrollController: _scrollController,
            title: chapterTitle,
            titleStyle: titleStyle,
            body: _chapterText ?? '',
            bodyStyle: bodyStyle,
            muted: muted,
            lamp: lamp,
            chapterIndex: _chapterIndex,
            chapterCount: _chapters.length,
            onPrev: () => _goChapter(_chapterIndex - 1),
            onNext: () => _goChapter(_chapterIndex + 1),
          ),
        );
    }
  }
}

class _VerticalChapterContent extends StatelessWidget {
  const _VerticalChapterContent({
    required this.scrollController,
    required this.title,
    required this.titleStyle,
    required this.body,
    required this.bodyStyle,
    required this.muted,
    required this.lamp,
    required this.chapterIndex,
    required this.chapterCount,
    required this.onPrev,
    required this.onNext,
  });

  final ScrollController scrollController;
  final String title;
  final TextStyle titleStyle;
  final String body;
  final TextStyle bodyStyle;
  final Color muted;
  final Color lamp;
  final int chapterIndex;
  final int chapterCount;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 48),
      children: [
        Text(title, style: titleStyle),
        const SizedBox(height: 18),
        Text(body, style: bodyStyle),
        const SizedBox(height: 36),
        Row(
          children: [
            TextButton(
              onPressed: chapterIndex > 0 ? onPrev : null,
              child: Text('上一章', style: GoogleFonts.notoSansSc(color: muted)),
            ),
            const Spacer(),
            TextButton(
              onPressed: chapterIndex < chapterCount - 1 ? onNext : null,
              child: Text('下一章', style: GoogleFonts.notoSansSc(color: lamp)),
            ),
          ],
        ),
      ],
    );
  }
}

class _TocBookmarkSheet extends ConsumerStatefulWidget {
  const _TocBookmarkSheet({
    required this.bookId,
    required this.chapters,
    required this.currentIndex,
    required this.bookTitle,
  });

  final String bookId;
  final List<ChapterRef> chapters;
  final int currentIndex;
  final String bookTitle;

  @override
  ConsumerState<_TocBookmarkSheet> createState() => _TocBookmarkSheetState();
}

class _TocBookmarkSheetState extends ConsumerState<_TocBookmarkSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  final _listCtrl = ScrollController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_listCtrl.hasClients) return;
      final offset = (widget.currentIndex * 52.0) - 120;
      _listCtrl.jumpTo(offset.clamp(0, _listCtrl.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.78;
    final filtered = _query.trim().isEmpty
        ? widget.chapters
        : widget.chapters
            .where((c) => c.title.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    final bookmarks =
        ref.watch(bookmarksProvider(widget.bookId)).value ?? const <Bookmark>[];

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.bookTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansSc(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '共 ${widget.chapters.length} 章节',
                        style: GoogleFonts.notoSansSc(
                          fontSize: 12,
                          color: colors.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(icon: Icon(Icons.list), text: '目录'),
              Tab(icon: Icon(Icons.bookmark_border), text: '书签'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: '搜索章节',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          ListView.builder(
                            controller: _listCtrl,
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final chapter = filtered[index];
                              final selected =
                                  chapter.index == widget.currentIndex;
                              return ListTile(
                                dense: true,
                                selected: selected,
                                selectedTileColor:
                                    colors.primary.withValues(alpha: 0.1),
                                title: Text(
                                  chapter.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.notoSansSc(
                                    fontSize: 14,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: selected
                                        ? colors.primary
                                        : colors.onSurface,
                                  ),
                                ),
                                onTap: () =>
                                    Navigator.pop(context, chapter.index),
                              );
                            },
                          ),
                          Positioned(
                            right: 12,
                            bottom: 16,
                            child: Column(
                              children: [
                                FloatingActionButton.small(
                                  heroTag: 'toc-top',
                                  onPressed: () {
                                    _listCtrl.animateTo(
                                      0,
                                      duration: const Duration(milliseconds: 280),
                                      curve: Curves.easeOut,
                                    );
                                  },
                                  child: const Icon(Icons.vertical_align_top),
                                ),
                                const SizedBox(height: 8),
                                FloatingActionButton.small(
                                  heroTag: 'toc-bottom',
                                  onPressed: () {
                                    _listCtrl.animateTo(
                                      _listCtrl.position.maxScrollExtent,
                                      duration: const Duration(milliseconds: 280),
                                      curve: Curves.easeOut,
                                    );
                                  },
                                  child: const Icon(Icons.vertical_align_bottom),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                bookmarks.isEmpty
                    ? Center(
                        child: Text(
                          '还没有书签',
                          style: GoogleFonts.notoSansSc(
                            color: colors.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: bookmarks.length,
                        itemBuilder: (context, index) {
                          final mark = bookmarks[index];
                          return ListTile(
                            title: Text(
                              mark.title,
                              style: GoogleFonts.notoSansSc(fontSize: 14),
                            ),
                            subtitle: Text(
                              '第 ${mark.chapterIndex + 1} 章',
                              style: GoogleFonts.notoSansSc(fontSize: 12),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () {
                                removeBookmarkForBook(
                                  ref,
                                  bookId: widget.bookId,
                                  bookmarkId: mark.id,
                                );
                              },
                            ),
                            onTap: () =>
                                Navigator.pop(context, mark.chapterIndex),
                          );
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderPrefsSheet extends ConsumerWidget {
  const _ReaderPrefsSheet({required this.onBrightnessChanged});

  final Future<void> Function(ReaderPrefs prefs) onBrightnessChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(readerPrefsProvider);
    final prefs = async.value ?? const ReaderPrefs();
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '阅读设置',
              style: GoogleFonts.notoSansSc(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Text('翻页方式', style: GoogleFonts.notoSansSc(fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in ReadMode.values)
                  ChoiceChip(
                    label: Text(switch (mode) {
                      ReadMode.pageFlip => '左右翻页',
                      ReadMode.verticalScroll => '上下滚动',
                    }),
                    selected: prefs.readMode == mode,
                    onSelected: (_) {
                      ref.read(readerPrefsProvider.notifier).setPrefs(
                            (p) => p.copyWith(readMode: mode),
                          );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '字号 ${prefs.fontSize.round()}',
              style: GoogleFonts.notoSansSc(fontSize: 13, color: colors.outline),
            ),
            Slider(
              value: prefs.fontSize,
              min: 14,
              max: 28,
              divisions: 14,
              onChanged: (value) {
                ref.read(readerPrefsProvider.notifier).setPrefs(
                      (p) => p.copyWith(fontSize: value),
                    );
              },
            ),
            Text(
              '行距 ${prefs.lineHeight.toStringAsFixed(2)}',
              style: GoogleFonts.notoSansSc(fontSize: 13, color: colors.outline),
            ),
            Slider(
              value: prefs.lineHeight,
              min: 1.4,
              max: 2.2,
              divisions: 16,
              onChanged: (value) {
                ref.read(readerPrefsProvider.notifier).setPrefs(
                      (p) => p.copyWith(lineHeight: value),
                    );
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('自动阅读', style: GoogleFonts.notoSansSc(fontSize: 14)),
              value: prefs.autoReadEnabled,
              onChanged: (v) {
                ref.read(readerPrefsProvider.notifier).setPrefs(
                      (p) => p.copyWith(autoReadEnabled: v),
                    );
              },
            ),
            if (prefs.autoReadEnabled) ...[
              Text(
                '速度 ${prefs.autoReadSpeed.toStringAsFixed(1)}x',
                style:
                    GoogleFonts.notoSansSc(fontSize: 13, color: colors.outline),
              ),
              Slider(
                value: prefs.autoReadSpeed,
                min: 0.4,
                max: 3.0,
                divisions: 13,
                onChanged: (value) {
                  ref.read(readerPrefsProvider.notifier).setPrefs(
                        (p) => p.copyWith(autoReadSpeed: value),
                      );
                },
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title:
                  Text('亮度跟随系统', style: GoogleFonts.notoSansSc(fontSize: 14)),
              value: prefs.followSystemBrightness,
              onChanged: (v) async {
                final next = prefs.copyWith(followSystemBrightness: v);
                await ref.read(readerPrefsProvider.notifier).setPrefs((_) => next);
                await onBrightnessChanged(next);
              },
            ),
            if (!prefs.followSystemBrightness) ...[
              Text(
                '亮度 ${(prefs.brightness * 100).round()}%',
                style:
                    GoogleFonts.notoSansSc(fontSize: 13, color: colors.outline),
              ),
              Slider(
                value: prefs.brightness,
                min: 0.05,
                max: 1,
                onChanged: (value) async {
                  final next = prefs.copyWith(brightness: value);
                  await ref
                      .read(readerPrefsProvider.notifier)
                      .setPrefs((_) => next);
                  await onBrightnessChanged(next);
                },
              ),
            ],
            const SizedBox(height: 8),
            Text('背景', style: GoogleFonts.notoSansSc(fontSize: 13)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: [
                ChoiceChip(
                  label: const Text('跟随系统'),
                  selected: prefs.followSystemTheme,
                  onSelected: (_) {
                    ref.read(readerPrefsProvider.notifier).setPrefs(
                          (p) => p.copyWith(followSystemTheme: true),
                        );
                  },
                ),
                ChoiceChip(
                  label: const Text('纸面'),
                  selected: !prefs.followSystemTheme && !prefs.forceDark,
                  onSelected: (_) {
                    ref.read(readerPrefsProvider.notifier).setPrefs(
                          (p) => p.copyWith(
                            followSystemTheme: false,
                            forceDark: false,
                          ),
                        );
                  },
                ),
                ChoiceChip(
                  label: const Text('夜间'),
                  selected: !prefs.followSystemTheme && prefs.forceDark,
                  onSelected: (_) {
                    ref.read(readerPrefsProvider.notifier).setPrefs(
                          (p) => p.copyWith(
                            followSystemTheme: false,
                            forceDark: true,
                          ),
                        );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

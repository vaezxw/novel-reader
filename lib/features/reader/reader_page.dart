import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models.dart';
import '../../providers/library_providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  final _scrollController = ScrollController();
  bool _chromeVisible = false;
  bool _booted = false;
  int _chapterIndex = 0;
  String? _chapterText;
  bool _loadingChapter = true;
  String? _error;
  List<ChapterRef> _chapters = const [];
  Book? _book;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _persistProgress();
    _scrollController.removeListener(_onScroll);
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
    _chapterIndex = book.lastChapterIndex.clamp(0, chapters.length - 1);
    await _loadChapter(restoreOffset: book.lastScrollOffset);
    _booted = true;
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

  void _onScroll() {
    if (!_booted) return;
    // Throttled persistence happens on chrome toggle / chapter change / dispose.
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
    if (!_chromeVisible) {
      _persistProgress();
    }
  }

  Future<void> _goChapter(int index) async {
    if (index < 0 || index >= _chapters.length || index == _chapterIndex) {
      return;
    }
    await _persistProgress();
    setState(() => _chapterIndex = index);
    await _loadChapter();
  }

  Future<void> _openToc() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return _TocSheet(
          chapters: _chapters,
          currentIndex: _chapterIndex,
        );
      },
    );
    if (selected != null) {
      await _goChapter(selected);
    }
  }

  Future<void> _openPrefs() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => const _ReaderPrefsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(readerPrefsProvider).value ?? const ReaderPrefs();
    final systemDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: paper,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final width = MediaQuery.sizeOf(context).width;
                    final x = details.localPosition.dx;
                    if (x < width * 0.28) {
                      _goChapter(_chapterIndex - 1);
                    } else if (x > width * 0.72) {
                      _goChapter(_chapterIndex + 1);
                    } else {
                      _toggleChrome();
                    }
                  },
                  child: _loadingChapter
                      ? Center(
                          child: CircularProgressIndicator(color: lamp),
                        )
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
                          : ListView(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(22, 28, 22, 48),
                              children: [
                                Text(
                                  chapterTitle,
                                  style: GoogleFonts.notoSansSc(
                                    fontSize: prefs.fontSize + 2,
                                    fontWeight: FontWeight.w600,
                                    color: ink,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  _chapterText ?? '',
                                  style: AppTheme.readingBody(
                                    color: ink,
                                    fontSize: prefs.fontSize,
                                    height: prefs.lineHeight,
                                  ),
                                ),
                                const SizedBox(height: 36),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: _chapterIndex > 0
                                          ? () => _goChapter(_chapterIndex - 1)
                                          : null,
                                      child: Text(
                                        '上一章',
                                        style: GoogleFonts.notoSansSc(
                                          color: muted,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed:
                                          _chapterIndex < _chapters.length - 1
                                              ? () =>
                                                  _goChapter(_chapterIndex + 1)
                                              : null,
                                      child: Text(
                                        '下一章',
                                        style: GoogleFonts.notoSansSc(
                                          color: lamp,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                ),
              ),
              if (_chromeVisible) ...[
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Material(
                    color: paper.withValues(alpha: 0.96),
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
                                icon: Icon(
                                  PhosphorIconsRegular.caretLeft,
                                  color: ink,
                                ),
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
                                tooltip: '目录',
                                onPressed: _openToc,
                                icon: Icon(
                                  PhosphorIconsRegular.listBullets,
                                  color: ink,
                                ),
                              ),
                              IconButton(
                                tooltip: '阅读设置',
                                onPressed: _openPrefs,
                                icon: Icon(
                                  PhosphorIconsRegular.textAa,
                                  color: ink,
                                ),
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
                    color: paper.withValues(alpha: 0.96),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Divider(height: 1, color: rule),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                          child: Row(
                            children: [
                              Text(
                                '${_chapterIndex + 1}/${_chapters.length}',
                                style: GoogleFonts.notoSansSc(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: _chapters.isEmpty
                                        ? 0
                                        : (_chapterIndex + 1) /
                                            _chapters.length,
                                    minHeight: 4,
                                    backgroundColor: rule,
                                    color: lamp,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _TocSheet extends StatelessWidget {
  const _TocSheet({
    required this.chapters,
    required this.currentIndex,
  });

  final List<ChapterRef> chapters;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.72;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Text(
                  '目录',
                  style: GoogleFonts.notoSansSc(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(PhosphorIconsRegular.x),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outline),
          Expanded(
            child: ListView.builder(
              itemCount: chapters.length,
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                final selected = index == currentIndex;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: colors.primary.withValues(alpha: 0.1),
                  title: Text(
                    chapter.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansSc(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? colors.primary : colors.onSurface,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderPrefsSheet extends ConsumerWidget {
  const _ReaderPrefsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(readerPrefsProvider);
    final prefs = async.value ?? const ReaderPrefs();
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
          const SizedBox(height: 18),
          Text(
            '字号 ${prefs.fontSize.round()}',
            style: GoogleFonts.notoSansSc(fontSize: 13, color: colors.outline),
          ),
          Slider(
            value: prefs.fontSize,
            min: 14,
            max: 28,
            divisions: 14,
            label: prefs.fontSize.round().toString(),
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
            label: prefs.lineHeight.toStringAsFixed(2),
            onChanged: (value) {
              ref.read(readerPrefsProvider.notifier).setPrefs(
                    (p) => p.copyWith(lineHeight: value),
                  );
            },
          ),
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
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/models.dart';
import '../../providers/library_providers.dart';
import '../reader/reader_page.dart';

class BookDetailPage extends ConsumerStatefulWidget {
  const BookDetailPage({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends ConsumerState<BookDetailPage> {
  bool _refreshing = false;

  Book? _findBook(List<Book> books) {
    for (final book in books) {
      if (book.id == widget.bookId) return book;
    }
    return null;
  }

  Future<void> _refreshToc() async {
    setState(() => _refreshing = true);
    try {
      final book =
          await ref.read(booksProvider.notifier).refreshRemoteToc(widget.bookId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('目录已刷新 · ${book.chapterCount} 章')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刷新失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final books = ref.watch(booksProvider).value ?? const <Book>[];
    final book = _findBook(books);

    if (book == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('书籍详情')),
        body: const Center(child: Text('找不到这本书')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('书籍详情'),
        actions: [
          if (book.isRemote)
            IconButton(
              tooltip: '章节刷新',
              onPressed: _refreshing ? null : _refreshToc,
              icon: _refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cover(url: book.coverUrl, title: book.title, width: 110),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: GoogleFonts.notoSansSc(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      book.author?.isNotEmpty == true ? book.author! : '未知作者',
                      style: GoogleFonts.notoSansSc(
                        fontSize: 14,
                        color: colors.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${book.isRemote ? (book.sourceName ?? '书源') : '本地 TXT'} · ${book.chapterCount} 章',
                      style: GoogleFonts.notoSansSc(
                        fontSize: 12,
                        color: colors.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '进度 ${book.lastChapterIndex + 1}/${book.chapterCount}',
                      style: GoogleFonts.notoSansSc(
                        fontSize: 12,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '简介',
            style: GoogleFonts.notoSansSc(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            (book.intro == null || book.intro!.trim().isEmpty)
                ? '暂无简介'
                : book.intro!,
            style: GoogleFonts.notoSansSc(
              fontSize: 14,
              height: 1.65,
              color: colors.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => ReaderPage(bookId: book.id),
                ),
              );
            },
            child: const Text('继续阅读'),
          ),
          if (book.isRemote) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _refreshing ? null : _refreshToc,
              child: Text(_refreshing ? '刷新中…' : '从书源刷新目录'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.url,
    required this.title,
    this.width = 96,
  });

  final String? url;
  final String title;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final height = width * 1.35;
    final radius = BorderRadius.circular(6);

    Widget placeholder() => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.85),
            borderRadius: radius,
          ),
          padding: const EdgeInsets.all(8),
          alignment: Alignment.center,
          child: Text(
            title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansSc(
              fontSize: 12,
              color: colors.onPrimary,
              height: 1.3,
            ),
          ),
        );

    if (url == null || url!.isEmpty) return placeholder();

    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        url!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder(),
      ),
    );
  }
}

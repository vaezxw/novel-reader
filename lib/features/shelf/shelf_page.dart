import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models.dart';
import '../../providers/library_providers.dart';
import '../../widgets/empty_state.dart';
import '../reader/reader_page.dart';

class ShelfPage extends ConsumerStatefulWidget {
  const ShelfPage({super.key});

  @override
  ConsumerState<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends ConsumerState<ShelfPage> {
  bool _importing = false;

  Future<void> _importTxt() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final path = file.path;
      if (path == null) {
        _toast('无法读取所选文件路径');
        return;
      }

      final book = await ref.read(booksProvider.notifier).importTxt(
            sourcePath: path,
            displayName: file.name,
          );
      if (!mounted) return;
      _toast('已导入「${book.title}」· ${book.chapterCount} 章');
    } catch (error) {
      if (!mounted) return;
      _toast('导入失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openBook(Book book) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderPage(bookId: book.id),
      ),
    );
    await ref.read(booksProvider.notifier).refresh();
  }

  Future<void> _confirmDelete(Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('移出书架'),
          content: Text('确定删除「${book.title}」？本地缓存也会清除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      await ref.read(booksProvider.notifier).deleteBook(book.id);
      if (mounted) _toast('已删除');
    }
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('墨架'),
        actions: [
          if (_importing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: '导入 TXT',
              onPressed: _importTxt,
              icon: Icon(PhosphorIconsRegular.fileArrowUp),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
        data: (books) {
          final readingCount =
              books.where((b) => b.lastReadAt != null).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  books.isEmpty
                      ? '本地书架 · 还没有书'
                      : '本地书架 · ${books.length} 本'
                          '${readingCount > 0 ? ' · 在读 $readingCount' : ''}',
                  style: GoogleFonts.notoSansSc(
                    fontSize: 13,
                    color: colors.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
              Divider(height: 1, color: colors.outline),
              Expanded(
                child: books.isEmpty
                    ? EmptyState(
                        icon: PhosphorIconsRegular.bookOpenText,
                        title: '还没有书',
                        body: '导入 TXT，或从书源搜索后加入书架。',
                        actionLabel: '导入 TXT',
                        onAction: _importTxt,
                      )
                    : ListView.separated(
                        itemCount: books.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          indent: 20,
                          endIndent: 20,
                          color: colors.outline.withValues(alpha: 0.7),
                        ),
                        itemBuilder: (context, index) {
                          final book = books[index];
                          return _BookTile(
                            book: book,
                            onOpen: () => _openBook(book),
                            onDelete: () => _confirmDelete(book),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.onOpen,
    required this.onDelete,
  });

  final Book book;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progressPct = (book.progress * 100).clamp(0, 100).round();
    final timeLabel = book.lastReadAt == null
        ? '未读'
        : DateFormat('M/d HH:mm').format(book.lastReadAt!);

    return InkWell(
      onTap: onOpen,
      onLongPress: onDelete,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 46,
              margin: const EdgeInsets.only(top: 2, right: 14),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansSc(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${book.isRemote ? '书源' : '本地'} · ${book.chapterCount} 章 · $timeLabel · $progressPct%',
                    style: GoogleFonts.notoSansSc(
                      fontSize: 12,
                      color: colors.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '删除',
              onPressed: onDelete,
              icon: Icon(
                PhosphorIconsRegular.trash,
                size: 18,
                color: colors.onSurface.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

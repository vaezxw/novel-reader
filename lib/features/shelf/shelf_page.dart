import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/models.dart';
import '../../providers/library_providers.dart';
import '../../widgets/empty_state.dart';
import '../reader/reader_page.dart';
import 'book_detail_page.dart';

class ShelfPage extends ConsumerStatefulWidget {
  const ShelfPage({super.key});

  @override
  ConsumerState<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends ConsumerState<ShelfPage> {
  bool _importing = false;
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _importTxt() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      final path = file.path;

      if (bytes == null && path == null) {
        _toast('无法读取所选文件');
        return;
      }

      final book = await ref.read(booksProvider.notifier).importTxt(
            sourcePath: path,
            bytes: bytes,
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

  Future<void> _openDetail(Book book) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookDetailPage(bookId: book.id),
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

  List<Book> _filter(List<Book> books) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return books;
    return books.where((b) {
      final author = b.author?.toLowerCase() ?? '';
      return b.title.toLowerCase().contains(q) || author.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索书名或作者',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : const Text('书架'),
        actions: [
          IconButton(
            tooltip: _searching ? '关闭搜索' : '搜索',
            onPressed: () {
              setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _query = '';
                  _searchCtrl.clear();
                }
              });
            },
            icon: Icon(_searching ? Icons.close : Icons.search),
          ),
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
              icon: const Icon(Icons.upload_file),
            ),
        ],
      ),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
        data: (books) {
          final visible = _filter(books);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  books.isEmpty
                      ? '本地书架 · 还没有书'
                      : _query.isEmpty
                          ? '本地书架 · ${books.length} 本'
                          : '找到 ${visible.length} 本',
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
                        icon: Icons.auto_stories_outlined,
                        title: '还没有书',
                        body: '导入 TXT，或从书源搜索后加入书架。',
                        actionLabel: '导入 TXT',
                        onAction: _importTxt,
                      )
                    : visible.isEmpty
                        ? Center(
                            child: Text(
                              '没有匹配的书',
                              style: GoogleFonts.notoSansSc(
                                color: colors.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.58,
                            ),
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final book = visible[index];
                              return _BookCoverCard(
                                book: book,
                                onOpen: () => _openBook(book),
                                onDetail: () => _openDetail(book),
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

class _BookCoverCard extends StatelessWidget {
  const _BookCoverCard({
    required this.book,
    required this.onOpen,
    required this.onDetail,
    required this.onDelete,
  });

  final Book book;
  final VoidCallback onOpen;
  final VoidCallback onDetail;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progress =
        '${book.lastChapterIndex + 1}/${book.chapterCount} 章';

    return InkWell(
      onTap: onOpen,
      onLongPress: () async {
        final action = await showModalBottomSheet<String>(
          context: context,
          builder: (context) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('书籍详情'),
                    onTap: () => Navigator.pop(context, 'detail'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('移出书架'),
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
                ],
              ),
            );
          },
        );
        if (action == 'detail') onDetail();
        if (action == 'delete') onDelete();
      },
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CoverImage(url: book.coverUrl, title: book.title),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      color: Colors.black.withValues(alpha: 0.55),
                      child: Text(
                        progress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansSc(
                          fontSize: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansSc(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url, required this.title});

  final String? url;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    Widget placeholder() => Container(
          color: colors.primary.withValues(alpha: 0.88),
          padding: const EdgeInsets.all(8),
          alignment: Alignment.center,
          child: Text(
            title,
            maxLines: 5,
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

    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder(),
    );
  }
}

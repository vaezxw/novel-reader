import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/source_models.dart';
import '../../providers/library_providers.dart';
import '../../widgets/empty_state.dart';
import '../reader/reader_page.dart';

class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({super.key});

  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _keywordCtrl = TextEditingController();
  bool _searching = false;
  bool _importing = false;
  List<SearchBookHit> _hits = const [];
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _keywordCtrl.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _importFromPaste() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('粘贴书源 JSON / 链接'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText:
                    '支持 JSON 对象/数组，或 Gitee/GitHub 的 raw/blob 链接',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('导入'),
            ),
          ],
        );
      },
    );
    if (text == null || text.trim().isEmpty) return;
    await _importText(text);
  }

  Future<void> _importFromFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'txt'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) {
      _toast('无法读取文件路径');
      return;
    }
    final text = await File(path).readAsString();
    await _importText(text);
  }

  Future<void> _importText(String text) async {
    setState(() => _importing = true);
    try {
      await ref.read(sourcesProvider.notifier).importJson(text);
      if (!mounted) return;
      _toast('书源已导入');
      _tabs.animateTo(0);
    } catch (error) {
      if (!mounted) return;
      _toast('导入失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _search() async {
    final keyword = _keywordCtrl.text.trim();
    if (keyword.isEmpty) {
      _toast('请输入书名或关键词');
      return;
    }
    final sources = (ref.read(sourcesProvider).value ?? [])
        .where((s) => s.enabled)
        .toList();
    if (sources.isEmpty) {
      _toast('请先添加并启用至少一个书源');
      return;
    }

    setState(() {
      _searching = true;
      _searchError = null;
      _hits = const [];
    });

    final engine = ref.read(sourceEngineProvider);
    final hits = <SearchBookHit>[];
    final errors = <String>[];
    for (final source in sources) {
      try {
        final part = await engine.search(source: source, keyword: keyword);
        hits.addAll(part);
      } catch (error) {
        errors.add('${source.bookSourceName}: $error');
      }
    }

    if (!mounted) return;
    setState(() {
      _searching = false;
      _hits = hits;
      if (hits.isEmpty && errors.isNotEmpty) {
        _searchError = errors.take(2).join('\n');
      }
    });
    if (hits.isEmpty && errors.isEmpty) {
      _toast('没有搜到结果');
    }
  }

  Future<void> _addHit(SearchBookHit hit) async {
    final sources = ref.read(sourcesProvider).value ?? [];
    BookSource? source;
    for (final item in sources) {
      if (item.id == hit.sourceId) {
        source = item;
        break;
      }
    }
    if (source == null) {
      _toast('书源不存在');
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final book =
          await ref.read(booksProvider.notifier).addRemote(hit, source);
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast('已加入书架「${book.title}」');
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderPage(bookId: book.id),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast('加入失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sourcesAsync = ref.watch(sourcesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('书源'),
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
          else ...[
            IconButton(
              tooltip: '从文件导入',
              onPressed: _importFromFile,
              icon: Icon(Icons.upload_file),
            ),
            IconButton(
              tooltip: '粘贴 JSON',
              onPressed: _importFromPaste,
              icon: Icon(Icons.add),
            ),
          ],
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: colors.primary,
          unselectedLabelColor: colors.onSurface.withValues(alpha: 0.55),
          indicatorColor: colors.primary,
          tabs: const [
            Tab(text: '管理'),
            Tab(text: '搜索'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          sourcesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败：$e')),
            data: (sources) {
              if (sources.isEmpty) {
                return EmptyState(
                  icon: Icons.travel_explore_outlined,
                  title: '还没有书源',
                  body: '粘贴或导入书源 JSON 后即可搜索。不预置任何书源。',
                  actionLabel: '粘贴 JSON',
                  onAction: _importFromPaste,
                );
              }
              return ListView.separated(
                itemCount: sources.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: colors.outline.withValues(alpha: 0.7),
                ),
                itemBuilder: (context, index) {
                  final source = sources[index];
                  return SwitchListTile(
                    value: source.enabled,
                    onChanged: (v) {
                      ref
                          .read(sourcesProvider.notifier)
                          .setEnabled(source.id, v);
                    },
                    title: Text(
                      source.bookSourceName,
                      style: GoogleFonts.notoSansSc(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      source.bookSourceUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansSc(
                        fontSize: 12,
                        color: colors.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    secondary: IconButton(
                      tooltip: '删除',
                      onPressed: () async {
                        await ref
                            .read(sourcesProvider.notifier)
                            .deleteSource(source.id);
                        _toast('已删除书源');
                      },
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: colors.onSurface.withValues(alpha: 0.35),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _keywordCtrl,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                        decoration: InputDecoration(
                          hintText: '搜索书名',
                          hintStyle: GoogleFonts.notoSansSc(fontSize: 14),
                          prefixIcon: Icon(Icons.search),
                          filled: true,
                          fillColor: colors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: colors.outline),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: colors.outline),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _searching ? null : _search,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(72, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _searching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('搜索'),
                    ),
                  ],
                ),
              ),
              if (_searchError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _searchError!,
                    style: GoogleFonts.notoSansSc(
                      fontSize: 12,
                      color: colors.error,
                    ),
                  ),
                ),
              Expanded(
                child: _hits.isEmpty
                    ? EmptyState(
                        icon: Icons.search,
                        title: '搜索网络书籍',
                        body: '使用已启用的书源搜索，再加入本地书架阅读。',
                      )
                    : ListView.separated(
                        itemCount: _hits.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          indent: 20,
                          endIndent: 20,
                          color: colors.outline.withValues(alpha: 0.7),
                        ),
                        itemBuilder: (context, index) {
                          final hit = _hits[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 6,
                            ),
                            title: Text(
                              hit.name,
                              style: GoogleFonts.notoSansSc(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Text(
                              [
                                if (hit.author != null && hit.author!.isNotEmpty)
                                  hit.author!,
                                hit.sourceName,
                              ].join(' · '),
                              style: GoogleFonts.notoSansSc(
                                fontSize: 12,
                                color: colors.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                            trailing: TextButton(
                              onPressed: () => _addHit(hit),
                              child: const Text('加入'),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

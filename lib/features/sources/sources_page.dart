import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/source_engine.dart';
import '../../data/source_models.dart';
import '../../providers/library_providers.dart';
import '../../widgets/empty_state.dart';
import '../reader/reader_page.dart';

enum _SearchMatchMode { fuzzy, exact }

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
  bool _exporting = false;
  List<SearchBookHit> _hits = const [];
  String? _searchError;
  String? _searchProgress;
  _SearchMatchMode _matchMode = _SearchMatchMode.fuzzy;
  int _searchGen = 0;

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

  Future<void> _importFromPaste({String? initialText, String? hint}) async {
    final controller = TextEditingController(text: initialText ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('粘贴书源 / 链接'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              maxLines: 12,
              decoration: InputDecoration(
                hintText: hint ??
                    (kIsWeb
                        ? 'Web 下链接常被跨域拦截：请粘贴 JSON/plist 全文；或用 Android/Windows 客户端导入链接'
                        : '支持 Legado JSON、站点 plist，或 Gitee/GitHub 链接'),
                border: const OutlineInputBorder(),
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
      allowedExtensions: const ['json', 'txt', 'plist'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes != null) {
      await _importText(utf8.decode(bytes, allowMalformed: true));
      return;
    }
    _toast('无法读取文件内容');
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
      final msg = '$error';
      final isCorsish = kIsWeb &&
          (msg.contains('跨域') ||
              msg.contains('XMLHttpRequest') ||
              msg.contains('CORS') ||
              msg.contains('浏览器无法'));
      _toast(
        isCorsish
            ? '浏览器无法下载该链接，请粘贴文件正文'
            : '导入失败：$error',
      );
      if (isCorsish) {
        await _importFromPaste(
          hint:
              '请打开 Gitee 页面 → 打开文件 → 全选复制正文粘贴到这里（不要只贴链接）',
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _exportSources({required bool copyOnly}) async {
    setState(() => _exporting = true);
    try {
      final json = await ref.read(sourcesProvider.notifier).exportJson();
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      if (copyOnly || kIsWeb) {
        _toast('已复制书源 JSON，可粘贴保存');
        return;
      }

      await SharePlus.instance.share(
        ShareParams(
          text: json,
          subject: 'InkShelf 书源导出',
        ),
      );
      if (!mounted) return;
      _toast('已导出 ${ref.read(sourcesProvider).value?.length ?? 0} 个书源');
    } catch (error) {
      if (!mounted) return;
      _toast('导出失败：$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  List<SearchBookHit> _filterHits(List<SearchBookHit> raw, String keyword) {
    final key = keyword.trim().toLowerCase();
    final keyCompact = key.replaceAll(RegExp(r'\s+'), '');
    return raw.where((hit) {
      final name = hit.name.trim().toLowerCase();
      final nameCompact = name.replaceAll(RegExp(r'\s+'), '');
      final author = (hit.author ?? '').trim().toLowerCase();
      if (_matchMode == _SearchMatchMode.exact) {
        return nameCompact == keyCompact;
      }
      return name.contains(key) ||
          nameCompact.contains(keyCompact) ||
          author.contains(key);
    }).toList();
  }

  Future<void> _search() async {
    final keyword = _keywordCtrl.text.trim();
    if (keyword.isEmpty) {
      _toast('请输入书名或关键词');
      return;
    }
    final allEnabled = (ref.read(sourcesProvider).value ?? [])
        .where((s) => s.enabled)
        .toList();
    if (allEnabled.isEmpty) {
      _toast('请先添加并启用至少一个书源');
      return;
    }

    final sources = allEnabled
        .where(
          (s) => !SourceEngine.isUnsupportedSearchUrl(s.searchUrl),
        )
        .toList();
    final skipped = allEnabled.length - sources.length;

    final gen = ++_searchGen;
    setState(() {
      _searching = true;
      _searchError = null;
      _searchProgress = '准备搜索 ${sources.length} 个书源…';
      _hits = const [];
    });

    final engine = ref.read(sourceEngineProvider);
    final hits = <SearchBookHit>[];
    final errors = <String>[];
    var done = 0;
    const batchSize = 8;
    const perSourceTimeout = Duration(seconds: 9);
    const enoughHits = 40;

    for (var i = 0; i < sources.length; i += batchSize) {
      if (!mounted || gen != _searchGen) return;
      if (_filterHits(hits, keyword).length >= enoughHits) break;

      final batch = sources.skip(i).take(batchSize).toList();
      final parts = await Future.wait(
        batch.map((source) async {
          try {
            final part = await engine
                .search(source: source, keyword: keyword)
                .timeout(perSourceTimeout);
            return (source.bookSourceName, part, null);
          } on TimeoutException {
            return (source.bookSourceName, const <SearchBookHit>[], '超时');
          } catch (error) {
            return (
              source.bookSourceName,
              const <SearchBookHit>[],
              '$error',
            );
          }
        }),
      );

      for (final (name, part, error) in parts) {
        hits.addAll(part);
        if (error != null) errors.add('$name: $error');
      }
      done += batch.length;

      if (!mounted || gen != _searchGen) return;
      final filteredSoFar = _filterHits(hits, keyword);
      setState(() {
        _hits = filteredSoFar;
        _searchProgress =
            '搜索中 $done/${sources.length} · 已找到 ${filteredSoFar.length}';
      });
    }

    if (!mounted || gen != _searchGen) return;
    final filtered = _filterHits(hits, keyword);
    setState(() {
      _searching = false;
      _searchProgress = null;
      _hits = filtered;
      if (filtered.isEmpty && errors.isNotEmpty) {
        final hint = kIsWeb
            ? 'Web 端受跨域限制，公共代理常超时；请用 Android/Windows 客户端搜书。'
            : (skipped > 0 ? '已跳过 $skipped 个含 JS 的书源。' : null);
        _searchError = [
          ...errors.take(2),
          if (hint != null) hint,
        ].join('\n');
      } else if (filtered.isEmpty && hits.isNotEmpty) {
        _searchError = _matchMode == _SearchMatchMode.exact
            ? '有结果但无精准匹配，可切换「模糊」再试'
            : null;
      } else {
        _searchError = null;
      }
    });
    if (filtered.isEmpty && errors.isEmpty && hits.isEmpty) {
      _toast(skipped > 0 ? '没有搜到结果（已跳过 $skipped 个 JS 书源）' : '没有搜到结果');
    } else if (filtered.isEmpty && hits.isNotEmpty) {
      _toast(
        '无匹配结果（已按${_matchMode == _SearchMatchMode.exact ? '精准' : '模糊'}过滤）',
      );
    } else if (filtered.isEmpty && errors.isNotEmpty) {
      _toast(kIsWeb ? '搜索失败（多为浏览器跨域限制）' : '搜索失败，请检查网络或书源');
    } else if (filtered.isNotEmpty) {
      _toast('找到 ${filtered.length} 条结果');
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
    final sourceCount = sourcesAsync.value?.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('书源'),
        actions: [
          if (_importing || _exporting)
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
            if (sourceCount > 0)
              PopupMenuButton<String>(
                tooltip: '导出',
                icon: const Icon(Icons.ios_share),
                onSelected: (value) {
                  if (value == 'share') {
                    _exportSources(copyOnly: false);
                  } else if (value == 'copy') {
                    _exportSources(copyOnly: true);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'share',
                    child: Text('导出并分享 JSON'),
                  ),
                  PopupMenuItem(
                    value: 'copy',
                    child: Text('复制 JSON 到剪贴板'),
                  ),
                ],
              ),
            IconButton(
              tooltip: '从文件导入',
              onPressed: _importFromFile,
              icon: const Icon(Icons.upload_file),
            ),
            IconButton(
              tooltip: '粘贴 JSON',
              onPressed: _importFromPaste,
              icon: const Icon(Icons.add),
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
                  body: '粘贴或导入书源 JSON 后即可搜索。重装前请先导出备份。',
                  actionLabel: '粘贴 JSON',
                  onAction: _importFromPaste,
                );
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '共 ${sources.length} 个书源 · 已启用 ${sources.where((s) => s.enabled).length} 个',
                            style: GoogleFonts.notoSansSc(
                              fontSize: 12,
                              color: colors.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _exportSources(copyOnly: false),
                          icon: const Icon(Icons.ios_share, size: 18),
                          label: const Text('导出'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
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
                    ),
                  ),
                ],
              );
            },
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
                          prefixIcon: const Icon(Icons.search),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Text(
                      '匹配',
                      style: GoogleFonts.notoSansSc(
                        fontSize: 12,
                        color: colors.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('模糊'),
                      selected: _matchMode == _SearchMatchMode.fuzzy,
                      onSelected: (_) =>
                          setState(() => _matchMode = _SearchMatchMode.fuzzy),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('精准'),
                      selected: _matchMode == _SearchMatchMode.exact,
                      onSelected: (_) =>
                          setState(() => _matchMode = _SearchMatchMode.exact),
                    ),
                    const Spacer(),
                    Text(
                      _searchProgress ?? '已启用书源全部参与',
                      style: GoogleFonts.notoSansSc(
                        fontSize: 11,
                        color: colors.onSurface.withValues(alpha: 0.4),
                      ),
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
                        body: kIsWeb
                            ? '浏览器有跨域限制，公共代理国内常不可用。搜书请优先用 Android / Windows 客户端。'
                            : '使用已启用的多个书源搜索；结果会标注来源书源。',
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
                              vertical: 8,
                            ),
                            title: Text(
                              hit.name,
                              style: GoogleFonts.notoSansSc(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Chip(
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    padding: EdgeInsets.zero,
                                    labelPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    backgroundColor:
                                        colors.primary.withValues(alpha: 0.12),
                                    side: BorderSide.none,
                                    label: Text(
                                      '书源 · ${hit.sourceName}',
                                      style: GoogleFonts.notoSansSc(
                                        fontSize: 11,
                                        color: colors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (hit.author != null &&
                                      hit.author!.isNotEmpty)
                                    Text(
                                      hit.author!,
                                      style: GoogleFonts.notoSansSc(
                                        fontSize: 12,
                                        color: colors.onSurface
                                            .withValues(alpha: 0.55),
                                      ),
                                    ),
                                ],
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

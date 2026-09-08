import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models.dart';
import '../../providers/library_providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final prefs = ref.watch(readerPrefsProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              '阅读偏好会同步到阅读页。',
              style: GoogleFonts.notoSansSc(
                fontSize: 13,
                height: 1.5,
                color: colors.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          Divider(height: 1, color: colors.outline),
          _SettingsTile(
            icon: PhosphorIconsRegular.textAa,
            title: '默认字号',
            subtitle: prefs == null ? '…' : '${prefs.fontSize.round()}',
            onTap: () => _adjustFont(context, ref),
          ),
          _SettingsTile(
            icon: PhosphorIconsRegular.moonStars,
            title: '阅读外观',
            subtitle: prefs == null
                ? '…'
                : prefs.followSystemTheme
                    ? '跟随系统'
                    : (prefs.forceDark ? '夜间' : '纸面'),
            onTap: () => _cycleTheme(ref),
          ),
          _SettingsTile(
            icon: PhosphorIconsRegular.broom,
            title: '清理缓存',
            subtitle: '在书架删除书籍即可清除对应缓存',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('在书架点删除或长按即可清除单本书')),
              );
            },
          ),
          Divider(height: 1, color: colors.outline),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(
              'InkShelf 墨架',
              style: GoogleFonts.notoSansSc(
                fontSize: 12,
                color: colors.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: Text(
              '本地阅读器 · v1.0.0',
              style: GoogleFonts.notoSansSc(
                fontSize: 12,
                color: colors.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _adjustFont(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Consumer(
            builder: (context, ref, _) {
              final prefs =
                  ref.watch(readerPrefsProvider).value ??
                      const ReaderPrefs();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '默认字号 ${prefs.fontSize.round()}',
                    style: GoogleFonts.notoSansSc(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
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
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _cycleTheme(WidgetRef ref) {
    ref.read(readerPrefsProvider.notifier).setPrefs((p) {
      if (p.followSystemTheme) {
        return p.copyWith(followSystemTheme: false, forceDark: false);
      }
      if (!p.forceDark) {
        return p.copyWith(followSystemTheme: false, forceDark: true);
      }
      return p.copyWith(followSystemTheme: true, forceDark: false);
    });
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(icon, color: colors.primary),
      title: Text(
        title,
        style: GoogleFonts.notoSansSc(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.notoSansSc(
          fontSize: 13,
          color: colors.onSurface.withValues(alpha: 0.55),
        ),
      ),
      trailing: Icon(
        PhosphorIconsRegular.caretRight,
        size: 16,
        color: colors.onSurface.withValues(alpha: 0.35),
      ),
      minVerticalPadding: 14,
      onTap: onTap,
    );
  }
}

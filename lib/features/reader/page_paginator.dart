import 'package:flutter/painting.dart';

/// Splits plain chapter text into pages that fit [pageSize] with [style].
///
/// Avoids laying out the entire remaining string on every iteration (that
/// freezes / aborts Flutter Web for long chapters).
class PagePaginator {
  PagePaginator._();

  static List<String> paginate({
    required String text,
    required Size pageSize,
    required TextStyle style,
  }) {
    final content = text.trim();
    if (content.isEmpty) return [''];
    if (pageSize.width <= 0 || pageSize.height <= 0) return [content];

    final metrics = _estimateMetrics(style, pageSize);
    if (metrics.charsPerPage < 80) {
      // Degenerate layout — fall back to coarse chunking.
      return _chunkByLength(content, 1200);
    }

    final pages = <String>[];
    var remaining = content;
    var guard = 0;
    const maxPages = 5000;

    while (remaining.isNotEmpty && guard < maxPages) {
      guard++;
      if (_fits(remaining, pageSize, style)) {
        pages.add(remaining);
        remaining = '';
        break;
      }

      // Start binary search near an estimated cut, not from 1..length on full text.
      final guess = metrics.charsPerPage.clamp(80, remaining.length);
      var low = (guess * 0.45).floor().clamp(1, remaining.length);
      var high = (guess * 1.35).ceil().clamp(low, remaining.length);

      // Expand high until it overflows (or hits end).
      while (high < remaining.length &&
          _fits(remaining.substring(0, high), pageSize, style)) {
        low = high;
        high = (high * 1.5).ceil().clamp(low + 1, remaining.length);
      }

      var fit = low;
      while (low <= high) {
        final mid = (low + high) ~/ 2;
        if (_fits(remaining.substring(0, mid), pageSize, style)) {
          fit = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }

      var breakAt = _preferBreak(remaining, fit);
      if (breakAt <= 0) breakAt = fit.clamp(1, remaining.length);

      pages.add(remaining.substring(0, breakAt).trimRight());
      remaining = remaining.substring(breakAt).trimLeft();
    }

    if (remaining.isNotEmpty) {
      pages.addAll(_chunkByLength(remaining, metrics.charsPerPage));
    }
    return pages.isEmpty ? [''] : pages;
  }

  static bool _fits(String text, Size pageSize, TextStyle style) {
    if (text.isEmpty) return true;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: pageSize.width);
    return painter.height <= pageSize.height;
  }

  static ({double charWidth, double lineHeight, int charsPerPage}) _estimateMetrics(
    TextStyle style,
    Size pageSize,
  ) {
    const sample = '中文阅读测试Aa字高行距0123456789';
    final painter = TextPainter(
      text: TextSpan(text: sample, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final charWidth = (painter.width / sample.length).clamp(6.0, 40.0);
    final lineHeight = (style.height ?? 1.6) * (style.fontSize ?? 19);
    final cols = (pageSize.width / charWidth).floor().clamp(8, 80);
    final rows = (pageSize.height / lineHeight).floor().clamp(4, 80);
    return (
      charWidth: charWidth,
      lineHeight: lineHeight,
      charsPerPage: (cols * rows * 0.92).floor().clamp(80, 8000),
    );
  }

  static int _preferBreak(String remaining, int fit) {
    if (fit >= remaining.length) return fit;
    final windowStart = (fit - 48).clamp(0, fit);
    final window = remaining.substring(windowStart, fit);
    final nl = window.lastIndexOf('\n');
    if (nl >= 0) return windowStart + nl + 1;
    final punct = RegExp(r'[。！？；…\s]');
    Match? last;
    for (final m in punct.allMatches(window)) {
      last = m;
    }
    if (last != null) return windowStart + last.end;
    return fit;
  }

  static List<String> _chunkByLength(String text, int size) {
    if (text.isEmpty) return [''];
    final out = <String>[];
    var i = 0;
    while (i < text.length) {
      final end = (i + size).clamp(0, text.length);
      out.add(text.substring(i, end));
      i = end;
    }
    return out;
  }
}

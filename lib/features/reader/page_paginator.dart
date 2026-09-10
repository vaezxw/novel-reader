import 'package:flutter/painting.dart';

/// Splits plain chapter text into pages that fit [pageSize] with [style].
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

    final pages = <String>[];
    var remaining = content;

    while (remaining.isNotEmpty) {
      final painter = TextPainter(
        text: TextSpan(text: remaining, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: pageSize.width);

      if (painter.height <= pageSize.height) {
        pages.add(remaining);
        break;
      }

      // Binary search how many characters fit in one page height.
      var low = 1;
      var high = remaining.length;
      var fit = 1;
      while (low <= high) {
        final mid = (low + high) ~/ 2;
        final slice = remaining.substring(0, mid);
        final probe = TextPainter(
          text: TextSpan(text: slice, style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: pageSize.width);
        if (probe.height <= pageSize.height) {
          fit = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }

      // Prefer breaking near a newline / punctuation.
      var breakAt = fit;
      if (fit < remaining.length) {
        final windowStart = (fit - 40).clamp(0, fit);
        final window = remaining.substring(windowStart, fit);
        final nl = window.lastIndexOf('\n');
        if (nl >= 0) {
          breakAt = windowStart + nl + 1;
        } else {
          final punct = RegExp(r'[。！？；…\s]');
          Match? last;
          for (final m in punct.allMatches(window)) {
            last = m;
          }
          if (last != null) {
            breakAt = windowStart + last.end;
          }
        }
      }
      if (breakAt <= 0) breakAt = fit.clamp(1, remaining.length);

      pages.add(remaining.substring(0, breakAt).trimRight());
      remaining = remaining.substring(breakAt).trimLeft();
    }

    return pages.isEmpty ? [''] : pages;
  }
}

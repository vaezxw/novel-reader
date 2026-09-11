import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'page_paginator.dart';

/// Horizontal page-flip within a chapter body.
class PageFlipView extends StatefulWidget {
  const PageFlipView({
    super.key,
    required this.text,
    required this.title,
    required this.style,
    required this.titleStyle,
    required this.onTapCenter,
    required this.onPrevChapter,
    required this.onNextChapter,
    this.allowGestureChapterChange = false,
    this.controller,
    this.initialPage = 0,
  });

  final String text;
  final String title;
  final TextStyle style;
  final TextStyle titleStyle;
  final VoidCallback onTapCenter;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;
  /// When true, swiping/tapping past the first/last page changes chapter.
  /// Auto-read still uses [onNextChapter] via [nextPageOrChapter].
  final bool allowGestureChapterChange;
  final PageController? controller;
  final int initialPage;

  @override
  State<PageFlipView> createState() => PageFlipViewState();
}

class PageFlipViewState extends State<PageFlipView> {
  late PageController _controller;
  List<String> _pages = const [''];
  int _pageIndex = 0;
  Size? _lastSize;
  DateTime? _lastChapterGestureAt;

  int get pageIndex => _pageIndex;
  int get pageCount => _pages.length;

  bool nextPageOrChapter() {
    if (_pageIndex < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return true;
    }
    widget.onNextChapter();
    return false;
  }

  void _gesturePrevChapter() {
    if (!_allowChapterGesture()) return;
    widget.onPrevChapter();
  }

  void _gestureNextChapter() {
    if (!_allowChapterGesture()) return;
    widget.onNextChapter();
  }

  bool _allowChapterGesture() {
    if (!widget.allowGestureChapterChange) return false;
    final now = DateTime.now();
    if (_lastChapterGestureAt != null &&
        now.difference(_lastChapterGestureAt!) <
            const Duration(milliseconds: 700)) {
      return false;
    }
    _lastChapterGestureAt = now;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? PageController(initialPage: widget.initialPage);
    _pageIndex = widget.initialPage;
  }

  @override
  void didUpdateWidget(covariant PageFlipView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.title != widget.title) {
      _lastSize = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _ensurePages(Size size) {
    if (_lastSize == size && _pages.isNotEmpty) return;
    _lastSize = size;
    final pageSize = Size(size.width - 44, size.height - 56);
    final bodyPages = PagePaginator.paginate(
      text: widget.text,
      pageSize: pageSize,
      style: widget.style,
    );
    _pages = bodyPages;
    if (_pageIndex >= _pages.length) {
      _pageIndex = _pages.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _ensurePages(Size(constraints.maxWidth, constraints.maxHeight));
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (!widget.allowGestureChapterChange) return false;
            if (notification is OverscrollNotification) {
              if (notification.overscroll < -12 && _pageIndex == 0) {
                _gesturePrevChapter();
              } else if (notification.overscroll > 12 &&
                  _pageIndex >= _pages.length - 1) {
                _gestureNextChapter();
              }
            }
            return false;
          },
          child: PageView.builder(
            controller: _controller,
            // Bouncing makes edge overscroll fire reliably for chapter change.
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _pageIndex = i),
            itemBuilder: (context, index) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final w = constraints.maxWidth;
                  final x = details.localPosition.dx;
                  if (x < w * 0.28) {
                    if (index > 0) {
                      _controller.previousPage(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOut,
                      );
                    } else if (widget.allowGestureChapterChange) {
                      _gesturePrevChapter();
                    } else {
                      widget.onTapCenter();
                    }
                  } else if (x > w * 0.72) {
                    if (index < _pages.length - 1) {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOut,
                      );
                    } else if (widget.allowGestureChapterChange) {
                      _gestureNextChapter();
                    } else {
                      widget.onTapCenter();
                    }
                  } else {
                    widget.onTapCenter();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (index == 0) ...[
                        Text(widget.title, style: widget.titleStyle),
                        const SizedBox(height: 14),
                      ],
                      Expanded(
                        child: Text(
                          _pages[index],
                          style: widget.style,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${index + 1}/${_pages.length}',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansSc(
                          fontSize: 11,
                          color: widget.style.color?.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

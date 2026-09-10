enum BookOrigin { local, remote }

enum ReadMode {
  horizontalChapter,
  verticalScroll,
  pageFlip,
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.fileName,
    required this.chapterCount,
    required this.addedAt,
    this.author,
    this.lastReadAt,
    this.lastChapterIndex = 0,
    this.lastScrollOffset = 0,
    this.origin = BookOrigin.local,
    this.sourceId,
    this.bookUrl,
    this.coverUrl,
    this.intro,
    this.sourceName,
  });

  final String id;
  final String title;
  final String? author;
  final String fileName;
  final int chapterCount;
  final DateTime addedAt;
  final DateTime? lastReadAt;
  final int lastChapterIndex;
  final double lastScrollOffset;
  final BookOrigin origin;
  final String? sourceId;
  final String? bookUrl;
  final String? coverUrl;
  final String? intro;
  final String? sourceName;

  bool get isRemote => origin == BookOrigin.remote;

  double get progress {
    if (chapterCount <= 0) return 0;
    final chapterProgress =
        (lastChapterIndex.clamp(0, chapterCount - 1) + 0.01) / chapterCount;
    return chapterProgress.clamp(0.0, 1.0);
  }

  Book copyWith({
    String? title,
    String? author,
    int? chapterCount,
    DateTime? lastReadAt,
    int? lastChapterIndex,
    double? lastScrollOffset,
    BookOrigin? origin,
    String? sourceId,
    String? bookUrl,
    String? coverUrl,
    String? intro,
    String? sourceName,
  }) {
    return Book(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      fileName: fileName,
      chapterCount: chapterCount ?? this.chapterCount,
      addedAt: addedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      lastChapterIndex: lastChapterIndex ?? this.lastChapterIndex,
      lastScrollOffset: lastScrollOffset ?? this.lastScrollOffset,
      origin: origin ?? this.origin,
      sourceId: sourceId ?? this.sourceId,
      bookUrl: bookUrl ?? this.bookUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      intro: intro ?? this.intro,
      sourceName: sourceName ?? this.sourceName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'fileName': fileName,
        'chapterCount': chapterCount,
        'addedAt': addedAt.toIso8601String(),
        'lastReadAt': lastReadAt?.toIso8601String(),
        'lastChapterIndex': lastChapterIndex,
        'lastScrollOffset': lastScrollOffset,
        'origin': origin.name,
        'sourceId': sourceId,
        'bookUrl': bookUrl,
        'coverUrl': coverUrl,
        'intro': intro,
        'sourceName': sourceName,
      };

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String?,
      fileName: json['fileName'] as String? ?? '',
      chapterCount: json['chapterCount'] as int? ?? 0,
      addedAt: DateTime.parse(json['addedAt'] as String),
      lastReadAt: json['lastReadAt'] == null
          ? null
          : DateTime.parse(json['lastReadAt'] as String),
      lastChapterIndex: json['lastChapterIndex'] as int? ?? 0,
      lastScrollOffset: (json['lastScrollOffset'] as num?)?.toDouble() ?? 0,
      origin: BookOrigin.values.firstWhere(
        (e) => e.name == json['origin'],
        orElse: () => BookOrigin.local,
      ),
      sourceId: json['sourceId'] as String?,
      bookUrl: json['bookUrl'] as String?,
      coverUrl: json['coverUrl'] as String?,
      intro: json['intro'] as String?,
      sourceName: json['sourceName'] as String?,
    );
  }
}

class ChapterRef {
  const ChapterRef({
    required this.index,
    required this.title,
    this.start = 0,
    this.end = 0,
    this.url,
  });

  final int index;
  final String title;
  final int start;
  final int end;
  final String? url;

  bool get isRemote => url != null && url!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'index': index,
        'title': title,
        'start': start,
        'end': end,
        'url': url,
      };

  factory ChapterRef.fromJson(Map<String, dynamic> json) {
    return ChapterRef(
      index: json['index'] as int,
      title: json['title'] as String,
      start: json['start'] as int? ?? 0,
      end: json['end'] as int? ?? 0,
      url: json['url'] as String?,
    );
  }
}

class Bookmark {
  const Bookmark({
    required this.id,
    required this.chapterIndex,
    required this.title,
    required this.createdAt,
    this.scrollOffset = 0,
  });

  final String id;
  final int chapterIndex;
  final String title;
  final DateTime createdAt;
  final double scrollOffset;

  Map<String, dynamic> toJson() => {
        'id': id,
        'chapterIndex': chapterIndex,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'scrollOffset': scrollOffset,
      };

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      id: json['id'] as String,
      chapterIndex: json['chapterIndex'] as int,
      title: json['title'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      scrollOffset: (json['scrollOffset'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ReaderPrefs {
  const ReaderPrefs({
    this.fontSize = 19,
    this.lineHeight = 1.78,
    this.forceDark = false,
    this.followSystemTheme = true,
    this.readMode = ReadMode.horizontalChapter,
    this.autoReadEnabled = false,
    this.autoReadSpeed = 1.0,
    this.followSystemBrightness = true,
    this.brightness = 0.7,
  });

  final double fontSize;
  final double lineHeight;
  final bool forceDark;
  final bool followSystemTheme;
  final ReadMode readMode;
  final bool autoReadEnabled;
  final double autoReadSpeed;
  final bool followSystemBrightness;
  final double brightness;

  ReaderPrefs copyWith({
    double? fontSize,
    double? lineHeight,
    bool? forceDark,
    bool? followSystemTheme,
    ReadMode? readMode,
    bool? autoReadEnabled,
    double? autoReadSpeed,
    bool? followSystemBrightness,
    double? brightness,
  }) {
    return ReaderPrefs(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      forceDark: forceDark ?? this.forceDark,
      followSystemTheme: followSystemTheme ?? this.followSystemTheme,
      readMode: readMode ?? this.readMode,
      autoReadEnabled: autoReadEnabled ?? this.autoReadEnabled,
      autoReadSpeed: autoReadSpeed ?? this.autoReadSpeed,
      followSystemBrightness:
          followSystemBrightness ?? this.followSystemBrightness,
      brightness: brightness ?? this.brightness,
    );
  }

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'forceDark': forceDark,
        'followSystemTheme': followSystemTheme,
        'readMode': readMode.name,
        'autoReadEnabled': autoReadEnabled,
        'autoReadSpeed': autoReadSpeed,
        'followSystemBrightness': followSystemBrightness,
        'brightness': brightness,
      };

  factory ReaderPrefs.fromJson(Map<String, dynamic> json) {
    return ReaderPrefs(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 19,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.78,
      forceDark: json['forceDark'] as bool? ?? false,
      followSystemTheme: json['followSystemTheme'] as bool? ?? true,
      readMode: ReadMode.values.firstWhere(
        (e) => e.name == json['readMode'],
        orElse: () => ReadMode.horizontalChapter,
      ),
      autoReadEnabled: json['autoReadEnabled'] as bool? ?? false,
      autoReadSpeed: (json['autoReadSpeed'] as num?)?.toDouble() ?? 1.0,
      followSystemBrightness: json['followSystemBrightness'] as bool? ?? true,
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.7,
    );
  }

  String get readModeLabel => switch (readMode) {
        ReadMode.horizontalChapter => '左右切章',
        ReadMode.verticalScroll => '上下滚动',
        ReadMode.pageFlip => '仿真翻页',
      };
}

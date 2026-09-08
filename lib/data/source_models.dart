import 'dart:convert';

class BookSource {
  const BookSource({
    required this.id,
    required this.bookSourceName,
    required this.bookSourceUrl,
    required this.raw,
    this.searchUrl,
    this.enabled = true,
    this.bookSourceGroup,
    this.headerJson,
  });

  final String id;
  final String bookSourceName;
  final String bookSourceUrl;
  final String? bookSourceGroup;
  final String? searchUrl;
  final bool enabled;
  final String? headerJson;
  final Map<String, dynamic> raw;

  Map<String, dynamic>? get ruleSearch =>
      raw['ruleSearch'] as Map<String, dynamic>?;
  Map<String, dynamic>? get ruleBookInfo =>
      raw['ruleBookInfo'] as Map<String, dynamic>?;
  Map<String, dynamic>? get ruleToc =>
      raw['ruleToc'] as Map<String, dynamic>?;
  Map<String, dynamic>? get ruleContent =>
      raw['ruleContent'] as Map<String, dynamic>?;

  BookSource copyWith({bool? enabled}) {
    return BookSource(
      id: id,
      bookSourceName: bookSourceName,
      bookSourceUrl: bookSourceUrl,
      bookSourceGroup: bookSourceGroup,
      searchUrl: searchUrl,
      enabled: enabled ?? this.enabled,
      headerJson: headerJson,
      raw: raw,
    );
  }

  Map<String, dynamic> toStorageJson() => {
        'id': id,
        'enabled': enabled,
        'raw': raw,
      };

  factory BookSource.fromLegadoJson(
    Map<String, dynamic> json, {
    String? id,
    bool? enabled,
  }) {
    String? header;
    final rawHeader = json['header'];
    if (rawHeader is String) {
      header = rawHeader;
    } else if (rawHeader != null) {
      header = jsonEncode(rawHeader);
    }

    return BookSource(
      id: id ??
          (json['bookSourceUrl'] as String? ??
              json['bookSourceName'] as String? ??
              DateTime.now().millisecondsSinceEpoch.toString()),
      bookSourceName: (json['bookSourceName'] as String?)?.trim().isNotEmpty ==
              true
          ? json['bookSourceName'] as String
          : '未命名书源',
      bookSourceUrl: json['bookSourceUrl'] as String? ?? '',
      bookSourceGroup: json['bookSourceGroup'] as String?,
      searchUrl: json['searchUrl'] as String?,
      enabled: enabled ?? (json['enabled'] as bool? ?? true),
      headerJson: header,
      raw: Map<String, dynamic>.from(json),
    );
  }

  factory BookSource.fromStorageJson(Map<String, dynamic> json) {
    final raw = Map<String, dynamic>.from(json['raw'] as Map);
    return BookSource.fromLegadoJson(
      raw,
      id: json['id'] as String?,
      enabled: json['enabled'] as bool?,
    );
  }
}

class SearchBookHit {
  const SearchBookHit({
    required this.sourceId,
    required this.sourceName,
    required this.name,
    required this.bookUrl,
    this.author,
    this.intro,
    this.coverUrl,
  });

  final String sourceId;
  final String sourceName;
  final String name;
  final String? author;
  final String? intro;
  final String? coverUrl;
  final String bookUrl;
}

class RemoteChapter {
  const RemoteChapter({
    required this.title,
    required this.url,
  });

  final String title;
  final String url;
}

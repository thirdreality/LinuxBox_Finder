class BrowserUrl {
  final String name;
  final String url;

  BrowserUrl({required this.name, required this.url});

  factory BrowserUrl.fromJson(Map<String, dynamic> json) {
    return BrowserUrl(
      name: json['name'] as String,
      url: json['url'] as String,
    );
  }
}

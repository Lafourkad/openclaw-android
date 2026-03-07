import 'dart:convert';
import 'dart:io';

/// Resolves Alpine package names to download URLs dynamically via APKINDEX.
/// No hardcoded versions — always fetches the latest from the Alpine repo.
class AlpineResolver {
  static const _base = 'https://dl-cdn.alpinelinux.org/alpine/v3.21';
  static const _mainUrl = '$_base/main/aarch64';
  static const _communityUrl = '$_base/community/aarch64';

  // In-memory cache: repoUrl → parsed package map
  static final Map<String, Map<String, _ApkEntry>> _cache = {};

  /// Returns list of APK URLs needed for [pkgName] and all its named deps.
  static Future<List<String>> resolveDeps(
    String pkgName, {
    bool community = false,
    int maxDepth = 3,
  }) async {
    final repoUrl = community ? _communityUrl : _mainUrl;

    // Try main first, then community if not found
    final index = await _getIndex(repoUrl);
    var entry = index[pkgName];

    // Fallback: check the other repo
    if (entry == null) {
      final otherUrl = community ? _mainUrl : _communityUrl;
      final otherIndex = await _getIndex(otherUrl);
      entry = otherIndex[pkgName];
      if (entry != null) {
        return _collectUrls(pkgName, otherUrl, otherIndex, await _getIndex(repoUrl), maxDepth);
      }
    }

    if (entry == null) throw 'Package not found in Alpine index: $pkgName';

    return _collectUrls(pkgName, repoUrl, index, await _getIndex(
      community ? _mainUrl : _communityUrl,
    ), maxDepth);
  }

  static Future<List<String>> _collectUrls(
    String pkgName,
    String primaryUrl,
    Map<String, _ApkEntry> primaryIndex,
    Map<String, _ApkEntry> secondaryIndex,
    int maxDepth,
  ) async {
    final visited = <String>{};
    final urls = <String>[];

    Future<void> resolve(String name, int depth) async {
      if (visited.contains(name) || depth > maxDepth) return;
      visited.add(name);

      var entry = primaryIndex[name];
      var repoUrl = primaryUrl;
      if (entry == null) {
        entry = secondaryIndex[name];
        repoUrl = primaryUrl == _mainUrl ? _communityUrl : _mainUrl;
      }
      if (entry == null) return; // Skip unknown deps silently

      urls.add('$repoUrl/${entry.filename}');

      for (final dep in entry.deps) {
        await resolve(dep, depth + 1);
      }
    }

    await resolve(pkgName, 0);
    return urls;
  }

  /// Fetch and parse APKINDEX for a repo, with in-memory caching.
  static Future<Map<String, _ApkEntry>> _getIndex(String repoUrl) async {
    if (_cache.containsKey(repoUrl)) return _cache[repoUrl]!;

    final url = '$repoUrl/APKINDEX.tar.gz';
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw 'Failed to fetch APKINDEX from $url: ${response.statusCode}';
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      final index = _parseApkIndex(bytes);
      _cache[repoUrl] = index;
      return index;
    } finally {
      client.close();
    }
  }

  /// Parse raw APKINDEX.tar.gz bytes → map of package name → entry.
  static Map<String, _ApkEntry> _parseApkIndex(List<int> bytes) {
    // Decompress gzip
    final decompressed = GZipCodec().decode(bytes);

    // Parse tar manually — APKINDEX.tar.gz contains two files: DESCRIPTION and APKINDEX
    // We need the APKINDEX file content
    final apkindexContent = _extractFileFromTar(decompressed, 'APKINDEX');
    if (apkindexContent == null) throw 'APKINDEX not found in tar';

    final text = utf8.decode(apkindexContent);
    final result = <String, _ApkEntry>{};

    // Stanzas separated by blank lines
    for (final stanza in text.split('\n\n')) {
      if (stanza.trim().isEmpty) continue;

      String? name, version;
      final deps = <String>[];

      for (final line in stanza.split('\n')) {
        if (line.startsWith('P:')) name = line.substring(2).trim();
        if (line.startsWith('V:')) version = line.substring(2).trim();
        if (line.startsWith('D:')) {
          for (final dep in line.substring(2).trim().split(' ')) {
            final d = dep.trim();
            if (d.isEmpty) continue;
            // Skip: so:*, pc:*, !*, /bin/*, cmd:*
            if (d.startsWith('so:') || d.startsWith('pc:') ||
                d.startsWith('!') || d.startsWith('/') ||
                d.startsWith('cmd:')) continue;
            // Strip version constraints: dep=1.0 or dep>=1.0
            final clean = d.split(RegExp(r'[=<>]'))[0].trim();
            if (clean.isNotEmpty) deps.add(clean);
          }
        }
      }

      if (name != null && version != null) {
        result[name] = _ApkEntry(
          name: name,
          version: version,
          filename: '$name-$version.apk',
          deps: deps,
        );
      }
    }

    return result;
  }

  /// Extract a named file from a raw (decompressed) tar archive.
  static List<int>? _extractFileFromTar(List<int> tar, String filename) {
    int offset = 0;
    while (offset + 512 <= tar.length) {
      // Read tar header (512 bytes)
      final header = tar.sublist(offset, offset + 512);

      // Check for end-of-archive (two zero blocks)
      if (header.every((b) => b == 0)) break;

      // Filename: bytes 0–99, null-terminated
      final nameBytes = header.sublist(0, 100).takeWhile((b) => b != 0).toList();
      final name = utf8.decode(nameBytes).trim();

      // File size: bytes 124–135, octal ASCII
      final sizeStr = String.fromCharCodes(
        header.sublist(124, 136).takeWhile((b) => b != 0),
      ).trim();
      final size = int.tryParse(sizeStr, radix: 8) ?? 0;

      offset += 512; // Skip header

      if (name == filename || name.endsWith('/$filename')) {
        return tar.sublist(offset, offset + size);
      }

      // Skip file content (rounded up to 512-byte blocks)
      offset += ((size + 511) ~/ 512) * 512;
    }
    return null;
  }

  /// Clear the in-memory cache (call if you want to re-fetch fresh data).
  static void clearCache() => _cache.clear();
}

// Helper for HttpClient response reading
Future<List<int>> consolidateHttpClientResponseBytes(HttpClientResponse response) async {
  final chunks = <List<int>>[];
  await for (final chunk in response) {
    chunks.add(chunk);
  }
  return chunks.expand((c) => c).toList();
}

class _ApkEntry {
  final String name;
  final String version;
  final String filename;
  final List<String> deps;
  const _ApkEntry({required this.name, required this.version, required this.filename, required this.deps});
}

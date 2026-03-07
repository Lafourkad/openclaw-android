import 'package:flutter/material.dart';

/// Package source types.
enum PackageSource {
  /// Our curated GitHub releases (Python, Go, Busybox)
  github,
  /// Alpine Linux main repo (musl aarch64)
  alpineMain,
  /// Alpine Linux community repo
  alpineCommunity,
  /// Termux glibc repo
  termux,
}

/// A package available from an external source.
class RegistryPackage {
  final String id;
  final String name;
  final String version;
  final String description;
  final String category;
  final IconData icon;
  final Color color;
  final PackageSource source;
  final String downloadUrl;
  final String? estimatedSize;
  /// Binary paths to check (relative to install dir)
  final List<String> binaries;
  /// Library dependencies (other Alpine APKs needed)
  final List<String> deps;
  /// If true, install automatically during bootstrap
  final bool defaultInstall;

  const RegistryPackage({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.category,
    required this.icon,
    required this.color,
    required this.source,
    required this.downloadUrl,
    this.estimatedSize,
    this.binaries = const [],
    this.deps = const [],
    this.defaultInstall = false,
  });
}

/// Curated package catalog — hand-picked useful tools.
class PackageRegistry {
  static const _alpineMain = 'https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64';
  static const _alpineCommunity = 'https://dl-cdn.alpinelinux.org/alpine/v3.21/community/aarch64';

  static const List<RegistryPackage> catalog = [
    // ── CLI Essentials ──
    RegistryPackage(
      id: 'jq', name: 'jq', version: '1.7.1',
      description: 'JSON processor — parse, filter, transform JSON',
      category: 'CLI Tools', icon: Icons.data_object, color: Colors.teal,
      source: PackageSource.alpineMain,
      downloadUrl: '$_alpineMain/jq-1.7.1-r0.apk',
      estimatedSize: '~500 KB', binaries: ['usr/bin/jq'],
      deps: ['oniguruma'],
    ),
    RegistryPackage(
      id: 'curl', name: 'curl', version: '8.14.1',
      description: 'HTTP client — download files, test APIs',
      category: 'CLI Tools', icon: Icons.cloud_download, color: Colors.blue,
      source: PackageSource.alpineMain,
      downloadUrl: '$_alpineMain/curl-8.14.1-r2.apk',
      estimatedSize: '~500 KB', binaries: ['usr/bin/curl'],
    ),
    RegistryPackage(
      id: 'wget', name: 'wget', version: '1.25.0',
      description: 'File downloader — recursive, resumable',
      category: 'CLI Tools', icon: Icons.download, color: Colors.indigo,
      source: PackageSource.alpineMain,
      downloadUrl: '$_alpineMain/wget-1.25.0-r0.apk',
      estimatedSize: '~600 KB', binaries: ['usr/bin/wget'],
    ),
    RegistryPackage(
      id: 'tree', name: 'tree', version: '2.2.1',
      description: 'Directory listing in tree format',
      category: 'CLI Tools', icon: Icons.account_tree, color: Colors.green,
      source: PackageSource.alpineMain,
      downloadUrl: '$_alpineMain/tree-2.2.1-r0.apk',
      estimatedSize: '~50 KB', binaries: ['usr/bin/tree'],
    ),
    RegistryPackage(
      id: 'less', name: 'less', version: '668',
      description: 'Pager — scroll through text files',
      category: 'CLI Tools', icon: Icons.description, color: Colors.blueGrey,
      source: PackageSource.alpineMain,
      downloadUrl: '$_alpineMain/less-668-r0.apk',
      estimatedSize: '~150 KB', binaries: ['usr/bin/less'],
    ),

    // ── Modern CLI ──
    RegistryPackage(
      id: 'ripgrep', name: 'ripgrep', version: '14.1.1',
      description: 'Ultra-fast grep — regex search in files',
      category: 'Modern CLI', icon: Icons.search, color: Colors.purple,
      source: PackageSource.alpineCommunity,
      downloadUrl: '$_alpineCommunity/ripgrep-14.1.1-r0.apk',
      estimatedSize: '~2 MB', binaries: ['usr/bin/rg'],
    ),
    RegistryPackage(
      id: 'fd', name: 'fd', version: '10.2.0',
      description: 'Modern find — fast file search',
      category: 'Modern CLI', icon: Icons.folder_open, color: Colors.deepPurple,
      source: PackageSource.alpineCommunity,
      downloadUrl: '$_alpineCommunity/fd-10.2.0-r0.apk',
      estimatedSize: '~1.5 MB', binaries: ['usr/bin/fd'],
    ),
    RegistryPackage(
      id: 'bat', name: 'bat', version: '0.24.0',
      description: 'Cat with syntax highlighting and git integration',
      category: 'Modern CLI', icon: Icons.code, color: Colors.amber,
      source: PackageSource.alpineCommunity,
      downloadUrl: '$_alpineCommunity/bat-0.24.0-r3.apk',
      estimatedSize: '~3 MB', binaries: ['usr/bin/bat'],
    ),
    RegistryPackage(
      id: 'fzf', name: 'fzf', version: '0.56.3',
      description: 'Fuzzy finder — interactive search/filter',
      category: 'Modern CLI', icon: Icons.filter_list, color: Colors.pink,
      source: PackageSource.alpineCommunity,
      downloadUrl: '$_alpineCommunity/fzf-0.56.3-r5.apk',
      estimatedSize: '~2 MB', binaries: ['usr/bin/fzf'],
    ),
    RegistryPackage(
      id: 'eza', name: 'eza', version: '0.20.12',
      description: 'Modern ls replacement with colors, git status, icons',
      category: 'Modern CLI', icon: Icons.list, color: Colors.lime,
      source: PackageSource.alpineCommunity,
      downloadUrl: '$_alpineCommunity/eza-0.20.12-r0.apk',
      estimatedSize: '~1 MB', binaries: ['usr/bin/eza'],
    ),

    // ── Editors ──
    RegistryPackage(
      id: 'nano', name: 'nano', version: '8.2',
      description: 'Simple terminal text editor',
      category: 'Editors', icon: Icons.edit, color: Colors.grey,
      source: PackageSource.alpineMain,
      downloadUrl: '$_alpineMain/nano-8.2-r0.apk',
      estimatedSize: '~400 KB', binaries: ['usr/bin/nano'],
    ),
    RegistryPackage(
      id: 'neovim', name: 'Neovim', version: '0.10.4',
      description: 'Modern Vim — extensible editor',
      category: 'Editors', icon: Icons.terminal, color: Colors.green,
      source: PackageSource.alpineCommunity,
      downloadUrl: '$_alpineCommunity/neovim-0.10.4-r0.apk',
      estimatedSize: '~8 MB', binaries: ['usr/bin/nvim'],
    ),

    // ── Data & Media ──
    RegistryPackage(
      id: 'sqlite', name: 'SQLite', version: '3.48.0',
      description: 'Embedded SQL database — query .db files',
      category: 'Data & Media', icon: Icons.storage, color: Colors.blue,
      source: PackageSource.alpineMain,
      downloadUrl: '$_alpineMain/sqlite-3.48.0-r4.apk',
      estimatedSize: '~1 MB', binaries: ['usr/bin/sqlite3'],
    ),
    RegistryPackage(
      id: 'ffmpeg', name: 'FFmpeg', version: '6.1.2',
      description: 'Audio/video processing — convert, trim, encode',
      category: 'Data & Media', icon: Icons.movie, color: Colors.red,
      source: PackageSource.alpineCommunity,
      downloadUrl: '$_alpineCommunity/ffmpeg-6.1.2-r1.apk',
      estimatedSize: '~15 MB', binaries: ['usr/bin/ffmpeg', 'usr/bin/ffprobe'],
      defaultInstall: true,
    ),
    RegistryPackage(
      id: 'yt-dlp', name: 'yt-dlp', version: '2025.03.31',
      description: 'Download videos from YouTube and 1000+ sites',
      category: 'Data & Media', icon: Icons.video_library, color: Colors.red,
      source: PackageSource.alpineCommunity,
      downloadUrl: '$_alpineCommunity/yt-dlp-2025.03.31-r0.apk',
      estimatedSize: '~5 MB', binaries: ['usr/bin/yt-dlp'],
    ),

    // ── Network & Security ──
    RegistryPackage(
      id: 'openssh', name: 'OpenSSH', version: '9.9p2',
      description: 'SSH client — connect to remote servers',
      category: 'Network', icon: Icons.vpn_key, color: Colors.orange,
      source: PackageSource.alpineMain,
      downloadUrl: '$_alpineMain/openssh-9.9_p2-r0.apk',
      estimatedSize: '~2 MB', binaries: ['usr/bin/ssh', 'usr/bin/scp', 'usr/bin/ssh-keygen'],
    ),
    RegistryPackage(
      id: 'socat', name: 'socat', version: '1.8.0',
      description: 'Multipurpose relay — TCP/UDP tunnels, proxies',
      category: 'Network', icon: Icons.swap_horiz, color: Colors.cyan,
      source: PackageSource.alpineMain,
      downloadUrl: '$_alpineMain/socat-1.8.0.3-r0.apk',
      estimatedSize: '~300 KB', binaries: ['usr/bin/socat'],
    ),
    RegistryPackage(
      id: 'age', name: 'age', version: '1.2.1',
      description: 'Modern encryption tool — simple file encryption',
      category: 'Network', icon: Icons.lock, color: Colors.deepOrange,
      source: PackageSource.alpineCommunity,
      downloadUrl: '$_alpineCommunity/age-1.2.1-r5.apk',
      estimatedSize: '~3 MB', binaries: ['usr/bin/age', 'usr/bin/age-keygen'],
    ),

    // ── System ──
    RegistryPackage(
      id: 'htop', name: 'htop', version: '3.3.0',
      description: 'Interactive process viewer',
      category: 'System', icon: Icons.monitor_heart, color: Colors.green,
      source: PackageSource.alpineMain,
      downloadUrl: '$_alpineMain/htop-3.3.0-r0.apk',
      estimatedSize: '~300 KB', binaries: ['usr/bin/htop'],
    ),
    RegistryPackage(
      id: 'tmux', name: 'tmux', version: '3.5a',
      description: 'Terminal multiplexer — split panes, detach sessions',
      category: 'System', icon: Icons.view_column, color: Colors.teal,
      source: PackageSource.alpineMain,
      downloadUrl: '$_alpineMain/tmux-3.5a-r0.apk',
      estimatedSize: '~500 KB', binaries: ['usr/bin/tmux'],
    ),
    RegistryPackage(
      id: 'rsync', name: 'rsync', version: '3.4.1',
      description: 'Fast file sync — incremental copy/backup',
      category: 'System', icon: Icons.sync, color: Colors.indigo,
      source: PackageSource.alpineMain,
      downloadUrl: '$_alpineMain/rsync-3.4.1-r1.apk',
      estimatedSize: '~500 KB', binaries: ['usr/bin/rsync'],
    ),

    // ── Archive ──
    RegistryPackage(
      id: 'zip', name: 'zip', version: '3.0',
      description: 'Create ZIP archives',
      category: 'Archive', icon: Icons.folder_zip, color: Colors.brown,
      source: PackageSource.alpineMain,
      downloadUrl: '$_alpineMain/zip-3.0-r13.apk',
      estimatedSize: '~200 KB', binaries: ['usr/bin/zip'],
    ),
    RegistryPackage(
      id: 'unzip', name: 'unzip', version: '6.0',
      description: 'Extract ZIP archives',
      category: 'Archive', icon: Icons.folder_zip, color: Colors.brown,
      source: PackageSource.alpineMain,
      downloadUrl: '$_alpineMain/unzip-6.0-r15.apk',
      estimatedSize: '~200 KB', binaries: ['usr/bin/unzip'],
    ),
  ];

  /// Group packages by category.
  static Map<String, List<RegistryPackage>> get byCategory {
    final map = <String, List<RegistryPackage>>{};
    for (final pkg in catalog) {
      map.putIfAbsent(pkg.category, () => []).add(pkg);
    }
    return map;
  }
}

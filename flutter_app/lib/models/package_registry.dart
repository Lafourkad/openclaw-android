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
  /// Download URL(s). Only used for non-Alpine packages (e.g. GitHub releases).
  /// Alpine packages use AlpineResolver — leave this empty.
  final List<String> downloadUrls;
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
    required this.downloadUrls,
    this.estimatedSize,
    this.binaries = const [],
    this.deps = const [],
    this.defaultInstall = false,
  });
}

/// Curated package catalog — hand-picked useful tools.
class PackageRegistry {
  static const List<RegistryPackage> catalog = [
    // ── CLI Essentials ──
    RegistryPackage(
      id: 'jq', name: 'jq', version: '1.7.x',
      description: 'JSON processor — parse, filter, transform JSON',
      category: 'CLI Tools', icon: Icons.data_object, color: Colors.teal,
      source: PackageSource.alpineMain,
      downloadUrls: [],
      estimatedSize: '~1 MB', binaries: ['usr/bin/jq'],
    ),
    RegistryPackage(
      id: 'curl', name: 'curl', version: 'latest',
      description: 'HTTP client — download files, test APIs',
      category: 'CLI Tools', icon: Icons.cloud_download, color: Colors.blue,
      source: PackageSource.alpineMain,
      downloadUrls: [],
      estimatedSize: '~2 MB', binaries: ['usr/bin/curl'],
    ),
    RegistryPackage(
      id: 'wget', name: 'wget', version: 'latest',
      description: 'File downloader — recursive, resumable',
      category: 'CLI Tools', icon: Icons.download, color: Colors.indigo,
      source: PackageSource.alpineMain,
      downloadUrls: [],
      estimatedSize: '~600 KB', binaries: ['usr/bin/wget'],
    ),
    RegistryPackage(
      id: 'tree', name: 'tree', version: 'latest',
      description: 'Directory listing in tree format',
      category: 'CLI Tools', icon: Icons.account_tree, color: Colors.green,
      source: PackageSource.alpineMain,
      downloadUrls: [],
      estimatedSize: '~50 KB', binaries: ['usr/bin/tree'],
    ),
    RegistryPackage(
      id: 'less', name: 'less', version: 'latest',
      description: 'Pager — scroll through text files',
      category: 'CLI Tools', icon: Icons.description, color: Colors.blueGrey,
      source: PackageSource.alpineMain,
      downloadUrls: [],
      estimatedSize: '~150 KB', binaries: ['usr/bin/less'],
    ),

    // ── Modern CLI ──
    RegistryPackage(
      id: 'ripgrep', name: 'ripgrep', version: 'latest',
      description: 'Ultra-fast grep — regex search in files',
      category: 'Modern CLI', icon: Icons.search, color: Colors.purple,
      source: PackageSource.alpineCommunity,
      downloadUrls: [],
      estimatedSize: '~2 MB', binaries: ['usr/bin/rg'],
    ),
    RegistryPackage(
      id: 'fd', name: 'fd', version: 'latest',
      description: 'Modern find — fast file search',
      category: 'Modern CLI', icon: Icons.folder_open, color: Colors.deepPurple,
      source: PackageSource.alpineCommunity,
      downloadUrls: [],
      estimatedSize: '~1.5 MB', binaries: ['usr/bin/fd'],
    ),
    RegistryPackage(
      id: 'bat', name: 'bat', version: 'latest',
      description: 'Cat with syntax highlighting and git integration',
      category: 'Modern CLI', icon: Icons.code, color: Colors.amber,
      source: PackageSource.alpineCommunity,
      downloadUrls: [],
      estimatedSize: '~3 MB', binaries: ['usr/bin/bat'],
    ),
    RegistryPackage(
      id: 'fzf', name: 'fzf', version: 'latest',
      description: 'Fuzzy finder — interactive search/filter',
      category: 'Modern CLI', icon: Icons.filter_list, color: Colors.pink,
      source: PackageSource.alpineCommunity,
      downloadUrls: [],
      estimatedSize: '~2 MB', binaries: ['usr/bin/fzf'],
    ),
    RegistryPackage(
      id: 'eza', name: 'eza', version: 'latest',
      description: 'Modern ls replacement with colors, git status, icons',
      category: 'Modern CLI', icon: Icons.list, color: Colors.lime,
      source: PackageSource.alpineCommunity,
      downloadUrls: [],
      estimatedSize: '~1 MB', binaries: ['usr/bin/eza'],
    ),

    // ── Editors ──
    RegistryPackage(
      id: 'nano', name: 'nano', version: 'latest',
      description: 'Simple terminal text editor',
      category: 'Editors', icon: Icons.edit, color: Colors.grey,
      source: PackageSource.alpineMain,
      downloadUrls: [],
      estimatedSize: '~400 KB', binaries: ['usr/bin/nano'],
    ),
    RegistryPackage(
      id: 'neovim', name: 'Neovim', version: 'latest',
      description: 'Modern Vim — extensible editor',
      category: 'Editors', icon: Icons.terminal, color: Colors.green,
      source: PackageSource.alpineCommunity,
      downloadUrls: [],
      estimatedSize: '~8 MB', binaries: ['usr/bin/nvim'],
    ),

    // ── Data & Media ──
    RegistryPackage(
      id: 'sqlite', name: 'SQLite', version: 'latest',
      description: 'Embedded SQL database — query .db files',
      category: 'Data & Media', icon: Icons.storage, color: Colors.blue,
      source: PackageSource.alpineMain,
      downloadUrls: [],
      estimatedSize: '~1 MB', binaries: ['usr/bin/sqlite3'],
    ),
    RegistryPackage(
      id: 'ffmpeg', name: 'FFmpeg', version: 'latest',
      description: 'Audio/video processing — convert, trim, encode',
      category: 'Data & Media', icon: Icons.movie, color: Colors.red,
      source: PackageSource.alpineCommunity,
      downloadUrls: [],
      estimatedSize: '~15 MB', binaries: ['usr/bin/ffmpeg', 'usr/bin/ffprobe'],
      defaultInstall: true,
    ),
    RegistryPackage(
      id: 'yt-dlp', name: 'yt-dlp', version: '2026.03.03',
      description: 'Download videos from YouTube and 1000+ sites',
      category: 'Data & Media', icon: Icons.video_library, color: Colors.red,
      source: PackageSource.github,
      downloadUrls: ['https://github.com/yt-dlp/yt-dlp/releases/download/2026.03.03/yt-dlp_linux_aarch64'],
      estimatedSize: '~5 MB', binaries: ['usr/bin/yt-dlp'],
    ),

    // ── Network & Security ──
    RegistryPackage(
      id: 'openssh-client-default', name: 'OpenSSH', version: 'latest',
      description: 'SSH client — connect to remote servers',
      category: 'Network', icon: Icons.vpn_key, color: Colors.orange,
      source: PackageSource.alpineMain,
      downloadUrls: [],
      estimatedSize: '~2 MB', binaries: ['usr/bin/ssh', 'usr/bin/scp', 'usr/bin/ssh-keygen'],
    ),
    RegistryPackage(
      id: 'socat', name: 'socat', version: 'latest',
      description: 'Multipurpose relay — TCP/UDP tunnels, proxies',
      category: 'Network', icon: Icons.swap_horiz, color: Colors.cyan,
      source: PackageSource.alpineMain,
      downloadUrls: [],
      estimatedSize: '~300 KB', binaries: ['usr/bin/socat'],
    ),
    RegistryPackage(
      id: 'age', name: 'age', version: 'latest',
      description: 'Modern encryption tool — simple file encryption',
      category: 'Network', icon: Icons.lock, color: Colors.deepOrange,
      source: PackageSource.alpineCommunity,
      downloadUrls: [],
      estimatedSize: '~3 MB', binaries: ['usr/bin/age', 'usr/bin/age-keygen'],
    ),

    // ── System ──
    RegistryPackage(
      id: 'htop', name: 'htop', version: 'latest',
      description: 'Interactive process viewer',
      category: 'System', icon: Icons.monitor_heart, color: Colors.green,
      source: PackageSource.alpineMain,
      downloadUrls: [],
      estimatedSize: '~300 KB', binaries: ['usr/bin/htop'],
    ),
    RegistryPackage(
      id: 'tmux', name: 'tmux', version: 'latest',
      description: 'Terminal multiplexer — split panes, detach sessions',
      category: 'System', icon: Icons.view_column, color: Colors.teal,
      source: PackageSource.alpineMain,
      downloadUrls: [],
      estimatedSize: '~700 KB', binaries: ['usr/bin/tmux'],
    ),
    RegistryPackage(
      id: 'rsync', name: 'rsync', version: 'latest',
      description: 'Fast file sync — incremental copy/backup',
      category: 'System', icon: Icons.sync, color: Colors.indigo,
      source: PackageSource.alpineMain,
      downloadUrls: [],
      estimatedSize: '~500 KB', binaries: ['usr/bin/rsync'],
    ),

    // ── Archive ──
    RegistryPackage(
      id: 'zip', name: 'zip', version: 'latest',
      description: 'Create ZIP archives',
      category: 'Archive', icon: Icons.folder_zip, color: Colors.brown,
      source: PackageSource.alpineMain,
      downloadUrls: [],
      estimatedSize: '~200 KB', binaries: ['usr/bin/zip'],
    ),
    RegistryPackage(
      id: 'unzip', name: 'unzip', version: 'latest',
      description: 'Extract ZIP archives',
      category: 'Archive', icon: Icons.folder_zip, color: Colors.brown,
      source: PackageSource.alpineMain,
      downloadUrls: [],
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

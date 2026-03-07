import 'package:flutter/material.dart';

/// Package source types.
enum PackageSource {
  /// Our curated GitHub releases (Python, Go, Busybox)
  github,
  /// Termux glibc repo (glibc-compiled aarch64 packages)
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
  /// Download URL(s). Multiple URLs = extract all APKs to the same directory.
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
  static const _termux = 'https://packages-cf.termux.dev/apt/termux-glibc/pool/main';

  static const List<RegistryPackage> catalog = [
    // ── CLI Essentials ──
    RegistryPackage(
      id: 'jq', name: 'jq', version: '1.7.1',
      description: 'JSON processor — parse, filter, transform JSON',
      category: 'CLI Tools', icon: Icons.data_object, color: Colors.teal,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/j/jq/jq_1.7.1_aarch64.deb'],
      estimatedSize: '~300 KB', binaries: ['usr/bin/jq'],
    ),
    RegistryPackage(
      id: 'curl', name: 'curl', version: '8.14.1',
      description: 'HTTP client — download files, test APIs',
      category: 'CLI Tools', icon: Icons.cloud_download, color: Colors.blue,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/c/curl/curl_8.14.1_aarch64.deb'],
      estimatedSize: '~600 KB', binaries: ['usr/bin/curl'],
    ),
    RegistryPackage(
      id: 'wget', name: 'wget', version: '1.25.0',
      description: 'File downloader — recursive, resumable',
      category: 'CLI Tools', icon: Icons.download, color: Colors.indigo,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/w/wget/wget_1.25.0_aarch64.deb'],
      estimatedSize: '~500 KB', binaries: ['usr/bin/wget'],
    ),
    RegistryPackage(
      id: 'tree', name: 'tree', version: '2.2.1',
      description: 'Directory listing in tree format',
      category: 'CLI Tools', icon: Icons.account_tree, color: Colors.green,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/t/tree/tree_2.2.1_aarch64.deb'],
      estimatedSize: '~50 KB', binaries: ['usr/bin/tree'],
    ),
    RegistryPackage(
      id: 'less', name: 'less', version: '668',
      description: 'Pager — scroll through text files',
      category: 'CLI Tools', icon: Icons.description, color: Colors.blueGrey,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/l/less/less_668_aarch64.deb'],
      estimatedSize: '~150 KB', binaries: ['usr/bin/less'],
    ),

    // ── Modern CLI ──
    RegistryPackage(
      id: 'ripgrep', name: 'ripgrep', version: '14.1.1',
      description: 'Ultra-fast grep — regex search in files',
      category: 'Modern CLI', icon: Icons.search, color: Colors.purple,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/r/ripgrep/ripgrep_14.1.1_aarch64.deb'],
      estimatedSize: '~2 MB', binaries: ['usr/bin/rg'],
    ),
    RegistryPackage(
      id: 'fd', name: 'fd', version: '10.2.0',
      description: 'Modern find — fast file search',
      category: 'Modern CLI', icon: Icons.folder_open, color: Colors.deepPurple,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/f/fd/fd_10.2.0_aarch64.deb'],
      estimatedSize: '~1 MB', binaries: ['usr/bin/fd'],
    ),
    RegistryPackage(
      id: 'bat', name: 'bat', version: '0.24.0',
      description: 'Cat with syntax highlighting and git integration',
      category: 'Modern CLI', icon: Icons.code, color: Colors.amber,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/b/bat/bat_0.24.0_aarch64.deb'],
      estimatedSize: '~3 MB', binaries: ['usr/bin/bat'],
    ),
    RegistryPackage(
      id: 'fzf', name: 'fzf', version: '0.56.3',
      description: 'Fuzzy finder — interactive search/filter',
      category: 'Modern CLI', icon: Icons.filter_list, color: Colors.pink,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/f/fzf/fzf_0.56.3_aarch64.deb'],
      estimatedSize: '~1.5 MB', binaries: ['usr/bin/fzf'],
    ),
    RegistryPackage(
      id: 'eza', name: 'eza', version: '0.20.12',
      description: 'Modern ls replacement with colors, git status, icons',
      category: 'Modern CLI', icon: Icons.list, color: Colors.lime,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/e/eza/eza_0.20.12_aarch64.deb'],
      estimatedSize: '~800 KB', binaries: ['usr/bin/eza'],
    ),

    // ── Editors ──
    RegistryPackage(
      id: 'nano', name: 'nano', version: '8.2',
      description: 'Simple terminal text editor',
      category: 'Editors', icon: Icons.edit, color: Colors.grey,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/n/nano/nano_8.2_aarch64.deb'],
      estimatedSize: '~300 KB', binaries: ['usr/bin/nano'],
    ),
    RegistryPackage(
      id: 'neovim', name: 'Neovim', version: '0.10.4',
      description: 'Modern Vim — extensible editor',
      category: 'Editors', icon: Icons.terminal, color: Colors.green,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/n/neovim/neovim_0.10.4_aarch64.deb'],
      estimatedSize: '~6 MB', binaries: ['usr/bin/nvim'],
    ),

    // ── Data & Media ──
    RegistryPackage(
      id: 'sqlite', name: 'SQLite', version: '3.48.0',
      description: 'Embedded SQL database — query .db files',
      category: 'Data & Media', icon: Icons.storage, color: Colors.blue,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/s/sqlite/sqlite_3.48.0_aarch64.deb'],
      estimatedSize: '~800 KB', binaries: ['usr/bin/sqlite3'],
    ),
    RegistryPackage(
      id: 'ffmpeg', name: 'FFmpeg', version: '6.1.2',
      description: 'Audio/video processing — convert, trim, encode',
      category: 'Data & Media', icon: Icons.movie, color: Colors.red,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/f/ffmpeg/ffmpeg_6.1.2_aarch64.deb'],
      estimatedSize: '~20 MB', binaries: ['usr/bin/ffmpeg', 'usr/bin/ffprobe'],
      defaultInstall: true,
    ),
    RegistryPackage(
      id: 'yt-dlp', name: 'yt-dlp', version: '2025.03.31',
      description: 'Download videos from YouTube and 1000+ sites',
      category: 'Data & Media', icon: Icons.video_library, color: Colors.red,
      source: PackageSource.github,
      downloadUrls: ['https://github.com/yt-dlp/yt-dlp/releases/download/2026.03.03/yt-dlp_linux_aarch64'],
      estimatedSize: '~5 MB', binaries: ['usr/bin/yt-dlp'],
    ),

    // ── Network & Security ──
    RegistryPackage(
      id: 'openssh', name: 'OpenSSH', version: '9.9p2',
      description: 'SSH client — connect to remote servers',
      category: 'Network', icon: Icons.vpn_key, color: Colors.orange,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/o/openssh/openssh_9.9p2_aarch64.deb'],
      estimatedSize: '~2 MB', binaries: ['usr/bin/ssh', 'usr/bin/scp', 'usr/bin/ssh-keygen'],
    ),
    RegistryPackage(
      id: 'socat', name: 'socat', version: '1.8.0',
      description: 'Multipurpose relay — TCP/UDP tunnels, proxies',
      category: 'Network', icon: Icons.swap_horiz, color: Colors.cyan,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/s/socat/socat_1.8.0_aarch64.deb'],
      estimatedSize: '~200 KB', binaries: ['usr/bin/socat'],
    ),
    RegistryPackage(
      id: 'age', name: 'age', version: '1.2.1',
      description: 'Modern encryption tool — simple file encryption',
      category: 'Network', icon: Icons.lock, color: Colors.deepOrange,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/a/age/age_1.2.1_aarch64.deb'],
      estimatedSize: '~1.5 MB', binaries: ['usr/bin/age', 'usr/bin/age-keygen'],
    ),

    // ── System ──
    RegistryPackage(
      id: 'htop', name: 'htop', version: '3.3.0',
      description: 'Interactive process viewer',
      category: 'System', icon: Icons.monitor_heart, color: Colors.green,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/h/htop/htop_3.3.0_aarch64.deb'],
      estimatedSize: '~200 KB', binaries: ['usr/bin/htop'],
    ),
    RegistryPackage(
      id: 'tmux', name: 'tmux', version: '3.5a',
      description: 'Terminal multiplexer — split panes, detach sessions',
      category: 'System', icon: Icons.view_column, color: Colors.teal,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/t/tmux/tmux_3.5a_aarch64.deb'],
      estimatedSize: '~400 KB', binaries: ['usr/bin/tmux'],
    ),
    RegistryPackage(
      id: 'rsync', name: 'rsync', version: '3.4.1',
      description: 'Fast file sync — incremental copy/backup',
      category: 'System', icon: Icons.sync, color: Colors.indigo,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/r/rsync/rsync_3.4.1_aarch64.deb'],
      estimatedSize: '~350 KB', binaries: ['usr/bin/rsync'],
    ),

    // ── Archive ──
    RegistryPackage(
      id: 'zip', name: 'zip', version: '3.0',
      description: 'Create ZIP archives',
      category: 'Archive', icon: Icons.folder_zip, color: Colors.brown,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/z/zip/zip_3.0_aarch64.deb'],
      estimatedSize: '~150 KB', binaries: ['usr/bin/zip'],
    ),
    RegistryPackage(
      id: 'unzip', name: 'unzip', version: '6.0',
      description: 'Extract ZIP archives',
      category: 'Archive', icon: Icons.folder_zip, color: Colors.brown,
      source: PackageSource.termux,
      downloadUrls: ['$_termux/u/unzip/unzip_6.0_aarch64.deb'],
      estimatedSize: '~150 KB', binaries: ['usr/bin/unzip'],
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

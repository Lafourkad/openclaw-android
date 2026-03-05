class AppConstants {
  static const String appName = 'OpenClaw';
  static const String version = '1.8.2';
  static const String packageName = 'com.openclaw.android';

  /// Matches ANSI escape sequences (e.g. color codes in terminal output).
  static final ansiEscape = RegExp(r'\x1b\[[0-9;]*[a-zA-Z]');

  // Credits
  static const String authorName = 'Grug';
  static const String authorXUrl = 'https://x.com/0xGrug';
  static const String githubUrl = 'https://github.com/openclaw/openclaw';
  static const String license = 'MIT';

  // Based on openclaw-termux by Mithun Gowda B
  static const String upstreamName = 'Mithun Gowda B';
  static const String upstreamUrl = 'https://github.com/mithun50/openclaw-termux';

  // glibc runtime approach by Aidan Park
  static const String glibcCreditName = 'Aidan Park';
  static const String glibcCreditUrl = 'https://github.com/AidanPark/openclaw-android';

  static const String gatewayHost = '127.0.0.1';
  static const int gatewayPort = 18789;
  static const String gatewayUrl = 'http://$gatewayHost:$gatewayPort';

  // glibc runtime — downloaded during bootstrap
  static const String glibcDebUrl =
      'https://packages-cf.termux.dev/apt/termux-glibc/pool/stable/g/glibc/glibc_2.42_aarch64.deb';
  // GCC runtime libs (libstdc++.so.6, libgcc_s.so.1) — needed by Node.js
  static const String gccLibsDebUrl =
      'https://packages-cf.termux.dev/apt/termux-glibc/pool/stable/g/gcc-libs-glibc/gcc-libs-glibc_14.2.1-1_aarch64.deb';

  // Node.js binary tarball — downloaded directly by Flutter, extracted by Java.
  static const String nodeVersion = '22.14.0';
  static const String nodeBaseUrl =
      'https://nodejs.org/dist/v$nodeVersion/node-v$nodeVersion-linux-';

  static String getNodeTarballUrl(String arch) {
    switch (arch) {
      case 'aarch64':
        return '${nodeBaseUrl}arm64.tar.xz';
      case 'arm':
        return '${nodeBaseUrl}armv7l.tar.xz';
      case 'x86_64':
        return '${nodeBaseUrl}x64.tar.xz';
      default:
        return '${nodeBaseUrl}arm64.tar.xz';
    }
  }

  // Python standalone build (astral-sh/python-build-standalone)
  static const String pythonVersion = '3.13.12';
  static const String pythonUrl =
      'https://github.com/astral-sh/python-build-standalone/releases/download/20260303/cpython-3.13.12%2B20260303-aarch64-unknown-linux-gnu-install_only.tar.gz';

  // Go toolchain (official)
  static const String goVersion = '1.26.0';
  static const String goUrl =
      'https://go.dev/dl/go1.26.0.linux-arm64.tar.gz';

  // Busybox 1.37.0 static binary (Alpine musl, 1.1 MB)
  static const String busyboxUrl =
      'https://github.com/Lafourkad/openclaw-android/releases/download/tools-v1/busybox-aarch64.bin';

  // Git 2.52.0 + musl libs bundle (Alpine, 7 MB — includes HTTPS support)
  static const String gitBundleUrl =
      'https://github.com/Lafourkad/openclaw-android/releases/download/tools-v1/git-aarch64-musl.tar.gz';

  // Make (Termux glibc deb — depends only on glibc)
  static const String makeDebUrl =
      'https://packages-cf.termux.dev/apt/termux-glibc/pool/stable/m/make-glibc/make-glibc_4.4.1_aarch64.deb';

  static const int healthCheckIntervalMs = 5000;
  static const int maxAutoRestarts = 3;

  // Node constants
  static const int wsReconnectBaseMs = 350;
  static const double wsReconnectMultiplier = 1.7;
  static const int wsReconnectCapMs = 8000;
  static const String nodeRole = 'node';
  static const int pairingTimeoutMs = 300000;

  static const String channelName = 'com.openclaw.android/native';
  static const String eventChannelName = 'com.openclaw.android/gateway_logs';
}

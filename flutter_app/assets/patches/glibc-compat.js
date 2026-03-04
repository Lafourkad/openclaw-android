/**
 * glibc-compat.js - Compatibility shim for glibc Node.js on Android
 *
 * Loaded via NODE_OPTIONS="--require <path>/glibc-compat.js"
 *
 * Handles:
 * 1. process.execPath fix: ld.so → node binary (for child process spawning)
 * 2. child_process.spawn/spawnSync patching: route node through ld.so
 * 3. os.cpus() fallback: SELinux blocks /proc/stat on Android 8+
 * 4. os.networkInterfaces() safety: EACCES on some Android configs
 * 5. /bin/sh path shim: Android 7-8 lacks /bin/sh
 */

'use strict';

const os = require('os');
const fs = require('fs');
const path = require('path');
const child_process = require('child_process');

// ─── ld.so → node routing for child processes ───────────────
// GrapheneOS mounts /data/data/ noexec, so only ld.so (in nativeLibDir)
// can be execve'd. process.execPath points to ld.so.
// When openclaw forks workers: spawn(process.execPath, [nodeFlags, script])
// → ld.so receives Node.js flags it doesn't understand.
//
// Fix: set execPath to node binary, intercept spawn to route through ld.so.

const _ldSo = process.execPath; // ld.so path (before override)
const _home = process.env.HOME || '';
const _nodeBin = path.join(_home, 'node', 'bin', 'node');
const _glibcLib = path.join(_home, 'glibc', 'lib');

// Override process.execPath to point to the actual node binary
try {
  Object.defineProperty(process, 'execPath', {
    value: _nodeBin,
    writable: true,
    configurable: true,
  });
} catch {}

// Patch spawn/spawnSync: when spawning the node binary, prepend ld.so
const _origSpawn = child_process.spawn;
const _origSpawnSync = child_process.spawnSync;

function _wrapIfNode(command, args) {
  if (command === _nodeBin || command === _ldSo) {
    // Route: ld.so --library-path glibc/lib node [originalArgs...]
    const ldArgs = ['--library-path', _glibcLib, _nodeBin];
    if (Array.isArray(args) && args.length) ldArgs.push(...args);
    return { command: _ldSo, args: ldArgs };
  }
  return { command, args: Array.isArray(args) ? args : [] };
}

child_process.spawn = function spawn(command, args, options) {
  // Handle spawn(cmd, opts) without args array
  if (args && !Array.isArray(args) && typeof args === 'object') {
    options = args;
    args = [];
  }
  const w = _wrapIfNode(command, args);
  return _origSpawn.call(child_process, w.command, w.args, options);
};

child_process.spawnSync = function spawnSync(command, args, options) {
  if (args && !Array.isArray(args) && typeof args === 'object') {
    options = args;
    args = [];
  }
  const w = _wrapIfNode(command, args);
  return _origSpawnSync.call(child_process, w.command, w.args, options);
};


// ─── os.cpus() fallback ─────────────────────────────────────
// Android 8+ blocks /proc/stat via SELinux → libuv returns empty array.

const _originalCpus = os.cpus;

os.cpus = function cpus() {
  const result = _originalCpus.call(os);
  if (result.length > 0) return result;
  return [{ model: 'unknown', speed: 0, times: { user: 0, nice: 0, sys: 0, idle: 0, irq: 0 } }];
};


// ─── os.networkInterfaces() safety ──────────────────────────

const _originalNetworkInterfaces = os.networkInterfaces;

os.networkInterfaces = function networkInterfaces() {
  try {
    return _originalNetworkInterfaces.call(os);
  } catch {
    return {
      lo: [{
        address: '127.0.0.1', netmask: '255.0.0.0', family: 'IPv4',
        mac: '00:00:00:00:00:00', internal: true, cidr: '127.0.0.1/8',
      }],
    };
  }
};


// ─── /bin/sh path shim ──────────────────────────────────────
// Android 9+ has /bin → /system/bin symlink. Android 7-8 lacks /bin/sh.
// Node.js child_process uses /bin/sh as default shell on Linux.

if (!fs.existsSync('/bin/sh')) {
  const _systemSh = '/system/bin/sh';
  if (fs.existsSync(_systemSh)) {
    const _origExec = child_process.exec;
    const _origExecSync = child_process.execSync;

    child_process.exec = function exec(command, options, callback) {
      if (typeof options === 'function') { callback = options; options = {}; }
      options = options || {};
      if (!options.shell) options.shell = _systemSh;
      return _origExec.call(child_process, command, options, callback);
    };

    child_process.execSync = function execSync(command, options) {
      options = options || {};
      if (!options.shell) options.shell = _systemSh;
      return _origExecSync.call(child_process, command, options);
    };
  }
}

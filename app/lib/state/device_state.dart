/// What machine is this? Currently one number: total RAM, so the install
/// browser can turn abstract requirements ("needs ~9 GB") into a personal
/// verdict ("fits" / "tight" / "too big for this device").
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Total physical memory in GB, or null when it can't be determined.
final deviceRamGbProvider = FutureProvider<double?>((_) async {
  try {
    if (Platform.isWindows) {
      final res = await Process.run('powershell', [
        '-NoLogo',
        '-NonInteractive',
        '-Command',
        '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory',
      ]).timeout(const Duration(seconds: 8));
      final bytes = double.tryParse((res.stdout as String).trim());
      if (bytes != null && bytes > 0) return bytes / (1024 * 1024 * 1024);
    } else {
      // Android and Linux both expose /proc/meminfo: "MemTotal: 16299 kB".
      final meminfo = await File('/proc/meminfo').readAsString();
      final m = RegExp(r'MemTotal:\s*(\d+)\s*kB').firstMatch(meminfo);
      if (m != null) return int.parse(m.group(1)!) / (1024 * 1024);
    }
  } catch (_) {}
  return null;
});

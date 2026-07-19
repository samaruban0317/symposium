/// What machine is this? Two numbers: total RAM and GPU VRAM.
///
/// The distinction matters more than either number alone. A model that fits
/// in VRAM runs entirely on the GPU — fast. One that fits in RAM but not
/// VRAM still *runs*, but Ollama splits it and the CPU becomes the
/// bottleneck (a 12b on a 6 GB card crawls at a few tok/s while the GPU
/// idles). The install browser uses both to say fast / slow / won't fit.
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

/// Dedicated GPU memory in GB (largest GPU), or null when undetectable.
/// nvidia-smi covers the cards people actually run LLMs on; anything else
/// just falls back to RAM-only verdicts.
final deviceVramGbProvider = FutureProvider<double?>((_) async {
  if (Platform.isAndroid || Platform.isIOS) return null;
  try {
    final res = await Process.run(
      'nvidia-smi',
      ['--query-gpu=memory.total', '--format=csv,noheader,nounits'],
    ).timeout(const Duration(seconds: 6));
    final values = [
      for (final line in (res.stdout as String).split('\n'))
        double.tryParse(line.trim()),
    ].nonNulls;
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a > b ? a : b) / 1024; // MB → GB
  } catch (_) {
    return null;
  }
});

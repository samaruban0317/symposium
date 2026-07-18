/// The ONE place that knows where Symposium keeps files on disk.
/// Everything that persists (saved sources, API keys, personas) goes through
/// [dataFile] so a storage-strategy change is a one-file edit.
///
/// Keys are stored as plain local files readable only by this OS user — the
/// same trade-off most desktop tools make (git credentials, kube configs).
/// If that ever feels too loose, swap this file's internals for OS keychains;
/// callers won't change.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

Directory? _dir; // resolved once; path_provider hits a platform channel

Future<File> dataFile(String name) async {
  final dir = _dir ??= await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return File('${dir.path}${Platform.pathSeparator}$name');
}

/// Read a JSON-ish text file, or null if it doesn't exist yet.
Future<String?> readData(String name) async {
  final f = await dataFile(name);
  return await f.exists() ? f.readAsString() : null;
}

Future<void> writeData(String name, String contents) async {
  final f = await dataFile(name);
  await f.writeAsString(contents, flush: true);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:symposium/models/catalog.dart';
import 'package:symposium/state/catalog_state.dart';

// A trimmed slice of ollama.com/library markup — the three markers the
// parser relies on (library link, description paragraph, blue size chips).
const _sampleHtml = '''
<a href="/library/llama3.1" class="group w-full space-y-5">
  <p class="max-w-lg break-words text-neutral-800 text-md">Llama 3.1 is a new state-of-the-art model from Meta.</p>
  <span class="... text-indigo-600 sm:text-[13px]">tools</span>
  <span class="... text-blue-600 sm:text-[13px]">8b</span>
  <span class="... text-blue-600 sm:text-[13px]">70b</span>
  <span >117.3M</span>
  <span class="hidden sm:flex">&nbsp;Pulls</span>
</a>
<a href="/library/moondream" class="group w-full space-y-5">
  <p class="max-w-lg break-words text-neutral-800 text-md">A tiny vision model &amp; friend.</p>
  <span class="... text-blue-600 sm:text-[13px]">1.8b</span>
</a>
''';

void main() {
  test('parses names, descriptions, sizes and pulls from library HTML', () {
    final entries = parseLibraryHtml(_sampleHtml);
    expect(entries, hasLength(2));

    expect(entries[0].name, 'llama3.1');
    expect(entries[0].description, contains('state-of-the-art'));
    expect(entries[0].sizes, ['8b', '70b']);
    expect(entries[0].capabilities, ['tools']);
    expect(entries[0].pulls, '117.3M');
    expect(entries[0].tagFor('8b'), 'llama3.1:8b');

    expect(entries[1].name, 'moondream');
    expect(entries[1].description, 'A tiny vision model & friend.');
    expect(entries[1].sizes, ['1.8b']);
    expect(entries[1].pulls, isNull);
  });

  test('hardware estimates scale with parameter count', () {
    final small = ModelReqs.forSize('0.5b')!;
    expect(small.downloadGB, closeTo(0.325, 0.01));
    expect(small.ramGB, lessThan(3));

    final medium = ModelReqs.forSize('7b')!;
    expect(medium.ramGB, closeTo(7.05, 0.1));

    final moe = ModelReqs.forSize('8x7b')!;
    expect(moe.downloadGB, closeTo(56 * 0.65, 0.1));

    final millions = ModelReqs.forSize('135m')!;
    expect(millions.downloadLabel, endsWith('MB'));

    expect(ModelReqs.forSize('latest'), isNull);
    expect(ModelReqs.forSize('instruct'), isNull);
  });

  test('duplicate links and nested paths are ignored', () {
    final entries = parseLibraryHtml(
        '<a href="/library/x">'
        '<a href="/library/x">'
        '<a href="/library/x/tags">');
    expect(entries, hasLength(1));
    expect(entries[0].name, 'x');
  });
}

// Security regression tests for the hardening pass that followed the
// Strix adversarial audit:
//   * set-cookie header splitting (comma-in-value corruption)
//   * CBZ filename sanitization (path traversal from source titles)
//   * backup zip-bomb guard (declared-size pre-scan)
//   * download size caps (Content-Length refusal + streamed cap)

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_reader/services/backup.dart';
import 'package:lumina_reader/services/download_manager/m_downloader.dart';
import 'package:lumina_reader/services/http/m_client.dart';

void main() {
  group('set-cookie splitting (MCookieManager.splitSetCookieHeader)', () {
    test('cookies with commas in Expires survive the split', () {
      const header =
          'session=abc123; Path=/; Expires=Wed, 09 Jun 2027 10:18:14 GMT, '
          'theme=dark; Path=/, cf_clearance=xyz; HttpOnly';
      final parts = MCookieManager.splitSetCookieHeader(header);
      // The Expires date contains ", 09 Jun..." which must NOT split.
      expect(parts.length, 3, reason: 'got: $parts');
      expect(parts[0], contains('Expires=Wed, 09 Jun 2027 10:18:14 GMT'));
      expect(parts[0].startsWith('session=abc123'), isTrue);
      expect(parts[1].trim().startsWith('theme=dark'), isTrue);
      expect(parts[2].trim().startsWith('cf_clearance=xyz'), isTrue);
    });

    test('single cookie without commas is returned as-is', () {
      const header = 'a=1; Path=/';
      expect(MCookieManager.splitSetCookieHeader(header), [header]);
    });
  });

  group('CBZ filename sanitization (sanitizeFileName)', () {
    test('path traversal attempts become safe names', () {
      expect(
        sanitizeFileName('../../../../data/data/escape'),
        isNot(contains('/')),
      );
      expect(sanitizeFileName('..\\..\\windows'), isNot(contains(r'\')));
      expect(sanitizeFileName('  .hidden '), isNot(startsWith('.')));
      expect(sanitizeFileName(''), 'untitled');
      expect(sanitizeFileName('Ch. 5: "Queen" <Part 2>?'),
          isNot(contains('?')));
      // A normal title keeps its readable shape.
      expect(
          sanitizeFileName('Chapter 12 - The Fall'), 'Chapter 12 - The Fall');
    });
  });

  group('backup zip-bomb guard (BackupService.validateZipSizes)', () {
    test('rejects archives declaring oversized entries', () {
      final archive = Archive()
        ..addFile(ArchiveFile('backup.json', 2, utf8.encode('{}')));
      final bytes = ZipEncoder().encode(archive)!;
      // Corrupt the declared uncompressed size in the central directory
      // (field at CDH offset 24) to ~1 GiB without inflating anything.
      final corrupted = bytes.toList();
      // Locate the central directory header signature 0x02014b50.
      var cdh = -1;
      for (var i = 0; i + 4 <= corrupted.length; i++) {
        if (corrupted[i] == 0x50 &&
            corrupted[i + 1] == 0x4b &&
            corrupted[i + 2] == 0x01 &&
            corrupted[i + 3] == 0x02) {
          cdh = i;
          break;
        }
      }
      expect(cdh, greaterThan(0));
      // Declare a 300 MiB uncompressed size (over the 256 MiB entry cap):
      // 300 * 1024 * 1024 = 0x12C00000 little-endian.
      const declared = 300 * 1024 * 1024;
      corrupted[cdh + 24] = declared & 0xFF;
      corrupted[cdh + 25] = (declared >> 8) & 0xFF;
      corrupted[cdh + 26] = (declared >> 16) & 0xFF;
      corrupted[cdh + 27] = (declared >> 24) & 0xFF;
      expect(
        () => BackupService.validateZipSizes(corrupted),
        throwsA(isA<BackupException>()),
      );
    });

    test('rejects ZIP64 sentinel sizes', () {
      final archive = Archive()
        ..addFile(ArchiveFile('backup.json', 2, utf8.encode('{}')));
      final bytes = ZipEncoder().encode(archive)!.toList();
      var cdh = -1;
      for (var i = 0; i + 4 <= bytes.length; i++) {
        if (bytes[i] == 0x50 &&
            bytes[i + 1] == 0x4b &&
            bytes[i + 2] == 0x01 &&
            bytes[i + 3] == 0x02) {
          cdh = i;
          break;
        }
      }
      for (var o = 24; o < 28; o++) {
        bytes[cdh + o] = 0xFF;
      }
      expect(
        () => BackupService.validateZipSizes(bytes),
        throwsA(isA<BackupException>()),
      );
    });

    test('accepts a normal backup zip', () {
      final archive = Archive()
        ..addFile(
            ArchiveFile('backup.json', 16, utf8.encode('{"version":1}')));
      final bytes = ZipEncoder().encode(archive)!;
      // Must not throw.
      BackupService.validateZipSizes(bytes);
    });
  });

  group('download size caps (MDownloader.readCapped)', () {
    test('refuses Content-Length above the per-file cap', () async {
      await expectLater(
        MDownloader.readCapped(
          Stream.value(List.filled(4, 1)),
          'http://evil/big.jpg',
          declaredLength: '${kMaxFileBytes + 1}',
        ),
        throwsA(isA<HttpException>()),
      );
    });

    test('caps a lying endless stream mid-flight', () async {
      final chunk = List<int>.filled(16 * 1024 * 1024, 1); // 16 MiB chunks
      Stream<List<int>> endless() async* {
        while (true) {
          yield chunk;
          await Future<void>.delayed(Duration.zero);
        }
      }

      final t0 = DateTime.now();
      await expectLater(
        MDownloader.readCapped(endless(), 'http://evil/liar.jpg'),
        throwsA(isA<HttpException>()),
      );
      // The cap must trip quickly (96 MiB cap / 16 MiB chunks = 7 chunks),
      // proving we never buffered an unbounded body.
      expect(DateTime.now().difference(t0).inSeconds, lessThan(30));
    });

    test('passes through a normal small body', () async {
      final body = await MDownloader.readCapped(
        Stream.value(List.filled(128, 7)),
        'http://ok/page.jpg',
        declaredLength: '128',
      );
      expect(body.length, 128);
    });
  });
}

// Copyright 2024 Lumina Reader Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License").

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_reader/services/repo_index_parser.dart';

/// Tiny protobuf encoder for building fixtures.
class PbEncoder {
  final BytesBuilder _b = BytesBuilder();

  void varintField(int field, int value) {
    _tag(field, 0);
    var v = value;
    while (true) {
      final byte = v & 0x7f;
      v >>= 7;
      _b.addByte(v == 0 ? byte : byte | 0x80);
      if (v == 0) break;
    }
  }

  void stringField(int field, String value) {
    lengthField(field, utf8.encode(value));
  }

  /// Correct length-delimited writer.
  void lengthField(int field, List<int> bytes) {
    _tag(field, 2);
    final len = bytes.length;
    var v = len;
    while (true) {
      final byte = v & 0x7f;
      v >>= 7;
      _b.addByte(v == 0 ? byte : byte | 0x80);
      if (v == 0) break;
    }
    _b.add(bytes);
  }

  void messageField(int field, void Function(PbEncoder) build) {
    final sub = PbEncoder();
    build(sub);
    lengthField(field, sub.bytes());
  }

  void _tag(int field, int wireType) {
    final tag = (field << 3) | wireType;
    var v = tag;
    while (true) {
      final byte = v & 0x7f;
      v >>= 7;
      _b.addByte(v == 0 ? byte : byte | 0x80);
      if (v == 0) break;
    }
  }

  Uint8List bytes() => _b.toBytes();
}

void main() {
  group('parseRepoIndex · protobuf', () {
    test('parses the MANGA variant (sources = field 8)', () {
      final pb = PbEncoder()
        ..stringField(1, 'Keiyoushi')
        ..stringField(2, 'KEI')
        ..messageField(101, (list) {
          list.messageField(1, (ext) {
            ext.stringField(1, 'AHottie');
            ext.stringField(2, 'eu.kanade.tachiyomi.extension.all.ahottie');
            ext.messageField(3, (res) {
              res.stringField(1, 'https://example.com/apk.apk');
              res.stringField(2, 'https://example.com/icon.png');
            });
            ext.stringField(4, '1.6');
            ext.varintField(5, 106004);
            ext.stringField(6, '1.6.4');
            ext.varintField(7, 3); // NSFW
            ext.messageField(8, (src) {
              src.varintField(1, 6289731484943315811);
              src.stringField(2, 'AHottie');
              src.stringField(3, 'all');
              src.stringField(4, 'https://ahottie.top');
              src.stringField(5, 'https://mirror.top');
            });
          });
        });
      final res = parseRepoIndex(pb.bytes(), 'https://x/repo/index.pb');
      expect(res.isRedirect, isFalse);
      final index = res.index!;
      expect(index.format, RepoFormat.protobuf);
      expect(index.storeName, 'Keiyoushi');
      expect(index.extensions, hasLength(1));
      final e = index.extensions.first;
      expect(e.name, 'AHottie');
      expect(e.isApk, isTrue);
      expect(e.isAnime, isFalse, reason: 'manga pkg');
      expect(e.apkUrl, 'https://example.com/apk.apk');
      expect(e.versionCode, 106004);
      expect(e.versionName, '1.6.4');
      expect(e.isNsfw, isTrue);
      expect(e.isTorrent, isFalse);
      expect(e.sources, hasLength(1));
      expect(e.sources.first.id, 6289731484943315811);
      expect(e.sources.first.baseUrl, 'https://ahottie.top');
    });

    test('parses the ANIME variant (isTorrent = 8, sources = 9)', () {
      final pb = PbEncoder()..messageField(101, (list) {
        list.messageField(1, (ext) {
          ext.stringField(1, 'Stremio');
          ext.stringField(2, 'eu.kanade.tachiyomi.animeextension.all.stremio');
          ext.messageField(3, (res) {
            res.stringField(1, 'https://example.com/stremio.apk');
          });
          ext.stringField(4, '17');
          ext.varintField(5, 17002);
          ext.stringField(6, '17.2');
          ext.varintField(7, 2); // MIXED
          ext.varintField(8, 1); // isTorrent = true (ANIME variant)
          ext.messageField(9, (src) {
            src.varintField(1, 8425771932667600381);
            src.stringField(2, 'Stremio');
            src.stringField(3, 'all');
          });
        });
      });
      final index = parseRepoIndex(pb.bytes(), 'https://x/index.pb').index!;
      final e = index.extensions.single;
      expect(e.isAnime, isTrue);
      expect(e.isTorrent, isTrue);
      expect(e.isNsfw, isTrue, reason: 'contentWarning MIXED >= 2');
      expect(e.sources.single.id, 8425771932667600381);
      expect(e.sources.single.name, 'Stremio');
    });

    test('gunzips gzip-compressed index.pb', () {
      final pb = PbEncoder()
        ..stringField(1, 'GzRepo')
        ..messageField(101, (list) {
          list.messageField(1, (ext) {
            ext.stringField(1, 'Solo');
            ext.stringField(2, 'eu.kanade.tachiyomi.extension.all.solo');
            ext.messageField(8, (src) => src.stringField(2, 'Solo'));
          });
        });
      final gz = Uint8List.fromList(gzip.encode(pb.bytes()));
      expect(gz[0], 0x1f, reason: 'gzip magic');
      final index = parseRepoIndex(gz, 'https://x/index.pb').index!;
      expect(index.storeName, 'GzRepo');
      expect(index.extensions.single.name, 'Solo');
    });

    test('skips unknown fields (e.g. Resources.jarUrl = 501)', () {
      final pb = PbEncoder()..messageField(101, (list) {
        list.messageField(1, (ext) {
          ext.stringField(1, 'Unknown501');
          ext.stringField(2, 'eu.kanade.tachiyomi.extension.all.u5');
          // Bogus high field numbers across wire types.
          ext.varintField(501, 7);
          ext.stringField(502, 'ignored');
          ext.messageField(8, (src) => src.stringField(2, 'U5'));
        });
      });
      final index = parseRepoIndex(pb.bytes(), 'https://x/index.pb').index!;
      expect(index.extensions.single.name, 'Unknown501');
    });

    test('extensionListUrl (field 102) surfaces as a redirect', () {
      final pb = PbEncoder()..stringField(102, 'https://x/ext.pb');
      final res = parseRepoIndex(pb.bytes(), 'https://x/index.pb');
      expect(res.isRedirect, isTrue);
      expect(res.redirectUrl, 'https://x/ext.pb');
    });
  });

  group('parseRepoIndex · JSON', () {
    test('Mangayomi array format', () {
      const body = '''[
        {"name":"Asura Scans","id":123,"baseUrl":"https://asura.gg","lang":"en",
         "typeSource":"single","iconUrl":"i","dateFormat":"","dateFormatLocale":"",
         "isNsfw":false,"hasCloudflare":true,
         "sourceCodeUrl":"https://eJ/main/javascript/manga/src/en/asura.js",
         "apiUrl":"","version":"0.0.1","isManga":true,"itemType":0,
         "isFullData":false,"appMinVerReq":"0.5.0","additionalParams":"",
         "sourceCodeLanguage":1,"notes":""}
      ]''';
      final index = parseRepoIndex(
              Uint8List.fromList(utf8.encode(body)), 'https://x/index.json')
          .index!;
      expect(index.format, RepoFormat.mangayomiJson);
      final e = index.extensions.single;
      expect(e.name, 'Asura Scans');
      expect(e.isAnime, isFalse);
      expect(e.mangayomiEntry, isNotNull);
      expect(e.mangayomiEntry!['typeSource'], 'single');
      expect(e.mangayomiEntry!['sourceCodeLanguage'], 1);
    });

    test('Mangayomi anime entries via itemType=1', () {
      const body =
          '[{"name":"AllAnime","id":9,"baseUrl":"https://allanime.to","lang":"en",'
          '"typeSource":"single","itemType":1,"isManga":false,'
          '"sourceCodeUrl":"https://eJ/allanime.js","sourceCodeLanguage":1,'
          '"version":"0.0.1"}]';
      final index =
          parseRepoIndex(utf8.encode(body), 'https://x/anime_index.json').index!;
      final e = index.extensions.single;
      expect(e.isAnime, isTrue);
      expect(e.isNovel, isFalse);
    });

    test('legacy Tachiyomi/Aniyomi array format', () {
      const body = '''[
        {"name":"Aniyomi: Jellyfin",
         "pkg":"eu.kanade.tachiyomi.animeextension.all.jellyfin",
         "apk":"aniyomi-all.jellyfin-v14.17.apk","lang":"all","code":17,
         "version":"14.17","nsfw":0,
         "sources":[
           {"name":"Jellyfin (1)","lang":"all","id":"1100359934660540567","baseUrl":""},
           {"name":"Jellyfin (2)","lang":"all","id":"5716273076275542763","baseUrl":""}
         ]}
      ]''';
      final index = parseRepoIndex(
              Uint8List.fromList(utf8.encode(body)),
              'https://x/repo/index.min.json')
          .index!;
      expect(index.format, RepoFormat.tachiyomiLegacyJson);
      final e = index.extensions.single;
      expect(e.isAnime, isTrue, reason: 'pkg contains animeextension');
      expect(
          e.apkUrl,
          'https://x/repo/apk/aniyomi-all.jellyfin-v14.17.apk',
          reason: 'legacy APK URL constructed from the index base');
      expect(e.iconUrl,
          'https://x/repo/icon/eu.kanade.tachiyomi.animeextension.all.jellyfin.png');
      expect(e.versionCode, 17);
      expect(e.versionName, '14.17');
      expect(e.sources, hasLength(2));
      expect(e.sources.first.id, 1100359934660540567);
    });

    test('repo.json surfaces index_v2 as redirect', () {
      const body =
          '{"index_v2":"https://github.com/keiyoushi/extensions/raw/repo/index.pb",'
          '"meta":{"name":"Keiyoushi"}}';
      final res =
          parseRepoIndex(utf8.encode(body), 'https://x/repo/repo.json');
      expect(res.isRedirect, isTrue);
      expect(
          res.redirectUrl, 'https://github.com/keiyoushi/extensions/raw/repo/index.pb');
    });

    test('v2 JSON store format (camelCase, string int64s)', () {
      const body = '''{
        "name": "Secozzi", "badge": "SECO",
        "extensions": [{
          "name": "Stremio",
          "packageName": "eu.kanade.tachiyomi.animeextension.all.stremio",
          "resources": {"apkUrl": "https://x/s.apk", "iconUrl": "https://x/i.png"},
          "extensionLib": "17", "versionCode": "17002", "versionName": "17.2",
          "contentWarning": "CONTENT_WARNING_MIXED", "isTorrent": true,
          "sources": [{"id": "8425771932667600381", "name": "Stremio",
                       "language": "all", "homeUrl": "https://stremio.com"}]
        }]
      }''';
      final index =
          parseRepoIndex(utf8.encode(body), 'https://x/index.json').index!;
      expect(index.format, RepoFormat.v2Json);
      expect(index.storeName, 'Secozzi');
      final e = index.extensions.single;
      expect(e.isAnime, isTrue);
      expect(e.isTorrent, isTrue);
      expect(e.isNsfw, isTrue, reason: 'MIXED counts as NSFW');
      expect(e.versionCode, 17002);
      expect(e.sources.single.id, 8425771932667600381);
      expect(e.apkUrl, 'https://x/s.apk');
    });
  });

  group('URL helpers', () {
    test('repoBaseFromIndexUrl strips the file name', () {
      expect(repoBaseFromIndexUrl('https://x.com/repo/index.min.json'),
          'https://x.com/repo');
      expect(repoBaseFromIndexUrl('https://x.com/repo/index.pb'),
          'https://x.com/repo');
      expect(repoBaseFromIndexUrl('https://x.com/repo'),
          'https://x.com/repo');
    });

    test('legacyApkUrls constructs apk/icon URLs', () {
      final urls = legacyApkUrls(
        indexUrl: 'https://x.com/repo/index.min.json',
        apkFileName: 'aniyomi-all.jellyfin-v14.17.apk',
        pkg: 'eu.kanade.tachiyomi.animeextension.all.jellyfin',
      );
      expect(urls.apkUrl,
          'https://x.com/repo/apk/aniyomi-all.jellyfin-v14.17.apk');
      expect(
          urls.iconUrl,
          'https://x.com/repo/icon/'
          'eu.kanade.tachiyomi.animeextension.all.jellyfin.png');
    });
  });
}

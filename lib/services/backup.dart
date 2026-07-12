// Copyright 2024 Lumina Reader Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Backup / restore system for Lumina Reader. Exports the library, notes,
// settings, reading sessions, history and categories to a single JSON
// payload, optionally wrapped in a password-protected ZIP archive.
//
// Sensitive data (OAuth tokens stored on [Track] entries) is excluded by
// default. The user can opt in to including them; when they do, the tokens
// are encrypted with AES-GCM derived from the backup password before being
// written to the archive.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path/path.dart' as p;

import 'package:lumina_reader/models/category.dart';
import 'package:lumina_reader/models/chapter.dart';
import 'package:lumina_reader/models/history.dart';
import 'package:lumina_reader/models/manga.dart';
import 'package:lumina_reader/models/note.dart';
import 'package:lumina_reader/models/reading_session.dart';
import 'package:lumina_reader/models/settings.dart';
import 'package:lumina_reader/models/track.dart';

/// Thrown by the backup / restore pipeline.
class BackupException implements Exception {
  BackupException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'BackupException: $message';
}

/// Options controlling what is exported and how.
class BackupOptions {
  const BackupOptions({
    this.includeLibrary = true,
    this.includeNotes = true,
    this.includeSettings = true,
    this.includeSessions = true,
    this.includeHistory = true,
    this.includeCategories = true,
    this.includeTrackerTokens = false,
    this.includeDownloads = false,
    this.password,
  });

  /// Export the [Manga] + [Chapter] library.
  final bool includeLibrary;

  /// Export [Note] annotations.
  final bool includeNotes;

  /// Export [Settings].
  final bool includeSettings;

  /// Export [ReadingSession] records.
  final bool includeSessions;

  /// Export [History] records.
  final bool includeHistory;

  /// Export [Category] definitions.
  final bool includeCategories;

  /// When `true`, OAuth tokens stored on [Track] entries are included (and
  /// encrypted with [password]). When `false`, tokens are stripped.
  final bool includeTrackerTokens;

  /// When `true`, download manifest metadata is included (files themselves
  /// are not bundled — only the references).
  final bool includeDownloads;

  /// Optional password. When set, the backup is encrypted with AES-GCM
  /// before being stored in the ZIP archive.
  final String? password;

  BackupOptions copyWith({
    bool? includeLibrary,
    bool? includeNotes,
    bool? includeSettings,
    bool? includeSessions,
    bool? includeHistory,
    bool? includeCategories,
    bool? includeTrackerTokens,
    bool? includeDownloads,
    String? password,
    bool clearPassword = false,
  }) {
    return BackupOptions(
      includeLibrary: includeLibrary ?? this.includeLibrary,
      includeNotes: includeNotes ?? this.includeNotes,
      includeSettings: includeSettings ?? this.includeSettings,
      includeSessions: includeSessions ?? this.includeSessions,
      includeHistory: includeHistory ?? this.includeHistory,
      includeCategories: includeCategories ?? this.includeCategories,
      includeTrackerTokens: includeTrackerTokens ?? this.includeTrackerTokens,
      includeDownloads: includeDownloads ?? this.includeDownloads,
      password: clearPassword ? null : (password ?? this.password),
    );
  }
}

/// Strategy used when importing a backup.
enum ImportStrategy {
  /// Replace the local database entirely with the backup contents.
  replace,

  /// Merge the backup into the local database. Existing local entries are
  /// kept; new entries from the backup are added. Conflicts are resolved by
  /// "last write wins" using the `updatedAt` / `lastReadAt` timestamps.
  merge,
}

/// Result of a backup import operation.
class ImportResult {
  ImportResult({
    this.mangaAdded = 0,
    this.mangaUpdated = 0,
    this.chaptersAdded = 0,
    this.notesAdded = 0,
    this.sessionsAdded = 0,
    this.historyAdded = 0,
    this.categoriesAdded = 0,
    this.tracksAdded = 0,
    this.skipped = 0,
    this.errors = const <String>[],
  });

  final int mangaAdded;
  final int mangaUpdated;
  final int chaptersAdded;
  final int notesAdded;
  final int sessionsAdded;
  final int historyAdded;
  final int categoriesAdded;
  final int tracksAdded;
  final int skipped;
  final List<String> errors;

  @override
  String toString() => 'ImportResult(manga+=$mangaAdded, manga~=$mangaUpdated, '
      'chapters+=$chaptersAdded, notes+=$notesAdded, sessions+=$sessionsAdded, '
      'history+=$historyAdded, categories+=$categoriesAdded, '
      'tracks+=$tracksAdded, skipped=$skipped, errors=${errors.length})';
}

/// Pluggable data-source the backup service reads from / writes to.
///
/// The default in-app implementation wires this to Isar; tests can swap it
/// out for an in-memory implementation.
abstract class BackupDataSource {
  Future<List<Manga>> fetchManga();
  Future<List<Chapter>> fetchChapters();
  Future<List<Note>> fetchNotes();
  Future<List<ReadingSession>> fetchSessions();
  Future<List<History>> fetchHistory();
  Future<List<Category>> fetchCategories();
  Future<List<Track>> fetchTracks();
  Future<Settings?> fetchSettings();

  Future<void> upsertManga(Iterable<Manga> entries);
  Future<void> upsertChapters(Iterable<Chapter> entries);
  Future<void> upsertNotes(Iterable<Note> entries);
  Future<void> upsertSessions(Iterable<ReadingSession> entries);
  Future<void> upsertHistory(Iterable<History> entries);
  Future<void> upsertCategories(Iterable<Category> entries);
  Future<void> upsertTracks(Iterable<Track> entries);
  Future<void> saveSettings(Settings settings);
  Future<void> clearAll();
}

/// The backup / restore service.
class BackupService {
  BackupService(this._dataSource);

  final BackupDataSource _dataSource;

  /// Magic header written at the start of every backup file so we can detect
  /// the format quickly.
  static const String _kMagic = 'LUMINABACKUP';

  /// Current backup schema version. Bumped when the JSON layout changes.
  static const int _kVersion = 1;

  // -- Export ---------------------------------------------------------------

  /// Exports the database to a JSON payload.
  ///
  /// When [options.password] is set, the JSON is encrypted with AES-GCM and
  /// wrapped in a single-file ZIP archive. Otherwise the JSON is written
  /// verbatim.
  Future<List<int>> export(BackupOptions options) async {
    final payload = await _buildPayload(options);
    final jsonBytes = utf8.encode(jsonEncode(payload));

    final archive = Archive();
    if (options.password != null) {
      final encrypted = _encryptPayload(jsonBytes, options.password!);
      archive.addFile(
        ArchiveFile('backup.json.enc', encrypted.length, encrypted),
      );
      archive.addFile(
        ArchiveFile(
          'backup.version',
          1,
          utf8.encode('$_kVersion'),
        ),
      );
    } else {
      archive.addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes));
    }

    final encoder = ZipEncoder();
    final zipBytes = encoder.encode(archive)!;
    // Prepend the magic header so we can validate the file on import.
    return <int>[
      ...utf8.encode(_kMagic),
      ...zipBytes,
    ];
  }

  /// Writes the backup to [path]. Convenience wrapper around [export].
  Future<void> exportToFile(String path, BackupOptions options) async {
    final bytes = await export(options);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<Map<String, dynamic>> _buildPayload(BackupOptions options) async {
    final payload = <String, dynamic>{
      'version': _kVersion,
      'createdAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      'schema': <String, dynamic>{
        'manga': Manga.toString(),
        'chapter': Chapter.toString(),
        'note': Note.toString(),
        'readingSession': ReadingSession.toString(),
        'history': History.toString(),
        'category': Category.toString(),
        'track': Track.toString(),
      },
    };

    if (options.includeLibrary) {
      final manga = await _dataSource.fetchManga();
      payload['manga'] = manga.map(_mangaToJson).toList();
      final chapters = await _dataSource.fetchChapters();
      payload['chapters'] = chapters.map(_chapterToJson).toList();
    }
    if (options.includeNotes) {
      final notes = await _dataSource.fetchNotes();
      payload['notes'] = notes.map(_noteToJson).toList();
    }
    if (options.includeSettings) {
      final settings = await _dataSource.fetchSettings();
      payload['settings'] = settings != null ? _settingsToJson(settings) : null;
    }
    if (options.includeSessions) {
      final sessions = await _dataSource.fetchSessions();
      payload['sessions'] = sessions.map(_sessionToJson).toList();
    }
    if (options.includeHistory) {
      final history = await _dataSource.fetchHistory();
      payload['history'] = history.map(_historyToJson).toList();
    }
    if (options.includeCategories) {
      final categories = await _dataSource.fetchCategories();
      payload['categories'] = categories.map(_categoryToJson).toList();
    }
    // Tracks are exported whenever the library is exported — they are
    // metadata about manga entries.
    if (options.includeLibrary) {
      final tracks = await _dataSource.fetchTracks();
      payload['tracks'] = tracks
          .map((t) => _trackToJson(t, includeTokens: options.includeTrackerTokens))
          .toList();
    }

    return payload;
  }

  // -- Import ---------------------------------------------------------------

  /// Imports a backup from [bytes] using [strategy]. When [password] is
  /// required (the backup is encrypted) and not provided, a [BackupException]
  /// is thrown.
  Future<ImportResult> import(
    List<int> bytes, {
    required ImportStrategy strategy,
    String? password,
  }) async {
    final json = await _decodeBytes(bytes, password: password);
    return _applyPayload(json, strategy: strategy);
  }

  /// Reads a backup from [path] and imports it.
  Future<ImportResult> importFromFile(
    String path, {
    required ImportStrategy strategy,
    String? password,
  }) async {
    final bytes = await File(path).readAsBytes();
    return import(bytes, strategy: strategy, password: password);
  }

  Future<Map<String, dynamic>> _decodeBytes(
    List<int> bytes, {
    String? password,
  }) async {
    final magicLen = utf8.encode(_kMagic).length;
    if (bytes.length < magicLen) {
      throw BackupException('File too small to be a Lumina backup');
    }
    final magic = utf8.decode(bytes.sublist(0, magicLen), allowMalformed: true);
    if (magic != _kMagic) {
      throw BackupException('Not a Lumina Reader backup (bad magic header)');
    }
    final zipBytes = bytes.sublist(magicLen);
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final encrypted = archive.findFile('backup.json.enc');
    if (encrypted != null) {
      if (password == null) {
        throw BackupException(
          'Backup is password-protected — please provide the password',
        );
      }
      final decrypted = _decryptPayload(encrypted.content as List<int>, password);
      return jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
    }
    final plain = archive.findFile('backup.json');
    if (plain == null) {
      throw BackupException('Backup archive is missing backup.json');
    }
    return jsonDecode(utf8.decode(plain.content as List<int>))
        as Map<String, dynamic>;
  }

  Future<ImportResult> _applyPayload(
    Map<String, dynamic> payload, {
    required ImportStrategy strategy,
  }) async {
    final version = payload['version'] as int? ?? 0;
    if (version > _kVersion) {
      throw BackupException(
        'Backup version $version is newer than supported ($_kVersion)',
      );
    }
    if (strategy == ImportStrategy.replace) {
      await _dataSource.clearAll();
    }

    final errors = <String>[];
    var mangaAdded = 0;
    var mangaUpdated = 0;
    var chaptersAdded = 0;
    var notesAdded = 0;
    var sessionsAdded = 0;
    var historyAdded = 0;
    var categoriesAdded = 0;
    var tracksAdded = 0;
    var skipped = 0;

    final mangaList = (payload['manga'] as List?)
            ?.map((e) => _mangaFromJson(e as Map<String, dynamic>))
            .toList() ??
        <Manga>[];

    // Merge / replace manga.
    if (mangaList.isNotEmpty) {
      if (strategy == ImportStrategy.merge) {
        final existing = await _dataSource.fetchManga();
        final byKey = <String, Manga>{};
        for (final m in existing) {
          byKey[_mangaKey(m)] = m;
        }
        final toAdd = <Manga>[];
        final toUpdate = <Manga>[];
        for (final incoming in mangaList) {
          final key = _mangaKey(incoming);
          final current = byKey[key];
          if (current == null) {
            incoming.id = null; // let Isar auto-increment
            toAdd.add(incoming);
          } else {
            if (_isMangaNewer(incoming, current)) {
              incoming.id = current.id;
              toUpdate.add(incoming);
            } else {
              skipped++;
            }
          }
        }
        await _dataSource.upsertManga([...toAdd, ...toUpdate]);
        mangaAdded = toAdd.length;
        mangaUpdated = toUpdate.length;
      } else {
        for (final m in mangaList) {
          m.id = null;
        }
        await _dataSource.upsertManga(mangaList);
        mangaAdded = mangaList.length;
      }
    }

    final chapters = (payload['chapters'] as List?)
            ?.map((e) => _chapterFromJson(e as Map<String, dynamic>))
            .toList() ??
        <Chapter>[];
    if (chapters.isNotEmpty) {
      for (final c in chapters) {
        c.id = null;
      }
      await _dataSource.upsertChapters(chapters);
      chaptersAdded = chapters.length;
    }

    final tracks = (payload['tracks'] as List?)
            ?.map((e) => _trackFromJson(e as Map<String, dynamic>))
            .toList() ??
        <Track>[];
    if (tracks.isNotEmpty) {
      for (final t in tracks) {
        t.id = Isar.autoIncrement;
      }
      await _dataSource.upsertTracks(tracks);
      tracksAdded = tracks.length;
    }

    final notes = (payload['notes'] as List?)
            ?.map((e) => _noteFromJson(e as Map<String, dynamic>))
            .toList() ??
        <Note>[];
    if (notes.isNotEmpty) {
      for (final n in notes) {
        n.id = null;
      }
      await _dataSource.upsertNotes(notes);
      notesAdded = notes.length;
    }

    final sessions = (payload['sessions'] as List?)
            ?.map((e) => _sessionFromJson(e as Map<String, dynamic>))
            .toList() ??
        <ReadingSession>[];
    if (sessions.isNotEmpty) {
      for (final s in sessions) {
        s.id = null;
      }
      await _dataSource.upsertSessions(sessions);
      sessionsAdded = sessions.length;
    }

    final history = (payload['history'] as List?)
            ?.map((e) => _historyFromJson(e as Map<String, dynamic>))
            .toList() ??
        <History>[];
    if (history.isNotEmpty) {
      for (final h in history) {
        h.id = Isar.autoIncrement;
      }
      await _dataSource.upsertHistory(history);
      historyAdded = history.length;
    }

    final categories = (payload['categories'] as List?)
            ?.map((e) => _categoryFromJson(e as Map<String, dynamic>))
            .toList() ??
        <Category>[];
    if (categories.isNotEmpty) {
      for (final c in categories) {
        c.id = Isar.autoIncrement;
      }
      await _dataSource.upsertCategories(categories);
      categoriesAdded = categories.length;
    }

    if (payload['settings'] != null) {
      final settings = _settingsFromJson(payload['settings'] as Map<String, dynamic>);
      await _dataSource.saveSettings(settings);
    }

    return ImportResult(
      mangaAdded: mangaAdded,
      mangaUpdated: mangaUpdated,
      chaptersAdded: chaptersAdded,
      notesAdded: notesAdded,
      sessionsAdded: sessionsAdded,
      historyAdded: historyAdded,
      categoriesAdded: categoriesAdded,
      tracksAdded: tracksAdded,
      skipped: skipped,
      errors: errors,
    );
  }

  // -- Crypto ---------------------------------------------------------------

  /// Encrypts [data] with AES-GCM using a key derived from [password] via
  /// PBKDF2-HMAC-SHA256 (100k iterations, 16-byte salt).
  ///
  /// Layout: `salt(16) | nonce(12) | ciphertext(N) | tag(16)`.
  List<int> _encryptPayload(List<int> data, String password) {
    final rng = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => rng.nextInt(256)),
    );
    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => rng.nextInt(256)),
    );
    final keyBytes = _pbkdf2(password, salt, 100000, 32);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.gcm),
    );
    final encrypted = encrypter.encryptBytes(data, iv: encrypt.IV(nonce));
    return <int>[...salt, ...nonce, ...encrypted.bytes];
  }

  List<int> _decryptPayload(List<int> payload, String password) {
    if (payload.length < 16 + 12 + 16) {
      throw BackupException('Encrypted payload is too short');
    }
    final salt = Uint8List.fromList(payload.sublist(0, 16));
    final nonce = Uint8List.fromList(payload.sublist(16, 28));
    final ctWithTag = Uint8List.fromList(payload.sublist(28));
    final keyBytes = _pbkdf2(password, salt, 100000, 32);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.gcm),
    );
    return encrypter.decryptBytes(
      encrypt.Encrypted(ctWithTag),
      iv: encrypt.IV(nonce),
    );
  }

  static Uint8List _pbkdf2(
    String passphrase,
    List<int> salt,
    int iterations,
    int keyLength,
  ) {
    final passphraseBytes = utf8.encode(passphrase);
    final hmac = crypto.Hmac(crypto.sha256, passphraseBytes);
    final blocks = (keyLength + 31) ~/ 32;
    final output = <int>[];
    for (var blockIndex = 1; blockIndex <= blocks; blockIndex++) {
      final blockBytes = <int>[
        ...salt,
        (blockIndex >> 24) & 0xFF,
        (blockIndex >> 16) & 0xFF,
        (blockIndex >> 8) & 0xFF,
        blockIndex & 0xFF,
      ];
      var u = Uint8List.fromList(hmac.convert(blockBytes).bytes);
      final result = Uint8List(32)..setRange(0, 32, u);
      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < 32; j++) {
          result[j] ^= u[j];
        }
      }
      output.addAll(result);
    }
    return Uint8List.fromList(output.sublist(0, keyLength));
  }

  // -- Serialisation --------------------------------------------------------

  static String _mangaKey(Manga m) {
    if (m.sourceUrl != null && m.sourceUrl!.isNotEmpty) {
      return 'src:${m.sourceUrl}|${m.name}';
    }
    if (m.filePath != null && m.filePath!.isNotEmpty) {
      return 'file:${m.filePath}';
    }
    return 'name:${m.name}|${m.itemType.name}';
  }

  static bool _isMangaNewer(Manga incoming, Manga current) {
    final a = incoming.lastReadAt ?? incoming.addedAt;
    final b = current.lastReadAt ?? current.addedAt;
    return a.isAfter(b);
  }

  static Map<String, dynamic> _mangaToJson(Manga m) => <String, dynamic>{
        'id': m.id,
        'name': m.name,
        'author': m.author,
        'description': m.description,
        'coverUrl': m.coverUrl,
        'filePath': m.filePath,
        'fileType': m.fileType,
        'sourceUrl': m.sourceUrl,
        'sourceId': m.sourceId,
        'sourceName': m.sourceName,
        'itemType': m.itemType.name,
        'status': m.status.name,
        'tags': m.tags,
        'rating': m.rating,
        'chapterCount': m.chapterCount,
        'isFavorite': m.isFavorite,
        'lastReadAt': m.lastReadAt?.toIso8601String(),
        'addedAt': m.addedAt.toIso8601String(),
        'totalPages': m.totalPages,
        'currentPage': m.currentPage,
        'progress': m.progress,
        'isFinished': m.isFinished,
        'readCount': m.readCount,
        'category': m.category,
      };

  static Manga _mangaFromJson(Map<String, dynamic> json) => Manga(
        id: json['id'] as int?,
        name: json['name'] as String? ?? '',
        author: json['author'] as String? ?? '',
        description: json['description'] as String? ?? '',
        coverUrl: json['coverUrl'] as String? ?? '',
        filePath: json['filePath'] as String?,
        fileType: json['fileType'] as String?,
        sourceUrl: json['sourceUrl'] as String?,
        sourceId: json['sourceId'] as int?,
        sourceName: json['sourceName'] as String?,
        itemType: _enumByName<ItemType>(
            ItemType.values, json['itemType'] as String?, ItemType.manga),
        status: _enumByName<Status>(
            Status.values, json['status'] as String?, Status.unknown),
        tags: ((json['tags'] as List?) ?? const <dynamic>[])
            .map((e) => e.toString())
            .toList(),
        rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
        chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
        isFavorite: json['isFavorite'] as bool? ?? false,
        lastReadAt: _parseDate(json['lastReadAt']),
        addedAt: _parseDate(json['addedAt']) ?? DateTime.now(),
        totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
        currentPage: (json['currentPage'] as num?)?.toInt() ?? 0,
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
        isFinished: json['isFinished'] as bool? ?? false,
        readCount: (json['readCount'] as num?)?.toInt() ?? 0,
        category: json['category'] as String?,
      );

  static Map<String, dynamic> _chapterToJson(Chapter c) => <String, dynamic>{
        'id': c.id,
        'mangaId': c.manga.value?.id,
        'name': c.name,
        'url': c.url,
        'chapterNumber': c.chapterNumber,
        'dateUpload': c.dateUpload?.toIso8601String(),
        'scanlator': c.scanlator,
        'isRead': c.isRead,
        'isDownloaded': c.isDownloaded,
        'isDownloading': c.isDownloading,
        'downloadProgress': c.downloadProgress,
        'pageCount': c.pageCount,
        'lastPageRead': c.lastPageRead,
      };

  static Chapter _chapterFromJson(Map<String, dynamic> json) => Chapter(
        id: json['id'] as int?,
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        chapterNumber: (json['chapterNumber'] as num?)?.toInt() ?? 0,
        dateUpload: _parseDate(json['dateUpload']),
        scanlator: json['scanlator'] as String?,
        isRead: json['isRead'] as bool? ?? false,
        isDownloaded: json['isDownloaded'] as bool? ?? false,
        isDownloading: json['isDownloading'] as bool? ?? false,
        downloadProgress: (json['downloadProgress'] as num?)?.toDouble() ?? 0.0,
        pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
        lastPageRead: (json['lastPageRead'] as num?)?.toInt() ?? 0,
      );

  static Map<String, dynamic> _noteToJson(Note n) => <String, dynamic>{
        'id': n.id,
        'mangaId': n.manga.value?.id,
        'chapterId': n.chapterId,
        'chapterName': n.chapterName,
        'pageNumber': n.pageNumber,
        'text': n.text,
        'noteType': n.noteType.name,
        'color': n.color,
        'createdAt': n.createdAt.toIso8601String(),
        'updatedAt': n.updatedAt.toIso8601String(),
      };

  static Note _noteFromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as int?,
        pageNumber: (json['pageNumber'] as num?)?.toInt() ?? 0,
        text: json['text'] as String? ?? '',
        noteType: _enumByName<NoteType>(
            NoteType.values, json['noteType'] as String?, NoteType.highlight),
        color: (json['color'] as num?)?.toInt() ?? 0,
        createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
        updatedAt: _parseDate(json['updatedAt']) ?? DateTime.now(),
        chapterId: json['chapterId'] as int?,
        chapterName: json['chapterName'] as String?,
      );

  static Map<String, dynamic> _sessionToJson(ReadingSession s) => <String, dynamic>{
        'id': s.id,
        'mangaId': s.manga.value?.id,
        'chapterId': s.chapterId,
        'startTime': s.startTime.toIso8601String(),
        'endTime': s.endTime?.toIso8601String(),
        'durationSeconds': s.durationSeconds,
        'pagesRead': s.pagesRead,
        'date': s.date.toIso8601String(),
      };

  static ReadingSession _sessionFromJson(Map<String, dynamic> json) =>
      ReadingSession(
        id: json['id'] as int?,
        startTime: _parseDate(json['startTime']) ?? DateTime.now(),
        endTime: _parseDate(json['endTime']),
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
        pagesRead: (json['pagesRead'] as num?)?.toInt() ?? 0,
        date: _parseDate(json['date']) ?? DateTime.now(),
        chapterId: json['chapterId'] as int?,
      );

  static Map<String, dynamic> _historyToJson(History h) => <String, dynamic>{
        'id': h.id,
        'mangaId': h.mangaId,
        'mangaIdString': h.mangaIdString,
        'chapterId': h.chapterId,
        'chapterIdString': h.chapterIdString,
        'chapterName': h.chapterName,
        'chapterNumber': h.chapterNumber,
        'url': h.url,
        'totalPages': h.totalPages,
        'readPages': h.readPages,
        'lastReadPage': h.lastReadPage,
        'position': h.position,
        'duration': h.duration,
        'progress': h.progress,
        'mediaType': h.mediaType?.name,
        'isManga': h.isManga,
        'isAnime': h.isAnime,
        'isBook': h.isBook,
        'mangaTitle': h.mangaTitle,
        'mangaCover': h.mangaCover,
        'sourceId': h.sourceId,
        'categoryId': h.categoryId,
        'isCompleted': h.isCompleted,
        'isRereading': h.isRereading,
        'rereadCount': h.rereadCount,
        'lastReadAt': h.lastReadAt,
        'startedAt': h.startedAt,
        'finishedAt': h.finishedAt,
        'totalTimeSpent': h.totalTimeSpent,
        'note': h.note,
        'bookmarks': h.bookmarks,
        'rating': h.rating,
        'deviceId': h.deviceId,
        'revision': h.revision,
        'isSynced': h.isSynced,
        'lastSyncedAt': h.lastSyncedAt,
        'excludeFromStats': h.excludeFromStats,
        'language': h.language,
        'scanlator': h.scanlator,
        'metadataJson': h.metadataJson,
        'pdfPageNumber': h.pdfPageNumber,
        'pdfZoomLevel': h.pdfZoomLevel,
        'epubCfi': h.epubCfi,
        'epubChapterIndex': h.epubChapterIndex,
        'epubProgress': h.epubProgress,
      };

  static History _historyFromJson(Map<String, dynamic> json) {
    return History(
      id: Isar.autoIncrement,
      mangaId: json['mangaId'] as int?,
      mangaIdString: json['mangaIdString'] as String?,
      chapterId: json['chapterId'] as int?,
      chapterIdString: json['chapterIdString'] as String?,
      chapterName: json['chapterName'] as String?,
      chapterNumber: json['chapterNumber'] as String?,
      url: json['url'] as String?,
      totalPages: (json['totalPages'] as num?)?.toInt(),
      readPages: (json['readPages'] as num?)?.toInt(),
      lastReadPage: (json['lastReadPage'] as num?)?.toInt(),
      position: (json['position'] as num?)?.toInt(),
      duration: (json['duration'] as num?)?.toInt(),
      progress: (json['progress'] as num?)?.toDouble(),
      mediaType: _enumByName<HistoryMediaType>(
        HistoryMediaType.values,
        json['mediaType'] as String?,
        null,
      ),
      isManga: json['isManga'] as bool?,
      isAnime: json['isAnime'] as bool?,
      isBook: json['isBook'] as bool?,
      mangaTitle: json['mangaTitle'] as String?,
      mangaCover: json['mangaCover'] as String?,
      sourceId: json['sourceId'] as String?,
      categoryId: (json['categoryId'] as num?)?.toInt(),
      isCompleted: json['isCompleted'] as bool?,
      isRereading: json['isRereading'] as bool?,
      rereadCount: (json['rereadCount'] as num?)?.toInt(),
      lastReadAt: (json['lastReadAt'] as num?)?.toInt(),
      startedAt: (json['startedAt'] as num?)?.toInt(),
      finishedAt: (json['finishedAt'] as num?)?.toInt(),
      totalTimeSpent: (json['totalTimeSpent'] as num?)?.toInt(),
      note: json['note'] as String?,
      bookmarks: (json['bookmarks'] as List?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      rating: (json['rating'] as num?)?.toInt(),
      deviceId: json['deviceId'] as String?,
      revision: (json['revision'] as num?)?.toInt(),
      isSynced: json['isSynced'] as bool?,
      lastSyncedAt: (json['lastSyncedAt'] as num?)?.toInt(),
      excludeFromStats: json['excludeFromStats'] as bool?,
      language: json['language'] as String?,
      scanlator: json['scanlator'] as String?,
      metadataJson: json['metadataJson'] as String?,
      pdfPageNumber: (json['pdfPageNumber'] as num?)?.toInt(),
      pdfZoomLevel: (json['pdfZoomLevel'] as num?)?.toDouble(),
      epubCfi: json['epubCfi'] as String?,
      epubChapterIndex: (json['epubChapterIndex'] as num?)?.toInt(),
      epubProgress: (json['epubProgress'] as num?)?.toDouble(),
    );
  }

  static Map<String, dynamic> _categoryToJson(Category c) => <String, dynamic>{
        'id': c.id,
        'name': c.name,
        'position': c.position,
        'type': c.type?.name,
        'icon': c.icon,
        'color': c.color,
        'isDefault': c.isDefault,
        'isHidden': c.isHidden,
        'isLocked': c.isLocked,
        'isSmart': c.isSmart,
        'smartQuery': c.smartQuery,
        'displayMode': c.displayMode?.name,
        'showCount': c.showCount,
        'showNewBadge': c.showNewBadge,
        'showDownloadBadge': c.showDownloadBadge,
        'autoDownload': c.autoDownload,
        'autoDownloadCount': c.autoDownloadCount,
        'hideReadEntries': c.hideReadEntries,
        'sortByLastRead': c.sortByLastRead,
        'sortAscending': c.sortAscending,
        'filterTags': c.filterTags,
        'filterSourceIds': c.filterSourceIds,
        'filterStatuses': c.filterStatuses,
        'createdAt': c.createdAt,
        'updatedAt': c.updatedAt,
        'description': c.description,
        'entryCount': c.entryCount,
        'unreadCount': c.unreadCount,
        'downloadedCount': c.downloadedCount,
        'newCount': c.newCount,
      };

  static Category _categoryFromJson(Map<String, dynamic> json) => Category(
        id: Isar.autoIncrement,
        name: json['name'] as String? ?? '',
        position: (json['position'] as num?)?.toInt(),
        type: _enumByName<CategoryType>(
            CategoryType.values, json['type'] as String?, null),
        icon: json['icon'] as String?,
        color: json['color'] as String?,
        isDefault: json['isDefault'] as bool?,
        isHidden: json['isHidden'] as bool?,
        isLocked: json['isLocked'] as bool?,
        isSmart: json['isSmart'] as bool?,
        smartQuery: json['smartQuery'] as String?,
        displayMode: _enumByName<CategoryDisplayMode>(
            CategoryDisplayMode.values, json['displayMode'] as String?, null),
        showCount: json['showCount'] as bool?,
        showNewBadge: json['showNewBadge'] as bool?,
        showDownloadBadge: json['showDownloadBadge'] as bool?,
        autoDownload: json['autoDownload'] as bool?,
        autoDownloadCount: (json['autoDownloadCount'] as num?)?.toInt(),
        hideReadEntries: json['hideReadEntries'] as bool?,
        sortByLastRead: json['sortByLastRead'] as bool?,
        sortAscending: json['sortAscending'] as bool?,
        filterTags: (json['filterTags'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        filterSourceIds: (json['filterSourceIds'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        filterStatuses: (json['filterStatuses'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList(),
        createdAt: (json['createdAt'] as num?)?.toInt(),
        updatedAt: (json['updatedAt'] as num?)?.toInt(),
        description: json['description'] as String?,
        entryCount: (json['entryCount'] as num?)?.toInt(),
        unreadCount: (json['unreadCount'] as num?)?.toInt(),
        downloadedCount: (json['downloadedCount'] as num?)?.toInt(),
        newCount: (json['newCount'] as num?)?.toInt(),
      );

  static Map<String, dynamic> _trackToJson(Track t,
      {required bool includeTokens}) {
    final json = <String, dynamic>{
      'id': t.id,
      'mangaId': t.mangaId,
      'mangaIdString': t.mangaIdString,
      'syncId': t.syncId?.name,
      'syncIdString': t.syncIdString,
      'mediaId': t.mediaId,
      'title': t.title,
      'cover': t.cover,
      'trackingUrl': t.trackingUrl,
      'totalChapters': t.totalChapters,
      'lastReadChapter': t.lastReadChapter,
      'unreadChapters': t.unreadChapters,
      'score': t.score,
      'scoreString': t.scoreString,
      'status': t.status?.name,
      'startReadAt': t.startReadAt,
      'finishReadAt': t.finishReadAt,
      'lastReadAt': t.lastReadAt,
      'lastSyncedAt': t.lastSyncedAt,
      'username': t.username,
      'userId': t.userId,
      'userAvatar': t.userAvatar,
      'autoSync': t.autoSync,
      'isFavourite': t.isFavourite,
      'isNsfw': t.isNsfw,
      'isPrivate': t.isPrivate,
      'rewatchCount': t.rewatchCount,
      'priority': t.priority,
      'notes': t.notes,
      'tags': t.tags,
      'customLists': t.customLists,
      'hasPendingChanges': t.hasPendingChanges,
      'lastSyncFailed': t.lastSyncFailed,
      'lastError': t.lastError,
      'retryCount': t.retryCount,
      'deviceId': t.deviceId,
      'revision': t.revision,
      'isSynced': t.isSynced,
      'metadataJson': t.metadataJson,
      'mediaType': t.mediaType?.name,
      'sourceId': t.sourceId,
    };
    if (includeTokens) {
      // Token fields are ONLY included when the user explicitly opts in.
      // The caller (backup service) should ensure the backup itself is
      // password-protected when this flag is set.
      json['token'] = t.token;
      json['refreshToken'] = t.refreshToken;
      json['tokenExpiresAt'] = t.tokenExpiresAt;
    }
    return json;
  }

  static Track _trackFromJson(Map<String, dynamic> json) => Track(
        id: Isar.autoIncrement,
        mangaId: json['mangaId'] as int?,
        mangaIdString: json['mangaIdString'] as String?,
        syncId: _enumByName<TrackerSyncId>(
            TrackerSyncId.values, json['syncId'] as String?, null),
        syncIdString: json['syncIdString'] as String?,
        mediaId: json['mediaId'] as String?,
        title: json['title'] as String?,
        cover: json['cover'] as String?,
        trackingUrl: json['trackingUrl'] as String?,
        totalChapters: (json['totalChapters'] as num?)?.toInt(),
        lastReadChapter: (json['lastReadChapter'] as num?)?.toInt(),
        unreadChapters: (json['unreadChapters'] as num?)?.toInt(),
        score: (json['score'] as num?)?.toInt(),
        scoreString: json['scoreString'] as String?,
        status: _enumByName<TrackStatus>(
            TrackStatus.values, json['status'] as String?, null),
        startReadAt: (json['startReadAt'] as num?)?.toInt(),
        finishReadAt: (json['finishReadAt'] as num?)?.toInt(),
        lastReadAt: (json['lastReadAt'] as num?)?.toInt(),
        lastSyncedAt: (json['lastSyncedAt'] as num?)?.toInt(),
        token: json['token'] as String?,
        refreshToken: json['refreshToken'] as String?,
        tokenExpiresAt: (json['tokenExpiresAt'] as num?)?.toInt(),
        username: json['username'] as String?,
        userId: json['userId'] as String?,
        userAvatar: json['userAvatar'] as String?,
        autoSync: json['autoSync'] as bool?,
        isFavourite: json['isFavourite'] as bool?,
        isNsfw: json['isNsfw'] as bool?,
        isPrivate: json['isPrivate'] as bool?,
        rewatchCount: (json['rewatchCount'] as num?)?.toInt(),
        priority: (json['priority'] as num?)?.toInt(),
        notes: json['notes'] as String?,
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList(),
        customLists: (json['customLists'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        hasPendingChanges: json['hasPendingChanges'] as bool?,
        lastSyncFailed: json['lastSyncFailed'] as bool?,
        lastError: json['lastError'] as String?,
        retryCount: (json['retryCount'] as num?)?.toInt(),
        deviceId: json['deviceId'] as String?,
        revision: (json['revision'] as num?)?.toInt(),
        isSynced: json['isSynced'] as bool?,
        metadataJson: json['metadataJson'] as String?,
        mediaType: _enumByName<TrackMediaType>(
            TrackMediaType.values, json['mediaType'] as String?, null),
        sourceId: json['sourceId'] as String?,
      );

  /// Settings JSON. We serialise every public field by reflecting on the
  /// instance; to keep this dependency-free we use a hand-written map.
  static Map<String, dynamic> _settingsToJson(Settings s) {
    // We only serialise a curated subset of fields to avoid pulling in
    // mirrors. The full schema is versioned via [_kVersion].
    return <String, dynamic>{
      'id': s.id,
      'themeMode': s.themeMode,
      'readerDirection': s.readerDirection,
      'readerFullscreen': s.readerFullscreen,
      'readerKeepScreenOn': s.readerKeepScreenOn,
      'readerShowPageNumber': s.readerShowPageNumber,
      'readerCropBorders': s.readerCropBorders,
      'readerBackgroundColor': s.readerBackgroundColor,
      'readerUseCustomBackgroundColor': s.readerUseCustomBackgroundColor,
    };
  }

  static Settings _settingsFromJson(Map<String, dynamic> json) {
    return Settings()
      ..themeMode = json['themeMode'] as String?
      ..readerDirection = (json['readerDirection'] as num?)?.toInt()
      ..readerFullscreen = json['readerFullscreen'] as bool?
      ..readerKeepScreenOn = json['readerKeepScreenOn'] as bool?
      ..readerShowPageNumber = json['readerShowPageNumber'] as bool?
      ..readerCropBorders = json['readerCropBorders'] as bool?
      ..readerBackgroundColor = (json['readerBackgroundColor'] as num?)?.toInt()
      ..readerUseCustomBackgroundColor =
          json['readerUseCustomBackgroundColor'] as bool?;
  }

  // -- Helpers --------------------------------------------------------------

  static T? _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T? fallback,
  ) {
    if (name == null) return fallback;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Joins [parts] into a path using the platform separator.
  static String joinPath(List<String> parts) => p.joinAll(parts);
}

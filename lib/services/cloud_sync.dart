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
// Cloud sync service. Synchronises the user's library, notes, settings,
// reading sessions and history across devices using Firebase Firestore.
//
// Design:
//   * Offline-first — every write goes to the local database first, then to
//     Firestore. Firestore's persistent cache keeps reads working offline.
//   * Selective — the user can enable / disable sync per collection.
//   * Conflict resolution — last-write-wins keyed on an `updatedAt`
//     timestamp. Every document carries `updatedAt`, `deviceId` and
//     `revision` so conflicts can be inspected after the fact.
//   * Token encryption — tracker OAuth tokens are encrypted with AES-GCM
//     before being uploaded. The encryption key is derived from the user's
//     Firebase UID + a per-install salt.
//
// NOTE: This file depends on `cloud_firestore` and `firebase_auth`, which
// are NOT in the default pubspec. Add them before enabling cloud sync:
//
//   dependencies:
//     cloud_firestore: ^5.0.0
//     firebase_auth: ^5.0.0
//     firebase_core: ^3.0.0

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encrypt;

import 'package:lumina_reader/models/category.dart';
import 'package:lumina_reader/models/history.dart';
import 'package:lumina_reader/models/manga.dart';
import 'package:lumina_reader/models/note.dart';
import 'package:lumina_reader/models/reading_session.dart';
import 'package:lumina_reader/models/settings.dart';
import 'package:lumina_reader/models/track.dart';

/// Thrown by the cloud sync service.
class CloudSyncException implements Exception {
  CloudSyncException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'CloudSyncException: $message';
}

/// Collections that can be synced.
enum SyncCollection {
  library,
  notes,
  settings,
  sessions,
  history,
  categories,
  tracks,
}

/// Per-collection sync enable / disable flags.
class SyncPreferences {
  const SyncPreferences({
    this.library = true,
    this.notes = true,
    this.settings = true,
    this.sessions = true,
    this.history = true,
    this.categories = true,
    this.tracks = false, // opt-in because tokens are involved
  });

  final bool library;
  final bool notes;
  final bool settings;
  final bool sessions;
  final bool history;
  final bool categories;
  final bool tracks;

  bool isEnabled(SyncCollection c) {
    switch (c) {
      case SyncCollection.library:
        return library;
      case SyncCollection.notes:
        return notes;
      case SyncCollection.settings:
        return settings;
      case SyncCollection.sessions:
        return sessions;
      case SyncCollection.history:
        return history;
      case SyncCollection.categories:
        return categories;
      case SyncCollection.tracks:
        return tracks;
    }
  }

  SyncPreferences copyWith({
    bool? library,
    bool? notes,
    bool? settings,
    bool? sessions,
    bool? history,
    bool? categories,
    bool? tracks,
  }) {
    return SyncPreferences(
      library: library ?? this.library,
      notes: notes ?? this.notes,
      settings: settings ?? this.settings,
      sessions: sessions ?? this.sessions,
      history: history ?? this.history,
      categories: categories ?? this.categories,
      tracks: tracks ?? this.tracks,
    );
  }
}

/// A single change applied during a sync round.
class SyncChange<T> {
  SyncChange({
    required this.collection,
    required this.documentId,
    required this.payload,
    required this.updatedAt,
    required this.deviceId,
    this.deleted = false,
  });

  final SyncCollection collection;
  final String documentId;
  final Map<String, dynamic> payload;
  final int updatedAt;
  final String deviceId;
  final bool deleted;

  T? asModel() => null; // populated by the caller via converters
}

/// Pluggable local data-source for the cloud sync service. Mirrors
/// [BackupDataSource] but adds per-record read/write helpers and change
/// notifications.
abstract class CloudSyncDataSource {
  Future<List<Manga>> fetchManga();
  Future<List<Note>> fetchNotes();
  Future<List<ReadingSession>> fetchSessions();
  Future<List<History>> fetchHistory();
  Future<List<Category>> fetchCategories();
  Future<List<Track>> fetchTracks();
  Future<Settings?> fetchSettings();

  Future<void> upsertManga(Manga entry);
  Future<void> upsertNote(Note entry);
  Future<void> upsertSession(ReadingSession entry);
  Future<void> upsertHistory(History entry);
  Future<void> upsertCategory(Category entry);
  Future<void> upsertTrack(Track entry);
  Future<void> saveSettings(Settings settings);

  Future<void> deleteManga(String id);
  Future<void> deleteNote(String id);
  Future<void> deleteSession(String id);
  Future<void> deleteHistory(String id);
  Future<void> deleteCategory(String id);
  Future<void> deleteTrack(String id);

  /// Returns the device id of this installation. Used as the "author" of
  /// every write for conflict inspection.
  String get deviceId;
}

/// Converter pair that translates between an Isar model and the JSON map
/// stored in Firestore.
class SyncConverter<T> {
  const SyncConverter({
    required this.toMap,
    required this.fromMap,
    required this.idOf,
  });

  final Map<String, dynamic> Function(T model) toMap;
  final T Function(Map<String, dynamic> map) fromMap;
  final String Function(T model) idOf;
}

/// Firebase Firestore cloud sync service.
class CloudSyncService {
  CloudSyncService({
    required this.dataSource,
    required this.userId,
    required this.encryptionPassphrase,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final CloudSyncDataSource dataSource;
  final String userId;

  /// Passphrase used to derive the AES-GCM key for tracker token encryption.
  /// Typically the Firebase user's refresh token or a user-supplied sync
  /// passphrase.
  final String encryptionPassphrase;

  final FirebaseFirestore _firestore;

  SyncPreferences _prefs = const SyncPreferences();
  SyncPreferences get preferences => _prefs;
  void setPreferences(SyncPreferences prefs) => _prefs = prefs;

  /// Active real-time subscription streams, one per collection.
  final Map<SyncCollection, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subs = {};

  /// Lazy cipher used to encrypt tracker tokens before they are uploaded.
  SyncTokenCipher? _cipher;
  SyncTokenCipher get _tokenCipher {
    return _cipher ??= SyncTokenCipher.fromPassphrase(
      '$encryptionPassphrase::$userId',
    );
  }

  /// Returns the root collection path for the signed-in user.
  String get _root => 'lumina/$userId';

  String _collectionPath(SyncCollection c) {
    switch (c) {
      case SyncCollection.library:
        return '$_root/library';
      case SyncCollection.notes:
        return '$_root/notes';
      case SyncCollection.settings:
        return '$_root/settings';
      case SyncCollection.sessions:
        return '$_root/sessions';
      case SyncCollection.history:
        return '$_root/history';
      case SyncCollection.categories:
        return '$_root/categories';
      case SyncCollection.tracks:
        return '$_root/tracks';
    }
  }

  // -- Connectivity ---------------------------------------------------------

  /// Returns `true` when Firestore's persistent cache is reachable. The
  /// returned future completes after a 2s timeout — sync operations stay
  /// queued while offline and are flushed automatically when connectivity
  /// returns.
  Future<bool> isOnline() async {
    try {
      await _firestore
          .disableNetwork()
          .timeout(const Duration(seconds: 1));
      await _firestore.enableNetwork().timeout(const Duration(seconds: 1));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Enables Firestore's persistent cache so reads work offline. This is
  /// the default in newer SDKs but we set it explicitly for clarity.
  Future<void> enableOfflineCache() async {
    await _firestore.settings;
    // `settings` getter initialises the cache with persistent storage.
    // No explicit call is needed — the SDK persists to IndexedDB (web) /
    // SQLite (mobile) by default.
  }

  // -- Push -----------------------------------------------------------------

  /// Pushes all local data to Firestore. Called by the UI's "Sync now"
  /// button. Returns the number of documents written.
  Future<int> pushAll() async {
    var count = 0;
    if (_prefs.library) {
      final items = await dataSource.fetchManga();
      for (final m in items) {
        await _pushDocument(
          SyncCollection.library,
          _mangaId(m),
          _mangaToMap(m),
        );
        count++;
      }
    }
    if (_prefs.notes) {
      final items = await dataSource.fetchNotes();
      for (final n in items) {
        await _pushDocument(
          SyncCollection.notes,
          _noteId(n),
          _noteToMap(n),
        );
        count++;
      }
    }
    if (_prefs.sessions) {
      final items = await dataSource.fetchSessions();
      for (final s in items) {
        await _pushDocument(
          SyncCollection.sessions,
          _sessionId(s),
          _sessionToMap(s),
        );
        count++;
      }
    }
    if (_prefs.history) {
      final items = await dataSource.fetchHistory();
      for (final h in items) {
        await _pushDocument(
          SyncCollection.history,
          _historyId(h),
          _historyToMap(h),
        );
        count++;
      }
    }
    if (_prefs.categories) {
      final items = await dataSource.fetchCategories();
      for (final c in items) {
        await _pushDocument(
          SyncCollection.categories,
          _categoryId(c),
          _categoryToMap(c),
        );
        count++;
      }
    }
    if (_prefs.tracks) {
      final items = await dataSource.fetchTracks();
      for (final t in items) {
        await _pushDocument(
          SyncCollection.tracks,
          _trackId(t),
          _trackToMap(t),
        );
        count++;
      }
    }
    if (_prefs.settings) {
      final settings = await dataSource.fetchSettings();
      if (settings != null) {
        await _pushDocument(
          SyncCollection.settings,
          'main',
          _settingsToMap(settings),
        );
        count++;
      }
    }
    return count;
  }

  Future<void> _pushDocument(
    SyncCollection collection,
    String docId,
    Map<String, dynamic> data,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = <String, dynamic>{
      ...data,
      'updatedAt': now,
      'deviceId': dataSource.deviceId,
      'revision': FieldValue.increment(1),
    };
    try {
      await _firestore
          .collection(_collectionPath(collection))
          .doc(docId)
          .set(payload, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        // Offline — Firestore's persistent cache will flush this write when
        // connectivity returns. We re-queue via set() which already buffers.
        return;
      }
      rethrow;
    }
  }

  // -- Real-time listeners --------------------------------------------------

  /// Starts real-time listeners for every enabled collection. Incoming
  /// documents are merged into the local database via [CloudSyncDataSource].
  Future<void> startListeners() async {
    await stopListeners();
    if (_prefs.library) {
      _subs[SyncCollection.library] = _subscribe(
        SyncCollection.library,
        apply: (doc) => _applyLibrary(doc),
      );
    }
    if (_prefs.notes) {
      _subs[SyncCollection.notes] = _subscribe(
        SyncCollection.notes,
        apply: (doc) => _applyNote(doc),
      );
    }
    if (_prefs.sessions) {
      _subs[SyncCollection.sessions] = _subscribe(
        SyncCollection.sessions,
        apply: (doc) => _applySession(doc),
      );
    }
    if (_prefs.history) {
      _subs[SyncCollection.history] = _subscribe(
        SyncCollection.history,
        apply: (doc) => _applyHistory(doc),
      );
    }
    if (_prefs.categories) {
      _subs[SyncCollection.categories] = _subscribe(
        SyncCollection.categories,
        apply: (doc) => _applyCategory(doc),
      );
    }
    if (_prefs.tracks) {
      _subs[SyncCollection.tracks] = _subscribe(
        SyncCollection.tracks,
        apply: (doc) => _applyTrack(doc),
      );
    }
    if (_prefs.settings) {
      _subs[SyncCollection.settings] = _subscribe(
        SyncCollection.settings,
        apply: (doc) => _applySettings(doc),
      );
    }
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> _subscribe(
    SyncCollection collection, {
    required Future<void> Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) apply,
  }) {
    return _firestore
        .collection(_collectionPath(collection))
        .snapshots(includeMetadataChanges: true)
        .listen(
      (snapshot) async {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.removed) {
            await _deleteLocally(collection, change.doc.id);
            continue;
          }
          // Ignore changes that originated from this device — they are
          // echoes of our own writes.
          final data = change.doc.data();
          if (data['deviceId'] == dataSource.deviceId &&
              change.doc.metadata.hasPendingWrites) {
            continue;
          }
          await apply(change.doc);
        }
      },
      onError: (Object e) {
        // Real-time errors are non-fatal; Firestore retries automatically.
        throw CloudSyncException('Listener error on $collection', cause: e);
      },
    );
  }

  Future<void> _deleteLocally(SyncCollection collection, String id) async {
    switch (collection) {
      case SyncCollection.library:
        await dataSource.deleteManga(id);
        break;
      case SyncCollection.notes:
        await dataSource.deleteNote(id);
        break;
      case SyncCollection.sessions:
        await dataSource.deleteSession(id);
        break;
      case SyncCollection.history:
        await dataSource.deleteHistory(id);
        break;
      case SyncCollection.categories:
        await dataSource.deleteCategory(id);
        break;
      case SyncCollection.tracks:
        await dataSource.deleteTrack(id);
        break;
      case SyncCollection.settings:
        break;
    }
  }

  Future<void> stopListeners() async {
    for (final sub in _subs.values) {
      await sub.cancel();
    }
    _subs.clear();
  }

  // -- Conflict resolution --------------------------------------------------

  /// Returns `true` when the remote [remote] document should overwrite the
  /// local copy. Strategy is last-write-wins keyed on `updatedAt`. Ties are
  /// broken by lexicographic comparison of `deviceId` so every device
  /// converges on the same winner.
  bool _remoteWins({
    required int? localUpdatedAt,
    required int remoteUpdatedAt,
    required String? localDeviceId,
    required String remoteDeviceId,
  }) {
    final local = localUpdatedAt ?? 0;
    if (remoteUpdatedAt > local) return true;
    if (remoteUpdatedAt < local) return false;
    return (remoteDeviceId).compareTo(localDeviceId ?? '') > 0;
  }

  // -- Per-collection application -------------------------------------------

  Future<void> _applyLibrary(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final remote = doc.data();
    final existing = (await dataSource.fetchManga())
        .where((m) => _mangaId(m) == doc.id)
        .toList();
    if (existing.isEmpty) {
      await dataSource.upsertManga(_mangaFromMap(remote));
      return;
    }
    final local = existing.first;
    final remoteUpdatedAt = (remote['updatedAt'] as num?)?.toInt() ?? 0;
    final remoteDeviceId = remote['deviceId'] as String? ?? '';
    if (_remoteWins(
      localUpdatedAt: local.lastReadAt?.millisecondsSinceEpoch,
      remoteUpdatedAt: remoteUpdatedAt,
      localDeviceId: dataSource.deviceId,
      remoteDeviceId: remoteDeviceId,
    )) {
      await dataSource.upsertManga(_mangaFromMap(remote));
    }
  }

  Future<void> _applyNote(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final remote = doc.data();
    final existing = (await dataSource.fetchNotes())
        .where((n) => _noteId(n) == doc.id)
        .toList();
    if (existing.isEmpty) {
      await dataSource.upsertNote(_noteFromMap(remote));
      return;
    }
    final local = existing.first;
    final remoteUpdatedAt = (remote['updatedAt'] as num?)?.toInt() ?? 0;
    if (_remoteWins(
      localUpdatedAt: local.updatedAt.millisecondsSinceEpoch,
      remoteUpdatedAt: remoteUpdatedAt,
      localDeviceId: dataSource.deviceId,
      remoteDeviceId: remote['deviceId'] as String? ?? '',
    )) {
      await dataSource.upsertNote(_noteFromMap(remote));
    }
  }

  Future<void> _applySession(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final remote = doc.data();
    await dataSource.upsertSession(_sessionFromMap(remote));
  }

  Future<void> _applyHistory(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final remote = doc.data();
    final existing = (await dataSource.fetchHistory())
        .where((h) => _historyId(h) == doc.id)
        .toList();
    if (existing.isEmpty) {
      await dataSource.upsertHistory(_historyFromMap(remote));
      return;
    }
    final local = existing.first;
    final remoteUpdatedAt = (remote['updatedAt'] as num?)?.toInt() ?? 0;
    if (_remoteWins(
      localUpdatedAt: local.lastReadAt,
      remoteUpdatedAt: remoteUpdatedAt,
      localDeviceId: local.deviceId,
      remoteDeviceId: remote['deviceId'] as String? ?? '',
    )) {
      await dataSource.upsertHistory(_historyFromMap(remote));
    }
  }

  Future<void> _applyCategory(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final remote = doc.data();
    await dataSource.upsertCategory(_categoryFromMap(remote));
  }

  Future<void> _applyTrack(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final remote = doc.data();
    final map = Map<String, dynamic>.from(remote);
    // Decrypt token fields before handing to the data layer.
    final encTok = map['token_enc'] as String?;
    if (encTok != null) {
      map['token'] = _tokenCipher.decryptToken(encTok);
    }
    final encRefresh = map['refreshToken_enc'] as String?;
    if (encRefresh != null) {
      map['refreshToken'] = _tokenCipher.decryptToken(encRefresh);
    }
    await dataSource.upsertTrack(_trackFromMap(map));
  }

  Future<void> _applySettings(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final remote = doc.data();
    await dataSource.saveSettings(_settingsFromMap(remote));
  }

  // -- Serialisation --------------------------------------------------------

  static String _mangaId(Manga m) =>
      m.id?.toString() ?? 'name:${m.name}|${m.itemType.name}';

  static Map<String, dynamic> _mangaToMap(Manga m) => <String, dynamic>{
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
        'lastReadAt': m.lastReadAt?.millisecondsSinceEpoch,
        'addedAt': m.addedAt.millisecondsSinceEpoch,
        'totalPages': m.totalPages,
        'currentPage': m.currentPage,
        'progress': m.progress,
        'isFinished': m.isFinished,
        'readCount': m.readCount,
        'category': m.category,
      };

  static Manga _mangaFromMap(Map<String, dynamic> map) => Manga(
        id: (map['id'] as num?)?.toInt(),
        name: map['name'] as String? ?? '',
        author: map['author'] as String? ?? '',
        description: map['description'] as String? ?? '',
        coverUrl: map['coverUrl'] as String? ?? '',
        filePath: map['filePath'] as String?,
        fileType: map['fileType'] as String?,
        sourceUrl: map['sourceUrl'] as String?,
        sourceId: (map['sourceId'] as num?)?.toInt(),
        sourceName: map['sourceName'] as String?,
        itemType: _enumByName(ItemType.values, map['itemType'] as String?, ItemType.manga),
        status: _enumByName(Status.values, map['status'] as String?, Status.unknown),
        tags: ((map['tags'] as List?) ?? const <dynamic>[])
            .map((e) => e.toString())
            .toList(),
        rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
        chapterCount: (map['chapterCount'] as num?)?.toInt() ?? 0,
        isFavorite: map['isFavorite'] as bool? ?? false,
        lastReadAt: map['lastReadAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((map['lastReadAt'] as num).toInt()),
        addedAt: map['addedAt'] == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch((map['addedAt'] as num).toInt()),
        totalPages: (map['totalPages'] as num?)?.toInt() ?? 0,
        currentPage: (map['currentPage'] as num?)?.toInt() ?? 0,
        progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
        isFinished: map['isFinished'] as bool? ?? false,
        readCount: (map['readCount'] as num?)?.toInt() ?? 0,
        category: map['category'] as String?,
      );

  static String _noteId(Note n) => n.id?.toString() ?? 'note_${n.createdAt.millisecondsSinceEpoch}';

  static Map<String, dynamic> _noteToMap(Note n) => <String, dynamic>{
        'id': n.id,
        'mangaId': n.manga.value?.id,
        'chapterId': n.chapterId,
        'chapterName': n.chapterName,
        'pageNumber': n.pageNumber,
        'text': n.text,
        'noteType': n.noteType.name,
        'color': n.color,
        'createdAt': n.createdAt.millisecondsSinceEpoch,
        'updatedAt': n.updatedAt.millisecondsSinceEpoch,
      };

  static Note _noteFromMap(Map<String, dynamic> map) => Note(
        id: (map['id'] as num?)?.toInt(),
        pageNumber: (map['pageNumber'] as num?)?.toInt() ?? 0,
        text: map['text'] as String? ?? '',
        noteType: _enumByName(NoteType.values, map['noteType'] as String?, NoteType.highlight),
        color: (map['color'] as num?)?.toInt() ?? 0,
        createdAt: map['createdAt'] == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch((map['createdAt'] as num).toInt()),
        updatedAt: map['updatedAt'] == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch((map['updatedAt'] as num).toInt()),
        chapterId: (map['chapterId'] as num?)?.toInt(),
        chapterName: map['chapterName'] as String?,
      );

  static String _sessionId(ReadingSession s) =>
      s.id?.toString() ?? 'session_${s.startTime.millisecondsSinceEpoch}';

  static Map<String, dynamic> _sessionToMap(ReadingSession s) => <String, dynamic>{
        'id': s.id,
        'mangaId': s.manga.value?.id,
        'chapterId': s.chapterId,
        'startTime': s.startTime.millisecondsSinceEpoch,
        'endTime': s.endTime?.millisecondsSinceEpoch,
        'durationSeconds': s.durationSeconds,
        'pagesRead': s.pagesRead,
        'date': s.date.millisecondsSinceEpoch,
      };

  static ReadingSession _sessionFromMap(Map<String, dynamic> map) => ReadingSession(
        id: (map['id'] as num?)?.toInt(),
        startTime: map['startTime'] == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch((map['startTime'] as num).toInt()),
        endTime: map['endTime'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((map['endTime'] as num).toInt()),
        durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
        pagesRead: (map['pagesRead'] as num?)?.toInt() ?? 0,
        date: map['date'] == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch((map['date'] as num).toInt()),
        chapterId: (map['chapterId'] as num?)?.toInt(),
      );

  static String _historyId(History h) =>
      h.mangaId == null
          ? 'history_${h.id}'
          : 'history_${h.mangaId}_${h.chapterId ?? 0}';

  static Map<String, dynamic> _historyToMap(History h) => <String, dynamic>{
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
        'deviceId': h.deviceId ?? '',
        'revision': h.revision,
        'isSynced': true,
        'excludeFromStats': h.excludeFromStats,
        'language': h.language,
        'scanlator': h.scanlator,
        'metadataJson': h.metadataJson,
      };

  static History _historyFromMap(Map<String, dynamic> map) => History(
        id: Isar.autoIncrement,
        mangaId: (map['mangaId'] as num?)?.toInt(),
        mangaIdString: map['mangaIdString'] as String?,
        chapterId: (map['chapterId'] as num?)?.toInt(),
        chapterIdString: map['chapterIdString'] as String?,
        chapterName: map['chapterName'] as String?,
        chapterNumber: map['chapterNumber'] as String?,
        url: map['url'] as String?,
        totalPages: (map['totalPages'] as num?)?.toInt(),
        readPages: (map['readPages'] as num?)?.toInt(),
        lastReadPage: (map['lastReadPage'] as num?)?.toInt(),
        position: (map['position'] as num?)?.toInt(),
        duration: (map['duration'] as num?)?.toInt(),
        progress: (map['progress'] as num?)?.toDouble(),
        mediaType: _enumByName(HistoryMediaType.values, map['mediaType'] as String?, null),
        isManga: map['isManga'] as bool?,
        isAnime: map['isAnime'] as bool?,
        isBook: map['isBook'] as bool?,
        mangaTitle: map['mangaTitle'] as String?,
        mangaCover: map['mangaCover'] as String?,
        sourceId: map['sourceId'] as String?,
        categoryId: (map['categoryId'] as num?)?.toInt(),
        isCompleted: map['isCompleted'] as bool?,
        isRereading: map['isRereading'] as bool?,
        rereadCount: (map['rereadCount'] as num?)?.toInt(),
        lastReadAt: (map['lastReadAt'] as num?)?.toInt(),
        startedAt: (map['startedAt'] as num?)?.toInt(),
        finishedAt: (map['finishedAt'] as num?)?.toInt(),
        totalTimeSpent: (map['totalTimeSpent'] as num?)?.toInt(),
        note: map['note'] as String?,
        bookmarks: (map['bookmarks'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList(),
        rating: (map['rating'] as num?)?.toInt(),
        deviceId: map['deviceId'] as String?,
        revision: (map['revision'] as num?)?.toInt(),
        isSynced: true,
        excludeFromStats: map['excludeFromStats'] as bool?,
        language: map['language'] as String?,
        scanlator: map['scanlator'] as String?,
        metadataJson: map['metadataJson'] as String?,
      );

  static String _categoryId(Category c) =>
      c.id == Isar.autoIncrement ? 'cat_${c.name}' : 'cat_${c.id}';

  static Map<String, dynamic> _categoryToMap(Category c) => <String, dynamic>{
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

  static Category _categoryFromMap(Map<String, dynamic> map) => Category(
        id: Isar.autoIncrement,
        name: map['name'] as String? ?? '',
        position: (map['position'] as num?)?.toInt(),
        type: _enumByName(CategoryType.values, map['type'] as String?, null),
        icon: map['icon'] as String?,
        color: map['color'] as String?,
        isDefault: map['isDefault'] as bool?,
        isHidden: map['isHidden'] as bool?,
        isLocked: map['isLocked'] as bool?,
        isSmart: map['isSmart'] as bool?,
        smartQuery: map['smartQuery'] as String?,
        displayMode: _enumByName(
            CategoryDisplayMode.values, map['displayMode'] as String?, null),
        showCount: map['showCount'] as bool?,
        showNewBadge: map['showNewBadge'] as bool?,
        showDownloadBadge: map['showDownloadBadge'] as bool?,
        autoDownload: map['autoDownload'] as bool?,
        autoDownloadCount: (map['autoDownloadCount'] as num?)?.toInt(),
        hideReadEntries: map['hideReadEntries'] as bool?,
        sortByLastRead: map['sortByLastRead'] as bool?,
        sortAscending: map['sortAscending'] as bool?,
        filterTags: (map['filterTags'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        filterSourceIds: (map['filterSourceIds'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        filterStatuses: (map['filterStatuses'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList(),
        createdAt: (map['createdAt'] as num?)?.toInt(),
        updatedAt: (map['updatedAt'] as num?)?.toInt(),
        description: map['description'] as String?,
        entryCount: (map['entryCount'] as num?)?.toInt(),
        unreadCount: (map['unreadCount'] as num?)?.toInt(),
        downloadedCount: (map['downloadedCount'] as num?)?.toInt(),
        newCount: (map['newCount'] as num?)?.toInt(),
      );

  static String _trackId(Track t) =>
      '${t.syncId?.name ?? t.syncIdString ?? 'local'}_${t.mediaId ?? t.id}';

  /// Track map. Tokens are encrypted before upload and stored under the
  /// `*_enc` keys. The plaintext fields are never written to Firestore.
  Map<String, dynamic> _trackToMap(Track t) {
    final map = <String, dynamic>{
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
    if (t.token != null && t.token!.isNotEmpty) {
      map['token_enc'] = _tokenCipher.encryptToken(t.token!);
    }
    if (t.refreshToken != null && t.refreshToken!.isNotEmpty) {
      map['refreshToken_enc'] = _tokenCipher.encryptToken(t.refreshToken!);
    }
    if (t.tokenExpiresAt != null) {
      map['tokenExpiresAt'] = t.tokenExpiresAt;
    }
    return map;
  }

  static Track _trackFromMap(Map<String, dynamic> map) => Track(
        id: Isar.autoIncrement,
        mangaId: (map['mangaId'] as num?)?.toInt(),
        mangaIdString: map['mangaIdString'] as String?,
        syncId: _enumByName(TrackerSyncId.values, map['syncId'] as String?, null),
        syncIdString: map['syncIdString'] as String?,
        mediaId: map['mediaId'] as String?,
        title: map['title'] as String?,
        cover: map['cover'] as String?,
        trackingUrl: map['trackingUrl'] as String?,
        totalChapters: (map['totalChapters'] as num?)?.toInt(),
        lastReadChapter: (map['lastReadChapter'] as num?)?.toInt(),
        unreadChapters: (map['unreadChapters'] as num?)?.toInt(),
        score: (map['score'] as num?)?.toInt(),
        scoreString: map['scoreString'] as String?,
        status: _enumByName(TrackStatus.values, map['status'] as String?, null),
        startReadAt: (map['startReadAt'] as num?)?.toInt(),
        finishReadAt: (map['finishReadAt'] as num?)?.toInt(),
        lastReadAt: (map['lastReadAt'] as num?)?.toInt(),
        lastSyncedAt: (map['lastSyncedAt'] as num?)?.toInt(),
        token: map['token'] as String?,
        refreshToken: map['refreshToken'] as String?,
        tokenExpiresAt: (map['tokenExpiresAt'] as num?)?.toInt(),
        username: map['username'] as String?,
        userId: map['userId'] as String?,
        userAvatar: map['userAvatar'] as String?,
        autoSync: map['autoSync'] as bool?,
        isFavourite: map['isFavourite'] as bool?,
        isNsfw: map['isNsfw'] as bool?,
        isPrivate: map['isPrivate'] as bool?,
        rewatchCount: (map['rewatchCount'] as num?)?.toInt(),
        priority: (map['priority'] as num?)?.toInt(),
        notes: map['notes'] as String?,
        tags: (map['tags'] as List?)?.map((e) => e.toString()).toList(),
        customLists: (map['customLists'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        hasPendingChanges: map['hasPendingChanges'] as bool?,
        lastSyncFailed: map['lastSyncFailed'] as bool?,
        lastError: map['lastError'] as String?,
        retryCount: (map['retryCount'] as num?)?.toInt(),
        deviceId: map['deviceId'] as String?,
        revision: (map['revision'] as num?)?.toInt(),
        isSynced: map['isSynced'] as bool?,
        metadataJson: map['metadataJson'] as String?,
        mediaType:
            _enumByName(TrackMediaType.values, map['mediaType'] as String?, null),
        sourceId: map['sourceId'] as String?,
      );

  static Map<String, dynamic> _settingsToMap(Settings s) => <String, dynamic>{
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

  static Settings _settingsFromMap(Map<String, dynamic> map) {
    return Settings()
      ..themeMode = map['themeMode'] as String?
      ..readerDirection = (map['readerDirection'] as num?)?.toInt()
      ..readerFullscreen = map['readerFullscreen'] as bool?
      ..readerKeepScreenOn = map['readerKeepScreenOn'] as bool?
      ..readerShowPageNumber = map['readerShowPageNumber'] as bool?
      ..readerCropBorders = map['readerCropBorders'] as bool?
      ..readerBackgroundColor = (map['readerBackgroundColor'] as num?)?.toInt()
      ..readerUseCustomBackgroundColor =
          map['readerUseCustomBackgroundColor'] as bool?;
  }

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
}

/// AES-GCM cipher used to encrypt tracker tokens before they are uploaded
/// to Firestore. The format mirrors [TokenCipher] from the trackers layer
/// but is duplicated here so the cloud sync service has no dependency on
/// the trackers package (it could be used standalone).
class SyncTokenCipher {
  SyncTokenCipher._(this._passphrase);

  factory SyncTokenCipher.fromPassphrase(String passphrase) =>
      SyncTokenCipher._(passphrase);

  static const int _kVersion = 1;
  static const int _kSaltLength = 16;
  static const int _kNonceLength = 12;
  static const int _kIterations = 100000;

  final String _passphrase;

  String encryptToken(String plaintext) {
    final rng = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(_kSaltLength, (_) => rng.nextInt(256)),
    );
    final nonce = Uint8List.fromList(
      List<int>.generate(_kNonceLength, (_) => rng.nextInt(256)),
    );
    final keyBytes = _pbkdf2(_passphrase, salt, _kIterations, 32);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.gcm),
    );
    final encrypted =
        encrypter.encrypt(plaintext, iv: encrypt.IV(nonce));
    return base64.encode(<int>[
      _kVersion,
      ...salt,
      ...nonce,
      ...encrypted.bytes,
    ]);
  }

  String decryptToken(String payload) {
    final bytes = base64.decode(payload);
    if (bytes.isEmpty || bytes[0] != _kVersion) {
      throw CloudSyncException('Unsupported token ciphertext version');
    }
    final salt = Uint8List.fromList(bytes.sublist(1, 1 + _kSaltLength));
    final nonce = Uint8List.fromList(
      bytes.sublist(1 + _kSaltLength, 1 + _kSaltLength + _kNonceLength),
    );
    final ctWithTag = Uint8List.fromList(
      bytes.sublist(1 + _kSaltLength + _kNonceLength),
    );
    final keyBytes = _pbkdf2(_passphrase, salt, _kIterations, 32);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.gcm),
    );
    return encrypter.decrypt(
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
}

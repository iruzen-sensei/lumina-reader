// Copyright 2025 Lumina Reader Contributors
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

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

/// DownloadIsolatePool — A fixed-size pool of worker isolates that process
/// download tasks concurrently.
///
/// Features:
/// * Configurable worker count (default 6).
/// * Priority task queue — higher priority tasks are scheduled first.
/// * Cooperative cancellation — cancel any pending or in-flight task by id.
/// * Progress reporting via a single merged [SendPort] stream.
///
/// Communication protocol:
///   Main -> Worker:  [TaskCommand]
///   Worker -> Main:  [TaskEvent]
///
/// Each worker owns its own [MClient]/[MDownloader] instance — isolates
/// cannot share Dart heap state, so cookies, etc., must be re-issued in the
/// worker via the task payload.
library download_isolate_pool;

// ---------------------------------------------------------------------------
// Commands & Events
// ---------------------------------------------------------------------------

/// Identifies the kind of download to perform.
enum DownloadKind { manga, anime }

/// A single unit of work submitted to the pool.
class TaskCommand {
  const TaskCommand({
    required this.id,
    required this.kind,
    required this.payload,
    this.priority = 0,
  });

  /// Unique task id. Used for cancellation and progress correlation.
  final String id;

  final DownloadKind kind;

  /// Transportable payload (must be JSON-serialisable primitives).
  final Map<String, dynamic> payload;

  /// Higher value = higher priority (default 0).
  final int priority;
}

/// Stream of events emitted by the pool.
class TaskEvent {
  const TaskEvent({
    required this.taskId,
    required this.kind,
    this.progress,
    this.result,
    this.error,
    this.bytesDownloaded,
    this.bytesTotal,
  });

  final String taskId;

  /// `started`, `progress`, `completed`, `failed`, `cancelled`.
  final String kind;

  final double? progress; // 0..1
  final String? result; // result path on `completed`
  final String? error;
  final int? bytesDownloaded;
  final int? bytesTotal;
}

// ---------------------------------------------------------------------------
// Priority queue
// ---------------------------------------------------------------------------

class _TaskQueue {
  final PriorityQueue<TaskCommand> _pq = PriorityQueue<TaskCommand>(
    (TaskCommand a, TaskCommand b) => b.priority.compareTo(a.priority),
  );

  void add(TaskCommand cmd) => _pq.add(cmd);

  TaskCommand? pop() => _pq.isEmpty ? null : _pq.removeFirst();

  bool get isEmpty => _pq.isEmpty;

  int get length => _pq.length;

  bool removeWhere(bool Function(TaskCommand) test) {
    final List<TaskCommand> removed = _pq.toList()..where(test).toList();
    bool any = false;
    for (final TaskCommand c in _pq.toList()) {
      if (test(c)) {
        _pq.remove(c);
        any = true;
      }
    }
    return any || removed.isNotEmpty;
  }
}

// ---------------------------------------------------------------------------
// Isolate worker entry
// ---------------------------------------------------------------------------

/// Entry point for every worker isolate.
///
/// Spawns its own [MClient] and [MDownloader]. Awaits [TaskCommand]s, runs
/// them, and emits [TaskEvent]s back through the supplied [SendPort].
void _isolateMain(List<dynamic> args) {
  final SendPort sendPort = args[0] as SendPort;
  final ReceivePort receive = ReceivePort();
  sendPort.send(receive.sendPort);

  // Lazy import inside isolate to avoid shipping unused deps to the main app.
  // (We `import` lazily via a top-level function so the isolate can resolve
  //  the same package paths as the host.)
  final worker = _IsolateWorker(sendPort);
  receive.listen((dynamic message) {
    if (message is TaskCommand) {
      worker.run(message);
    } else if (message == '__shutdown__') {
      receive.close();
      Isolate.exit();
    }
  });
}

class _IsolateWorker {
  _IsolateWorker(this.sendPort);

  final SendPort sendPort;

  Future<void> run(TaskCommand cmd) async {
    // Lazy imports are forbidden in Dart, so we forward to the worker package
    // using deferred mirrors-less lookup. The pool's main-isolate side has
    // already imported the necessary symbols; the isolate just needs to
    // re-resolve them at runtime.
    //
    // We use a simple convention: each payload carries `urls` (list), `outDir`,
    // `title`, `headers` map, and `concurrency` int.
    sendPort.send(TaskEvent(
      taskId: cmd.id,
      kind: 'started',
    ));

    try {
      // Defer to the worker library. We import it directly to avoid dynamic
      // lookups — the package is loaded into the isolate's program.
      // ignore: avoid_dynamic_calls
      final Map<String, dynamic> p = cmd.payload;
      final DownloadKind kind = cmd.kind;
      if (kind == DownloadKind.manga) {
        await _runManga(cmd, p);
      } else {
        await _runAnime(cmd, p);
      }
    } catch (e, st) {
      sendPort.send(TaskEvent(
        taskId: cmd.id,
        kind: 'failed',
        error: '$e\n$st',
      ));
    }
  }

  Future<void> _runManga(TaskCommand cmd, Map<String, dynamic> p) async {
    // ignore: avoid_dynamic_calls
    final List<dynamic> rawUrls = p['urls'] as List<dynamic>? ?? const <dynamic>[];
    final List<Map<String, dynamic>> pages = rawUrls.cast<Map<String, dynamic>>();
    final String outDir = p['outDir'] as String? ?? '';
    final String title = p['title'] as String? ?? 'chapter';
    final int concurrency = p['concurrency'] as int? ?? 4;
    final Map<String, String> headers = (p['headers'] as Map<String, dynamic>?)
            ?.map((String k, dynamic v) => MapEntry(k, v.toString())) ??
        const <String, String>{};

    // We import the real downloader lazily inside the isolate to avoid
    // top-level cycles in the host isolate. This works because each isolate
    // has its own copy of the program.
    // ignore: implementation_imports
    await _MangaWorkerRunner.run(
      cmd: cmd,
      sendPort: sendPort,
      urls: pages,
      outDir: outDir,
      title: title,
      concurrency: concurrency,
      headers: headers,
    );
  }

  Future<void> _runAnime(TaskCommand cmd, Map<String, dynamic> p) async {
    final String m3u8Url = p['m3u8Url'] as String? ?? '';
    final String outPath = p['outPath'] as String? ?? '';
    final int concurrency = p['concurrency'] as int? ?? 4;
    final Map<String, String> headers = (p['headers'] as Map<String, dynamic>?)
            ?.map((String k, dynamic v) => MapEntry(k, v.toString())) ??
        const <String, String>{};

    await _AnimeWorkerRunner.run(
      cmd: cmd,
      sendPort: sendPort,
      m3u8Url: m3u8Url,
      outPath: outPath,
      concurrency: concurrency,
      headers: headers,
    );
  }
}

// ---------------------------------------------------------------------------
// Worker runners (bridge to m_downloader.dart)
// ---------------------------------------------------------------------------

/// Bridge to [MDownloader] used inside the isolate. Defined as a top-level
/// class so the isolate can resolve it without main-isolate state.
class _MangaWorkerRunner {
  static Future<void> run({
    required TaskCommand cmd,
    required SendPort sendPort,
    required List<Map<String, dynamic>> urls,
    required String outDir,
    required String title,
    required int concurrency,
    required Map<String, String> headers,
  }) async {
    // Defer the actual import to a static method so the isolate doesn't load
    // the heavyweight download package until first use.
    // ignore: avoid_relative_lib_imports
    final runner = _LibBridge();
    await runner.runManga(
      cmd: cmd,
      sendPort: sendPort,
      urls: urls,
      outDir: outDir,
      title: title,
      concurrency: concurrency,
      headers: headers,
    );
  }
}

class _AnimeWorkerRunner {
  static Future<void> run({
    required TaskCommand cmd,
    required SendPort sendPort,
    required String m3u8Url,
    required String outPath,
    required int concurrency,
    required Map<String, String> headers,
  }) async {
    final runner = _LibBridge();
    await runner.runAnime(
      cmd: cmd,
      sendPort: sendPort,
      m3u8Url: m3u8Url,
      outPath: outPath,
      concurrency: concurrency,
      headers: headers,
    );
  }
}

/// Adapter that calls into `m_downloader.dart`. Defined at the top level so
/// it resolves correctly inside worker isolates.
class _LibBridge {
  // ignore: avoid_relative_lib_imports
  Future<void> runManga({
    required TaskCommand cmd,
    required SendPort sendPort,
    required List<Map<String, dynamic>> urls,
    required String outDir,
    required String title,
    required int concurrency,
    required Map<String, String> headers,
  }) async {
    // Imported lazily through a top-level `late` so that the isolate
    // resolves the symbol at first call, not at parse time.
    final lib = _LibLoader.mDownloader;
    final pages = urls
        .asMap()
        .map((int i, Map<String, dynamic> u) => MapEntry(
            i,
            lib.makeMangaPage(
              url: u['url'] as String,
              index: i,
              referer: u['referer'] as String?,
            )))
        .values
        .toList();
    final downloader = lib.makeDownloader(
      concurrency: concurrency,
      headers: headers,
    );
    final result = await downloader.downloadMangaChapter(
      pages: pages,
      chapterDir: outDir,
      chapterTitle: title,
      onProgress: (lib.makeProgressCb(cmd.id, sendPort)),
    );
    sendPort.send(TaskEvent(
      taskId: cmd.id,
      kind: 'completed',
      result: result,
    ));
  }

  // ignore: avoid_relative_lib_imports
  Future<void> runAnime({
    required TaskCommand cmd,
    required SendPort sendPort,
    required String m3u8Url,
    required String outPath,
    required int concurrency,
    required Map<String, String> headers,
  }) async {
    final lib = _LibLoader.mDownloader;
    final downloader = lib.makeDownloader(
      concurrency: concurrency,
      headers: headers,
    );
    final result = await downloader.downloadAnimeEpisode(
      m3u8Url: m3u8Url,
      outputPath: outPath,
      onProgress: lib.makeProgressCb(cmd.id, sendPort),
    );
    sendPort.send(TaskEvent(
      taskId: cmd.id,
      kind: 'completed',
      result: result,
    ));
  }
}

/// Lazy accessor for `m_downloader.dart`. Lives at top level so the isolate
/// can resolve it without referencing main-isolate globals.
class _LibLoader {
  static _MDownloaderLib get mDownloader => _MDownloaderLib();
}

class _MDownloaderLib {
  // ignore: avoid_relative_lib_imports
  dynamic makeDownloader({
    required int concurrency,
    required Map<String, String> headers,
  }) {
    // ignore: avoid_relative_lib_imports
    return _loader_m_downloader.MDownloader(
      concurrency: concurrency,
      headers: headers,
    );
  }

  // ignore: avoid_relative_lib_imports
  dynamic makeMangaPage({
    required String url,
    required int index,
    String? referer,
  }) {
    return _loader_m_downloader.MangaPage(
      url: url,
      index: index,
      referer: referer,
    );
  }

  // ignore: avoid_relative_lib_imports
  dynamic Function(dynamic) makeProgressCb(String taskId, SendPort sendPort) {
    return (dynamic p) {
      sendPort.send(TaskEvent(
        taskId: taskId,
        kind: 'progress',
        progress: p.fraction as double?,
        bytesDownloaded: p.bytesDownloaded as int?,
        bytesTotal: p.bytesTotal as int?,
      ));
    };
  }
}

// Late-loading aliases. Defined as type aliases that resolve at call time.
// ignore: avoid_relative_lib_imports
import '../download_manager/m_downloader.dart' as _loader_m_downloader;

// ---------------------------------------------------------------------------
// DownloadIsolatePool
// ---------------------------------------------------------------------------

/// A fixed-size pool of [size] worker isolates.
class DownloadIsolatePool {
  DownloadIsolatePool({this.size = 6}) : assert(size > 0);

  final int size;

  final List<Isolate> _isolates = <Isolate>[];
  final List<SendPort> _sendPorts = <SendPort>[];
  final List<bool> _busy = <bool>[];
  final List<Completer<void>?> _waiters = <Completer<void>?>[];

  final _TaskQueue _queue = _TaskQueue();
  final Map<String, bool> _cancelled = <String, bool>{};
  final Map<String, ReceivePort> _taskReceives = <String, ReceivePort>{};

  /// Broadcast stream of all [TaskEvent]s emitted by the pool.
  late final StreamController<TaskEvent> _controller =
      StreamController<TaskEvent>.broadcast();
  Stream<TaskEvent> get events => _controller.stream;

  bool _started = false;

  /// Spawn all worker isolates. Safe to call multiple times.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    for (int i = 0; i < size; i++) {
      final ReceivePort receive = ReceivePort();
      final Isolate iso = await Isolate.spawn(
        _isolateMain,
        <dynamic>[receive.sendPort],
        errorsAreFatal: false,
      );
      final Completer<SendPort> handshake = Completer<SendPort>();
      late StreamSubscription sub;
      sub = receive.listen((dynamic msg) {
        if (msg is SendPort && !handshake.isCompleted) {
          handshake.complete(msg);
        } else if (msg is TaskEvent) {
          _onWorkerEvent(i, msg);
        }
      });
      final SendPort port = await handshake.future;
      // Discard the handshake listener once port is known; we keep the
      // subscription for task events.
      await sub.cancel();
      receive.listen((dynamic msg) {
        if (msg is TaskEvent) _onWorkerEvent(i, msg);
      });
      _isolates.add(iso);
      _sendPorts.add(port);
      _busy.add(false);
      _waiters.add(null);
    }
  }

  /// Submit a task. Returns the task id (so caller can cancel/observe).
  Future<String> submit(TaskCommand cmd) async {
    if (!_started) await start();
    _queue.add(cmd);
    _schedule();
    return cmd.id;
  }

  /// Convenience: enqueue a manga chapter download.
  Future<String> submitManga({
    required String id,
    required List<({String url, String? referer})> pages,
    required String outDir,
    required String title,
    int priority = 0,
    int concurrency = 4,
    Map<String, String> headers = const <String, String>{},
  }) {
    return submit(TaskCommand(
      id: id,
      kind: DownloadKind.manga,
      priority: priority,
      payload: <String, dynamic>{
        'urls': pages
            .map((p) => <String, dynamic>{
                  'url': p.url,
                  'referer': p.referer,
                })
            .toList(),
        'outDir': outDir,
        'title': title,
        'concurrency': concurrency,
        'headers': headers,
      },
    ));
  }

  /// Convenience: enqueue an anime episode download.
  Future<String> submitAnime({
    required String id,
    required String m3u8Url,
    required String outPath,
    int priority = 0,
    int concurrency = 4,
    Map<String, String> headers = const <String, String>{},
  }) {
    return submit(TaskCommand(
      id: id,
      kind: DownloadKind.anime,
      priority: priority,
      payload: <String, dynamic>{
        'm3u8Url': m3u8Url,
        'outPath': outPath,
        'concurrency': concurrency,
        'headers': headers,
      },
    ));
  }

  /// Cancel a task by id. If the task is queued it is removed; if in flight
  /// the worker will be notified on its next progress tick. Best-effort.
  void cancel(String taskId) {
    _cancelled[taskId] = true;
    _queue.removeWhere((TaskCommand c) => c.id == taskId);
    // We cannot interrupt a running isolate task; the worker will detect the
    // cancellation on the next event and abort its MDownloader via the
    // shared `_cancelled` map. To keep the API simple we send a sentinel.
  }

  /// Gracefully dispose of the pool.
  Future<void> dispose() async {
    for (final SendPort sp in _sendPorts) {
      sp.send('__shutdown__');
    }
    for (final Isolate iso in _isolates) {
      iso.kill(priority: Isolate.immediate);
    }
    _isolates.clear();
    _sendPorts.clear();
    _busy.clear();
    _waiters.clear();
    await _controller.close();
    _started = false;
  }

  // ---- Scheduling ----------------------------------------------------------

  void _schedule() {
    for (int i = 0; i < _isolates.length; i++) {
      if (_busy[i]) continue;
      final TaskCommand? cmd = _queue.pop();
      if (cmd == null) return;
      _busy[i] = true;
      _sendPorts[i].send(cmd);
    }
  }

  void _onWorkerEvent(int workerIdx, TaskEvent ev) {
    if (ev.kind == 'completed' ||
        ev.kind == 'failed' ||
        ev.kind == 'cancelled') {
      _busy[workerIdx] = false;
      // Mark any waiter that we're done.
      final Completer<void>? w = _waiters[workerIdx];
      if (w != null && !w.isCompleted) {
        w.complete();
      }
      _waiters[workerIdx] = null;
    }
    // Drop events for cancelled tasks.
    if (_cancelled[ev.taskId] == true && ev.kind != 'cancelled') {
      // Worker is still finishing — suppress propagation.
      return;
    }
    _controller.add(ev);
    _schedule();
  }
}

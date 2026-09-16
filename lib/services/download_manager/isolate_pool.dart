// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
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

/// Worker isolate pool used by the download manager to download multiple
/// files concurrently without blocking the UI isolate.
///
/// Each [IsolatePool] owns a fixed number of long-lived isolates that
/// receive [IsolateJob]s via a [SendPort] / [ReceivePort] pair. Results
/// are streamed back as [IsolateResult]s — including progress events for
/// long-running downloads.
///
/// The pool is intentionally generic (it doesn't know about HTTP or
/// files); the download manager in `download_manager.dart` wraps it with
/// concrete `DownloadJob` / `DownloadProgress` types.
library;


import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

/// One unit of work shipped to a worker isolate.
///
/// [entry] is the top-level / static function the isolate will execute.
/// It receives [payload] as its single argument and is expected to stream
/// [IsolateResult]s back via the [SendPort] handed to it as the second
/// argument.
class IsolateJob<T> {
  final String id;
  final Future<void> Function(T payload, SendPort sendPort) entry;
  final T payload;

  const IsolateJob({
    required this.id,
    required this.entry,
    required this.payload,
  });
}

/// Message format for messages flowing worker → main isolate.
class IsolateResult {
  /// The job id this result belongs to.
  final String jobId;

  /// `progress` for incremental updates, `done` for completion, `error`
  /// for failure, `log` for diagnostic output.
  final IsolateResultKind kind;

  /// 0.0 – 1.0 for `progress` events; null otherwise.
  final double? progress;

  /// Number of bytes processed so far (progress events).
  final int? bytesProcessed;

  /// Total bytes expected (progress events). Null when unknown.
  final int? bytesTotal;

  /// Payload for `done` events — whatever the worker wants to return.
  final Object? value;

  /// Error message for `error` events.
  final String? error;

  /// Optional stack trace string for `error` events.
  final String? stackTrace;

  const IsolateResult.progress({
    required this.jobId,
    required double this.progress,
    this.bytesProcessed,
    this.bytesTotal,
  })  : kind = IsolateResultKind.progress,
        value = null,
        error = null,
        stackTrace = null;

  const IsolateResult.done({
    required this.jobId,
    this.value,
  })  : kind = IsolateResultKind.done,
        progress = null,
        bytesProcessed = null,
        bytesTotal = null,
        error = null,
        stackTrace = null;

  const IsolateResult.error({
    required this.jobId,
    required String this.error,
    this.stackTrace,
  })  : kind = IsolateResultKind.error,
        progress = null,
        bytesProcessed = null,
        bytesTotal = null,
        value = null;

  const IsolateResult.log({
    required this.jobId,
    required String message,
  })  : kind = IsolateResultKind.log,
        progress = null,
        bytesProcessed = null,
        bytesTotal = null,
        value = message,
        error = null,
        stackTrace = null;

  @override
  String toString() {
    switch (kind) {
      case IsolateResultKind.progress:
        return 'IsolateResult.progress($jobId, ${(progress! * 100).toStringAsFixed(1)}%)';
      case IsolateResultKind.done:
        return 'IsolateResult.done($jobId)';
      case IsolateResultKind.error:
        return 'IsolateResult.error($jobId, $error)';
      case IsolateResultKind.log:
        return 'IsolateResult.log($jobId, $value)';
    }
  }
}

enum IsolateResultKind { progress, done, error, log }

/// Per-job cancel handle. [cancel] asks the pool to abort the job: queued
/// jobs are dropped immediately; running jobs receive a best-effort cancel
/// notice (long-running native calls may not be interruptible).
class IsolateJobHandle {
  final String jobId;
  final Stream<IsolateResult> results;
  final void Function(String jobId) _onCancel;

  IsolateJobHandle._({
    required this.jobId,
    required this.results,
    required void Function(String jobId) onCancel,
  }) : _onCancel = onCancel;

  /// Ask the pool to abort this job (best-effort).
  void cancel() => _onCancel(jobId);

  /// Releases main-side resources for the handle. Safe to call twice.
  Future<void> dispose() async {}
}

/// Long-lived worker isolate abstraction. Created once per isolate inside
/// the pool; routes jobs and forwards their results back to the pool.
class _Worker {
  _Worker(this.id);

  final int id;
  late final Isolate _isolate;
  late final ReceivePort _receivePort;

  /// Broadcast bridge for worker messages. The raw ReceivePort is a
  /// single-subscription stream — the original implementation consumed it
  /// with `.first` in [start] and then tried to `listen()` again in routing,
  /// which throws `StateError: Stream has already been listened to` on the
  /// very first job. Routing listens on this broadcast stream instead.
  final StreamController<dynamic> _messages =
      StreamController<dynamic>.broadcast();

  SendPort? _sendPort;
  final _ready = Completer<void>();

  bool _busy = false;
  bool get isBusy => _busy;

  Future<void> get ready => _ready.future;

  Stream<dynamic> get messages => _messages.stream;

  Future<void> start() async {
    _receivePort = ReceivePort();
    _receivePort.listen((message) {
      if (_sendPort == null) {
        // First message must be the worker's SendPort handshake.
        if (message is SendPort) {
          _sendPort = message;
          _ready.complete();
        } else {
          _ready.completeError(
              StateError('Worker isolate did not hand back a SendPort'));
        }
        return;
      }
      _messages.add(message);
    }, onDone: _messages.close);
    _isolate = await Isolate.spawn(_workerMain, _receivePort.sendPort);
    await _ready.future;
  }

  void run(IsolateJob<dynamic> job) {
    if (_busy) {
      throw StateError('Worker $id is already running a job');
    }
    _busy = true;
    _sendPort!.send(_WorkerEnvelope(job: job));
  }

  /// Best-effort cancel notice for a job this worker is running. The worker
  /// drops the job's final result when it sees the notice.
  void sendCancelNotice(String jobId) =>
      _sendPort?.send(_CancelNotice(jobId));

  void markIdle() => _busy = false;

  Future<void> dispose() async {
    _sendPort?.send(const _WorkerShutdown());
    _receivePort.close();
    await _messages.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

class _WorkerEnvelope {
  final IsolateJob<dynamic> job;
  const _WorkerEnvelope({required this.job});
}

class _WorkerShutdown {
  const _WorkerShutdown();
}

/// Sent main → worker over the worker's own message channel: the main
/// isolate gave up on [jobId]; the worker should drop its final result.
class _CancelNotice {
  final String jobId;
  const _CancelNotice(this.jobId);
}

/// Top-level isolate entry. Sets up a ReceivePort, hands its SendPort back
/// to the main isolate, then enters a loop waiting for [_WorkerEnvelope]s.
void _workerMain(SendPort mainPort) {
  final receivePort = ReceivePort();
  mainPort.send(receivePort.sendPort);

  // Job ids the main isolate has given up on. The worker cannot be
  // interrupted mid-entry, so cancellation is cooperative: the final
  // result of a cancelled job is simply not sent back.
  final cancelledJobs = <String>{};

  receivePort.listen((message) async {
    if (message is _WorkerShutdown) {
      receivePort.close();
      Isolate.exit(); // never returns
    }
    if (message is _CancelNotice) {
      cancelledJobs.add(message.jobId);
      return;
    }
    if (message is! _WorkerEnvelope) return;

    final job = message.job;
    try {
      await job.entry(job.payload, mainPort);
      if (cancelledJobs.remove(job.id)) {
        // Worker completed its side but the main isolate already gave up
        // — drop the final result.
        return;
      }
      mainPort.send(IsolateResult.done(jobId: job.id));
    } catch (e, st) {
      if (cancelledJobs.remove(job.id)) return;
      mainPort.send(IsolateResult.error(
        jobId: job.id,
        error: e.toString(),
        stackTrace: st.toString(),
      ));
    }
  });
}

/// A pool of [size] worker isolates, ready to run [IsolateJob]s concurrently.
///
/// The pool maintains a queue: jobs submitted when every worker is busy
/// are buffered and dispatched in FIFO order as workers become idle.
class IsolatePool {
  IsolatePool({this.size = 6}) : assert(size > 0);

  final int size;
  final List<_Worker> _workers = [];
  final _queue = <_QueuedJob>[];
  final _results = StreamController<IsolateResult>.broadcast();
  final _jobHandles = <String, IsolateJobHandle>{};

  /// Job id → worker currently executing it (for cancel routing).
  final _runningWorkers = <String, _Worker>{};

  bool _disposed = false;
  int _nextWorkerId = 0;

  /// Stream of every [IsolateResult] from every job across the pool.
  /// Filter by [IsolateResult.jobId] to follow a specific job.
  Stream<IsolateResult> get results => _results.stream;

  /// Number of jobs currently being executed.
  int get activeCount =>
      _workers.where((w) => w.isBusy).length;

  /// Number of jobs queued waiting for a worker.
  int get queuedCount => _queue.length;

  /// Number of workers in the pool.
  int get workerCount => _workers.length;

  /// Spin up the worker isolates. Must be called before [submit].
  Future<void> start() async {
    if (_disposed) {
      throw StateError('IsolatePool has been disposed');
    }
    if (_workers.isNotEmpty) return;
    for (var i = 0; i < size; i++) {
      final worker = _Worker(_nextWorkerId++);
      await worker.start();
      _workers.add(worker);
    }
    _pumpQueue();
  }

  /// Submit [job] for execution. Returns a handle that exposes the result
  /// stream and a cancellation method.
  IsolateJobHandle submit<T>(IsolateJob<T> job) {
    if (_disposed) {
      throw StateError('IsolatePool has been disposed');
    }
    final resultsController = StreamController<IsolateResult>.broadcast();
    final sub = _results.stream
        .where((r) => r.jobId == job.id)
        .listen(
          resultsController.add,
          onError: resultsController.addError,
          onDone: resultsController.close,
        );
    final handle = IsolateJobHandle._(
      jobId: job.id,
      results: resultsController.stream,
      onCancel: _onJobCancelled,
    );
    _jobHandles[job.id] = handle;
    _queue.add(_QueuedJob(job: job));
    // Auto-cleanup once the job is done or errored.
    resultsController.stream.listen(
      (event) {
        if (event.kind == IsolateResultKind.done ||
            event.kind == IsolateResultKind.error) {
          sub.cancel();
          resultsController.close();
          _jobHandles.remove(job.id);
          _runningWorkers.remove(job.id);
        }
      },
    );
    _pumpQueue();
    return handle;
  }

  /// Cancel a running (or queued) job. Returns true if the job was found
  /// and signalled.
  bool cancel(String jobId) {
    final known = _jobHandles.containsKey(jobId) ||
        _queue.any((q) => q.job.id == jobId);
    if (!known) return false;
    _onJobCancelled(jobId);
    return true;
  }

  /// Internal cancel routing: queued jobs are dropped and completed with a
  /// synthetic `done('cancelled')` result; running jobs get a best-effort
  /// cancel notice forwarded to their worker.
  void _onJobCancelled(String jobId) {
    final queuedIdx = _queue.indexWhere((q) => q.job.id == jobId);
    if (queuedIdx >= 0) {
      _queue.removeAt(queuedIdx);
      _runningWorkers.remove(jobId);
      _results.add(IsolateResult.done(jobId: jobId, value: 'cancelled'));
      return;
    }
    _runningWorkers[jobId]?.sendCancelNotice(jobId);
  }

  void _pumpQueue() {
    if (_queue.isEmpty) return;
    final idle = _workers.where((w) => !w.isBusy).toList();
    for (final worker in idle) {
      if (_queue.isEmpty) break;
      final next = _queue.removeAt(0);
      _runningWorkers[next.job.id] = worker;
      worker.run(next.job);
      _routeResultsFor(worker, next.job.id);
    }
  }

  void _routeResultsFor(_Worker worker, String jobId) {
    StreamSubscription<dynamic>? sub;
    sub = worker.messages.listen((message) {
      if (message is! IsolateResult) return;
      if (message.jobId != jobId) return;
      _results.add(message);
      if (message.kind == IsolateResultKind.done ||
          message.kind == IsolateResultKind.error) {
        worker.markIdle();
        _runningWorkers.remove(jobId);
        sub?.cancel();
        // Schedule on the next microtask so the queue pump sees the freed
        // worker.
        scheduleMicrotask(_pumpQueue);
      }
    });
  }

  /// Shut down the pool, releasing every worker isolate. After [dispose]
  /// is called the pool must not be used again.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final handle in _jobHandles.values) {
      await handle.dispose();
    }
    _jobHandles.clear();
    _queue.clear();
    for (final worker in _workers) {
      await worker.dispose();
    }
    _workers.clear();
    await _results.close();
  }
}

class _QueuedJob {
  final IsolateJob<dynamic> job;
  const _QueuedJob({required this.job});
}

/// Helper that wraps a plain callback into an [IsolateJob]. Useful when
/// the caller doesn't want to define a top-level function just for one
/// invocation — the closure is captured by the [entry] thunk.
///
/// Note: the closure must not capture any objects that can't cross the
/// isolate boundary (i.e. no `SendPort`-only types, no live pointers into
/// the main isolate's heap). Primitives, `Map`s, `List`s, `Uint8List`s,
/// and `String`s are all safe.
IsolateJob<T> jobFromCallback<T>(
  String id,
  T payload,
  Future<void> Function(T payload, SendPort sendPort) callback,
) =>
    IsolateJob<T>(id: id, payload: payload, entry: callback);

/// Pre-cast helper for the common case where the worker's payload is a
/// `Map<String, dynamic>` describing a download request.
typedef DownloadPayload = Map<String, dynamic>;

/// Encode a typed [Uint8List] so it can be shipped across the isolate
/// boundary without copy where possible. Returns the same buffer the
/// caller passed in; the helper exists purely for symmetry with
/// [decodeBytes].
Uint8List encodeBytes(Uint8List bytes) => bytes;

/// Inverse of [encodeBytes].
Uint8List decodeBytes(Object? value) {
  if (value is Uint8List) return value;
  if (value is List<int>) return Uint8List.fromList(value);
  throw ArgumentError('Cannot decode $value as Uint8List');
}

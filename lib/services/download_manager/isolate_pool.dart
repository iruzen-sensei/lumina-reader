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
    required double progress,
    this.bytesProcessed,
    this.bytesTotal,
  })  : kind = IsolateResultKind.progress,
        this.progress = progress,
        value = null,
        error = null,
        stackTrace = null;

  const IsolateResult.done({
    required this.jobId,
    Object? value,
  })  : kind = IsolateResultKind.done,
        progress = null,
        bytesProcessed = null,
        bytesTotal = null,
        this.value = value,
        error = null,
        stackTrace = null;

  const IsolateResult.error({
    required this.jobId,
    required String error,
    String? stackTrace,
  })  : kind = IsolateResultKind.error,
        progress = null,
        bytesProcessed = null,
        bytesTotal = null,
        value = null,
        this.error = error,
        this.stackTrace = stackTrace;

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

/// Per-job cancel handle. Pass [cancelPort] to the worker so it can poll
/// for cancellation; the main isolate uses [cancel] to signal.
class IsolateJobHandle {
  final String jobId;
  final Stream<IsolateResult> results;
  final ReceivePort _cancelReceivePort;

  IsolateJobHandle._({
    required this.jobId,
    required this.results,
    required ReceivePort cancelReceivePort,
  }) : _cancelReceivePort = cancelReceivePort;

  /// Ask the worker to abort. The worker is expected to honour this on a
  /// best-effort basis — long-running native calls may not be interruptible.
  void cancel() {
    _cancelReceivePort.sendPort.send(const _CancelSignal());
  }

  Future<void> dispose() async {
    _cancelReceivePort.close();
  }
}

class _CancelSignal {
  const _CancelSignal();
}

/// Long-lived worker isolate abstraction. Created once per isolate inside
/// the pool; routes jobs and forwards their results back to the pool.
class _Worker {
  _Worker(this.id);

  final int id;
  late final Isolate _isolate;
  late final SendPort _sendPort;
  late final ReceivePort _receivePort;
  final _ready = Completer<void>();

  bool _busy = false;
  bool get isBusy => _busy;

  Future<void> get ready => _ready.future;

  Future<void> start() async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_workerMain, _receivePort.sendPort);
    // First message is the worker's SendPort.
    final first = await _receivePort.first;
    if (first is! SendPort) {
      throw StateError('Worker isolate did not hand back a SendPort');
    }
    _sendPort = first;
    _ready.complete();
  }

  void run(IsolateJob<dynamic> job) {
    if (_busy) {
      throw StateError('Worker $id is already running a job');
    }
    _busy = true;
    _sendPort.send(_WorkerEnvelope(job: job, cancelPort: null));
  }

  void runWithCancelPort(IsolateJob<dynamic> job, SendPort cancelPort) {
    if (_busy) {
      throw StateError('Worker $id is already running a job');
    }
    _busy = true;
    _sendPort.send(_WorkerEnvelope(job: job, cancelPort: cancelPort));
  }

  void markIdle() => _busy = false;

  Future<void> dispose() async {
    _sendPort.send(const _WorkerShutdown());
    _receivePort.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

class _WorkerEnvelope {
  final IsolateJob<dynamic> job;
  final SendPort? cancelPort;
  const _WorkerEnvelope({required this.job, required this.cancelPort});
}

class _WorkerShutdown {
  const _WorkerShutdown();
}

/// Top-level isolate entry. Sets up a ReceivePort, hands its SendPort back
/// to the main isolate, then enters a loop waiting for [_WorkerEnvelope]s.
void _workerMain(SendPort mainPort) {
  final receivePort = ReceivePort();
  mainPort.send(receivePort.sendPort);

  receivePort.listen((message) async {
    if (message is _WorkerShutdown) {
      receivePort.close();
      Isolate.exit();
      return;
    }
    if (message is! _WorkerEnvelope) return;

    final envelope = message;
    final job = envelope.job;
    final cancelPort = envelope.cancelPort;

    StreamSubscription? cancelSub;
    var cancelled = false;
    if (cancelPort != null) {
      cancelSub = cancelPort.asBroadcastStream().listen((_) {
        cancelled = true;
      });
    }

    try {
      await job.entry(job.payload, mainPort);
      if (cancelled) {
        // Worker completed its side but the main isolate already gave up
        // — drop the final result.
        return;
      }
      mainPort.send(IsolateResult.done(jobId: job.id));
    } catch (e, st) {
      mainPort.send(IsolateResult.error(
        jobId: job.id,
        error: e.toString(),
        stackTrace: st.toString(),
      ));
    } finally {
      await cancelSub?.cancel();
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
    final cancelPort = ReceivePort();
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
      cancelReceivePort: cancelPort,
    );
    _jobHandles[job.id] = handle;
    _queue.add(_QueuedJob(job: job, cancelPort: cancelPort.sendPort));
    // Auto-cleanup once the job is done or errored.
    resultsController.stream.listen(
      (event) {
        if (event.kind == IsolateResultKind.done ||
            event.kind == IsolateResultKind.error) {
          sub.cancel();
          _jobHandles.remove(job.id);
        }
      },
    );
    _pumpQueue();
    return handle;
  }

  /// Cancel a running (or queued) job. Returns true if the job was found
  /// and signalled.
  bool cancel(String jobId) {
    // First, check if it's still queued.
    final queuedIdx = _queue.indexWhere((q) => q.job.id == jobId);
    if (queuedIdx >= 0) {
      final queued = _queue.removeAt(queuedIdx);
      _results.add(IsolateResult.done(jobId: jobId, value: 'cancelled'));
      queued.cancelPort.send(const _CancelSignal());
      return true;
    }
    final handle = _jobHandles[jobId];
    if (handle == null) return false;
    handle.cancel();
    return true;
  }

  void _pumpQueue() {
    if (_queue.isEmpty) return;
    final idle = _workers.where((w) => !w.isBusy).toList();
    for (final worker in idle) {
      if (_queue.isEmpty) break;
      final next = _queue.removeAt(0);
      worker.runWithCancelPort(next.job, next.cancelPort);
      _routeResultsFor(worker, next.job.id);
    }
  }

  void _routeResultsFor(_Worker worker, String jobId) {
    final sub = worker._receivePort.listen((message) {
      if (message is! IsolateResult) return;
      _results.add(message);
      if (message.kind == IsolateResultKind.done ||
          message.kind == IsolateResultKind.error) {
        worker.markIdle();
        sub.cancel();
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
  final SendPort cancelPort;
  const _QueuedJob({required this.job, required this.cancelPort});
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

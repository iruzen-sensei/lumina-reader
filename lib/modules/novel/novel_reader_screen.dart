// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart' as data;
import 'novel_reader_view.dart';

/// Novel reader entry point. Receives a chapter id (deep-linkable from
/// history), resolves its parent novel and opens the real [NovelReaderView].
class NovelReaderScreen extends ConsumerStatefulWidget {
  const NovelReaderScreen({super.key, required this.id});

  final int id;

  @override
  ConsumerState<NovelReaderScreen> createState() => _NovelReaderScreenState();
}

class _NovelReaderScreenState extends ConsumerState<NovelReaderScreen> {
  int? _novelId;
  int? _chapterId;
  String _title = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final (manga, chapter) = await ref
        .read(data.libraryRepositoryProvider)
        .resolveChapter(widget.id);
    if (!mounted) return;
    setState(() {
      _novelId = manga?.id;
      _chapterId = chapter?.id;
      _title = manga?.title ?? '';
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final novelId = _novelId;
    if (novelId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Novel')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_stories_outlined, size: 56),
              const SizedBox(height: 12),
              Text(
                'This chapter is no longer in your library.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }
    return NovelReaderView(novelId: novelId, initialChapterId: _chapterId);
  }
}

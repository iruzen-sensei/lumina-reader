// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart' as data;
import 'epub_reader_view.dart';

/// EPUB reader entry point. Receives a library item id, resolves its stored
/// file path from the database and hands it to the real [EpubReaderView].
class EpubReaderScreen extends ConsumerStatefulWidget {
  const EpubReaderScreen({super.key, required this.id});

  final int id;

  @override
  ConsumerState<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends ConsumerState<EpubReaderScreen> {
  String? _path;
  String _title = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final manga =
        await ref.read(data.libraryRepositoryProvider).getManga(widget.id);
    if (!mounted) return;
    setState(() {
      _path = manga == null ? null : _epubPathFor(manga.url);
      _title = manga?.title ?? '';
      _loaded = true;
    });
  }

  /// The mapper stores the imported file path in `url` for book items;
  /// tolerate both plain paths and `file://` URIs.
  String? _epubPathFor(String url) {
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri != null && uri.scheme == 'file') {
      return uri.toFilePath();
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final path = _path;
    if (path == null) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.menu_book_outlined, size: 56),
              const SizedBox(height: 12),
              Text(
                'The original file for "$_title" is no longer available.\n'
                'Re-import it from the Library.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }
    return EpubReaderView(path: path, title: _title, mangaId: widget.id);
  }
}

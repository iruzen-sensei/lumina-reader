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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart' as data;
import 'cbz_reader_view.dart';

/// CBZ / comic-zip reader entry point. Receives a library item id, resolves
/// its stored file path from the database and hands it to [CbzReaderView].
///
/// CBZ files are imported through the Library "Import" button alongside
/// EPUB/PDF; before this reader existed they landed on the generic detail
/// screen with no chapters and no way to open the content.
class CbzReaderScreen extends ConsumerStatefulWidget {
  const CbzReaderScreen({super.key, required this.id});

  final int id;

  @override
  ConsumerState<CbzReaderScreen> createState() => _CbzReaderScreenState();
}

class _CbzReaderScreenState extends ConsumerState<CbzReaderScreen> {
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
      _path = manga == null ? null : _cbzPathFor(manga.url);
      _title = manga?.title ?? '';
      _loaded = true;
    });
  }

  /// The mapper stores the imported file path in `url` for book items;
  /// tolerate both plain paths and `file://` URIs.
  String? _cbzPathFor(String url) {
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
              const Icon(Icons.photo_library_outlined, size: 56),
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
    return CbzReaderView(path: path, title: _title, mangaId: widget.id);
  }
}

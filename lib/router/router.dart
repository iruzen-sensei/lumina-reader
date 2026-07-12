// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'router.g.dart';

@riverpod
GoRouter router(RouterRef ref) {
  return GoRouter(
    initialLocation: '/library',
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainScreen(child: child),
        routes: [
          // Library (manga + novels + books)
          GoRoute(
            path: '/library',
            name: 'library',
            builder: (context, state) => const LibraryScreen(),
          ),
          // Anime Library (separate tab)
          GoRoute(
            path: '/anime',
            name: 'animeLibrary',
            builder: (context, state) => const AnimeLibraryScreen(),
          ),
          // Browse (all sources — manga + anime + novels)
          GoRoute(
            path: '/browse',
            name: 'browse',
            builder: (context, state) => const BrowseScreen(),
          ),
          // Downloads (manga + anime)
          GoRoute(
            path: '/downloads',
            name: 'downloads',
            builder: (context, state) => const DownloadsScreen(),
          ),
          // More (history, updates, stats, notes, calendar, settings)
          GoRoute(
            path: '/more',
            name: 'more',
            builder: (context, state) => const MoreScreen(),
          ),
        ],
      ),
      // Manga/Novel/Book detail
      GoRoute(
        path: '/mangaDetail/:id',
        name: 'mangaDetail',
        builder: (context, state) =>
            MangaDetailScreen(id: int.parse(state.pathParameters['id']!)),
      ),
      // Anime detail
      GoRoute(
        path: '/animeDetail/:id',
        name: 'animeDetail',
        builder: (context, state) =>
            AnimeDetailScreen(id: int.parse(state.pathParameters['id']!)),
      ),
      // Manga reader
      GoRoute(
        path: '/reader/:chapterId',
        name: 'reader',
        builder: (context, state) =>
            ReaderScreen(id: int.parse(state.pathParameters['chapterId']!)),
      ),
      // Novel reader
      GoRoute(
        path: '/novelReader/:chapterId',
        name: 'novelReader',
        builder: (context, state) =>
            NovelReaderScreen(id: int.parse(state.pathParameters['chapterId']!)),
      ),
      // EPUB reader
      GoRoute(
        path: '/epubReader/:mangaId',
        name: 'epubReader',
        builder: (context, state) =>
            EpubReaderScreen(id: int.parse(state.pathParameters['mangaId']!)),
      ),
      // PDF reader
      GoRoute(
        path: '/pdfReader/:mangaId',
        name: 'pdfReader',
        builder: (context, state) =>
            PdfReaderScreen(id: int.parse(state.pathParameters['mangaId']!)),
      ),
      // Anime player
      GoRoute(
        path: '/animePlayer/:episodeId',
        name: 'animePlayer',
        builder: (context, state) =>
            AnimePlayerScreen(id: int.parse(state.pathParameters['episodeId']!)),
      ),
      // Calendar (anime airing schedule)
      GoRoute(
        path: '/calendar',
        name: 'calendar',
        builder: (context, state) => const CalendarScreen(),
      ),
      // Stats
      GoRoute(
        path: '/stats',
        name: 'stats',
        builder: (context, state) => const StatsScreen(),
      ),
      // Notes
      GoRoute(
        path: '/notes',
        name: 'notes',
        builder: (context, state) => const NotesScreen(),
      ),
      // History
      GoRoute(
        path: '/history',
        name: 'history',
        builder: (context, state) => const HistoryScreen(),
      ),
      // Updates
      GoRoute(
        path: '/updates',
        name: 'updates',
        builder: (context, state) => const UpdatesScreen(),
      ),
      // Settings
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}

// Placeholder imports
import 'package:flutter/material.dart';
import '../modules/main_view/main_screen.dart';
import '../modules/library/library_screen.dart';
import '../modules/anime_library/anime_library_screen.dart';
import '../modules/browse/browse_screen.dart';
import '../modules/downloads/downloads_screen.dart';
import '../modules/history/history_screen.dart';
import '../modules/updates/updates_screen.dart';
import '../modules/stats/stats_screen.dart';
import '../modules/notes/notes_screen.dart';
import '../modules/calendar/calendar_screen.dart';
import '../modules/more/more_screen.dart';
import '../modules/manga/manga_detail_screen.dart';
import '../modules/anime/anime_detail_screen.dart';
import '../modules/manga/reader/reader_screen.dart';
import '../modules/novel/novel_reader_screen.dart';
import '../modules/epub/epub_reader_screen.dart';
import '../modules/pdf/pdf_reader_screen.dart';
import '../modules/anime/player/anime_player_screen.dart';
import '../modules/more/settings/settings_screen.dart';

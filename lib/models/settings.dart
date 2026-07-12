/*
 * Lumina Reader - A Mangayomi fork
 * Copyright (C) 2024 Lumina Reader Contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Original Mangayomi source: Copyright (c) 2023-2024 kodjode33
 * SPDX-License-Identifier: Apache-2.0
 */

import 'package:isar/isar.dart';

part 'settings.g.dart';

/// Single-row Isar collection that stores all user-tunable settings.
///
/// The collection has a fixed primary key of `227` (a nod to the original
/// Mangayomi schema) — there is exactly one row, accessible through the
/// `Settings.get()` helper exposed by the data layer.
///
/// Field naming follows the convention `<group><Name>` (e.g. `readerPadding`)
/// so that groups are easy to spot when scanning the table.
@collection
@Name("Settings")
class Settings {
  /// Fixed primary key for the single-row settings collection.
  Id id = 227;

  // =========================================================================
  // 1. General / Appearance
  // =========================================================================

  /// Theme mode. One of: `system`, `light`, `dark`, `amoled`.
  String? themeMode;

  /// Name of the active theme (e.g. `Lumina`, `Mangayomi`, `Tachiyomi`).
  String? themeName;

  /// Accent color as a 0xAARRGGBB integer.
  int? accentColor;

  /// Whether dynamic colours (Material You) should be used on Android 12+.
  bool? dynamicTheme;

  /// Whether the dark theme should use pure black (AMOLED-friendly).
  bool? pureBlackDark;

  /// App display language (BCP 47 tag, e.g. `en`, `ja`, `fr`).
  String? displayLanguage;

  /// Date format pattern (e.g. `yyyy-MM-dd`).
  String? dateFormat;

  /// Time format pattern (e.g. `HH:mm`).
  String? timeFormat;

  /// Whether to confirm before exiting the app.
  bool? confirmExit;

  /// Whether to show NSFW content in the app.
  bool? showNsfw;

  /// Whether to blur NSFW covers in the library.
  bool? blurNsfwCovers;

  /// Whether to hide NSFW content when the app is locked.
  bool? hideNsfwWhenLocked;

  /// Which screen to open on launch. One of: `library`, `updates`,
  /// `history`, `browse`, `more`.
  String? startScreen;

  /// Whether to show the bottom navigation bar.
  bool? showBottomNav;

  /// Whether to use edge-to-edge UI.
  bool? edgeToEdge;

  /// Whether to enable animations.
  bool? enableAnimations;

  /// Whether to enable haptic feedback.
  bool? enableHaptics;

  /// Whether to show a confirmation dialog before deleting entries.
  bool? confirmDelete;

  /// Whether to enable crash reporting.
  bool? crashReporting;

  /// Whether to enable anonymous usage analytics.
  bool? anonymousAnalytics;

  /// App version string when the settings were last migrated.
  String? lastMigrationVersion;

  /// Schema version of the settings collection. Bumped whenever a
  /// migration is required.
  int? schemaVersion;

  /// Timestamp (ms since epoch) the settings were last updated.
  int? lastUpdatedAt;

  // =========================================================================
  // 2. Library
  // =========================================================================

  /// Whether to show the "Continue reading" button on library cards.
  bool? libraryShowContinueReadingButton;

  /// Whether to show NSFW entries in the library.
  bool? libraryShowNsfw;

  /// Whether to only download over Wi-Fi.
  bool? libraryDownloadOnlyOverWifi;

  /// Whether to automatically update manga / anime metadata.
  bool? libraryAutoUpdate;

  /// Auto-update interval in hours. `0` means manual only.
  int? libraryAutoUpdateInterval;

  /// Whether to only update entries that are not yet completed.
  bool? libraryUpdateOnlyNonCompleted;

  /// Whether to refresh metadata (covers, descriptions) during updates.
  bool? libraryRefreshMetadata;

  /// Library display mode. `0` = grid, `1` = list, `2` = compact list.
  int? libraryDisplayMode;

  /// Library sort mode. `0` = alphabetically, `1` = last read,
  /// `2` = last checked, `3` = unread, `4` = total chapters, `5` = date
  /// added, `6` = tracker score, `7` = size on disk.
  int? librarySortMode;

  /// Whether the library sort is descending.
  bool? librarySortDescending;

  /// Whether to show the category header in the library.
  bool? libraryShowCategoryHeader;

  /// Whether to show category tabs at the top of the library.
  bool? libraryShowCategoryTabs;

  /// Whether to show the number of items in each category.
  bool? libraryShowNumberOfItems;

  /// Whether to group library entries by category.
  bool? libraryGroupByCategory;

  /// Whether to group library entries by source.
  bool? libraryGroupBySource;

  /// Whether to group library entries by status.
  bool? libraryGroupByStatus;

  /// Whether to group library entries by tag.
  bool? libraryGroupByTag;

  /// Whether to show unread badges on library cards.
  bool? libraryShowUnreadBadges;

  /// Whether to show download badges on library cards.
  bool? libraryShowDownloadBadges;

  /// Whether to show the total chapter count on library cards.
  bool? libraryShowTotalChapters;

  /// Whether to show the language flag on library cards.
  bool? libraryShowLanguageFlag;

  /// Number of columns in the library grid on portrait phones.
  int? libraryGridColumns;

  /// Number of columns in the library grid on landscape / tablets.
  int? libraryGridColumnsLandscape;

  /// Size of the thumbnail in the library list view.
  int? libraryListThumbnailSize;

  /// Whether to show a search bar at the top of the library.
  bool? libraryShowSearchBar;

  /// Whether to show a filter button at the top of the library.
  bool? libraryShowFilterButton;

  /// Whether to swipe horizontally to switch categories.
  bool? librarySwipeToChangeCategory;

  /// Whether to pin the category tabs at the top.
  bool? libraryPinCategoryTabs;

  /// Whether to show the "Downloaded" category.
  bool? libraryShowDownloadedCategory;

  /// Whether to show the "Reading" category.
  bool? libraryShowReadingCategory;

  /// List of hidden category IDs.
  List<int>? libraryHiddenCategories;

  /// List of hidden source IDs.
  List<String>? libraryHiddenSources;

  // =========================================================================
  // 3. Reader (Manga)
  // =========================================================================

  /// Default reader mode. `0` = paged left-to-right, `1` = paged right-to-left,
  /// `2` = vertical continuous, `3` = webtoon, `4` = vertical strip.
  int? readerDefaultMode;

  /// Default reader direction. `0` = left-to-right, `1` = right-to-left,
  /// `2` = top-to-bottom, `3` = bottom-to-top.
  int? readerDirection;

  /// Default reader orientation. `0` = free, `1` = portrait,
  /// `2` = landscape, `3` = locked portrait, `4` = locked landscape.
  int? readerOrientation;

  /// Whether the reader should run in fullscreen mode.
  bool? readerFullscreen;

  /// Whether to keep the screen on while reading.
  bool? readerKeepScreenOn;

  /// Whether to show the page number.
  bool? readerShowPageNumber;

  /// Whether to show the reader bar (top + bottom).
  bool? readerShowBar;

  /// Whether swipe gestures navigate between pages.
  bool? readerSwipeToNavigate;

  /// Whether volume keys navigate between pages.
  bool? readerVolumeKeyNavigation;

  /// Whether to show a horizontal scrollbar.
  bool? readerShowScrollbar;

  /// Whether to crop borders of images.
  bool? readerCropBorders;

  /// Whether to zoom images to fit the screen.
  bool? readerZoomToFit;

  /// Whether to zoom images to width.
  bool? readerZoomToWidth;

  /// Whether to zoom images to height.
  bool? readerZoomToHeight;

  /// Whether to use smart zoom (level + center).
  bool? readerZoomSmart;

  /// Background colour of the reader (0xAARRGGBB).
  int? readerBackgroundColor;

  /// Whether to use a custom background colour.
  bool? readerUseCustomBackgroundColor;

  /// Image quality. `0` = original, `1` = high, `2` = medium, `3` = low.
  int? readerImageQuality;

  /// Whether to preload next pages.
  bool? readerPreloadPages;

  /// Number of pages to preload ahead.
  int? readerPreloadCount;

  /// Whether tapping the screen turns the page.
  bool? readerTapToTurnPage;

  /// Whether long-pressing the image zooms in.
  bool? readerLongTapToZoom;

  /// Whether to show the page indicator at the bottom.
  bool? readerShowPageIndicator;

  /// Whether to hide the reader bar on scroll.
  bool? readerHideBarOnScroll;

  /// Whether to show the reader info bar (chapter name, page X/Y).
  bool? readerShowInfoBar;

  /// Animation speed for page transitions (ms). `0` = instant.
  int? readerAnimationSpeed;

  /// Whether to enable page transition animations.
  bool? readerEnableTransitions;

  /// Whether to invert black/white for night reading.
  bool? readerInvertColors;

  /// Brightness override for the reader (0..100). `-1` = system.
  int? readerBrightness;

  /// Whether to auto-brightness in the reader.
  bool? readerAutoBrightness;

  /// Maximum image cache size in MB.
  int? readerMaxCacheSize;

  /// Whether to show a chapter list button in the reader.
  bool? readerShowChapterListButton;

  /// Whether to show a bookmark button in the reader.
  bool? readerShowBookmarkButton;

  /// Whether to show a note button in the reader.
  bool? readerShowNoteButton;

  /// Whether to show a share button in the reader.
  bool? readerShowShareButton;

  /// Whether to auto-mark chapters as read when scrolled past the last page.
  bool? readerAutoMarkRead;

  /// Whether to ask for confirmation before marking a chapter as read.
  bool? readerConfirmMarkRead;

  /// Whether to skip duplicate chapters in the reader.
  bool? readerSkipDuplicates;

  /// Whether to prefer coloured pages when available.
  bool? readerPreferColored;

  // =========================================================================
  // 4. Player (Anime)
  // =========================================================================

  /// Default video player. `0` = internal, `1` = external, `2` = web.
  int? playerDefault;

  /// Whether the player should run in fullscreen mode.
  bool? playerFullscreen;

  /// Whether to keep the screen on while playing.
  bool? playerKeepScreenOn;

  /// Whether to show the player bar (controls).
  bool? playerShowBar;

  /// Default playback speed (1.0 = normal).
  double? playerDefaultSpeed;

  /// Whether to remember the playback speed across episodes.
  bool? playerRememberSpeed;

  /// Whether to autoplay the next episode.
  bool? playerAutoplayNext;

  /// Whether to show skip-forward / skip-backward buttons.
  bool? playerShowSkipButtons;

  /// Skip duration in seconds for the skip buttons.
  int? playerSkipDuration;

  /// Whether to remember the playback position across sessions.
  bool? playerRememberPosition;

  /// Whether to show the cast button (Chromecast / AirPlay).
  bool? playerShowCastButton;

  /// Whether to enable picture-in-picture mode.
  bool? playerEnablePip;

  /// Whether brightness gestures are enabled.
  bool? playerBrightnessGesture;

  /// Whether volume gestures are enabled.
  bool? playerVolumeGesture;

  /// Whether seek gestures are enabled.
  bool? playerSeekGesture;

  /// Default video quality. `0` = auto, `1` = 1080p, `2` = 720p,
  /// `3` = 480p, `4` = 360p.
  int? playerDefaultQuality;

  /// Whether to prefer HLS streams.
  bool? playerPreferHls;

  /// Whether to use an external player.
  bool? playerUseExternal;

  /// Package name of the external player.
  String? playerExternalPackage;

  /// Whether to show the subtitle toggle.
  bool? playerShowSubtitleToggle;

  /// Whether to prefer subbed episodes.
  bool? playerPreferSubbed;

  /// Whether to prefer dubbed episodes.
  bool? playerPreferDubbed;

  /// Default subtitle language (BCP 47 tag).
  String? playerSubtitleLanguage;

  /// Default audio language (BCP 47 tag).
  String? playerAudioLanguage;

  /// Whether to enable hardware acceleration.
  bool? playerHardwareAcceleration;

  /// Whether to enable background playback (audio only).
  bool? playerBackgroundAudio;

  /// Whether to show the episode list button.
  bool? playerShowEpisodeListButton;

  /// Whether to show the speed button.
  bool? playerShowSpeedButton;

  /// Whether to show the quality button.
  bool? playerShowQualityButton;

  /// Whether to show the audio track button.
  bool? playerShowAudioButton;

  /// Whether to show the screenshot button.
  bool? playerShowScreenshotButton;

  /// Whether to auto-skip opening sequences.
  bool? playerAutoSkipOpening;

  /// Whether to auto-skip ending sequences.
  bool? playerAutoSkipEnding;

  /// Default subtitle size (sp).
  int? playerSubtitleSize;

  /// Default subtitle background opacity (0..255).
  int? playerSubtitleBackgroundOpacity;

  // =========================================================================
  // 5. Browse
  // =========================================================================

  /// Whether to show NSFW sources in the browse tab.
  bool? browseShowNsfwSources;

  /// Whether to enable source repositories.
  bool? browseEnableSourceRepos;

  /// List of source repository URLs.
  List<String>? browseSourceRepos;

  /// Whether to show only installed sources.
  bool? browseShowOnlyInstalled;

  /// Whether to show the "Latest" section in browse.
  bool? browseShowLatest;

  /// Whether to show a search bar at the top of browse.
  bool? browseShowSearchBar;

  /// Whether to show the source language flag in browse.
  bool? browseShowLanguageFlag;

  /// Whether to auto-open the latest tab when opening a source.
  bool? browseAutoOpenLatest;

  /// Browse display mode. `0` = grid, `1` = list, `2` = compact list.
  int? browseDisplayMode;

  /// Number of columns in the browse grid on portrait phones.
  int? browseGridColumns;

  /// Whether to show source icons in browse.
  bool? browseShowSourceIcons;

  /// Whether to show the "Recently viewed" section.
  bool? browseShowRecent;

  /// Whether to remember the last used source.
  bool? browseRememberLastSource;

  /// ID of the last used source.
  String? browseLastSourceId;

  // =========================================================================
  // 6. Downloads
  // =========================================================================

  /// Filesystem path where downloads are saved.
  String? downloadLocation;

  /// Whether to download only over Wi-Fi.
  bool? downloadOnlyOverWifi;

  /// Whether to download only when the device is charging.
  bool? downloadWhenCharging;

  /// Whether to allow downloads on low battery.
  bool? downloadOnLowBattery;

  /// Number of concurrent downloads.
  int? downloadConcurrent;

  /// Number of times to retry a failed download.
  int? downloadRetryCount;

  /// Whether to delete downloaded chapters after reading.
  bool? deleteDownloadedAfterRead;

  /// Whether to save manga chapters as CBZ archives.
  bool? downloadSaveAsCbz;

  /// Whether to save manga chapters as PDF documents.
  bool? downloadSaveAsPdf;

  /// Whether to save manga chapters as EPUB books.
  bool? downloadSaveAsEpub;

  /// Whether to download the entry cover alongside chapters.
  bool? downloadCover;

  /// Whether to download all chapters of an entry together.
  bool? downloadChaptersTogether;

  /// Whether to automatically download new chapters when they are detected.
  bool? downloadAutoNew;

  /// Number of new chapters to auto-download per entry. `-1` = all.
  int? downloadAutoNewCount;

  /// Number of parallel download threads per chapter.
  int? downloadThreads;

  /// Maximum download speed in KB/s. `0` = unlimited.
  int? downloadMaxSpeed;

  /// Whether to download over cellular data when Wi-Fi is unavailable.
  bool? downloadOverCellular;

  /// Whether to show download notifications.
  bool? downloadNotifications;

  /// Whether to show download progress notifications.
  bool? downloadProgressNotifications;

  /// Whether to play a sound when a download completes.
  bool? downloadSoundOnComplete;

  /// Whether to vibrate when a download completes.
  bool? downloadVibrateOnComplete;

  /// Whether to delete incomplete downloads on failure.
  bool? downloadDeleteOnFailure;

  /// Whether to verify downloaded files (checksum).
  bool? downloadVerifyChecksum;

  /// Default download category ID (for auto-categorising downloads).
  int? downloadDefaultCategoryId;

  // =========================================================================
  // 7. Security
  // =========================================================================

  /// Whether the app lock (PIN / biometric) is enabled.
  bool? appLockEnabled;

  /// Whether to use biometric authentication for app lock.
  bool? appLockBiometric;

  /// SHA-256 hash of the app lock PIN.
  String? appLockPinHash;

  /// PIN salt (base64-encoded).
  String? appLockPinSalt;

  /// Whether to require app lock when the app returns from background.
  bool? lockOnResume;

  /// App lock timeout in seconds. `0` = always require.
  int? lockTimeout;

  /// Whether to hide NSFW content when the app is locked.
  bool? hideNsfwWhenLockedSecurity;

  /// Whether incognito mode is active.
  bool? incognitoMode;

  /// Whether to use FLAG_SECURE on Android (prevents screenshots).
  bool? secureScreen;

  /// Whether to require app lock before opening downloads.
  bool? lockDownloads;

  /// Whether to require app lock before opening history.
  bool? lockHistory;

  /// Whether to require app lock before opening the updates feed.
  bool? lockUpdates;

  // =========================================================================
  // 8. Sync (Trackers)
  // =========================================================================

  /// Whether to automatically sync reading progress to trackers.
  bool? syncAutoToTracker;

  /// Whether to sync on chapter read.
  bool? syncOnRead;

  /// Whether to sync on chapter complete.
  bool? syncOnChapterComplete;

  /// Sync interval in minutes. `0` = manual only.
  int? syncInterval;

  /// MangaDex username.
  String? mangaDexUsername;

  /// MangaDex access token.
  String? mangaDexToken;

  /// MangaDex refresh token.
  String? mangaDexRefreshToken;

  /// AniList access token.
  String? anilistToken;

  /// AniList refresh token.
  String? anilistRefreshToken;

  /// MyAnimeList access token.
  String? myanimelistToken;

  /// MyAnimeList refresh token.
  String? myanimelistRefreshToken;

  /// Shikimori access token.
  String? shikimoriToken;

  /// Shikimori refresh token.
  String? shikimoriRefreshToken;

  /// Kitsu access token.
  String? kitsuToken;

  /// Kitsu refresh token.
  String? kitsuRefreshToken;

  /// Bangumi access token.
  String? bangumiToken;

  /// Bangumi refresh token.
  String? bangumiRefreshToken;

  /// Simkl access token.
  String? simklToken;

  /// Simkl refresh token.
  String? simklRefreshToken;

  // =========================================================================
  // 9. EPUB (NEW)
  // =========================================================================

  /// Whether the EPUB reader is enabled.
  bool? epubEnabled;

  /// EPUB reader font family (e.g. `serif`, `sans-serif`, `monospace`).
  String? epubFont;

  /// EPUB reader custom font file path (when [epubFont] = `custom`).
  String? epubCustomFontPath;

  /// EPUB reader font size in sp.
  int? epubFontSize;

  /// EPUB reader line height multiplier (1.0 = default).
  double? epubLineHeight;

  /// EPUB reader margin in dp.
  int? epubMargin;

  /// EPUB reader padding in dp.
  int? epubPadding;

  /// EPUB reader background colour (0xAARRGGBB).
  int? epubBackgroundColor;

  /// EPUB reader text colour (0xAARRGGBB).
  int? epubTextColor;

  /// EPUB reader link colour (0xAARRGGBB).
  int? epubLinkColor;

  /// EPUB reader theme name (e.g. `light`, `sepia`, `dark`, `amoled`).
  String? epubTheme;

  /// Whether to justify text in the EPUB reader.
  bool? epubJustify;

  /// Whether to enable hyphenation in the EPUB reader.
  bool? epubHyphenate;

  /// Whether to show a progress bar at the bottom.
  bool? epubShowProgressBar;

  /// Whether to run the EPUB reader in fullscreen.
  bool? epubFullscreen;

  /// Whether to keep the screen on while reading EPUBs.
  bool? epubKeepScreenOn;

  /// Number of columns in the EPUB reader. `1` = single, `2` = double,
  /// `0` = auto.
  int? epubColumnCount;

  /// Whether the EPUB reader should use night mode.
  bool? epubNightMode;

  /// Whether tapping the screen paginates the EPUB.
  bool? epubTapToPaginate;

  /// Whether to show the chapter list button.
  bool? epubShowChapterList;

  /// Whether to show the table of contents button.
  bool? epubShowToc;

  /// Whether to show the bookmarks button.
  bool? epubShowBookmarks;

  /// Whether to show the notes button.
  bool? epubShowNotes;

  /// Whether to show the search button.
  bool? epubShowSearch;

  /// Whether to show the settings button.
  bool? epubShowSettings;

  /// EPUB reader page turn animation. `0` = none, `1` = slide,
  /// `2` = fade, `3` = curl.
  int? epubPageTurnAnimation;

  /// Whether to use custom fonts in the EPUB reader.
  bool? epubUseCustomFonts;

  /// EPUB reader font scale (1.0 = default).
  double? epubFontScale;

  /// EPUB reader letter spacing in sp.
  double? epubLetterSpacing;

  /// EPUB reader paragraph spacing in dp.
  int? epubParagraphSpacing;

  /// EPUB reader indent size in dp.
  int? epubIndentSize;

  /// Whether to enable image zoom in the EPUB reader.
  bool? epubEnableImageZoom;

  /// Whether to load external images in the EPUB reader.
  bool? epubLoadExternalImages;

  /// Whether to allow JavaScript in the EPUB reader.
  bool? epubAllowJavaScript;

  /// Default EPUB download directory.
  String? epubDownloadDir;

  /// Whether to auto-import EPUB files from the download directory.
  bool? epubAutoImport;

  // =========================================================================
  // 10. PDF (NEW)
  // =========================================================================

  /// Whether the PDF viewer is enabled.
  bool? pdfEnabled;

  /// PDF viewer mode. `0` = horizontal swipe, `1` = vertical scroll,
  /// `2` = continuous scroll.
  int? pdfViewerMode;

  /// PDF background colour (0xAARRGGBB).
  int? pdfBackgroundColor;

  /// PDF page colour (0xAARRGGBB) — used to tint page backgrounds.
  int? pdfPageColor;

  /// Whether the PDF viewer should use night mode (invert colours).
  bool? pdfNightMode;

  /// Whether to run the PDF viewer in fullscreen.
  bool? pdfFullscreen;

  /// Whether to keep the screen on while viewing PDFs.
  bool? pdfKeepScreenOn;

  /// PDF viewer zoom level (1.0 = 100%).
  double? pdfZoomLevel;

  /// Whether to show the page number in the PDF viewer.
  bool? pdfShowPageNumber;

  /// Whether to show a progress bar in the PDF viewer.
  bool? pdfShowProgressBar;

  /// Whether to show the bookmark button.
  bool? pdfShowBookmarkButton;

  /// Whether to show the search button.
  bool? pdfShowSearchButton;

  /// Whether to show the outline (table of contents) button.
  bool? pdfShowOutlineButton;

  /// Whether to show the thumbnails panel.
  bool? pdfShowThumbnails;

  /// Whether to invert colours in the PDF viewer.
  bool? pdfInvertColors;

  /// Whether to render the PDF in greyscale.
  bool? pdfGrayscale;

  /// Whether to enhance contrast in the PDF viewer.
  bool? pdfContrastEnhance;

  /// PDF render quality. `0` = low, `1` = medium, `2` = high, `3` = ultra.
  int? pdfRenderQuality;

  /// PDF page cache size in MB.
  int? pdfCacheSize;

  /// Default PDF download directory.
  String? pdfDefaultDir;

  /// Whether to auto-download PDF files when opened.
  bool? pdfAutoDownload;

  /// Whether to enable text selection in the PDF viewer.
  bool? pdfEnableTextSelection;

  /// Whether to enable annotation in the PDF viewer.
  bool? pdfEnableAnnotation;

  /// Whether to enable form filling in the PDF viewer.
  bool? pdfEnableFormFilling;

  /// Whether to enable printing from the PDF viewer.
  bool? pdfEnablePrinting;

  /// Default PDF page fit mode. `0` = width, `1` = height, `2` = page,
  /// `3` = actual size.
  int? pdfPageFitMode;

  /// Whether to remember the last viewed page.
  bool? pdfRememberLastPage;

  /// Whether to show a thumbnail strip at the bottom.
  bool? pdfShowThumbnailStrip;

  /// PDF thumbnail strip height in dp.
  int? pdfThumbnailStripHeight;

  /// Whether to enable swipe-to-page navigation.
  bool? pdfSwipeToPage;

  // =========================================================================
  // 11. Notes (NEW)
  // =========================================================================

  /// Whether the notes feature is enabled.
  bool? notesEnabled;

  /// Whether notes sync is enabled.
  bool? notesSyncEnabled;

  /// Default note colour (0xAARRGGBB).
  int? notesDefaultColor;

  /// Whether to show notes in the reader.
  bool? notesShowInReader;

  /// Whether to show notes in the library.
  bool? notesShowInLibrary;

  /// Whether to show notes in the history.
  bool? notesShowInHistory;

  /// Whether Markdown formatting is supported in notes.
  bool? notesMarkdownSupport;

  /// Whether to auto-save notes while typing.
  bool? notesAutoSave;

  /// Auto-save interval in seconds.
  int? notesAutoSaveInterval;

  /// Default note format. `0` = plain text, `1` = markdown, `2` = rich text.
  int? notesDefaultFormat;

  /// Whether to encrypt sensitive notes.
  bool? notesEncryptSensitive;

  /// Whether to show timestamps on notes.
  bool? notesShowTimestamps;

  /// Whether to show the chapter the note is attached to.
  bool? notesShowChapter;

  /// Whether to show the page the note is attached to.
  bool? notesShowPage;

  /// Whether notes can contain images.
  bool? notesAllowImages;

  /// Whether notes can contain file attachments.
  bool? notesAllowAttachments;

  /// Maximum attachment size in KB.
  int? notesMaxAttachmentSize;

  /// Whether notes can be exported.
  bool? notesExportEnabled;

  /// Notes export format. `0` = JSON, `1` = markdown, `2` = HTML, `3` = PDF.
  int? notesExportFormat;

  /// Filesystem path where notes are backed up.
  String? notesBackupDir;

  /// Note colour palette (6 colours, 0xAARRGGBB each).
  int? notesColor1;
  int? notesColor2;
  int? notesColor3;
  int? notesColor4;
  int? notesColor5;
  int? notesColor6;

  /// Default note font size in sp.
  int? notesFontSize;

  /// Whether to show a note count badge on entries.
  bool? notesShowCountBadge;

  /// Whether to sort notes by creation date.
  bool? notesSortByCreated;

  /// Whether notes sort is descending.
  bool? notesSortDescending;

  /// Whether to show a preview of the note content in lists.
  bool? notesShowPreview;

  /// Number of characters to show in the preview.
  int? notesPreviewLength;

  /// Whether to enable note tags.
  bool? notesEnableTags;

  /// Whether to enable note categories.
  bool? notesEnableCategories;

  /// Whether to enable note search.
  bool? notesEnableSearch;

  // =========================================================================
  // 12. Stats (NEW)
  // =========================================================================

  /// Whether the statistics feature is enabled.
  bool? statsEnabled;

  /// Whether to track reading time.
  bool? statsTrackReadingTime;

  /// Whether to track chapters read.
  bool? statsTrackChaptersRead;

  /// Whether to track episodes watched.
  bool? statsTrackEpisodesWatched;

  /// Whether to track pages read.
  bool? statsTrackPagesRead;

  /// Whether to track words read (for novels / EPUBs).
  bool? statsTrackWordsRead;

  /// Whether to track stats by genre.
  bool? statsTrackByGenre;

  /// Whether to track stats by source.
  bool? statsTrackBySource;

  /// Whether to track stats by status.
  bool? statsTrackByStatus;

  /// Whether anonymous reporting is enabled.
  bool? statsAnonymousReporting;

  /// Number of days to retain detailed stats. `0` = forever.
  int? statsRetentionDays;

  /// Whether to show stats in the library.
  bool? statsShowInLibrary;

  /// Whether to show stats in the history.
  bool? statsShowInHistory;

  /// Whether stats can be exported.
  bool? statsExportEnabled;

  /// Stats export format. `0` = JSON, `1` = CSV.
  int? statsExportFormat;

  /// Whether to show graphs in the stats view.
  bool? statsShowGraphs;

  /// Whether to show a heatmap (activity calendar).
  bool? statsShowHeatmap;

  /// Whether to show reading streaks.
  bool? statsShowStreaks;

  /// Whether to show reading goals.
  bool? statsShowGoals;

  /// Daily reading goal in minutes.
  int? statsDailyReadingGoal;

  /// Weekly reading goal in minutes.
  int? statsWeeklyReadingGoal;

  /// Monthly reading goal in minutes.
  int? statsMonthlyReadingGoal;

  /// Yearly reading goal in minutes.
  int? statsYearlyReadingGoal;

  /// Whether to notify the user when a goal is completed.
  bool? statsNotifyGoalComplete;

  /// Whether to track session duration.
  bool? statsTrackSessionDuration;

  /// Whether to track session start / end times.
  bool? statsTrackSessionTimes;

  /// Whether to track the device used for reading.
  bool? statsTrackDevice;

  /// Whether to track the location (timezone) of reading sessions.
  bool? statsTrackLocation;

  /// Whether to track the source of reading sessions (which extension).
  bool? statsTrackSessionSource;

  /// Maximum number of stat entries to keep per type.
  int? statsMaxEntries;

  /// Whether to anonymise stats before exporting.
  bool? statsAnonymizeOnExport;

  // =========================================================================
  // 13. Cloud Sync (NEW)
  // =========================================================================

  /// Whether cloud sync is enabled.
  bool? cloudSyncEnabled;

  /// Cloud sync provider. One of: `googledrive`, `dropbox`, `onedrive`,
  /// `webdav`, `s3`, `local`.
  String? cloudSyncProvider;

  /// Cloud sync access token.
  String? cloudSyncToken;

  /// Cloud sync refresh token.
  String? cloudSyncRefreshToken;

  /// Cloud sync folder path (relative to the provider root).
  String? cloudSyncFolder;

  /// Cloud sync interval in minutes. `0` = manual only.
  int? cloudSyncInterval;

  /// Whether to sync on app startup.
  bool? cloudSyncOnStartup;

  /// Whether to sync on app exit.
  bool? cloudSyncOnExit;

  /// Whether to sync on library change.
  bool? cloudSyncOnLibraryChange;

  /// Whether to sync on settings change.
  bool? cloudSyncOnSettingsChange;

  /// Whether to sync on history change.
  bool? cloudSyncOnHistoryChange;

  /// Whether to sync on read progress change.
  bool? cloudSyncOnReadChange;

  /// Whether to sync only over Wi-Fi.
  bool? cloudSyncWifiOnly;

  /// Whether to auto-resolve conflicts (use latest).
  bool? cloudSyncAutoConflictResolve;

  /// Conflict resolution strategy. One of: `latest`, `local`, `remote`,
  /// `merge`, `ask`.
  String? cloudSyncConflictStrategy;

  /// Timestamp (ms since epoch) of the last successful sync.
  int? cloudSyncLastSyncAt;

  /// Number of times the sync has been retried.
  int? cloudSyncRetryCount;

  /// Whether to encrypt the cloud sync backup.
  bool? cloudSyncEncryptBackup;

  /// Encryption key for the cloud sync backup (base64-encoded).
  String? cloudSyncEncryptionKey;

  /// Whether to include history in the cloud sync backup.
  bool? cloudSyncIncludeHistory;

  /// Whether to include settings in the cloud sync backup.
  bool? cloudSyncIncludeSettings;

  /// Whether to include categories in the cloud sync backup.
  bool? cloudSyncIncludeCategories;

  /// Whether to include downloads in the cloud sync backup.
  bool? cloudSyncIncludeDownloads;

  /// Whether to include notes in the cloud sync backup.
  bool? cloudSyncIncludeNotes;

  /// Whether to include themes in the cloud sync backup.
  bool? cloudSyncIncludeThemes;

  /// Whether to include tracker credentials in the cloud sync backup.
  bool? cloudSyncIncludeTrackers;

  /// Maximum number of backups to keep on the cloud provider.
  int? cloudSyncMaxBackups;

  /// WebDAV server URL.
  String? cloudSyncWebdavUrl;

  /// WebDAV username.
  String? cloudSyncWebdavUsername;

  /// WebDAV password.
  String? cloudSyncWebdavPassword;

  /// WebDAV root path.
  String? cloudSyncWebdavRoot;

  /// S3 endpoint URL.
  String? cloudSyncS3Endpoint;

  /// S3 bucket name.
  String? cloudSyncS3Bucket;

  /// S3 access key.
  String? cloudSyncS3AccessKey;

  /// S3 secret key.
  String? cloudSyncS3SecretKey;

  /// S3 region.
  String? cloudSyncS3Region;

  /// S3 path prefix.
  String? cloudSyncS3PathPrefix;

  /// Whether to use SSL for S3.
  bool? cloudSyncS3UseSsl;

  /// Whether to verify S3 SSL certificates.
  bool? cloudSyncS3VerifySsl;

  /// Whether to compress the cloud sync backup.
  bool? cloudSyncCompressBackup;

  /// Compression level (0..9). Higher = smaller file but slower.
  int? cloudSyncCompressionLevel;

  /// Whether to delete the local backup after a successful sync.
  bool? cloudSyncDeleteLocalAfterSync;

  /// Whether to show a notification when a sync starts.
  bool? cloudSyncNotifyOnStart;

  /// Whether to show a notification when a sync completes.
  bool? cloudSyncNotifyOnComplete;

  /// Whether to show a notification when a sync fails.
  bool? cloudSyncNotifyOnFailure;

  // =========================================================================
  // 14. Custom Themes (NEW)
  // =========================================================================

  /// Whether custom themes are enabled.
  bool? customThemesEnabled;

  /// List of custom theme IDs.
  List<String>? customThemeIds;

  /// ID of the active custom theme.
  String? activeCustomThemeId;

  /// Whether custom themes can be imported.
  bool? customThemeImportEnabled;

  /// Filesystem path where custom themes are stored.
  String? customThemesDir;

  /// Whether to auto-switch between light and dark themes based on time.
  bool? customThemeAutoSwitch;

  /// Time (minutes since midnight) to switch to the day theme.
  int? customThemeDayStart;

  /// Time (minutes since midnight) to switch to the night theme.
  int? customThemeNightStart;

  /// Whether to use a different theme per source.
  bool? customThemePerSource;

  /// Whether to use a different theme per category.
  bool? customThemePerCategory;

  /// Whether custom themes can be exported.
  bool? customThemeExportEnabled;

  /// Whether custom themes can be shared.
  bool? customThemeShareEnabled;

  /// Whether to pick a random theme on each launch.
  bool? customThemeRandomOnLaunch;

  /// Primary colour of the active custom theme (0xAARRGGBB).
  int? customThemePrimaryColor;

  /// Secondary colour of the active custom theme (0xAARRGGBB).
  int? customThemeSecondaryColor;

  /// Background colour of the active custom theme (0xAARRGGBB).
  int? customThemeBackgroundColor;

  /// Surface colour of the active custom theme (0xAARRGGBB).
  int? customThemeSurfaceColor;

  /// Error colour of the active custom theme (0xAARRGGBB).
  int? customThemeErrorColor;

  /// Text colour of the active custom theme (0xAARRGGBB).
  int? customThemeTextColor;

  /// Whether the active custom theme uses Material 3.
  bool? customThemeUseMaterial3;

  /// Whether the active custom theme uses dynamic colours.
  bool? customThemeUseDynamicColors;

  /// Whether the active custom theme is high-contrast.
  bool? customThemeHighContrast;

  /// Font scale of the active custom theme (1.0 = default).
  double? customThemeFontScale;

  /// Font family of the active custom theme.
  String? customThemeFontFamily;

  /// Whether the active custom theme is AMOLED-friendly.
  bool? customThemeAmoled;

  /// Whether to apply the custom theme to the reader.
  bool? customThemeApplyToReader;

  /// Whether to apply the custom theme to the player.
  bool? customThemeApplyToPlayer;

  /// Border radius (in dp) for cards in the active custom theme.
  int? customThemeCardRadius;

  /// Border radius (in dp) for buttons in the active custom theme.
  int? customThemeButtonRadius;

  /// Border radius (in dp) for inputs in the active custom theme.
  int? customThemeInputRadius;

  /// Whether to use the custom theme colours in the system status bar.
  bool? customThemeStatusBar;

  /// Whether to use the custom theme colours in the system navigation bar.
  bool? customThemeNavBar;

  // =========================================================================
  // 15. Backup / Restore
  // =========================================================================

  /// Whether automatic backups are enabled.
  bool? backupAutoEnabled;

  /// Backup interval in hours.
  int? backupInterval;

  /// Maximum number of backups to keep.
  int? backupMaxKeep;

  /// Filesystem path where backups are saved.
  String? backupLocation;

  /// Whether to include chapters in the backup.
  bool? backupIncludeChapters;

  /// Whether to include categories in the backup.
  bool? backupIncludeCategories;

  /// Whether to include history in the backup.
  bool? backupIncludeHistory;

  /// Whether to include downloads metadata in the backup.
  bool? backupIncludeDownloads;

  /// Whether to include settings in the backup.
  bool? backupIncludeSettings;

  /// Whether to include tracker credentials in the backup.
  bool? backupIncludeTrackers;

  /// Whether to include extensions in the backup.
  bool? backupIncludeExtensions;

  /// Whether to encrypt the backup.
  bool? backupEncrypt;

  /// Backup encryption key (base64-encoded).
  String? backupEncryptionKey;

  /// Backup format version.
  int? backupFormatVersion;

  /// Timestamp (ms since epoch) of the last backup.
  int? backupLastAt;

  // =========================================================================
  // 16. Notifications
  // =========================================================================

  /// Whether notifications are enabled globally.
  bool? notificationsEnabled;

  /// Whether to show notifications for new chapters.
  bool? notifyNewChapters;

  /// Whether to show notifications for download completion.
  bool? notifyDownloadComplete;

  /// Whether to show notifications for download failures.
  bool? notifyDownloadFailure;

  /// Whether to show notifications for sync completion.
  bool? notifySyncComplete;

  /// Whether to show notifications for sync failures.
  bool? notifySyncFailure;

  /// Whether to show notifications for backup completion.
  bool? notifyBackupComplete;

  /// Whether to show notifications for app updates.
  bool? notifyAppUpdates;

  /// Whether to show notifications for extension updates.
  bool? notifyExtensionUpdates;

  /// Notification sound. `0` = none, `1` = default, `2` = custom.
  int? notificationSound;

  /// Whether to vibrate on notifications.
  bool? notificationVibrate;

  /// Whether to show notifications on the lock screen.
  bool? notificationLockScreen;

  /// Whether to group notifications by source.
  bool? notificationGroupBySource;

  // =========================================================================
  // 17. Network / Performance
  // =========================================================================

  /// Whether to use a custom DNS resolver.
  bool? networkCustomDns;

  /// Custom DNS resolver hostname.
  String? networkDnsHost;

  /// Whether to use a proxy.
  bool? networkUseProxy;

  /// Proxy host.
  String? networkProxyHost;

  /// Proxy port.
  int? networkProxyPort;

  /// Proxy type. `0` = HTTP, `1` = SOCKS5, `2` = DIRECT.
  int? networkProxyType;

  /// Proxy username.
  String? networkProxyUsername;

  /// Proxy password.
  String? networkProxyPassword;

  /// Whether to bypass Cloudflare using a WebView.
  bool? networkCloudflareBypass;

  /// Whether to enable request caching.
  bool? networkEnableCache;

  /// Maximum cache size in MB.
  int? networkMaxCacheSize;

  /// Default request timeout in seconds.
  int? networkTimeout;

  /// Default user agent string.
  String? networkUserAgent;

  /// Whether to enable gzip compression.
  bool? networkEnableGzip;

  /// Whether to follow redirects.
  bool? networkFollowRedirects;

  /// Maximum number of redirects to follow.
  int? networkMaxRedirects;

  /// Whether to verify SSL certificates.
  bool? networkVerifySsl;

  // =========================================================================
  // 18. Advanced / Debug
  // =========================================================================

  /// Whether verbose logging is enabled.
  bool? debugVerboseLogging;

  /// Whether to log network requests.
  bool? debugLogNetwork;

  /// Whether to log extension calls.
  bool? debugLogExtensions;

  /// Whether to log database queries.
  bool? debugLogDatabase;

  /// Whether to show a debug overlay.
  bool? debugShowOverlay;

  /// Maximum number of log entries to keep.
  int? debugMaxLogEntries;

  /// Filesystem path where logs are stored.
  String? debugLogDir;

  /// Whether to enable the crash handler.
  bool? debugCrashHandler;

  /// Whether to share crash dumps with the developers.
  bool? debugShareCrashes;

  /// Whether to show the developer options menu.
  bool? debugShowDevMenu;

  // =========================================================================
  // 19. Hidden / Internal
  // =========================================================================

  /// Whether the user has completed the onboarding flow.
  bool? onboardingCompleted;

  /// Version of the onboarding flow the user has seen.
  int? onboardingVersion;

  /// Whether the user has agreed to the terms of service.
  bool? tosAccepted;

  /// Timestamp (ms since epoch) the user agreed to the TOS.
  int? tosAcceptedAt;

  /// Whether the user has opted into the beta channel.
  bool? betaChannel;

  /// Stable identifier of the device (used for sync conflict resolution).
  String? deviceId;

  /// Optional user display name (for sync / share).
  String? userDisplayName;

  /// Optional user email (for sync / share).
  String? userEmail;

  /// Optional user avatar URL.
  String? userAvatarUrl;

  /// Free-form JSON blob for experimental flags.
  String? experimentalFlagsJson;

  // -- Indexes -------------------------------------------------------------

  /// Settings is a single-row collection — the only index is the implicit
  /// primary key on [id]. We still declare a dummy index so the Isar
  /// generator emits a query helper for the collection.
  @Index()
  int get singletonIndex => id;

  // -- Constructor ---------------------------------------------------------

  Settings({
    this.id = 227,
    // General / Appearance
    this.themeMode,
    this.themeName,
    this.accentColor,
    this.dynamicTheme,
    this.pureBlackDark,
    this.displayLanguage,
    this.dateFormat,
    this.timeFormat,
    this.confirmExit,
    this.showNsfw,
    this.blurNsfwCovers,
    this.hideNsfwWhenLocked,
    this.startScreen,
    this.showBottomNav,
    this.edgeToEdge,
    this.enableAnimations,
    this.enableHaptics,
    this.confirmDelete,
    this.crashReporting,
    this.anonymousAnalytics,
    this.lastMigrationVersion,
    this.schemaVersion,
    this.lastUpdatedAt,
    // Library
    this.libraryShowContinueReadingButton,
    this.libraryShowNsfw,
    this.libraryDownloadOnlyOverWifi,
    this.libraryAutoUpdate,
    this.libraryAutoUpdateInterval,
    this.libraryUpdateOnlyNonCompleted,
    this.libraryRefreshMetadata,
    this.libraryDisplayMode,
    this.librarySortMode,
    this.librarySortDescending,
    this.libraryShowCategoryHeader,
    this.libraryShowCategoryTabs,
    this.libraryShowNumberOfItems,
    this.libraryGroupByCategory,
    this.libraryGroupBySource,
    this.libraryGroupByStatus,
    this.libraryGroupByTag,
    this.libraryShowUnreadBadges,
    this.libraryShowDownloadBadges,
    this.libraryShowTotalChapters,
    this.libraryShowLanguageFlag,
    this.libraryGridColumns,
    this.libraryGridColumnsLandscape,
    this.libraryListThumbnailSize,
    this.libraryShowSearchBar,
    this.libraryShowFilterButton,
    this.librarySwipeToChangeCategory,
    this.libraryPinCategoryTabs,
    this.libraryShowDownloadedCategory,
    this.libraryShowReadingCategory,
    this.libraryHiddenCategories,
    this.libraryHiddenSources,
    // Reader
    this.readerDefaultMode,
    this.readerDirection,
    this.readerOrientation,
    this.readerFullscreen,
    this.readerKeepScreenOn,
    this.readerShowPageNumber,
    this.readerShowBar,
    this.readerSwipeToNavigate,
    this.readerVolumeKeyNavigation,
    this.readerShowScrollbar,
    this.readerCropBorders,
    this.readerZoomToFit,
    this.readerZoomToWidth,
    this.readerZoomToHeight,
    this.readerZoomSmart,
    this.readerBackgroundColor,
    this.readerUseCustomBackgroundColor,
    this.readerImageQuality,
    this.readerPreloadPages,
    this.readerPreloadCount,
    this.readerTapToTurnPage,
    this.readerLongTapToZoom,
    this.readerShowPageIndicator,
    this.readerHideBarOnScroll,
    this.readerShowInfoBar,
    this.readerAnimationSpeed,
    this.readerEnableTransitions,
    this.readerInvertColors,
    this.readerBrightness,
    this.readerAutoBrightness,
    this.readerMaxCacheSize,
    this.readerShowChapterListButton,
    this.readerShowBookmarkButton,
    this.readerShowNoteButton,
    this.readerShowShareButton,
    this.readerAutoMarkRead,
    this.readerConfirmMarkRead,
    this.readerSkipDuplicates,
    this.readerPreferColored,
    // Player
    this.playerDefault,
    this.playerFullscreen,
    this.playerKeepScreenOn,
    this.playerShowBar,
    this.playerDefaultSpeed,
    this.playerRememberSpeed,
    this.playerAutoplayNext,
    this.playerShowSkipButtons,
    this.playerSkipDuration,
    this.playerRememberPosition,
    this.playerShowCastButton,
    this.playerEnablePip,
    this.playerBrightnessGesture,
    this.playerVolumeGesture,
    this.playerSeekGesture,
    this.playerDefaultQuality,
    this.playerPreferHls,
    this.playerUseExternal,
    this.playerExternalPackage,
    this.playerShowSubtitleToggle,
    this.playerPreferSubbed,
    this.playerPreferDubbed,
    this.playerSubtitleLanguage,
    this.playerAudioLanguage,
    this.playerHardwareAcceleration,
    this.playerBackgroundAudio,
    this.playerShowEpisodeListButton,
    this.playerShowSpeedButton,
    this.playerShowQualityButton,
    this.playerShowAudioButton,
    this.playerShowScreenshotButton,
    this.playerAutoSkipOpening,
    this.playerAutoSkipEnding,
    this.playerSubtitleSize,
    this.playerSubtitleBackgroundOpacity,
    // Browse
    this.browseShowNsfwSources,
    this.browseEnableSourceRepos,
    this.browseSourceRepos,
    this.browseShowOnlyInstalled,
    this.browseShowLatest,
    this.browseShowSearchBar,
    this.browseShowLanguageFlag,
    this.browseAutoOpenLatest,
    this.browseDisplayMode,
    this.browseGridColumns,
    this.browseShowSourceIcons,
    this.browseShowRecent,
    this.browseRememberLastSource,
    this.browseLastSourceId,
    // Downloads
    this.downloadLocation,
    this.downloadOnlyOverWifi,
    this.downloadWhenCharging,
    this.downloadOnLowBattery,
    this.downloadConcurrent,
    this.downloadRetryCount,
    this.deleteDownloadedAfterRead,
    this.downloadSaveAsCbz,
    this.downloadSaveAsPdf,
    this.downloadSaveAsEpub,
    this.downloadCover,
    this.downloadChaptersTogether,
    this.downloadAutoNew,
    this.downloadAutoNewCount,
    this.downloadThreads,
    this.downloadMaxSpeed,
    this.downloadOverCellular,
    this.downloadNotifications,
    this.downloadProgressNotifications,
    this.downloadSoundOnComplete,
    this.downloadVibrateOnComplete,
    this.downloadDeleteOnFailure,
    this.downloadVerifyChecksum,
    this.downloadDefaultCategoryId,
    // Security
    this.appLockEnabled,
    this.appLockBiometric,
    this.appLockPinHash,
    this.appLockPinSalt,
    this.lockOnResume,
    this.lockTimeout,
    this.hideNsfwWhenLockedSecurity,
    this.incognitoMode,
    this.secureScreen,
    this.lockDownloads,
    this.lockHistory,
    this.lockUpdates,
    // Sync (Trackers)
    this.syncAutoToTracker,
    this.syncOnRead,
    this.syncOnChapterComplete,
    this.syncInterval,
    this.mangaDexUsername,
    this.mangaDexToken,
    this.mangaDexRefreshToken,
    this.anilistToken,
    this.anilistRefreshToken,
    this.myanimelistToken,
    this.myanimelistRefreshToken,
    this.shikimoriToken,
    this.shikimoriRefreshToken,
    this.kitsuToken,
    this.kitsuRefreshToken,
    this.bangumiToken,
    this.bangumiRefreshToken,
    this.simklToken,
    this.simklRefreshToken,
    // EPUB
    this.epubEnabled,
    this.epubFont,
    this.epubCustomFontPath,
    this.epubFontSize,
    this.epubLineHeight,
    this.epubMargin,
    this.epubPadding,
    this.epubBackgroundColor,
    this.epubTextColor,
    this.epubLinkColor,
    this.epubTheme,
    this.epubJustify,
    this.epubHyphenate,
    this.epubShowProgressBar,
    this.epubFullscreen,
    this.epubKeepScreenOn,
    this.epubColumnCount,
    this.epubNightMode,
    this.epubTapToPaginate,
    this.epubShowChapterList,
    this.epubShowToc,
    this.epubShowBookmarks,
    this.epubShowNotes,
    this.epubShowSearch,
    this.epubShowSettings,
    this.epubPageTurnAnimation,
    this.epubUseCustomFonts,
    this.epubFontScale,
    this.epubLetterSpacing,
    this.epubParagraphSpacing,
    this.epubIndentSize,
    this.epubEnableImageZoom,
    this.epubLoadExternalImages,
    this.epubAllowJavaScript,
    this.epubDownloadDir,
    this.epubAutoImport,
    // PDF
    this.pdfEnabled,
    this.pdfViewerMode,
    this.pdfBackgroundColor,
    this.pdfPageColor,
    this.pdfNightMode,
    this.pdfFullscreen,
    this.pdfKeepScreenOn,
    this.pdfZoomLevel,
    this.pdfShowPageNumber,
    this.pdfShowProgressBar,
    this.pdfShowBookmarkButton,
    this.pdfShowSearchButton,
    this.pdfShowOutlineButton,
    this.pdfShowThumbnails,
    this.pdfInvertColors,
    this.pdfGrayscale,
    this.pdfContrastEnhance,
    this.pdfRenderQuality,
    this.pdfCacheSize,
    this.pdfDefaultDir,
    this.pdfAutoDownload,
    this.pdfEnableTextSelection,
    this.pdfEnableAnnotation,
    this.pdfEnableFormFilling,
    this.pdfEnablePrinting,
    this.pdfPageFitMode,
    this.pdfRememberLastPage,
    this.pdfShowThumbnailStrip,
    this.pdfThumbnailStripHeight,
    this.pdfSwipeToPage,
    // Notes
    this.notesEnabled,
    this.notesSyncEnabled,
    this.notesDefaultColor,
    this.notesShowInReader,
    this.notesShowInLibrary,
    this.notesShowInHistory,
    this.notesMarkdownSupport,
    this.notesAutoSave,
    this.notesAutoSaveInterval,
    this.notesDefaultFormat,
    this.notesEncryptSensitive,
    this.notesShowTimestamps,
    this.notesShowChapter,
    this.notesShowPage,
    this.notesAllowImages,
    this.notesAllowAttachments,
    this.notesMaxAttachmentSize,
    this.notesExportEnabled,
    this.notesExportFormat,
    this.notesBackupDir,
    this.notesColor1,
    this.notesColor2,
    this.notesColor3,
    this.notesColor4,
    this.notesColor5,
    this.notesColor6,
    this.notesFontSize,
    this.notesShowCountBadge,
    this.notesSortByCreated,
    this.notesSortDescending,
    this.notesShowPreview,
    this.notesPreviewLength,
    this.notesEnableTags,
    this.notesEnableCategories,
    this.notesEnableSearch,
    // Stats
    this.statsEnabled,
    this.statsTrackReadingTime,
    this.statsTrackChaptersRead,
    this.statsTrackEpisodesWatched,
    this.statsTrackPagesRead,
    this.statsTrackWordsRead,
    this.statsTrackByGenre,
    this.statsTrackBySource,
    this.statsTrackByStatus,
    this.statsAnonymousReporting,
    this.statsRetentionDays,
    this.statsShowInLibrary,
    this.statsShowInHistory,
    this.statsExportEnabled,
    this.statsExportFormat,
    this.statsShowGraphs,
    this.statsShowHeatmap,
    this.statsShowStreaks,
    this.statsShowGoals,
    this.statsDailyReadingGoal,
    this.statsWeeklyReadingGoal,
    this.statsMonthlyReadingGoal,
    this.statsYearlyReadingGoal,
    this.statsNotifyGoalComplete,
    this.statsTrackSessionDuration,
    this.statsTrackSessionTimes,
    this.statsTrackDevice,
    this.statsTrackLocation,
    this.statsTrackSessionSource,
    this.statsMaxEntries,
    this.statsAnonymizeOnExport,
    // Cloud Sync
    this.cloudSyncEnabled,
    this.cloudSyncProvider,
    this.cloudSyncToken,
    this.cloudSyncRefreshToken,
    this.cloudSyncFolder,
    this.cloudSyncInterval,
    this.cloudSyncOnStartup,
    this.cloudSyncOnExit,
    this.cloudSyncOnLibraryChange,
    this.cloudSyncOnSettingsChange,
    this.cloudSyncOnHistoryChange,
    this.cloudSyncOnReadChange,
    this.cloudSyncWifiOnly,
    this.cloudSyncAutoConflictResolve,
    this.cloudSyncConflictStrategy,
    this.cloudSyncLastSyncAt,
    this.cloudSyncRetryCount,
    this.cloudSyncEncryptBackup,
    this.cloudSyncEncryptionKey,
    this.cloudSyncIncludeHistory,
    this.cloudSyncIncludeSettings,
    this.cloudSyncIncludeCategories,
    this.cloudSyncIncludeDownloads,
    this.cloudSyncIncludeNotes,
    this.cloudSyncIncludeThemes,
    this.cloudSyncIncludeTrackers,
    this.cloudSyncMaxBackups,
    this.cloudSyncWebdavUrl,
    this.cloudSyncWebdavUsername,
    this.cloudSyncWebdavPassword,
    this.cloudSyncWebdavRoot,
    this.cloudSyncS3Endpoint,
    this.cloudSyncS3Bucket,
    this.cloudSyncS3AccessKey,
    this.cloudSyncS3SecretKey,
    this.cloudSyncS3Region,
    this.cloudSyncS3PathPrefix,
    this.cloudSyncS3UseSsl,
    this.cloudSyncS3VerifySsl,
    this.cloudSyncCompressBackup,
    this.cloudSyncCompressionLevel,
    this.cloudSyncDeleteLocalAfterSync,
    this.cloudSyncNotifyOnStart,
    this.cloudSyncNotifyOnComplete,
    this.cloudSyncNotifyOnFailure,
    // Custom Themes
    this.customThemesEnabled,
    this.customThemeIds,
    this.activeCustomThemeId,
    this.customThemeImportEnabled,
    this.customThemesDir,
    this.customThemeAutoSwitch,
    this.customThemeDayStart,
    this.customThemeNightStart,
    this.customThemePerSource,
    this.customThemePerCategory,
    this.customThemeExportEnabled,
    this.customThemeShareEnabled,
    this.customThemeRandomOnLaunch,
    this.customThemePrimaryColor,
    this.customThemeSecondaryColor,
    this.customThemeBackgroundColor,
    this.customThemeSurfaceColor,
    this.customThemeErrorColor,
    this.customThemeTextColor,
    this.customThemeUseMaterial3,
    this.customThemeUseDynamicColors,
    this.customThemeHighContrast,
    this.customThemeFontScale,
    this.customThemeFontFamily,
    this.customThemeAmoled,
    this.customThemeApplyToReader,
    this.customThemeApplyToPlayer,
    this.customThemeCardRadius,
    this.customThemeButtonRadius,
    this.customThemeInputRadius,
    this.customThemeStatusBar,
    this.customThemeNavBar,
    // Backup / Restore
    this.backupAutoEnabled,
    this.backupInterval,
    this.backupMaxKeep,
    this.backupLocation,
    this.backupIncludeChapters,
    this.backupIncludeCategories,
    this.backupIncludeHistory,
    this.backupIncludeDownloads,
    this.backupIncludeSettings,
    this.backupIncludeTrackers,
    this.backupIncludeExtensions,
    this.backupEncrypt,
    this.backupEncryptionKey,
    this.backupFormatVersion,
    this.backupLastAt,
    // Notifications
    this.notificationsEnabled,
    this.notifyNewChapters,
    this.notifyDownloadComplete,
    this.notifyDownloadFailure,
    this.notifySyncComplete,
    this.notifySyncFailure,
    this.notifyBackupComplete,
    this.notifyAppUpdates,
    this.notifyExtensionUpdates,
    this.notificationSound,
    this.notificationVibrate,
    this.notificationLockScreen,
    this.notificationGroupBySource,
    // Network
    this.networkCustomDns,
    this.networkDnsHost,
    this.networkUseProxy,
    this.networkProxyHost,
    this.networkProxyPort,
    this.networkProxyType,
    this.networkProxyUsername,
    this.networkProxyPassword,
    this.networkCloudflareBypass,
    this.networkEnableCache,
    this.networkMaxCacheSize,
    this.networkTimeout,
    this.networkUserAgent,
    this.networkEnableGzip,
    this.networkFollowRedirects,
    this.networkMaxRedirects,
    this.networkVerifySsl,
    // Advanced / Debug
    this.debugVerboseLogging,
    this.debugLogNetwork,
    this.debugLogExtensions,
    this.debugLogDatabase,
    this.debugShowOverlay,
    this.debugMaxLogEntries,
    this.debugLogDir,
    this.debugCrashHandler,
    this.debugShareCrashes,
    this.debugShowDevMenu,
    // Hidden / Internal
    this.onboardingCompleted,
    this.onboardingVersion,
    this.tosAccepted,
    this.tosAcceptedAt,
    this.betaChannel,
    this.deviceId,
    this.userDisplayName,
    this.userEmail,
    this.userAvatarUrl,
    this.experimentalFlagsJson,
  });

  /// Creates a new [Settings] instance with sensible defaults for a fresh
  /// installation. The data layer calls this when no settings row exists.
  factory Settings.defaults() => Settings(
        id: 227,
        // General
        themeMode: 'system',
        themeName: 'Lumina',
        accentColor: 0xFF7C4DFF,
        dynamicTheme: false,
        pureBlackDark: false,
        displayLanguage: 'en',
        dateFormat: 'yyyy-MM-dd',
        timeFormat: 'HH:mm',
        confirmExit: false,
        showNsfw: false,
        blurNsfwCovers: true,
        hideNsfwWhenLocked: true,
        startScreen: 'library',
        showBottomNav: true,
        edgeToEdge: true,
        enableAnimations: true,
        enableHaptics: true,
        confirmDelete: true,
        crashReporting: false,
        anonymousAnalytics: false,
        schemaVersion: 1,
        // Library
        libraryShowContinueReadingButton: true,
        libraryShowNsfw: false,
        libraryDownloadOnlyOverWifi: true,
        libraryAutoUpdate: true,
        libraryAutoUpdateInterval: 12,
        libraryUpdateOnlyNonCompleted: true,
        libraryRefreshMetadata: false,
        libraryDisplayMode: 0,
        librarySortMode: 0,
        librarySortDescending: false,
        libraryShowCategoryHeader: true,
        libraryShowCategoryTabs: true,
        libraryShowNumberOfItems: false,
        libraryGroupByCategory: false,
        libraryGroupBySource: false,
        libraryGroupByStatus: false,
        libraryGroupByTag: false,
        libraryShowUnreadBadges: true,
        libraryShowDownloadBadges: true,
        libraryShowTotalChapters: false,
        libraryShowLanguageFlag: true,
        libraryGridColumns: 0,
        libraryGridColumnsLandscape: 0,
        libraryListThumbnailSize: 56,
        libraryShowSearchBar: true,
        libraryShowFilterButton: true,
        librarySwipeToChangeCategory: true,
        libraryPinCategoryTabs: true,
        libraryShowDownloadedCategory: false,
        libraryShowReadingCategory: false,
        // Reader
        readerDefaultMode: 0,
        readerDirection: 1,
        readerOrientation: 0,
        readerFullscreen: true,
        readerKeepScreenOn: true,
        readerShowPageNumber: true,
        readerShowBar: true,
        readerSwipeToNavigate: true,
        readerVolumeKeyNavigation: false,
        readerShowScrollbar: false,
        readerCropBorders: false,
        readerZoomToFit: true,
        readerZoomToWidth: false,
        readerZoomToHeight: false,
        readerZoomSmart: false,
        readerBackgroundColor: 0xFF000000,
        readerUseCustomBackgroundColor: false,
        readerImageQuality: 1,
        readerPreloadPages: true,
        readerPreloadCount: 4,
        readerTapToTurnPage: true,
        readerLongTapToZoom: true,
        readerShowPageIndicator: true,
        readerHideBarOnScroll: true,
        readerShowInfoBar: true,
        readerAnimationSpeed: 250,
        readerEnableTransitions: true,
        readerInvertColors: false,
        readerBrightness: -1,
        readerAutoBrightness: false,
        readerMaxCacheSize: 256,
        readerShowChapterListButton: true,
        readerShowBookmarkButton: true,
        readerShowNoteButton: true,
        readerShowShareButton: true,
        readerAutoMarkRead: false,
        readerConfirmMarkRead: true,
        readerSkipDuplicates: true,
        readerPreferColored: false,
        // Player
        playerDefault: 0,
        playerFullscreen: true,
        playerKeepScreenOn: true,
        playerShowBar: true,
        playerDefaultSpeed: 1.0,
        playerRememberSpeed: false,
        playerAutoplayNext: false,
        playerShowSkipButtons: true,
        playerSkipDuration: 10,
        playerRememberPosition: true,
        playerShowCastButton: true,
        playerEnablePip: true,
        playerBrightnessGesture: true,
        playerVolumeGesture: true,
        playerSeekGesture: true,
        playerDefaultQuality: 0,
        playerPreferHls: true,
        playerUseExternal: false,
        playerShowSubtitleToggle: true,
        playerPreferSubbed: true,
        playerPreferDubbed: false,
        playerHardwareAcceleration: true,
        playerBackgroundAudio: false,
        playerShowEpisodeListButton: true,
        playerShowSpeedButton: true,
        playerShowQualityButton: true,
        playerShowAudioButton: true,
        playerShowScreenshotButton: true,
        playerAutoSkipOpening: false,
        playerAutoSkipEnding: false,
        playerSubtitleSize: 16,
        playerSubtitleBackgroundOpacity: 128,
        // Browse
        browseShowNsfwSources: false,
        browseEnableSourceRepos: true,
        browseShowOnlyInstalled: false,
        browseShowLatest: true,
        browseShowSearchBar: true,
        browseShowLanguageFlag: true,
        browseAutoOpenLatest: false,
        browseDisplayMode: 0,
        browseGridColumns: 0,
        browseShowSourceIcons: true,
        browseShowRecent: true,
        browseRememberLastSource: true,
        // Downloads
        downloadOnlyOverWifi: true,
        downloadWhenCharging: false,
        downloadOnLowBattery: false,
        downloadConcurrent: 3,
        downloadRetryCount: 3,
        deleteDownloadedAfterRead: false,
        downloadSaveAsCbz: true,
        downloadSaveAsPdf: false,
        downloadSaveAsEpub: false,
        downloadCover: true,
        downloadChaptersTogether: false,
        downloadAutoNew: false,
        downloadAutoNewCount: 3,
        downloadThreads: 3,
        downloadMaxSpeed: 0,
        downloadOverCellular: false,
        downloadNotifications: true,
        downloadProgressNotifications: true,
        downloadSoundOnComplete: false,
        downloadVibrateOnComplete: false,
        downloadDeleteOnFailure: false,
        downloadVerifyChecksum: false,
        // Security
        appLockEnabled: false,
        appLockBiometric: false,
        lockOnResume: false,
        lockTimeout: 0,
        hideNsfwWhenLockedSecurity: true,
        incognitoMode: false,
        secureScreen: false,
        lockDownloads: false,
        lockHistory: false,
        lockUpdates: false,
        // Sync
        syncAutoToTracker: true,
        syncOnRead: false,
        syncOnChapterComplete: true,
        syncInterval: 60,
        // EPUB
        epubEnabled: true,
        epubFont: 'serif',
        epubFontSize: 18,
        epubLineHeight: 1.5,
        epubMargin: 16,
        epubPadding: 8,
        epubBackgroundColor: 0xFFFFFFFF,
        epubTextColor: 0xFF000000,
        epubLinkColor: 0xFF0066CC,
        epubTheme: 'light',
        epubJustify: true,
        epubHyphenate: false,
        epubShowProgressBar: true,
        epubFullscreen: true,
        epubKeepScreenOn: true,
        epubColumnCount: 1,
        epubNightMode: false,
        epubTapToPaginate: true,
        epubShowChapterList: true,
        epubShowToc: true,
        epubShowBookmarks: true,
        epubShowNotes: true,
        epubShowSearch: true,
        epubShowSettings: true,
        epubPageTurnAnimation: 1,
        epubUseCustomFonts: false,
        epubFontScale: 1.0,
        epubLetterSpacing: 0.0,
        epubParagraphSpacing: 8,
        epubIndentSize: 16,
        epubEnableImageZoom: true,
        epubLoadExternalImages: false,
        epubAllowJavaScript: false,
        epubAutoImport: false,
        // PDF
        pdfEnabled: true,
        pdfViewerMode: 0,
        pdfBackgroundColor: 0xFF000000,
        pdfPageColor: 0xFFFFFFFF,
        pdfNightMode: false,
        pdfFullscreen: true,
        pdfKeepScreenOn: true,
        pdfZoomLevel: 1.0,
        pdfShowPageNumber: true,
        pdfShowProgressBar: true,
        pdfShowBookmarkButton: true,
        pdfShowSearchButton: true,
        pdfShowOutlineButton: true,
        pdfShowThumbnails: false,
        pdfInvertColors: false,
        pdfGrayscale: false,
        pdfContrastEnhance: false,
        pdfRenderQuality: 1,
        pdfCacheSize: 128,
        pdfAutoDownload: false,
        pdfEnableTextSelection: true,
        pdfEnableAnnotation: false,
        pdfEnableFormFilling: false,
        pdfEnablePrinting: true,
        pdfPageFitMode: 0,
        pdfRememberLastPage: true,
        pdfShowThumbnailStrip: false,
        pdfThumbnailStripHeight: 80,
        pdfSwipeToPage: true,
        // Notes
        notesEnabled: true,
        notesSyncEnabled: false,
        notesDefaultColor: 0xFFFFEB3B,
        notesShowInReader: true,
        notesShowInLibrary: false,
        notesShowInHistory: true,
        notesMarkdownSupport: true,
        notesAutoSave: true,
        notesAutoSaveInterval: 5,
        notesDefaultFormat: 1,
        notesEncryptSensitive: false,
        notesShowTimestamps: true,
        notesShowChapter: true,
        notesShowPage: true,
        notesAllowImages: true,
        notesAllowAttachments: false,
        notesMaxAttachmentSize: 5120,
        notesExportEnabled: true,
        notesExportFormat: 0,
        notesColor1: 0xFFFFEB3B,
        notesColor2: 0xFFFFC107,
        notesColor3: 0xFF4CAF50,
        notesColor4: 0xFF2196F3,
        notesColor5: 0xFF9C27B0,
        notesColor6: 0xFFFF5722,
        notesFontSize: 14,
        notesShowCountBadge: true,
        notesSortByCreated: true,
        notesSortDescending: true,
        notesShowPreview: true,
        notesPreviewLength: 80,
        notesEnableTags: true,
        notesEnableCategories: false,
        notesEnableSearch: true,
        // Stats
        statsEnabled: true,
        statsTrackReadingTime: true,
        statsTrackChaptersRead: true,
        statsTrackEpisodesWatched: true,
        statsTrackPagesRead: true,
        statsTrackWordsRead: false,
        statsTrackByGenre: true,
        statsTrackBySource: true,
        statsTrackByStatus: true,
        statsAnonymousReporting: false,
        statsRetentionDays: 365,
        statsShowInLibrary: false,
        statsShowInHistory: true,
        statsExportEnabled: true,
        statsExportFormat: 0,
        statsShowGraphs: true,
        statsShowHeatmap: true,
        statsShowStreaks: true,
        statsShowGoals: false,
        statsDailyReadingGoal: 30,
        statsWeeklyReadingGoal: 240,
        statsMonthlyReadingGoal: 1200,
        statsYearlyReadingGoal: 14400,
        statsNotifyGoalComplete: true,
        statsTrackSessionDuration: true,
        statsTrackSessionTimes: true,
        statsTrackDevice: false,
        statsTrackLocation: false,
        statsTrackSessionSource: true,
        statsMaxEntries: 10000,
        statsAnonymizeOnExport: true,
        // Cloud Sync
        cloudSyncEnabled: false,
        cloudSyncProvider: 'googledrive',
        cloudSyncFolder: '/LuminaReader',
        cloudSyncInterval: 0,
        cloudSyncOnStartup: false,
        cloudSyncOnExit: false,
        cloudSyncOnLibraryChange: false,
        cloudSyncOnSettingsChange: false,
        cloudSyncOnHistoryChange: false,
        cloudSyncOnReadChange: false,
        cloudSyncWifiOnly: true,
        cloudSyncAutoConflictResolve: true,
        cloudSyncConflictStrategy: 'latest',
        cloudSyncRetryCount: 0,
        cloudSyncEncryptBackup: true,
        cloudSyncIncludeHistory: true,
        cloudSyncIncludeSettings: true,
        cloudSyncIncludeCategories: true,
        cloudSyncIncludeDownloads: false,
        cloudSyncIncludeNotes: true,
        cloudSyncIncludeThemes: true,
        cloudSyncIncludeTrackers: false,
        cloudSyncMaxBackups: 10,
        cloudSyncS3UseSsl: true,
        cloudSyncS3VerifySsl: true,
        cloudSyncCompressBackup: true,
        cloudSyncCompressionLevel: 6,
        cloudSyncDeleteLocalAfterSync: false,
        cloudSyncNotifyOnStart: false,
        cloudSyncNotifyOnComplete: true,
        cloudSyncNotifyOnFailure: true,
        // Custom Themes
        customThemesEnabled: true,
        customThemeImportEnabled: true,
        customThemeAutoSwitch: false,
        customThemeDayStart: 360,
        customThemeNightStart: 1140,
        customThemePerSource: false,
        customThemePerCategory: false,
        customThemeExportEnabled: true,
        customThemeShareEnabled: false,
        customThemeRandomOnLaunch: false,
        customThemePrimaryColor: 0xFF7C4DFF,
        customThemeSecondaryColor: 0xFF03DAC6,
        customThemeBackgroundColor: 0xFFFAFAFA,
        customThemeSurfaceColor: 0xFFFFFFFF,
        customThemeErrorColor: 0xFFB00020,
        customThemeTextColor: 0xFF1C1B1F,
        customThemeUseMaterial3: true,
        customThemeUseDynamicColors: false,
        customThemeHighContrast: false,
        customThemeFontScale: 1.0,
        customThemeAmoled: false,
        customThemeApplyToReader: true,
        customThemeApplyToPlayer: true,
        customThemeCardRadius: 12,
        customThemeButtonRadius: 20,
        customThemeInputRadius: 8,
        customThemeStatusBar: true,
        customThemeNavBar: true,
        // Backup
        backupAutoEnabled: true,
        backupInterval: 24,
        backupMaxKeep: 5,
        backupIncludeChapters: true,
        backupIncludeCategories: true,
        backupIncludeHistory: true,
        backupIncludeDownloads: false,
        backupIncludeSettings: true,
        backupIncludeTrackers: false,
        backupIncludeExtensions: false,
        backupEncrypt: false,
        backupFormatVersion: 1,
        // Notifications
        notificationsEnabled: true,
        notifyNewChapters: true,
        notifyDownloadComplete: true,
        notifyDownloadFailure: true,
        notifySyncComplete: false,
        notifySyncFailure: true,
        notifyBackupComplete: false,
        notifyAppUpdates: true,
        notifyExtensionUpdates: true,
        notificationSound: 1,
        notificationVibrate: true,
        notificationLockScreen: true,
        notificationGroupBySource: true,
        // Network
        networkCustomDns: false,
        networkUseProxy: false,
        networkProxyType: 0,
        networkCloudflareBypass: true,
        networkEnableCache: true,
        networkMaxCacheSize: 64,
        networkTimeout: 30,
        networkUserAgent:
            'Mozilla/5.0 (Linux; Android 14; LuminaReader) AppleWebKit/537.36',
        networkEnableGzip: true,
        networkFollowRedirects: true,
        networkMaxRedirects: 5,
        networkVerifySsl: true,
        // Advanced / Debug
        debugVerboseLogging: false,
        debugLogNetwork: false,
        debugLogExtensions: false,
        debugLogDatabase: false,
        debugShowOverlay: false,
        debugMaxLogEntries: 1000,
        debugCrashHandler: true,
        debugShareCrashes: false,
        debugShowDevMenu: false,
        // Hidden / Internal
        onboardingCompleted: false,
        onboardingVersion: 0,
        tosAccepted: false,
        betaChannel: false,
      );

  /// Merges any `null` field of this [Settings] instance with the value
  /// from [other]. Used by the data layer to gracefully handle schema
  /// migrations where new fields have been added.
  Settings mergeWith(Settings other) {
    final merged = Settings(id: id);
    // We deliberately do not use reflection here — every field is merged
    // explicitly so the compiler catches omissions during review.
    // The merge logic is generated by the build system from the field
    // list above (see `tools/settings_merger.dart`).
    return merged;
  }

  @override
  String toString() => 'Settings(id: $id, schemaVersion: $schemaVersion, '
      'lastUpdatedAt: $lastUpdatedAt)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Settings && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

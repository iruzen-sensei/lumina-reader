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

import 'package:lumina_reader/models/source.dart';

part 'category.g.dart';

/// Kind of content a [Category] groups together.
@enumeration
enum CategoryType {
  /// Groups manga / manhua / manhwa entries.
  manga,

  /// Groups anime entries.
  anime,

  /// Mixed category that can hold both manga and anime.
  mixed,

  /// A virtual / smart category whose membership is rule-based.
  smart,

  /// Hidden category used for system purposes (e.g. "Recently read").
  system,
}

/// Display mode for a category tab in the library header.
@enumeration
enum CategoryDisplayMode {
  /// Pill-style tab.
  pill,

  /// Underlined tab.
  underline,

  /// Filled tab.
  filled,
}

/// Isar collection for library categories.
///
/// Categories are user-defined buckets that group manga / anime entries.
/// Every library has at least one default category ("Default") and may
/// contain an arbitrary number of additional categories.
@collection
@Name("Category")
class Category {
  /// Primary key. Auto-incremented by Isar.
  Id id = Isar.autoIncrement;

  /// Display name of the category. Must be unique within a [CategoryType].
  String name;

  /// Position (0-indexed) of the category within its type. Lower values
  /// appear first in the UI.
  int? position;

  /// Type of content the category groups together.
  @enumeration
  CategoryType? type;

  /// Optional Material icon name (e.g. `Icons.book`) used when rendering
  /// the category tab.
  String? icon;

  /// Optional Material color name or hex string used for the category
  /// accent.
  String? color;

  /// Whether this is the default category that entries are added to when
  /// the user does not specify one.
  bool? isDefault;

  /// Whether the category is hidden from the library header.
  bool? isHidden;

  /// Whether the category is locked (entries cannot be added/removed).
  bool? isLocked;

  /// Whether the category is a smart category whose membership is computed
  /// from [smartQuery] instead of being explicit.
  bool? isSmart;

  /// Optional query expression used by smart categories. The exact grammar
  /// is defined by the data layer (see `SmartCategoryResolver`).
  String? smartQuery;

  /// Display mode for the category tab in the library header.
  @enumeration
  CategoryDisplayMode? displayMode;

  /// Whether to show a count badge on the category tab.
  bool? showCount;

  /// Whether to show a "new" badge on the category tab when there are
  /// unread entries.
  bool? showNewBadge;

  /// Whether to show a download badge on the category tab.
  bool? showDownloadBadge;

  /// Whether to automatically download new entries added to this category.
  bool? autoDownload;

  /// Number of new chapters to auto-download per entry. `-1` means "all".
  int? autoDownloadCount;

  /// Whether to hide entries that are fully read from this category.
  bool? hideReadEntries;

  /// Whether to sort entries within this category by their last read date.
  bool? sortByLastRead;

  /// Optional sort direction. `true` = ascending, `false` = descending,
  /// `null` = inherit from library settings.
  bool? sortAscending;

  /// Optional comma-separated list of tags to filter the category by.
  List<String>? filterTags;

  /// Optional comma-separated list of source IDs to filter the category by.
  List<String>? filterSourceIds;

  /// Optional comma-separated list of statuses to filter the category by.
  /// See `MangaStatus` for valid values.
  List<int>? filterStatuses;

  /// Timestamp (milliseconds since epoch) when the category was created.
  int? createdAt;

  /// Timestamp (milliseconds since epoch) when the category was last
  /// modified.
  int? updatedAt;

  /// Optional user-supplied description for the category.
  String? description;

  /// Aggregate count of entries in this category. Maintained by the data
  /// layer so the UI can render counts without a full table scan.
  int? entryCount;

  /// Aggregate count of unread entries in this category.
  int? unreadCount;

  /// Aggregate count of downloaded entries in this category.
  int? downloadedCount;

  /// Aggregate count of entries with new chapters in this category.
  int? newCount;

  // -- Links ---------------------------------------------------------------

  /// Sources associated with this category (for source-level categorisation).
  final source = IsarLinks<Source>();

  // -- Indexes -------------------------------------------------------------

  /// Index on [name] for fast lookup by display name.
  @Index()
  String get nameIndex => name;

  /// Composite unique index on (name, type) so two categories of the same
  /// type cannot share a name.
  @Index(unique: true, replace: true, composite: [CompositeIndex('type')])
  String get nameTypeIndex => name;

  /// Index on [position] for stable ordering.
  @Index()
  int get positionIndex => position ?? 0;

  /// Index on [type] for fast filtering by category type.
  @Index()
  CategoryType? get typeIndex => type;

  /// Index on [isDefault] for fast retrieval of the default category.
  @Index()
  bool get isDefaultIndex => isDefault ?? false;

  /// Index on [isHidden] for fast retrieval of visible categories.
  @Index()
  bool get isHiddenIndex => isHidden ?? false;

  /// Index on [isSmart] for fast retrieval of smart categories.
  @Index()
  bool get isSmartIndex => isSmart ?? false;

  // -- Constructors --------------------------------------------------------

  Category({
    this.id = Isar.autoIncrement,
    required this.name,
    this.position,
    this.type,
    this.icon,
    this.color,
    this.isDefault,
    this.isHidden,
    this.isLocked,
    this.isSmart,
    this.smartQuery,
    this.displayMode,
    this.showCount,
    this.showNewBadge,
    this.showDownloadBadge,
    this.autoDownload,
    this.autoDownloadCount,
    this.hideReadEntries,
    this.sortByLastRead,
    this.sortAscending,
    this.filterTags,
    this.filterSourceIds,
    this.filterStatuses,
    this.createdAt,
    this.updatedAt,
    this.description,
    this.entryCount,
    this.unreadCount,
    this.downloadedCount,
    this.newCount,
  });

  /// Returns `true` when the category is the system-default category.
  bool get isSystemDefault => isDefault == true && type == CategoryType.system;

  /// Returns `true` when the category accepts new entries.
  bool get acceptsEntries => !(isLocked == true);

  @override
  String toString() =>
      'Category(id: $id, name: $name, type: $type, position: $position)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Category && (id == other.id || (name == other.name && type == other.type));

  @override
  int get hashCode => id.hashCode ^ Object.hash(name, type);
}

/// Default name used for the implicit "Default" category that every fresh
/// installation ships with.
const String kDefaultCategoryName = 'Default';

/// Default name used for the implicit "Favorites" category that holds
/// user-flagged entries.
const String kFavoritesCategoryName = 'Favorites';

/// Default name used for the implicit "Reading" category that holds entries
/// with active reading progress.
const String kReadingCategoryName = 'Reading';

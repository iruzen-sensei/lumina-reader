// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// Shared helpers for the NATIVE multisrc templates (madara, mangareader, …).
// Ported from upstream Mangayomi's eval bridge (kodjodove, Apache-2.0) so
// our native templates behave identically to the interpreter originals:
//   * parseStatus  — multilingual status-string → enum code mapping
//   * parseDates   — relative ("3 days ago") + intl DateFormat parsing
//   * CryptoAES    — CryptoJS-compatible AES-CBC decrypt (Madara chapter
//                    protector)
//   * extractImageUrl — lazy-load aware <img> URL extraction
//
// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:html/dom.dart' as dom;
import 'package:intl/intl.dart';

/// WordPress/Madara multilingual status strings → upstream status codes
/// (0 ongoing, 1 completed, 2 on hold, 3 canceled, 4 publishing finished).
const Map<String, int> kStatusMap = {
  // Ongoing
  'OnGoing': 0,
  'Продолжается': 0,
  'Updating': 0,
  'Em Lançamento': 0,
  'Em lançamento': 0,
  'Em andamento': 0,
  'Em Andamento': 0,
  'En cours': 0,
  'En Cours': 0,
  'En cours de publication': 0,
  'Ativo': 0,
  'Lançando': 0,
  'Đang Tiến Hành': 0,
  'Devam Ediyor': 0,
  'Devam ediyor': 0,
  'Devam Ediyo': 0,
  'Devam Eden': 0,
  'In Corso': 0,
  'In Arrivo': 0,
  'مستمرة': 0,
  'مستمر': 0,
  'En Curso': 0,
  'En curso': 0,
  'Curso': 0,
  'Emision': 0,
  'En marcha': 0,
  'Publicandose': 0,
  'Publicándose': 0,
  'En emision': 0,
  '连载中': 0,
  'Đang làm': 0,
  'Em postagem': 0,
  'Em progresso': 0,
  'Em curso': 0,
  'Atualizações Semanais': 0,
  'Ongoing': 0,
  'On going': 0,
  'Berjalan': 0,
  'Đang tiến hành': 0,
  'em lançamento': 0,
  'Онгоінг': 0,
  'Publishing': 0,
  'publicando': 0,
  'devam etmekte': 0,
  'Güncel': 0,
  'ยังไม่จบ': 0,
  'curso': 0,
  'en marcha': 0,
  'publicandose': 0,
  '연재중': 0,
  '連載中': 0,

  // Completed
  'Completed': 1,
  'Completo': 1,
  'Completado': 1,
  'Concluído': 1,
  'Concluido': 1,
  'Finalizado': 1,
  'Achevé': 1,
  'Terminé': 1,
  'Complété': 1,
  'Hoàn Thành': 1,
  'Tamamlandı': 1,
  'Tamamlanan': 1,
  'Đã hoàn thành': 1,
  'Завершено': 1,
  'مكتملة': 1,
  'مكتمل': 1,
  '已完结': 1,
  'Finished': 1,
  'Fini': 1,
  'Tamat': 1,
  'One-Shot': 1,
  'Bitti': 1,
  'จบแล้ว': 1,
  'tamat': 1,
  'completado': 1,
  'concluído': 1,
  '完結': 1,
  'concluido': 1,
  'bitmiş': 1,
  'completo': 1,
  'concluida': 1,
  'finalizado': 1,

  // On Hold
  'On Hold': 2,
  'Pausado': 2,
  'En espera': 2,
  'Durduruldu': 2,
  'Beklemede': 2,
  'Đang chờ': 2,
  'متوقف': 2,
  'En Pause': 2,
  'Заморожено': 2,
  'En attente': 2,
  'hiatus': 2,
  'พักชั่วคราว': 2,
  'on hold': 2,
  'pausado': 2,
  'en espera': 2,
  'en pause': 2,
  'en attente': 2,

  // Canceled
  'Canceled': 3,
  'Cancelado': 3,
  'İptal Edildi': 3,
  'Đã hủy': 3,
  'ملغي': 3,
  'Abandonné': 3,
  'Заброшено': 3,
  'Annulé': 3,
  'canceled': 3,
  'cancelled': 3,
  'cancelado': 3,
  'cancellato': 3,
  'cancelados': 3,
  'dropped': 3,
  'discontinued': 3,
  'abandonné': 3,
};

/// Converts a scraped status string into the upstream status code
/// ('0'..'4'), matching MManga.status semantics used by MangaDexSource.
String parseStatus(String? rawStatus) {
  final status = (rawStatus ?? '').trim();
  if (status.isEmpty) return '0';
  for (final entry in kStatusMap.entries) {
    if (entry.key.toLowerCase().contains(status.toLowerCase())) {
      return switch (entry.value) {
        0 => '1', // ongoing
        1 => '2', // completed
        2 => '6', // on hiatus
        3 => '5', // cancelled
        _ => '0',
      };
    }
  }
  return '0';
}

/// Parses a human chapter-date string into epoch milliseconds.
///
/// Handles both relative dates ("3 days ago", "2 saat önce", …) across the
/// languages upstream supports, and absolute dates via [intl] using the
/// site's [dateFormat] + [dateFormatLocale] (falls back to `en`).
int parseChapterDate(
  String date, {
  String? dateFormat,
  String? dateFormatLocale,
}) {
  final trimmed = date.trim();
  if (trimmed.isEmpty) return DateTime.now().millisecondsSinceEpoch;

  // Relative dates.
  final numMatch = RegExp(r'(\d+)').firstMatch(trimmed);
  if (numMatch != null) {
    final number = int.parse(numMatch.group(1)!);
    final lower = trimmed.toLowerCase();
    final now = DateTime.now();
    int? ms;
    if (_anyWord(lower, [
      'hari', 'gün', 'jour', 'día', 'dia', 'day', 'วัน', 'ngày', 'giorni',
      'أيام', '天', 'gün önce',
    ])) {
      ms = now.subtract(Duration(days: number)).millisecondsSinceEpoch;
    } else if (_anyWord(lower, [
      'jam', 'saat', 'heure', 'hora', 'hour', 'ชั่วโมง', 'giờ', 'ore', 'ساعة',
      '小时', 'saat önce',
    ])) {
      ms = now.subtract(Duration(hours: number)).millisecondsSinceEpoch;
    } else if (_anyWord(lower, [
      'menit', 'dakika', 'min', 'minute', 'minuto', 'นาที', 'دقائق',
      'dakika önce',
    ])) {
      ms = now.subtract(Duration(minutes: number)).millisecondsSinceEpoch;
    } else if (_anyWord(
        lower, ['detik', 'segundo', 'second', 'วินาที', 'sec'])) {
      ms = now.subtract(Duration(seconds: number)).millisecondsSinceEpoch;
    } else if (_anyWord(lower, ['week', 'semana', 'hafta'])) {
      ms = now.subtract(Duration(days: number * 7)).millisecondsSinceEpoch;
    } else if (_anyWord(lower, ['month', 'mes', 'ay'])) {
      ms = now.subtract(Duration(days: number * 30)).millisecondsSinceEpoch;
    } else if (_anyWord(lower, ['year', 'año', 'yıl', 'anno'])) {
      ms = now.subtract(Duration(days: number * 365)).millisecondsSinceEpoch;
    } else if (_anyWord(lower, ['ago', 'önce', 'atrás', 'fa'])) {
      // Bare "N ago" — assume days (some sites omit the unit).
      ms = now.subtract(Duration(days: number)).millisecondsSinceEpoch;
    }
    if (ms != null) return ms;
  }

  // Absolute dates via intl.
  if (dateFormat != null && dateFormat.isNotEmpty) {
    var locale = (dateFormatLocale ?? 'en').replaceAll('_', '-');
    if (locale.length > 2) {
      // intl expects e.g. 'pt_BR' / 'en_US' style for custom symbols.
      final parts = locale.split('-');
      if (parts.length == 2) {
        locale = '${parts[0]}_${parts[1].toUpperCase()}';
      }
    }
    try {
      final dt = DateFormat(dateFormat, locale).parse(trimmed);
      return dt.millisecondsSinceEpoch;
    } catch (_) {
      try {
        final dt = DateFormat(dateFormat, 'en').parse(trimmed);
        return dt.millisecondsSinceEpoch;
      } catch (_) {
        // fall through to raw parse
      }
    }
  }
  return DateTime.tryParse(trimmed)?.millisecondsSinceEpoch ??
      DateTime.now().millisecondsSinceEpoch;
}

bool _anyWord(String haystack, List<String> words) =>
    words.any((w) => haystack.contains(w));

/// Extracts the real image URL from an `<img>` element honouring the
/// lazy-loading attributes Madara themes use (data-src, data-lazy-src,
/// srcset).
String? extractImageUrl(dom.Element? img) {
  if (img == null) return null;
  final dataSrc = img.attributes['data-src'];
  if (dataSrc != null && dataSrc.isNotEmpty) return dataSrc.trim();
  final lazySrc = img.attributes['data-lazy-src'];
  if (lazySrc != null && lazySrc.isNotEmpty) return lazySrc.trim();
  final srcset = img.attributes['srcset'];
  if (srcset != null && srcset.isNotEmpty) {
    return srcset.split(' ').first.trim();
  }
  final src = img.attributes['src'];
  if (src != null && src.isNotEmpty) return src.trim();
  return null;
}

/// Everything in [s] before the first occurrence of [marker].
String substringBefore(String s, String marker) {
  final idx = s.indexOf(marker);
  return idx <= 0 ? s : s.substring(0, idx);
}

// ---------------------------------------------------------------------------
// CryptoJS-compatible AES decryption (Madara "wpmangaprotector" chapters).
// ---------------------------------------------------------------------------

class CryptoAES {
  /// Decrypts a CryptoJS `OpenSSL.encrypt` payload: base64 of
  /// `Salted__ | salt(8) | AES-256-CBC(ciphertext)`, key+IV derived from the
  /// passphrase with the OpenSSL EVP_BytesToKey (MD5) KDF.
  static String? decryptAESCryptoJS(String encrypted, String passphrase) {
    try {
      final bytesWithSalt = base64.decode(encrypted.trim());
      if (bytesWithSalt.length <= 16) return null;
      final salt = bytesWithSalt.sublist(8, 16);
      final ct = bytesWithSalt.sublist(16);
      final (key, iv) = deriveKeyAndIV(passphrase.trim(), salt);
      final encrypter = encrypt.Encrypter(
        encrypt.AES(encrypt.Key(key),
            mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
      );
      return encrypter.decrypt64(base64.encode(ct), iv: encrypt.IV(iv));
    } catch (_) {
      return null;
    }
  }

  /// EVP_BytesToKey with MD5: produces a 32-byte key + 16-byte IV.
  static (Uint8List, Uint8List) deriveKeyAndIV(
      String passphrase, List<int> salt) {
    final password = utf8.encode(passphrase);
    var concatenated = <int>[];
    var current = <int>[];
    while (concatenated.length < 48) {
      final preHash = current.isEmpty
          ? [...password, ...salt]
          : [...current, ...password, ...salt];
      current = crypto.md5.convert(preHash).bytes;
      concatenated = [...concatenated, ...current];
    }
    return (
      Uint8List.fromList(concatenated.sublist(0, 32)),
      Uint8List.fromList(concatenated.sublist(32, 48)),
    );
  }
}

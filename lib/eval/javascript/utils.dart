import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:flutter_qjs/quickjs/ffi.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http_interceptor/http_interceptor.dart';
import 'package:js_packer/js_packer.dart';
import 'package:lumina_reader/eval/http_response_extensions.dart';
import 'package:lumina_reader/eval/model/m_bridge.dart';
import 'package:lumina_reader/providers/storage_provider.dart';
import 'package:lumina_reader/services/http/m_client.dart';
import 'package:lumina_reader/utils/cryptoaes/js_unpacker.dart';

class JsUtils {
  late JavascriptRuntime runtime;
  JsUtils(this.runtime);

  void init() {
    runtime.onMessage('log', (dynamic args) {
      debugPrint('JS extension: ${args[0]}');
      return null;
    });
    runtime.onMessage('cryptoHandler', (dynamic args) {
      return MBridge.cryptoHandler((args[0] as String), (args[1] as String), (args[2] as String), (args[3] as bool));
    });
    runtime.onMessage('encryptAESCryptoJS', (dynamic args) {
      return MBridge.encryptAESCryptoJS((args[0] as String), (args[1] as String));
    });
    runtime.onMessage('decryptAESCryptoJS', (dynamic args) {
      return MBridge.decryptAESCryptoJS((args[0] as String), (args[1] as String));
    });
    runtime.onMessage('decryptAESGCM', (dynamic args) {
      // tagHex is optional (empty when already appended); coerce null → "".
      return MBridge.decryptAESGCM((args[0] as String), (args[1] as String), (args[2] as String), (args[3] as String) ?? '');
    });
    runtime.onMessage('deobfuscateJsPassword', (dynamic args) {
      return MBridge.deobfuscateJsPassword((args[0] as String));
    });
    runtime.onMessage('unpackJsAndCombine', (dynamic args) {
      return JsUnpacker.unpackAndCombine((args[0] as String)) ?? "";
    });
    runtime.onMessage('unpackJs', (dynamic args) {
      return JSPacker((args[0] as String)).unpack() ?? "";
    });
    runtime.onMessage('evaluateJavascriptViaWebview', (dynamic args) async {
      // The WebView Cloudflare broker was removed from this build (it had no
      // platform poller and dead-hung 25s x retries). Extensions depending
      // on it receive an honest empty result.
      if (kDebugMode) {
        // ignore: avoid_print
        print('JsUtils: evaluateJavascriptViaWebview requested but the '
            'WebView broker is not shipped; returning empty.');
      }
      return '';
    });
    runtime.onMessage('parseEpub', (dynamic args) async {
      // The Rust EPUB parser is not shipped in this build; only one novel
      // extension in the corpus uses it. Report an empty book instead of
      // crashing the extension runtime.
      return jsonEncode({"title": "", "author": "", "chapters": []});
    });
    runtime.onMessage('parseEpubChapter', (dynamic args) async {
      return "";
    });

    runtime.evaluate('''
console.log = function (message) {
    if (typeof message === "object") {
         message = JSON.stringify(message);
      }
    sendMessage("log", JSON.stringify([message.toString()]));
};
console.warn = function (message) {
    if (typeof message === "object") {
         message = JSON.stringify(message);
      }
    sendMessage("log", JSON.stringify([message.toString()]));
};
console.error = function (message) {
    if (typeof message === "object") {
         message = JSON.stringify(message);
      }
    sendMessage("log", JSON.stringify([message.toString()]));
};
String.prototype.substringAfter = function(pattern) {
    const startIndex = this.indexOf(pattern);
    if (startIndex === -1) return this.substring(0);

    const start = startIndex + pattern.length;
    return this.substring(start);
}

String.prototype.substringAfterLast = function(pattern) {
    return this.split(pattern).pop();
}

String.prototype.substringBefore = function(pattern) {
    const endIndex = this.indexOf(pattern);
    if (endIndex === -1) return this.substring(0);

    return this.substring(0, endIndex);
}

String.prototype.substringBeforeLast = function(pattern) {
    const endIndex = this.lastIndexOf(pattern);
    if (endIndex === -1) return this.substring(0);
    return this.substring(0, endIndex);
}

String.prototype.substringBetween = function(left, right) {
    let startIndex = 0;
    let index = this.indexOf(left, startIndex);
    if (index === -1) return "";
    let leftIndex = index + left.length;
    let rightIndex = this.indexOf(right, leftIndex);
    if (rightIndex === -1) return "";
    startIndex = rightIndex + right.length;
    return this.substring(leftIndex, rightIndex);
}

function cryptoHandler(text, iv, secretKeyString, encrypt) {
    return sendMessage(
        "cryptoHandler",
        JSON.stringify([text, iv, secretKeyString, encrypt])
    );
}
function encryptAESCryptoJS(plainText, passphrase) {
    return sendMessage(
        "encryptAESCryptoJS",
        JSON.stringify([plainText, passphrase])
    );
}
function decryptAESCryptoJS(encrypted, passphrase) {
    return sendMessage(
        "decryptAESCryptoJS",
        JSON.stringify([encrypted, passphrase])
    );
}
function decryptAESGCM(encrypted, keyHex, ivHex, tagHex = "") {
    return sendMessage(
        "decryptAESGCM",
        JSON.stringify([encrypted, keyHex, ivHex, tagHex])
    );
}
function deobfuscateJsPassword(inputString) {
    return sendMessage(
        "deobfuscateJsPassword",
        JSON.stringify([inputString])
    );
}
function unpackJsAndCombine(scriptBlock) {
    return sendMessage(
        "unpackJsAndCombine",
        JSON.stringify([scriptBlock])
    );
}
function unpackJs(packedJS) {
    return sendMessage(
        "unpackJs",
        JSON.stringify([packedJS])
    );
}
function parseDates(value, dateFormat, dateFormatLocale) {
    return sendMessage(
        "parseDates",
        JSON.stringify([value, dateFormat, dateFormatLocale])
    );
}
async function evaluateJavascriptViaWebview(url, headers, scripts) {
    return await sendMessage(
        "evaluateJavascriptViaWebview",
        JSON.stringify([url, headers, scripts])
    );
}
async function parseEpub(bookName, url, headers) {
    return JSON.parse(await sendMessage(
        "parseEpub",
        JSON.stringify([bookName, url, headers])
    ));
}
async function parseEpubChapter(bookName, url, headers, chapterTitle) {
    return await sendMessage(
        "parseEpubChapter",
        JSON.stringify([bookName, url, headers, chapterTitle])
    );
}
''');
  }

}

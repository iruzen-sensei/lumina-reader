import 'package:http_interceptor/http_interceptor.dart';
import 'package:lumina_reader/eval/javascript/xvideo.dart';
import 'package:html/parser.dart' show parse;
import 'package:lumina_reader/services/http/m_client.dart';
import 'package:lumina_reader/utils/extensions/string_extensions.dart';

class StreamTapeExtractor {
  Future<List<XVideo>> videosFromUrl(
    String url, {
    String quality = "StreamTape",
  }) async {
    final InterceptedClient client = MClient.httpClient();
    try {
      const baseUrl = "https://streamtape.com/e/";
      final newUrl = !url.startsWith(baseUrl)
          ? "$baseUrl${url.split("/")[4]}"
          : url;

      final response = await client.get(Uri.parse(newUrl));
      final document = parse(response.body);

      const targetLine = "document.getElementById('robotlink')";
      String script = "";
      final scri = document
          .querySelectorAll("script")
          .where((element) => element.innerHtml.contains(targetLine))
          .map((e) => e.innerHtml)
          .toList();
      if (scri.isEmpty) {
        return [];
      }
      script = scri.first.split("$targetLine.innerHTML = '").last;
      final videoUrl =
          "https:${script.substringBefore("'")}${script.substringAfter("+ ('xcd").substringBefore("'")}";

      return [XVideo(videoUrl, quality, videoUrl)];
    } catch (_) {
      return [];
    }
  }
}

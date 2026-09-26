import 'package:html/parser.dart' show parse;
import 'package:http_interceptor/http_interceptor.dart';
import 'package:lumina_reader/eval/javascript/xvideo.dart';
import 'package:lumina_reader/services/http/m_client.dart';
import 'package:lumina_reader/utils/extensions/string_extensions.dart';

class MytvExtractor {
  final InterceptedClient client = MClient.httpClient();

  Future<List<XVideo>> videosFromUrl(String url) async {
    try {
      final response = await client.get(Uri.parse(url));
      final document = parse(response.body);
      final videoList = <XVideo>[];

      document.querySelectorAll("script").forEach((script) {
        if (script.text.contains("CreatePlayer(\"v")) {
          final videosString = script.text;
          final videoUrl = videosString
              .substringAfter("\"v=")
              .substringBefore("\\u0026tp=video")
              .replaceAll("%26", "&")
              .replaceAll("%3a", ":")
              .replaceAll("%2f", "/")
              .replaceAll("%3f", "?")
              .replaceAll("%3d", "=");

          if (!videoUrl.contains("https:")) {
            videoList.add(XVideo(videoUrl, "Stream", videoUrl));
          } else {
            videoList.add(XVideo(videoUrl, "Mytv", videoUrl));
          }
        }
      });

      return videoList;
    } catch (_) {
      return [];
    }
  }
}

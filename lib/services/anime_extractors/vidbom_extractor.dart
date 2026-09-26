import 'package:http_interceptor/http_interceptor.dart';
import 'package:lumina_reader/eval/javascript/xvideo.dart';
import 'package:lumina_reader/services/http/m_client.dart';
import 'package:lumina_reader/utils/extensions/string_extensions.dart';
import 'package:lumina_reader/utils/xpath_selector.dart';

class VidBomExtractor {
  final InterceptedClient client = MClient.httpClient();

  Future<List<XVideo>> videosFromUrl(String url) async {
    try {
      final response = await client.get(Uri.parse(url));
      final script = xpathSelector(response.body)
          .queryXPath('//script[contains(text(), "sources")]/text()')
          .attrs;

      final data = script.first!
          .substringAfter('sources: [')
          .substringBefore('],');

      return data.split('file:"').skip(1).map((source) {
        final src = source.substringBefore('"');
        var quality =
            'Vidbom - ${source.substringAfter('label:"').substringBefore('"')}';
        if (quality.length > 15) {
          quality = 'Vidshare - 480p';
        }
        return XVideo(src, quality, src);
      }).toList();
    } catch (_) {
      return [];
    }
  }
}

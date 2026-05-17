import 'package:app_links/app_links.dart';
import 'launch_service.dart';
import 'log_service.dart';

class DeepLinkService {
  static final instance = DeepLinkService._();
  DeepLinkService._();

  final _appLinks = AppLinks();

  void init() {
    
    _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri);
    });

    
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleUri(uri);
      }
    });
  }

  void _handleUri(Uri uri) {
    vLog('RECEIVED DEEP LINK: $uri');
    if (uri.scheme == 'vantage' && uri.host == 'launch') {
      final itemId = uri.queryParameters['itemId'];
      vLog('DEEP LINK ACTION: launch | ITEM ID: $itemId');
      if (itemId != null) {
        LaunchService.instance.launchItem(itemId);
      }
    } else {
      vLog('IGNORED DEEP LINK: Unsupported scheme/host');
    }
  }
}

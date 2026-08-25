import 'package:flutter/services.dart';

/// Platform storage query used only as a preflight guard before a large
/// offline download. It deliberately has no Google/Play dependency.
class OfflineStorageService {
  static const _channel = MethodChannel('app.wildbit/storage');

  Future<int?> availableBytes() async {
    try {
      final value = await _channel.invokeMethod<int>('availableStorageBytes');
      return value == null || value < 0 ? null : value;
    } on MissingPluginException {
      // Desktop/iOS implementations can be added independently; an unknown
      // value never blocks a user from starting a download.
      return null;
    } on PlatformException {
      return null;
    }
  }
}

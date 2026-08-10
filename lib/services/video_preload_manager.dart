import 'api_client.dart';

/// URL resolution helper for video URLs.
/// MediaKit handles its own buffering internally — no player pool needed.
class VideoPreloadManager {
  static final VideoPreloadManager _instance = VideoPreloadManager._internal();
  factory VideoPreloadManager() => _instance;
  VideoPreloadManager._internal();

  /// Resolve relative /uploads/ paths and fix known CDN issues.
  String resolveUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) {
      // Fix commondatastorage → storage.googleapis.com redirect issue
      if (url.contains('commondatastorage.googleapis.com')) {
        return url.replaceAll(
          'commondatastorage.googleapis.com',
          'storage.googleapis.com',
        );
      }
      return url;
    }
    if (url.startsWith('/')) {
      return 'http://${ApiClient.serverHost}:${ApiClient.serverPort}$url';
    }
    return url;
  }

  String getWorkingVideoUrl(String url, {int index = 0}) => resolveUrl(url);

  // No-op — kept for API compatibility
  Future<void> preloadVideos(List<String> urls, int currentIndex) async {}
  void disposeAll() {}
}

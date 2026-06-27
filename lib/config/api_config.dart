/// Central place for all backend URLs.
///
/// The Railway deployment uses HTTPS, so iOS ATS (App Transport Security)
/// allows it with no extra Info.plist configuration needed.
///
/// NOTE: if the backend takes more than ~30 s on a cold start (Railway
/// free-tier sleep), the app will show an error.  Tap "Try again" and the
/// second request will succeed once the dyno is warm.
class ApiConfig {
  ApiConfig._();

  static const String baseUrl =
      'https://calm-mind-backend-production-21d2.up.railway.app';

  static const String chatEndpoint   = '/chat';
  static const String healthEndpoint = '/health';

  /// Full URL for the chat POST.
  static const String chatUrl = '$baseUrl$chatEndpoint';
}

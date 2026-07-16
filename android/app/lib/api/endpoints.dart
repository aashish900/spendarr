/// Backend REST paths, appended to the user-supplied base URL (Settings).
///
/// Only `/health` is live in offline-only mode. Sync (`/sync/push`,
/// `/sync/pull`) and `/summary` are added with their milestones (B7, B5).
class Endpoints {
  Endpoints._();

  static const String apiV1 = '/api/v1';

  /// Liveness probe for the "Test connection" button. Auth scope: none
  /// (the bearer is still sent by the interceptor; the endpoint ignores it).
  static const String health = '$apiV1/health';
}

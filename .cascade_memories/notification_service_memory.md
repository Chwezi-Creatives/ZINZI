# Notification Service Memory Backup
Last updated: 2025-07-31 10:45:00+03:00

## Notification Service Architecture

### Overview
The notification service provides a unified API for handling push notifications across all platforms (Web, iOS, Android, macOS) while abstracting away platform-specific implementations.

### Key Design Principles
1. **Single Entry Point**: All notification functionality is accessed through the NotificationService singleton.
2. **Platform Abstraction**: Platform-specific code is isolated in separate files:
   - `notification_service_web.dart` for web implementation
   - `notification_service_io.dart` for native platforms
3. **Graceful Degradation**: Features not available on all platforms degrade gracefully with appropriate fallbacks.
4. **Consistent API**: The public API remains consistent across platforms.

## Platform Support Matrix
| Feature        | Web        | Native      | Notes                      |
|----------------|------------|-------------|----------------------------|
| FCM Tokens     | ✅         | ✅          |                            |
| Foreground     | ✅         | ✅          |                            |
| Background     | ✅         | ✅          |                            |
| Local Notifs   | ❌         | ✅          | Web uses browser API       |
| Click Actions  | ✅         | ✅          |                            |
| Badges         | ✅         | ✅          |                            |
| Sounds         | ✅         | ✅          |                            |

## Implementation Details

### Web Implementation (`notification_service_web.dart`)
- Uses browser's Notification API for showing notifications
- Requires user permission to display notifications
- Falls back to no-op if notifications are not supported
- Handles service worker registration for background messages

### Native Implementation (`notification_service_io.dart`)
- Uses `flutter_local_notifications` package
- Supports all native notification features (sounds, badges, actions)
- Handles notification taps and data passing
- Implements platform-specific channels (Android) and categories (iOS)

### Common Patterns
- Token management and refresh
- Background message handling
- Notification tap actions
- Error handling and logging

## Versioning & Backward Compatibility
- When adding new features, maintain backward compatibility
- Deprecate old methods instead of removing them
- Update documentation when making changes
- Test on all target platforms before deployment

## Common Pitfalls
1. Web requires HTTPS for service workers to work
2. iOS needs proper entitlements and capabilities
3. Android requires proper notification channels
4. Always test on all target platforms

## File Structure
```
lib/
  services/
    notification_service.dart       # Main service implementation
    notification_service_web.dart  # Web-specific implementation
    notification_service_io.dart   # Native platform implementation
```

## Related Files
- `web/firebase-messaging-sw.js` - Service worker for web notifications
- `web/index.html` - Web entry point with service worker registration
- `pubspec.yaml` - Dependencies for notifications (firebase_messaging, flutter_local_notifications)

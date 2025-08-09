# Manual Memory Backup
Created: 2025-07-31 10:53:00+03:00
Last Updated: 2025-07-31 11:05:00+03:00

## Memory 0: Memory Backup and Update Procedure
**ID**: deddc41b-3142-43d4-80b9-8e2d0aebeda3
**Tags**: backup_procedure, documentation, best_practices, memory_management

### Core Principle
Always maintain two parallel copies of important information:
1. In Cascade's memory system
2. In local backup files (`.cascade_memories/` directory)

### Update Process
1. **Memory First**: Any new information or updates must first be saved to Cascade's memory system
2. **Immediate Local Backup**: After updating memory, immediately update the corresponding local backup file
3. **Verification**: Verify that the local backup file contains all the latest information

### File Structure
- `.cascade_memories/` - Root directory for all memory backups
  - `manual_memory_backup.md` - Main backup file (human-readable)
  - `backup_memories.py` - Python backup script
  - `backup_memories.sh` - Bash backup script (alternative)
  - `README.md` - Instructions for using the backup system

### Key Rules
- Never rely solely on Cascade's memory system
- Always update local backups when making changes
- Keep backup files in sync with memory updates
- Document any special considerations in the backup files
- Follow the format and structure of existing backups

### Best Practices
- Use clear, descriptive titles for memories
- Include relevant tags for easy searching
- Add timestamps to track when updates were made
- Keep backup files organized and well-formatted
- Document any dependencies or related files

---

## Memory 1: Web Push Notification Implementation
**ID**: 3c808378-7e7a-4b21-8403-40e1545fd130
**Tags**: notifications, web, implementation, fcm

### Current Implementation (DO NOT MODIFY)

#### 1. Service Worker (firebase-messaging-sw.js)
- Uses Firebase Messaging v9.2.0 (compat version)
- Handles background messages and displays notifications
- Configured with production Firebase project credentials
- Automatically shows notifications with title, body, and app icon
- Logs background message receipt for debugging

#### 2. HTML Configuration (index.html)
- Registers the service worker on page load
- Includes necessary meta tags for PWA support
- Loads Google Maps API (separate from notifications)
- Uses deferred loading for better performance

#### 3. Notification Service (notification_service.dart)
- Handles both web and native platforms
- Web-specific features:
  - Uses browser's Notification API for foreground notifications
  - Configures Firebase for web push notifications
  - Handles permission requests
  - Includes test notification functionality
- Properly initializes Firebase for web
- Handles notification taps and callbacks

#### 4. Critical Implementation Notes
- Uses Firebase v9.2.0 for web compatibility
- Service worker is registered at the root scope ('/')
- Icons are served from the /icons/ directory
- Debug logging is enabled for troubleshooting

## Memory 2: Import and Error Handling Standards
**ID**: 6f4378fc-417b-4d37-8d82-14ae38331c31
**Tags**: imports, error_handling, code_standards

### 1. Import Management
- Always use absolute imports starting with 'package:'
- Group imports in the following order:
  1. Dart/Flutter SDK imports
  2. Package imports (pub.dev packages)
  3. Local project imports (using 'package:zinzi/')
- When adding a new import, ensure all required dependencies are added to pubspec.yaml
- Run `flutter pub get` after adding new dependencies

### 2. Error-Free Code
- Never commit code with errors or warnings (except TODOs marked with issue numbers)
- Run `flutter analyze` before considering any task complete
- Fix all analyzer warnings unless there's a specific reason not to
- Ensure all tests pass before finalizing changes
- For test files, mock all external dependencies

### 3. Test File Standards
- Import all necessary test utilities and mocks
- Use proper test setup and teardown
- Mock all external services and dependencies
- Ensure test files can run independently
- Add clear test descriptions

### 4. Dependency Management
- Always specify exact versions in pubspec.yaml
- Document why each dependency is needed
- Keep dependencies up to date with security patches
- Use `dependency_overrides` sparingly and document the reason

## Memory 3: Zinzi Project Technical Specifications
**ID**: 304ec9e9-128c-430c-84af-0873acf58670
**Tags**: technical_specs, architecture, flutter, fastapi, postgresql

### Frontend
- **Framework**: Flutter 3.27.1
  - Do not upgrade Flutter version without explicit permission
  - All development must work within the current Flutter version
  - Test thoroughly on all target platforms before considering any version updates

### Backend
- **Framework**: Python FastAPI
  - Must maintain high performance and efficiency
  - Ensure all operations are non-blocking
  - Prioritize robustness and reliability
  - Optimize for speed in all API responses
- **Database**: PostgreSQL
  - All database queries must be optimized for performance
  - Use appropriate indexing for frequently queried columns
  - Implement efficient JOIN operations
  - Monitor and optimize slow queries
  - Use connection pooling effectively

## Memory 4: FCM Token Registration System
**ID**: 279a1417-26e9-41f1-996a-aee63dd3f629
**Tags**: fcm, notifications, registration, mobile

### Current Implementation
1. **User ID Storage Pattern**:
   - Each user type (user, chef, producer, stakeholder) stores their ID in both:
     - Type-specific key (e.g., `chef_user_id`, `producer_id`)
     - Standardized `user_id` key for FCM token registration
   - All IDs are stored as strings for consistency

2. **FCM Token Registration Flow**:
   - Happens automatically after successful login via `saveUserDetails`
   - Uses `user_id` and `user_type` from SharedPreferences
   - Falls back to 'unknown' if values not found
   - Sends to `/api/register-fcm-token` endpoint

3. **Data Structure Sent**:
   ```json
   {
     "fcm_token": "token_here",
     "user_id": "id_from_prefs",
     "user_type": "user_type_from_prefs",
     "platform": "os_name",
     "app_version": "1.0.0"
   }
   ```

### Critical Compatibility Rules
1. **DO NOT** modify the existing key structure in SharedPreferences
2. **ALWAYS** maintain both type-specific and standardized keys
3. **NEVER** change the FCM registration data structure without:
   - Updating the backend to handle the new structure
   - Implementing backward compatibility
   - Updating all client applications
4. **PRESERVE** the fallback to 'unknown' values
5. **MAINTAIN** string type for all IDs in SharedPreferences

## Memory 5: FCM Token Behavior and Registration Flow
**ID**: b2518dff-eaec-4744-a2e6-1c5f1b91c7da
**Tags**: fcm, tokens, registration_flow, mobile

### Token Generation and Stability
- FCM tokens are generated once per app installation and remain stable across app restarts
- Tokens typically only change in these scenarios:
  - App is uninstalled and reinstalled
  - User clears app data
  - Token is explicitly refreshed by Firebase
  - App is restored on a new device

### Registration Flow
1. **Initial Registration**:
   - Token is generated on first app launch
   - Stored in SharedPreferences for persistence
   - Sent to backend during user login

2. **Subsequent Launches**:
   - Existing token is reused from SharedPreferences
   - Not resent to backend unless invalidated
   - Token refresh is handled automatically by Firebase

3. **Token Refresh Handling**:
   - `onTokenRefresh` listener detects when token changes
   - New token is automatically sent to backend
   - Old token is automatically invalidated by FCM

### Backend Communication
- Tokens are only sent to backend when:
  - User logs in (new or existing session)
  - Token is refreshed by Firebase
  - App is reinstalled
- Backend receives token with user context (user_id, user_type)
- Token is associated with device/platform information

## Memory 6: Notification Service Architecture
**ID**: 47b5957a-c6aa-432b-b4ba-c04bc4bc99cd
**Tags**: notifications, architecture, documentation, flutter, fcm

### Overview
The notification service provides a unified API for handling push notifications across all platforms (Web, iOS, Android, macOS) while abstracting away platform-specific implementations.

### Key Design Principles
1. **Single Entry Point**: All notification functionality is accessed through the NotificationService singleton.
2. **Platform Abstraction**: Platform-specific code is isolated in separate files:
   - `notification_service_web.dart` for web implementation
   - `notification_service_io.dart` for native platforms
3. **Graceful Degradation**: Features not available on all platforms degrade gracefully with appropriate fallbacks.
4. **Consistent API**: The public API remains consistent across platforms.

### Platform Support Matrix
| Feature        | Web        | Native      | Notes                      |
|----------------|------------|-------------|----------------------------|
| FCM Tokens     | ✅         | ✅          |                            |
| Foreground     | ✅         | ✅          |                            |
| Background     | ✅         | ✅          |                            |
| Local Notifs   | ❌         | ✅          | Web uses browser API       |
| Click Actions  | ✅         | ✅          |                            |
| Badges         | ✅         | ✅          |                            |
| Sounds         | ✅         | ✅          |                            |

### Implementation Details

#### Web Implementation (`notification_service_web.dart`)
- Uses browser's Notification API for showing notifications
- Requires user permission to display notifications
- Falls back to no-op if notifications are not supported
- Handles service worker registration for background messages

#### Native Implementation (`notification_service_io.dart`)
- Uses `flutter_local_notifications` package
- Supports all native notification features (sounds, badges, actions)
- Handles notification taps and data passing
- Implements platform-specific channels (Android) and categories (iOS)

### Common Patterns
- Token management and refresh
- Background message handling
- Notification tap actions
- Error handling and logging

### Versioning & Backward Compatibility
- When adding new features, maintain backward compatibility
- Deprecate old methods instead of removing them
- Update documentation when making changes
- Test on all target platforms before deployment

### Common Pitfalls
1. Web requires HTTPS for service workers to work
2. iOS needs proper entitlements and capabilities
3. Android requires proper notification channels
4. Always test on all target platforms

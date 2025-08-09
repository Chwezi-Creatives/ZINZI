import Cocoa
import FlutterMacOS
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate, MessagingDelegate {
  
  override init() {
    super.init()
    // Initialize Firebase
    FirebaseApp.configure()
    
    // Set up Firebase Messaging
    Messaging.messaging().delegate = self
    
    // Set up notification center delegate
    UNUserNotificationCenter.current().delegate = self
  }
  
  override func applicationDidFinishLaunching(_ aNotification: Notification) {
    // Initialize Firebase if not already initialized
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }
    
    // Request notification permissions
    requestNotificationPermission()
    
    // Set notification delegate
    UNUserNotificationCenter.current().delegate = self
    
    super.applicationDidFinishLaunching(aNotification)
  }
  
  private func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
      DispatchQueue.main.async {
        if granted {
          print("Notification permission granted")
          NSApplication.shared.registerForRemoteNotifications()
          
          // Update application icon badge
          NSApplication.shared.dockTile.badgeLabel = nil
        } else {
          print("Notification permission denied")
        }
        
        if let error = error {
          print("Error requesting notification permission: \(error.localizedDescription)")
        }
      }
    }
  }
  
  // Handle successful registration for remote notifications
  override func application(_ application: NSApplication, 
                          didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
    let token = tokenParts.joined()
    print("APNs device token: \(token)")
    
    // On macOS, we don't use Firebase Cloud Messaging (FCM) directly
    // The token can be used with your own notification service if needed
  }
  
  // Handle failure to register for remote notifications
  override func application(_ application: NSApplication, 
                          didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("Failed to register for remote notifications: \(error.localizedDescription)")
  }
  
  // MARK: - FCM Token Handling
  
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("Firebase registration token: \(fcmToken ?? "")")
    
    // Send token to your server if needed
    if let token = fcmToken {
      // You can send this token to your server here
      print("FCM Token: \(token)")
    }
  }
  
  // MARK: - Notification Handling
  
  // Handle silent notifications
  func application(_ application: NSApplication, 
                 didReceiveRemoteNotification userInfo: [String: Any],
                 fetchCompletionHandler completionHandler: @escaping () -> Void) {
    print("Received remote notification: \(userInfo)")
    completionHandler()
  }
  
  // MARK: - App Lifecycle
  
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
  
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
  // Handle notification when app is in foreground (macOS 10.15+)
  @available(macOS 10.15, *)
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                            willPresent notification: UNNotification,
                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    let userInfo = notification.request.content.userInfo
    print("Will present notification: \(userInfo)")
    
    // Show the notification with banner, sound, and badge
    if #available(macOS 11.0, *) {
      completionHandler([[.banner, .sound, .badge]])
    } else {
      // Fallback for macOS 10.15
      completionHandler([[.alert, .sound, .badge]])
    }
  }
  
  // Handle notification tap
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse,
                            withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo
    print("Notification tapped with userInfo: \(userInfo)")
    
    // Handle the notification tap as needed
    // You can post a notification that your Flutter code can observe if needed
    
    completionHandler()
  }
}

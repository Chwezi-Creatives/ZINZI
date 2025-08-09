import UIKit
import Flutter
import GoogleMaps
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import os.log

@main
@objc class AppDelegate: FlutterAppDelegate, MessagingDelegate {
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialize Firebase
    FirebaseApp.configure()
    
    // Configure Firebase Messaging
    configureFirebaseMessaging(application)
    
    // Provide Google Maps API Key
    GMSServices.provideAPIKey("AIzaSyDqbiGKI-dtc6QZV9VSgXRp1Viqu5a3A1w")
    
    // Register with Flutter plugins
    GeneratedPluginRegistrant.register(with: self)
    
    // Call super last to ensure Flutter is fully set up
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // MARK: - Firebase Messaging Configuration
  
  private func configureFirebaseMessaging(_ application: UIApplication) {
    // Set Firebase Messaging delegate
    Messaging.messaging().delegate = self
    
    // Set up notification center delegate
    UNUserNotificationCenter.current().delegate = self
    
    // Request notification authorization
    requestNotificationAuthorization(application)
    
    // Register for remote notifications
    application.registerForRemoteNotifications()
  }
  
  private func requestNotificationAuthorization(_ application: UIApplication) {
    let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound, .provisional]
    let notificationCenter = UNUserNotificationCenter.current()
    
    // First, remove any existing notification delegate to prevent duplicate registrations
    notificationCenter.removeAllPendingNotificationRequests()
    notificationCenter.removeAllDeliveredNotifications()
    
    // Request authorization with options
    notificationCenter.requestAuthorization(options: authOptions) { [weak self] granted, error in
      DispatchQueue.main.async {
        if let error = error {
          os_log("Error requesting notification authorization: %{public}@", 
                type: .error, error.localizedDescription)
          return
        }
        
        os_log("Notification authorization granted: %{public}@", 
              type: .info, granted ? "true" : "false")
        
        // Get current notification settings
        notificationCenter.getNotificationSettings { settings in
          os_log("Notification settings: %{public}@", settings.debugDescription)
          
          // Register for remote notifications if authorized
          if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            DispatchQueue.main.async {
              application.registerForRemoteNotifications()
              
              // Configure notification categories for interactive notifications
              self?.configureNotificationCategories()
            }
          }
        }
      }
    }
    
    // Set the badge count to zero on launch
    UIApplication.shared.applicationIconBadgeNumber = 0
  }
  
  private func configureNotificationCategories() {
    // Define the actions
    let replyAction = UNTextInputNotificationAction(
      identifier: "REPLY_ACTION",
      title: "Reply",
      options: []
    )
    
    let viewAction = UNNotificationAction(
      identifier: "VIEW_ACTION",
      title: "View",
      options: [.foreground]
    )
    
    // Define the category with actions
    let messageCategory = UNNotificationCategory(
      identifier: "MESSAGE_CATEGORY",
      actions: [replyAction, viewAction],
      intentIdentifiers: [],
      options: []
    )
    
    // Register the category
    UNUserNotificationCenter.current().setNotificationCategories([messageCategory])
  }
  
  // MARK: - APNs Registration
  
  override func application(_ application: UIApplication, 
                          didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    // Forward the APNs token to Firebase Messaging
    Messaging.messaging().apnsToken = deviceToken
    
    // Log the token for debugging
    let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
    let token = tokenParts.joined()
    os_log("APNs device token: %{public}@", type: .info, token)
    
    // Store the token in UserDefaults for debugging
    UserDefaults.standard.set(token, forKey: "apnsDeviceToken")
    
    // This will trigger the messaging:didReceiveRegistrationToken: delegate method
    // which will handle the FCM token
  }
  
  override func application(_ application: UIApplication, 
                          didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("Failed to register for remote notifications: \(error.localizedDescription)")
  }
  
  // MARK: - MessagingDelegate
  
  func messaging(_ messaging: Messaging, 
                didReceiveRegistrationToken fcmToken: String?) {
    guard let fcmToken = fcmToken else {
      os_log("No FCM token available", type: .error)
      return
    }
    
    // Log the token for debugging
    os_log("Firebase registration token: %{public}@", type: .info, fcmToken)
    
    // Store the token in UserDefaults for debugging
    UserDefaults.standard.set(fcmToken, forKey: "fcmToken")
    
    // Send token to your server if needed
    // Note: This callback is fired at each app startup and whenever a new token is generated
    // The FCM token is what you should use for sending push notifications
    sendTokenToServer(fcmToken: fcmToken)
  }
  
  private func sendTokenToServer(fcmToken: String) {
    // TODO: Implement your server token registration logic here
    // This is where you would typically send the FCM token to your backend
    // Example:
    // NetworkManager.shared.registerDeviceToken(fcmToken) { result in
    //   switch result {
    //   case .success():
    //     os_log("Successfully registered FCM token with server", type: .info)
    //   case .failure(let error):
    //     os_log("Failed to register FCM token: %{public}@", 
    //           type: .error, error.localizedDescription)
    //   }
    // }
    
    os_log("FCM Token ready to be sent to server: %{public}@", 
          type: .info, fcmToken.prefix(10) + "...")
    
    // You can subscribe to topics here if needed
    // Messaging.messaging().subscribe(toTopic: "all_users") { error in
    //   print("Subscribed to topic: all_users")
    // }
  }
  
  // MARK: - UNUserNotificationCenterDelegate
  
  // Handle notification when app is in foreground
  @available(iOS 10.0, *)
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    let userInfo = notification.request.content.userInfo
    print("Will present notification: \(userInfo)")
    
    // With swizzling disabled, you must let Messaging know about the message
    // Messaging.messaging().appDidReceiveMessage(userInfo)
    
    // Show the notification even when the app is in the foreground
    // You can customize these options based on your needs
    completionHandler([[.banner, .sound, .badge]])
  }
  
  // Handle notification tap
  @available(iOS 10.0, *)
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    didReceive response: UNNotificationResponse,
                                    withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo
    print("User tapped notification: \(userInfo)")
    
    // Handle notification tap here
    // You can navigate to specific screens based on the notification data
    
    // Example of handling deep links from notification
    // if let deepLink = userInfo["deep_link"] as? String {
    //   // Handle deep link
    //   print("Deep link: \(deepLink)")
    // }
    
    completionHandler()
  }
  
  // MARK: - Background Refresh
  
  // Handle silent notifications (background data fetch)
  override func application(_ application: UIApplication,
                          didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                          fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    print("Received silent notification: \(userInfo)")
    
    // Handle the silent notification
    // This is called when a silent notification is received in the background
    // or when the app is in the foreground
    
    // Call the completion handler with the appropriate result
    completionHandler(.newData)
  }
}
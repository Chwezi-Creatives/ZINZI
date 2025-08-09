// /web/firebase-messaging-sw.js

// These scripts are required for the service worker to function.
importScripts("https://www.gstatic.com/firebasejs/9.2.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.2.0/firebase-messaging-compat.js");

// Use the Firebase configuration from your firebase_options.dart to ensure consistency.
const firebaseConfig = {
  apiKey: 'AIzaSyAtPIxFkbzNtZ8_9ADNmb_6IriS_0jD4kE',
  authDomain: 'zinzi-fcm2.firebaseapp.com',
  projectId: 'zinzi-fcm2',
  storageBucket: 'zinzi-fcm2.firebasestorage.app',
  messagingSenderId: '140229310127',
  appId: '1:140229310127:web:05f48494c489bd048b065a',
  measurementId: 'G-HFLZEDCKZN',
};

// Initialize the Firebase app in the service worker.
firebase.initializeApp(firebaseConfig);

// Retrieve an instance of Firebase Messaging to handle background messages.
const messaging = firebase.messaging();

// Add a handler for background messages.
messaging.onBackgroundMessage(function(payload) {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  
  // Customize the notification that is shown to the user.
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/icons/Icon-192.png'
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});
importScripts('https://www.gstatic.com/firebasejs/9.0.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.0.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyAtPIxFkbzNtZ8_9ADNmb_6IriS_0jD4kE",
  authDomain: "zinzi-fcm2.firebaseapp.com",
  projectId: "zinzi-fcm2",
  storageBucket: "zinzi-fcm2.firebasestorage.app",
  messagingSenderId: "140229310127",
  appId: "1:140229310127:web:05f48494c489bd048b065a",
  measurementId: "G-HFLZEDCKZN"
});

const messaging = firebase.messaging();

// Optionally, handle background messages:
messaging.onBackgroundMessage(function(payload) {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  // Customize notification here
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/icons/Icon-192.png' // Update path if you have a custom icon
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
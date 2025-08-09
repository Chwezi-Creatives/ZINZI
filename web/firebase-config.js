// Firebase configuration and version management
// This file is used to keep Firebase SDK versions in sync across the project

const firebaseConfig = {
  apiKey: "AIzaSyAtPIxFkbzNtZ8_9ADNmb_6IriS_0jD4kE",
  authDomain: "zinzi-fcm2.firebaseapp.com",
  projectId: "zinzi-fcm2",
  storageBucket: "zinzi-fcm2.firebasestorage.app",
  messagingSenderId: "140229310127",
  appId: "1:140229310127:web:917ace6ee004c6c18b065a",
  measurementId: "G-R0FCP7HS7Z"
};

// Firebase SDK versions
const firebaseSDKVersion = '10.7.2'; // This should match the version in pubspec.yaml

// Export the configuration
if (typeof module !== 'undefined' && module.exports) {
  // For Node.js/CommonJS
  module.exports = { firebaseConfig, firebaseSDKVersion };
} else {
  // For browser/ES modules
  window.firebaseConfig = firebaseConfig;
  window.firebaseSDKVersion = firebaseSDKVersion;
}

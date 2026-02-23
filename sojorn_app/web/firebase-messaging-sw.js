importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

// Firebase config is loaded from firebase-config.js (gitignored, generated at deploy time).
// See firebase-config.js.template for the template.
importScripts('/firebase-config.js');

firebase.initializeApp(FIREBASE_CONFIG);

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const title = notification.title || 'New Message';
  const options = {
    body: notification.body || 'Encrypted message received',
    data: payload.data || {},
  };
  self.registration.showNotification(title, options);
});

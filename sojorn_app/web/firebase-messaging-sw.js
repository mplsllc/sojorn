importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'FIREBASE_API_KEY_REDACTED',
  authDomain: 'sojorn-a7a78.firebaseapp.com',
  projectId: 'sojorn-a7a78',
  storageBucket: 'sojorn-a7a78.firebasestorage.app',
  messagingSenderId: '486753572104',
  appId: '1:486753572104:web:d3e6ab825d1e008f9fc8bd',
  measurementId: 'G-702W5531Z3',
});

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

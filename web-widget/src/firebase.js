import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import { getFunctions } from 'firebase/functions';

// Same web app config as lib/firebase_options.dart — reuses the Firebase
// web app already registered for this project, no new registration needed.
const firebaseConfig = {
  apiKey: 'AIzaSyB0xiDPvQ9mb_CFRtwlzwMHh3g_pgjDD0o',
  authDomain: 'fitness-booking-app-23bdc.firebaseapp.com',
  projectId: 'fitness-booking-app-23bdc',
  storageBucket: 'fitness-booking-app-23bdc.firebasestorage.app',
  messagingSenderId: '100021036305',
  appId: '1:100021036305:web:e4f9d3a3509a31cf1298b0',
  measurementId: 'G-L7N9CRZQHL',
};

export const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);

// Cloud Functions are deployed to asia-southeast1 (see functions/index.js
// setGlobalOptions) — the default region (us-central1) would silently fail
// to find any of these functions.
export const functions = getFunctions(app, 'asia-southeast1');

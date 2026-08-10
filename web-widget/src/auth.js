import {
  GoogleAuthProvider,
  OAuthProvider,
  onAuthStateChanged,
  signInWithPopup,
  signOut,
} from 'firebase/auth';
import { doc, getDoc, serverTimestamp, setDoc } from 'firebase/firestore';
import { auth, db } from './firebase.js';

// Mirrors the first-login write in lib/screens/login/login_screen.dart's
// _upsertUserAndFinish (lines 138-152), simplified for a public widget:
// no invitation lookup, no super-admin bootstrap — every widget signup is
// a plain client. adminPermissions is always written by the native app
// even for clients, so it's included here for schema consistency.
async function upsertUser(user) {
  const userRef = doc(db, 'users', user.uid);
  const existing = await getDoc(userRef);
  if (existing.exists()) return;

  await setDoc(userRef, {
    email: user.email ?? '',
    name: user.displayName ?? '',
    photoUrl: user.photoURL ?? '',
    role: 'client',
    adminPermissions: [],
    credits: 0,
    memberships: [],
    createdAt: serverTimestamp(),
  });
}

export async function signInWithGoogle() {
  const result = await signInWithPopup(auth, new GoogleAuthProvider());
  await upsertUser(result.user);
  return result.user;
}

export async function signInWithApple() {
  const provider = new OAuthProvider('apple.com');
  const result = await signInWithPopup(auth, provider);
  await upsertUser(result.user);
  return result.user;
}

export function signOutUser() {
  return signOut(auth);
}

export function watchAuthState(callback) {
  return onAuthStateChanged(auth, callback);
}

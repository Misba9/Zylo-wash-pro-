// Production Firebase wiring (PRD §3.2). When VITE_FIREBASE_* env vars are absent the app runs in DEMO MODE using the local store (same business logic as Cloud Functions). To go live: install firebase, uncomment, set .env.local.
// export const firebaseConfig = { apiKey: import.meta.env.VITE_FIREBASE_API_KEY, authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN, projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID, storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET, messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID, appId: import.meta.env.VITE_FIREBASE_APP_ID };
export const isDemoMode = !import.meta.env.VITE_FIREBASE_PROJECT_ID;
export const firebaseProjectId = import.meta.env.VITE_FIREBASE_PROJECT_ID as string | undefined;

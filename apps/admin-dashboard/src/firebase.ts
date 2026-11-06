// Production Firebase wiring (PRD §3.2). Without VITE_FIREBASE_* vars the dashboard runs in DEMO MODE (local seed + shared business logic). Go-live steps in README/docs/deployment.md.
export const isDemoMode = !import.meta.env.VITE_FIREBASE_PROJECT_ID;
export const firebaseProjectId = import.meta.env.VITE_FIREBASE_PROJECT_ID as string | undefined;

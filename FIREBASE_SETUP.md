# Firebase / FCM setup (Huddle)

Android-first push notifications. Real delivery needs a Firebase project and
service-account credentials on the Nest API.

## 1. Firebase Console (Android app)

1. Create a Firebase project (or use an existing one).
2. Add an Android app with package name **`com.huddle.huddle`**.
3. Download `google-services.json`.
4. Replace [`android/app/google-services.json`](android/app/google-services.json)
   (the checked-in file is a placeholder and will not receive real FCM tokens).

Gradle already applies the Google Services plugin:

- Root: `android/settings.gradle.kts` → `com.google.gms.google-services`
- App: `android/app/build.gradle.kts` → `id("com.google.gms.google-services")`

`POST_NOTIFICATIONS` is declared in `AndroidManifest.xml` (API 33+).

## 2. Nest backend env

In `huddle-backend/.env` (never commit secrets):

```env
FIREBASE_PROJECT_ID="your-project-id"
FIREBASE_CLIENT_EMAIL="firebase-adminsdk-...@....iam.gserviceaccount.com"
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

Or point at a local JSON file:

```env
FIREBASE_SERVICE_ACCOUNT_PATH="D:/secrets/huddle-firebase-adminsdk.json"
```

Download the service account from Firebase Console → Project settings →
Service accounts → Generate new private key.

## 3. Database

Apply the Prisma migration that adds `UserDevice` and `notifications`:

```bash
cd huddle-backend
npx prisma migrate deploy
# or: npx prisma migrate dev
```

## 4. Smoke test

1. Start Nest (`npm run start:dev`) with Firebase env set.
2. Run the Flutter app against your API (`API_BASE_URL`).
3. Sign in → grant notification permission → confirm `POST /api/users/register-device`.
4. Approve/reject/submit/reimburse an expense → recipient should get a tray/banner.
5. Tap notification → opens expense detail (`/expenses/:id`).
6. Bell on Today / Expenses → history list with unread badge.

## Out of scope (this pass)

- iOS `GoogleService-Info.plist` / APNs
- Web FCM
- Comment / reminder / announcement senders (enum ready; hooks later)

# Huddle

Flutter client for the Huddle workspace app (tasks, expenses, team, org admin).

## Run

Requires the Nest API to be reachable (`GET /api/health`). If the API is down, the app shows a retry screen and does not open.

**Production API (default):** `https://huddle-backend-api.vercel.app/api`

```powershell
flutter run -d <device>
```

Local API override:

```powershell
flutter run -d <device> --dart-define=API_BASE_URL=http://192.168.x.x:3000/api
```

Release APK (production API):

```powershell
flutter build apk --release
```

Backend: `../huddle-backend`. Default seed login: `admin@gmail.com` / `test@123`.

# Hospital Dashboard (React + Vite)

```bash
cp .env.example .env     # set VITE_API_BASE_URL to the FastAPI backend
npm install
npm run dev              # http://localhost:5173
```

Sign-in is Google OAuth: set `VITE_GOOGLE_CLIENT_ID` (the same web client ID as the
backend's `GOOGLE_CLIENT_ID`) and add `http://localhost:5173` to that client's
authorized JavaScript origins. A Google account signing in for the first time is
asked for its hospital's name, location and departments; the account then manages
that hospital. For local work without Google, set `VITE_ALLOW_DEV_LOGIN=true` here
and `ALLOW_DEV_LOGIN=true` in the backend `.env`.

Backend notes: run `alembic upgrade head` once (adds `incidents.transcript`, the
driver tables and the `hospital_accounts` table).
CORS is open only when `APP_ENV=development` in the backend `.env`.

Endpoints used: `POST /auth/google`, `POST /auth/register/hospital`, `GET /auth/me`,
`GET/PATCH /hospitals/{id}`,
`GET /hospitals/{id}/broadcasts?status=pending|accepted`,
`POST /incidents/{incident_id}/broadcasts/{broadcast_id}/accept`.

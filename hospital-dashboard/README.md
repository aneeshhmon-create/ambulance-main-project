# Hospital Dashboard (React + Vite)

```bash
cp .env.example .env     # set VITE_API_BASE_URL to the FastAPI backend
npm install
npm run dev              # http://localhost:5173
```

Backend notes: run `alembic upgrade head` once (adds `incidents.transcript`).
CORS is open only when `APP_ENV=development` in the backend `.env`.

Endpoints used: `GET /hospitals`, `GET/PATCH /hospitals/{id}`,
`GET /hospitals/{id}/broadcasts?status=pending|accepted`,
`POST /incidents/{incident_id}/broadcasts/{broadcast_id}/accept`.

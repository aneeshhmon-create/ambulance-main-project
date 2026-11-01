# Deploying to AWS (single EC2 host)

Stack on one EC2 instance, all in Docker Compose (`docker-compose.prod.yml`):

```
Internet ──443──> Caddy (auto HTTPS) ──> FastAPI app ──> Postgres/PostGIS
                    └── serves the hospital dashboard
```

Only Caddy (ports 80/443) is exposed. The app and database have no published ports.
Nothing here has been run against a real AWS account yet; the images, compose file and
Caddyfile were validated locally.

## 1. Create the AWS resources (console)

1. **EC2 instance**: Ubuntu 24.04 LTS, `t3.small` (2 GB RAM) or larger, 20–30 GB gp3 disk.
2. **Security group** inbound rules:
   - 22 (SSH): **your IP only**, not 0.0.0.0/0
   - 80 and 443: anywhere (needed for HTTPS certificate issuance)
   - Do **not** open 5432 or 8000.
3. **Elastic IP**: allocate one and attach it, so the address survives reboots.
4. Download the key pair (`.pem`) and `chmod 400` it.

## 2. Pick your hostnames

With no domain, use free [sslip.io](https://sslip.io) names built from the Elastic IP.
For IP `3.110.1.2`:

```
API_HOST=api.3-110-1-2.sslip.io
DASH_HOST=dash.3-110-1-2.sslip.io
```

Caddy gets real Let's Encrypt certificates for these. If you later buy a domain, point two
A records (`api.`, `dash.`) at the Elastic IP and change the two values.

## 3. Set up the server

```bash
ssh -i key.pem ubuntu@<elastic-ip>

# Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker ubuntu && exit        # log back in afterwards

# Code
git clone https://github.com/aneeshhmon-create/ambulance-main-project.git
cd ambulance-main-project
cp .env.production.example .env.production
```

Edit `.env.production`:
- `SECRET_KEY`, `JWT_SECRET`: generate each with
  `python3 -c "import secrets; print(secrets.token_hex(32))"`
- `POSTGRES_PASSWORD`, and put the same password inside `DATABASE_URL`
- `GEMINI_API_KEY`, `GOOGLE_CLIENT_ID` (the **web** client ID)
- `API_HOST`, `DASH_HOST` from step 2
- `CORS_ORIGINS=https://<DASH_HOST>`
- leave `APP_ENV=production` and `ALLOW_DEV_LOGIN=false`

The app refuses to start in production if the secrets are still the defaults or dev login
is on.

## 4. Start it

```bash
docker compose -f docker-compose.prod.yml --env-file .env.production up -d --build
docker compose -f docker-compose.prod.yml logs -f app     # Ctrl+C to leave
curl https://<API_HOST>/health
```

Migrations run automatically on each start. Open `https://<DASH_HOST>` for the dashboard.
The first request can take a few seconds while Caddy obtains the certificate.

Optional demo data: `docker compose -f docker-compose.prod.yml exec app python seed_hospitals.py`
(the seed scripts are baked into the image).

## 5. Google sign-in

- **Dashboard**: in Google Cloud Console, add `https://<DASH_HOST>` to **Authorized
  JavaScript origins** on the *web* client. Caveat: Google can be strict about shared
  public domains such as sslip.io; if it rejects the origin, a real domain is needed.
- **Android apps**: sign-in is tied to package name + SHA-1, not the server. Debug builds
  already work. A **release** build is signed with a different key, so create a release
  keystore and add *its* SHA-1 to both Android OAuth clients (user and driver).
  Google Play App Signing uses yet another SHA-1 if you publish to the Play Store.

## 6. Build the phone apps against production

```bash
cd flutter_app
flutter build apk --release --flavor user   -t lib/user_app/main.dart   --dart-define=API_BASE_URL=https://<API_HOST>
flutter build apk --release --flavor driver -t lib/driver_app/main.dart --dart-define=API_BASE_URL=https://<API_HOST>
```

The release build is currently signed with the debug key (see
`android/app/build.gradle.kts`); replace that before distributing.

## 7. Updating

```bash
cd ambulance-main-project && git pull
docker compose -f docker-compose.prod.yml --env-file .env.production up -d --build
```

## 8. Backups (do this before real use)

The database lives in a Docker volume on the instance's disk. If the instance is lost, so
is the data. Minimum:

```bash
# nightly dump, kept 14 days (add to crontab -e)
0 2 * * * cd ~/ambulance-main-project && docker compose -f docker-compose.prod.yml exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' | gzip > ~/backups/db-$(date +\%F).sql.gz && find ~/backups -mtime +14 -delete
```

Also enable EBS snapshots (AWS Data Lifecycle Manager) and copy dumps off the box (an S3
bucket). Create `~/backups` first.

## Known limits of this setup

- Single server: a reboot or crash means a short outage, and there is no failover.
- Database and app share one machine. If you outgrow it, move the database to RDS
  PostgreSQL (PostGIS is supported) and drop the `db` service.
- The `.env.production` file holds all secrets on the server's disk. Restrict it with
  `chmod 600`, and consider AWS Secrets Manager later.
- Voice STT/extraction depend on the Gemini API (about 5–10 s per call) and its quota.

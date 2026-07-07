# sett backend

Invite-only FastAPI backend for the sett v2 iOS app: cursor sync, Sign in
with Apple, Oura sleep import, AI digests (Claude), friends, and gyms.
Design doc: `design-backend.md`.

## Layout

- `app/` — FastAPI app (`app.main:app`), routers, services, worker, CLI
- `alembic/` — migrations (initial revision creates schema + exercise seed)
- `tests/` — pytest suite (SQLite + aiosqlite, no network)

## Local run

```sh
cd backend
uv venv --python 3.12
uv pip install -e ".[dev]"
uv run uvicorn app.main:app --reload
```

With no `DATABASE_URL` set, the app uses `sqlite+aiosqlite:///./sett_dev.db`
and — because `AUTO_CREATE_SCHEMA` defaults on — creates tables, the sync
counter, and the 67-exercise seed catalog at startup via
`Base.metadata.create_all`. Production disables that and uses Alembic; the
initial migration builds the identical schema from the same metadata, so the
two paths cannot drift.

## Tests

```sh
uv run pytest -q
```

The suite runs fully offline: SQLite temp-file databases, a fake Apple
verifier, an httpx `MockTransport` for Oura, and a canned digest model.

## Migrations

```sh
uv run alembic upgrade head                       # uses DATABASE_URL
uv run alembic revision --autogenerate -m "..."   # future changes
```

`sync_seq` is allocated from the single-row `sync_counter` table in the
service layer (`app/seq.py`) instead of a Postgres trigger, so SQLite and
Postgres share one code path.

## Admin CLI

```sh
docker compose exec sett-api python -m app.cli create-invite --note "for Marcos"
docker compose exec sett-api python -m app.cli run-digest --user marcos@example.com
docker compose exec sett-api python -m app.cli pull-oura
```

## Deploy (Nett VPS pattern)

One-time on the VPS:

1. `mkdir -p /opt/sett && cd /opt/sett`
2. Copy `docker-compose.prod.yml` and `.env` (from `.env.example`, `chmod 600`).
3. `docker network create edge` if Nett hasn't already; add an nginx server
   block for `sett.<domain>` proxying to `sett-api:8000` over `edge`, and
   extend the certbot cert with `-d sett.<domain>`.
4. `docker compose -f docker-compose.prod.yml pull && docker compose -f docker-compose.prod.yml run --rm sett-api alembic upgrade head && docker compose -f docker-compose.prod.yml up -d`

Every push to `main` then runs `.github/workflows/build.yml`: pytest →
build/push `ghcr.io/borjainglefernandez/sett-api` (`:latest` + `:<sha>`) →
SSH deploy (pull, migrate, `up -d`). CI secrets: `VPS_HOST`, `VPS_USER`,
`VPS_SSH_KEY`.

## Backups & monitoring

- Worker (`python -m app.worker`) schedules: Oura pulls 09:30 & 15:30 UTC,
  weekly digest Monday 06:00 Europe/Madrid, nightly `pg_dump | gzip` → S3 at
  03:15 UTC (only when `BACKUP_S3_BUCKET` is set; bucket lifecycle expires
  objects >30 days).
- Restore drill: `aws s3 cp s3://<bucket>/sett/pg/sett-YYYY-MM-DD.sql.gz - | gunzip | docker compose exec -T sett-db psql -U sett sett`
- UptimeRobot on `GET /v1/health`; optional healthchecks.io dead-man pings
  via `HC_PING_OURA` / `HC_PING_DIGEST` / `HC_PING_BACKUP`.

## Exercise catalog

`app/seed/ExerciseSeed.json` is a byte-identical copy of
`SettCore/Sources/SettCore/Seed/ExerciseSeed.json`. The frozen UUIDs are how
client and server agree on exercise identity — change both together or not
at all.

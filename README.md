# GeoTrade-X (DBMS project)

GeoTrade-X is a small full-stack demo that pairs a **MySQL** database (geopolitical tension, news, assets, watchlists, trades) with a **Node.js** API and a **dark-themed** single-page web UI.

## What’s in the repo

| Path | Purpose |
|------|--------|
| `backend/db_schema.sql` | Full **GeoTradeX** database: tables, views, procedures, triggers, seed data |
| `backend/server.js` | **Express** API + static file server for the frontend |
| `frontend/index.html` | UI: dashboard, news, market, watchlist, trades, table browser, login |
| `.env.example` | Template for local DB and server port |

## Prerequisites

- **Node.js** (LTS recommended)
- **MySQL** 8.x (roles, procedures, and triggers match MySQL 8 syntax)

## Quick start

1. **Clone and install**

   ```bash
   git clone <your-repo-url>
   cd dbms
   npm install
   ```

2. **Environment**

   ```bash
   cp .env.example .env
   ```

   Edit `.env` and set at least `DB_USER`, `DB_PASSWORD`, and `DB_NAME` (default database name is `GeoTradeX`). Optional: `PORT` (default **5500**), `ALERT_PCT` (default **5** — percent move vs trade entry that creates a price alert).

3. **Create the database** (this drops `GeoTradeX` if it already exists)

   ```bash
   mysql -u root -p -e "DROP DATABASE IF EXISTS GeoTradeX;"
   mysql -u root -p < backend/db_schema.sql
   ```

4. **Run the app**

   ```bash
   npm start
   ```

   Open **http://localhost:5500** (or your `PORT`).

## Features (high level)

- **Dashboard** — GTI-style region cards, news terminal snippet, market and watchlist samples  
- **News / Market / Watchlist** — Reads from GeoTradeX tables; watchlist supports adding an asset by name  
- **Trades** — Submit trades tied to `Users` and `Assets` (`asset_id` in DB; UI can send asset name, resolved server-side)  
- **Trade price alerts** — After each trade save, `Check_Trade_Price_Alert` compares entry price to latest `Asset_Prices`; rows land in `Trade_Alerts` and show on the Trades screen  
- **Assistant (chatbot)** — Predefined questions with answers built from live SQL (`Market_Impact`, GTI, news, watchlists, trades)  
- **Tables** — Browse non-empty tables, `Region_Risk` view, role/grant display (MySQL demo user)  
- **Auth** — `App_Users` with `role_id` → `Roles`; login gates tabs by role (viewer / analyst / admin)

On first start, `server.js` ensures helper objects exist (e.g. `User_Trades`, `App_Users`, `Region_Risk` view) if the schema was loaded partially.

## API (for reference)

All routes are relative to the server origin (same host as the UI).

| Method | Path | Role |
|--------|------|------|
| GET | `/api/dashboard` | Aggregated dashboard data |
| GET | `/api/news`, `/api/market`, `/api/watchlist` | Screen data |
| POST | `/api/watchlist-items` | Add watchlist row |
| GET | `/api/tables`, `/api/tables/:name` | Table browser |
| GET | `/api/trades` | List trades |
| POST | `/api/trades` | Insert trade (transaction), then price alert check |
| GET | `/api/trade-alerts` | List trade price alerts |
| GET | `/api/region-risk`, `/api/role-grants` | View and grants demo |
| POST | `/api/login`, `/api/register` | App users |
| GET | `/api/chat/prompts` | Suggested assistant questions |
| POST | `/api/chat` | Run a predefined DB-backed answer (`query_id` in body) |

## Schema notes

- Canonical DDL and seed data live in **`backend/db_schema.sql`**.  
- Design follows **3NF** where practical (e.g. trades reference `Assets` by `asset_id`; app roles reference `Roles` by `role_id`).

## Demo: trade price alerts

1. Login as **analyst** (`analyst1` / `pass123`).
2. Open **Trades**. Note latest market prices in **Market** or **Tables → Asset_Prices** (e.g. Gold is often ~50k+ in seed data).
3. Save a trade: asset **Gold**, **trade price** far from latest (e.g. `100` if market is ~60000) so change exceeds `ALERT_PCT`.
4. **Price alerts** panel should show **PRICE UP** or **PRICE DOWN** with percent and message.
5. As **admin**, open **Tables** and load **Trade_Alerts** to show the stored row.

## Troubleshooting

- **`ECONNREFUSED` / DB errors** — Check MySQL is running and `.env` matches your user/password/host.  
- **Stale tables after editing SQL** — Reload the schema (drop + import) and restart `npm start`.  
- **No trade alerts after save** — Reload DB so `Check_Trade_Price_Alert` exists; ensure entry price differs from latest `Asset_Prices` by at least `ALERT_PCT`%.  
- **Port in use** — Change `PORT` in `.env` or stop the other process using that port.

## License

Private coursework / demo — not licensed for redistribution unless you add one.

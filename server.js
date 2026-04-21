const path = require("path");
const express = require("express");
const cors = require("cors");
const mysql = require("mysql2/promise");
require("dotenv").config();

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname)));

const pool = mysql.createPool({
  host: process.env.DB_HOST || "localhost",
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || "root",
  password: process.env.DB_PASSWORD || "",
  database: process.env.DB_NAME || "geotradex",
  waitForConnections: true,
  connectionLimit: 10,
});

app.get("/api/dashboard", async (_req, res) => {
  try {
    const [regions] = await pool.query(
      `SELECT region_name, index_value, risk_level
       FROM v_latest_region_gti
       ORDER BY index_value DESC
       LIMIT 3`
    );

    const [terminal] = await pool.query(
      `SELECT a.published_at AS timestamp,
              a.title,
              r.region_name,
              c.category_name,
              s.score_value AS sentiment,
              sv.severity_name
       FROM article_analysis aa
       JOIN articles a ON a.article_id = aa.article_id
       JOIN regions r ON r.region_id = a.region_id
       JOIN sentiment_labels s ON s.sentiment_id = aa.sentiment_id
       JOIN severity_levels sv ON sv.severity_id = aa.severity_id
       JOIN categories c ON c.category_id = aa.category_id
       ORDER BY a.published_at DESC
       LIMIT 5`
    );

    const [market] = await pool.query(
      `SELECT asset_name, asset_symbol, price_value, direction
       FROM v_latest_market_impact
       ORDER BY price_timestamp DESC
       LIMIT 5`
    );

    const [watchlist] = await pool.query(
      `SELECT a.asset_symbol, ap.price_value
       FROM watchlist_items wi
       JOIN watchlists w ON w.watchlist_id = wi.watchlist_id
       JOIN assets a ON a.asset_id = wi.asset_id
       JOIN (
         SELECT asset_id, MAX(price_timestamp) AS max_ts
         FROM asset_prices
         GROUP BY asset_id
       ) latest ON latest.asset_id = a.asset_id
       JOIN asset_prices ap ON ap.asset_id = latest.asset_id AND ap.price_timestamp = latest.max_ts
       ORDER BY w.watchlist_id, wi.watchlist_item_id
       LIMIT 5`
    );

    res.json({ regions, terminal, market, watchlist });
  } catch (error) {
    res.status(500).json({
      error: "Database query failed",
      details: error.message,
    });
  }
});

app.get("/api/news", async (_req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT article_id, published_at, title, region_name, category_name, sentiment, severity_name
       FROM v_news_feed
       ORDER BY published_at DESC
       LIMIT 50`
    );
    res.json({ rows });
  } catch (error) {
    res.status(500).json({ error: "News query failed", details: error.message });
  }
});

app.get("/api/market", async (_req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT asset_id, asset_symbol, asset_name, price_value, price_timestamp, direction, predicted_volatility
       FROM v_market_screen
       ORDER BY price_timestamp DESC
       LIMIT 100`
    );
    res.json({ rows });
  } catch (error) {
    res.status(500).json({ error: "Market query failed", details: error.message });
  }
});

app.get("/api/watchlist", async (_req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT watchlist_id, watchlist_name, username, asset_symbol, asset_name, price_value, price_timestamp
       FROM v_watchlist_screen
       ORDER BY watchlist_name, asset_symbol
       LIMIT 200`
    );
    res.json({ rows });
  } catch (error) {
    res.status(500).json({ error: "Watchlist query failed", details: error.message });
  }
});

app.get(/.*/, (_req, res) => {
  res.sendFile(path.join(__dirname, "index.html"));
});

const port = Number(process.env.PORT || 5500);
app.listen(port, () => {
  console.log(`Server running on http://localhost:${port}`);
});

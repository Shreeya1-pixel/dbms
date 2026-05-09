const path = require("path");
const express = require("express");
const cors = require("cors");
const mysql = require("mysql2/promise");
require("dotenv").config({ path: path.join(__dirname, "..", ".env") });

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, "..", "frontend")));

const pool = mysql.createPool({
  host: process.env.DB_HOST || "localhost",
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || "root",
  password: process.env.DB_PASSWORD || "",
  database: process.env.DB_NAME || "GeoTradeX",
  waitForConnections: true,
  connectionLimit: 10,
});

async function ensureUserTradesTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS User_Trades (
      trade_id INT PRIMARY KEY AUTO_INCREMENT,
      user_id INT NOT NULL,
      asset_id INT NOT NULL,
      trade_date DATE NOT NULL,
      trade_type VARCHAR(30) NOT NULL,
      quantity FLOAT NOT NULL,
      trade_price FLOAT NOT NULL,
      notes VARCHAR(255),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES Users(user_id),
      FOREIGN KEY (asset_id) REFERENCES Assets(asset_id)
    )
  `);
}

ensureUserTradesTable().catch((error) => {
  console.error("Failed to ensure User_Trades table:", error.message);
});

async function ensureViewAndRole() {
  await pool.query(`
    CREATE OR REPLACE VIEW Region_Risk AS
    SELECT
      r.region_id,
      r.name AS region_name,
      g.record_date,
      g.index_value,
      CASE
        WHEN g.index_value > 25 THEN 'Critical'
        WHEN g.index_value > 15 THEN 'High'
        WHEN g.index_value > 5 THEN 'Medium'
        ELSE 'Low'
      END AS risk_level
    FROM Regions r
    JOIN GTI_Records g ON g.region_id = r.region_id
  `);
  await pool.query("CREATE ROLE IF NOT EXISTS analyst_role");
  await pool.query("GRANT SELECT ON GeoTradeX.* TO analyst_role");
  await pool.query("CREATE USER IF NOT EXISTS 'analyst1'@'localhost' IDENTIFIED BY 'pass123'");
  await pool.query("GRANT analyst_role TO 'analyst1'@'localhost'");
}

ensureViewAndRole().catch((error) => {
  console.error("Failed to ensure view/role objects:", error.message);
});

async function ensureAppUsers() {
  await pool.query(`
    INSERT IGNORE INTO Roles (role_id, role_name) VALUES
    (1, 'admin'), (2, 'analyst'), (3, 'viewer')
  `);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS App_Users (
      app_user_id INT PRIMARY KEY AUTO_INCREMENT,
      username VARCHAR(60) NOT NULL UNIQUE,
      password VARCHAR(100) NOT NULL,
      role_id INT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (role_id) REFERENCES Roles(role_id)
    )
  `);
  await pool.query(`
    INSERT IGNORE INTO App_Users (username, password, role_id) VALUES
    ('admin', 'admin123', 1),
    ('analyst1', 'pass123', 2),
    ('viewer1', 'pass123', 3)
  `);
}

ensureAppUsers().catch((error) => {
  console.error("Failed to ensure App_Users table:", error.message);
});

const APP_ROLE_IDS = { admin: 1, analyst: 2, viewer: 3 };

app.post("/api/register", async (req, res) => {
  const conn = await pool.getConnection();
  try {
    const username = String(req.body?.username || "").trim();
    const password = String(req.body?.password || "").trim();
    const roleKey = String(req.body?.role || "viewer").trim().toLowerCase();

    if (!username || !password) {
      conn.release();
      return res.status(400).json({ error: "username and password are required" });
    }
    const roleId = APP_ROLE_IDS[roleKey];
    if (!roleId) {
      conn.release();
      return res.status(400).json({ error: "role must be admin, analyst, or viewer" });
    }

    await conn.beginTransaction();
    await conn.query(
      "INSERT INTO App_Users (username, password, role_id) VALUES (?, ?, ?)",
      [username, password, roleId]
    );
    await conn.commit();
    conn.release();
    return res.status(201).json({ ok: true, message: "User registered" });
  } catch (error) {
    try { await conn.rollback(); } catch {}
    conn.release();
    if (error.code === "ER_DUP_ENTRY") {
      return res.status(409).json({ error: "Username already exists" });
    }
    return res.status(500).json({ error: "Registration failed", details: error.message });
  }
});

app.post("/api/login", async (req, res) => {
  const conn = await pool.getConnection();
  try {
    const username = String(req.body?.username || "").trim();
    const password = String(req.body?.password || "").trim();

    if (!username || !password) {
      conn.release();
      return res.status(400).json({ error: "username and password are required" });
    }

    await conn.beginTransaction();
    const [rows] = await conn.query(
      `SELECT u.app_user_id, u.username, LOWER(r.role_name) AS role
       FROM App_Users u
       JOIN Roles r ON r.role_id = u.role_id
       WHERE u.username = ? AND u.password = ?
       LIMIT 1`,
      [username, password]
    );
    await conn.commit();
    conn.release();

    if (!rows.length) {
      return res.status(401).json({ error: "Invalid username or password" });
    }
    return res.json({ ok: true, user: rows[0] });
  } catch (error) {
    try { await conn.rollback(); } catch {}
    conn.release();
    return res.status(500).json({ error: "Login failed", details: error.message });
  }
});

app.get("/api/dashboard", async (_req, res) => {
  try {
    const [regions] = await pool.query(
      `SELECT r.name AS region_name,
              g.index_value,
              CASE
                WHEN g.index_value > 25 THEN 'Critical'
                WHEN g.index_value > 15 THEN 'High'
                WHEN g.index_value > 5 THEN 'Medium'
                ELSE 'Low'
              END AS risk_level
       FROM GTI_Records g
       JOIN Regions r ON r.region_id = g.region_id
       ORDER BY index_value DESC
       LIMIT 3`
    );

    const [terminal] = await pool.query(
      `SELECT a.publish_date AS timestamp,
              a.title,
              r.name AS region_name,
              c.category_name,
              ss.score_value AS sentiment,
              sv.level_name AS severity_name
       FROM Article_Analysis aa
       JOIN News_Articles a ON a.article_id = aa.article_id
       JOIN News_Sources ns ON a.source_id = ns.source_id
       JOIN Countries co ON ns.country_id = co.country_id
       JOIN Regions r ON r.region_id = co.region_id
       JOIN Sentiment_Scores ss ON ss.sentiment_id = aa.sentiment_id
       JOIN Severity_Levels sv ON sv.severity_id = aa.severity_id
       JOIN Categories c ON c.category_id = aa.category_id
       ORDER BY a.publish_date DESC
       LIMIT 5`
    );

    const [market] = await pool.query(
      `SELECT a.name AS asset_name,
              a.name AS asset_symbol,
              ap.price AS price_value,
              mi.direction
       FROM Market_Impact mi
       JOIN Assets a ON a.asset_id = mi.asset_id
       LEFT JOIN (
         SELECT p1.asset_id, p1.price
         FROM Asset_Prices p1
         JOIN (
           SELECT asset_id, MAX(price_date) AS max_date
           FROM Asset_Prices
           GROUP BY asset_id
         ) latest ON latest.asset_id = p1.asset_id AND latest.max_date = p1.price_date
       ) ap ON ap.asset_id = a.asset_id
       ORDER BY mi.impact_date DESC, mi.impact_id DESC
       LIMIT 5`
    );

    const [watchlist] = await pool.query(
      `SELECT a.name AS asset_symbol, ap.price AS price_value, mi.direction
       FROM Watchlist_Items wi
       JOIN Watchlists w ON w.watchlist_id = wi.watchlist_id
       JOIN Assets a ON a.asset_id = wi.asset_id
       JOIN (
         SELECT asset_id, MAX(price_date) AS max_ts
         FROM Asset_Prices
         GROUP BY asset_id
       ) latest ON latest.asset_id = a.asset_id
       JOIN Asset_Prices ap ON ap.asset_id = latest.asset_id AND ap.price_date = latest.max_ts
       LEFT JOIN Market_Impact mi ON mi.impact_id = (
         SELECT mi2.impact_id
         FROM Market_Impact mi2
         WHERE mi2.asset_id = a.asset_id
         ORDER BY mi2.impact_date DESC, mi2.impact_id DESC
         LIMIT 1
       )
       ORDER BY w.watchlist_id, wi.id
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
      `SELECT a.article_id,
              a.publish_date AS published_at,
              a.title,
              r.name AS region_name,
              c.category_name,
              ss.score_value AS sentiment,
              sv.level_name AS severity_name
       FROM News_Articles a
       JOIN Article_Analysis aa ON aa.article_id = a.article_id
       JOIN News_Sources ns ON a.source_id = ns.source_id
       JOIN Countries co ON ns.country_id = co.country_id
       JOIN Regions r ON r.region_id = co.region_id
       JOIN Sentiment_Scores ss ON ss.sentiment_id = aa.sentiment_id
       JOIN Categories c ON c.category_id = aa.category_id
       JOIN Severity_Levels sv ON sv.severity_id = aa.severity_id
       ORDER BY a.publish_date DESC
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
      `SELECT a.asset_id,
              a.name AS asset_symbol,
              a.name AS asset_name,
              ap.price AS price_value,
              ap.price_date AS price_timestamp,
              mi.direction,
              mi.predicted_volatility
       FROM Assets a
       LEFT JOIN (
         SELECT p1.asset_id, p1.price_date, p1.price
         FROM Asset_Prices p1
         JOIN (
           SELECT asset_id, MAX(price_date) AS max_date
           FROM Asset_Prices
           GROUP BY asset_id
         ) latest ON latest.asset_id = p1.asset_id AND latest.max_date = p1.price_date
       ) ap ON ap.asset_id = a.asset_id
       LEFT JOIN Market_Impact mi ON mi.impact_id = (
         SELECT mi2.impact_id
         FROM Market_Impact mi2
         WHERE mi2.asset_id = a.asset_id
         ORDER BY mi2.impact_date DESC, mi2.impact_id DESC
         LIMIT 1
       )
       ORDER BY ap.price_date DESC, a.asset_id
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
      `SELECT w.watchlist_id,
              CONCAT('Watchlist ', w.watchlist_id) AS watchlist_name,
              u.user_name AS username,
              a.name AS asset_symbol,
              a.name AS asset_name,
              ap.price AS price_value,
              ap.price_date AS price_timestamp,
              mi.direction
       FROM Watchlist_Items wi
       JOIN Watchlists w ON w.watchlist_id = wi.watchlist_id
       JOIN Users u ON u.user_id = w.user_id
       JOIN Assets a ON a.asset_id = wi.asset_id
       LEFT JOIN (
         SELECT p1.asset_id, p1.price_date, p1.price
         FROM Asset_Prices p1
         JOIN (
           SELECT asset_id, MAX(price_date) AS max_date
           FROM Asset_Prices
           GROUP BY asset_id
         ) latest ON latest.asset_id = p1.asset_id AND latest.max_date = p1.price_date
       ) ap ON ap.asset_id = a.asset_id
       LEFT JOIN Market_Impact mi ON mi.impact_id = (
         SELECT mi2.impact_id
         FROM Market_Impact mi2
         WHERE mi2.asset_id = a.asset_id
         ORDER BY mi2.impact_date DESC, mi2.impact_id DESC
         LIMIT 1
       )
       ORDER BY w.watchlist_id, a.name
       LIMIT 200`
    );
    res.json({ rows });
  } catch (error) {
    res.status(500).json({ error: "Watchlist query failed", details: error.message });
  }
});

app.post("/api/watchlist-items", async (req, res) => {
  try {
    const watchlistId = Number(req.body?.watchlist_id);
    const assetName = String(req.body?.asset_name || "").trim();

    if (!watchlistId || !assetName) {
      return res.status(400).json({
        error: "watchlist_id and asset_name are required",
      });
    }

    const [assetRows] = await pool.query(
      "SELECT asset_id FROM Assets WHERE name = ? LIMIT 1",
      [assetName]
    );

    if (!assetRows.length) {
      return res.status(404).json({ error: "Asset symbol not found" });
    }

    await pool.query(
      "INSERT INTO Watchlist_Items (watchlist_id, asset_id) VALUES (?, ?)",
      [watchlistId, assetRows[0].asset_id]
    );

    return res.status(201).json({ ok: true });
  } catch (error) {
    if (error && error.code === "ER_DUP_ENTRY") {
      return res.status(409).json({ error: "Asset already exists in this watchlist" });
    }
    return res.status(500).json({ error: "Failed to add watchlist item", details: error.message });
  }
});

app.get("/api/tables", (_req, res) => {
  const tables = [
    "Regions", "Countries", "Cities", "Source_Types", "News_Sources", "News_Articles",
    "Sentiment_Scores", "Severity_Levels", "Categories", "Event_Types", "Article_Analysis",
    "GTI_Records", "GTI_History", "Risk_Thresholds", "Asset_Types", "Assets", "Asset_Prices",
    "Market_Impact", "Roles", "Users", "Watchlists", "Watchlist_Items", "Risk_Scores",
    "Trend_Analysis", "GTI_Alerts", "User_Trades",
  ];

  (async () => {
    try {
      const available = [];
      for (const table of tables) {
        const [countRows] = await pool.query(`SELECT COUNT(*) AS c FROM ${table}`);
        if (Number(countRows[0].c) > 0) {
          available.push(table);
        }
      }
      res.json({ tables: available });
    } catch (error) {
      res.status(500).json({ error: "Tables query failed", details: error.message });
    }
  })();
});

app.get("/api/tables/:name", async (req, res) => {
  try {
    const name = req.params.name;
    const allowed = new Set([
      "Regions", "Countries", "Cities", "Source_Types", "News_Sources", "News_Articles",
      "Sentiment_Scores", "Severity_Levels", "Categories", "Event_Types", "Article_Analysis",
      "GTI_Records", "GTI_History", "Risk_Thresholds", "Asset_Types", "Assets", "Asset_Prices",
      "Market_Impact", "Roles", "Users", "Watchlists", "Watchlist_Items", "Risk_Scores",
      "Trend_Analysis", "GTI_Alerts", "User_Trades",
    ]);
    if (!allowed.has(name)) {
      return res.status(400).json({ error: "Invalid table name" });
    }
    const [rows] = await pool.query(`SELECT * FROM ${name} LIMIT 500`);
    return res.json({ table: name, rows });
  } catch (error) {
    return res.status(500).json({ error: "Table query failed", details: error.message });
  }
});

app.get("/api/trades", async (_req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT t.trade_id, t.trade_date, t.trade_type, ast.name AS asset_name, t.quantity, t.trade_price, t.notes, t.created_at,
              u.user_id, u.user_name
       FROM User_Trades t
       JOIN Users u ON u.user_id = t.user_id
       JOIN Assets ast ON ast.asset_id = t.asset_id
       ORDER BY t.trade_id DESC
       LIMIT 200`
    );
    return res.json({ rows });
  } catch (error) {
    return res.status(500).json({ error: "Trades query failed", details: error.message });
  }
});

app.get("/api/region-risk", async (_req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT region_id, region_name, record_date, index_value, risk_level
       FROM Region_Risk
       ORDER BY index_value DESC
       LIMIT 50`
    );
    return res.json({ rows });
  } catch (error) {
    return res.status(500).json({ error: "Region_Risk view query failed", details: error.message });
  }
});

app.get("/api/role-grants", async (_req, res) => {
  try {
    const [roleGrants] = await pool.query("SHOW GRANTS FOR 'analyst_role'@'%'");
    const [userGrants] = await pool.query("SHOW GRANTS FOR 'analyst1'@'localhost'");
    return res.json({
      role: "analyst_role",
      roleGrants: roleGrants.map((row) => Object.values(row)[0]),
      user: "analyst1@localhost",
      userGrants: userGrants.map((row) => Object.values(row)[0]),
    });
  } catch (error) {
    return res.status(500).json({ error: "Role/grant query failed", details: error.message });
  }
});

app.post("/api/trades", async (req, res) => {
  const conn = await pool.getConnection();
  try {
    const userIdInput = req.body?.user_id == null ? null : Number(req.body.user_id);
    const userNameInput = String(req.body?.user_name || "").trim();
    const tradeDate = String(req.body?.trade_date || "").trim();
    const tradeType = String(req.body?.trade_type || "").trim().toUpperCase();
    const assetIdInput = req.body?.asset_id == null || req.body?.asset_id === "" ? null : Number(req.body.asset_id);
    const assetName = String(req.body?.asset_name || "").trim();
    const quantity = Number(req.body?.quantity);
    const tradePrice = Number(req.body?.trade_price);
    const notes = String(req.body?.notes || "").trim();

    if (!tradeDate || !tradeType || !Number.isFinite(quantity) || !Number.isFinite(tradePrice)) {
      conn.release();
      return res.status(400).json({
        error: "trade_date, trade_type, quantity, and trade_price are required",
      });
    }

    const hasAssetId = Number.isFinite(assetIdInput) && assetIdInput > 0;
    if (!hasAssetId && !assetName) {
      conn.release();
      return res.status(400).json({
        error: "asset_id or asset_name is required",
      });
    }

    await conn.beginTransaction();

    let assetId;
    if (hasAssetId) {
      const [byId] = await conn.query("SELECT asset_id FROM Assets WHERE asset_id = ? LIMIT 1", [assetIdInput]);
      if (!byId.length) {
        await conn.rollback();
        conn.release();
        return res.status(404).json({ error: "asset_id not found in Assets table" });
      }
      assetId = byId[0].asset_id;
    } else {
      const [assetRows] = await conn.query(
        "SELECT asset_id FROM Assets WHERE name = ? LIMIT 1",
        [assetName]
      );
      if (!assetRows.length) {
        await conn.rollback();
        conn.release();
        return res.status(404).json({ error: "asset_name not found in Assets table" });
      }
      assetId = assetRows[0].asset_id;
    }

    let userId = userIdInput;

    if (userId) {
      const [existing] = await conn.query("SELECT user_id FROM Users WHERE user_id = ? LIMIT 1", [userId]);
      if (!existing.length) {
        throw new Error("User not found for provided user_id");
      }
    } else if (userNameInput) {
      const [existingByName] = await conn.query("SELECT user_id FROM Users WHERE user_name = ? LIMIT 1", [userNameInput]);
      if (existingByName.length) {
        userId = existingByName[0].user_id;
      } else {
        const [nextIdRows] = await conn.query("SELECT IFNULL(MAX(user_id), 0) + 1 AS next_id FROM Users");
        userId = nextIdRows[0].next_id;
        await conn.query("INSERT INTO Users (user_id, user_name, role_id) VALUES (?, ?, 2)", [userId, userNameInput]);
      }
    } else {
      throw new Error("Provide either user_id or user_name");
    }

    const [result] = await conn.query(
      `INSERT INTO User_Trades (user_id, asset_id, trade_date, trade_type, quantity, trade_price, notes)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [userId, assetId, tradeDate, tradeType, quantity, tradePrice, notes || null]
    );

    await conn.commit();
    conn.release();
    return res.status(201).json({ ok: true, trade_id: result.insertId, user_id: userId });
  } catch (error) {
    try {
      await conn.rollback();
    } catch {}
    conn.release();
    return res.status(500).json({ error: "Failed to save trade", details: error.message });
  }
});

app.get(/.*/, (_req, res) => {
  res.sendFile(path.join(__dirname, "..", "frontend", "index.html"));
});

const port = Number(process.env.PORT || 5500);
app.listen(port, () => {
  console.log(`Server running on http://localhost:${port}`);
});

CREATE DATABASE IF NOT EXISTS geotradex;
USE geotradex;

CREATE TABLE roles (
  role_id INT AUTO_INCREMENT PRIMARY KEY,
  role_name VARCHAR(50) NOT NULL UNIQUE
);
CREATE TABLE users (
  user_id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) NOT NULL UNIQUE,
  role_id INT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (role_id) REFERENCES roles(role_id)
);
CREATE TABLE regions (
  region_id INT AUTO_INCREMENT PRIMARY KEY,
  region_name VARCHAR(80) NOT NULL UNIQUE
);
CREATE TABLE risk_levels (
  risk_level_id INT AUTO_INCREMENT PRIMARY KEY,
  level_name VARCHAR(20) NOT NULL UNIQUE,
  min_value DECIMAL(6,2) NOT NULL,
  max_value DECIMAL(6,2) NOT NULL,
  CHECK (min_value <= max_value)
);
CREATE TABLE source_types (
  source_type_id INT AUTO_INCREMENT PRIMARY KEY,
  source_type_name VARCHAR(50) NOT NULL UNIQUE
);
CREATE TABLE news_sources (
  source_id INT AUTO_INCREMENT PRIMARY KEY,
  source_name VARCHAR(100) NOT NULL UNIQUE,
  source_type_id INT NOT NULL,
  FOREIGN KEY (source_type_id) REFERENCES source_types(source_type_id)
);
CREATE TABLE articles (
  article_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  source_id INT NOT NULL,
  region_id INT NOT NULL,
  published_at DATETIME NOT NULL,
  FOREIGN KEY (source_id) REFERENCES news_sources(source_id),
  FOREIGN KEY (region_id) REFERENCES regions(region_id),
  INDEX idx_articles_region_published (region_id, published_at)
);
CREATE TABLE categories (
  category_id INT AUTO_INCREMENT PRIMARY KEY,
  category_name VARCHAR(50) NOT NULL UNIQUE
);
CREATE TABLE sentiment_labels (
  sentiment_id INT AUTO_INCREMENT PRIMARY KEY,
  sentiment_label VARCHAR(20) NOT NULL UNIQUE,
  score_value DECIMAL(4,2) NOT NULL CHECK (score_value BETWEEN -1.00 AND 1.00)
);
CREATE TABLE severity_levels (
  severity_id INT AUTO_INCREMENT PRIMARY KEY,
  severity_name VARCHAR(20) NOT NULL UNIQUE,
  severity_weight INT NOT NULL CHECK (severity_weight > 0)
);
CREATE TABLE article_analysis (
  analysis_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  article_id BIGINT NOT NULL UNIQUE,
  sentiment_id INT NOT NULL,
  severity_id INT NOT NULL,
  category_id INT NOT NULL,
  intensity DECIMAL(5,2) NOT NULL CHECK (intensity >= 0),
  analyzed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (article_id) REFERENCES articles(article_id) ON DELETE CASCADE,
  FOREIGN KEY (sentiment_id) REFERENCES sentiment_labels(sentiment_id),
  FOREIGN KEY (severity_id) REFERENCES severity_levels(severity_id),
  FOREIGN KEY (category_id) REFERENCES categories(category_id)
);
CREATE TABLE gti_records (
  gti_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  region_id INT NOT NULL,
  record_date DATE NOT NULL,
  index_value DECIMAL(6,2) NOT NULL,
  risk_level_id INT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (region_id) REFERENCES regions(region_id),
  FOREIGN KEY (risk_level_id) REFERENCES risk_levels(risk_level_id),
  UNIQUE KEY uq_region_record_date (region_id, record_date),
  INDEX idx_gti_region_date (region_id, record_date)
);
CREATE TABLE asset_types (
  asset_type_id INT AUTO_INCREMENT PRIMARY KEY,
  asset_type_name VARCHAR(50) NOT NULL UNIQUE
);
CREATE TABLE assets (
  asset_id INT AUTO_INCREMENT PRIMARY KEY,
  asset_symbol VARCHAR(20) NOT NULL UNIQUE,
  asset_name VARCHAR(100) NOT NULL,
  asset_type_id INT NOT NULL,
  FOREIGN KEY (asset_type_id) REFERENCES asset_types(asset_type_id)
);
CREATE TABLE asset_prices (
  price_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  asset_id INT NOT NULL,
  price_timestamp DATETIME NOT NULL,
  price_value DECIMAL(18,4) NOT NULL,
  FOREIGN KEY (asset_id) REFERENCES assets(asset_id),
  UNIQUE KEY uq_asset_price_timestamp (asset_id, price_timestamp),
  INDEX idx_prices_asset_time (asset_id, price_timestamp)
);
CREATE TABLE watchlists (
  watchlist_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  watchlist_name VARCHAR(80) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(user_id),
  UNIQUE KEY uq_user_watchlist_name (user_id, watchlist_name)
);
CREATE TABLE watchlist_items (
  watchlist_item_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  watchlist_id BIGINT NOT NULL,
  asset_id INT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (watchlist_id) REFERENCES watchlists(watchlist_id) ON DELETE CASCADE,
  FOREIGN KEY (asset_id) REFERENCES assets(asset_id),
  UNIQUE KEY uq_watchlist_asset (watchlist_id, asset_id)
);
CREATE TABLE market_impact (
  impact_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  asset_id INT NOT NULL,
  gti_id BIGINT NOT NULL,
  impact_date DATE NOT NULL,
  direction ENUM('Bullish', 'Bearish', 'Neutral') NOT NULL,
  predicted_volatility DECIMAL(8,4) NOT NULL CHECK (predicted_volatility >= 0),
  FOREIGN KEY (asset_id) REFERENCES assets(asset_id),
  FOREIGN KEY (gti_id) REFERENCES gti_records(gti_id),
  INDEX idx_impact_date (impact_date)
);
CREATE TABLE gti_alerts (
  alert_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  region_id INT NOT NULL,
  gti_id BIGINT NOT NULL,
  alert_message VARCHAR(140) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (region_id) REFERENCES regions(region_id),
  FOREIGN KEY (gti_id) REFERENCES gti_records(gti_id)
);

CREATE OR REPLACE VIEW v_latest_region_gti AS
SELECT r.region_id, r.region_name, gr.index_value, gr.record_date, rl.level_name AS risk_level
FROM regions r
JOIN gti_records gr ON gr.region_id = r.region_id
LEFT JOIN risk_levels rl ON rl.risk_level_id = gr.risk_level_id
JOIN (SELECT region_id, MAX(record_date) AS max_date FROM gti_records GROUP BY region_id) latest
  ON latest.region_id = gr.region_id AND latest.max_date = gr.record_date;

CREATE OR REPLACE VIEW v_news_feed AS
SELECT a.article_id, a.published_at, a.title, r.region_name, c.category_name, sl.score_value AS sentiment, sv.severity_name
FROM article_analysis aa
JOIN articles a ON a.article_id = aa.article_id
JOIN regions r ON r.region_id = a.region_id
JOIN categories c ON c.category_id = aa.category_id
JOIN sentiment_labels sl ON sl.sentiment_id = aa.sentiment_id
JOIN severity_levels sv ON sv.severity_id = aa.severity_id;

CREATE OR REPLACE VIEW v_market_screen AS
SELECT a.asset_id, a.asset_symbol, a.asset_name, ap.price_value, ap.price_timestamp, mi.direction, mi.predicted_volatility
FROM assets a
JOIN (SELECT asset_id, MAX(price_timestamp) AS max_ts FROM asset_prices GROUP BY asset_id) lp ON lp.asset_id = a.asset_id
JOIN asset_prices ap ON ap.asset_id = lp.asset_id AND ap.price_timestamp = lp.max_ts
LEFT JOIN market_impact mi ON mi.impact_id = (
  SELECT mi2.impact_id FROM market_impact mi2 WHERE mi2.asset_id = a.asset_id
  ORDER BY mi2.impact_date DESC, mi2.impact_id DESC LIMIT 1
);

CREATE OR REPLACE VIEW v_watchlist_screen AS
SELECT w.watchlist_id, w.watchlist_name, u.username, a.asset_symbol, a.asset_name, ap.price_value, ap.price_timestamp
FROM watchlist_items wi
JOIN watchlists w ON w.watchlist_id = wi.watchlist_id
JOIN users u ON u.user_id = w.user_id
JOIN assets a ON a.asset_id = wi.asset_id
JOIN (SELECT asset_id, MAX(price_timestamp) AS max_ts FROM asset_prices GROUP BY asset_id) lp ON lp.asset_id = a.asset_id
JOIN asset_prices ap ON ap.asset_id = lp.asset_id AND ap.price_timestamp = lp.max_ts;

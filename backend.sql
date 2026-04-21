CREATE DATABASE IF NOT EXISTS geotradex;
USE geotradex;

-- 3NF schema (no demo inserts)

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

-- Frontend query views
CREATE OR REPLACE VIEW v_latest_region_gti AS
SELECT r.region_id, r.region_name, gr.index_value, gr.record_date, rl.level_name AS risk_level
FROM regions r
JOIN gti_records gr ON gr.region_id = r.region_id
LEFT JOIN risk_levels rl ON rl.risk_level_id = gr.risk_level_id
JOIN (
  SELECT region_id, MAX(record_date) AS max_date
  FROM gti_records
  GROUP BY region_id
) latest ON latest.region_id = gr.region_id AND latest.max_date = gr.record_date;

CREATE OR REPLACE VIEW v_news_feed AS
SELECT a.article_id,
       a.published_at,
       a.title,
       r.region_name,
       c.category_name,
       sl.score_value AS sentiment,
       sv.severity_name
FROM article_analysis aa
JOIN articles a ON a.article_id = aa.article_id
JOIN regions r ON r.region_id = a.region_id
JOIN categories c ON c.category_id = aa.category_id
JOIN sentiment_labels sl ON sl.sentiment_id = aa.sentiment_id
JOIN severity_levels sv ON sv.severity_id = aa.severity_id;

CREATE OR REPLACE VIEW v_market_screen AS
SELECT a.asset_id, a.asset_symbol, a.asset_name, ap.price_value, ap.price_timestamp, mi.direction, mi.predicted_volatility
FROM assets a
JOIN (
  SELECT asset_id, MAX(price_timestamp) AS max_ts
  FROM asset_prices
  GROUP BY asset_id
) lp ON lp.asset_id = a.asset_id
JOIN asset_prices ap ON ap.asset_id = lp.asset_id AND ap.price_timestamp = lp.max_ts
LEFT JOIN market_impact mi ON mi.impact_id = (
  SELECT mi2.impact_id
  FROM market_impact mi2
  WHERE mi2.asset_id = a.asset_id
  ORDER BY mi2.impact_date DESC, mi2.impact_id DESC
  LIMIT 1
);

CREATE OR REPLACE VIEW v_watchlist_screen AS
SELECT w.watchlist_id, w.watchlist_name, u.username, a.asset_symbol, a.asset_name, ap.price_value, ap.price_timestamp
FROM watchlist_items wi
JOIN watchlists w ON w.watchlist_id = wi.watchlist_id
JOIN users u ON u.user_id = w.user_id
JOIN assets a ON a.asset_id = wi.asset_id
JOIN (
  SELECT asset_id, MAX(price_timestamp) AS max_ts
  FROM asset_prices
  GROUP BY asset_id
) lp ON lp.asset_id = a.asset_id
JOIN asset_prices ap ON ap.asset_id = lp.asset_id AND ap.price_timestamp = lp.max_ts;
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

CREATE TABLE severity_levels (
  severity_id INT AUTO_INCREMENT PRIMARY KEY,
  severity_name VARCHAR(20) NOT NULL UNIQUE,
  severity_weight INT NOT NULL CHECK (severity_weight > 0)
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

-- Frontend query helpers (no demo inserts)
CREATE OR REPLACE VIEW v_latest_region_gti AS
SELECT r.region_id, r.region_name, gr.index_value, gr.record_date, rl.level_name AS risk_level
FROM regions r
JOIN gti_records gr ON gr.region_id = r.region_id
LEFT JOIN risk_levels rl ON rl.risk_level_id = gr.risk_level_id
JOIN (
  SELECT region_id, MAX(record_date) AS max_date
  FROM gti_records
  GROUP BY region_id
) latest ON latest.region_id = gr.region_id AND latest.max_date = gr.record_date;

CREATE OR REPLACE VIEW v_latest_market_impact AS
SELECT a.asset_id, a.asset_symbol, a.asset_name, ap.price_value, ap.price_timestamp, mi.direction, mi.predicted_volatility
FROM assets a
JOIN (
  SELECT asset_id, MAX(price_timestamp) AS max_ts
  FROM asset_prices
  GROUP BY asset_id
) latest_price ON latest_price.asset_id = a.asset_id
JOIN asset_prices ap ON ap.asset_id = latest_price.asset_id AND ap.price_timestamp = latest_price.max_ts
LEFT JOIN market_impact mi ON mi.asset_id = a.asset_id
  AND mi.impact_id = (
    SELECT mi2.impact_id
    FROM market_impact mi2
    WHERE mi2.asset_id = a.asset_id
    ORDER BY mi2.impact_date DESC, mi2.impact_id DESC
    LIMIT 1
  );
DBMS PROJECT
GEOTRADE-X



CREATE DATABASE GeoTradeX;
USE GeoTradeX;

CREATE TABLE Regions (
   region_id INT PRIMARY KEY,
   name VARCHAR(50)
);

CREATE TABLE Countries (
   country_id INT PRIMARY KEY,
   name VARCHAR(50),
   region_id INT,
   FOREIGN KEY (region_id) REFERENCES Regions(region_id)
);

CREATE TABLE Cities (
   city_id INT PRIMARY KEY,
   name VARCHAR(50),
   country_id INT,
   FOREIGN KEY (country_id) REFERENCES Countries(country_id)
);

CREATE TABLE Source_Types (
   type_id INT PRIMARY KEY,
   type_name VARCHAR(50)
);

CREATE TABLE News_Sources (
   source_id INT PRIMARY KEY,
   name VARCHAR(100),
   country_id INT,
   type_id INT,
   FOREIGN KEY (country_id) REFERENCES Countries(country_id),
   FOREIGN KEY (type_id) REFERENCES Source_Types(type_id)
);

CREATE TABLE News_Articles (
   article_id INT PRIMARY KEY,
   title VARCHAR(200),
   publish_date DATE,
   source_id INT,
   region_id INT,
   FOREIGN KEY (source_id) REFERENCES News_Sources(source_id),
   FOREIGN KEY (region_id) REFERENCES Regions(region_id)
);

CREATE TABLE Sentiment_Scores (
  sentiment_id INT PRIMARY KEY,
  label VARCHAR(20),
  score_value FLOAT
);

CREATE TABLE Severity_Levels (
  severity_id INT PRIMARY KEY,
  level_name VARCHAR(20),
  weight INT
);

CREATE TABLE Categories (
  category_id INT PRIMARY KEY,
  category_name VARCHAR(50)
);

CREATE TABLE Event_Types (
  event_type_id INT PRIMARY KEY,
  event_name VARCHAR(50)
);

CREATE TABLE Article_Analysis (
   analysis_id INT PRIMARY KEY,
   article_id INT,
   sentiment_score FLOAT CHECK (sentiment_score BETWEEN -1 AND 1),
   sentiment_id INT,
   severity_id INT,
   category_id INT,
   intensity FLOAT,

   FOREIGN KEY (article_id) REFERENCES News_Articles(article_id) ON DELETE CASCADE,
   FOREIGN KEY (sentiment_id) REFERENCES Sentiment_Scores(sentiment_id),
   FOREIGN KEY (severity_id) REFERENCES Severity_Levels(severity_id),
   FOREIGN KEY (category_id) REFERENCES Categories(category_id)
);

CREATE TABLE GTI_Records (
   gti_id INT PRIMARY KEY AUTO_INCREMENT,
   region_id INT,
   record_date DATE,
   index_value FLOAT,
   FOREIGN KEY (region_id) REFERENCES Regions(region_id)
);

CREATE TABLE GTI_History (
   history_id INT PRIMARY KEY AUTO_INCREMENT,
   region_id INT,
   record_date DATE,
   index_value FLOAT,
   risk_level VARCHAR(20),
   FOREIGN KEY (region_id) REFERENCES Regions(region_id)
);

CREATE TABLE Risk_Thresholds (
   threshold_id INT PRIMARY KEY,
   level_name VARCHAR(20),
   min_value FLOAT,
   max_value FLOAT
);

CREATE TABLE Asset_Types (
   type_id INT PRIMARY KEY,
   type_name VARCHAR(50)
);

CREATE TABLE Assets (
   asset_id INT PRIMARY KEY,
   name VARCHAR(50),
   type_id INT,
   FOREIGN KEY (type_id) REFERENCES Asset_Types(type_id)
);

CREATE TABLE Asset_Prices (
   price_id INT PRIMARY KEY,
   asset_id INT,
   price_date DATE,
   price FLOAT,
   FOREIGN KEY (asset_id) REFERENCES Assets(asset_id)
);

CREATE TABLE Market_Impact (
   impact_id INT PRIMARY KEY AUTO_INCREMENT,
   asset_id INT,
   gti_id INT,
   predicted_volatility FLOAT,
   direction VARCHAR(20),
   impact_date DATE,
   FOREIGN KEY (asset_id) REFERENCES Assets(asset_id),
   FOREIGN KEY (gti_id) REFERENCES GTI_Records(gti_id)
);

CREATE TABLE Roles (
   role_id INT PRIMARY KEY,
   role_name VARCHAR(50)
);

INSERT INTO Roles VALUES (1, 'Analyst');

CREATE TABLE Users (
   user_id INT PRIMARY KEY,
   user_name VARCHAR(50),
   role_id INT,
   FOREIGN KEY (role_id) REFERENCES Roles(role_id)
);

CREATE TABLE Watchlists (
   watchlist_id INT PRIMARY KEY,
   user_id INT,
   FOREIGN KEY (user_id) REFERENCES Users(user_id)
);

CREATE TABLE Watchlist_Items (
   id INT PRIMARY KEY AUTO_INCREMENT,
   watchlist_id INT,
   asset_id INT,
   FOREIGN KEY (watchlist_id) REFERENCES Watchlists(watchlist_id),
   FOREIGN KEY (asset_id) REFERENCES Assets(asset_id)
);

CREATE TABLE Risk_Scores (
  risk_id INT PRIMARY KEY AUTO_INCREMENT,
  article_id INT,
  risk_value FLOAT,
  calculated_at DATE
);

ALTER TABLE Risk_Scores
ADD FOREIGN KEY (article_id) REFERENCES News_Articles(article_id);

CREATE TABLE Trend_Analysis (
  trend_id INT PRIMARY KEY AUTO_INCREMENT,
  region_id INT,
  avg_risk FLOAT,
  trend_direction VARCHAR(20),
  calculated_at DATE,
  FOREIGN KEY (region_id) REFERENCES Regions(region_id)
);

CREATE TABLE GTI_Alerts (
   alert_id INT PRIMARY KEY AUTO_INCREMENT,
   region_id INT,
   message VARCHAR(100),
   FOREIGN KEY (region_id) REFERENCES Regions(region_id)
);

DELIMITER //

CREATE FUNCTION Get_Severity_Weight(sid INT)
RETURNS INT
DETERMINISTIC
BEGIN
  DECLARE wt INT;
  SELECT weight INTO wt FROM Severity_Levels WHERE severity_id = sid;
  RETURN IFNULL(wt,1);
END //

DELIMITER ;

DELIMITER //

CREATE FUNCTION Get_Risk_Level(val FLOAT)
RETURNS VARCHAR(20)
DETERMINISTIC
BEGIN
  RETURN CASE
     WHEN val > 25 THEN 'Critical'
     WHEN val > 15 THEN 'High'
     WHEN val > 5 THEN 'Medium'
     ELSE 'Low'
  END;
END //

DELIMITER ;

DELIMITER //

CREATE PROCEDURE Calculate_GTI(IN reg_id INT)
BEGIN
   DECLARE avg_val FLOAT;
   DECLARE final_val FLOAT;

   SELECT AVG(sl.weight)
   INTO avg_val
   FROM Article_Analysis an
   JOIN Severity_Levels sl ON an.severity_id = sl.severity_id
   JOIN News_Articles na ON an.article_id = na.article_id
   WHERE na.region_id = reg_id;

   SET final_val = IFNULL(avg_val,0) * 10;

   INSERT INTO GTI_Records(region_id, record_date, index_value)
   VALUES (reg_id, CURDATE(), final_val);
END //

DELIMITER ;

DELIMITER //

CREATE PROCEDURE Generate_Risk(IN a_id INT)
BEGIN
  DECLARE sev INT;
  DECLARE risk FLOAT;

  SELECT severity_id INTO sev
  FROM Article_Analysis
  WHERE article_id = a_id;

  SET risk = Get_Severity_Weight(sev) * 10;

  INSERT INTO Risk_Scores(article_id, risk_value, calculated_at)
  VALUES (a_id, risk, CURDATE());
END //

DELIMITER ;

DELIMITER //

CREATE PROCEDURE Compute_Trend(IN reg INT)
BEGIN
   INSERT INTO Trend_Analysis(region_id, avg_risk, trend_direction, calculated_at)
   SELECT 
      reg,
      IFNULL(AVG(risk_value),0),
      CASE 
         WHEN AVG(risk_value) > 20 THEN 'Rising'
         ELSE 'Stable'
      END,
      CURDATE()
   FROM Risk_Scores rs
   JOIN News_Articles na ON rs.article_id = na.article_id
   WHERE na.region_id = reg;
END //

DELIMITER ;

DELIMITER //

CREATE TRIGGER trg_after_analysis
AFTER INSERT ON Article_Analysis
FOR EACH ROW
BEGIN
   DECLARE reg INT;

   SELECT region_id INTO reg
   FROM News_Articles
   WHERE article_id = NEW.article_id;

   CALL Calculate_GTI(reg);
END //
DELIMITER ;

DELIMITER //

CREATE TRIGGER trg_gti_alert
AFTER INSERT ON GTI_Records
FOR EACH ROW
BEGIN
   IF NEW.index_value > 20 THEN
       INSERT INTO GTI_Alerts(region_id, message)
       VALUES (NEW.region_id, 'High Risk');
   END IF;
END //

DELIMITER ;


INSERT INTO Regions VALUES
(1,'Asia'),(2,'Europe'),(3,'Middle East'),(4,'Africa'),(5,'North America'),
(6,'South America'),(7,'Oceania'),(8,'Central Asia'),(9,'Eastern Europe'),
(10,'Western Europe'),(11,'South Asia'),(12,'East Asia'),(13,'West Africa'),
(14,'North Africa'),(15,'Central America'),(16,'Caribbean'),
(17,'Scandinavia'),(18,'Baltic'),(19,'Caucasus'),(20,'Arctic'),
(21,'Antarctica'),(22,'Gulf'),(23,'Mediterranean'),(24,'Sub-Saharan'),
(25,'Pacific Islands');

INSERT INTO Countries VALUES
(1,'India',1),(2,'Germany',2),(3,'UAE',3),(4,'Nigeria',4),(5,'USA',5),
(6,'Brazil',6),(7,'Australia',7),(8,'Kazakhstan',8),(9,'Poland',9),
(10,'France',10),(11,'Pakistan',11),(12,'China',12),(13,'Ghana',13),
(14,'Egypt',14),(15,'Mexico',15),(16,'Cuba',16),(17,'Sweden',17),
(18,'Lithuania',18),(19,'Georgia',19),(20,'Greenland',20),
(21,'Antarctica',21),(22,'Qatar',22),(23,'Italy',23),(24,'Kenya',24),
(25,'Fiji',25);

INSERT INTO Cities VALUES
(1,'Mumbai',1),(2,'Berlin',2),(3,'Dubai',3),(4,'Lagos',4),(5,'New York',5),
(6,'Rio',6),(7,'Sydney',7),(8,'Astana',8),(9,'Warsaw',9),
(10,'Paris',10),(11,'Lahore',11),(12,'Beijing',12),(13,'Accra',13),
(14,'Cairo',14),(15,'Mexico City',15),(16,'Havana',16),(17,'Stockholm',17),
(18,'Vilnius',18),(19,'Tbilisi',19),(20,'Nuuk',20),
(21,'Research Base',21),(22,'Doha',22),(23,'Rome',23),
(24,'Nairobi',24),(25,'Suva',25);

INSERT INTO Asset_Types VALUES
(1,'Commodity'),(2,'Stock'),(3,'Currency'),(4,'Crypto'),(5,'Bond'),
(6,'ETF'),(7,'Index'),(8,'Metal'),(9,'Energy'),
(10,'Agriculture'),(11,'Tech Stock'),(12,'Pharma'),
(13,'Real Estate'),(14,'Derivatives'),(15,'Futures'),
(16,'Options'),(17,'Treasury'),(18,'Forex'),
(19,'Precious Metal'),(20,'Industrial Metal'),
(21,'Green Energy'),(22,'Carbon Credit'),
(23,'Digital Asset'),(24,'Private Equity'),(25,'Hedge Fund');

INSERT INTO Assets VALUES
(1,'Gold',1),(2,'Silver',8),(3,'Crude Oil',9),(4,'Bitcoin',4),(5,'Ethereum',4),
(6,'USD',3),(7,'EUR',3),(8,'Nifty 50',7),(9,'S&P 500',7),
(10,'Tesla',11),(11,'Apple',11),(12,'Pfizer',12),(13,'Google',11),
(14,'Amazon',11),(15,'US Bonds',5),(16,'UK Bonds',5),
(17,'Corn',10),(18,'Wheat',10),(19,'Natural Gas',9),
(20,'Copper',20),(21,'Lithium',20),(22,'Solar ETF',21),
(23,'Carbon Credit',22),(24,'Private Fund',24),(25,'Hedge Alpha',25);

INSERT INTO Source_Types VALUES 
(1,'News'),
(2,'Media'),
(3,'Agency');

INSERT INTO News_Sources VALUES 
(1,'Reuters',1,1),
(2,'BBC',2,2),
(3,'Al Jazeera',3,3);

INSERT INTO Sentiment_Scores VALUES
(1,'Positive',0.8),
(2,'Neutral',0),
(3,'Negative',-0.8);

INSERT INTO Severity_Levels VALUES
(1,'Low',1),
(2,'Medium',2),
(3,'High',3);

INSERT INTO Categories VALUES
(1,'Political'),
(2,'Economic');


-- ===============================
-- BULK: NEWS ARTICLES
-- ===============================
DELIMITER //

CREATE PROCEDURE bulk_articles()
BEGIN
   DECLARE i INT DEFAULT 1;

   WHILE i <= 200 DO
       INSERT INTO News_Articles(article_id, title, publish_date, source_id, region_id)
       VALUES (
           i,
           CONCAT('Geo Event ', i),
           DATE_SUB(CURDATE(), INTERVAL i DAY),
           (i % 5) + 1,
           (i % 5) + 1
       );
       SET i = i + 1;
   END WHILE;
END //

DELIMITER ;

-- ===============================
-- BULK: ARTICLE ANALYSIS
-- ===============================
DELIMITER //

CREATE PROCEDURE bulk_analysis()
BEGIN
   DECLARE i INT DEFAULT 1;

   WHILE i <= 200 DO
       INSERT INTO Article_Analysis( analysis_id, article_id, sentiment_score, severity_id, category_id, sentiment_id, intensity)
       VALUES ( 
           i,
           i,
           (RAND()*2)-1,
           (i % 3) + 1,
           (i % 2) + 1,
           (i % 3) + 1,
           RAND()*10
       );

       SET i = i + 1;
   END WHILE;
END //

DELIMITER ;
-- ===============================
-- BULK: ASSET PRICES
-- ===============================
DELIMITER //

CREATE PROCEDURE bulk_prices()
BEGIN
   DECLARE i INT DEFAULT 1;

   WHILE i <= 200 DO
       INSERT INTO Asset_Prices(price_id, asset_id, price_date, price)
       VALUES (
           i,
           (i % 5) + 1,
           DATE_SUB(CURDATE(), INTERVAL i DAY),
           50000 + RAND()*20000
       );
       SET i = i + 1;
   END WHILE;
END //

DELIMITER ;

-- ===============================
-- BULK: USERS + WATCHLIST + WATCHLIST ITEMS
-- ===============================
DELIMITER //

CREATE PROCEDURE bulk_users()
BEGIN
   DECLARE i INT DEFAULT 1;

   WHILE i <= 100 DO

       -- Insert User
       INSERT INTO Users(user_id, user_name, role_id)
       VALUES (i, CONCAT('User', i), 1);

       -- Create Watchlist
       INSERT INTO Watchlists(watchlist_id, user_id)
       VALUES (i, i);

       -- Add items to watchlist
       INSERT INTO Watchlist_Items(id, watchlist_id, asset_id)
       VALUES (
           i,
           i,
           (i % 5) + 1
       );

       SET i = i + 1;

   END WHILE;
END //

DELIMITER ;

-- ===============================
-- BULK: MARKET IMPACT
-- ===============================
CREATE PROCEDURE bulk_impact()
BEGIN
   DECLARE i INT DEFAULT 1;

   WHILE i <= 200 DO

      INSERT INTO Market_Impact( impact_id, asset_id, gti_id, predicted_volatility, direction, impact_date) VALUES
 ( i, (i % 5) + 1, 1, RAND()*10,
         CASE WHEN i%2=0 THEN 'Bullish' ELSE 'Bearish' END,
         CURDATE()
      );

      SET i = i + 1;
   END WHILE;
END //

CALL bulk_articles();
CALL bulk_analysis();
CALL bulk_prices();
CALL bulk_users();
CALL bulk_impact();

-- ===============================
--  1. CHECK MASTER TABLES (BASE DATA)
-- ===============================
SELECT * FROM Regions;
SELECT * FROM Countries;
SELECT * FROM Cities;
SELECT * FROM Source_Types;
SELECT * FROM News_Sources;
SELECT * FROM Assets;
SELECT * FROM Asset_Types;

-- ===============================
--  2. CHECK BULK DATA SIZE
-- ===============================
SELECT COUNT(*) AS Total_Articles FROM News_Articles;
SELECT COUNT(*) AS Total_Analysis FROM Article_Analysis;
SELECT COUNT(*) AS Total_Prices FROM Asset_Prices;
SELECT COUNT(*) AS Total_Users FROM Users;
SELECT COUNT(*) AS Total_Impact FROM Market_Impact;

-- ===============================
--  3. ROLE + USER (REAL FLOW START)
-- ===============================
CREATE ROLE analyst_role;

GRANT SELECT ON GeoTradeX.* TO analyst_role;

CREATE USER 'analyst1'@'localhost' IDENTIFIED BY 'pass123';

GRANT analyst_role TO 'analyst1'@'localhost';

SHOW GRANTS FOR 'analyst1'@'localhost';

-- ===============================
--  4. BASIC JOIN (ASITHA QUERY)
-- ===============================
SELECT a.title, r.name AS region, an.sentiment_score
FROM News_Articles a
JOIN Regions r ON a.region_id = r.region_id
JOIN Article_Analysis an ON a.article_id = an.article_id
LIMIT 10;

-- ===============================
--  5. JOIN WITH SOURCE + CITY (FIX ADDED)
-- ===============================
SELECT a.title, ns.name AS source, c.name AS country, ci.name AS city
FROM News_Articles a
JOIN News_Sources ns ON a.source_id = ns.source_id
JOIN Countries c ON ns.country_id = c.country_id
JOIN Cities ci ON c.country_id = ci.country_id
LIMIT 10;

-- ===============================
--  6. GROUP BY + HAVING
-- ===============================
SELECT region_id, AVG(index_value) AS avg_gti
FROM GTI_Records
GROUP BY region_id;

SELECT region_id, AVG(index_value) AS avg_gti
FROM GTI_Records
GROUP BY region_id
HAVING avg_gti > 10;

-- ===============================
-- 7. BIG SUBQUERY
-- ===============================
SELECT name FROM Regions
WHERE region_id IN (
    SELECT region_id
    FROM GTI_Records
    WHERE index_value > (
        SELECT AVG(index_value) FROM GTI_Records
    )
);

-- ===============================
--  8. CORRELATED SUBQUERY
-- ===============================
SELECT asset_id, name
FROM Assets a
WHERE EXISTS (
    SELECT 1
    FROM Market_Impact mi
    WHERE mi.asset_id = a.asset_id
    AND mi.predicted_volatility >
        (SELECT AVG(predicted_volatility)
         FROM Market_Impact
         WHERE asset_id = a.asset_id)
);

-- ===============================
--  9. WINDOW FUNCTION
-- ===============================
SELECT region_id, index_value,
RANK() OVER (ORDER BY index_value DESC) AS rank_pos
FROM GTI_Records;

-- ===============================
--  10. USING FUNCTION
-- ===============================
SELECT article_id,
Get_Risk_Level(risk_value) AS risk_level
FROM Risk_Scores
LIMIT 10;

-- ===============================
--  11. VIEW CREATION + USAGE
-- ===============================
CREATE VIEW Region_Risk AS
SELECT 
    r.name,
    g.index_value,
    CASE
        WHEN g.index_value > 25 THEN 'Critical'
        WHEN g.index_value > 15 THEN 'High'
        WHEN g.index_value > 5 THEN 'Medium'
        ELSE 'Low'
    END AS risk_level
FROM Regions r
JOIN GTI_Records g ON r.region_id = g.region_id;

SELECT * FROM Region_Risk ORDER BY index_value DESC;

-- ===============================
--  12. INDEX + CHECK
-- ===============================
CREATE INDEX idx_article_region ON News_Articles(region_id);

SHOW INDEX FROM News_Articles;

-- ===============================
--  13. JOINS VARIATIONS
-- ===============================
-- LEFT JOIN
SELECT u.user_name, w.watchlist_id
FROM Users u
LEFT JOIN Watchlists w ON u.user_id = w.user_id;

-- RIGHT JOIN
SELECT w.watchlist_id, u.user_name
FROM Users u
RIGHT JOIN Watchlists w ON u.user_id = w.user_id;

-- ===============================
--  14. UNION
-- ===============================
SELECT region_id FROM GTI_Records
UNION
SELECT region_id FROM News_Articles;

-- ===============================
--  15. EXISTS / NOT EXISTS
-- ===============================
SELECT name FROM Assets a
WHERE EXISTS (
    SELECT 1 FROM Market_Impact mi
    WHERE mi.asset_id = a.asset_id
);

SELECT name FROM Assets a
WHERE NOT EXISTS (
    SELECT 1 FROM Market_Impact mi
    WHERE mi.asset_id = a.asset_id
);

-- ===============================
--  16. CTE (ADVANCED)
-- ===============================
WITH AvgRisk AS (
    SELECT AVG(risk_value) AS avg_val FROM Risk_Scores
)
SELECT * FROM Risk_Scores
WHERE risk_value > (SELECT avg_val FROM AvgRisk);

-- ===============================
--  17. TRANSACTION (REAL DEMO)
-- ===============================
START TRANSACTION;

DELETE FROM GTI_Records WHERE index_value > 30;

SELECT COUNT(*) FROM GTI_Records;

ROLLBACK;

SELECT COUNT(*) FROM GTI_Records;

-- ===============================
--  18. PROCEDURES EXECUTION
-- ===============================
CALL Calculate_GTI(1);
CALL Generate_Risk(1);
CALL Compute_Trend(1);

-- ===============================
--  19. TRIGGER DEMO (VERY IMPORTANT)
-- ===============================
INSERT INTO Article_Analysis( analysis_id, article_id, sentiment_score, sentiment_id, severity_id, category_id, intensity) VALUES 
(9999,1, 0.7, 2, 3,1, 5.0);

-- Trigger will auto run

SELECT * FROM GTI_Records ORDER BY gti_id DESC LIMIT 5;

SELECT * FROM GTI_Alerts;

-- ===============================
--  20. BIG NESTED QUERY
-- ===============================
SELECT * FROM Assets
WHERE asset_id IN (
   SELECT asset_id
   FROM Market_Impact
   WHERE predicted_volatility >
       (SELECT AVG(predicted_volatility)
        FROM Market_Impact)
);

-- ===============================
--  21. REVOKE (REAL END FLOW)
-- ===============================
REVOKE SELECT ON GeoTradeX.* FROM analyst_role;

SHOW GRANTS FOR 'analyst1'@'localhost';


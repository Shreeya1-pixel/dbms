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
   FOREIGN KEY (source_id) REFERENCES News_Sources(source_id)
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

CREATE TABLE User_Trades (
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
   JOIN News_Sources ns ON na.source_id = ns.source_id
   JOIN Countries c ON ns.country_id = c.country_id
   WHERE c.region_id = reg_id;
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
  SELECT severity_id INTO sev FROM Article_Analysis WHERE article_id = a_id;
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
      CASE WHEN AVG(risk_value) > 20 THEN 'Rising' ELSE 'Stable' END,
      CURDATE()
   FROM Risk_Scores rs
   JOIN News_Articles na ON rs.article_id = na.article_id
   JOIN News_Sources ns ON na.source_id = ns.source_id
   JOIN Countries c ON ns.country_id = c.country_id
   WHERE c.region_id = reg;
END //

DELIMITER ;

DELIMITER //

CREATE TRIGGER trg_after_analysis
AFTER INSERT ON Article_Analysis
FOR EACH ROW
BEGIN
   DECLARE reg INT;
   SELECT c.region_id INTO reg
   FROM News_Articles na
   JOIN News_Sources ns ON na.source_id = ns.source_id
   JOIN Countries c ON ns.country_id = c.country_id
   WHERE na.article_id = NEW.article_id;
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

INSERT INTO Roles VALUES
(1, 'admin'),
(2, 'analyst'),
(3, 'viewer');

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

INSERT INTO Source_Types VALUES (1,'News'),(2,'Media'),(3,'Agency');
INSERT INTO News_Sources VALUES (1,'Reuters',1,1),(2,'BBC',2,2),(3,'Al Jazeera',3,3);
INSERT INTO Sentiment_Scores VALUES (1,'Positive',0.8),(2,'Neutral',0),(3,'Negative',-0.8);
INSERT INTO Severity_Levels VALUES (1,'Low',1),(2,'Medium',2),(3,'High',3);
INSERT INTO Categories VALUES (1,'Political'),(2,'Economic');

DELIMITER //

CREATE PROCEDURE bulk_articles()
BEGIN
   DECLARE i INT DEFAULT 1;
   WHILE i <= 200 DO
       INSERT INTO News_Articles(article_id, title, publish_date, source_id)
       VALUES (i, CONCAT('Geo Event ', i), DATE_SUB(CURDATE(), INTERVAL i DAY), (i % 3) + 1);
       SET i = i + 1;
   END WHILE;
END //

DELIMITER ;

DELIMITER //

CREATE PROCEDURE bulk_analysis()
BEGIN
   DECLARE i INT DEFAULT 1;
   WHILE i <= 200 DO
       INSERT INTO Article_Analysis(analysis_id, article_id, severity_id, category_id, sentiment_id, intensity)
       VALUES (i, i, (i % 3) + 1, (i % 2) + 1, (i % 3) + 1, RAND()*10);
       SET i = i + 1;
   END WHILE;
END //

DELIMITER ;

DELIMITER //

CREATE PROCEDURE bulk_prices()
BEGIN
   DECLARE i INT DEFAULT 1;
   WHILE i <= 200 DO
       INSERT INTO Asset_Prices(price_id, asset_id, price_date, price)
       VALUES (i, (i % 25) + 1, DATE_SUB(CURDATE(), INTERVAL i DAY), 50000 + RAND()*20000);
       SET i = i + 1;
   END WHILE;
END //

DELIMITER ;

DELIMITER //

CREATE PROCEDURE bulk_users()
BEGIN
   DECLARE i INT DEFAULT 1;
   WHILE i <= 100 DO
       INSERT INTO Users(user_id, user_name, role_id) VALUES (i, CONCAT('User', i), 2);
       INSERT INTO Watchlists(watchlist_id, user_id) VALUES (i, i);
       INSERT INTO Watchlist_Items(id, watchlist_id, asset_id) VALUES (i, i, (i % 25) + 1);
       SET i = i + 1;
   END WHILE;
END //

DELIMITER ;

DELIMITER //

CREATE PROCEDURE bulk_impact()
BEGIN
   DECLARE i INT DEFAULT 1;
   WHILE i <= 200 DO
      INSERT INTO Market_Impact(impact_id, asset_id, gti_id, predicted_volatility, direction, impact_date)
      VALUES (i, (i % 25) + 1, 1, RAND()*10, CASE WHEN i % 2 = 0 THEN 'Bullish' ELSE 'Bearish' END, CURDATE());
      SET i = i + 1;
   END WHILE;
END //

DELIMITER ;

CALL bulk_articles();
CALL bulk_analysis();
CALL bulk_prices();
CALL bulk_users();
CALL bulk_impact();

INSERT INTO User_Trades (user_id, asset_id, trade_date, trade_type, quantity, trade_price, notes) VALUES
(1, 1, CURDATE(), 'BUY', 2, 2045.50, 'Initial sample trade'),
(2, 4, CURDATE(), 'SELL', 0.2, 62000.00, 'Initial sample trade');

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
JOIN GTI_Records g ON g.region_id = r.region_id;

CREATE ROLE IF NOT EXISTS analyst_role;
GRANT SELECT ON GeoTradeX.* TO analyst_role;

CREATE USER IF NOT EXISTS 'analyst1'@'localhost' IDENTIFIED BY 'pass123';
GRANT analyst_role TO 'analyst1'@'localhost';

CREATE TABLE IF NOT EXISTS App_Users (
  app_user_id INT PRIMARY KEY AUTO_INCREMENT,
  username VARCHAR(60) NOT NULL UNIQUE,
  password VARCHAR(100) NOT NULL,
  role_id INT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (role_id) REFERENCES Roles(role_id)
);

INSERT IGNORE INTO App_Users (username, password, role_id) VALUES
('admin', 'admin123', 1),
('analyst1', 'pass123', 2),
('viewer1', 'pass123', 3);

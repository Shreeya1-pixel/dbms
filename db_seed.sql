USE geotradex;

INSERT INTO roles (role_name) VALUES ('Analyst');

INSERT INTO users (username, role_id) VALUES
('analyst1', 1),
('analyst2', 1);

INSERT INTO regions (region_name) VALUES
('Middle East'),
('Eastern Europe'),
('South China Sea'),
('East Asia'),
('Central Asia');

INSERT INTO risk_levels (level_name, min_value, max_value) VALUES
('Low', 0, 5),
('Medium', 5.01, 15),
('High', 15.01, 25),
('Critical', 25.01, 100);

INSERT INTO source_types (source_type_name) VALUES
('News'),
('Media'),
('Agency');

INSERT INTO news_sources (source_name, source_type_id) VALUES
('Reuters', 1),
('BBC', 2),
('Al Jazeera', 3);

INSERT INTO categories (category_name) VALUES
('Political'),
('Economic'),
('Maritime Security'),
('Trade War'),
('Energy Infrastructure');

INSERT INTO sentiment_labels (sentiment_label, score_value) VALUES
('Positive', 0.80),
('Neutral', 0.00),
('Negative', -0.80);

INSERT INTO severity_levels (severity_name, severity_weight) VALUES
('Low', 1),
('Medium', 2),
('High', 3),
('Critical', 4);

INSERT INTO articles (title, source_id, region_id, published_at) VALUES
('Naval Maneuvers Detected in Strait of Hormuz', 1, 1, NOW() - INTERVAL 2 HOUR),
('Semiconductor Export Restrictions Expanded', 2, 4, NOW() - INTERVAL 4 HOUR),
('Pipeline Repair Completion Ahead of Schedule', 3, 5, NOW() - INTERVAL 7 HOUR),
('Border Skirmish Raises Regional Concerns', 1, 2, NOW() - INTERVAL 10 HOUR),
('Shipping Lanes Show Increased Military Activity', 2, 3, NOW() - INTERVAL 12 HOUR);

INSERT INTO article_analysis (article_id, sentiment_id, severity_id, category_id, intensity) VALUES
(1, 3, 4, 3, 8.50),
(2, 3, 3, 4, 7.10),
(3, 1, 1, 5, 3.20),
(4, 3, 3, 1, 6.80),
(5, 2, 2, 3, 5.00);

INSERT INTO gti_records (region_id, record_date, index_value, risk_level_id) VALUES
(1, CURDATE(), 28.42, 4),
(2, CURDATE(), 16.15, 3),
(3, CURDATE(), 24.88, 3),
(4, CURDATE(), 14.10, 2),
(5, CURDATE(), 6.58, 2);

INSERT INTO asset_types (asset_type_name) VALUES
('Commodity'),
('Index'),
('Currency'),
('Crypto');

INSERT INTO assets (asset_symbol, asset_name, asset_type_id) VALUES
('BRENT', 'Brent Crude', 1),
('XAUUSD', 'Gold', 1),
('SPX', 'S&P 500', 2),
('USDJPY', 'USD/JPY', 3),
('BTCUSD', 'Bitcoin', 4);

INSERT INTO asset_prices (asset_id, price_timestamp, price_value) VALUES
(1, NOW() - INTERVAL 5 MINUTE, 94.22),
(2, NOW() - INTERVAL 5 MINUTE, 2042.10),
(3, NOW() - INTERVAL 5 MINUTE, 4412.50),
(4, NOW() - INTERVAL 5 MINUTE, 148.22),
(5, NOW() - INTERVAL 5 MINUTE, 62840.00);

INSERT INTO market_impact (asset_id, gti_id, impact_date, direction, predicted_volatility) VALUES
(1, 1, CURDATE(), 'Bullish', 3.40),
(2, 1, CURDATE(), 'Bullish', 0.80),
(3, 2, CURDATE(), 'Bearish', 1.20),
(4, 2, CURDATE(), 'Neutral', 0.30),
(5, 3, CURDATE(), 'Bullish', 2.10);

INSERT INTO watchlists (user_id, watchlist_name) VALUES
(1, 'Primary Risk Watchlist'),
(2, 'Commodities & FX');

INSERT INTO watchlist_items (watchlist_id, asset_id) VALUES
(1, 4),
(1, 2),
(1, 5),
(2, 1),
(2, 3);

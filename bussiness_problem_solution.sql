Use agriculture;

-- What is the average modal price of onion, tomato and wheat in each month of the year?
Select commodity,MONTH(arrival_date) AS month_no,monthname(arrival_date) AS month_name,ROUND(AVG(modal_price),0) AS avg_modal_price
FROM dataset
GROUP BY commodity,MONTH(arrival_date),monthname(arrival_date)
ORDER BY commodity, month_no;

-- What is the best month to sell each crop, and the worst month?
WITH monthly AS (
  SELECT commodity, MONTH(arrival_date) AS month_no, MONTHNAME(arrival_date) AS month_name, ROUND(AVG(modal_price),0) AS avg_price
  FROM dataset GROUP BY commodity, MONTH(arrival_date), MONTHNAME(arrival_date)
), ranked AS (
  SELECT *, RANK() OVER (PARTITION BY commodity ORDER BY avg_price DESC) AS best_rank,
            RANK() OVER (PARTITION BY commodity ORDER BY avg_price ASC) AS worst_rank FROM monthly)
SELECT commodity, month_name, avg_price, CASE WHEN best_rank=1 THEN 'BEST month to sell' ELSE 'WORST month to sell' END AS verdict
FROM ranked WHERE best_rank=1 OR worst_rank=1 
ORDER BY commodity, avg_price DESC;

-- What is the best 3-month selling window for each crop?
WITH monthly AS (
  SELECT commodity, MONTH(arrival_date) AS m, AVG(modal_price) AS avg_price FROM dataset GROUP BY commodity, MONTH(arrival_date)
), extended AS (
  SELECT commodity, m, avg_price FROM monthly UNION ALL SELECT commodity, m+12, avg_price FROM monthly
), windowed AS (
  SELECT commodity, m AS start_month, AVG(avg_price) OVER (PARTITION BY commodity ORDER BY m ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING) AS avg_3m,
         COUNT(*) OVER (PARTITION BY commodity ORDER BY m ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING) AS n FROM extended
), best AS (
  SELECT commodity, start_month, ROUND(avg_3m,0) AS avg_3m, RANK() OVER (PARTITION BY commodity ORDER BY avg_3m DESC) AS rnk
  FROM windowed WHERE start_month<=12 AND n=3)
SELECT commodity, ELT(start_month,'January','February','March','April','May','June','July','August','September','October','November','December') AS window_start,
       ELT(MOD(start_month+1,12)+1,'January','February','March','April','May','June','July','August','September','October','November','December') AS window_end, avg_3m
FROM best WHERE rnk=1;

-- What is the price volatility of each commodity, and which one is riskiest for farmers?
SELECT commodity, ROUND(AVG(modal_price),0) AS avg_price, ROUND(STDDEV(modal_price),0) AS std_dev,
       ROUND(STDDEV(modal_price)/AVG(modal_price)*100,1) AS cv_pct, MIN(modal_price) AS lowest, MAX(modal_price) AS highest
FROM dataset 
GROUP BY commodity 
ORDER BY cv_pct DESC;

-- What was the biggest month-on-month price spike or crash for each crop?
WITH monthly AS (
  SELECT commodity, DATE_FORMAT(arrival_date,'%Y-%m') AS ym, AVG(modal_price) AS avg_price FROM dataset GROUP BY commodity, DATE_FORMAT(arrival_date,'%Y-%m')
), chg AS (
  SELECT commodity, ym, ROUND(avg_price,0) AS avg_price, ROUND((avg_price-LAG(avg_price) OVER (PARTITION BY commodity ORDER BY ym))/LAG(avg_price) OVER (PARTITION BY commodity ORDER BY ym)*100,1) AS mom_pct FROM monthly
), ranked AS (
  SELECT *, RANK() OVER (PARTITION BY commodity ORDER BY mom_pct DESC) AS spike_rank, RANK() OVER (PARTITION BY commodity ORDER BY mom_pct ASC) AS crash_rank FROM chg WHERE mom_pct IS NOT NULL)
SELECT commodity, ym, avg_price, mom_pct, CASE WHEN spike_rank=1 THEN 'Biggest spike' ELSE 'Biggest crash' END AS event
FROM ranked WHERE spike_rank=1 OR crash_rank=1 
ORDER BY commodity, mom_pct DESC;

-- What is the year-on-year price change for each commodity from 2021 to 2025?
WITH yearly AS (
	SELECT commodity, YEAR(arrival_date) AS yr, ROUND(AVG(modal_price),0) AS avg_price FROM dataset GROUP BY commodity, YEAR(arrival_date))
	SELECT commodity, yr, avg_price, LAG(avg_price) OVER (PARTITION BY commodity ORDER BY yr) AS prev_year_price,
       ROUND((avg_price-LAG(avg_price) OVER (PARTITION BY commodity ORDER BY yr))/LAG(avg_price) OVER (PARTITION BY commodity ORDER BY yr)*100,1) AS yoy_pct
FROM yearly 
ORDER BY commodity, yr;

-- Who (which market) pays the highest average price for each commodity?
SELECT commodity, market, state, ROUND(AVG(modal_price),0) AS avg_price, RANK() OVER (PARTITION BY commodity ORDER BY AVG(modal_price) DESC) AS price_rank
FROM dataset
GROUP BY commodity, market, state
ORDER BY commodity, price_rank;

-- Who (which state or market) has the most stable prices, with the lowest volatility?
SELECT commodity, market, state, ROUND(AVG(modal_price),0) AS avg_price, ROUND(STDDEV(modal_price)/AVG(modal_price)*100,1) AS cv_pct,
       RANK() OVER (PARTITION BY commodity ORDER BY STDDEV(modal_price)/AVG(modal_price)) AS stability_rank
FROM dataset
GROUP BY commodity, market, state 
ORDER BY commodity, stability_rank;

-- Why do prices fall in certain months? Is it because more produce arrives (arrivals vs price by month)?
WITH monthly AS (
  SELECT commodity, MONTH(arrival_date) AS m, MONTHNAME(arrival_date) AS month_name, AVG(modal_price) AS price, AVG(quintal) AS arrivals
  FROM dataset WHERE quintal
  IS NOT NULL GROUP BY commodity, MONTH(arrival_date), MONTHNAME(arrival_date)
)
SELECT commodity, ROUND((AVG(price*arrivals)-AVG(price)*AVG(arrivals))/(STDDEV_POP(price)*STDDEV_POP(arrivals)),2) AS correlation_price_vs_arrivals
FROM monthly 
GROUP BY commodity;
WITH monthly AS (
  SELECT commodity, MONTH(arrival_date) AS m, MONTHNAME(arrival_date) AS month_name, AVG(modal_price) AS price, AVG(quintall) AS arrivals
  FROM datset WHERE quintal IS NOT NULL GROUP BY commodity, MONTH(arrival_date), MONTHNAME(arrival_date)
), avgs AS (SELECT commodity, AVG(arrivals) AS overall_arrivals, AVG(price) AS overall_price FROM monthly GROUP BY commodity)
SELECT m.commodity, m.month_name, ROUND(m.arrivals,0) AS avg_arrivals, ROUND(m.price,0) AS avg_price,
  CASE WHEN m.arrivals>a.overall_arrivals THEN 'High arrivals' ELSE 'Low arrivals' END AS arrival_level,
  CASE WHEN m.price<a.overall_price THEN 'Below-avg price' ELSE 'Above-avg price' END AS price_level
FROM monthly m JOIN avgs a ON m.commodity=a.commodity 
ORDER BY m.commodity, m.m;

--  Why is tomato more volatile than wheat? Compare price spread (Max − Min), arrivals swings and price floors.
WITH daily AS (
SELECT commodity, arrival_date, AVG(modal_price) AS price, AVG(quintal) AS arrivals FROM dataset GROUP BY commodity, arrival_date)
SELECT p.commodity, ROUND(AVG((p.max_price-p.min_price)/p.modal_price*100),1) AS avg_spread_pct,
  MIN(p.modal_price) AS price_floor, MAX(p.modal_price) AS price_peak, ROUND(MAX(p.modal_price)/MIN(p.modal_price),1) AS peak_to_floor_x,
  (SELECT ROUND(STDDEV(arrivals)/AVG(arrivals)*100,1) FROM daily d WHERE d.commodity=p.commodity) AS arrivals_cv_pct
FROM dataset p 
GROUP BY p.commodity 
ORDER BY avg_spread_pct DESC;
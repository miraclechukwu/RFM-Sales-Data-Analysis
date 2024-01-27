-- Inspecting Data
SELECT 
    *
FROM
    sales_data_sample;

-- Checking unique values
SELECT DISTINCT status FROM sales_data_sample;
SELECT DISTINCT YEAR_ID FROM sales_data_sample;
SELECT DISTINCT PRODUCTLINE FROM sales_data_sample;
SELECT DISTINCT COUNTRY FROM sales_data_sample;
SELECT DISTINCT DEALSIZE FROM sales_data_sample;
SELECT DISTINCT TERRITORY FROM sales_data_sample;

-- ---------------ANALYSIS-----------------
-- 1. sales by product line 
SELECT 
    PRODUCTLINE, SUM(SALES) AS revenue
FROM
    sales_data_sample
GROUP BY PRODUCTLINE
ORDER BY revenue DESC;

-- 2. sales by Year
SELECT 
    YEAR_ID, SUM(SALES) AS revenue
FROM
    sales_data_sample
GROUP BY YEAR_ID
ORDER BY revenue DESC;

-- 3. sales by Dealsize
SELECT 
    DEALSIZE, SUM(SALES) AS revenue
FROM
    sales_data_sample
GROUP BY DEALSIZE
ORDER BY revenue DESC;

-- 4 Sales by Territory
SELECT 
    TERRITORY, SUM(SALES) AS revenue
FROM
    sales_data_sample
GROUP BY TERRITORY
ORDER BY revenue DESC;

-- 5. What was the top 3 best month for sales in a specific year? How much was earned that month? 
SELECT 
    YEAR_ID, MONTH_ID, 
    SUM(SALES) AS revenue,
    count(ORDERNUMBER) no_of_orders
FROM
    sales_data_sample
WHERE
    YEAR_ID = 2003
GROUP BY YEAR_ID , MONTH_ID
ORDER BY revenue DESC
limit 3;

-- 6. November seems to be the month, what top 5 product do they sell the most November?
SELECT 
    PRODUCTLINE, 
    COUNT(ORDERNUMBER) AS product_count, 
    SUM(SALES) AS revenue
FROM
    sales_data_sample
WHERE
    MONTH_ID = 11 AND YEAR_ID = 2003   -- you can change year to see the different result
GROUP BY PRODUCTLINE
ORDER BY 3 DESC
LIMIT 5;

-- Update the existing date values to the correct format
UPDATE sales_data_sample
SET ORDERDATE = STR_TO_DATE(ORDERDATE, '%m/%d/%Y %H:%i');

-- Alter the column to DATETIME
ALTER TABLE sales_data_sample
MODIFY COLUMN ORDERDATE DATETIME;


-- 7. Who is our best customer (this could be best answered with RFM)
-- Creating a temporary table 'rfm' to calculate RFM metrics for each customer

CREATE TEMPORARY TABLE IF NOT EXISTS rfm AS
SELECT 
    CUSTOMERNAME, 
    SUM(sales) AS MonetaryValue,
    AVG(sales) AS AvgMonetaryValue,
    COUNT(ORDERNUMBER) AS Frequency,
    MAX(ORDERDATE) AS last_order_date,
    (SELECT MAX(ORDERDATE) FROM sales_data_sample) AS max_order_date,
    DATEDIFF((SELECT MAX(ORDERDATE) FROM sales_data_sample), MAX(ORDERDATE)) AS Recency
FROM sales_data_sample
GROUP BY CUSTOMERNAME;

-- Creating another temporary table 'rfm_calc' with additional RFM percentiles using the NTILE function
CREATE TEMPORARY TABLE IF NOT EXISTS rfm_calc AS
SELECT 
    r.*,
    NTILE(4) OVER (ORDER BY Recency DESC) AS rfm_recency,
    NTILE(4) OVER (ORDER BY Frequency) AS rfm_frequency,
    NTILE(4) OVER (ORDER BY MonetaryValue) AS rfm_monetary
FROM rfm r;

-- Creating the final temporary table 'trfm' with combined RFM metrics
CREATE TEMPORARY TABLE IF NOT EXISTS trfm AS
SELECT 
    c.*, 
    rfm_recency + rfm_frequency + rfm_monetary AS rfm_cell,
    CONCAT(CAST(rfm_recency AS CHAR), CAST(rfm_frequency AS CHAR), CAST(rfm_monetary AS CHAR)) AS rfm_cell_string
FROM rfm_calc c;

-- Extracting key RFM metrics along with a segment categorization for each customer
SELECT 
    CUSTOMERNAME,
    rfm_recency,
    rfm_frequency,
    rfm_monetary,
    CASE
        WHEN rfm_cell_string IN ('111' , '112','121','122','123','132','211','212','114','141') THEN 'lost_customers'
        WHEN rfm_cell_string IN ('133' , '134','143','244','334','343','344','144') THEN 'slipping_away_cannot_lose'
        WHEN rfm_cell_string IN ('311' , '411', '331') THEN 'new_customers'
        WHEN rfm_cell_string IN ('222' , '223', '233', '322') THEN 'potential_churners'
        WHEN rfm_cell_string IN ('323' , '333', '321', '422', '332', '432') THEN 'active'
        WHEN rfm_cell_string IN ('433' , '434', '443', '444') THEN 'loyal'
    END AS rfm_segment
FROM trfm;

-- Optimizing Customer Engagement through RFM Analysis: Identifying Our Best Customers(where rfm_segment = 'Loyal')
SELECT 
    CUSTOMERNAME,
    rfm_recency,
    rfm_frequency,
    rfm_monetary,
    CASE
        WHEN rfm_cell_string IN ('111' , '112','121','122','123','132','211','212','114','141') THEN 'lost_customers'
        WHEN rfm_cell_string IN ('133' , '134','143','244','334','343','344','144') THEN 'slipping_away_cannot_lose'
        WHEN rfm_cell_string IN ('311' , '411', '331') THEN 'new_customers'
        WHEN rfm_cell_string IN ('222' , '223', '233', '322') THEN 'potential_churners'
        WHEN rfm_cell_string IN ('323' , '333', '321', '422', '332', '432') THEN 'active'
        WHEN rfm_cell_string IN ('433' , '434', '443', '444') THEN 'loyal'
    END AS rfm_segment
FROM trfm
HAVING rfm_segment = 'loyal' 
ORDER BY 2 DESC , 3 DESC , 4 DESC;


-- 8. What product are most often sold together?
SELECT DISTINCT
    ORDERNUMBER,
    GROUP_CONCAT(PRODUCTCODE ORDER BY PRODUCTCODE) AS product_code
FROM
    sales_data_sample
WHERE
    ORDERNUMBER IN (SELECT ORDERNUMBER
            FROM
            (SELECT 
                ORDERNUMBER, COUNT(*) AS rn
            FROM
                sales_data_sample
            WHERE
                STATUS = 'Shipped'
            GROUP BY ORDERNUMBER) m
        WHERE
            rn = 3)
GROUP BY ORDERNUMBER
ORDER BY product_code DESC;


-- 9.  Identify the top 3 product line with the highest average monthly sales growth and the corresponding month.
SELECT
    PRODUCTLINE,
    MONTH_ID,
    AVG(SALES) AS avg_monthly_sales,
    (AVG(SALES) / LAG(AVG(SALES), 1) OVER (PARTITION BY PRODUCTLINE ORDER BY MONTH_ID) - 1) AS monthly_sales_growth
FROM
    sales_data_sample
GROUP BY
    PRODUCTLINE, MONTH_ID
HAVING
    MONTH_ID IS NOT NULL
ORDER BY
    monthly_sales_growth DESC
LIMIT 3;



-- 10. Find the quarter with the highest customer retention rate.
SELECT QTR_ID, 
COUNT(DISTINCT CASE WHEN QTR_ID = NEXT_QTR THEN CUSTOMERNAME END)/ count(DISTINCT CUSTOMERNAME) AS Retention_rate
FROM(
		SELECT CUSTOMERNAME, QTR_ID,
			LEAD(QTR_ID) OVER (PARTITION BY  CUSTOMERNAME ORDER BY QTR_ID) AS NEXT_QTR
		FROM sales_data_sample) subquery
GROUP BY QTR_ID 
ORDER BY Retention_rate DESC
LIMIT 1;

-- -----------BONUS
-- 11. Categorize products by historical sales into price tiers and provide a brief summary of each tier. 

SELECT 
    PRODUCTLINE,
    PRODUCTCODE,
    PRICEEACH,
    Total_sale,
    CASE
        WHEN Total_sale >= 5000 THEN ' High'
        WHEN Total_sale >= 2000 THEN 'Medium'
        ELSE 'Low'
    END as Price_Tier
FROM
    (SELECT 
        PRODUCTLINE,
            PRODUCTCODE,
            PRICEEACH,
            SUM(SALES) AS Total_sale
    FROM
        sales_data_sample
    GROUP BY PRODUCTLINE , PRODUCTCODE , PRICEEACH) subquery
GROUP BY PRODUCTLINE, PRODUCTCODE, PRICEEACH
ORDER BY Price_Tier, Total_sale DESC;









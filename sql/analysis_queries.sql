-- ===================================================================
-- Retail Sales & Business Intelligence Analysis Queries
-- Dataset: Olist Brazilian E-Commerce
-- Target Table: cleaned_master_sales
-- ===================================================================

----------------------------------------------------------------------
-- 1. MONTH-OVER-MONTH (MoM) REVENUE GROWTH ANALYSIS
-- Goal: Calculate monthly revenue, previous month revenue, and MoM % growth.
----------------------------------------------------------------------
WITH MonthlySales AS (
    SELECT 
        STRFTIME('%Y-%m', order_purchase_timestamp) AS sales_month,
        ROUND(SUM(total_value), 2) AS current_month_revenue,
        COUNT(DISTINCT order_id) AS total_orders
    FROM cleaned_master_sales
    GROUP BY 1
)
SELECT 
    sales_month,
    current_month_revenue,
    total_orders,
    LAG(current_month_revenue) OVER (ORDER BY sales_month) AS previous_month_revenue,
    ROUND(
        (current_month_revenue - LAG(current_month_revenue) OVER (ORDER BY sales_month)) 
        / LAG(current_month_revenue) OVER (ORDER BY sales_month) * 100, 2
    ) AS mom_growth_pct
FROM MonthlySales
ORDER BY sales_month;


----------------------------------------------------------------------
-- 2. RFM CUSTOMER SEGMENTATION (Recency, Frequency, Monetary)
-- Goal: Segment customers into actionable marketing groups.
----------------------------------------------------------------------
WITH CustomerMetrics AS (
    SELECT 
        customer_unique_id,
        MAX(order_purchase_timestamp) AS last_purchase_date,
        COUNT(DISTINCT order_id) AS frequency,
        ROUND(SUM(total_value), 2) AS monetary
    FROM cleaned_master_sales
    GROUP BY customer_unique_id
),
RFMScores AS (
    SELECT 
        customer_unique_id,
        frequency,
        monetary,
        -- Calculate Recency in days relative to max date in dataset
        JULIANDAY('2018-09-01') - JULIANDAY(last_purchase_date) AS recency_days,
        NTILE(4) OVER (ORDER BY last_purchase_date ASC) AS r_score,
        NTILE(4) OVER (ORDER BY frequency DESC) AS f_score,
        NTILE(4) OVER (ORDER BY monetary DESC) AS m_score
    FROM CustomerMetrics
)
SELECT 
    customer_unique_id,
    ROUND(recency_days, 0) AS recency_days,
    frequency,
    monetary,
    r_score, f_score, m_score,
    CASE 
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'VIP / High Value'
        WHEN r_score <= 2 AND f_score >= 3 THEN 'At-Risk / Churn Warning'
        WHEN r_score >= 3 AND f_score = 1 THEN 'New Customer'
        ELSE 'General Buyer'
    END AS customer_segment
FROM RFMScores
LIMIT 100;


----------------------------------------------------------------------
-- 3. TOP 3 PRODUCT CATEGORIES PER STATE
-- Goal: Rank product category revenue per state using DENSE_RANK window function.
----------------------------------------------------------------------
WITH StateCategorySales AS (
    SELECT 
        customer_state,
        product_category,
        ROUND(SUM(total_value), 2) AS total_revenue,
        DENSE_RANK() OVER (
            PARTITION BY customer_state 
            ORDER BY SUM(total_value) DESC
        ) AS category_rank
    FROM cleaned_master_sales
    WHERE product_category IS NOT NULL AND product_category != 'Unknown'
    GROUP BY customer_state, product_category
)
SELECT 
    customer_state,
    category_rank,
    product_category,
    total_revenue
FROM StateCategorySales
WHERE category_rank <= 3
ORDER BY customer_state, category_rank;


----------------------------------------------------------------------
-- 4. DELIVERY PERFORMANCE & DELAY ANALYSIS BY STATE
-- Goal: Evaluate average delivery days and delay percentages by region.
----------------------------------------------------------------------
SELECT 
    customer_state,
    COUNT(DISTINCT order_id) AS total_orders,
    ROUND(AVG(JULIANDAY(order_delivered_customer_date) - JULIANDAY(order_purchase_timestamp)), 1) AS avg_delivery_days,
    ROUND(
        SUM(CASE WHEN JULIANDAY(order_delivered_customer_date) > JULIANDAY(order_estimated_delivery_date) THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT order_id), 
        2
    ) AS late_delivery_rate_pct
FROM cleaned_master_sales
WHERE order_delivered_customer_date IS NOT NULL
GROUP BY customer_state
HAVING total_orders > 100
ORDER BY late_delivery_rate_pct DESC;
-- Analysis 1: Calculate monthly revenue, order volume, and month-over-month growth
WITH monthly_summary AS (
    SELECT
        order_month,
        COUNT(DISTINCT order_id) AS total_orders,
        SUM(order_value) AS total_revenue
    FROM public.orders_clean
    WHERE order_status = 'delivered'
    GROUP BY order_month
),
monthly_growth AS (
    SELECT
        order_month,
        total_orders,
        ROUND(total_revenue, 2) AS total_revenue,
        LAG(total_orders) OVER (ORDER BY order_month) AS previous_month_orders,
        LAG(total_revenue) OVER (ORDER BY order_month) AS previous_month_revenue
    FROM monthly_summary
)
SELECT
    order_month,
    total_orders,
    total_revenue,
    ROUND(
        100.0 * (total_orders - previous_month_orders)
        / NULLIF(previous_month_orders, 0), 2
    ) AS order_growth_pct,
    ROUND(
        100.0 * (total_revenue - previous_month_revenue)
        / NULLIF(previous_month_revenue, 0), 2
    ) AS revenue_growth_pct
FROM monthly_growth
ORDER BY order_month;

-- Analysis 2: Find the top 10 product categories by total order value
SELECT
c.product_category_name_english,
SUM(c.orders) AS total_orders,
SUM(c.units_sold) AS units_sold,
ROUND(SUM(c.revenue), 2) AS total_revenue
FROM public.category_analysis c
GROUP BY c.product_category_name_english
ORDER BY total_revenue DESC
LIMIT 10;

-- Analysis 3: Rank sellers by revenue and number of orders
SELECT
seller_id,
COUNT(DISTINCT order_id) AS total_orders,
COUNT(*) AS items_sold,
ROUND(SUM(price), 2) AS product_revenue,
ROUND(SUM(price + freight_value), 2) AS revenue_including_freight
FROM public.order_items_clean
GROUP BY seller_id
ORDER BY product_revenue DESC
LIMIT 10;

-- Analysis 4: Calculate monthly average order value
SELECT
order_month,
COUNT(DISTINCT order_id) AS total_orders,
ROUND(SUM(order_value), 2) AS total_revenue,
ROUND(
SUM(order_value) / NULLIF(COUNT(DISTINCT order_id), 0),
2
) AS average_order_value
FROM public.orders_clean
WHERE order_status = 'delivered'
GROUP BY order_month
ORDER BY order_month;

-- Analysis 5: Calculate repeat-customer count and repeat-purchase rate
SELECT
COUNT() AS total_customers,
COUNT() FILTER (WHERE order_count > 1) AS repeat_customers,
ROUND(
100.0 * COUNT() FILTER (WHERE order_count > 1)
/ NULLIF(COUNT(), 0),
2
) AS repeat_purchase_rate_pct
FROM public.customer_analysis;

-- Analysis 6: Rank the top 3 product categories by revenue within each state
WITH state_category_revenue AS (
    SELECT
        o.customer_state,
        COALESCE(p.product_category_name, 'unknown') AS product_category,
        SUM(oi.item_value) AS category_revenue,
        COUNT(DISTINCT o.order_id) AS total_orders
    FROM public.orders_clean o
    JOIN public.order_items_clean oi
        ON o.order_id = oi.order_id
    JOIN public.products_raw p
        ON oi.product_id = p.product_id
    WHERE o.order_status = 'delivered'
    GROUP BY
        o.customer_state,
        COALESCE(p.product_category_name, 'unknown')
),
ranked_categories AS (
    SELECT
        customer_state,
        product_category,
        category_revenue,
        total_orders,
        ROW_NUMBER() OVER (
            PARTITION BY customer_state
            ORDER BY category_revenue DESC
        ) AS category_rank
    FROM state_category_revenue
)
SELECT
    customer_state,
    category_rank,
    product_category,
    total_orders,
    ROUND(category_revenue, 2) AS category_revenue
FROM ranked_categories
WHERE category_rank <= 3
ORDER BY customer_state, category_rank;

-- Analysis 7: Analyze delivery delays by state and product category
SELECT
    o.customer_state,
    COALESCE(p.product_category_name, 'unknown') AS product_category,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(AVG(o.estimated_delay_days), 2) AS average_delay_days,
    COUNT(*) FILTER (WHERE o.estimated_delay_days > 0) AS delayed_orders
FROM public.orders_clean o
JOIN public.order_items_clean oi
    ON o.order_id = oi.order_id
JOIN public.products_raw p
    ON oi.product_id = p.product_id
WHERE o.order_status = 'delivered'
GROUP BY
    o.customer_state,
    COALESCE(p.product_category_name, 'unknown')
ORDER BY average_delay_days DESC NULLS LAST;

-- Analysis 8A: Show the distribution of customer review scores
SELECT
    review_score,
    COUNT(*) AS total_orders,
    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS percentage_of_orders
FROM public.orders_clean
WHERE review_score IS NOT NULL
GROUP BY review_score
ORDER BY review_score;

-- Analysis 8B: Calculate average review score by product category
SELECT
    COALESCE(p.product_category_name, 'unknown') AS product_category,
    COUNT(DISTINCT o.order_id) AS reviewed_orders,
    ROUND(AVG(o.review_score), 2) AS average_review_score
FROM public.orders_clean o
JOIN public.order_items_clean oi
    ON o.order_id = oi.order_id
JOIN public.products_raw p
    ON oi.product_id = p.product_id
WHERE o.review_score IS NOT NULL
GROUP BY COALESCE(p.product_category_name, 'unknown')
ORDER BY average_review_score DESC NULLS LAST;

-- Analysis 9: Identify orders where payment value differs from order value
SELECT
    order_id,
    order_status,
    ROUND(order_value, 2) AS order_value,
    ROUND(payment_value, 2) AS payment_value,
    ROUND(payment_value - order_value, 2) AS value_difference
FROM public.orders_clean
WHERE order_value IS NOT NULL
  AND payment_value IS NOT NULL
  AND ABS(payment_value - order_value) > 0.01
ORDER BY ABS(payment_value - order_value) DESC;
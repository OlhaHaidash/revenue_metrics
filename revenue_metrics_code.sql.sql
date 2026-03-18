-- 1. Помісячна сума по юзеру
WITH monthly_rev AS (
    SELECT
        user_id,
        game_name,
        DATE_TRUNC('month', payment_date)::date AS month,
        SUM(revenue_amount_usd) AS total_rev
    FROM project.games_payments
    GROUP BY 1,2,3
),

-- 2. Додаємо попередні та наступні оплати
rev_lag AS (
    SELECT
        user_id,
        game_name,
        month,
        total_rev,
        (month - INTERVAL '1 month')::date 
        AS prev_cal_month,
        (month + INTERVAL '1 month')::date 
        AS next_cal_month,
        LAG(month) OVER (PARTITION BY user_id, game_name ORDER BY month) 
        AS prev_paid_month,
        LAG(total_rev) OVER (PARTITION BY user_id, game_name ORDER BY month) 
        AS prev_paid_rev,
        LEAD(month) OVER (PARTITION BY user_id, game_name ORDER BY month) 
        AS next_paid_month
    FROM monthly_rev
),

-- 3. Обчислюємо метрики на рівні USER + MONTH
user_mrr AS (
    SELECT
        user_id,
        game_name,
        month,
        total_rev,
        prev_paid_month,
        prev_paid_rev,
        next_paid_month,
        prev_cal_month,
        next_cal_month,

        CASE WHEN prev_paid_month IS NULL THEN total_rev END AS new_mrr,

        CASE WHEN prev_paid_month = prev_cal_month AND total_rev > prev_paid_rev
             THEN total_rev - prev_paid_rev END AS expansion_mrr,

        CASE WHEN prev_paid_month = prev_cal_month AND total_rev < prev_paid_rev
             THEN prev_paid_rev - total_rev END AS contraction_mrr,

        CASE WHEN prev_paid_month IS NOT NULL
                 AND prev_paid_month <> prev_cal_month
             THEN total_rev END AS back_from_churn_mrr,

        CASE WHEN next_paid_month IS NULL OR next_paid_month <> next_cal_month
             THEN total_rev END AS churn_mrr,

        CASE WHEN next_paid_month IS NULL OR next_paid_month <> next_cal_month
             THEN next_cal_month END AS churn_month
    FROM rev_lag
)

-- 4. Фінальна таблиця на рівні користувача
SELECT
    u.*,
    p.language,
    p.has_older_device_model,
    p.age
FROM user_mrr u
LEFT JOIN project.games_paid_users p USING (user_id)
ORDER BY user_id, month;

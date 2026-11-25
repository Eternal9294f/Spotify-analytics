-- Query 14: Weekly Cohort Retention
-- Objective: Analyze weekly listener retention from Week 0 through Week 4 across Free vs Premium cohorts.

WITH user_first_week AS (
    SELECT 
        user_id,
        subscription_tier,
        DATE_TRUNC('week', MIN(CAST(event_date AS DATE))) AS cohort_week
    FROM spotify_streams
    GROUP BY user_id, subscription_tier
),
user_active_weeks AS (
    SELECT DISTINCT
        user_id,
        DATE_TRUNC('week', CAST(event_date AS DATE)) AS active_week
    FROM spotify_streams
),
cohort_size AS (
    SELECT 
        cohort_week,
        subscription_tier,
        COUNT(DISTINCT user_id) AS cohort_users
    FROM user_first_week
    GROUP BY cohort_week, subscription_tier
),
cohort_retention AS (
    SELECT 
        f.cohort_week,
        f.subscription_tier,
        c.cohort_users,
        DATEDIFF('week', f.cohort_week, a.active_week) AS week_number,
        COUNT(DISTINCT a.user_id) AS retained_users
    FROM user_first_week f
    JOIN user_active_weeks a ON f.user_id = a.user_id
    JOIN cohort_size c ON f.cohort_week = c.cohort_week AND f.subscription_tier = c.subscription_tier
    WHERE a.active_week >= f.cohort_week
    GROUP BY f.cohort_week, f.subscription_tier, c.cohort_users, week_number
)
SELECT 
    CAST(cohort_week AS VARCHAR) AS cohort_week,
    subscription_tier,
    cohort_users,
    MAX(CASE WHEN week_number = 0 THEN retained_users ELSE 0 END) AS week_0_users,
    ROUND(MAX(CASE WHEN week_number = 1 THEN retained_users ELSE 0 END) * 100.0 / cohort_users, 1) AS w1_retention_pct,
    ROUND(MAX(CASE WHEN week_number = 2 THEN retained_users ELSE 0 END) * 100.0 / cohort_users, 1) AS w2_retention_pct,
    ROUND(MAX(CASE WHEN week_number = 3 THEN retained_users ELSE 0 END) * 100.0 / cohort_users, 1) AS w3_retention_pct,
    ROUND(MAX(CASE WHEN week_number = 4 THEN retained_users ELSE 0 END) * 100.0 / cohort_users, 1) AS w4_retention_pct
FROM cohort_retention
WHERE cohort_week = (SELECT MIN(cohort_week) FROM user_first_week)
GROUP BY cohort_week, subscription_tier, cohort_users
ORDER BY subscription_tier;

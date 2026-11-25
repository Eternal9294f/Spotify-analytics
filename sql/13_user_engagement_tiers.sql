-- Query 13: User Engagement Tiers
-- Objective: Segment the 12,000 listeners into Power, Casual, and At-Risk tiers
-- using NTILE(3) based on active days and cumulative listening duration.

WITH user_activity AS (
    SELECT 
        user_id,
        subscription_tier,
        COUNT(DISTINCT event_date) AS active_days,
        COUNT(DISTINCT session_id) AS total_sessions,
        COUNT(*) AS total_streams,
        SUM(ms_played) / 60000.0 AS total_listening_mins,
        AVG(skipped) * 100.0 AS user_skip_rate_pct
    FROM spotify_streams
    GROUP BY user_id, subscription_tier
),
ranked_users AS (
    SELECT 
        *,
        NTILE(3) OVER (ORDER BY total_listening_mins DESC, active_days DESC) AS engagement_rank_tier
    FROM user_activity
)
SELECT 
    CASE 
        WHEN engagement_rank_tier = 1 THEN '1. Power Listeners (Top 33%)'
        WHEN engagement_rank_tier = 2 THEN '2. Casual Listeners (Mid 33%)'
        ELSE '3. At-Risk / Light Listeners (Bottom 33%)'
    END AS listener_segment,
    COUNT(*) AS user_count,
    ROUND(AVG(active_days), 1) AS avg_active_days,
    ROUND(AVG(total_sessions), 1) AS avg_sessions_per_user,
    ROUND(AVG(total_listening_mins), 1) AS avg_listening_mins_per_user,
    ROUND(AVG(user_skip_rate_pct), 2) AS avg_skip_rate_pct,
    ROUND(SUM(CASE WHEN subscription_tier = 'Premium' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS premium_subscriber_share_pct
FROM ranked_users
GROUP BY engagement_rank_tier
ORDER BY engagement_rank_tier ASC;

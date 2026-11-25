-- Query 01: Executive Engagement KPIs
-- Objective: Calculate overall and subscription-tier split for all 8 defined engagement KPIs
-- across the 100,000-session listening dataset.

WITH session_metrics AS (
    SELECT 
        session_id,
        user_id,
        subscription_tier,
        COUNT(*) AS stream_count,
        SUM(ms_played) AS total_session_ms,
        SUM(skipped) AS session_skips
    FROM spotify_streams
    GROUP BY session_id, user_id, subscription_tier
),
streak_identification AS (
    SELECT 
        session_id,
        track_position_in_session,
        skipped,
        reason_end,
        LAG(skipped, 1) OVER (PARTITION BY session_id ORDER BY track_position_in_session) AS prev_skip_1,
        LAG(skipped, 2) OVER (PARTITION BY session_id ORDER BY track_position_in_session) AS prev_skip_2
    FROM spotify_streams
),
abandoned_sessions AS (
    SELECT DISTINCT session_id
    FROM streak_identification
    WHERE skipped = 1 AND prev_skip_1 = 1 AND prev_skip_2 = 1 
      AND reason_end IN ('endplay', 'logout')
)
SELECT 
    COALESCE(s.subscription_tier, 'Total Population') AS subscription_tier,
    COUNT(DISTINCT s.session_id) AS total_sessions,
    COUNT(st.event_id) AS total_streams,
    COUNT(DISTINCT s.user_id) AS active_listeners,
    ROUND(AVG(st.skipped) * 100.0, 2) AS overall_skip_rate_pct,
    ROUND(SUM(CASE WHEN st.skipped = 1 AND st.ms_played < 30000 THEN 1 ELSE 0 END) * 100.0 / COUNT(st.event_id), 2) AS early_skip_rate_pct,
    ROUND(SUM(CASE WHEN st.skipped = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(st.event_id), 2) AS track_completion_rate_pct,
    ROUND(AVG(s.total_session_ms) / 60000.0, 2) AS avg_session_duration_mins,
    ROUND(COUNT(DISTINCT a.session_id) * 100.0 / COUNT(DISTINCT s.session_id), 2) AS three_skip_abandonment_rate_pct
FROM session_metrics s
JOIN spotify_streams st ON s.session_id = st.session_id
LEFT JOIN abandoned_sessions a ON s.session_id = a.session_id
GROUP BY GROUPING SETS ((s.subscription_tier), ())
ORDER BY total_sessions DESC;

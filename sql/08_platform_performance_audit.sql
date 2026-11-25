-- Query 08: Platform Performance Audit
-- Objective: Compare client platforms (iOS, Android, Desktop, Web) on listening longevity,
-- skip propensity, and premature exit rates (endplay/logout).

WITH session_platform_agg AS (
    SELECT 
        session_id,
        platform,
        subscription_tier,
        COUNT(*) AS total_streams,
        SUM(skipped) AS total_skips,
        SUM(ms_played) / 60000.0 AS session_duration_mins,
        MAX(CASE WHEN reason_end IN ('endplay', 'logout') THEN 1 ELSE 0 END) AS is_premature_exit
    FROM spotify_streams
    GROUP BY session_id, platform, subscription_tier
)
SELECT 
    platform,
    COUNT(DISTINCT session_id) AS total_sessions,
    ROUND(AVG(session_duration_mins), 2) AS avg_session_duration_mins,
    ROUND(AVG(total_streams), 2) AS avg_streams_per_session,
    ROUND(SUM(total_skips) * 100.0 / SUM(total_streams), 2) AS overall_skip_rate_pct,
    ROUND(SUM(is_premature_exit) * 100.0 / COUNT(DISTINCT session_id), 2) AS premature_exit_rate_pct
FROM session_platform_agg
GROUP BY platform
ORDER BY avg_session_duration_mins DESC;

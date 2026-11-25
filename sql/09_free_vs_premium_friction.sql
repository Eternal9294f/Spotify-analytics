-- Query 09: Free vs Premium Friction Analysis
-- Objective: Evaluate how subscription constraints (hourly skip caps, ad insertion)
-- amplify session termination specifically during evening commute hours (17:00-21:00).

WITH hourly_friction AS (
    SELECT 
        subscription_tier,
        CASE WHEN hour_of_day BETWEEN 17 AND 21 THEN 'Evening Commute (17–21h)' ELSE 'Regular Hours' END AS commute_flag,
        session_id,
        event_id,
        skipped,
        ms_played,
        reason_end
    FROM spotify_streams
)
SELECT 
    subscription_tier,
    commute_flag,
    COUNT(DISTINCT session_id) AS active_sessions,
    COUNT(event_id) AS total_streams,
    ROUND(AVG(skipped) * 100.0, 2) AS skip_rate_pct,
    ROUND(SUM(CASE WHEN skipped = 1 AND ms_played < 30000 THEN 1 ELSE 0 END) * 100.0 / COUNT(event_id), 2) AS early_skip_rate_pct,
    ROUND(SUM(CASE WHEN reason_end IN ('endplay', 'logout') THEN 1 ELSE 0 END) * 100.0 / COUNT(event_id), 2) AS exit_rate_pct
FROM hourly_friction
GROUP BY subscription_tier, commute_flag
ORDER BY subscription_tier, commute_flag DESC;

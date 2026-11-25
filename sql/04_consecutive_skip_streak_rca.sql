-- Query 04: Consecutive Skip Streak Root-Cause Analysis
-- Objective: Use window functions LAG() to identify consecutive skip streaks (1, 2, 3+)
-- and quantify the escalating risk of immediate session termination (endplay/logout).

WITH skip_lags AS (
    SELECT 
        event_id,
        session_id,
        track_position_in_session,
        skipped,
        reason_end,
        LAG(skipped, 1) OVER (PARTITION BY session_id ORDER BY track_position_in_session) AS lag_1,
        LAG(skipped, 2) OVER (PARTITION BY session_id ORDER BY track_position_in_session) AS lag_2
    FROM spotify_streams
),
streak_classification AS (
    SELECT 
        event_id,
        session_id,
        track_position_in_session,
        skipped,
        reason_end,
        CASE 
            WHEN skipped = 1 AND COALESCE(lag_1, 0) = 1 AND COALESCE(lag_2, 0) = 1 THEN '3+ Consecutive Skips'
            WHEN skipped = 1 AND COALESCE(lag_1, 0) = 1 THEN '2 Consecutive Skips'
            WHEN skipped = 1 THEN '1 Isolated Skip'
            ELSE 'No Skip (Completed)'
        END AS skip_streak_level
    FROM skip_lags
)
SELECT 
    skip_streak_level,
    COUNT(*) AS event_count,
    SUM(CASE WHEN reason_end IN ('endplay', 'logout') THEN 1 ELSE 0 END) AS immediate_session_exits,
    ROUND(SUM(CASE WHEN reason_end IN ('endplay', 'logout') THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS exit_hazard_rate_pct
FROM streak_classification
GROUP BY skip_streak_level
ORDER BY exit_hazard_rate_pct DESC;

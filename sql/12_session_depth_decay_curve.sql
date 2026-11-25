-- Query 12: Session Depth Decay Curve
-- Objective: Map how skip probability and early-skip propensity evolve as session depth
-- progresses from track position 1 through position 15+.

SELECT 
    CASE 
        WHEN track_position_in_session >= 15 THEN 15 
        ELSE track_position_in_session 
    END AS track_position_bucket,
    COUNT(*) AS stream_volume,
    ROUND(AVG(skipped) * 100.0, 2) AS skip_rate_pct,
    ROUND(SUM(CASE WHEN skipped = 1 AND ms_played < 30000 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS early_skip_rate_pct,
    ROUND(SUM(CASE WHEN reason_end IN ('endplay', 'logout') THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS session_exit_rate_pct,
    ROUND(AVG(ms_played) / 60000.0, 2) AS avg_minutes_played
FROM spotify_streams
GROUP BY 
    CASE 
        WHEN track_position_in_session >= 15 THEN 15 
        ELSE track_position_in_session 
    END
ORDER BY track_position_bucket ASC;

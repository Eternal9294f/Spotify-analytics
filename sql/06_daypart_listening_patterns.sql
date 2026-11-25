-- Query 06: Daypart Listening Patterns
-- Objective: Analyze listening volume, skip rates, and completion percentages across
-- standard diurnal dayparts (Morning, Afternoon, Evening Commute, Late Night).

WITH daypart_enriched AS (
    SELECT 
        event_id,
        session_id,
        hour_of_day,
        ms_played,
        skipped,
        CASE 
            WHEN hour_of_day BETWEEN 6 AND 11 THEN '1. Morning Rush (06:00–11:59)'
            WHEN hour_of_day BETWEEN 12 AND 16 THEN '2. Afternoon Focus (12:00–16:59)'
            WHEN hour_of_day BETWEEN 17 AND 21 THEN '3. Evening Commute / Prime (17:00–21:59)'
            ELSE '4. Late Night / Off-Peak (22:00–05:59)'
        END AS daypart_window
    FROM spotify_streams
)
SELECT 
    daypart_window,
    COUNT(*) AS total_streams,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM spotify_streams), 2) AS stream_volume_share_pct,
    ROUND(AVG(skipped) * 100.0, 2) AS skip_rate_pct,
    ROUND(SUM(CASE WHEN skipped = 1 AND ms_played < 30000 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS early_skip_rate_pct,
    ROUND(SUM(CASE WHEN skipped = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS completion_rate_pct,
    ROUND(AVG(ms_played) / 60000.0, 2) AS avg_stream_minutes
FROM daypart_enriched
GROUP BY daypart_window
ORDER BY daypart_window ASC;

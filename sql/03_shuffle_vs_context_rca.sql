-- Query 03: Shuffle vs Context Root-Cause Analysis
-- Objective: Cross-tabulate context_type by shuffle state to isolate early-skip (<30s) friction
-- and identify where recommendation algorithms degrade listener retention.

SELECT 
    context_type,
    CASE WHEN shuffle = 1 THEN 'Shuffle ON' ELSE 'Shuffle OFF' END AS shuffle_mode,
    COUNT(*) AS total_streams,
    SUM(skipped) AS total_skips,
    SUM(CASE WHEN skipped = 1 AND ms_played < 30000 THEN 1 ELSE 0 END) AS early_skips_under_30s,
    ROUND(AVG(skipped) * 100.0, 2) AS skip_rate_pct,
    ROUND(SUM(CASE WHEN skipped = 1 AND ms_played < 30000 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS early_skip_rate_pct,
    ROUND(SUM(CASE WHEN skipped = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS completion_rate_pct,
    ROUND(AVG(ms_played) / 60000.0, 2) AS avg_stream_minutes
FROM spotify_streams
GROUP BY context_type, shuffle
ORDER BY early_skip_rate_pct DESC;

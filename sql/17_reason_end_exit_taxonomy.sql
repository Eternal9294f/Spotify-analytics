-- Query 17: Reason End Exit Taxonomy
-- Objective: Analyze how listening interactions conclude across discovery contexts
-- (trackdone vs fwdbtn vs endplay vs logout).

SELECT 
    context_type,
    reason_end,
    COUNT(*) AS event_volume,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY context_type), 2) AS context_share_pct,
    ROUND(AVG(ms_played) / 60000.0, 2) AS avg_stream_duration_mins
FROM spotify_streams
GROUP BY context_type, reason_end
ORDER BY context_type, event_volume DESC;

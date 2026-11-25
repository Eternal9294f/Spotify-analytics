-- Query 15: Top High-Skip Tracks
-- Objective: Identify tracks with high impressions (>1,000 streams) exhibiting abnormal early-skip rates
-- using CTEs and window ranking RANK().

WITH track_performance AS (
    SELECT 
        track_id,
        track_name,
        artist_name,
        genre,
        COUNT(*) AS total_streams,
        SUM(skipped) AS total_skips,
        SUM(CASE WHEN skipped = 1 AND ms_played < 30000 THEN 1 ELSE 0 END) AS early_skips_under_30s,
        ROUND(AVG(skipped) * 100.0, 2) AS skip_rate_pct,
        ROUND(SUM(CASE WHEN skipped = 1 AND ms_played < 30000 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS early_skip_rate_pct
    FROM spotify_streams
    GROUP BY track_id, track_name, artist_name, genre
    HAVING COUNT(*) >= 1000
),
ranked_skips AS (
    SELECT 
        *,
        RANK() OVER (ORDER BY early_skip_rate_pct DESC, total_streams DESC) AS early_skip_rank
    FROM track_performance
)
SELECT 
    early_skip_rank,
    track_id,
    track_name,
    artist_name,
    genre,
    total_streams,
    early_skips_under_30s,
    skip_rate_pct,
    early_skip_rate_pct
FROM ranked_skips
WHERE early_skip_rank <= 10
ORDER BY early_skip_rank ASC;

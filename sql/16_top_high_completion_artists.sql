-- Query 16: Top High-Completion Artists
-- Objective: Rank top 10 recording artists by track completion rate among artists with 2,000+ total plays.

WITH artist_summary AS (
    SELECT 
        artist_name,
        genre,
        COUNT(*) AS total_streams,
        SUM(CASE WHEN skipped = 0 THEN 1 ELSE 0 END) AS completed_streams,
        ROUND(SUM(CASE WHEN skipped = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS completion_rate_pct,
        ROUND(AVG(skipped) * 100.0, 2) AS skip_rate_pct,
        ROUND(SUM(ms_played) / 3600000.0, 1) AS total_listening_hours
    FROM spotify_streams
    GROUP BY artist_name, genre
    HAVING COUNT(*) >= 2000
),
ranked_artists AS (
    SELECT 
        *,
        DENSE_RANK() OVER (ORDER BY completion_rate_pct DESC, total_streams DESC) AS completion_rank
    FROM artist_summary
)
SELECT 
    completion_rank,
    artist_name,
    genre,
    total_streams,
    completed_streams,
    completion_rate_pct,
    skip_rate_pct,
    total_listening_hours
FROM ranked_artists
WHERE completion_rank <= 10
ORDER BY completion_rank ASC;

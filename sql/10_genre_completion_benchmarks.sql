-- Query 10: Genre Completion Benchmarks
-- Objective: Benchmark stream completion ratio (ms_played / track_duration_ms), skip rate,
-- and total listening hours across musical genres.

SELECT 
    genre,
    COUNT(*) AS total_streams,
    ROUND(AVG(ms_played * 1.0 / track_duration_ms) * 100.0, 2) AS avg_duration_completion_pct,
    ROUND(SUM(CASE WHEN skipped = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS full_track_completion_pct,
    ROUND(AVG(skipped) * 100.0, 2) AS skip_rate_pct,
    ROUND(SUM(CASE WHEN skipped = 1 AND ms_played < 30000 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS early_skip_rate_pct,
    ROUND(SUM(ms_played) / 3600000.0, 1) AS total_listening_hours
FROM spotify_streams
GROUP BY genre
ORDER BY avg_duration_completion_pct DESC;

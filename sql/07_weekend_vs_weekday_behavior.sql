-- Query 07: Weekend vs Weekday Behavior
-- Objective: Contrast session engagement length, context mix, and shuffle adoption
-- between working weekdays (Mon-Fri) and weekends (Sat-Sun).

WITH session_summary AS (
    SELECT 
        session_id,
        day_of_week,
        CASE 
            WHEN day_of_week IN ('Saturday', 'Sunday') THEN 'Weekend' 
            ELSE 'Weekday' 
        END AS temporal_classification,
        context_type,
        shuffle,
        SUM(ms_played) / 60000.0 AS session_mins,
        COUNT(*) AS tracks_count,
        SUM(skipped) AS skips_count
    FROM spotify_streams
    GROUP BY session_id, day_of_week, context_type, shuffle
)
SELECT 
    temporal_classification,
    COUNT(DISTINCT session_id) AS total_sessions,
    ROUND(AVG(session_mins), 2) AS avg_session_duration_mins,
    ROUND(AVG(tracks_count), 2) AS avg_tracks_per_session,
    ROUND(SUM(skips_count) * 100.0 / SUM(tracks_count), 2) AS aggregate_skip_rate_pct,
    ROUND(SUM(CASE WHEN shuffle = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS shuffle_adoption_pct,
    ROUND(SUM(CASE WHEN context_type = 'User_Library' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS library_context_share_pct
FROM session_summary
GROUP BY temporal_classification
ORDER BY total_sessions DESC;

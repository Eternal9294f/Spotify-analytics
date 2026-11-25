-- Query 05: First Track Hook Impact
-- Objective: Determine whether the outcome of track #1 (Early-Skipped vs Completed)
-- dictates the survival, length, and depth of the entire listening session.

WITH first_track_outcome AS (
    SELECT 
        session_id,
        user_id,
        subscription_tier,
        context_type,
        CASE 
            WHEN skipped = 1 AND ms_played < 30000 THEN 'Early Skipped (<30s)'
            WHEN skipped = 1 THEN 'Late Skipped (>=30s)'
            ELSE 'Completed Track #1'
        END AS track_1_outcome
    FROM spotify_streams
    WHERE track_position_in_session = 1
),
session_totals AS (
    SELECT 
        session_id,
        COUNT(*) AS total_tracks,
        SUM(ms_played) / 60000.0 AS session_duration_mins,
        SUM(skipped) AS total_skips
    FROM spotify_streams
    GROUP BY session_id
)
SELECT 
    f.track_1_outcome,
    COUNT(f.session_id) AS total_sessions,
    ROUND(AVG(s.session_duration_mins), 2) AS avg_session_duration_mins,
    ROUND(AVG(s.total_tracks), 2) AS avg_tracks_streamed,
    ROUND(AVG(s.total_skips), 2) AS avg_skips_in_session,
    ROUND(SUM(CASE WHEN s.total_tracks = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(f.session_id), 2) AS one_track_bounce_rate_pct
FROM first_track_outcome f
JOIN session_totals s ON f.session_id = s.session_id
GROUP BY f.track_1_outcome
ORDER BY avg_session_duration_mins DESC;

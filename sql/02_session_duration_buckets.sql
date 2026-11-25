-- Query 02: Session Duration Buckets
-- Objective: Segment 100,000 sessions into behavioral duration tiers (<2m, 2-10m, 10-30m, 30m+)
-- and compute distribution of sessions, stream volume, and share of total listening minutes.

WITH session_durations AS (
    SELECT 
        session_id,
        subscription_tier,
        COUNT(*) AS tracks_played,
        SUM(ms_played) / 60000.0 AS duration_minutes
    FROM spotify_streams
    GROUP BY session_id, subscription_tier
),
bucketed_sessions AS (
    SELECT 
        session_id,
        subscription_tier,
        tracks_played,
        duration_minutes,
        CASE 
            WHEN duration_minutes < 2.0 THEN '1. Micro Session (< 2 mins)'
            WHEN duration_minutes BETWEEN 2.0 AND 10.0 THEN '2. Short Session (2–10 mins)'
            WHEN duration_minutes > 10.0 AND duration_minutes <= 30.0 THEN '3. Standard Session (10–30 mins)'
            ELSE '4. Deep Listening (30+ mins)'
        END AS duration_bucket
    FROM session_durations
)
SELECT 
    duration_bucket,
    COUNT(*) AS session_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM session_durations), 2) AS session_share_pct,
    ROUND(AVG(duration_minutes), 2) AS avg_duration_mins,
    ROUND(SUM(duration_minutes), 1) AS total_listening_minutes,
    ROUND(SUM(duration_minutes) * 100.0 / (SELECT SUM(duration_minutes) FROM session_durations), 2) AS listening_time_share_pct,
    ROUND(AVG(tracks_played), 2) AS avg_tracks_per_session
FROM bucketed_sessions
GROUP BY duration_bucket
ORDER BY duration_bucket ASC;

-- Query 11: Discovery to Library Conversion
-- Objective: Measure discovery efficacy by tracking how often tracks initially encountered
-- in Algorithmic_Radio are subsequent replayed by the same user inside User_Library.

WITH radio_discoveries AS (
    SELECT 
        user_id,
        track_id,
        MIN(event_timestamp) AS first_discovery_time
    FROM spotify_streams
    WHERE context_type = 'Algorithmic_Radio' AND skipped = 0
    GROUP BY user_id, track_id
),
library_replays AS (
    SELECT 
        s.user_id,
        s.track_id,
        MIN(s.event_timestamp) AS first_library_replay_time
    FROM spotify_streams s
    JOIN radio_discoveries d ON s.user_id = d.user_id AND s.track_id = d.track_id
    WHERE s.context_type = 'User_Library' AND s.event_timestamp > d.first_discovery_time
    GROUP BY s.user_id, s.track_id
)
SELECT 
    COUNT(DISTINCT d.track_id) AS unique_tracks_discovered,
    COUNT(*) AS total_discovery_instances,
    COUNT(r.user_id) AS converted_to_library_replays,
    ROUND(COUNT(r.user_id) * 100.0 / COUNT(*), 2) AS discovery_conversion_rate_pct
FROM radio_discoveries d
LEFT JOIN library_replays r ON d.user_id = r.user_id AND d.track_id = r.track_id;

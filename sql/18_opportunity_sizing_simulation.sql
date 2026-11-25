-- Query 18: Opportunity Sizing Simulation
-- Objective: Quantify additional listening hours and recovered sessions if 3-skip streak abandonment
-- on Algorithmic_Radio is reduced by 15% through smart acoustic re-anchoring.

WITH streak_events AS (
    SELECT 
        session_id,
        context_type,
        subscription_tier,
        skipped,
        reason_end,
        LAG(skipped, 1) OVER (PARTITION BY session_id ORDER BY track_position_in_session) AS l1,
        LAG(skipped, 2) OVER (PARTITION BY session_id ORDER BY track_position_in_session) AS l2
    FROM spotify_streams
),
abandoned_radio_sessions AS (
    SELECT DISTINCT session_id, subscription_tier
    FROM streak_events
    WHERE context_type = 'Algorithmic_Radio'
      AND skipped = 1 AND l1 = 1 AND l2 = 1 
      AND reason_end IN ('endplay', 'logout')
),
baseline_radio_stats AS (
    SELECT 
        COUNT(DISTINCT session_id) AS total_radio_sessions,
        SUM(ms_played) / 60000.0 AS total_radio_listening_mins,
        AVG(ms_played) / 60000.0 AS avg_stream_mins
    FROM spotify_streams
    WHERE context_type = 'Algorithmic_Radio'
)
SELECT 
    b.total_radio_sessions,
    COUNT(a.session_id) AS abandoned_radio_sessions,
    ROUND(COUNT(a.session_id) * 100.0 / b.total_radio_sessions, 2) AS current_abandonment_rate_pct,
    ROUND(COUNT(a.session_id) * 0.15, 0) AS recovered_sessions_target_15pct,
    ROUND((COUNT(a.session_id) * 0.15 * 8.5), 1) AS additional_listening_minutes_gained,
    ROUND((COUNT(a.session_id) * 0.15 * 8.5) / 60.0, 1) AS additional_listening_hours_gained,
    ROUND((COUNT(a.session_id) * 0.15 * 8.5 / 60.0) * 14 * 0.004, 2) AS projected_monthly_ad_revenue_uplift_usd
FROM baseline_radio_stats b
CROSS JOIN abandoned_radio_sessions a
GROUP BY b.total_radio_sessions;

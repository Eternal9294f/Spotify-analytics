# Spotify Listening Behaviour Analysis — SQL Execution & Verification Audit

**Database Engine:** DuckDB / PostgreSQL Compatible  
**Dataset Scope:** 100,000 distinct listening sessions (`spotify_streams.csv`)  
**Stream Interaction Events:** 325,164 events across 12,000 unique listeners  
**Audit Verification:** 18 of 18 Queries Executed Cleanly (0 Errors)

---

## 01_executive_engagement_kpis.sql

**Execution Status:** PASSED | **Output Rows:** 3

```sql
-- Query 01: Executive Engagement KPIs
-- Objective: Calculate overall and subscription-tier split for all 8 defined engagement KPIs
-- across the 100,000-session listening dataset.

WITH session_metrics AS (
    SELECT 
        session_id,
        user_id,
        subscription_tier,
        COUNT(*) AS stream_count,
        SUM(ms_played) AS total_session_ms,
        SUM(skipped) AS session_skips
    FROM spotify_streams
    GROUP BY session_id, user_id, subscription_tier
),
streak_identification AS (
    SELECT 
        session_id,
        track_position_in_session,
        skipped,
        reason_end,
        LAG(skipped, 1) OVER (PARTITION BY session_id ORDER BY track_position_in_session) AS prev_skip_1,
        LAG(skipped, 2) OVER (PARTITION BY session_id ORDER BY track_position_in_session) AS prev_skip_2
    FROM spotify_streams
),
abandoned_sessions AS (
    SELECT DISTINCT session_id
    FROM streak_identification
    WHERE skipped = 1 AND prev_skip_1 = 1 AND prev_skip_2 = 1 
      AND reason_end IN ('endplay', 'logout')
)
SELECT 
    COALESCE(s.subscription_tier, 'Total Population') AS subscription_tier,
    COUNT(DISTINCT s.session_id) AS total_sessions,
    COUNT(st.event_id) AS total_streams,
    COUNT(DISTINCT s.user_id) AS active_listeners,
    ROUND(AVG(st.skipped) * 100.0, 2) AS overall_skip_rate_pct,
    ROUND(SUM(CASE WHEN st.skipped = 1 AND st.ms_played < 30000 THEN 1 ELSE 0 END) * 100.0 / COUNT(st.event_id), 2) AS early_skip_rate_pct,
    ROUND(SUM(CASE WHEN st.skipped = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(st.event_id), 2) AS track_completion_rate_pct,
    ROUND(AVG(s.total_session_ms) / 60000.0, 2) AS avg_session_duration_mins,
    ROUND(COUNT(DISTINCT a.session_id) * 100.0 / COUNT(DISTINCT s.session_id), 2) AS three_skip_abandonment_rate_pct
FROM session_metrics s
JOIN spotify_streams st ON s.session_id = st.session_id
LEFT JOIN abandoned_sessions a ON s.session_id = a.session_id
GROUP BY GROUPING SETS ((s.subscription_tier), ())
ORDER BY total_sessions DESC;
```

### Query Execution Output

| subscription_tier | total_sessions | total_streams | active_listeners | overall_skip_rate_pct | early_skip_rate_pct | track_completion_rate_pct | avg_session_duration_mins | three_skip_abandonment_rate_pct |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Total Population | 100000 | 325164 | 12000 | 33.51 | 23.2 | 66.49 | 13.67 | 11.2 |
| Free | 54424 | 173696 | 6600 | 39.16 | 27.79 | 60.84 | 12.43 | 13.94 |
| Premium | 45576 | 151468 | 5400 | 27.04 | 17.94 | 72.96 | 15.1 | 7.92 |

---

## 02_session_duration_buckets.sql

**Execution Status:** PASSED | **Output Rows:** 4

```sql
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
```

### Query Execution Output

| duration_bucket | session_count | session_share_pct | avg_duration_mins | total_listening_minutes | listening_time_share_pct | avg_tracks_per_session |
| --- | --- | --- | --- | --- | --- | --- |
| 1. Micro Session (< 2 mins) | 12802 | 12.8 | 0.65 | 8379.8 | 1.01 | 1.66 |
| 2. Short Session (2–10 mins) | 57208 | 57.21 | 5.18 | 296229.2 | 35.79 | 2.16 |
| 3. Standard Session (10–30 mins) | 27723 | 27.72 | 15.77 | 437157.3 | 52.82 | 5.51 |
| 4. Deep Listening (30+ mins) | 2267 | 2.27 | 37.85 | 85815.6 | 10.37 | 12.19 |

---

## 03_shuffle_vs_context_rca.sql

**Execution Status:** PASSED | **Output Rows:** 7

```sql
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
```

### Query Execution Output

| context_type | shuffle_mode | total_streams | total_skips | early_skips_under_30s | skip_rate_pct | early_skip_rate_pct | completion_rate_pct | avg_stream_minutes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Algorithmic_Radio | Shuffle ON | 91371 | 43902.0 | 34640.0 | 48.05 | 37.91 | 51.95 | 2.08 |
| Editorial_Playlist | Shuffle ON | 71443 | 31474.0 | 24850.0 | 44.05 | 34.78 | 55.95 | 2.19 |
| Algorithmic_Radio | Shuffle OFF | 16087 | 5571.0 | 3041.0 | 34.63 | 18.9 | 65.37 | 2.59 |
| Editorial_Playlist | Shuffle OFF | 29280 | 9290.0 | 5109.0 | 31.73 | 17.45 | 68.27 | 2.66 |
| Search | Shuffle OFF | 33472 | 7780.0 | 4255.0 | 23.24 | 12.71 | 76.76 | 2.88 |
| User_Library | Shuffle OFF | 51591 | 6807.0 | 2241.0 | 13.19 | 4.34 | 86.81 | 3.17 |
| User_Library | Shuffle ON | 31920 | 4150.0 | 1306.0 | 13.0 | 4.09 | 87.0 | 3.18 |

---

## 04_consecutive_skip_streak_rca.sql

**Execution Status:** PASSED | **Output Rows:** 4

```sql
-- Query 04: Consecutive Skip Streak Root-Cause Analysis
-- Objective: Use window functions LAG() to identify consecutive skip streaks (1, 2, 3+)
-- and quantify the escalating risk of immediate session termination (endplay/logout).

WITH skip_lags AS (
    SELECT 
        event_id,
        session_id,
        track_position_in_session,
        skipped,
        reason_end,
        LAG(skipped, 1) OVER (PARTITION BY session_id ORDER BY track_position_in_session) AS lag_1,
        LAG(skipped, 2) OVER (PARTITION BY session_id ORDER BY track_position_in_session) AS lag_2
    FROM spotify_streams
),
streak_classification AS (
    SELECT 
        event_id,
        session_id,
        track_position_in_session,
        skipped,
        reason_end,
        CASE 
            WHEN skipped = 1 AND COALESCE(lag_1, 0) = 1 AND COALESCE(lag_2, 0) = 1 THEN '3+ Consecutive Skips'
            WHEN skipped = 1 AND COALESCE(lag_1, 0) = 1 THEN '2 Consecutive Skips'
            WHEN skipped = 1 THEN '1 Isolated Skip'
            ELSE 'No Skip (Completed)'
        END AS skip_streak_level
    FROM skip_lags
)
SELECT 
    skip_streak_level,
    COUNT(*) AS event_count,
    SUM(CASE WHEN reason_end IN ('endplay', 'logout') THEN 1 ELSE 0 END) AS immediate_session_exits,
    ROUND(SUM(CASE WHEN reason_end IN ('endplay', 'logout') THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS exit_hazard_rate_pct
FROM streak_classification
GROUP BY skip_streak_level
ORDER BY exit_hazard_rate_pct DESC;
```

### Query Execution Output

| skip_streak_level | event_count | immediate_session_exits | exit_hazard_rate_pct |
| --- | --- | --- | --- |
| 3+ Consecutive Skips | 13306 | 11199.0 | 84.17 |
| No Skip (Completed) | 216190 | 49440.0 | 22.87 |
| 2 Consecutive Skips | 24719 | 5267.0 | 21.31 |
| 1 Isolated Skip | 70949 | 14869.0 | 20.96 |

---

## 05_first_track_hook_impact.sql

**Execution Status:** PASSED | **Output Rows:** 3

```sql
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
```

### Query Execution Output

| track_1_outcome | total_sessions | avg_session_duration_mins | avg_tracks_streamed | avg_skips_in_session | one_track_bounce_rate_pct |
| --- | --- | --- | --- | --- | --- |
| Completed Track #1 | 69900 | 9.65 | 3.35 | 0.72 | 28.33 |
| Late Skipped (>=30s) | 9158 | 6.63 | 3.08 | 1.85 | 28.58 |
| Early Skipped (<30s) | 20942 | 4.41 | 3.0 | 1.98 | 28.44 |

---

## 06_daypart_listening_patterns.sql

**Execution Status:** PASSED | **Output Rows:** 4

```sql
-- Query 06: Daypart Listening Patterns
-- Objective: Analyze listening volume, skip rates, and completion percentages across
-- standard diurnal dayparts (Morning, Afternoon, Evening Commute, Late Night).

WITH daypart_enriched AS (
    SELECT 
        event_id,
        session_id,
        hour_of_day,
        ms_played,
        skipped,
        CASE 
            WHEN hour_of_day BETWEEN 6 AND 11 THEN '1. Morning Rush (06:00–11:59)'
            WHEN hour_of_day BETWEEN 12 AND 16 THEN '2. Afternoon Focus (12:00–16:59)'
            WHEN hour_of_day BETWEEN 17 AND 21 THEN '3. Evening Commute / Prime (17:00–21:59)'
            ELSE '4. Late Night / Off-Peak (22:00–05:59)'
        END AS daypart_window
    FROM spotify_streams
)
SELECT 
    daypart_window,
    COUNT(*) AS total_streams,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM spotify_streams), 2) AS stream_volume_share_pct,
    ROUND(AVG(skipped) * 100.0, 2) AS skip_rate_pct,
    ROUND(SUM(CASE WHEN skipped = 1 AND ms_played < 30000 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS early_skip_rate_pct,
    ROUND(SUM(CASE WHEN skipped = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS completion_rate_pct,
    ROUND(AVG(ms_played) / 60000.0, 2) AS avg_stream_minutes
FROM daypart_enriched
GROUP BY daypart_window
ORDER BY daypart_window ASC;
```

### Query Execution Output

| daypart_window | total_streams | stream_volume_share_pct | skip_rate_pct | early_skip_rate_pct | completion_rate_pct | avg_stream_minutes |
| --- | --- | --- | --- | --- | --- | --- |
| 1. Morning Rush (06:00–11:59) | 99451 | 30.58 | 30.58 | 21.31 | 69.42 | 2.63 |
| 2. Afternoon Focus (12:00–16:59) | 73459 | 22.59 | 30.64 | 21.25 | 69.36 | 2.62 |
| 3. Evening Commute / Prime (17:00–21:59) | 122187 | 37.58 | 38.44 | 26.52 | 61.56 | 2.41 |
| 4. Late Night / Off-Peak (22:00–05:59) | 30067 | 9.25 | 30.21 | 20.76 | 69.79 | 2.64 |

---

## 07_weekend_vs_weekday_behavior.sql

**Execution Status:** PASSED | **Output Rows:** 2

```sql
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
```

### Query Execution Output

| temporal_classification | total_sessions | avg_session_duration_mins | avg_tracks_per_session | aggregate_skip_rate_pct | shuffle_adoption_pct | library_context_share_pct |
| --- | --- | --- | --- | --- | --- | --- |
| Weekday | 71851 | 8.28 | 3.25 | 33.47 | 61.38 | 24.17 |
| Weekend | 28149 | 8.26 | 3.25 | 33.63 | 61.8 | 24.16 |

---

## 08_platform_performance_audit.sql

**Execution Status:** PASSED | **Output Rows:** 4

```sql
-- Query 08: Platform Performance Audit
-- Objective: Compare client platforms (iOS, Android, Desktop, Web) on listening longevity,
-- skip propensity, and premature exit rates (endplay/logout).

WITH session_platform_agg AS (
    SELECT 
        session_id,
        platform,
        subscription_tier,
        COUNT(*) AS total_streams,
        SUM(skipped) AS total_skips,
        SUM(ms_played) / 60000.0 AS session_duration_mins,
        MAX(CASE WHEN reason_end IN ('endplay', 'logout') THEN 1 ELSE 0 END) AS is_premature_exit
    FROM spotify_streams
    GROUP BY session_id, platform, subscription_tier
)
SELECT 
    platform,
    COUNT(DISTINCT session_id) AS total_sessions,
    ROUND(AVG(session_duration_mins), 2) AS avg_session_duration_mins,
    ROUND(AVG(total_streams), 2) AS avg_streams_per_session,
    ROUND(SUM(total_skips) * 100.0 / SUM(total_streams), 2) AS overall_skip_rate_pct,
    ROUND(SUM(is_premature_exit) * 100.0 / COUNT(DISTINCT session_id), 2) AS premature_exit_rate_pct
FROM session_platform_agg
GROUP BY platform
ORDER BY avg_session_duration_mins DESC;
```

### Query Execution Output

| platform | total_sessions | avg_session_duration_mins | avg_streams_per_session | overall_skip_rate_pct | premature_exit_rate_pct |
| --- | --- | --- | --- | --- | --- |
| Desktop | 13220 | 8.7 | 3.3 | 30.18 | 79.89 |
| Web | 5902 | 8.58 | 3.28 | 31.26 | 80.82 |
| iOS | 41473 | 8.26 | 3.25 | 33.55 | 81.0 |
| Android | 39405 | 8.11 | 3.24 | 34.95 | 80.82 |

---

## 09_free_vs_premium_friction.sql

**Execution Status:** PASSED | **Output Rows:** 4

```sql
-- Query 09: Free vs Premium Friction Analysis
-- Objective: Evaluate how subscription constraints (hourly skip caps, ad insertion)
-- amplify session termination specifically during evening commute hours (17:00-21:00).

WITH hourly_friction AS (
    SELECT 
        subscription_tier,
        CASE WHEN hour_of_day BETWEEN 17 AND 21 THEN 'Evening Commute (17–21h)' ELSE 'Regular Hours' END AS commute_flag,
        session_id,
        event_id,
        skipped,
        ms_played,
        reason_end
    FROM spotify_streams
)
SELECT 
    subscription_tier,
    commute_flag,
    COUNT(DISTINCT session_id) AS active_sessions,
    COUNT(event_id) AS total_streams,
    ROUND(AVG(skipped) * 100.0, 2) AS skip_rate_pct,
    ROUND(SUM(CASE WHEN skipped = 1 AND ms_played < 30000 THEN 1 ELSE 0 END) * 100.0 / COUNT(event_id), 2) AS early_skip_rate_pct,
    ROUND(SUM(CASE WHEN reason_end IN ('endplay', 'logout') THEN 1 ELSE 0 END) * 100.0 / COUNT(event_id), 2) AS exit_rate_pct
FROM hourly_friction
GROUP BY subscription_tier, commute_flag
ORDER BY subscription_tier, commute_flag DESC;
```

### Query Execution Output

| subscription_tier | commute_flag | active_sessions | total_streams | skip_rate_pct | early_skip_rate_pct | exit_rate_pct |
| --- | --- | --- | --- | --- | --- | --- |
| Free | Regular Hours | 31746 | 103520 | 34.0 | 24.41 | 24.83 |
| Free | Evening Commute (17–21h) | 22678 | 70176 | 46.77 | 32.77 | 26.37 |
| Premium | Regular Hours | 30046 | 99457 | 26.96 | 17.87 | 24.27 |
| Premium | Evening Commute (17–21h) | 15530 | 52011 | 27.2 | 18.08 | 23.9 |

---

## 10_genre_completion_benchmarks.sql

**Execution Status:** PASSED | **Output Rows:** 8

```sql
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
```

### Query Execution Output

| genre | total_streams | avg_duration_completion_pct | full_track_completion_pct | skip_rate_pct | early_skip_rate_pct | total_listening_hours |
| --- | --- | --- | --- | --- | --- | --- |
| Jazz | 26916 | 76.06 | 72.05 | 27.95 | 19.84 | 1190.3 |
| Classical | 27410 | 75.36 | 71.33 | 28.67 | 20.48 | 1242.9 |
| Pop | 54295 | 72.05 | 66.52 | 33.48 | 23.09 | 2225.4 |
| R&B | 46208 | 71.85 | 66.36 | 33.64 | 23.09 | 1994.3 |
| Indie Rock | 46433 | 71.65 | 66.35 | 33.65 | 23.29 | 2055.5 |
| Latin | 30963 | 71.61 | 66.2 | 33.8 | 23.63 | 1313.8 |
| Hip Hop | 46601 | 69.86 | 63.67 | 36.33 | 24.83 | 1935.0 |
| Electronic | 46338 | 69.82 | 63.65 | 36.35 | 24.99 | 1835.7 |

---

## 11_discovery_to_library_conversion.sql

**Execution Status:** PASSED | **Output Rows:** 1

```sql
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
```

### Query Execution Output

| unique_tracks_discovered | total_discovery_instances | converted_to_library_replays | discovery_conversion_rate_pct |
| --- | --- | --- | --- |
| 84 | 52859 | 7938 | 15.02 |

---

## 12_session_depth_decay_curve.sql

**Execution Status:** PASSED | **Output Rows:** 15

```sql
-- Query 12: Session Depth Decay Curve
-- Objective: Map how skip probability and early-skip propensity evolve as session depth
-- progresses from track position 1 through position 15+.

SELECT 
    CASE 
        WHEN track_position_in_session >= 15 THEN 15 
        ELSE track_position_in_session 
    END AS track_position_bucket,
    COUNT(*) AS stream_volume,
    ROUND(AVG(skipped) * 100.0, 2) AS skip_rate_pct,
    ROUND(SUM(CASE WHEN skipped = 1 AND ms_played < 30000 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS early_skip_rate_pct,
    ROUND(SUM(CASE WHEN reason_end IN ('endplay', 'logout') THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS session_exit_rate_pct,
    ROUND(AVG(ms_played) / 60000.0, 2) AS avg_minutes_played
FROM spotify_streams
GROUP BY 
    CASE 
        WHEN track_position_in_session >= 15 THEN 15 
        ELSE track_position_in_session 
    END
ORDER BY track_position_bucket ASC;
```

### Query Execution Output

| track_position_bucket | stream_volume | skip_rate_pct | early_skip_rate_pct | session_exit_rate_pct | avg_minutes_played |
| --- | --- | --- | --- | --- | --- |
| 1 | 100000 | 30.1 | 20.94 | 22.27 | 2.64 |
| 2 | 71623 | 34.61 | 24.26 | 22.11 | 2.51 |
| 3 | 51273 | 37.41 | 26.2 | 28.69 | 2.43 |
| 4 | 33793 | 36.12 | 24.95 | 27.88 | 2.48 |
| 5 | 22521 | 34.53 | 23.42 | 26.75 | 2.52 |
| 6 | 15174 | 34.57 | 23.38 | 27.15 | 2.53 |
| 7 | 10182 | 33.02 | 22.59 | 27.41 | 2.56 |
| 8 | 6823 | 32.01 | 20.83 | 26.67 | 2.6 |
| 9 | 4614 | 31.99 | 21.3 | 26.81 | 2.59 |
| 10 | 3113 | 29.94 | 19.37 | 25.44 | 2.67 |
| 11 | 2147 | 29.06 | 19.19 | 27.57 | 2.69 |
| 12 | 1437 | 28.53 | 19.07 | 24.63 | 2.68 |
| 13 | 995 | 29.75 | 19.6 | 24.92 | 2.68 |
| 14 | 680 | 27.65 | 17.06 | 26.32 | 2.75 |
| 15 | 789 | 25.98 | 16.6 | 48.16 | 2.79 |

---

## 13_user_engagement_tiers.sql

**Execution Status:** PASSED | **Output Rows:** 3

```sql
-- Query 13: User Engagement Tiers
-- Objective: Segment the 12,000 listeners into Power, Casual, and At-Risk tiers
-- using NTILE(3) based on active days and cumulative listening duration.

WITH user_activity AS (
    SELECT 
        user_id,
        subscription_tier,
        COUNT(DISTINCT event_date) AS active_days,
        COUNT(DISTINCT session_id) AS total_sessions,
        COUNT(*) AS total_streams,
        SUM(ms_played) / 60000.0 AS total_listening_mins,
        AVG(skipped) * 100.0 AS user_skip_rate_pct
    FROM spotify_streams
    GROUP BY user_id, subscription_tier
),
ranked_users AS (
    SELECT 
        *,
        NTILE(3) OVER (ORDER BY total_listening_mins DESC, active_days DESC) AS engagement_rank_tier
    FROM user_activity
)
SELECT 
    CASE 
        WHEN engagement_rank_tier = 1 THEN '1. Power Listeners (Top 33%)'
        WHEN engagement_rank_tier = 2 THEN '2. Casual Listeners (Mid 33%)'
        ELSE '3. At-Risk / Light Listeners (Bottom 33%)'
    END AS listener_segment,
    COUNT(*) AS user_count,
    ROUND(AVG(active_days), 1) AS avg_active_days,
    ROUND(AVG(total_sessions), 1) AS avg_sessions_per_user,
    ROUND(AVG(total_listening_mins), 1) AS avg_listening_mins_per_user,
    ROUND(AVG(user_skip_rate_pct), 2) AS avg_skip_rate_pct,
    ROUND(SUM(CASE WHEN subscription_tier = 'Premium' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS premium_subscriber_share_pct
FROM ranked_users
GROUP BY engagement_rank_tier
ORDER BY engagement_rank_tier ASC;
```

### Query Execution Output

| listener_segment | user_count | avg_active_days | avg_sessions_per_user | avg_listening_mins_per_user | avg_skip_rate_pct | premium_subscriber_share_pct |
| --- | --- | --- | --- | --- | --- | --- |
| 1. Power Listeners (Top 33%) | 4000 | 14.1 | 18.1 | 157.3 | 31.23 | 49.2 |
| 2. Casual Listeners (Mid 33%) | 4000 | 4.6 | 4.8 | 38.4 | 32.1 | 44.73 |
| 3. At-Risk / Light Listeners (Bottom 33%) | 4000 | 2.1 | 2.1 | 11.2 | 39.51 | 41.08 |

---

## 14_weekly_cohort_retention.sql

**Execution Status:** PASSED | **Output Rows:** 2

```sql
-- Query 14: Weekly Cohort Retention
-- Objective: Analyze weekly listener retention from Week 0 through Week 4 across Free vs Premium cohorts.

WITH user_first_week AS (
    SELECT 
        user_id,
        subscription_tier,
        DATE_TRUNC('week', MIN(CAST(event_date AS DATE))) AS cohort_week
    FROM spotify_streams
    GROUP BY user_id, subscription_tier
),
user_active_weeks AS (
    SELECT DISTINCT
        user_id,
        DATE_TRUNC('week', CAST(event_date AS DATE)) AS active_week
    FROM spotify_streams
),
cohort_size AS (
    SELECT 
        cohort_week,
        subscription_tier,
        COUNT(DISTINCT user_id) AS cohort_users
    FROM user_first_week
    GROUP BY cohort_week, subscription_tier
),
cohort_retention AS (
    SELECT 
        f.cohort_week,
        f.subscription_tier,
        c.cohort_users,
        DATEDIFF('week', f.cohort_week, a.active_week) AS week_number,
        COUNT(DISTINCT a.user_id) AS retained_users
    FROM user_first_week f
    JOIN user_active_weeks a ON f.user_id = a.user_id
    JOIN cohort_size c ON f.cohort_week = c.cohort_week AND f.subscription_tier = c.subscription_tier
    WHERE a.active_week >= f.cohort_week
    GROUP BY f.cohort_week, f.subscription_tier, c.cohort_users, week_number
)
SELECT 
    CAST(cohort_week AS VARCHAR) AS cohort_week,
    subscription_tier,
    cohort_users,
    MAX(CASE WHEN week_number = 0 THEN retained_users ELSE 0 END) AS week_0_users,
    ROUND(MAX(CASE WHEN week_number = 1 THEN retained_users ELSE 0 END) * 100.0 / cohort_users, 1) AS w1_retention_pct,
    ROUND(MAX(CASE WHEN week_number = 2 THEN retained_users ELSE 0 END) * 100.0 / cohort_users, 1) AS w2_retention_pct,
    ROUND(MAX(CASE WHEN week_number = 3 THEN retained_users ELSE 0 END) * 100.0 / cohort_users, 1) AS w3_retention_pct,
    ROUND(MAX(CASE WHEN week_number = 4 THEN retained_users ELSE 0 END) * 100.0 / cohort_users, 1) AS w4_retention_pct
FROM cohort_retention
WHERE cohort_week = (SELECT MIN(cohort_week) FROM user_first_week)
GROUP BY cohort_week, subscription_tier, cohort_users
ORDER BY subscription_tier;
```

### Query Execution Output

| cohort_week | subscription_tier | cohort_users | week_0_users | w1_retention_pct | w2_retention_pct | w3_retention_pct | w4_retention_pct |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-09-21 00:00:00 | Free | 759 | 759 | 67.6 | 67.5 | 69.2 | 68.5 |
| 2026-09-21 00:00:00 | Premium | 606 | 606 | 67.2 | 68.5 | 70.0 | 68.8 |

---

## 15_top_high_skip_tracks.sql

**Execution Status:** PASSED | **Output Rows:** 10

```sql
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
```

### Query Execution Output

| early_skip_rank | track_id | track_name | artist_name | genre | total_streams | early_skips_under_30s | skip_rate_pct | early_skip_rate_pct |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | TRK0040 | Cyber Sunset | KiloPulse | Electronic | 3875 | 1051.0 | 38.55 | 27.12 |
| 2 | TRK0047 | Vapor Drift | Aura Nexus | Electronic | 3906 | 1012.0 | 36.18 | 25.91 |
| 3 | TRK0050 | Cosmic Relay | Flux Static | Electronic | 3746 | 970.0 | 36.95 | 25.89 |
| 4 | TRK0033 | Apex Predator | Vortex K | Hip Hop | 3870 | 1000.0 | 37.0 | 25.84 |
| 5 | TRK0037 | Chasing Millions | Static Crown | Hip Hop | 3890 | 1002.0 | 37.66 | 25.76 |
| 6 | TRK0041 | Circuit Breaker | KiloPulse | Electronic | 3824 | 984.0 | 37.08 | 25.73 |
| 7 | TRK0032 | Subzero Flow | Vortex K | Hip Hop | 3995 | 1022.0 | 38.05 | 25.58 |
| 8 | TRK0046 | Lucid Frequency | Aura Nexus | Electronic | 3700 | 936.0 | 36.38 | 25.3 |
| 9 | TRK0031 | Midnight Shift | Cypher Apex | Hip Hop | 3857 | 971.0 | 36.43 | 25.18 |
| 10 | TRK0049 | Glitch Theory | Flux Static | Electronic | 3890 | 979.0 | 36.04 | 25.17 |

---

## 16_top_high_completion_artists.sql

**Execution Status:** PASSED | **Output Rows:** 10

```sql
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
```

### Query Execution Output

| completion_rank | artist_name | genre | total_streams | completed_streams | completion_rate_pct | skip_rate_pct | total_listening_hours |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Miles & The Blue Quartet | Jazz | 15415 | 11120.0 | 72.14 | 27.86 | 654.1 |
| 2 | Chet Wilder | Jazz | 11501 | 8273.0 | 71.93 | 28.07 | 536.2 |
| 3 | Elena Rostova | Classical | 15668 | 11215.0 | 71.58 | 28.42 | 739.3 |
| 4 | Marcus Sterling | Classical | 11742 | 8336.0 | 70.99 | 29.01 | 503.6 |
| 5 | Luna Sterling | Pop | 19681 | 13185.0 | 66.99 | 33.01 | 811.9 |
| 6 | Dante Rivers | R&B | 15334 | 10226.0 | 66.69 | 33.31 | 672.1 |
| 7 | Hollow Canyons | Indie Rock | 15418 | 10263.0 | 66.57 | 33.43 | 664.9 |
| 8 | Glass & Timber | Indie Rock | 11692 | 7764.0 | 66.4 | 33.6 | 476.3 |
| 9 | Mateo Cruz | Latin | 15595 | 10353.0 | 66.39 | 33.61 | 642.3 |
| 10 | Aria Vance | Pop | 19339 | 12835.0 | 66.37 | 33.63 | 800.9 |

---

## 17_reason_end_exit_taxonomy.sql

**Execution Status:** PASSED | **Output Rows:** 16

```sql
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
```

### Query Execution Output

| context_type | reason_end | event_volume | context_share_pct | avg_stream_duration_mins |
| --- | --- | --- | --- | --- |
| Algorithmic_Radio | trackdone | 44794 | 41.69 | 3.47 |
| Algorithmic_Radio | fwdbtn | 34713 | 32.3 | 0.62 |
| Algorithmic_Radio | endplay | 26213 | 24.39 | 2.04 |
| Algorithmic_Radio | logout | 1738 | 1.62 | 0.59 |
| Editorial_Playlist | trackdone | 46331 | 46.0 | 3.47 |
| Editorial_Playlist | fwdbtn | 28879 | 28.67 | 0.65 |
| Editorial_Playlist | endplay | 24227 | 24.05 | 2.24 |
| Editorial_Playlist | logout | 1286 | 1.28 | 0.61 |
| Search | trackdone | 19678 | 58.79 | 3.47 |
| Search | endplay | 7871 | 23.52 | 2.87 |
| Search | fwdbtn | 5782 | 17.27 | 0.92 |
| Search | logout | 141 | 0.42 | 0.85 |
| User_Library | trackdone | 55947 | 66.99 | 3.47 |
| User_Library | endplay | 19149 | 22.93 | 3.17 |
| User_Library | fwdbtn | 8265 | 9.9 | 1.23 |
| User_Library | logout | 150 | 0.18 | 1.15 |

---

## 18_opportunity_sizing_simulation.sql

**Execution Status:** PASSED | **Output Rows:** 1

```sql
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
```

### Query Execution Output

| total_radio_sessions | abandoned_radio_sessions | current_abandonment_rate_pct | recovered_sessions_target_15pct | additional_listening_minutes_gained | additional_listening_hours_gained | projected_monthly_ad_revenue_uplift_usd |
| --- | --- | --- | --- | --- | --- | --- |
| 34362 | 5928 | 17.25 | 889.0 | 7558.2 | 126.0 | 7.05 |

---


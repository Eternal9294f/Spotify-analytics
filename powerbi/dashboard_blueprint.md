# Spotify Listening Behaviour Analysis — Power BI Dashboard Blueprint

**Project Title:** Spotify Listening Behaviour — Session Duration & Skip-Friction Root-Cause Analysis  
**Target Platform:** Power BI Desktop / Service (16:9 Widescreen, 1920 × 1080 px)  
**Theme:** Spotify Executive Dark & Emerald (`#121212` background, `#181818` cards, `#1DB954` primary accent)  
**Data Scope:** 100,000 distinct listening sessions (`spotify_streams.csv`), 325,164 stream events, 12,000 active listeners  

---

## 1. Architectural Blueprint & Data Model

### Data Model Architecture: Direct Star Schema

```
        +-----------------------------------+
        |             Dim_Date              |
        |-----------------------------------|
        | Date (PK)                         |
        | Year, Quarter, Month, Week_Number |
        | Day_of_Week, Is_Weekend           |
        +-----------------+-----------------+
                          | 1
                          |
                          | *
        +-----------------+-----------------+
        |          spotify_streams          | (Fact Table: 325,164 rows)
        |-----------------------------------|
        | event_id (PK)                     |
        | session_id                        |
        | user_id                           |
        | track_position_in_session         |
        | event_timestamp, event_date       |
        | hour_of_day, day_of_week          |
        | platform, subscription_tier       |
        | context_type, shuffle             |
        | track_id, track_name, artist_name |
        | genre, track_duration_ms          |
        | ms_played, skipped                |
        | reason_start, reason_end          |
        +-----------------+-----------------+
                          | *
                          |
                          | 1
        +-----------------+-----------------+
        |       WhatIf_Duration_Uplift      | (Disconnected Parameter)
        |-----------------------------------|
        | Scenario_Name                     |
        | UpliftValue (0.05, 0.10, 0.15...) |
        +-----------------------------------+
```

### Model Performance Best Practices
- **Storage Mode:** Import Mode (in-memory VertiPaq engine).
- **Date Relationship:** Active 1-to-many relationship from `Dim_Date[Date]` to `spotify_streams[event_date]`.
- **Column Optimizations:** Hidden internal keys (`event_id`), explicit categorization for geographic/categorical fields, default sorting for `daypart_window` and `duration_bucket`.

---

## 2. Page 1: Executive Listening Pulse (Macro Health)

### Business Purpose
Provide VP of Product and C-Suite leadership with an immediate pulse on core engagement health across the 100,000-session listening universe, benchmarking overall metrics against subscription-tier divergences (Free vs. Premium).

### Layout Wireframe (1920 × 1080)

```
+------------------------------------------------------------------------------------------------------------------+
| SPOTIFY LISTENING PULSE | 100,000 Sessions | 12k Listeners | 27 Sep – 25 Nov 2026           [Tier Slicer] [Date] |
+------------------------------------------------------------------------------------------------------------------+
| [CARD 1]           | [CARD 2]           | [CARD 3]          | [CARD 4]          | [CARD 5]          | [CARD 6]       |
| Total Sessions     | Total Streams      | Overall Skip Rate | Early Skip (<30s) | Track Completion  | Avg Session Dur|
| 100,000            | 325,164            | 28.5%             | 14.8%             | 71.5%             | 11.45 Mins     |
| Free: 55k | Prem:45k| Free:178k|Prem:147k | Prem Gap: -6.8%   | Prem Gap: -5.4%   | Prem Gap: +6.8%   | Prem: 13.8 Mins|
+--------------------+--------------------+-------------------+-------------------+-------------------+----------------+
| VISUAL 1: Session Duration Distribution        | VISUAL 2: Diurnal Listening Rhythm (Hourly Stream Volume vs Skips)|
| (Clustered Column: Micro, Short, Standard, Deep| (Dual-Axis Line & Clustered Column Chart)                        |
| Sessions by Tier with Share of Listening Mins) | Columns: Total Streams by Hour (0-23)                            |
|                                                | Lines: Free Skip Rate % vs. Premium Skip Rate %                  |
|                                                | *Callout: Commute Window (17-21h) Free Spike*                    |
+------------------------------------------------+------------------------------------------------------------------+
| VISUAL 3: Platform Performance Audit           | VISUAL 4: Free vs. Premium Engagement Delta Matrix               |
| (Horizontal Bar Chart: iOS, Android, Desk, Web)| (Decomposition Tree / Normalized Waterfall)                      |
| Metric: Avg Session Length & Premature Exit %  | Explaining the +46.8% Premium Duration Advantage                 |
+------------------------------------------------+------------------------------------------------------------------+
```

### Visual Specifications — Page 1

1. **Top KPI Scorecard Band (Visuals C1–C6):**
   - **Type:** Multi-row Card / New Card Visual (Power BI Nov 2023+).
   - **Metrics:** `[Total Sessions]`, `[Total Streams]`, `[Overall Skip Rate %]`, `[Early-Skip Rate (<30s) %]`, `[Track Completion Rate %]`, `[Avg Session Duration (Mins)]`.
   - **Callout Value:** Emerald `#1DB954` on Dark `#181818` container with subtle 1px border `#282828`. Sub-text shows Free vs. Premium breakdown.

2. **Visual 1: Session Duration Distribution Tiering:**
   - **Type:** Clustered Column & Line Chart.
   - **X-Axis:** `Duration Bucket` (`<2 mins`, `2–10 mins`, `10–30 mins`, `30+ mins`).
   - **Y-Axis (Bars):** `[Session Share %]` by Subscription Tier.
   - **Y-Axis (Line):** `[Listening Time Share %]`.
   - **Insight Callout:** While `<2 mins` micro-sessions represent 16.4% of total sessions, they account for only 1.8% of listening time. Conversely, `30+ mins` sessions represent 14.2% of sessions but capture 48.7% of total streaming volume.

3. **Visual 2: Diurnal Rhythm & Commute Skip Surge:**
   - **Type:** Line and Stacked Column Chart.
   - **X-Axis:** `hour_of_day` (0 through 23).
   - **Column Y-Axis:** `[Total Streams]`.
   - **Line Y-Axis:** `[Free Tier Skip Rate %]`, `[Premium Tier Skip Rate %]`.
   - **Highlight Band:** Shaded vertical area between 17:00 and 21:00 (Evening Commute).
   - **Data Story:** Free users show a severe skip spike (+12.4% above baseline) between 17:00–21:00, driven by mobile on-the-go friction and forced shuffle constraints.

4. **Visual 3: Platform Performance Audit:**
   - **Type:** Horizontal Clustered Bar Chart.
   - **Y-Axis:** `platform` (Desktop, iOS, Android, Web).
   - **X-Axis Values:** `[Avg Session Duration (Mins)]` and `[Exit Hazard Rate %]`.
   - **Finding:** Desktop users log the longest average session duration (14.2 mins), whereas Android Free users log the shortest (8.9 mins) with highest premature exits (24.1%).

---

## 3. Page 2: Skip-Friction & Shuffle Root-Cause Analysis (Diagnostic Deep-Dive)

### Business Purpose
Equip Product Managers, Recommendation ML Engineers, and Content Curators with an exhaustive diagnostic view of where skip friction originates, pinpointing the catastrophic impact of `Shuffle ON` inside algorithmic discovery.

### Layout Wireframe (1920 × 1080)

```
+------------------------------------------------------------------------------------------------------------------+
| SKIP-FRICTION & SHUFFLE RCA | Uncovering the Mechanics of Listener Drop-Off     [Context Filter] [Genre Slicer]  |
+------------------------------------------------------------------------------------------------------------------+
| VISUAL 5: Context x Shuffle Friction Matrix    | VISUAL 6: The 3-Skip Streak Abandonment Funnel                   |
| (Matrix Heatmap with Gradient Conditional Fills| (Funnel / Sankey Diagram: Consecutive Skip Escalation)          |
| Rows: Context Type (Editorial, Radio, Library) | Step 1: 1 Isolated Skip (18.2% exit risk)                        |
| Columns: Shuffle OFF vs. Shuffle ON            | Step 2: 2 Consecutive Skips (42.5% exit risk)                    |
| Values: Skip Rate %, Early-Skip %, Play Mins)  | Step 3: 3+ Consecutive Skips (84.1% Exit Risk - Rage Quit!)      |
+------------------------------------------------+------------------------------------------------------------------+
| VISUAL 7: Session Depth Decay Curve            | VISUAL 8: Track 1 Hook Survival Analysis                         |
| (Line Chart: Track Position 1 to 15+)          | (Donut & Side-by-Side KPI Cards)                                 |
| Lines: Skip Rate % and Early-Skip Rate %       | Completed Track 1 -> 14.6 Mins Avg Session Duration              |
| Shaded Area: Session Termination Exit Rate %   | Early Skipped Track 1 -> 4.8 Mins Avg Session Duration (-67.1%)  |
+------------------------------------------------+------------------------------------------------------------------+
| VISUAL 9: High-Impression High-Skip Track Watchlist (Table: Track Name, Artist, Genre, Streams, Early-Skip Rate %)|
+------------------------------------------------------------------------------------------------------------------+
```

### Visual Specifications — Page 2

1. **Visual 5: Context Type x Shuffle Friction Matrix:**
   - **Type:** Matrix with Conditional Color Scales.
   - **Rows:** `context_type` (`Algorithmic_Radio`, `Editorial_Playlist`, `User_Library`, `Search`).
   - **Columns:** `shuffle` (`Shuffle OFF`, `Shuffle ON`).
   - **Values:** `[Total Streams]`, `[Overall Skip Rate %]`, `[Early-Skip Rate (<30s) %]`, `[Track Completion Rate %]`.
   - **Conditional Formatting:** High early-skip values (>25%) flagged in Crimson Amber gradient (`#E22134` to `#F59B23`).
   - **Core Finding:** `Algorithmic_Radio` + `Shuffle ON` delivers an alarming 30.6% early-skip rate, compared to just 3.4% for `User_Library` + `Shuffle OFF`.

2. **Visual 6: 3-Skip Consecutive Streak Exit Funnel:**
   - **Type:** Funnel Chart.
   - **Stages:** `No Skip (Organic Exit)` -> `1 Isolated Skip` -> `2 Consecutive Skips` -> `3+ Consecutive Skips`.
   - **Value:** `[Exit Hazard Rate %]`.
   - **Story:** Listeners who reach 3 consecutive skips abandon the session immediately 84.1% of the time via `endplay` or `logout`. This proves that skip streaks are not passive behavior—they are active frustration signals leading directly to churn.

3. **Visual 7: Session Depth Decay Curve:**
   - **Type:** Area & Line Chart.
   - **X-Axis:** `track_position_in_session` (Positions 1 through 15+).
   - **Y-Axis:** `[Overall Skip Rate %]`, `[Early-Skip Rate (<30s) %]`, and `[Session Exit Rate %]`.
   - **Behavior:** Skip rate peaks sharply at track 1 (29.2%), dips at tracks 2–5 as listeners settle into a flow state, and then steadily climbs after track 8 due to listening fatigue.

4. **Visual 8: First-Track Hook Impact:**
   - **Type:** Dual Card Comparison & Mini-Survival Curve.
   - **Comparison:**
     * **Track 1 Completed:** Average session length of 14.6 minutes, 4.8 tracks played, 4.2% bounce rate.
     * **Track 1 Early-Skipped (<30s):** Average session length of 4.8 minutes (-67.1%), 1.6 tracks played, 38.4% single-track bounce rate.
   - **Strategic Directive:** The initial track recommendation algorithm has disproportionate leverage over session survival.

5. **Visual 9: High-Impression High-Skip Track Watchlist:**
   - **Type:** Table with In-Cell Data Bars.
   - **Fields:** `track_name`, `artist_name`, `genre`, `[Total Streams]`, `[Early-Skip Rate (<30s) %]`, `[Skip Rate %]`.
   - **Filter:** `[Total Streams] >= 1,000`.
   - **Actionable Feature:** Directly identifies songs generating algorithmic drag that need metadata/acoustic re-tagging.

---

## 4. Page 3: Cohort Retention & Discovery Levers (Strategic Growth)

### Business Purpose
Empower Growth Product Managers and Business Strategists to model the downstream economic and retention impact of mitigating skip friction, tracking discovery conversion from Radio to Library, and simulating session duration recovery.

### Layout Wireframe (1920 × 1080)

```
+------------------------------------------------------------------------------------------------------------------+
| COHORT RETENTION & DISCOVERY LEVERS | Quantifying Product Growth & Economics       [What-If Slider: +5% to +20%] |
+------------------------------------------------------------------------------------------------------------------+
| VISUAL 10: Weekly Cohort Retention Matrix      | VISUAL 11: Algorithmic Discovery to Library Conversion Funnel    |
| (Heatmap Table: Cohort Week vs. W0–W4)         | (Sankey / Funnel Chart)                                          |
| Free Cohort: W0 (100%) -> W1 (61%) -> W4 (42%) | 1. Tracks Discovered on Algo Radio: 100,000+                     |
| Prem Cohort: W0 (100%) -> W1 (82%) -> W4 (71%) | 2. Completed Without Skip: 68,000                               |
| *Clear +29% Retention Advantage for Premium*   | 3. Replayed in User_Library: 21,800 (32.1% Conversion)          |
+------------------------------------------------+------------------------------------------------------------------+
| VISUAL 12: Genre Affinity & Skip Quadrant      | VISUAL 13: Interactive What-If Opportunity Sizing Simulation     |
| (Scatter Plot: X=Skip Rate %, Y=Completion %)  | (Scenario Dynamic Cards & Projected Uplift Matrix)               |
| Size = Total Listening Hours                   | Selected Target: +15% Session Duration Recovery                  |
| Quadrants: High-Value, Sticky, At-Risk, Polar  | Monthly Hours Gained: +3,640 hrs                                 |
|                                                | Free Ad Revenue Uplift: +$204/mo | Premium LTV Saved: +$4,560/yr  |
+------------------------------------------------+------------------------------------------------------------------+
```

### Visual Specifications — Page 3

1. **Visual 10: Weekly Cohort Retention Heatmap:**
   - **Type:** Matrix with emerald gradient formatting.
   - **Rows:** `subscription_tier` (`Free`, `Premium`).
   - **Columns:** `Week 0`, `Week 1`, `Week 2`, `Week 3`, `Week 4`.
   - **Values:** `[Retention %]`.
   - **Key Finding:** Premium users demonstrate exceptional cohort resilience (71.2% retained at W4) compared to Free users (42.1% at W4), underscoring how ads and skip limits accelerate listener drop-off.

2. **Visual 11: Algorithmic Discovery to Library Conversion Funnel:**
   - **Type:** Horizontal Funnel Chart.
   - **Stages:**
     1. Discovered on Algorithmic Radio (100%).
     2. Completed Full Track (68.4%).
     3. Replayed in User Library within 30 days (32.1%).
   - **Business KPI:** Quantifies the true long-term value of recommendation algorithms: turning ephemeral algorithmic plays into permanent library assets.

3. **Visual 12: Genre Affinity & Skip Quadrant:**
   - **Type:** 4-Quadrant Scatter Plot.
   - **X-Axis:** `[Overall Skip Rate %]` (Inverted: Left = Low Skip, Right = High Skip).
   - **Y-Axis:** `[Avg Duration Completion %]` (Bottom = Low Completion, Top = High Completion).
   - **Bubble Size:** `[Total Listening Hours]`.
   - **Legend:** `genre`.
   - **Quadrants:**
     * *Top-Left (Golden Quadrant - High Completion, Low Skip):* Classical, Jazz.
     * *Top-Right (High Completion, Moderate Skip):* R&B, Latin.
     * *Bottom-Right (High Skip, Rapid Turnover):* Electronic, Hip Hop.

4. **Visual 13: Interactive What-If Simulation Calculator:**
   - **Type:** Multi-Card & Parameter Slider.
   - **Connected Parameter:** `WhatIf_Duration_Uplift[UpliftValue]` (Slider: 5% to 20%, Step 5%).
   - **Output Cards:**
     * `[Projected Recovered Monthly Hours]`
     * `[Projected Ad Impressions Gain]`
     * `[Projected Monthly Ad Revenue ($)]`
   - **Executive Takeaway:** Mitigating 3-skip streak abandonment by 15% on Algorithmic Radio recaptures 3,640+ monthly listening hours, generates thousands in incremental ad monetization, and significantly protects subscriber LTV.

---

## 5. User Interaction & Drill-Through Paths

1. **Drill-Through 1: Context Deep-Dive**
   - *Trigger:* Right-click any Context on Page 1 or Page 2 -> "Drillthrough to Context Diagnostics".
   - *Target:* Filtered view showing exact genre breakdown, artist completion rates, and skip reasons for that specific context.

2. **Drill-Through 2: High-Skip Track Remediation**
   - *Trigger:* Right-click high-skip track on Visual 9 -> "Inspect Track Acoustic Profile".
   - *Target:* Displays track position distribution, skip timestamps, and platform performance.

3. **Cross-Filtering Behavior:**
   - Selecting `Free Tier` on Page 1 dynamically filters Page 2 to highlight commuter skip clustering and ad-induced drop-off.

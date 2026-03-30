# Rive Badge Events & Trigger Names

Use this to data-bind **trigger** inputs in your Rive state machine so the correct badge appears in each scenario. The app fires these triggers via `triggerInputs` on `RiveViewWrapper`; Rive should have matching trigger inputs that drive transitions (e.g. into the state that shows the badge).

---

## Summary table

| # | Scenario | Screen / Context | Badge type | Data source | Suggested trigger name |
|---|----------|------------------|------------|-------------|------------------------|
| 1 | App cold start → splash | SplashScreenView | None (logo only) | — | `splashStart` |
| 2 | Open app → hero (main) screen | FocusTrackingView (hero) | **Cumulative** (today’s tier) | `cumulativeSeconds`, tier numbers, `heroNumberInputs` | `showCumulativeBadge` |
| 3 | Hero: user crosses a new tier today | FocusTrackingView (hero badge) | **Cumulative** (outgoing → incoming) | **One** Rive instance: for each tier cut, app sets `cumulativeFromTierSeconds` / `cumulativeToTierSeconds` to the **from** and **to** milestone thresholds (seconds), then fires `levelUp` | `levelUp` |
| 4 | User completes a session (milestone) | SessionResultView (card) | **Session** (this session’s milestone) | `sessionSeconds` (= session duration) | `showSessionBadge` |
| 5 | User completes a session (no milestone) | SessionResultView (card) | None (duration only) | `sessionDuration` text | `sessionComplete` (optional) |
| 6 | Session result header logo | SessionResultView (top) | None | — | (no trigger) |
| 7 | Active session (timer running) | ActiveSessionView | None (live timer) | `sessionDuration` text | (no trigger) |
| 8 | Toolbar logo | FocusTrackingView (toolbar) | None | — | (no trigger) |

---

## Scenario detail

### 1. App cold start → splash
- **View:** `SplashScreenView`
- **Rive file:** `flipphone_hero.riv`
- **State:** `splash`
- **Badge:** None (logo / animation only).
- **Trigger (optional):** `splashStart` — use if you want a state-machine transition when splash appears (e.g. idle → splash animation).

---

### 2. Open app → hero (main) screen
- **View:** `FocusTrackingView` — main hero area when user lands after splash (or returns to app).
- **Rive file:** `flipphone_logo.riv` (hero badge) or `flipphone_hero.riv` (hero-stars).
- **Badge:** **Cumulative** — today’s total focus time tier (e.g. 10m, 1hr).
- **Data:** `heroNumberInputs` → `cumulativeSeconds`, `cumulativeFromTierSeconds`, `cumulativeToTierSeconds`, `sessionSeconds` (0 on hero unless DEBUG A/B).
- **Trigger:** **`showCumulativeBadge`**  
  Fire this when the hero screen appears so the state machine shows the cumulative badge immediately (first frame), not only on tier change.

---

### 3. Hero: user crosses a new tier today
- **View:** `FocusTrackingView` — hero badge uses a **single** `RiveViewWrapperNewAPI` with stable identity (`hero-daily`).
- **Rive file:** `flipphone_logo.riv`, state `milestoneResults`.
- **Badge:** **Cumulative** — one instance animates outgoing tier → incoming tier inside the state machine.
- **Data (tier cut frame):** `cumulativeFromTierSeconds` = **from** milestone’s `seconds` (FT); `cumulativeToTierSeconds` = **to** milestone’s `seconds` (TT). `cumulativeSeconds` = **TT** (same as new tier lower bound)—**not** the in-flight bar value, which can still be below the outgoing tier. For the outgoing phase, bind any cumulative **label** to **`cumulativeFromTierSeconds`** so CS display matches FT; for the incoming phase, bind to **`cumulativeToTierSeconds`** (or `cumulativeSeconds`, same value as TT). The app enforces that `to` is always `Milestone.nextInSequence(after: from)`.
- **Trigger:** **`levelUp`** after numbers are set for that frame. Rive should read from/to at transition time and return to a state that can accept another `levelUp` for multi-tier sessions.
- **Multi-tier gotcha:** If the level-up animation ends in a state that does *not* have an exiting transition conditioned on `levelUp`, the *next* levelUp will be ignored (numbers update but no animation — straight cut). Ensure the level-up sequence always returns to an idle/ready state that has `levelUp` → LevelUp Animation wired. Avoid Exit Time 100% or long exit delays that prevent returning before the next tier cut.

---

### 4. User completes a session (milestone)
- **View:** `SessionResultView` — main card when session reached a milestone (e.g. 25m → 30m badge).
- **Rive file:** `flipphone_logo.riv`, state `milestoneResults`.
- **Badge:** **Session** — this session’s milestone only (e.g. “30m” for a 30-minute session).
- **Data:** `numberInputs`: `sessionSeconds` → drives badge shape/label via Rive converter (app mirrors legacy `totalSessionSeconds` on VM/SMI when the file still uses it).
- **Trigger:** **`showSessionBadge`**  
  Fire when the session result card appears so the state machine shows the session badge (recommended).  
  The app currently uses `levelUp` here too; you can either keep `levelUp` for both hero tier-cut and session complete, or use `showSessionBadge` only for session complete so Rive can differentiate (e.g. different animation).

---

### 5. User completes a session (no milestone)
- **View:** `SessionResultView` — card when session did not hit a milestone (e.g. 4 minutes).
- **Rive file:** `flipphone_logo.riv`, state `sessionResults`.
- **Badge:** None — duration text only.
- **Data:** `textInputs`: `sessionDuration`.
- **Trigger (optional):** **`sessionComplete`** — only if you want a state transition for “session done, no badge” (e.g. subtle logo motion).

---

### 6. Session result header logo
- **View:** `SessionResultView` — small logo at top.
- **Rive file:** `flipphone_logo.riv`, state `hero`.
- **Badge:** None.
- **Trigger:** None.

---

### 7. Active session (timer running)
- **View:** `ActiveSessionView`.
- **Rive file:** `flipphone_logo.riv`, state `sessionResults`.
- **Badge:** None — live `sessionDuration` text only.
- **Trigger:** None.

---

### 8. Toolbar logo
- **View:** `FocusTrackingView` — toolbar.
- **Rive file:** `flipphone_logo.riv`, state `hero`.
- **Badge:** None.
- **Trigger:** None.

---

## Trigger names to add in Rive (state machine)

Create these as **trigger** inputs in your Rive state machine and wire transitions as needed:

| Trigger name | When the app fires it | Suggested use in Rive |
|--------------|------------------------|------------------------|
| **`showCumulativeBadge`** | When hero (main) screen appears with cumulative data | Transition to state that shows cumulative badge (today’s tier). |
| **`levelUp`** | Hero tier-cut + currently also on session result milestone | Tier-cut animation (outgoing → incoming badge). Optionally reuse for session milestone or split (see below). |
| **`showSessionBadge`** | When session result card appears with a milestone | Transition to state that shows session badge only. |
| **`splashStart`** | When splash view appears (optional) | Start splash animation if needed. |
| **`sessionComplete`** | When session result shows with no milestone (optional) | “Session done, no badge” transition if desired. |

---

## Optional: split hero vs session “level up”

- **Current:** App uses `levelUp` for both (a) hero tier-cut and (b) session result milestone.
- **If you want different animations:**  
  - Keep **`levelUp`** only for hero tier-cut (FocusTrackingView).  
  - Use **`showSessionBadge`** for session complete (SessionResultView) and in Rive drive the “session badge appear” animation from that trigger.

---

## App-side wiring (reference)

- **Hero screen, show cumulative badge on load:**  
  In `FocusTrackingView`, `heroDailyBadgeRiveView` uses `showCumulativeBadge` when not in post-session animation. During post-session animation, burst triggers are `nil` except for one-shot `showCumulativeBadge` at sequence start and `levelUp` (or `showCumulativeBadge` if there was no prior tier) on each tier cut — see `heroBadgeBurstTriggers` / `runMilestoneAnimation`.
- **Session result, show session badge:**  
  In `SessionResultView`, for the milestone result card, set `triggerInputs: ["showSessionBadge"]` (or keep `["levelUp"]` if you keep a single trigger for both).

Once these triggers exist in Rive and the app passes them in `triggerInputs`, the right badge can appear for “hero load” (cumulative) and “session complete” (session) as intended.

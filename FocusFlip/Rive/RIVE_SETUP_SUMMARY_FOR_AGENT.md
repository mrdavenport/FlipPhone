# Rive File Setup Summary (for Rive Agent)

Use this summary to configure `flipphone_hero.riv` and `flipphone_logo.riv` so they match the iOS app’s data binding and triggers.

---

## 1. View Model name

- **Name the data-binding View Model: `Hero`** (not "View Model 1" or "ViewModel1").
- The app resolves the view model by trying, in order: `"Hero"`, `"View Model 1"`, `"ViewModel1"`.

---

## 2. Badge shapes (order 0 → 6)

Badge shapes are **sequential by duration tier**. Use these **exact names** in the Rive file:

| Index | Shape name      | Duration tier        | Notes                    |
|-------|------------------|----------------------|--------------------------|
| 0     | badge-shape-0   | 5m only              | No badge in hero/session |
| 1     | badge-shape-1   | 10m, 15m             |                          |
| 2     | badge-shape-2   | 20m, 30m             |                          |
| 3     | badge-shape-3   | 40m, 50m             |                          |
| 4     | badge-shape-4   | 1hr, 2hr, 3hr        |                          |
| 5     | badge-shape-5   | 4hr, 5hr, 6hr        |                          |
| 6     | badge-shape-6   | 7hr through 24hr+    |                          |

- **5m does not show a badge** in the hero or on session completion (progress/streak only). Index 0 = “no badge” for those flows.
- Important: the app can support either (A) **0–6 index** selection or (B) **old selector codes** (5, 10, 15 … 2400). Your current Rive setup is using **old selector codes** (see below). Don’t wire to 0–6 unless you also update the Rive logic to expect 0–6.

---

## 3. Session seconds → badge selector (converter)

- **Input:** `sessionSeconds` (this session’s duration in seconds), from the View Model.
- **Output:** A badge selector number that your Rive state machine uses to choose a badge.

### Current (Rive expects old selector codes)

- `0–599` → **0** (no badge, including 5m)
- `600–899` → **10**
- `900–1199` → **15**
- `1200–1799` → **20**
- `1800–2399` → **30**
- `2400–2999` → **40**
- `3000–3599` → **50**
- `3600–7199` → **100**
- `7200–10799` → **200**
- … continuing by hour: **300, 400, …, 2400** (24hr+ caps at 2400)

- Add a **Converter** script in Rive: Number input (`sessionSeconds`), Number output (old selector codes above).
- Bind the converter output to the badge selector input your state machine uses.
- The project’s `session_seconds_to_badge_shape.lua` is restored to output these old selector codes (with 0 under 10m).

---

## 4. Triggers (state machine)

The app fires these **trigger** inputs at specific times. Add them to your state machine and wire transitions as needed:

| Trigger name           | When the app fires it                         | Suggested use in Rive                          |
|------------------------|-----------------------------------------------|------------------------------------------------|
| **splashStart**        | When the splash screen appears                | Start splash animation / entry state           |
| **showCumulativeBadge**| When the hero (main) screen shows its badge   | Show cumulative badge (today’s tier)           |
| **levelUp**            | When the user crosses a new tier (hero)       | Animate outgoing → incoming badge (tier cut)   |
| **showSessionBadge**   | When the session result card shows a milestone| Show session badge (this session’s milestone)   |
| **sessionComplete**    | When the session result shows with no milestone | “Session done, no badge” transition          |

- **Hero screen:** First appearance uses **showCumulativeBadge**; tier changes use **levelUp**.
- **Session result:** Milestone sessions use **showSessionBadge**; non-milestone (e.g. under 10m) use **sessionComplete**.

---

## 5. Number inputs (Hero View Model)

The app sends these **number** properties to the **Hero** View Model. Ensure the View Model has properties with these **exact names** (or the app will log “not found”):

**For hero / cumulative (daily total):**

- `cumulativeSeconds` — Today’s total focus time in seconds. On a **hero tier-cut** (`levelUp`), the app sends the **incoming** tier’s lower bound (same as `cumulativeToTierSeconds`) so it stays aligned with TT; do **not** use the bar’s in-flight total there. Bind the **outgoing** numeric label to `cumulativeFromTierSeconds` at your first event so it matches FT.
- `cumulativeFromTierSeconds` — Start of the tier for the **current** cumulative badge (`milestone.seconds`). On a **hero tier-cut frame**, the **outgoing** milestone’s `seconds` (FT).
- `cumulativeToTierSeconds` — Normally: start of the **next** tier after `milestone` (`nextMilestoneAfter`). On a **hero tier-cut frame**: **incoming** milestone’s `seconds` (TT).
- `sessionSeconds` — Usually **0** on the hero. DEBUG: optional A/B — Animation Debug sheet toggle “Hero sessionSeconds when animating” sends the last completed session’s duration while the post-session tier animation runs.

**For session completion (per-session):**

- `sessionSeconds` — This session’s duration in seconds (drives the session badge converter). The app also mirrors legacy VM/SMI names (`totalSessionSeconds`, `sessionDuration`) when present in the `.riv`.

---

## 6. Color inputs

- **themeColor** — Category/theme color (SwiftUI `Color` → app passes as needed).
- **badgeColor** — Used where the badge is tinted (e.g. hero badge, session result).

---

## 7. Files and states (reference)

- **flipphone_hero.riv:** Splash (`splash`), hero with stars (`hero-stars`), hero animation artboard.
- **flipphone_logo.riv:** Hero logo state (`hero`), session result no-milestone (`sessionResults`), session result with milestone (`milestoneResults`). Badge selection for session result is driven by `sessionSeconds` → converter → selector code.

---

## 8. Checklist for Rive

- [ ] View Model named **Hero**.
- [ ] Number properties on Hero: `cumulativeSeconds`, `cumulativeFromTierSeconds`, `cumulativeToTierSeconds`, `sessionSeconds` (hero often 0); session result card: `sessionSeconds` = session duration.
- [ ] Badge shapes named **badge-shape-0** through **badge-shape-6** (0 = no badge for 5m).
- [ ] Converter: `sessionSeconds` (seconds) → output selector code (currently old codes like 10/15/…/2400); bind output to badge selection.
- [ ] Trigger inputs: **splashStart**, **showCumulativeBadge**, **levelUp**, **showSessionBadge**, **sessionComplete**; wire to the correct state transitions.
- [ ] Color inputs: **themeColor**, **badgeColor** where needed.

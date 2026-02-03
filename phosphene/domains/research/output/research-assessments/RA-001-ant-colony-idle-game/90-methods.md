ID: RA-001
Title: Ant Colony Idle Game — Methods
Status: Draft
Updated: 2026-01-09
Dependencies: 
Owner: 

## C) Research intent + method (web) + source profile + bias notes

Checklist:
- Research intent (what decision(s) this supports)
- Method(s) used (web search, competitive scan, doc triangulation, desk research)
- Source profile (types + counts): docs, blogs, analyst notes, forums, reviews, filings, OSS repos
- Date range and freshness
- Bias notes (selection bias, survivorship, availability)
- Confidence grading approach (how you assigned C1–C3)

Intent:
- Determine whether an ant-colony “pseudo-idle” simulation has credible demand + monetization paths, and whether ChatGPT Apps is a plausible distribution wedge.

Method (web-only):
- Desk research + competitive scan (market products, portals, app stores, Steam)
- Forum/review mining for monetization sentiment and UX failure modes
- Lightweight triangulation: combine at least one “hard” signal (store metrics / published stats) with qualitative signals where possible
- Synthesize into: reference solutions → competitive landscape → pitch set → segment/persona hypotheses

Source profile (representative):
- App store listings + reviews (`play.google.com`)
- Steam pages (`store.steampowered.com`)
- Blogs/industry notes (`xsolla.com`, `blog.founders.illinois.edu`)
- Forums/social (`reddit.com`, `steamcommunity.com`)
- Platform announcements (`openai.com`) and secondary commentary (`medium.com`, `synergylabs.co`)
- OSS/academic demos (`github.com`, `discourse.threejs.org`)

Date range:
- Research assembled January 2026 (see `Updated:` fields). Platform-roadmap items are time-sensitive.

Bias notes:
- Availability bias (English web + discoverable sources)
- Survivorship bias (successful games have more visible metrics)
- Forum selection bias (loud minority; over-index on negative monetization sentiment)

Confidence grading approach:
- C3: triangulated and/or backed by store metrics or multiple aligned sources
- C2: plausible but incomplete; meaningful uncertainty remains
- C1: speculative; requires direct validation/prototype telemetry

## C.1) Research log (queries + source trail)

Checklist:
- Search queries used (and why)
- “Source trail” notes (how you followed references)
- What you deliberately ignored (and why)

| Timestamp | Query / path | What you were testing | Sources opened |
|---|---|---|---|
| 2026-01-08 | "idle ants downloads" | Is there mass-market demand for ant idle theme? | `play.google.com` |
| 2026-01-08 | "ant colony simulation game steam" | Are there “serious” ant sims and how are they received? | `store.steampowered.com`, `steamcommunity.com` |
| 2026-01-08 | "idle game monetization ads vs iap" | What monetization patterns are standard and what fails? | `xsolla.com`, `blog.founders.illinois.edu`, `reddit.com` |
| 2026-01-08 | "ChatGPT Apps SDK in-app purchases" | Is ChatGPT a plausible new distribution wedge? | `openai.com`, `synergylabs.co`, `medium.com` |
| 2026-01-08 | "GPU ant colony simulation pheromone trails" | Is large-scale ant sim technically plausible in GPU/web contexts? | `github.com`, `discourse.threejs.org` |

## I) Quantification anchors (value ranges)

Checklist:
- Unit of value (time saved, risk reduced, revenue, compliance)
- Measurable vs not measurable
- Time-to-value bands (ranges)
- Any quantified anchors (even rough ranges) + what would firm them up

Unit of value:
- Player value is time/attention + “progress felt” (offline progress, satisfying growth loop).
- Monetization value typically maps to time saved (boosts), content unlocked (species/maps), and cosmetics/support.

Measurable anchors (hypotheses):
- Retention targets (idle baseline): D1 > 40%, D7 > 15%, D30 > 5% (directional; validate by cohort).
- ARPDAU (directional): $0.05–$0.20 (depends on ads vs IAP mix; ChatGPT variant likely IAP-first).

Time-to-value bands:
- <1 minute: visible progress (first forage/hatch).
- <1 hour: meaningful new unlock (new ant type / chamber).
- 1–2 days: milestone (prestige/expansion) to refresh loop.

## J) Alternatives, switching costs, win/lose patterns

Checklist:
- Do-nothing baseline and inertia
- Switching costs (technical, org, procurement)
- Competitor comparisons (if any)
- Explicit “we lose when…” conditions

Do-nothing baseline:
- Players choose other idle games, other entertainment, or (for enthusiasts) premium sims. There is no urgent “pain”, so discovery + novelty must carry acquisition.

Switching costs:
- Low for casual idle (many free alternatives).
- Medium for sim enthusiasts once invested (time spent learning/optimizing + sunk cost).
- Potentially medium for ChatGPT users if it becomes part of their daily routine.

Win/lose patterns (hypotheses):
- We lose if first-session clarity/polish is weaker than mainstream idle.
- We lose if “realism” is only cosmetic (SEG-0002 churn).
- We lose if monetization feels coercive (SEG-0001 churn + bad reviews).
- We lose if distribution is unsolved (web-only without reach) (E-0007).

## K) Messaging ingredients (candidate; usable by `<product-marketing>`)

Checklist:
- Resonant phrases (quotes preferred)
- Taboo words / red-flag claims
- Narrative frames that worked
- Claim constraints (must/must-not)

Resonant frames (hypotheses):
- “Relax and watch your colony thrive” (ties to stress-free idle framing, E-0012).
- “Fair monetization: optional spend, no paywalls” (ties to E-0001).
- “Surprisingly deep: real ant behaviors” (SEG-0002 hook; ties to RS-0002/RS-0005 patterns).

Taboo / red-flag claims:
- “Guaranteed realistic” (too strong for web-only); prefer “inspired by real ant behaviors”.
- Any “loot box” / gambling-adjacent framing.

## L) Prioritized use-case catalog (mapped)

Checklist:
- Use cases mapped to personas + triggers
- Integration/data prerequisites
- Dependencies and constraints per use case

Use cases (initial):
- Casual: start + check-in loop (CPE-0001, trigger = downtime).
- Enthusiast: “run experiments” sandbox mode (CPE-0002, trigger = curiosity/strategy).
- ChatGPT: “ask why” explanations + natural-language controls (CPE-0003, trigger = in-chat novelty).

## M) Capability constraints + non-negotiables

Checklist:
- Latency / performance requirements
- Auditability / compliance requirements
- Data residency / security posture
- Support model expectations (if relevant)

Constraints (hypotheses):
- WebGPU availability/performance variability (notably iOS constraints) must be handled (degrade gracefully).
- Performance target: smooth at small colony; degrade without breaking play at large colony.
- If distributed via ChatGPT: adhere to platform review/policy; avoid unsafe data collection; provide clear privacy notes.

## N) Assumption register + gaps + validation plan

Checklist:
- Assumptions (explicit)
- Research gaps and unknowns
- Validation plan (next experiments)
- “Do not sell here” edge cases (explicit)

Assumptions:
- F2P monetization norms apply; fair/optional monetization matters (E-0001).
- Ant theme has enough top-of-funnel pull (E-0002).

Gaps/unknowns:
- True player retention/engagement with a “realistic” ant sim (prototype required).
- ChatGPT “games” adoption and discoverability (E-0009/E-0010 are directional only).

Validation plan (next):
- Prototype core loop (forage/hatch/upgrade) + one “realism” mechanic (pheromone trails) and test with target communities.
- A/B test onboarding complexity vs retention; test monetization offers for backlash signals.
- Evaluate distribution: web portals vs ChatGPT Apps; measure activation + revisit rate.

“Do not sell here” edge cases:
- Avoid promising scientific accuracy or educational outcomes without validation.
- Avoid competitive PvP or power-selling if later competition is introduced (E-0013).

## Appendix: Glossary + naming table

| Canonical term | Disallowed synonyms | Notes |
|---|---|---|
| pseudo-idle | “AFK-only” | Idle progression with intermittent meaningful decisions. |
| fair monetization | “pay-to-win” | Fair means no hard paywalls; purchases are optional/convenience/cosmetic. |
| WebGPU | “GPU everywhere” | Assume variability; must degrade gracefully. |


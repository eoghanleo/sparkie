ID: RA-001
Title: Ant Colony Idle Game — Hypotheses (segments/personas/pains/gains)
Status: Draft
Updated: 2026-01-09
Dependencies: 
Owner: 

## D) Segmentation prioritization logic

Checklist:
- Prioritization logic (scoring or narrative)
- Buying-center dynamics by segment
- Deprioritized segments + rationale
- Explicit out-of-scope segments

Prioritization narrative (web-only hypothesis):
- We prioritize **SEG-0001 (Casual Idle Gamers)** for first-run UX (fast time-to-value, clarity, delight).
- We keep **SEG-0002 (Simulation/Strategy Enthusiasts)** by layering optional depth (realistic behaviors, strategy controls) without gating the casual experience.
- We treat **SEG-0003 (ChatGPT Power-Users / Edutainment Seekers)** as a **distribution + packaging wedge** (not a separate product at first): same core sim, augmented with AI explanation and in-chat invocation.

Buying-center dynamics:
- Primary buyer is the player. For minors, parents act as gatekeepers for IAP (safety + spend controls).
- For SEG-0003, the platform (OpenAI) is a gatekeeper: app review + discovery can dominate early adoption.

Deprioritized / out-of-scope segments:
- Hardcore competitive gamers (PvP/esports): misfit for idle/sim pacing.
- Pure match-3 casual players with no idle/sim interest: not worth concept dilution.
- Institutional educational buyers (district/procurement): B2B licensing is out of scope.
- Crypto/NFT/web3 gamers: out of scope (audience + backlash risk).

## E) Core workflows (3–7)

Checklist:
- 3–7 workflows only (keep sharp)
- Each workflow written as: trigger → steps → outcome
- Identify who performs each step (role tags)
- Identify integration/data prerequisites where relevant

Workflows (hypotheses; distilled from raw):
- **W1: Start new colony (onboarding)**: trigger → start new colony → choose defaults (or species/environment) → guided first forage/hatch → outcome: “I get it” + first win.
- **W2: Idle check-in loop**: trigger → return after hours → offline summary → spend resources on upgrades/expansion → outcome: meaningful progress in <5 minutes (SEG-0001).
- **W3: Challenge event**: trigger → predator/weather event → deploy ants / spend item → outcome: short spike of agency + renewed goals (avoid punitive fail states).
- **W4: Meta-progression (expansion/prestige)**: trigger → milestone reached → unlock new territory / evolve → outcome: refreshed goals + long-term retention.
- **W5: In-chat IAP (ChatGPT variant)**: trigger → intent to buy → in-chat checkout → immediate benefit → outcome: low-friction conversion (E-0010).

## F) Ranked jobs / pains / gains per segment

Checklist:
- Per segment: ranked JTBD, pains, gains
- Severity + frequency per pain (1–5)
- Success metrics (how they measure “done”)
- Inertia sources (why they don’t change)

SEG-0001 (Casual Idle) — hypothesis summary:
- JTBD: fill downtime; feel progress without stress; enjoy a quirky theme.
- Top pains: P-0001 (monetization pressure, sev 5 / freq 4, E-0001), P-0002 (repetition, sev 4 / freq 5), P-0003 (overwhelm, sev 3 / freq 2, E-0003).
- Top gains: G-0001 (offline progress), G-0002 (fair optional spend, E-0001), G-0003 (delightful visuals/theme).
- Success metrics: D1/D7 retention; offline earnings used; store reviews mentioning “fair” / “relaxing” (E-0012).

SEG-0002 (Sim/Strategy) — hypothesis summary:
- JTBD: explore a complex system; optimize; learn/observe believable behaviors.
- Top pains: P-0004 (lack of depth, sev 5), P-0005 (F2P breaks realism, sev 4), P-0006 (shallow reskin, sev 5).
- Top gains: G-0004 (authentic emergent sim), G-0005 (meaningful decisions, E-0005), G-0006 (accessible depth).
- Success metrics: D30 retention for this cohort; engagement with advanced controls/info; community discussion volume.

SEG-0003 (ChatGPT power-users) — hypothesis summary:
- JTBD: quick integrated entertainment; learn through asking; avoid context switching.
- Top pains: P-0008 (context switching, E-0009), P-0009 (trust/safety).
- Top gains: G-0007 (in-chat launch, E-0009), G-0008 (AI explanations), G-0009 (quick play).
- Success metrics: activation from ChatGPT directory; repeat usage; question/answer interactions.

## G) Candidate persona dossiers (CPE; hypotheses)

Checklist:
- Candidate persona stable ID (CPE-####) and segment stable ID (SEG-####)
- Objections, decision criteria, terminology/lexicon
- Evidence IDs attached to each major claim

Canonical personas (PER-####) are authoritative in `<product-marketing>` only.
In `<research>`, we keep 1:1 proposals as Candidate Personas under `60-candidate-personas/`.

Candidate persona files (authoritative in this bundle):
- CPE-0001 — “Idle Ingrid” (SEG-0001)
- CPE-0002 — “Strategic Sam” (SEG-0002)
- CPE-0003 — “AI Alex” (SEG-0003)

## Appendix: Canonical segment table (stable IDs)

| SegmentID | Segment name | Rank | In-scope? | Buyer map notes | Top pains (IDs) | Top gains (IDs) |
|---|---|---:|---|---|---|---|
| SEG-0001 | Casual Idle Gamers | 1 | Yes | End-user; influenced by reviews/short-form video | P-0001, P-0002, P-0003 | G-0001, G-0002, G-0003 |
| SEG-0002 | Simulation/Strategy Enthusiasts | 2 | Yes | End-user; influenced by community/forums/reviews | P-0004, P-0005, P-0006 | G-0004, G-0005, G-0006 |
| SEG-0003 | ChatGPT Power-Users / Edutainment | 3 | Yes | End-user + platform gatekeeper | P-0007, P-0008, P-0009 | G-0007, G-0008, G-0009 |

## Appendix: Candidate persona index (stable IDs)

| CandidatePersonaID | Persona name | SegmentID | Role tags | Rank pains | Rank gains | Objections (top) |
|---|---|---|---|---|---|---|
| CPE-0001 | Idle Ingrid | SEG-0001 | end-user | P-0001, P-0002, P-0003 | G-0001, G-0002, G-0003 | “gross ants”, “too complex”, “pay-to-win” |
| CPE-0002 | Strategic Sam | SEG-0002 | end-user | P-0004, P-0005, P-0006 | G-0004, G-0005, G-0006 | “shallow idle”, “F2P catch”, “fake realism” |
| CPE-0003 | AI Alex | SEG-0003 | end-user | P-0008, P-0009 | G-0007, G-0008, G-0009 | “gimmick”, “privacy”, “state loss” |


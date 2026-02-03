## AGENTS.md (repo root)

This repo is a **PHOSPHENE framework sandbox** and is actively evolving.

### CRITICAL — language policy

ALL CODE NOT IN THE .GITHUB WORKFLOWS SECTION MUST USE BASH AND ONLY BASH. No other libraries.

Code in the workflows section is designed to run in github actions and MAY use scripts supported only by DEFAULT in that environment.

Ensure you ADHERE to languages already in use wherever possible.

### CRITICAL — instrument specs are mandatory

The instrument specifications under `WIP/schematics/instrument_spec/` are **MUST-level** requirements. These specs define the canonical, cross-domain behavior for every instrument and take priority over local convention. If an implementation diverges, the spec is wrong or the code is wrong — resolve the mismatch before proceeding.

### Domain status (authoritative)

Domains without DONE receipt emit scripts are **not in development** unless explicitly listed below; they must not be run in live flows unless explicitly authorized.

- **Active (bus + emit receipts)**
  - `<product-marketing>` (beryl)
  - `<product-management>` (cerulean)
- **In development**
  - `<research>` (viridian)
- **Todo**
  - `<ideation>` (viridian)
  - `<product-strategy>` (beryl)
  - `<feature-management>` (cerulean)
  - `<scrum-management>` (amaranth)
  - `<test-management>` (cadmium)
  - `<retrospective>` (chartreuse)

### Operational assumptions (v1 topology)

- **Issues are untrusted and public-facing**: assume any content in Issues/Comments may be visible to summoned agents anyway. We do not attempt to “sanitize” Issue text as a security boundary.
- **Issue boundary**: only **Hoppers** and **Scribes** interact with GitHub Issues directly (read/write).
- **Repo write boundary**: Gantries and Apparatus may write to the repo, but **Gantries must be constrained to an explicit allowlist of signal-bus paths only**.
- **Everything is bus**: orchestration MUST be driven by bus changes; issue/comment triggers are non-canonical.
- **Schematics-first**: before changing workflows or core mechanics, **write/update a schematic** under `WIP/schematics/` (Markdown + Mermaid). Use `instrument_spec/` for instrument behavior and `domain_subflows/<color>/<domain>/` for orchestration. We use schematics to stay clear on the system *before* we start code builds.
- **WIP placement**: ALL working ON Phosphene materials and in-progress notes must live under `WIP/`.

If you are an agent doing work in this repo:
- Read the canonical agent entrypoint: `phosphene/AGENTS.md`
- Skills are mandatory and live in: `.codex/skills/phosphene/**`

This root file is intentionally lightweight; domain and workflow contracts live under `phosphene/`.

### Phosphene brand colours

- 1. Phosphene (pink pearlescent on smoky plum)
  - Overall palette intent: iridescent fuchsia-magenta lettering with pale pearl core and subtle RGB fringe glow on a dark aubergine haze.
  - Background
    - Deep aubergine-black: <span style="background-color:#140B12; color:#140B12; padding: 0 8px;">&nbsp;</span> `#140B12`
    - Smoky plum midtones: <span style="background-color:#2A1524; color:#2A1524; padding: 0 8px;">&nbsp;</span> `#2A1524`
    - Violet haze lift: <span style="background-color:#3B1D33; color:#3B1D33; padding: 0 8px;">&nbsp;</span> `#3B1D33`
  - Typography (fill + bevel)
    - Pearl highlight (inner face): <span style="background-color:#F4E3F1; color:#F4E3F1; padding: 0 8px;">&nbsp;</span> `#F4E3F1`
    - Warm pink face: <span style="background-color:#D97AAE; color:#D97AAE; padding: 0 8px;">&nbsp;</span> `#D97AAE`
    - Hot magenta edge: <span style="background-color:#C12C7D; color:#C12C7D; padding: 0 8px;">&nbsp;</span> `#C12C7D`
    - Deep wine shadow: <span style="background-color:#5A1837; color:#5A1837; padding: 0 8px;">&nbsp;</span> `#5A1837`
  - Glow / chromatic aberration accents
    - Neon pink glow: <span style="background-color:#FF4FB3; color:#FF4FB3; padding: 0 8px;">&nbsp;</span> `#FF4FB3`
    - Lime fringe: <span style="background-color:#9CFF3A; color:#9CFF3A; padding: 0 8px;">&nbsp;</span> `#9CFF3A`
    - Cyan fringe: <span style="background-color:#4FE8FF; color:#4FE8FF; padding: 0 8px;">&nbsp;</span> `#4FE8FF`
  - Suggested gradient (letter face): `#F4E3F1` → `#D97AAE` → `#C12C7D` → `#5A1837`

- 2. Viridian (neon green on dark forest smoke)
  - Overall palette intent: viridian/emerald neon letters with yellow-green rim light against a deep green-black fog.
  - Background
    - Forest black: <span style="background-color:#060B08; color:#060B08; padding: 0 8px;">&nbsp;</span> `#060B08`
    - Deep pine: <span style="background-color:#0E1A12; color:#0E1A12; padding: 0 8px;">&nbsp;</span> `#0E1A12`
    - Smoked green midtone: <span style="background-color:#1A2C1F; color:#1A2C1F; padding: 0 8px;">&nbsp;</span> `#1A2C1F`
  - Typography (fill + bevel)
    - Bright mint highlight: <span style="background-color:#B9FFD6; color:#B9FFD6; padding: 0 8px;">&nbsp;</span> `#B9FFD6`
    - Emerald face: <span style="background-color:#26C77D; color:#26C77D; padding: 0 8px;">&nbsp;</span> `#26C77D`
    - Viridian core: <span style="background-color:#0E8B5B; color:#0E8B5B; padding: 0 8px;">&nbsp;</span> `#0E8B5B`
    - Deep teal shadow: <span style="background-color:#063C2E; color:#063C2E; padding: 0 8px;">&nbsp;</span> `#063C2E`
  - Rim light / glow
    - Yellow-green rim: <span style="background-color:#D2FF52; color:#D2FF52; padding: 0 8px;">&nbsp;</span> `#D2FF52`
    - Aqua edge sparkle: <span style="background-color:#66FFD8; color:#66FFD8; padding: 0 8px;">&nbsp;</span> `#66FFD8`
  - Suggested gradient (letter face): `#B9FFD6` → `#26C77D` → `#0E8B5B` → `#063C2E`

- 3. Beryl (teal glass on faceted gemstone)
  - Overall palette intent: cool aqua-teal glass lettering over a crystalline, faceted teal/blue-green background.
  - Background (gem facets)
    - Deep blue-green: <span style="background-color:#082427; color:#082427; padding: 0 8px;">&nbsp;</span> `#082427`
    - Petrol teal: <span style="background-color:#0F3E41; color:#0F3E41; padding: 0 8px;">&nbsp;</span> `#0F3E41`
    - Facet cyan reflections: <span style="background-color:#19A9A8; color:#19A9A8; padding: 0 8px;">&nbsp;</span> `#19A9A8`
    - Dark slate-teal shadows: <span style="background-color:#06181A; color:#06181A; padding: 0 8px;">&nbsp;</span> `#06181A`
  - Typography (fill + bevel)
    - Ice-aqua highlight: <span style="background-color:#BFFBFF; color:#BFFBFF; padding: 0 8px;">&nbsp;</span> `#BFFBFF`
    - Aqua face: <span style="background-color:#4DE3DF; color:#4DE3DF; padding: 0 8px;">&nbsp;</span> `#4DE3DF`
    - Beryl teal: <span style="background-color:#159D9B; color:#159D9B; padding: 0 8px;">&nbsp;</span> `#159D9B`
    - Deep teal shadow: <span style="background-color:#0A4F55; color:#0A4F55; padding: 0 8px;">&nbsp;</span> `#0A4F55`
  - Glow
    - Soft cyan glow: <span style="background-color:#66FFF2; color:#66FFF2; padding: 0 8px;">&nbsp;</span> `#66FFF2`
  - Suggested gradient (letter face): `#BFFBFF` → `#4DE3DF` → `#159D9B` → `#0A4F55`

- 4. Cerulean (underwater blue on rippled sea floor)
  - Overall palette intent: cyan-to-cerulean metallic letters with cool blue shadows, set over a dark aquatic scene with caustic light patterns.
  - Background (water + caustics)
    - Abyssal blue-black: <span style="background-color:#041218; color:#041218; padding: 0 8px;">&nbsp;</span> `#041218`
    - Deep ocean teal: <span style="background-color:#06303A; color:#06303A; padding: 0 8px;">&nbsp;</span> `#06303A`
    - Caustic highlight lines: <span style="background-color:#2C7C86; color:#2C7C86; padding: 0 8px;">&nbsp;</span> `#2C7C86`
    - Silted shadow blue: <span style="background-color:#061A25; color:#061A25; padding: 0 8px;">&nbsp;</span> `#061A25`
  - Typography (fill + bevel)
    - Pale aqua highlight: <span style="background-color:#C9FBFF; color:#C9FBFF; padding: 0 8px;">&nbsp;</span> `#C9FBFF`
    - Bright cyan face: <span style="background-color:#41E4F6; color:#41E4F6; padding: 0 8px;">&nbsp;</span> `#41E4F6`
    - Cerulean mid: <span style="background-color:#1E86C7; color:#1E86C7; padding: 0 8px;">&nbsp;</span> `#1E86C7`
    - Indigo-blue shadow: <span style="background-color:#123D7A; color:#123D7A; padding: 0 8px;">&nbsp;</span> `#123D7A`
  - Glow
    - Cyan glow: <span style="background-color:#5BFAFF; color:#5BFAFF; padding: 0 8px;">&nbsp;</span> `#5BFAFF`
    - Cool blue edge: <span style="background-color:#2FA6FF; color:#2FA6FF; padding: 0 8px;">&nbsp;</span> `#2FA6FF`
  - Suggested gradient (letter face): `#C9FBFF` → `#41E4F6` → `#1E86C7` → `#123D7A`

- 5. Amaranth (cosmic magenta with cyan nebula)
  - Overall palette intent: amaranth/purple neon typography over a space field that shifts from hot magenta to electric cyan, with star-white sparkles.
  - Background (nebula + space)
    - Space black: <span style="background-color:#03020A; color:#03020A; padding: 0 8px;">&nbsp;</span> `#03020A`
    - Deep violet: <span style="background-color:#1A0B2E; color:#1A0B2E; padding: 0 8px;">&nbsp;</span> `#1A0B2E`
    - Nebula magenta: <span style="background-color:#B10B6B; color:#B10B6B; padding: 0 8px;">&nbsp;</span> `#B10B6B`
    - Nebula cyan: <span style="background-color:#14C7D6; color:#14C7D6; padding: 0 8px;">&nbsp;</span> `#14C7D6`
    - Star white: <span style="background-color:#F7FBFF; color:#F7FBFF; padding: 0 8px;">&nbsp;</span> `#F7FBFF`
  - Typography (fill + bevel)
    - Soft lavender highlight: <span style="background-color:#EAD9FF; color:#EAD9FF; padding: 0 8px;">&nbsp;</span> `#EAD9FF`
    - Neon fuchsia face: <span style="background-color:#E62E9D; color:#E62E9D; padding: 0 8px;">&nbsp;</span> `#E62E9D`
    - Amaranth purple: <span style="background-color:#8E2BC9; color:#8E2BC9; padding: 0 8px;">&nbsp;</span> `#8E2BC9`
    - Deep plum shadow: <span style="background-color:#2B0D3A; color:#2B0D3A; padding: 0 8px;">&nbsp;</span> `#2B0D3A`
  - Glow accents
    - Pink glow: <span style="background-color:#FF4AC0; color:#FF4AC0; padding: 0 8px;">&nbsp;</span> `#FF4AC0`
    - Cyan counter-glow: <span style="background-color:#4FF4FF; color:#4FF4FF; padding: 0 8px;">&nbsp;</span> `#4FF4FF`
  - Suggested gradient (letter face): `#EAD9FF` → `#E62E9D` → `#8E2BC9` → `#2B0D3A`

- 6. Cadmium (hot orange-gold with ember smoke)
  - Overall palette intent: cadmium orange lettering with gold highlights and subtle greenish-gold undertones, set on a smoky, ember-filled warm background.
  - Background (smoke + embers)
    - Charred brown-black: <span style="background-color:#140A05; color:#140A05; padding: 0 8px;">&nbsp;</span> `#140A05`
    - Smoky umber: <span style="background-color:#3A1E0C; color:#3A1E0C; padding: 0 8px;">&nbsp;</span> `#3A1E0C`
    - Warm ochre haze: <span style="background-color:#9B6A1D; color:#9B6A1D; padding: 0 8px;">&nbsp;</span> `#9B6A1D`
    - Ember specks: <span style="background-color:#FF7A1A; color:#FF7A1A; padding: 0 8px;">&nbsp;</span> `#FF7A1A`
  - Typography (fill + bevel)
    - Gold highlight: <span style="background-color:#FFE2A6; color:#FFE2A6; padding: 0 8px;">&nbsp;</span> `#FFE2A6`
    - Cadmium orange face: <span style="background-color:#FF7A1C; color:#FF7A1C; padding: 0 8px;">&nbsp;</span> `#FF7A1C`
    - Deep orange-red: <span style="background-color:#D14800; color:#D14800; padding: 0 8px;">&nbsp;</span> `#D14800`
    - Burnt shadow: <span style="background-color:#5A1A06; color:#5A1A06; padding: 0 8px;">&nbsp;</span> `#5A1A06`
    - Subtle green-gold undertone (lowlights): <span style="background-color:#8A8B2D; color:#8A8B2D; padding: 0 8px;">&nbsp;</span> `#8A8B2D`
  - Glow
    - Orange glow: <span style="background-color:#FF9B3A; color:#FF9B3A; padding: 0 8px;">&nbsp;</span> `#FF9B3A`
  - Suggested gradient (letter face): `#FFE2A6` → `#FF7A1C` → `#D14800` → `#5A1A06`

- 7. Chartreuse (acid yellow-green neon on dark bubbling green)
  - Overall palette intent: bright chartreuse neon letters with yellow highlights and deep green shadows over a near-black green background with bubble-like bokeh.
  - Background
    - Green-black: <span style="background-color:#040705; color:#040705; padding: 0 8px;">&nbsp;</span> `#040705`
    - Deep olive: <span style="background-color:#142112; color:#142112; padding: 0 8px;">&nbsp;</span> `#142112`
    - Murky green haze: <span style="background-color:#1F3520; color:#1F3520; padding: 0 8px;">&nbsp;</span> `#1F3520`
    - Bubble highlights (soft): <span style="background-color:#6E7B72; color:#6E7B72; padding: 0 8px;">&nbsp;</span> `#6E7B72`
  - Typography (fill + bevel)
    - Lemon highlight: <span style="background-color:#FFF6A8; color:#FFF6A8; padding: 0 8px;">&nbsp;</span> `#FFF6A8`
    - Chartreuse face: <span style="background-color:#C7FF3A; color:#C7FF3A; padding: 0 8px;">&nbsp;</span> `#C7FF3A`
    - Yellow-green mid: <span style="background-color:#9AE51B; color:#9AE51B; padding: 0 8px;">&nbsp;</span> `#9AE51B`
    - Deep green shadow: <span style="background-color:#1F6A2F; color:#1F6A2F; padding: 0 8px;">&nbsp;</span> `#1F6A2F`
    - Dark olive recess: <span style="background-color:#0E2B14; color:#0E2B14; padding: 0 8px;">&nbsp;</span> `#0E2B14`
  - Glow
    - Acid glow: <span style="background-color:#D7FF4F; color:#D7FF4F; padding: 0 8px;">&nbsp;</span> `#D7FF4F`
    - Warm rim tint: <span style="background-color:#FFC94A; color:#FFC94A; padding: 0 8px;">&nbsp;</span> `#FFC94A`
  - Suggested gradient (letter face): `#FFF6A8` → `#C7FF3A` → `#9AE51B` → `#1F6A2F`

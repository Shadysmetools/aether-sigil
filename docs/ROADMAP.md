# Aether Sigil: roadmap

**Game:** Aether Sigil: Chronicles of the Prism Realms (working title; see `docs/IP-CHECK.md`). Original anime tactical monster-board game for iOS and Android, Godot 4.7.2.
**Owner:** Shady (solo founder). **Repo:** https://github.com/Shadysmetools/aether-sigil (private). **Written:** 2026-10-21.
**Tracking:** each milestone below is a GitHub milestone, and each bullet is a GitHub issue with its own acceptance criteria.

## How "done" is proven

A milestone closes only when its evidence is attached to the milestone's close comment. Three kinds of evidence are used:

- **Tests:** `bash game/run_tests.sh` output, quoted as `N pass / M fail` per suite. M must be 0 **and** every suite must show `script_errors=0`, because Godot exits 0 even when a script fails to parse. Quote the commit hash with the counts. (The 69/12 counts in HANDOFF.md are from the earlier Emberwick hex prototype and are not a baseline for Aether Sigil.)
- **Recorded play video:** a screen recording of the named flow, linked from the close comment.
- **Device install:** a photo or screen recording of the build running on a physical phone (debug APK for M1-M4, store test track for M5, TestFlight for M6, the live store for M7).

## Milestones

### M1: Battle loop vertical slice

GitHub milestone: https://github.com/Shadysmetools/aether-sigil/milestone/1

**Done means:** Tower 1 (Verdant Spire, T01-L01..L10) is playable end to end on desktop and in a portrait phone-sized window: deploy a squad of 4, fight with initiative turns and terrain, and win or lose under the Player Sigil and multi-objective rules, through T01-L10.

**Evidence required:**
- `bash game/run_tests.sh` prints `N pass / 0 fail` for every suite **and** `script_errors=0` (Godot exits 0 on script errors, so the exit code alone proves nothing); the per-suite counts and the commit hash are pasted into the milestone close comment.
- A recorded play video (desktop, portrait 1080x1920 window) showing one full T01 stage won and one lost, with each action (Move/Attack/Skill/Defend/Wait) used at least once.
- An Android debug APK installed on one physical device that loads T01-L01 and finishes one turn (photo or screen recording).

**Issues:**
- [#1](https://github.com/Shadysmetools/aether-sigil/issues/1) 12x12 isometric grid with terrain: high ground, water, bridges, line-of-sight blockers (`area:engine`, `P1`)
- [#2](https://github.com/Shadysmetools/aether-sigil/issues/2) Initiative turn order and the five actions: Move, Attack, Skill, Defend, Wait (`area:engine`, `P1`)
- [#3](https://github.com/Shadysmetools/aether-sigil/issues/3) Capsule-node summoning and squad-of-4 deployment (`area:engine`, `P1`)
- [#4](https://github.com/Shadysmetools/aether-sigil/issues/4) Player Sigil, win/loss conditions and multi-objectives (`area:engine`, `P1`)
- [#5](https://github.com/Shadysmetools/aether-sigil/issues/5) Data-driven stage loader for Tower 1 (T01-L01..L10) (`area:engine`, `P1`)
- [#6](https://github.com/Shadysmetools/aether-sigil/issues/6) Enemy AI for Tower 1 opponents (`area:engine`, `P1`)
- [#7](https://github.com/Shadysmetools/aether-sigil/issues/7) Test gate: every suite reports N pass / 0 fail and script_errors=0 (`area:engine`, `P1`)
- [#8](https://github.com/Shadysmetools/aether-sigil/issues/8) Combat formulas and ability spec for the Tower 1 roster (`area:design`, `P1`)
- [#9](https://github.com/Shadysmetools/aether-sigil/issues/9) Portrait touch controls and battle HUD for phones (`area:mobile`, `P1`)

### M2: All 120 stages, progression and save

GitHub milestone: https://github.com/Shadysmetools/aether-sigil/milestone/2

**Done means:** All 12 towers x 10 stages load from the bible data with their special rules, weather, hazards and bosses. Progression unlocks towers in order, and the game saves and resumes.

**Evidence required:**
- `bash game/run_tests.sh` prints `N pass / 0 fail` for every suite **and** `script_errors=0` (Godot exits 0 on script errors, so the exit code alone proves nothing), including a data test that loads all 120 stage IDs and asserts each has a roster, a win condition and terrain.
- An AI-vs-AI simulation report covering all 120 stages (win rate per stage), committed under `docs/`.
- A recorded video: clear a stage, quit the app, relaunch, and progress is still there; the world map shows tower 2 unlocked.
- A device install (Android debug APK) on which a save from the previous build still loads (save-schema migration).

**Issues:**
- [#10](https://github.com/Shadysmetools/aether-sigil/issues/10) Load all 120 stages with per-stage special rules and win conditions (`area:engine`, `P1`)
- [#11](https://github.com/Shadysmetools/aether-sigil/issues/11) Weather, hazards and L10 boss phases (`area:engine`, `P2`)
- [#12](https://github.com/Shadysmetools/aether-sigil/issues/12) AI for all opponent styles plus a 120-stage difficulty simulation (`area:engine`, `area:design`, `P2`)
- [#13](https://github.com/Shadysmetools/aether-sigil/issues/13) Progression: tower unlocks, stage stars and rank badges (`area:engine`, `P1`)
- [#14](https://github.com/Shadysmetools/aether-sigil/issues/14) Save and load with a versioned schema (`area:engine`, `P1`)
- [#15](https://github.com/Shadysmetools/aether-sigil/issues/15) World map and tower progression screen (`area:engine`, `P2`)
- [#16](https://github.com/Shadysmetools/aether-sigil/issues/16) Reconcile champion names between the bible JSON and the stage CSV (`area:design`, `P1`)
- [#17](https://github.com/Shadysmetools/aether-sigil/issues/17) Hook the 486 dialogue lines to battle and story triggers (`area:design`, `P2`)

### M3: Meta: squad builder, evolution, fusion, Symbol, Prism Core

GitHub milestone: https://github.com/Shadysmetools/aether-sigil/milestone/3

**Done means:** The between-battle layer: choose a Symbol, build squads, evolve (3-4 stages), fuse, and equip Prism Core loadouts with set bonuses, all reflected in battle stats.

**Evidence required:**
- `bash game/run_tests.sh` prints `N pass / 0 fail` for every suite **and** `script_errors=0` (Godot exits 0 on script errors, so the exit code alone proves nothing), with unit tests for evolution, fusion and Prism Core set-bonus maths.
- A recorded video: pick a Symbol, build a squad, evolve one monster, fuse two, equip a Prism Core set, then win a battle where the changed stats are visible.
- A device install showing the meta screens usable one-handed in portrait.

**Issues:**
- [#18](https://github.com/Shadysmetools/aether-sigil/issues/18) Squad builder (`area:engine`, `P1`)
- [#19](https://github.com/Shadysmetools/aether-sigil/issues/19) Evolution (3-4 stages per line) (`area:engine`, `P1`)
- [#20](https://github.com/Shadysmetools/aether-sigil/issues/20) Fusion (`area:engine`, `P2`)
- [#21](https://github.com/Shadysmetools/aether-sigil/issues/21) Symbol choice: Nexus, Valor, Aegis, Orbital, Void (`area:engine`, `area:design`, `P1`)
- [#22](https://github.com/Shadysmetools/aether-sigil/issues/22) Prism Core loadout with set bonuses (`area:engine`, `area:design`, `P2`)
- [#23](https://github.com/Shadysmetools/aether-sigil/issues/23) Economy and drop tables: materials, capsules, rewards (`area:design`, `P2`)

### M4: Art pass: tiles, units, animation, VFX, audio

GitHub milestone: https://github.com/Shadysmetools/aether-sigil/milestone/4

**Done means:** Placeholder art is replaced with original, owned art for every asset that ships at launch, with a complete licence log.

**Evidence required:**
- `bash game/run_tests.sh` prints `N pass / 0 fail` for every suite **and** `script_errors=0` (Godot exits 0 on script errors, so the exit code alone proves nothing), plus a check that every texture path the game references exists (no missing-asset fallbacks).
- `THIRD_PARTY_NOTICES` lists every non-original asset with its licence; zero NC/ND/GPL/CC-BY-SA items (per RESEARCH-open-source.md).
- A recorded play video of one stage per tower (12 clips) with final tiles, animated units, VFX, music and SFX.
- A device install on a low-end Android phone holding 30 fps or better in battle (profiler screenshot).

**Issues:**
- [#24](https://github.com/Shadysmetools/aether-sigil/issues/24) Launch art scope: which monsters and champions need final art (`area:art`, `area:design`, `P1`)
- [#25](https://github.com/Shadysmetools/aether-sigil/issues/25) Original isometric tile sets for the 12 tower themes (`area:art`, `P1`)
- [#26](https://github.com/Shadysmetools/aether-sigil/issues/26) Unit sprites and animation rigs: idle, move, attack, skill, hit, faint (`area:art`, `P1`)
- [#27](https://github.com/Shadysmetools/aether-sigil/issues/27) VFX: summon, skills, Sigil and objectives (`area:art`, `P2`)
- [#28](https://github.com/Shadysmetools/aether-sigil/issues/28) Music and SFX with a licence log (`area:art`, `P2`)
- [#29](https://github.com/Shadysmetools/aether-sigil/issues/29) Redesign the capsule so it isn't a held capture ball (`area:art`, `area:legal`, `P1`)
- [#30](https://github.com/Shadysmetools/aether-sigil/issues/30) THIRD_PARTY_NOTICES and in-game credits (`area:legal`, `P2`)

### M5: Android closed test (12 testers x 14 days)

GitHub milestone: https://github.com/Shadysmetools/aether-sigil/milestone/5

**Done means:** The game passes Google Play's closed-testing gate for new personal developer accounts and is ready to apply for production access.

**Evidence required:**
- `bash game/run_tests.sh` prints `N pass / 0 fail` for every suite **and** `script_errors=0` (Godot exits 0 on script errors, so the exit code alone proves nothing) on the release build's commit.
- A signed release AAB built with Gradle and uploaded to a Play closed-testing track (Play Console screenshot).
- Play Console shows at least 12 testers opted in continuously for 14 days (screenshot of the testing dashboard).
- A device install from the Play test link on at least 2 different physical Android phones.
- A recorded play video of one full T01 stage played on the Play closed-test build.

**Issues:**
- [#31](https://github.com/Shadysmetools/aether-sigil/issues/31) Decide the final title and subtitle before the first store listing (`area:legal`, `P1`)
- [#32](https://github.com/Shadysmetools/aether-sigil/issues/32) Pick a permanent application ID and bundle ID (`area:mobile`, `P1`)
- [#33](https://github.com/Shadysmetools/aether-sigil/issues/33) Android release pipeline: JDK 17, SDK 36, release keystore, Gradle AAB (`area:mobile`, `P1`)
- [#34](https://github.com/Shadysmetools/aether-sigil/issues/34) Play Console setup and the 12-tester x 14-day closed test (`area:mobile`, `P1`)
- [#35](https://github.com/Shadysmetools/aether-sigil/issues/35) Low-end Android performance and battery pass (`area:mobile`, `P2`)

### M6: iOS TestFlight

GitHub milestone: https://github.com/Shadysmetools/aether-sigil/milestone/6

**Done means:** An iOS build made with Xcode 26+ is on TestFlight and playable by external testers.

**Evidence required:**
- `bash game/run_tests.sh` prints `N pass / 0 fail` for every suite **and** `script_errors=0` (Godot exits 0 on script errors, so the exit code alone proves nothing) on the release build's commit.
- App Store Connect shows the build processed and available in TestFlight (screenshot), built with Xcode 26+ / iOS 26 SDK.
- A device install from TestFlight on a physical iPhone, with a recorded video of one full T01 stage.

**Issues:**
- [#36](https://github.com/Shadysmetools/aether-sigil/issues/36) iOS export and TestFlight build (`area:mobile`, `P1`)

### M7: Launch

GitHub milestone: https://github.com/Shadysmetools/aether-sigil/milestone/7

**Done means:** Public release on Google Play and the App Store with listings, privacy policy, age ratings, analytics and cosmetic IAP.

**Evidence required:**
- `bash game/run_tests.sh` prints `N pass / 0 fail` for every suite **and** `script_errors=0` (Godot exits 0 on script errors, so the exit code alone proves nothing) on the launch commit.
- Both store listings live (URLs recorded in the milestone close comment), with a privacy policy URL, the Play Data safety form and Apple privacy labels completed.
- IARC (Play) and Apple age ratings issued (screenshots).
- Sandbox IAP purchases succeed on both platforms (recorded video), and the analytics dashboard shows tutorial and stage funnel events from real devices.
- A device install from the live store listing on one physical Android phone and one physical iPhone (photo or recording).
- A lawyer has reviewed docs/IP-CHECK.md and the final title (sign-off noted in the milestone close comment).

**Issues:**
- [#37](https://github.com/Shadysmetools/aether-sigil/issues/37) Privacy policy, Play Data safety form and Apple privacy labels (`area:legal`, `P1`)
- [#38](https://github.com/Shadysmetools/aether-sigil/issues/38) Age ratings: IARC (Google Play) and Apple (`area:legal`, `P1`)
- [#39](https://github.com/Shadysmetools/aether-sigil/issues/39) Analytics: tutorial and stage funnels (`area:engine`, `P2`)
- [#40](https://github.com/Shadysmetools/aether-sigil/issues/40) Cosmetic IAP on both stores (no paid random draws at launch) (`area:mobile`, `area:legal`, `P2`)
- [#41](https://github.com/Shadysmetools/aether-sigil/issues/41) Store listings: screenshots, descriptions, feature graphic, trailer (`area:design`, `P2`)

### Ordering notes

- M1 to M3 are mostly sequential; M4 art can start as soon as the M4 launch-art scope issue is settled (it depends on the M2 champion-name decision).
- **The title must be settled before M5**, not at launch: a Play closed test needs a store listing, and the Android package name can't change after the first upload.
- Google's 12-testers-for-14-days gate applies to personal Play accounts created after 2023-11-13 (organisation accounts are exempt). Budget about 3 weeks for M5.
- M6 needs a Mac or cloud Mac running a current macOS: uploads have required Xcode 26+ since 2026-04-28, and there is no published godot-storekit2 build for Godot 4.7 yet.
- Minimum cash to ship both stores: $25 (Google, once) + $99/yr (Apple) = $124 in year one (RESEARCH-open-source.md section 5).

## Team roles

### Now (agents, directed by Shady)

| Area | Owner | Owns |
|---|---|---|
| Producer / IP review | Producer agent (this doc) | Roadmap, milestones, issues, `docs/IP-CHECK.md`, release checklists; area:legal triage |
| `area:engine` | Developer agent | Godot battle loop in `game/`, data loading, AI, save, meta systems, `game/run_tests.sh` |
| `area:design` | Design agent | Balance and ability docs in `docs/` (ABILITIES.md, BALANCE-REPORT.md), economy, difficulty sims, dialogue wiring spec |
| `area:art` | Art agent (placeholders only) + **Shady (finals)** | Placeholder art in `art/generated/`; final character art is drawn by Shady so it can be owned (HANDOFF.md) |
| `area:mobile` | Developer agent + Shady | Export presets, keystore, store consoles, device testing; Shady holds all store accounts and signing keys |
| `area:legal` | Shady + a lawyer | Final name decision, trademark filing, privacy policy, age ratings, store agreements |

### Later (human hires)

Rates are from section 7 of `RESEARCH-open-source.md` (sampled 2026-10-20). Freelancer.com profiles skew to lower-cost regions, so treat them as a **floor**; Upwork pages were unreachable (UNVERIFIED).

| Hire | When | What they'd do | Cited cost | Source |
|---|---|---|---|---|
| 2D creature / character illustrator | M4 (after the launch-art scope issue) | Help Shady scale final monster art (470 unique enemy monsters are referenced by the stage data, plus the player roster, evolutions and 12 champions), key art for store listings | $8-30/hr (Freelancer.com game-art profiles) | https://www.freelancer.com/hire/game-art |
| 2D animator | M4 | Idle/move/attack/skill/hit/faint rigs (Skeleton2D, or Spine if they use it: Spine Essential $69) | $15-40/hr (Freelancer.com 2D-animation profiles) | https://www.freelancer.com/hire/2d-animation |
| Composer / sound designer | M4 | Tower themes, battle/boss stingers, UI and unit SFX | Music for indie games, per finished minute (GameSoundCon 2025): most common $400, median $407, average $618, top $2,100. Sound design $9-30/hr | https://www.gamesoundcon.com/post/gamesoundcon-game-audio-industry-survey-2025 · https://www.freelancer.com/hire/sound-design |
| QA tester (optional) | M5 | Device matrix, IAP sandbox, recruiting the 12 Play testers | $15-45/hr (Freelancer.com game-testing profiles) | https://www.freelancer.com/hire/game-testing |
| UI/UX designer (optional) | M3-M4 | Touch-first HUD and meta screens | $10-40/hr (Freelancer.com UI-design profiles) | https://www.freelancer.com/hire/ui-design |
| Trademark lawyer | Before M5 listing; sign-off before M7 | Clearance and filing for the title; review of IP-CHECK.md | Not costed in the research doc (get quotes) | — |

Where to hire: Work With Indies (https://workwithindies.com/, posts from $49), Freelancer.com, Upwork.

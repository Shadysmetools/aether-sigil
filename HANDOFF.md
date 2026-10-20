# Emberwick handoff, 2026-10-20

## Where things are
- **Repo:** https://github.com/Shadysmetools/emberwick (private, `main`)
- **Design doc:** https://claude.ai/code/artifact/c95fe8f8-8f5f-4ebe-a95c-f0e41bd44a86
- **Concept gallery** (anime-ink art, 18 Wicks, sigil maker): https://claude.ai/artifact/RuZforo69NoB46s47zqYsi, also at `docs/gallery/`
- **Prototype:** `game/` (Godot 4.7.2). Tests: rules 69 pass / 0 fail, UI smoke 12 pass / 0 fail
- **Research:** `RESEARCH-open-source.md` (licence-checked tools, assets, costs; recommended stack plus a do-not-use list)
- **Local only (not in git):** `engine/` (Godot 4.7.2), `assets/` (Kenney Hexagon Kit, CC0), `art/incoming/` (Shady's drawings go here)

## Decisions
- **All art and code must be original or CC0 / MIT / OFL.** No Yu-Gi-Oh or other franchise assets, characters or maps, and no reverse-engineering. Archetypes and anime style are fine.
- **Shady draws the characters himself.** AI may be used for concepts only; finals are drawn by a human so they can be owned.

## Next steps
1. **Prototype fixes:**
   - AI variety and balance: the AI always plays the same game and P1 always wins.
   - Satchels: add Bloom or Stone, so the x1.5 element bonus can actually happen.
   - Hearth placement: they currently sit in opposite corners.
   - Phone layout: replace fixed positions with anchors.
2. **Integrate Shady's drawings** from `art/incoming/` as sprites, and rig them with Skeleton2D.
3. **Original chapter maps:** terrain, Beacons and spawns.
4. **Android export:**
   - JDK 17
   - SDK Platform 36
   - release keystore
   - AAB via Gradle
   - Play Console ($25), then a 12-tester, 14-day closed test
5. **iOS export:**
   - a Mac with Xcode 26+
   - an Apple developer account ($99/yr)
   - StoreKit 2 plugin built for 4.7
6. **Claude Design design-system push:** blocked until Shady runs `/design-login`.

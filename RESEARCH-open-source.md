# Emberwick: open-source and free resources for a commercial, closed-source mobile game

**Prepared:** 2026-10-20, for Shady, solo founder.
**Game:** Emberwick. A 37-tile hex board (radius 3), with Wicks summoned from lanterns and light acting as territory. Built in Godot 4.7 for iOS and Android.

**How this was checked**
- Every row below was opened on 2026-10-20, either the live page or the GitHub repo through the GitHub API.
- "Last activity" means the repo's last push date, or the date shown on the page. "Not shown" means the page shows no date.
- Anything I could not open, or that came only from search snippets or third parties, is marked **UNVERIFIED**.
- This is not legal advice. Before launch, keep a `THIRD_PARTY_NOTICES` / credits file that lists every asset and its licence.

**Licence key for a closed-source commercial app**
- **YES**: no conditions that matter (CC0, Unlicense, public domain).
- **ATTRIB**: allowed, but you must ship the licence or copyright notice or credit the author (MIT, Apache-2.0, BSD, CC-BY, OFL).
- **NO**: copyleft or non-commercial terms are incompatible with a closed-source paid app (GPL, AGPL, CC-NC, ND), or the repo has no licence at all, which legally means all rights reserved.
- **TOOL-OK**: a GPL or proprietary *tool* whose *output* (your art or audio) belongs to you. You don't ship the tool.

---

## 1. Godot 4 code: engine, addons, plugins

| Name | Link | Licence | Closed-source commercial? | Last activity | Why it helps Emberwick |
|---|---|---|---|---|---|
| Godot Engine 4.7.2-stable | https://github.com/godotengine/godot · https://godotengine.org/license/ | MIT | ATTRIB. The licence page says you must include Godot's copyright notice and licence text, plus third-party notices (COPYRIGHT.txt). Linking godotengine.org/license in your credits is acceptable. No royalties. | 4.7.2 released 2026-08-18 (4.7 was 2026-06-18) | The engine. Update from 4.7 to **4.7.2**; it's a patch release with the same export targets. |
| AStar2D (built-in) | https://docs.godotengine.org/en/stable/classes/class_astar2d.html | MIT (engine) | ATTRIB (covered by the Godot notice) | 4.7 docs | Pathfinding over any graph. Add your 37 hex centres as points and connect each to its neighbours. **AStarGrid2D has no hex cell shape** (Square, Isometric Right, Isometric Down only), so use AStar2D. |
| Saving games (built-in) | https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html | MIT (engine) | ATTRIB (covered) | 4.7 docs | Covers ConfigFile for settings, JSON, or binary `FileAccess.store_var` to `user://`. That's enough for local saves; no addon needed. |
| godot-hexagon-tile-map-layer (Zehir) | https://github.com/Zehir/godot-hexagon-tile-map-layer | MIT | ATTRIB | 2026-09-21 (v2.5.2, 2025-11-02) | **Main hex library.** Extends TileMapLayer with cube coordinates and built-in A* pathfinding. Needs Godot 4.4+. |
| GDHexGrid (romlok) | https://github.com/romlok/godot-gdhexgrid | MIT | ATTRIB | 2022-10-07 | Small GDScript hex-math library based on Red Blob Games. 2018-era (Godot 3); **4.x compatibility UNVERIFIED**. Use it as math reference. |
| Red Blob Games: Hexagonal Grids | https://www.redblobgames.com/grids/hexagons/ | No licence stated ("Copyright © 2026 Red Blob Games") | Learn the maths; don't copy-paste the code verbatim | Modified 2026-09-29 | The reference for coordinates, distance, rings (radius-3 board = rings 0–3), line of sight, pixel↔hex and pathfinding. |
| Godot Tactical RPG (ramaureirac) | https://github.com/ramaureirac/godot-tactical-rpg | MIT | ATTRIB. Check any bundled art before reuse. | 2026-02-21 (v2.0.0, 2024-08-20) | 3D square-grid tactics template for Godot 4.3. Turn order, movement and attack architecture to study or adapt. |
| GDQuest 2D Tactical RPG Movement | https://github.com/gdquest-demos/godot-2d-tactical-rpg-movement | Code **MIT**; art **CC-BY-NC-SA 4.0** | Code ATTRIB; **art NO** | 2026-05-16 | Clean grid unit-selection and movement code with a `godot4` folder. Don't ship its art. |
| LimboAI | https://github.com/limbonaut/limboai | MIT | ATTRIB | 2026-10-04 (v1.8.1, 2026-08-20) | Behaviour trees and state machines. v1.8.1 ships **Godot 4.7.2 Android libs and export templates**; a GDExtension build exists too. Good for enemy-Wick turn logic. |
| Beehave | https://github.com/bitbrain/beehave | MIT | ATTRIB | 2026-09-20 | Pure-GDScript behaviour trees (v2.10+ for Godot 4.5+). Simpler than LimboAI; no native binaries to manage on iOS. |
| godot-utility-ai (Pennycook) | https://github.com/Pennycook/godot-utility-ai | MIT | ATTRIB | 2024-04-21 (v0.2.0) | Utility AI (score each candidate action). Fits "where to place a lantern or Wick" decisions. Not recently maintained. |
| Minimax / expectimax for the AI | (no maintained Godot addon found; best search hit was an unlicensed 2019 tic-tac-toe repo) | n/a | Write your own | n/a | A 37-tile board is small enough for a hand-written depth-limited minimax with alpha-beta in GDScript. Combine it with utility scoring for the evaluation function. |
| Maaack's Godot Game Template | https://github.com/Maaack/Godot-Game-Template | MIT | ATTRIB | 2026-09-10 | Main, options, pause and credits menus, already targeted at Godot 4.7. Saves weeks of UI shell work. |
| Godot demo projects | https://github.com/godotengine/godot-demo-projects | MIT | ATTRIB | 2026-10-08 | Official samples (UI, GUI scaling, mobile input). Reference code. |
| **Google Play Billing (official, Godot Foundation)** | https://github.com/godot-sdk-integrations/godot-google-play-billing | MIT | ATTRIB | 2026-09-25 (3.3.0, 2026-07-27) | **Android IAP.** Master supports Godot 4.2+. It uses `billing-ktx:9.1.0`, which meets Google's "Play Billing Library 8+ from 2026-08-31" rule. Needs Gradle build enabled. |
| **godot-storekit2 (official org)** | https://github.com/godot-sdk-integrations/godot-storekit2 | MIT | ATTRIB | 2026-04-27 (v0.2, 2025-09-18) | **iOS IAP via StoreKit 2.** Release zips go up to **Godot 4.6.2. There is no 4.7 build**, so you'd build it on a Mac or wait for a release. It's v0.x, so test carefully. |
| godot-ios-plugins (official org) | https://github.com/godot-sdk-integrations/godot-ios-plugins | MIT | ATTRIB | 2026-07-10 (last binary release 3.5-stable, 2022) | Holds `inappstore` (StoreKit 1), `gamecenter`, `icloud` and `apn`. **No Godot 4 binaries are published**; you build from source on a Mac against the 4.7 headers. |
| Godot Play Game Services (official org) | https://github.com/godot-sdk-integrations/godot-play-game-services | MIT | ATTRIB | 2026-07-20 | Android sign-in, achievements, leaderboards and **snapshots** (cloud save) for Godot 4.3+. |
| GodotFirebase (GodotNuts) | https://github.com/GodotNuts/GodotFirebase | MIT | ATTRIB | 2026-09-13 | GDScript Firebase over REST: Auth, Firestore, Storage, Functions. Works on both platforms with no native plugin, so it's a good **cross-platform cloud save**. |
| godot-firebase (godot-mobile-plugins) | https://github.com/godot-mobile-plugins/godot-firebase | MIT | ATTRIB | 2026-05-06 | Native Firebase plugin; an alternative if you need native Analytics or Crashlytics (feature list not opened). |
| GameAnalytics Godot SDK (official) | https://github.com/GameAnalytics/GA-SDK-GODOT | MIT (SDK) | ATTRIB. The GameAnalytics *service* has its own ToS (not opened). | 2026-10-16 (3.1.2, 2026-10-06) | Free-tier game analytics for Android and iOS on Godot 4.5+. Funnels for tutorial and level drop-off. |
| AdMob (official org) | https://github.com/godot-sdk-integrations/godot-admob | MIT | ATTRIB | 2026-05-27 | Only relevant if you add rewarded ads. Poing Studios' plugin is an alternative (MIT, 2026-10-18). |
| godot-safe-resource-loader | https://github.com/derkork/godot-safe-resource-loader | MIT | ATTRIB | 2026-04-28 | Use it if you save via `.tres` Resources. Loading untrusted `.tres` files can run code. |
| Pandora (bitbrain) | https://github.com/bitbrain/pandora | MIT | ATTRIB | 2026-08-20 | Data management for item and creature definitions (a Wick roster). |
| Godot Dialogue Manager | https://github.com/nathanhoad/godot_dialogue_manager | MIT | ATTRIB | 2026-10-17 | Tutorial and story text, if Emberwick has any. |
| Mobile UI kit | No dedicated, maintained, licensed Godot 4 "mobile UI kit" turned up in searches | n/a | n/a | n/a | Use Godot's Theme system with the Kenney UI Pack (section 2) and Maaack's template. |

## 2. Art and asset sources

| Name | Link | Licence | Closed-source commercial? | Last activity | Why it helps Emberwick |
|---|---|---|---|---|---|
| Kenney (all asset pages) | https://kenney.nl/support | **CC0** ("public domain… free to use them, even in commercial projects… Attribution is not required"). The Kenney logo is reserved. | YES | Not shown | The safest placeholder and production art source. |
| Kenney Hexagon Pack | https://kenney.nl/assets/hexagon-pack | CC0 | YES | Not shown (310 files) | 2D hex terrain and building tiles. Instant board prototype. |
| Kenney UI Pack | https://kenney.nl/assets/ui-pack | CC0 | YES | v2.0 remake; date not shown (430 files) | Buttons, panels and sliders for the mobile UI. |
| Kenney Particle Pack | https://kenney.nl/assets/particle-pack | CC0 | YES | Not shown (80 files) | Glow, spark and smoke sprites for lantern light and summon VFX. |
| Kenney Game Icons | https://kenney.nl/assets/game-icons | CC0 | YES | Not shown (105 files) | UI icons (settings, pause, sound). |
| Quaternius | https://quaternius.com/license.html | Custom licence: free for commercial games, **no attribution**, but you **may not redistribute the assets standalone** or claim authorship | YES (inside a game) | Not shown | Mostly 3D models. Useful for 3D Wicks or for pre-rendering 3D creatures to 2D sprites. |
| game-icons.net | https://game-icons.net/about.html | **CC-BY 3.0** | ATTRIB. Credit **each author** ("Icons made by {author}. Available on https://game-icons.net"). | Repo pushed 2026-04-23 | 4,000+ SVG icons for abilities and status effects. Keep a per-icon author list in your credits. |
| OpenGameArt (licence filter) | https://opengameart.org/art-search-advanced | Mixed, chosen per item: CC0, CC-BY 3.0/4.0, OGA-BY, CC-BY-SA, GPL 2/3 | **Per item.** Only CC0 or CC-BY are safe. **Avoid GPL and CC-BY-SA.** | Live site | Big library. Many items carry several licences; read each item's page. |
| OGA "Hex Tileset Pack" (adythewolf) | https://opengameart.org/content/hex-tileset-pack | CC0 | YES | 2015-02-18 | 32×32 hex terrain, roads and units. Pixel-art prototype board. |
| Other OGA hex results ("Pixel hex tilesets enhanced", "180+ Seamless Hex Tiles", "Hexset v.01.1"…) | Search results page | **UNVERIFIED**: licences not opened individually | Check each | n/a | More hex tile options; open each page first. |
| Ninja Adventure Asset Pack (Pixel-boy) | https://pixel-boy.itch.io/ninja-adventure-asset-pack | **CC0 1.0** | YES | Update #8, 2026-03-29 | 50+ characters, 30+ monsters, 37 music tracks, 100+ SFX, UI and 30+ VFX. Big free prototype kit (top-down pixel style). |
| Pixilart Hexagonal Tileset (Scrython) | https://scrython.itch.io/hexagonal-tileset | No named licence; page says "Free for Commercial Use… no credit required" | YES per page text. Redistribution terms not stated. | "Updated 9 days ago" (about 2026-10-11) | Pixel hex tiles, pay-what-you-want. Screenshot the terms for your records. |
| itch.io "Hexagonal Village 3D" (Voloshka) | https://viravoloshyn.itch.io/hexagonal-village-3d | **UNVERIFIED** (page not opened) | Check | n/a | Possible 3D hex village set. |
| GODOT-VFX-LIBRARY (haowg) | https://github.com/haowg/GODOT-VFX-LIBRARY | MIT | ATTRIB | 2026-01-25 | 35+ particle effects and 17+ shaders for Godot 4.5+. Adapt for light-spread and summon effects. |
| Universal Transition Shader | https://github.com/cashew-olddew/Universal-Transition-Shader | CC0-1.0 | YES | 2026-03-18 | Screen and scene transitions. |
| Google Fonts (font files) | https://github.com/google/fonts | Per-family: OFL, Apache-2.0 or UFL (each family folder has its licence) | ATTRIB. Ship the font's licence text. | 2026-10-20 | Free UI and title fonts. "Always read the license for every font." |
| SIL Open Font License FAQ | https://openfontlicense.org/ofl-faq/ | OFL-1.1 | ATTRIB. Bundling in a sold game is fine. Can't sell the font alone. Rename if you modify a font with Reserved Font Names. Mobile apps include the copyright, licence notice and licence text. | Live | Rules for every OFL font you embed. |

## 3. Animation tools

| Name | Link | Licence / cost | Closed-source commercial? | Last activity | Why it helps Emberwick |
|---|---|---|---|---|---|
| AnimationPlayer / AnimationTree / Skeleton2D (built-in) | https://docs.godotengine.org | MIT (engine) | ATTRIB (covered by Godot notice) | 4.7 | **Default choice.** Cut-out bone animation with Skeleton2D and Bone2D, plus a state machine in AnimationTree. Zero cost and zero runtime risk on iOS. |
| Spine (Esoteric Software) | https://esotericsoftware.com/spine-purchase | Essential **$69** (was $99), Professional **$379** (was $449), Enterprise $2,499 + $379/user/yr. Enterprise required at ≥ $500k annual revenue *or funding*. Retrieved 2026-10-20. | YES with a licence. The runtimes licence (https://esotericsoftware.com/spine-runtimes-license) requires users integrating the runtime to own a Spine Editor licence. You can keep shipping after the licence expires. | Runtimes repo pushed 2026-10-19 | Industry-standard 2D skeletal animation. **spine-godot CI builds Godot 4.7.2 including an iOS export template** (`spine-godot-v4.yml`). A GDExtension flavour needs no custom build (iOS GDExtension path UNVERIFIED). |
| Rive editor | https://rive.app/pricing | Free $0 (**exports play a Rive splash screen**, 3 files); Cadet $9/seat/mo (no splash); Voyager $32; Enterprise $120. Retrieved 2026-10-20. | Runtime is MIT (https://github.com/rive-app/rive-runtime, pushed 2026-10-19). The free-tier commercial terms aren't stated on the pricing page (**UNVERIFIED**). | n/a | Godot is **not** in Rive's official runtime list. |
| RiveGD (community Godot runtime) | https://github.com/maidopi-usagi/RiveGD | MIT | ATTRIB, but README says "**not ready for production**" and "**iOS and Web are not supported yet**" | 2026-10-18 | **Not viable for an iPhone launch today.** Watch it. |
| kibble-cabal/godot-rive | https://github.com/kibble-cabal/godot-rive | **No licence** | **NO** (all rights reserved) | 2025-03-10 | Don't use. |
| DragonBones | https://github.com/DragonBones/DragonBonesJS · https://github.com/DragonBones/Tools | Runtimes and Tools: MIT | ATTRIB | JS runtime 2026-01-23; Tools 2022-06-09 | Effectively dormant. No Godot runtime found. Editor status is **UNVERIFIED** (official site didn't render). Skip it. |
| Blender | https://www.blender.org/about/license/ | GPL (tool) | **TOOL-OK.** "What you create with Blender is your sole property… free for you to use as you like." | Mirror pushed 2026-10-20 | Model Wicks in 3D and render to sprite sheets, or do 2D with Grease Pencil. GPL never touches your game. |
| Krita | https://docs.krita.org/en/KritaFAQ.html | GPL-3.0 (tool) | **TOOL-OK.** "Krita can be used commercially by artists for any purpose… What you create with Krita is your sole property." | Repo pushed 2026-10-20 | Painting creatures and backgrounds, plus frame-by-frame animation. |
| Pixelorama | https://github.com/Orama-Interactive/Pixelorama | MIT | YES (tool; art is yours) | 2026-10-20 | Free pixel-art and animation editor, itself built in Godot. Strong Aseprite alternative. |
| LibreSprite | https://github.com/LibreSprite/LibreSprite | GPL-2.0 (fork of the last GPL Aseprite) | TOOL-OK | 2026-10-15 | Free sprite editor. GPL applies to the program, not your sprites. |
| Aseprite | https://www.aseprite.org/faq/ · https://github.com/aseprite/aseprite | **Proprietary EULA** since Aug 2016 (not GPL). $19.99 binary. Source can be compiled for personal use only; no redistribution of builds. | TOOL-OK. FAQ: art made with it can be used in commercial products. | 2026-10-14 | Best-in-class pixel animation; Godot importer plugins exist. A $20 one-off. |

## 4. Audio

| Name | Link | Licence / cost | Closed-source commercial? | Last activity | Why it helps Emberwick |
|---|---|---|---|---|---|
| Freesound | https://freesound.org/help/faq/ | Per sound: **CC0**, **CC-BY**, **CC-BY-NC** (plus retired Sampling+) | CC0 YES; CC-BY ATTRIB; **CC-BY-NC NO** | Live | Use the search page's licence filter and keep CC0 and CC-BY only. Log every sound ID and author. |
| Kenney audio packs | https://kenney.nl/assets/category:Audio | CC0 | YES | Not shown | Interface Sounds, UI Audio, Impact Sounds, RPG Audio, Music Jingles, Digital Audio and more. Covers UI clicks, summons and win/lose stings. |
| Ninja Adventure pack audio | https://pixel-boy.itch.io/ninja-adventure-asset-pack | CC0 | YES | 2026-03-29 | 37 music tracks and 100+ SFX. Placeholder soundtrack. |
| jsfxr (chr15m) / sfxr.me | https://github.com/chr15m/jsfxr · https://sfxr.me/ | Code: Unlicense. Site's table: "Unrestricted commercial use" on the Free tier. | YES (tool) | 2026-05-05 | Generate retro SFX in the browser in seconds. |
| jsfxr (grumdrig, original port) | https://github.com/grumdrig/jsfxr | Unlicense | YES (tool) | 2023-05-04 | Same idea, older. |
| Bfxr | https://github.com/increpare/bfxr | README says **Apache-2.0**; GitHub detects no licence file (mismatch) | TOOL-OK | 2025-04-17 | sfxr with more controls (Flash/AIR desktop build). |
| LMMS | https://github.com/LMMS/lmms | GPL-2.0 (tool) | TOOL-OK. GPL governs the program. **Licences of bundled samples and presets are UNVERIFIED** (docs page didn't cover it). | 2026-10-19 | Free music production. Prefer your own or CC0 samples. |
| Audacity | https://github.com/audacity/audacity | GPL-3.0 / GPL-2.0+ (tool) | TOOL-OK. GPL governs the software, not your audio (FAQ is silent on output terms). | 2026-10-20 | Editing, trimming, normalising and loudness work on SFX and music. |

## 5. Mobile pipeline from Godot 4.7 (costs retrieved 2026-10-20)

**Godot side (both platforms)**
1. Install **Godot 4.7.2** and its matching export templates (Editor > Manage Export Templates). The templates must match the editor version exactly.
2. Both 4.7-stable and 4.7.2-stable ship `targetSdk 36` and `compileSdk 36` (`platform/android/java/app/config.gradle`). That meets Google Play's rule: since **2026-08-31**, new apps and updates must target **API 36 (Android 16)**.

**Android**

| Step | Detail | Cost |
|---|---|---|
| Toolchain | OpenJDK **17**; Android SDK: Platform-Tools ≥ 35.0.0, Build-Tools 35.0.1, Platform 35, Command-line Tools, CMake 3.10.2.4988404, NDK r28b. The 4.7 docs say Platform 35, but the engine compiles against 36, so **install Platform 36 too**. Set the Java and SDK paths in Editor Settings. | Free |
| Release keystore | `keytool` to create a non-debug keystore. Set Release path, user (alias) and password in the export preset; keystore and key passwords must match. Uncheck "Export With Debug". **Back up the keystore.** | Free |
| AAB + Gradle | Play requires **AAB** (since Aug 2021), which requires "Use Gradle Build". Gradle build is also needed for the Billing plugin. | Free |
| Google Play Console | **US$25 one-time**. 18+, possibly government ID and card under your legal name. Device verification via the Play Console app. | $25 |
| New personal-account testing gate | Personal accounts created after 2023-11-13: closed test with **≥ 12 testers opted in continuously for 14 days** before production. Budget about 3 weeks. An *organisation* account is not subject to this (per page scope). | $0 (recruit testers) |
| IAP | Google Play Billing plugin 3.3.0 (PBL 9.1.0). Google requires **PBL 8+** for new apps and updates from 2026-08-31. | 15% / 30% store fee (Google's rates; **UNVERIFIED** here) |

Sources: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html · https://support.google.com/googleplay/android-developer/answer/6112435 · https://support.google.com/googleplay/android-developer/answer/14151465 · https://support.google.com/googleplay/android-developer/answer/11926878 · https://developer.android.com/google/play/billing/deprecation-faq

**iOS**

| Step | Detail | Cost |
|---|---|---|
| Mac + Xcode | Godot docs (4.7): "You must export for iOS from a computer running macOS with Xcode installed." Godot writes an `.xcodeproj`; you build, sign and upload in Xcode. | Mac hardware (your choice) |
| Xcode version | Since **2026-04-28**, App Store Connect uploads must be built with **Xcode 26+ / iOS 26 SDK**. Xcode 26.6 needs **macOS Tahoe 26.2+**; 26.0.1–26.3 ran on Sequoia 15.6+. **Any Mac or cloud Mac you use must run a current macOS.** Since 2026-09-09 apps must target iOS 13+. | Free |
| Apple Developer Program | **US$99/year**. Individual: enrol under your legal name (that's the seller name). Organisation: needs a legal entity and a **D-U-N-S number** (free in most places). | $99/yr |
| Team ID + bundle ID | The 10-character Team ID from developer.apple.com goes in the Godot iOS export preset, plus a reverse-DNS bundle ID. | Free |
| iOS IAP | Either StoreKit 2 plugin (binaries up to Godot 4.6.2; **build for 4.7 on a Mac**) or `godot-ios-plugins/inappstore` (build from source). **Either way you build a native plugin on a Mac.** | Mac time |
| No-Mac options | **Codemagic**: 500 free macOS M2 minutes/month on personal accounts; then $0.095/min (M2) or $0.114/min (M4). **GitHub Actions** macOS runner: $0.062/min (free-minute and public-repo terms **UNVERIFIED**). **MacinCloud**: about $1/hr pay-as-you-go, about $20–49/mo managed (**UNVERIFIED**: their pages returned 403/404; figures are third-party). A fully headless Godot export → xcodebuild → TestFlight flow on CI is **UNVERIFIED end-to-end**. A used Apple-silicon Mac mini that can run macOS Tahoe is the low-friction path. | $0–$1/hr |

Sources: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html · https://developer.apple.com/support/enrollment/ · https://developer.apple.com/news/upcoming-requirements/ · https://developer.apple.com/xcode/system-requirements/ · https://docs.codemagic.io/billing/pricing/ · https://docs.github.com/en/billing/reference/actions-runner-pricing

**Minimum cash to ship both stores:** $25 (Google, once) + $99/yr (Apple) = **$124 in year one**, plus access to a Mac.

## 6. Comparable open-source games and templates (architecture study)

| Name | Link | Licence | Use | Last activity | What to learn |
|---|---|---|---|---|---|
| Battle for Wesnoth | https://github.com/wesnoth/wesnoth | GPL-2.0 | **REFERENCE ONLY.** Learn ideas; never copy code or assets. | 2026-10-19 | The canonical hex turn-based game: zone of control, terrain modifiers, AI turn structure, data-driven unit definitions (WML). |
| OpenXcom | https://github.com/OpenXcom/OpenXcom | GPL-3.0 | **REFERENCE ONLY.** Also needs the original commercial X-COM data files; never use those. | 2026-09-28 | Tactical turn and time-unit systems, line of sight, save formats. |
| Freeciv | https://github.com/freeciv/freeciv | GPL-2.0 | **REFERENCE ONLY** | 2026-10-20 | Territory and borders on a tile map, which is close to "light as territory". |
| Unciv | https://github.com/yairm210/Unciv | MPL-2.0 (file-level copyleft) | **REFERENCE ONLY** (to be safe) | 2026-10-20 | A *mobile* hex strategy game (Kotlin, Android): touch UX on hex maps, AI turn budgeting on phones. It's a Civ V remake; ignore any Civ-derived content. |
| OpenRA | https://github.com/OpenRA/OpenRA | GPL-3.0 | **REFERENCE ONLY** | 2026-10-20 | Data-driven trait/actor architecture. |
| Godot Tactical RPG (ramaureirac) | https://github.com/ramaureirac/godot-tactical-rpg | MIT | Code reusable with notice | 2026-02-21 | Godot-native tactics loop. |
| GDQuest 2D Tactical RPG Movement | https://github.com/gdquest-demos/godot-2d-tactical-rpg-movement | MIT code / CC-BY-NC-SA art | Code OK; **art NO** | 2026-05-16 | Board/Unit/Cursor scene architecture. |
| TBS_GoDot (ja-brouil) | https://github.com/ja-brouil/TBS_GoDot | MIT code | **REFERENCE ONLY.** It's a Fire Emblem clone; any Fire Emblem-derived content is commercial IP. | 2020-12-23 | Turn-based state flow (Godot 3). |
| WeatheredSouls/GodotTactics | https://github.com/WeatheredSouls/GodotTactics | **No licence** | **NO.** Reading only; all rights reserved. | 2026-07-01 | A tutorial port; learn from the video/tutorial instead. |

## 7. Team roles and freelance costs

The rates below are **samples of visible profiles on 2026-10-20**. Freelancer.com listings skew to lower-cost regions (India, Pakistan, Sri Lanka and similar), so treat them as a floor. Upwork's rate pages returned 403 (**UNVERIFIED**).

| Role | What they do on Emberwick | Cited cost | Source |
|---|---|---|---|
| Mobile game developer (Godot) | Hex board, turn engine, AI, IAP and cloud-save plugins, export and store submission | **$18–50/hr** on visible Freelancer.com profiles. UK Godot contracts: median **£441/day** for the 6 months to Oct 2025, from only 6 rates; no 2026 data. | https://www.freelancer.com/hire/godot · https://www.itjobswatch.co.uk/contracts/uk/godot.do |
| 2D creature/character artist | Wick designs, lantern and tile art, key art for store listings | **$8–30/hr** (Freelancer.com game-art profiles). Upwork figures of about $18–44/hr come from search snippets only (**UNVERIFIED**). | https://www.freelancer.com/hire/game-art |
| Animator (2D) | Idle, summon, attack and fade animations (Skeleton2D or Spine rigs) | **$15–40/hr** (Freelancer.com 2D-animation profiles) | https://www.freelancer.com/hire/2d-animation |
| UI/UX designer | Touch-first HUD, board readability on small screens, IAP store screens, onboarding | **$10–40/hr** (Freelancer.com UI-design profiles) | https://www.freelancer.com/hire/ui-design |
| Composer / sound designer | Soundtrack, summon and light SFX, UI sounds | Music, **indie games, per finished minute (GameSoundCon 2025)**: most common **$400**, average **$618**, median **$407**, top **$2,100**. Sound design: **$9–30/hr** (Freelancer.com profiles). | https://www.gamesoundcon.com/post/gamesoundcon-game-audio-industry-survey-2025 · https://www.freelancer.com/hire/sound-design |
| QA tester | Device matrix (low-end Android and iPhones), IAP sandbox tests, regression passes. Also covers recruiting the 12-tester Play closed test. | **$15–45/hr** (Freelancer.com game-testing profiles) | https://www.freelancer.com/hire/game-testing |

**Where to hire**
- **Work With Indies** (https://workwithindies.com/): indie games job board; posts from **$49**. It warns of impersonators, and its real email comes only from @workwithindies.com.
- **Freelancer.com** and **Upwork**: general marketplaces.
- **UNVERIFIED** (not opened): ArtStation, r/gameDevClassifieds, itch.io community boards, the Godot forums.

---

## Recommended starter stack (use these first)

1. **Godot 4.7.2** with matching export templates. MIT; credit Godot and include the third-party notices from COPYRIGHT.txt.
2. **Zehir godot-hexagon-tile-map-layer** for the hex board, cube coordinates and A*. MIT.
3. **Red Blob Games hex guide** for the maths: rings, distance and line of sight on the radius-3 board.
4. **Built-in AStar2D**, if you outgrow the addon's pathfinding.
5. **Beehave** (pure GDScript, lowest iOS risk) or **LimboAI** (ships 4.7.2 Android builds) for enemy AI. Add a hand-written depth-limited **minimax** for the 37-tile board.
6. **Maaack's Godot Game Template** (MIT) for menus, options and credits.
7. **Built-in saving** (`FileAccess` / JSON to `user://`) for local saves, with **GodotFirebase** (MIT) for cross-platform cloud save.
8. **Google Play Billing plugin 3.3.0** (MIT; PBL 9.1.0) for Android IAP.
9. **godot-storekit2** (MIT) for iOS IAP. Plan one Mac session to build it for 4.7.
10. **GameAnalytics Godot SDK** (MIT) for analytics.
11. **Kenney**: Hexagon Pack, UI Pack, Particle Pack, Game Icons and audio packs (CC0) for all placeholder art and SFX.
12. **Ninja Adventure pack** (CC0) for placeholder music and extra VFX.
13. **AnimationPlayer + Skeleton2D** for Wick animation at $0. Buy **Spine Essential ($69)** only if the artist works in Spine; spine-godot builds Godot 4.7.2 with iOS templates.
14. **Krita / Blender / Pixelorama** as free art tools (output is yours), plus **jsfxr** and **Audacity** for SFX.
15. **Google Fonts (OFL)** for UI type. Ship each font's OFL text in your credits.

## Do not use (licence traps)

- **Any GPL/AGPL code inside the game:** Wesnoth, OpenXcom, Freeciv, OpenRA (reference only), JensRosaman/godot_hexagon (GPL-3.0), the Zenva strategy repos (GPL-3.0), MrMinimal/godot-vfx-sketchbook (AGPL-3.0), and sdfgeoff fireball shader (GPL-3.0).
- **MPL-2.0 code copied in (Unciv):** modified files would have to be published. Keep it reference only.
- **GDQuest art.** This covers godot-2d-tactical-rpg-movement and godot-shaders: the code is MIT, but the textures and models are **CC-BY-NC-SA 4.0** (non-commercial).
- **CC-BY-NC sounds on Freesound**, and any NC or ND asset anywhere.
- **CC-BY-SA and GPL items on OpenGameArt.** Filter to CC0 or CC-BY and read each item; many carry several licences.
- **Repos with no licence:** kibble-cabal/godot-rive, WeatheredSouls/GodotTactics and GodotTacticsVideo, godotlabsio/godot-tactical-rpg-lite, the save-system repos without licences. No licence means no right to reuse.
- **Clones of commercial games:** TBS_GoDot (Fire Emblem), OpenXcom's required X-COM data, and anything containing a commercial game's sprites, music or code. No reverse-engineering or reuse of commercial games, ever.
- **Rive in Godot for launch:** RiveGD isn't production-ready and has no iOS support. The free Rive tier adds a splash screen to exports.
- **Redistributing Aseprite builds you compiled.** The EULA forbids it; using it for art is fine.
- **Reselling raw assets:** Quaternius forbids standalone redistribution, and the OFL forbids selling a font on its own. Shipping them inside the game is fine.
- **Unofficial "free" packs whose only licence is a title or tag** (for example "Free for Commercial Use" in an itch.io title). Screenshot the terms at download time, or prefer CC0 sources.
- **Kenney's logo** (reserved), and **game-icons.net without per-author credits** (CC-BY 3.0 requires attribution).

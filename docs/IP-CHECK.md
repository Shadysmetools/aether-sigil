# IP check: Aether Sigil: Chronicles of the Capsule Realms

**Prepared:** 2026-10-20/21 by the producer/IP-review agent, for Shady (solo founder).
**Scope:** the title, the subtitle, "Capsule Realms", the 12 tower names, the 12 champion names (`tower_boss` in `data/AETHER_SIGIL_MASTER_GAME_BIBLE.json`), the word "Capsule", and capsule/ball imagery.

> **This is not legal advice.** It is a desk search by a non-lawyer, using public web search and store search. It can't prove a name is free to use. **Have a trademark lawyer review the title, subtitle and capsule design before any store listing goes public** (before the M5 closed test at the latest, since a Play closed test needs a listing).

## Method and its limits

| Source | How it was searched (2026-10-20) | Reliability |
|---|---|---|
| Steam | Store search API `https://store.steampowered.com/api/storesearch/?term=<name>&l=english&cc=US`, exact-phrase match on returned titles | Good for titles; doesn't search in-game content |
| Apple App Store | iTunes Search API `https://itunes.apple.com/search?term=<name>&entity=software&limit=25`, exact-phrase match on `trackName` | Good for app titles (US store) |
| Google Play | `https://play.google.com/store/search?q="<name>"&c=apps&hl=en&gl=US`, HTML parsed for result titles | **Weak.** The page is mostly client-rendered, and the query text is echoed back into the page, so "phrase found" means nothing on its own. Only one real title hit was found. Treat Play as **partially verified**. |
| itch.io | `https://itch.io/search?q=<name>`, exact-phrase match on game-link titles | Good for titles; the result count (~54) is just one generic results page |
| General web | WebSearch per name (games, novels, famous characters) | Search snippets only; links are cited, not every page was opened |
| Trademark registers | USPTO tmsearch (POST to its API returned an S3 `MethodNotAllowed` error), Justia Trademarks (HTTP 403), WIPO Global Brand Database (HTTP 200 for the page shell only; searches run in JavaScript) | **Not reachable from this environment. All trademark status below is UNVERIFIED.** See the manual steps at the end. |

**Not checked:** the 1,000 monster names (already done earlier: 0 exact collisions with 1,025 Pokémon, 14,615 Yu-Gi-Oh cards and 1,488 Digimon; 3 names contain "archen"), the ~100 stage-opponent names in `data/120_STAGES_AND_OPPONENTS.csv` (e.g. Ari Voss, Kael Nyx), the L10 boss names in that CSV (Zane Lux, Yuna Reed, ...; they differ from the JSON champions, see [#16](https://github.com/Shadysmetools/aether-sigil/issues/16)), Symbol names (Nexus, Valor, Aegis, Orbital, Void), "Prism Core", and the rank badge names.

---

## 1. Title, subtitle and "Capsule Realms"

| Name | Stores (Steam / App Store / Play / itch.io) | Web | Trademark | Finding |
|---|---|---|---|---|
| **Aether Sigil** | No exact title on any of the four | No game, app, book or character with that exact name found | UNVERIFIED | No exact collision. But both words are crowded in games: **"AETHER"** has several US applications for game software (AETHER PRISM, serial 98942572, class 9, pending; AETHER & IRON, serials 97291703 and 99433489, class 9; AETHER STUDIOS, serial 90667671; AETHER GAMES, serial 97812022, class 42), per Justia listings seen only as search snippets: https://trademarks.justia.com/989/42/aether-98942572.html · https://trademarks.justia.com/994/33/aether-99433489.html · https://trademarks.justia.com/972/91/aether-97291703.html · https://trademarks.justia.com/owners/aether-studios-inc-4792933 · https://trademarks.justia.com/978/12/aether-97812022.html (**UNVERIFIED**, pages returned 403). **"SIGIL"** is claimed as a trademark (™) of Romero Games Ltd for its Doom episode: https://en.wikipedia.org/wiki/Sigil_(mod) · https://limitedrungames.com/blogs/news/introducing-sigil-from-john-romero (registration status UNVERIFIED). Related uses: *Aether Gazer*, a mobile action RPG whose gear system is called "Sigils" (https://www.gamedeveloper.com/press-release/aether-gazer-releases-major-update-with-new-chapter-and-exciting-event), and the Flesh and Blood TCG card "Sigil of Aether" (https://khaoz.tcgsync.com/products/sigil-of-aether-marvel-ros168-rosetta). |
| **Chronicles of the Capsule Realms** | No exact title | Nothing found. Nearest: *EVE: The Capsuleer Chronicles* (Dark Horse comic, CCP), https://www.eveonline.com/news/view/capsuleer-chronicles-final-volume-available-now | UNVERIFIED | No exact collision. "Capsuleer" is a different word; low risk on its own. |
| **Capsule Realms** | No exact title | Nothing found. Unrelated "Capsule" titles exist (Steam app 303940 *Capsule*, https://store.steampowered.com/app/303940; *Capsule Project 3D*, https://fayvit.itch.io/projeto-capsula-3d) | UNVERIFIED | No exact collision. The risk is not the phrase but the **concept association with Konami's Capsule Monsters** (section 4). |

## 2. Tower names

| Tower | Exact-title hits | Other notable uses | Risk |
|---|---|---|---|
| Verdant Spire | None | *Verdant* board game (Flatout Games) and *Verdant* video game (Tiny Roar), single-word only: https://www.meeplemountain.com/boardgame/verdant/ · https://gameinformer.com/preview/2026/01/27/surviving-an-overgrown-fantastical-apocalypse | Low |
| Ember Bastion | None | A location in a private Kanka worldbuilding wiki: https://app.kanka.io/w/delvers/entities/7609184 | Low |
| Tideglass Citadel | None | Nothing found | Low |
| Frost Meridian | None | Nearest is "Frost Citadel" in Guild Wars 2: https://wiki.guildwars2.com/wiki/Frost_Citadel | Low |
| Iron Labyrinth | **Contained in titles:** *LastCore: Iron Labyrinth* (iOS, Le Trong Nghia Nguyen) https://apps.apple.com/us/app/lastcore-iron-labyrinth/id6777114201 (also appeared in Play results; package not resolved, UNVERIFIED); *Out of the Iron Labyrinth* (itch.io) https://m-allen-hall.itch.io/out-of-the-iron-labyrinth | Generic phrase | Low–Medium (used as a subtitle by another mobile game; fine as an in-game location, don't use it as a product name) |
| Storm Crown | None | *The Storm Crow* (novel, Kalyn Josephson) and *Crown of Storms* (Annie Bellet): https://www.harryhartog.com.au/products/the-storm-crow-kalyn-josephson-9781728206974 · https://anniebellet.com/books/crown-of-storms/ | Low |
| Obsidian Eclipse | **Contained in a title:** *Obsidian Eclipse: Azure Enforcer* (Steam) https://store.steampowered.com/app/2949180/ | A one-shot TTRPG adventure on BackerKit (https://www.backerkit.com/c/users/2444720/backed_projects) | Low–Medium (prefix of another game's title; fine as a location, don't use as a product name) |
| Sunken Archive | None | Nothing exact | Low |
| Astral Observatory | **Contained in an asset title:** *Astral Observatory: 12 Painterly Backgrounds* (itch.io asset pack) https://revmine.itch.io/astral-observatory-6-painterly-backgrounds | A location set in the Roblox game *Fisch* (https://xboxplay.games/fisch/how-to-find-all-6-astral-observatory-in-fisch-75567) | Low |
| Crystal Sanctum | None | Nearest: "Crystal Sanctuary", a Commander Keen fan-mod level: https://keenwiki.shikadi.net/wiki/Crystal_Sanctuary | Low |
| Rift Frontier | None | *RIFT* MMO (Trion), single word: https://telarapedia.fandom.com/wiki/RIFT | Low |
| **Crown of Ages** | **Exact collision:** *Crown of Ages*, Steam app 5364500, developer/publisher Lunvero Studio, indie strategy (4X), planned release Q1 2027: https://store.steampowered.com/app/5364500/ (page opened 2026-10-20) | — | **Medium.** Same name, same industry (video games), launching about when we would. As a tower name inside our game it's a weak conflict, but it will confuse search and may draw a complaint if their mark is filed. **Rename the tower.** |

## 3. Champion names (`tower_boss` in the bible JSON)

None of the 12 full names returned an exact match on any store or in web search for a famous character. Only single-word overlaps appeared, which are normal for given names and common nouns.

| Champion | Exact hits | Partial overlaps found | Risk |
|---|---|---|---|
| Lyra Quill | None | Lyra (She-Hulk Lyra, Marvel; Lyra Belacqua, *His Dark Materials*); Quill (Marvel): https://en.wikipedia.org/wiki/She-Hulk_(Lyra) · https://comicvine.gamespot.com/app.php/quill/4005-62968/ | Low. Note "Quill" also evokes Peter Quill (Star-Lord); don't pair it with a space-outlaw look. |
| Varen Lux | None | "Lux" (League of Legends champion): https://wiki.leagueoflegends.com/en-us/Category:LGBTQ+_characters | Low |
| Niko Ardent | None | None | Low |
| Rhea Volt | None | "Rhea" (Fire Emblem: Three Houses): https://grandavehousing.calpoly.edu/news/rhea-fire-emblem-a-deep | Low |
| Renn Calder | None | None | Low |
| Zara Nyx | None | "Nyx" is widely used (The Dragon Prince, Spawn, Call of Duty Mobile, Mass Effect's Sidera/Vetra Nyx): https://comicvine.gamespot.com/nyx/4005-3382/ · https://giantbomb.com/wiki/Characters/Sidera_Nyx | Low |
| Cira Dawn | None | None | Low |
| Tarin Moss | None | None | Low |
| Silas Wren | None | "Wren" (Pretty Little Liars, Fear the Walking Dead): https://www.romper.com/p/what-happened-to-wren-on-pretty-little-liars-he-was-involved-all-along-67185 | Low |
| Sera Vale | None | None | Low |
| Mako Reed | None | None found ("Mako" is also a Final Fantasy VII term; not a character name) | Low |
| Ari Zephyr | None | "Zephyr" (Marvel Elementals, Disney Fairies, Resonance of Fate): https://www.writeups.org/zephyr-marvel-comics-elementals/ · https://disneyfairies.fandom.com/wiki/Zephyr | Low |

Store searches for all 12 full names (Steam API, iTunes API, Play, itch.io) returned no exact title.

## 4. Known risk areas

### 4a. "Capsule" and Konami's Capsule Monsters

- Konami published three games based on the in-universe board game **Capsule Monster Chess**: *Monster Capsule: Breed & Battle* (PlayStation, Japan, 1998), *Monster Capsule GB* (Game Boy Color, Japan, 2000) and *Yu-Gi-Oh! Capsule Monster Coliseum* (PS2, 2004 JP/NA, 2005 EU). Sources: https://yugipedia.com/wiki/Yu-Gi-Oh!_Monster_Capsule:_Breed_and_Battle · https://yugipedia.com/wiki/Yu-Gi-Oh!_Monster_Capsule_GB · https://yugipedia.com/wiki/Yu-Gi-Oh!_Capsule_Monster_Coliseum
- A 12-episode anime, *Yu-Gi-Oh! Capsule Monsters*, aired on 4Kids TV in 2006; in it, the characters summon monsters from capsules (same Yugipedia sources). There was also a physical *Capsule Monsters* product with its own rulebook: https://ms.yugipedia.com//1/1f/Capsule_Monsters_rulebook.pdf
- Konami's trademark list includes **"YU-GI-OH! CAPSULE MONSTER COLISEUM"** for video game software (https://trademark.justia.com/owners/konami-corporation-280685/page45; search snippet only, **UNVERIFIED**, status unknown). No standalone "CAPSULE MONSTERS" registration was confirmed either way.
- **Why it matters here:** the risk isn't the dictionary word "capsule". It's that the overall package is close to Capsule Monster Chess: monsters deployed from capsules onto a tactical grid board with terrain. The repo's own `data/README_FOR_CLAUDE.md` says the bible "uses the broad concept of capsule-deployed monsters", and its `ip_note` says the names were made original "to avoid copying Yu-Gi-Oh!". Game mechanics and ideas aren't protected by copyright, but **a subtitle that puts "Capsule" next to monsters and a tactical board invites a comparison with Konami** in a listing, a review or a takedown request.

### 4b. Capture-ball imagery (Poké Ball trade dress) and capture patents

- What the concepts show: in `art/concepts/key-art-poster.png` a small creature sits **inside a transparent sphere with a gold band, held at the hero's side**. In `art/concepts/battle-screen-v2.png` the capsule nodes are glowing blue orbs on pedestals, and the "Orbis" unit is a blue sphere with a gold ring. None is the red-and-white, banded, button-centred Poké Ball design, but **"a creature carried in a hand-held sphere" is the core of that trade dress**, and the key art leans that way.
- Patents (a separate risk from trade dress): in September 2024 Nintendo and The Pokémon Company sued Pocketpair (*Palworld*) in Tokyo over Japanese patents covering **aiming and throwing an item to capture a creature**, a capture-probability indicator, and mounting creatures. Sources: https://www.pockettactics.com/palworld/lawsuit · https://www.gamingonlinux.com/2024/11/palworld-dev-details-the-patents-nintendo-and-the-pokemon-company-are-suing-for/ · https://dc.fortune.com/asia/2024/09/19/nintendo-pokemon-company-files-patent-lawsuit-palworld-developer-pocketpair . Later reports say the requested relief was narrowed in November 2025, Pocketpair patched out the disputed mechanics, and no court has ruled on the merits. Those reports come from low-quality secondary sites only, so treat them as **UNVERIFIED**: https://openclassactions.com/news/palworld-nintendo-patent-lawsuit-update-july-2026.php · https://www.notices.mce.ca.gov/2026/06/nintendos-palworld-lawsuit-is-falling-apart/ . **Aether Sigil has no throw-to-capture or capture-chance mechanic today. Keep it that way.** Monsters come from capsule nodes and rewards, not from throwing anything at a wild creature.

### 4c. Brand position

- AI-generated concept art (`art/concepts/`) isn't owned in the way human-made finals are. HANDOFF.md already says finals are drawn by a human; keep AI concepts out of store listings and marketing.
- A store listing that says "like Pokémon / Yu-Gi-Oh" uses others' marks; don't.

---

## Risk table

| # | Item | Risk | Why | Recommendation |
|---|---|---|---|---|
| 1 | Title **"Aether Sigil"** | **Low–Medium** | No exact game/app/title found; but "AETHER" has several live/pending game-software applications and "SIGIL" is claimed ™ by Romero Games. A combined mark is usually distinguishable, but this is unverified. | Run the manual trademark searches below (classes 9, 28, 41). If clear, file your own application early (US and your home market). |
| 2 | Subtitle **"Chronicles of the Capsule Realms"** / "Capsule Realms" | **Medium** | No exact collision, but "Capsule" + monsters + tactical board points at Konami's Capsule Monsters / Capsule Monster Chess, and the design data openly references that concept. | Drop "Capsule" from the **subtitle** and store name (e.g. "Chronicles of the Sigil Realms", "...of the Prism Realms"). In-game, consider renaming capsules ("seals", "cores", "vessels"). |
| 3 | Capsule visual (sphere holding a creature) | **Medium** | Key art shows a hand-held sphere with a gold band containing a creature; close to the idea behind Poké Ball trade dress. | Redesign before the art pass ([#29](https://github.com/Shadysmetools/aether-sigil/issues/29)): a non-spherical shape (crystal shard, sigil disc, prism), never two-tone with a band and a button, never thrown. |
| 4 | Capture mechanics (Nintendo patents) | **Low now / High if added** | No throw-to-capture or capture-probability UI exists. | Never add throw-to-capture or capture-percentage meters without a patent review. |
| 5 | Tower **"Crown of Ages"** | **Medium** | Exact name of a Steam strategy game (Lunvero Studio) due Q1 2027. | Rename the tower (and its art/map files `T12-*`). |
| 6 | Towers "Iron Labyrinth", "Obsidian Eclipse" | **Low–Medium** | Contained in other games' titles. | Fine as in-game locations. Don't use them as product, DLC or subtitle names. |
| 7 | Other 9 tower names | **Low** | No exact hits. | No action. |
| 8 | 12 champion names | **Low** | No exact full-name matches; single-word overlaps only. | Keep; avoid visual designs that echo the namesakes (e.g. Lux, Nyx, Quill). Reconcile the JSON/CSV champion lists first. |
| 9 | Monster names | **Low** | 0 exact collisions with Pokémon / Yu-Gi-Oh / Digimon (prior check); 3 contain "archen". | Rename the 3 "archen" names (Pokémon *Archen*). Human review of final names. |
| 10 | Trademark records overall | **UNVERIFIED** | Registers unreachable from here. | Manual searches below, then a lawyer. |

## Recommendations

1. **Before the M5 closed test** (a Play listing makes the name public): pick the final title/subtitle ([#31](https://github.com/Shadysmetools/aether-sigil/issues/31)). Preferred: keep "Aether Sigil", drop "Capsule" from the subtitle.
2. Rename **Crown of Ages** and reconcile the champion names in one pass ([#16](https://github.com/Shadysmetools/aether-sigil/issues/16)).
3. Redesign the capsule visual during M4 ([#29](https://github.com/Shadysmetools/aether-sigil/issues/29)); ban throw-to-capture mechanics in the design docs.
4. Run the manual trademark searches below and paste the results into this file.
5. **Have a trademark lawyer review** the title, the subtitle and the capsule design before launch (M7 requires a recorded sign-off). Budget for a US filing (and EU/UK if you sell there) once cleared.
6. Keep a dated record (screenshots) of these searches; it helps show good faith.

## Manual trademark search steps (not reachable from this environment)

Search each of: `AETHER SIGIL`, `AETHER`, `SIGIL`, `CAPSULE REALMS`, `CAPSULE REALM`, `CAPSULE MONSTER*`, `CROWN OF AGES`, and your final subtitle.

1. **USPTO (US):** https://tmsearch.uspto.gov → Search → enter the word mark → filter **Status: Live** → filter International Class **009** (game software), **041** (online games/entertainment) and **028** (toys/games). Open each hit in **TSDR** (https://tsdr.uspto.gov) to confirm owner, status and goods.
2. **WIPO Global Brand Database:** https://branddb.wipo.int → Brand name search → the same terms → filter Nice class 9 and 41 → check status "Active".
3. **TMview (EU and national offices):** https://www.tmdn.org/tmview → the same terms, classes 9 and 41.
4. **J-PlatPat (Japan, where Konami and Nintendo file):** https://www.j-platpat.inpit.go.jp → Trademarks → search "CAPSULE MONSTER", "カプセルモンスター" and "AETHER SIGIL".
5. **UK IPO:** https://trademarks.ipo.gov.uk → the same terms.
6. Re-run the store checks just before the listing goes live (Steam, App Store, Play, itch.io); names collide fast.

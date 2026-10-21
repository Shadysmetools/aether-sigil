# Aether Sigil: Chronicles of the Prism Realms - Story

> Narrative bible for the campaign. The dialogue the game plays lives in `data/story.json`; this document is the reasoning behind it.
> It adds to `data/AETHER_SIGIL_MASTER_GAME_BIBLE.json` and does not override it. Tower names, champions (`tower_boss`), opponents, opponent styles and stage dialogue all come from the bible as written.

---

## 1. World premise

**The Prism Realms** are hundreds of floating isles and continents scattered across one vast, fractured sky. Waterfalls pour off their edges into cloud. Prismatic towers rise from the largest realms, and across the upper sky runs **the crack**: a slow, dark tear that has been widening for as long as anyone remembers.

**The Aether Sigil** was a single twelve-faceted crystal that once held every realm under one sky. Each facet was a **prism** tuned to one part of the world: Nature, Fire, Water, Ice, Metal, Wind, Dark, Ancient, Space, Crystal and Aether, plus the twelfth, the **Mixed Prism**, which holds a little of every color and is kept at the Sunforge Throne. While the Sigil was whole, the realms drifted *together*, close enough that bridges and portals joined them.

**Why it broke.** An age ago one summoner, **Ari Zephyr**, held all twelve facets at once. Ari believed the realms suffered because they were too different, and tried to command the Sigil to make them one realm under one light. The Sigil refused. It broke rather than obey. The twelve prisms scattered, the realms began to drift apart, and the crack opened in the sky.

**Why the towers exist.** In grief, Ari asked eleven companions to guard the scattered prisms and to keep them apart, so that no one could ever misuse them, until a summoner came who was strong enough to carry them back up to the **Sunforge Throne**. Each companion raised a tower around one prism and became its **keeper**. Over the ages the keepers stopped meeting, then stopped talking, and finally forgot why they had shut themselves away. Most people now believe the towers *anchor* the realms. The truth, uncovered in Act 2, is that the sealed prisms keep them *apart*: the crack feeds on separation.

**Why keepers fight summoners.** A prism will only pass to a bond that has been tested. Each keeper's ten chambers are a trial of one idea (restoration, discipline, adaptation and so on). The keeper fights last, in the tenth chamber. Win, and the tower's reward, the **Sigil Core** (for example *Sigil Core: Nature Prism*), joins the challenger's **Player Sigil** as a new lit facet.

**How battles work in the fiction.** A Summoner never steps onto the board. They stand behind their **Player Sigil**, a crystal on a pedestal that is the side's commander, and their monsters fight on their behalf. Monsters are deployed from **capsule nodes**, the faceted **Prism Cores** that stand on node tiles. Opposing summoners command through their own **Symbol**; break it and the field is won, lose your Sigil and the field is lost. Monsters grow through **evolution** and, once they are strong enough (`progression.json` fusion `min_level`), two bonded monsters can **fuse** into one. The twelve element families sit in three rings: **Elemental** (Fire > Wind > Earth > Water > Fire), **Wild** (Thunder > Tech > Ice > Wood > Thunder) and **Mystic** (Dark > Arcane > Space > Light, with **Light and Dark as mutual rivals**). The Light-and-Dark rivalry is also the rivalry between Ari Zephyr and Cira Dawn.

Taglines in the fiction: *Collect. Command. Evolve. Conquer.* and *Awaken the world through what you summon.* The Summoner's own motto, from the character board: *Worlds call, and I answer.*

## 2. The protagonist: Elio of Lowmere

- **Name:** Elio. **Title:** Summoner. He is the dark-haired caped summoner on the key art.
- **Home:** **Lowmere**, a small edge-isle with a bell tower that drifts closer to the crack every year. Its skystone, the glowing rock that keeps an isle aloft, is going dark.
- **Motive:** to save Lowmere. He has heard the towers hold the prisms and the prisms hold the realms, so he sets out to win prisms and stop his home falling. At the start this is a *possessive* goal: take enough power and fix it.
- **Arc: from command to answer.** Each keeper shows Elio that a prism isn't taken, it's given to a bond that holds. He learns restraint (Varen), letting go (Zara), seeing through illusion (Cira), patience (Tarin), and finally that the Sigil was never meant to be held by one person (Silas, Sera). At the Throne he refuses the crown Ari built and reforges the Sigil as something the twelve keepers hold *with* him. His last line in the finale turns his motto into a plural: *"Worlds called. We answered."*
- **Voice:** plain, warm, quick, a little stubborn. Uses short tactical sentences in battle and asks honest questions out of it. Never boasts. Never fights directly: Elio commands, plans and trusts.

## 3. The companion: Pell

- A small white **prism-fox kit** with a gold plume of feathers, Light family. It is the little creature in the orb on the key art and character board.
- Pell hatched beside the Sigil shard that fell onto Maren's roof when Elio was six. Maren cut Elio's Player Sigil from that same shard, so Pell and the Sigil are bonded.
- **Speaks** through the Sigil in short third-person fragments ("Pell ready." "Pell sees two Kesses. One is fake."). Pell is the emotional barometer of every scene: brave, a little scared, always honest.
- Pell spots the truth the human characters miss (the fake Kess, "watch the Symbol"). In the epilogue Pell thinks it might be evolving. That is a hook for a post-game evolution, not a mechanic promise.

## 4. Recurring NPCs (exactly three speak)

| NPC | Role | Voice | Arc |
|---|---|---|---|
| **Maren Oake** | Lowmere's sigil-smith who raised Elio. She speaks to him across the realms through the Player Sigil. | Dry, practical, loving, rarely sentimental. | Sends him off. Introduces **fusion** in the story (tower 5 arrival). This is narrative only; the real gate is monster level. Reports Lowmere's state as the prisms gather. In the epilogue she reports the bell ringing on its own. |
| **Kess Varrow** | A rival summoner from another edge-isle, always one tower ahead or one floor behind. | Cocky, fast, funny, secretly kind. | Climbs for glory. Is beaten and humbled (frozen at tower 4, lost in illusions at tower 7). Becomes Elio's companion on the climb from tower 8 and asks for a friendly rematch in the epilogue. |
| **Pell** | Companion monster (see section 3). | Fragments, third person. | Grows braver each act. |

Every other speaker is either **Elio**, a **keeper** (the 12 `tower_boss` names) or the **Narrator**. The bible's 108 non-boss stage opponents (Ari Voss, Kael Nyx and others) keep their stage-dialogue lines and have **no** lines in `story.json`. The one exception is Silas Wren's cameo; Silas is also the T09 keeper (see section 6).

## 5. The antagonist force and the twist

- **The visible threat:** the crack in the sky, which pulls drifting isles like Lowmere toward it.
- **The apparent villain (Act 2):** Ari Zephyr. Cira Dawn reveals that Ari wants the twelve prisms brought to the Sunforge to be forged into *one crown, one realm, one light*.
- **The twist (tower 8, Sunken Archive):** Ari *is* the summoner who broke the Sigil. The towers were Ari's grief: a way to keep the pieces safe until someone could carry them back. And the separation itself is what feeds the crack (Renn's data, tower 5).
- **The real antagonist** is an idea, not a monster: *one person holding the whole sky*. Ari isn't evil, but Ari is about to repeat the original mistake with Elio's help.
- **Resolution:** Elio beats Ari on the board, then refuses to finish Ari's forging. A prism doesn't make one light; it splits light into every color (Sera's realization). All twelve keepers lay a hand on their prisms, and the Sigil reforms as a **ring of light** held in common. The crack begins to close.

## 6. The twelve keepers

`L10 style` is the keeper's `opponent_style` on their own tenth-chamber stage in the bible. Each `pre_boss` scene foreshadows it.

| # | Tower | Keeper | Theme (board) | L10 style | Personality | What they test | Arc resolution |
|---|---|---|---|---|---|---|---|
| 01 | Verdant Spire | **Lyra Quill** | Nature / Life / Restoration | rush attacker | Sunny, impatient, cheerful. Spring doesn't wait. | Whether the team *grows* under pressure (evolution). | Admits she has regrown her tower a hundred times and the sky still cracks: the break isn't down here. |
| 02 | Ember Bastion | **Varen Lux** | Fire / Warfare / Discipline | mobility specialist | Drill-commander, formal, dry humor. | Discipline: knowing when *not* to strike. | Respects Elio's restraint. Points the story upward toward the Sunforge Throne. |
| 03 | Tideglass Citadel | **Niko Ardent** | Water / Tides / Adaptation | counter-attacker | Laid-back, teasing, slippery. "I answer every attack." | Adaptation: dropping a plan when the tide turns. | Realizes the prisms heal *together*, not alone. |
| 04 | Frost Meridian | **Rhea Volt** | Ice / Isolation / Resilience | status-effect strategist | Terse, guarded, lonely. | Endurance under slow attrition, and whether a team protects its weakest. | Thaws. Reveals the keepers once met at one table and stopped talking. Ends Act 1. |
| 05 | Iron Labyrinth | **Renn Calder** | Machine / Logic / Perseverance | trap engineer | Methodical, literal, counts turns, kind. | Logic plus persistence. | His measurements prove the crack feeds on separation. "Someone old decided this." |
| 06 | Storm Crown | **Zara Nyx** | Air / Freedom / Change | summoner | Wild, laughing, restless. | Letting go: trusting monsters to act on their own. | "Freedom isn't chaos. It's trust." Names Ari Zephyr as her old teacher. |
| 07 | Obsidian Eclipse | **Cira Dawn** | Shadow / Illusion / Ambition | long-range sniper | Velvet, sardonic, sharp. The Dark rival of Ari's Light. | Seeing what's real. Aim at the Symbol, not the shadows. | Confesses her ambition was fear. Reveals Ari's plan. Arrives at the finale. |
| 08 | Sunken Archive | **Tarin Moss** | Knowledge / Memory / The Past | defensive fortress | Gentle, slow, bookish, immovable. | Patience against an unbreakable wall. | Reveals the twist (Ari broke the Sigil) and reminds Elio the past is a record, not a prophecy. |
| 09 | Astral Observatory | **Silas Wren** | Cosmos / Time / Possibilities | terrain controller | Serene, cryptic, gently funny. | Shaping the board, and choosing a future. | Sees Elio make the one move he couldn't foresee: "The Sigil was meant to be shared." |
| 10 | Crystal Sanctum | **Sera Vale** | Arcana / Purification / Ascension | resource thief | Exacting, cool, idealistic; half-agrees with Ari. | What remains when your resources are stripped. | "A prism makes light clear enough to show all its colors." Turns against Ari's single-light dream. |
| 11 | Rift Frontier | **Mako Reed** | Dimensions / Instability / The Unknown | rush attacker | Fast-talking, reckless, brave, grinning. | Acting without full information. | Has been holding up Lowmere himself. Agrees to bring the keepers to the Throne. |
| 12 | Sunforge Throne | **Ari Zephyr** | Light / Legacy / Transcendence | mobility specialist | Radiant, regal, weary, sincere. Carries an age of guilt. | Legacy: would Elio repeat Ari's mistake? | "I commanded. You answered." Lets go of the crown. "A legacy is only what you hand to others." |

**Silas Wren cameo.** The bible lists Silas Wren as the T03-L06 opponent as well as the T09 keeper. The story makes this deliberate: Silas comes down from his Observatory to Tideglass Citadel chamber six "to see if you're real". He beats Kess, and on arrival he tells Elio to meet him in chamber six (tower 3 arrival). At tower 9 he recalls the meeting.

## 7. Act structure

### Act 1 - The Climb Begins (towers 1-4: Verdant Spire, Ember Bastion, Tideglass Citadel, Frost Meridian)
Elio leaves Lowmere to win prisms. Kess races ahead. The keepers teach growth, discipline, adaptation and resilience, and each hints that the break is higher up. Lowmere's skystone flickers back to life as prisms gather. **Act 1 turn:** Rhea reveals the twelve keepers once sat at one table, and that locking the prisms away is why they stopped speaking. With four facets lit, Lowmere stops sinking, for now.

### Act 2 - What the Towers Hide (towers 5-8: Iron Labyrinth, Storm Crown, Obsidian Eclipse, Sunken Archive)
Maren urges Elio's team to try **fusion**. Renn's data shows separation feeds the crack. Zara names Ari Zephyr. Cira Dawn, Ari's Dark rival, reveals Ari's plan for one crown, one realm, one light, and accuses Elio of being Ari's courier. **Midpoint twist** at the Sunken Archive: Tarin reveals that Ari broke the Sigil an age ago, and the towers are Ari's grief. Kess, humbled, joins Elio.

### Act 3 - The Shared Sky (towers 9-12: Astral Observatory, Crystal Sanctum, Rift Frontier, Sunforge Throne)
Silas shows that in most futures Elio hands Ari the prisms and the sky breaks again, but there is one future he can't see. Sera turns from Ari's dream: a prism shows every color. At the Rift Frontier, Elio sees the crack up close and learns Mako has been holding Lowmere up. Elio asks the keepers to come to the Throne.

### Finale - The Sunforge Throne
Ari Zephyr fights across a gauntlet that combines every earlier tower's terrain (the bible's "multi-biome gauntlet"). Ari loses, and sees that Elio's monsters guarded the Sigil because they chose to. The eleven keepers arrive. Cira and Ari, Dark and Light, face each other as rivals who still show up. Elio asks every keeper to hold their prism *with* him. The Aether Sigil reforms as a ring of light, not a crown, and the crack begins to close.

### Epilogue
The realms still float apart, but now they drift together, and the towers' doors stay open. Lowmere's bell rings. Kess wants a rematch. Pell might be evolving.

**Playback order for the last scenes:** `towers[11].post_boss` -> `finale` -> `epilogue`. They are written to play back-to-back without repeating each other.

## 8. Tone guide for writers

- **Bright anime adventure with a melancholy undertow.** The sky is beautiful and broken. Stakes are personal (a home isle), never grimdark. No one dies on screen. Monsters are knocked out, never killed.
- **Keepers are mentors who play to win.** They're respectful, sporting and specific. Every keeper names their own test, and the bible's in-game lines already carry that voice ("It tests whether your team can adapt", "I lost the field, not the lesson"). Don't echo those lines verbatim in story scenes; they play during battle.
- **The Summoner never fights.** Elio plans, commands and trusts. No line has him strike, cast or take a hit. The Player Sigil takes the risk.
- **Mobile-readable.** One idea per line, at most 140 characters (the current maximum is 119). Prefer two short lines to one long one. Plain ASCII punctuation: straight quotes and "...", no em dashes.
- **Use the game's real terms and keep them distinct.** *Player Sigil* (the player's commander crystal), *Symbol* (the enemy's), *capsule node* / *Prism Core* (the deployment crystal on a node tile), *Sigil Core: X Prism* (a tower reward), *keeper* (a champion), *chamber* (a stage). Elements by family name: Wood and Thunder, not Nature and Lightning. Light and Dark are rivals.
- **Humor comes from character, not jokes.** Pell's fragments, Kess's bravado, Renn's turn counts, Tarin's biting shelves.
- **Keepers' voices at a glance:** Lyra exclaims; Varen orders; Niko teases; Rhea clips; Renn measures; Zara laughs; Cira purrs; Tarin muses; Silas wonders; Sera judges; Mako rushes; Ari confesses.
- **Never** let a line imply the player is trapped in another world or a game. Elio is a native of the Prism Realms.

## 9. Notes for the orchestrator and developer

- `data/story.json` follows the agreed schema exactly. The companion and NPC details live only in this document.
- Speakers in `story.json`: `Elio`, `Narrator`, the 12 `tower_boss` names, and the NPCs `Maren Oake`, `Kess Varrow` and `Pell`.
- **Known mismatch:** in the bible, every stage's `defeat` line (including Ari Zephyr's at T12-L10) reads "Climb higher and face the next keeper." At tower 12 there is no next keeper. Suggested fix, for whoever owns the bible: give T12-L10 a final-tower defeat line. This document doesn't edit the bible.
- The 2026-10-21 decisions in `docs/IP-CHECK.md` are respected: the subtitle is *Prism Realms* and the final tower is *Sunforge Throne*.

## IP guardrails

- The story is original. The keeper-and-tower structure is framed as *trials of an idea guarding a world-anchoring prism*. It is not a ranked circuit of arenas: there is no league, gym, badge or trainer language, and the rewards keep the bible's "Sigil Core: X Prism" wording. Prisms are never called crests or named after virtues, which avoids Digimon's Crests.
- Banned in story text: duel, "heart of the cards", shadow realm, pharaoh, millennium, chosen, digital world, and anything that echoes Yu-Gi-Oh!, Pokemon or Digimon catchphrases. No real people.
- No "trapped in a game world" premise, because that is the Capsule Monsters anime plot (see `docs/IP-CHECK.md` 4a). "Capsule" appears only as the mechanic term *capsule node*.
- The concept sheets still print the retired names "Capsule Realms" and "Crown of Ages". The story uses "Prism Realms" and "Sunforge Throne" throughout.
- Original names were checked in code against the 1,000 monster names, the 120 stage opponents' first names and surnames, and `game/data/reserved_names.json`: Elio, Lowmere, Maren Oake, Kess Varrow and Pell. All are clear.

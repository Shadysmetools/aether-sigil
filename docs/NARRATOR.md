# Vellum, the Narrator (character bible)

The Narrator is a character, not a caption. In data the speaker id stays `Narrator` (portrait slot
`portraits/narrator`, voice casting key, voice-key hashes, tests). On screen the name plate reads **Vellum**.

## In five lines

1. **Vellum, Archivist of the Aether Sigil.** A luminous archivist spirit bound to the Sigil. Painted
   in anime style matching the character design board: an androgynous young spirit with long silver-white hair and
   gold ribbon strands, amber eyes, a black-and-gold hooded mantle trimmed in parchment and glowing script, a broken
   halo (the Sigil, one gap) and a quill-shard at one shoulder. No legs: glyph-motes trail where they would be.
2. **Voice.** Dry, exact, fond of understatement and dashes; hates timers, loves surprises it did not write.
3. **Want.** To see this story end well. **Fear:** the first ending it wrote.
4. **Secret.** Vellum was the thirteenth keeper. An age ago it wrote the Sigil's whole future into its facets so
   nothing could ever break; a perfect, closed ending has no room to breathe, and the Sigil cracked. Vellum has
   narrated ever since, trying to steer toward an ending it did not write. It always says the break in the
   passive ("it was broken").
5. **Arc.** Control becomes trust. Early it calls Elio "the Summoner" and predicts; mid it slips and says
   "Elio"; late it admits it has stopped predicting. In the Sunforge it confesses, and at the end it puts the
   pen down and thanks him by name.

## Relationships

- **Elio.** The Sigil holder who keeps surprising it. Vellum's narration reaches him as the faint hum in his
  Player Sigil; he does not answer until the Sunforge ("Worlds called. We answered." is his reply).
- **Pell.** The only one who ever looks at the place Vellum floats. Vellum calls it "the small one" until Pell
  holds the Sigil with everyone else, then "Pell".
- **Maren, Kess.** Vellum respects Maren (a craftswoman who mends rather than writes) and finds Kess's
  fusion experiments unreasonably exciting.

## Foreshadowing, in order

Prologue: "Then it was broken" (passive). Tower 04 and 08 post-boss: Vellum is glad, then privately afraid of nine.
Tower 08 Sunken Archive: "I know these shelves." Tower 10: "Some of that sound is old. Some is mine." Tower 12
arrival: "The margin ends here." Finale: "I did not write this." / "I wrote the first ending, you see. It was perfect,
and so it broke." / "Thank you, Elio." Epilogue: "pen down, listening".

## Reactions (barks, `data/narrator.json`)

Every event has three lines, chosen by arc phase: early = towers 1-4, mid = 5-8, late = 9-12.
Events: `battle_start`, `first_crack` (first Vessel crack of the player), `big_hit` (a monster loses 40% of its
max HP, or a Sigil 25%, in one refresh; at most once per 3 rounds), `ko`, `vessel_broken`, `low_sigil_hp`,
`victory`, `defeat`, `evolution`, `fusion`. Plus one `arrival` and one `clear` line per tower (24). Each event
fires once per battle; when several fire at once the priority is low_sigil_hp > vessel_broken > ko > big_hit >
first_crack > battle_start. Tower 12 clear is the pen hand-over: "The pen is yours, Elio."
Reward drops are announced by Vellum ("Entered in the ledger, with some satisfaction: the {reward}. Yours.").

## Rules for writing Vellum

- One idea per line, under 150 characters in story scenes, under 70 in barks (the bubble is small).
- Dry first, tender second. One joke per scene at most; never mock the player's losses, reframe them
  ("Defeat is only a draft.").
- Verbal tics, used sparingly: "Noted." after a surprise; a dash aside; counting ("Twelve."); "Allow me."
- The break is always passive. Never write who broke it before the Sunforge.
- Elio is "the Summoner" until tower 6; barks from the mid phase may say "Elio". The ending says "Elio" with
  thanks. Do not use the player's name or second person ("you") for the player, only for Elio.
- No franchise vocabulary. Vellum knows the towers, keepers, prisms, Vessels, Bond and the Sigil.
- Every line needs a `mood` tag from `mood_expression` in `data/narrator.json` (dry, wry, wistful, rueful, solemn,
  uneasy, tense, fond, proud, delighted, wonder, hushed, stunned, resolute, ...). The tag chooses the face.
  Edit lines in `tools/narrator_lines.py` and re-run it (idempotent); it rewrites both story.json copies.

## Look and faces

Palette: parchment `#EBDDB6`, ink-violet `#2A1A4A`, Sigil gold `#F6C445`, crystal violet `#B15CFF`, amber eyes.
The game has seven expressions (neutral, amused, grave, awed, angry, determined, sad); Vellum's art covers four
(angry and sad use grave, determined uses neutral). Painted art resolves `portraits/narrator__<mood>` and
`characters/narrator` (prompts: `art/NARRATOR-PROMPTS.md`, job: `tools/art/jobs/narrator.json`). The old logo-emblem
restore at `art/ai/portraits/narrator.png` is a crystal crest, not a character, and is ignored
(`Assets.narrator_art`). Until the painted art lands Vellum is a name plate plus a glowing Sigil icon (`actor_art.gd` `draw_sigil_icon`); the game never draws procedural people.

## Voice (ElevenLabs)

Adult, androgynous-warm tenor; a measured, slightly dusty "reading to a room" timbre; unhurried pace with a
small lift on dry punchlines; light British received accent; never theatrical. Direction and settings live in
`game/audio/voices/CASTING.json` under `Narrator`. Dialogue blip: `text_blip` (falls back to `ui_tap`),
pitch per character from a stable name hash.

## How it appears

- **Scenes:** Vellum floats at centre stage above the dialogue panel (idle float, mood-driven face, glow pulse
  while it speaks), name plate in violet-gold. Every other speaker uses the same scene layer
  (`scene_dialogue.gd`, `character_actor.gd`): Elio and Pell on the left, rivals and champions on the right.
- **Battle and meta screens:** a small floating bubble (`bark_bubble.gd`). Never blocks input, dismisses itself,
  tap to skip, waits while a dialogue is open, static under reduced motion.
  Opt out: `aether_sigil/accessibility/narrator_barks = false`.

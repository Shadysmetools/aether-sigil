# Vellum (the Narrator): image-generation prompts

**Painted anime art is the deliverable.** Until it lands Vellum is only a name plate and a glowing Sigil icon: the game never draws procedural people.
Match `art/concepts/character-design-board.png`: polished anime key-visual finish, fine linework, glowing magic,
midnight navy + sigil gold + crystal violet, ornate black-and-gold coats with embroidery (the summoners' look),
tall elegant proportions. Vellum is the one non-human cast member: a luminous spirit. Character bible: `docs/NARRATOR.md`.

Machine-readable job: `tools/art/jobs/narrator.json` (one seed, 4207, and the same style reference for all five;
only the expression tags change):

```bash
python tools/art/comfy_gen.py tools/art/jobs/narrator.json     # after the current production run; GPU
```

## File names (what the game resolves)

Resolver chain for every speaker (`Assets.portrait_mood` / `Assets.full_body`), first hit wins:
`portraits/<id>__<mood>` -> `portraits/<id>` -> `characters/<id>` (full body) -> from-concepts crops -> a recoloured
champion portrait of the speaker's tower -> procedural figure.

| Image | File | Size | Notes |
|---|---|---|---|
| neutral | `art/ai/portraits/narrator__neutral.png` | 1024x1024 opaque | head and shoulders, eyes ~38% height, drawn cover-cropped into the frame |
| amused | `art/ai/portraits/narrator__amused.png` | 1024x1024 | |
| grave | `art/ai/portraits/narrator__grave.png` | 1024x1024 | also used for angry and sad |
| awed | `art/ai/portraits/narrator__awed.png` | 1024x1024 | |
| full body | `art/ai/characters/narrator.png` | 832x1216 transparent | the scene layer stands this character in the scene |

**Exact mood set used by the game: neutral, amused, grave, awed, angry, determined, sad.** Vellum ships four
(angry and sad fold to grave, determined to neutral). Every other character may ship any subset as
`portraits/<id>__<mood>.png` plus `characters/<id>.png`; moods they lack fall back to `portraits/<id>.png`.
The old logo-emblem restore at `art/ai/portraits/narrator.png` is a crystal crest, not a character: it is ignored by the
game and should be deleted once `narrator__neutral.png` exists (so `produce.py` does not count the slot done).

## Shared subject block (Animagine XL 4.0 tags, IP-Adapter style transfer 0.7 on `tools/art/refs/ref_elio.png`)

> 1other, androgynous, solo, upper body, portrait, looking at viewer, young ethereal archivist spirit, long flowing
> silver-white hair with thin gold ribbon strands, glowing amber eyes, delicate anime face, pale luminous skin, hooded
> mantle of black and gold with parchment scroll trim and glowing gold script, ornate gold embroidery, scroll rolls at
> the shoulders, broken golden halo ring floating above the head with one gap, floating glowing silver quill shard beside
> the shoulder, drifting glowing gold glyph motes, violet aura, polished anime key visual, deep navy blue starry background

Negative: scenery, landscape, multiple views, reference sheet, text, letters, lowres, bad anatomy, bad hands, cropped,
watermark, logo, chibi, photorealistic, 3d render, extra limbs.

## The five images

1. **neutral**: shared block + *calm composed expression, level amber eyes, closed mouth*.
2. **amused**: shared block + *amused expression, eyes curved into happy arcs, one raised eyebrow, faint wry smile*.
3. **grave**: shared block + *grave solemn expression, half-lidded amber eyes, eyebrows drawn together and slightly raised, downturned lips*.
4. **awed**: shared block + *awed expression, wide round amber eyes with bright highlights, raised eyebrows, small open mouth in wonder*.
5. **full body** (transparent): shared block with "full body, standing, robe tapering into drifting glyph motes, no feet"
   instead of "upper body, portrait", "simple background, white background" instead of the navy background, + calm expression.
   Style reference `ref_elio_full.png`, 832x1216.

Keep the face identical across 1-4 (same seed, same hair, same halo and quill): check the four side by side before shipping.
No franchise names, character names or artist names in any prompt. Ownership note from `art/PROMPTS.md` applies: a human
artist redraws the finals.

## Until the art exists

Cast with art (Elio, Pell, the champions: `art/ai/portraits/*`, from-concepts crops) show those anime portraits.
Stage rivals, Maren and Kess without art borrow their tower champion's portrait with a stable per-name recolour.
Vellum has no anime stand-in: a name plate and a glowing Sigil icon show until `narrator__*.png` lands. Any speaker with no art and no champion to borrow is a name plate only.

# Aether Sigil: the publishing case

**Game:** Aether Sigil: Chronicles of the Prism Realms. **Prepared:** 2026-10-21, by a game business analyst for Shady (solo founder). **Deck:** `docs/pitch/index.html`.

> **Read this first.** Revenue figures here are **illustrative scenarios built on labelled assumptions, not a forecast**. Market figures cite their sources by number (see Sources at the end). Where a figure could not be verified on an opened page, it is labelled UNVERIFIED or left out. IP notes come from `docs/IP-CHECK.md`, which is a desk search, not legal advice.

## 1. What the game is

A 12×12 isometric tactical monster-board game for iPhone and Android, built in Godot 4.7.2 (GDScript). Players deploy a squad of 4 monsters from their Sigil onto spawn tiles and captured Prism (capsule) nodes. They use high ground, water, bridges and line of sight, and win by destroying the rival's Symbol (or holding 3 relic nodes on some stages).

- **Content (data):** 120 stages in 12 towers; 1,000 monsters defined in data, in 12 element families (16 element names); 486 dialogue lines.
- **Progression:** XP and levels, evolution at Lv16 and Lv36 (3 forms per line), deterministic fusion of 2 monsters (both Lv10+), and a versioned local save.
- **Quality bar:** `bash game/run_tests.sh` reports **18,489 pass / 0 fail** across 6 suites. The gate was proven by a deliberate break.
- **Balance:** in AI-vs-AI simulation over all 120 stages, a progressing default squad wins 50% (every tower 30–70%). Without progression it wins 8%.
- **Art:** 365 original placeholder files in `art/generated/`, plus AI concept sheets in `art/concepts/` (reference only).

**Not yet true (said plainly):** no phone build has been run yet (Android SDK, export preset and device test are next). No milestone is formally closed (closing requires video and device evidence). All visuals are placeholder or AI concept. There has been no human playtest. The concept sheets predate the 2026-10-21 decisions and still show the retired subtitle ("Capsule Realms") and tower name ("Crown of Ages").

## 2. Market

| Metric | Figure | Source |
|---|---|---|
| Global games revenue 2025 | $201.6B (+9.1%) | Newzoo [1] |
| Mobile games 2025 / 2026 forecast | $113.3B (+10.7%) / $121.1B | Newzoo [1] |
| Console / PC 2025 | $44.7B / $43.6B; 2025–2028 CAGR 5.1% | Newzoo [2] |
| Store IAP game spending 2025 | $81.75B (+1.3%); downloads 50.41B (−7.2%) | Sensor Tower [4] |
| Strategy share 2024 | 21.4% of mobile game spending, 4% of downloads | Sensor Tower [3] |
| Strategy vs RPG 2024 | $17.5B (+16.2%) vs $16.8B (−17.3%) | Sensor Tower [5] |
| Strategy 2025 | $20.2B; RPG declining | Sensor Tower [4] |
| Players | Average age 41; 51% male / 48% female; 55% play on mobile (22 countries) | ESA 2025 [6] |
| Anime-style demand | Japan = 49% of revenue of the top 50 anime-style mobile games (Jan–Jul 2024) | Sensor Tower [7] |

**Reading:** mobile is the largest platform, and spending keeps growing while installs fall. Players cost more to acquire, so a clear hook and organic channels matter. Strategy earns heavily from a small share of installs. **Gaps:** no verified public figure for the tactics or monster-collector sub-genres, or for strategy-player demographics. Sensor Tower and Newzoo measure different things (store IAP vs broader revenue).

## 3. Comparable titles

| Title | Type | Public figure | Period | Source |
|---|---|---|---|---|
| Fire Emblem Heroes | Tactics, gacha | >$1B player spending | Feb 2017 – Jun 2022 | Sensor Tower [8] |
| Arknights | Tactics / tower defence, anime gacha | >$1.1B worldwide | Jan 2020 – Nov 2023 | Sensor Tower [9] |
| Honkai: Star Rail | Turn-based RPG, anime gacha | >$2B gross on mobile | Apr 2023 – Mar 2025 | AppMagic [14] |
| Pokémon TCG Pocket | Monster collecting (cards) | $1.3B | First year to Oct 2025 | AppMagic [12] |
| Pokémon Masters EX | Monster collecting, gacha | ~$75M | First year to Sep 2020 | Sensor Tower [11] |
| Monster Hunter Now | Monster hunting, AR | >$100M gross | < 3 months, 2023 | PocketGamer.biz [13] |
| Teamfight Tactics (mobile) | Auto-battler | 3.6M downloads, >$1.2M gross | First 7 days, Mar 2020 | Sensor Tower [10] |
| Balatro (mobile) | Premium indie, no IAP or ads | >$9.3M net | Sep 2024 – Jan 2025 | AppMagic [15] |
| Coromon | Indie monster collector (PC) | >100,000 units | First 3 months, 2022 | Developer [17] |
| Temtem | Indie monster collector (PC) | 500,000 copies (headline only) | First month of Early Access, 2020 | Press, partly verified [18] |

Balatro's 5M sales across all platforms is a separate figure. [16] Most large figures are gacha (paid random draws), which this design rules out; treat them as proof of the audience, not as a benchmark. Into the Breach, Cassette Beasts, Monster Sanctuary and Super Auto Pets had no verified figures and are excluded.

## 4. Monetization options

| Option | Pros | Cons | Regulation / policy |
|---|---|---|---|
| Premium unlock (first tower free) | One fair price. No pay-to-win. Fits a 120-stage campaign. The free tower acts as the demo. | Mobile players resist paying up front, and income stops once the campaign is sold. | Low risk. Name the price clearly on the store page. |
| Cosmetics (skins, board themes, Sigil styles) | Doesn't touch balance. Fits anime collectors. Keeps earning after launch. | Needs extra art for every item. Small at first. | Sell named, fixed items only. Never a random draw. |
| Season / battle pass | Rewards regular play and gives a reason to return. Found in about 60% of the top 20% grossing mobile games (2022). | Needs live-ops content every season, which is hard for a solo founder. | Fine when every reward is listed up front. Decide after launch. |
| Ad-supported free tier (rewarded ads) | Earns from players who never pay. Rewarded ads are opt-in. | Ad revenue per user is low, and ads cheapen a premium anime look. eCPM is unverified, so ads are left out of the model. | Needs privacy and consent work (data-safety forms, ATT). |
| Paid loot boxes / gacha | This is where the biggest grossers earn. | Rejected by design: pay-to-win pressure and legal exposure. | Belgium: illegal gambling (2018). Netherlands: a 2022 court overturned the EA penalty. China: draw odds must be published (2017). Apple and Google: odds must be disclosed. |

Sources: Belgium [24]; Netherlands [25]; China [26,27]; UK has not regulated loot boxes [28]; Apple 3.1.1 [22]; Google Play odds disclosure [23]; battle-pass adoption [31]. The rewarded-ad eCPM and ARPDAU benchmarks were UNVERIFIED (numbers sit in charts or gated reports), so ads are left out of the model.

**Recommendation:** Tower 1 free, one premium unlock for towers 2–12, and cosmetic-only IAP (issue #40). A season pass waits for data. **Capsules stay earn-only:** selling random capsule contents would be a loot box.

## 5. Store fees

- Apple Small Business Program: **15%** for developers with up to $1M proceeds in the prior year [19]; standard 30% (Apple states proceeds of 70%/85%) [20].
- Google Play: **15% on the first $1M** a year in markets still on the old schedule. In the **US, EEA and UK from 2026-06-30, and Australia and Japan from 2026-09-30**, a new schedule applies. Its first-$1M row reads **10% service fee + 5% billing fee (15% total)**. The 'Standard' row, read as earnings above $1M, is 20% + 5% for new installs and 25% + 5% for existing installs, with 5 points less in Play Games Level Up [21]. The table layout is ambiguous (the first-$1M cell spans all columns), and another reading is 20% + 5% for new installs. Confirm before launch.
- Steam (later): $100 per app (recoupable after $1,000 adjusted gross) [33]; 30%, 25% above $10M, 20% above $50M [34].
- **Model assumption:** 15% fee on both stores while under $1M a year. The scenario table also shows net at 30% as a worst case.

## 6. Costs

| Year-one line | Low | High | Basis |
|---|---:|---:|---|
| Store accounts | $124 | $124 | $25 Google once + $99/yr Apple [49,50] |
| 2D creature art | $3,200 | $24,000 | 400–800 h (assumption) × $8–30/h [53] |
| 2D animation | $2,250 | $12,000 | 150–300 h (assumption) × $15–40/h [54] |
| Music | $11,200 | $17,304 | 14 tracks × ~2 min (assumption) × $400–618 per finished minute [52] |
| Sound design | $360 | $2,400 | 40–80 h (assumption) × $9–30/h [55] |
| Marketing basics | $500 | $5,000 | Press kit, trailer edit, small test ads (assumption) (assumption) |
| **Outsourced polish, total** | **$17,634** | **$60,828** | sum |
| **Lean path** | **$624** | **$2,124** | store + marketing; Shady draws the finals; CC0 audio |

Minimum cash to reach both stores: $25 + $99 = $124 in year one, plus access to a Mac with Xcode 26 (or Codemagic's 500 free macOS minutes a month) [51,56]. Freelancer.com rates skew low, so read them as a floor. Hours are assumptions. The trademark lawyer is not costed (get quotes).

## 7. Timeline

| Milestone | Scope | Status (2026-10-21) | Duration |
|---|---|---|---|
| M1 | Battle loop slice | Code done; evidence pending | 1–3 wk* |
| M2 | 120 stages, progression, save | Mostly done | 2–4 wk* |
| M3 | Squad, evolution, fusion, Symbol, Prism Core | Partly done | 4–8 wk* |
| M4 | Art pass: tiles, units, VFX, audio | Not started | 3–6 mo* |
| M5 | Android closed test, 12 testers × 14 days | Blocked on title and package ID | ~3 wk (sourced) |
| M6 | iOS TestFlight (needs a Mac and Xcode 26) | Not started | 1–3 wk* |
| M7 | Launch: listings, ratings, privacy, cosmetic IAP | Not started | 2–4 wk* |

Only the M5 duration is sourced (12 testers × 14 days, about 3 weeks) [48]. Durations marked * are **estimates**. The roadmap has no calendar dates. Summing the estimates gives launch in about 4–8 months from the start of M4 if M4–M7 run in sequence (19–36 weeks), or roughly 6–12 months from today including the M1–M3 close-out (estimate). The title must be final before M5.

## 8. Scenario model (illustrative, not a forecast)

**Model:** Tower 1 free → one unlock at **$4.99** for towers 2–12 → cosmetic IAP. Gross = downloads × unlock rate × price + downloads × cosmetic-buyer rate × average cosmetic spend. Net = gross × (1 − fee). Net ignores VAT/GST deducted by stores, refunds and income tax. No paid user acquisition in any scenario.

| Scenario | Downloads (yr 1) | Unlock rate | Cosmetic buyers × avg | Unlock gross | Cosmetic gross | Gross | **Net @15%** | Net @30% |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Conservative | 10,000 | 2% | 0.5% × $3 | $998 | $150 | $1,148 | **$976** | $804 |
| Base | 50,000 | 4% | 1.0% × $4 | $9,980 | $2,000 | $11,980 | **$10,183** | $8,386 |
| Optimistic | 250,000 | 6% | 2.0% × $5 | $74,850 | $25,000 | $99,850 | **$84,872** | $69,895 |

**Assumptions (all labelled):** downloads, unlock rate, price and cosmetic spend are assumptions. Anchors: only 1.83% of mobile players make any IAP (Unity 2024) [30]. Median D1 retention is about 22% and D7 just under 4% (GameAnalytics 2026) [29]. A paid unlock after a free tower could convert above the F2P payer rate, but this is unproven. **Against year-one costs** (lean $624–$2,124; outsourced $17,634–$60,828): Conservative ($976 net) covers only the low end of the lean path; Base ($10,183 net) covers the whole lean path, but not outsourced polish; Optimistic ($84,872 net) covers even the high end of outsourced polish.

## 9. Benefits of publishing

- **Revenue potential.** Illustrative year-one net of $976 / $10,183 / $84,872. Small at the low end, but every extra download earns at near-zero marginal cost. Balatro shows the upside for a premium game on mobile. [15]
- **An owned IP and brand.** 1,000 original monsters with 0 exact name collisions against Pokémon, Yu-Gi-Oh and Digimon, 12 towers, 12 champions and 486 dialogue lines, all held in one data bible. A live game makes the brand real enough to extend: Steam PC (Steam Direct costs $100 [33]), a sequel, an art book, plushies and merch.
- **Portfolio and credibility.** A shipped game on two stores, with public ratings and download counts, is evidence a publisher or investor can check. A prototype isn't. Publishing deals with an advance averaged a 55/45 split in the developer's favour in GameDiscoverCo's sample, and traction is what gets you those terms. [40]
- **Community and data.** Real funnels (tutorial, stage drop-off) replace AI-vs-AI guesses. The balance curve is currently tuned on simulations only. Discord and devlogs build a group that wishlists the PC version and brings launch-day reviews. [45]
- **The AI-agent pipeline as an asset.** One founder plus agents produced 18,489 green checks, a reproducible balance script, an idempotent decisions script and 41 issues with acceptance criteria. Shipping proves the method works, and the method carries over to the next title. (The studio framework is third-party MIT, so the asset is the process, not the tool.)
- **Low capital at risk.** $124 in cash reaches both stores. The lean path is about $624–$2,124. Spend can grow only after the data says yes: soft launch first, art budget second.

## 10. Risks and mitigations

| Risk | Level | Evidence | Mitigation |
|---|---|---|---|
| IP and trademark | Med | No exact-title collision was found, but 'AETHER' appears in several pending game-software trademark applications (unverified: seen only in search snippets), and Romero Games claims 'SIGIL' as a trademark. [58] The capsule and creature-in-a-sphere look echoes Konami's Capsule Monsters and the Poké Ball. [59] No register search has been done. | Subtitle already changed ("Capsule" dropped), Crown of Ages renamed, the 3 "archen" names fixed. Before M5: run the manual USPTO/EUIPO/J-PlatPat searches, get a lawyer's review (#31) and redesign the capsule (#29). |
| Discoverability and competition | High | Installs fell 7.2% in 2025 while spending grew. [4] Liftoff/Singular found casual games averaging $1.41 per install on iOS and $0.14 on Android, and called RPG and strategy installs 'comparatively high' without giving a number. [32] The genre is led by $1B gacha titles. | Lead with a clear hook (chess-like monster tactics, no gacha). TikTok devlogs and Discord before launch, soft launch to measure, and Steam later for a second audience. |
| Art quality vs AI art ownership | High | Purely AI-generated images aren't copyrightable in the US. Human authorship is required. [35,36] Steam requires AI-content disclosure. [37] Every current visual is AI concept or placeholder. | Shady draws the finals, or we hire illustrators. Keep a licence log (#30). Keep AI concepts out of the store. Shrink the launch art scope (#24) to what's needed. |
| Balance and data quality | Med | There are 353 contradictions in the generated bible, handled by rule fallbacks. Rarity doesn't scale stats (it explains 0.5% of power). Win rates come only from AI-vs-AI runs. | The fallbacks are listed and covered by tests. Add rarity multipliers, then run a human closed test (M5) and use funnel analytics (#39) before tuning further. |
| Solo-founder bandwidth | High | One person holds the store accounts, signing keys, legal work, final art and community. A season pass would add constant live-ops on top. | Agents handle code and tests. Launch with a finished campaign and no live-ops promises. Hire for art and audio only when the data justifies it. |
| Store review and platform rules | Med | Google's 12-tester × 14-day gate. iOS needs Xcode 26 on a Mac. Privacy labels, age ratings and IAP review are still ahead. [48,51] | Recruit testers early from Discord. Use Codemagic or rent a cloud Mac. Fill in the M7 checklist (#37, #38, #40) before submitting. |

## 11. Go-to-market

1. **Closed test:** 12 testers × 14 days (M5) [48], recruited via Discord. Measure the tutorial and Tower 1 funnels.
2. **Soft launch** in an English-speaking test market. Canada (72%), Australia (56%) and the Philippines (44%) were the most used in a 2016 study [38]. The Philippines is now in about half of soft launches, with installs under $0.50 [39].
3. **Global launch** only if D1/D7 meet the median benchmarks (~22% / ~4%) [29].
4. **Community:** Discord (testers, launch-day reviews) [45]. TikTok devlogs (one 571k-view video brought about 2,900 wishlists in a case study) [44].
5. **Press kit:** human-made key art, a 30–60 s trailer, a fact sheet (120 stages, 1,000 monsters, no loot boxes) and the founder-plus-AI-agents story.
6. **Steam PC later:** $100 Steam Direct [33]; Next Fest 3× a year, one per game [47]; median wishlist conversion about 0.15× (0.10× above $10) [46]. Disclose AI use where it applies [37].

## 12. Publisher vs self-publish

| Dimension | Self-publish | With a publisher |
|---|---|---|
| Revenue share | 100% after store fees | No-advance deals averaged ~71% to the developer. With a $100k–500k advance, ~55/45 to the developer. Some recoup the advance +15% first, then split 50/50. [40] |
| Cash up front | None: self-funded ($124 minimum) | An advance can pay for the art pass |
| Marketing and user acquisition | Founder's time and small tests | The publisher's channels, press contacts and UA budget |
| Control and IP | Full control, IP kept | Depends on the contract. Read the IP, term and recoup clauses. |
| Speed | As fast as Shady and the agents can go | Contracting takes time, plus the publisher's milestone gates |
| Platform programmes | Apple Arcade takes pitches (no ads, no IAP). [41] Google Play Pass is invitation-only, with royalties set by Google's own algorithm. [42] | Arcade payouts are reported to be falling (anonymous sources). [43] |

**Recommendation:** self-publish the mobile soft launch (low capital, and it produces the data publishers ask for). Then pitch publishers for the art pass, global launch and Steam port, from evidence. The split data is a small 2020 sample. Use it as a negotiating range, not a quote.

## Sources

1. PocketGamer.biz: Newzoo, global games revenue passes $200bn in 2025; mobile $113bn (2026-06-19): https://www.pocketgamer.biz/global-games-revenue-surpasses-200bn-for-the-first-time-mobile-generates-113bn/
2. GameDev Reports: Newzoo 2025 market, console/PC split and 2028 forecast: https://gamedevreports.substack.com/p/newzoo-gaming-market-surpassed-200
3. Sensor Tower: State of Mobile Gaming 2025 (2024 data): https://sensortower.com/blog/state-of-mobile-gaming-apps
4. GameDev Reports: Sensor Tower State of Gaming 2026 (2025 data): https://gamedevreports.substack.com/p/sensor-tower-state-of-gaming-2026
5. GameDev Reports: Sensor Tower mobile market in 2025 (2024 genre revenue): https://gamedevreports.substack.com/p/sensor-tower-mobile-market-in-2025
6. GameDev Reports: ESA Global Video Games Report 2025: https://gamedevreports.substack.com/p/esa-global-video-games-report-2025
7. Sensor Tower: 2024 Japan mobile gaming market insights (anime-style games): https://sensortower.com/blog/2024-japan-mobile-gaming-market-insights
8. Sensor Tower: Fire Emblem Heroes passes $1B: https://sensortower.com/blog/fire-emblem-heroes-one-billion-revenue
9. Sensor Tower (JP): Arknights and Yostar: https://sensortower.com/ja/blog/arknights-and-yostar-strengths
10. Sensor Tower: Teamfight Tactics mobile first week: https://sensortower.com/blog/teamfight-tactics-mobile-first-week
11. Sensor Tower: Pokémon Masters first-year revenue: https://sensortower.com/blog/pokemon-masters-revenue-75-million
12. WN Hub (AppMagic): Pokémon TCG Pocket $1.3B first year: https://wnhub.io/news/analytics/item-49183
13. PocketGamer.biz: Monster Hunter Now $100M in under three months: https://www.pocketgamer.biz/news/83019/monster-hunter-now-is-a-roaring-success-making-100-million-in-under-three-months/
14. PocketGamer.biz (AppMagic): Honkai: Star Rail passes $2bn on mobile: https://www.pocketgamer.biz/honkai-star-rail-rockets-past-2bn-on-mobile-in-under-two-years/
15. WN Hub (AppMagic): Balatro mobile net revenue: https://wnhub.io/news/investment/item-46849
16. Pocket Gamer: Balatro five million sales: https://www.pocketgamer.com/balatro/five-million-sales
17. Gamespress: Coromon 100,000 PC units: https://gamespress.com/Coromon-Lands-Critical-Hit-Release-Date-for-Nintendo-Switch-on-July-21
18. Windows Central: Temtem passes 500,000 copies (headline only seen): https://www.windowscentral.com/temtem-passed-500000-copies-sold-roadmap-way
19. Apple: App Store Small Business Program: https://developer.apple.com/app-store/small-business-program/
20. Apple: Auto-renewable subscriptions (70% / 85% proceeds): https://developer.apple.com/app-store/subscriptions/
21. Google Play Console Help: service fees (incl. 2026 schedule): https://support.google.com/googleplay/android-developer/answer/112622
22. Apple App Review Guidelines 3.1.1 (loot-box odds): https://developer.apple.com/app-store/review/guidelines/
23. Google Play policy: randomized items odds disclosure: https://support.google.com/googleplay/android-developer/answer/9858738
24. Belgian Gaming Commission loot-box report 2018 (English, hosted by Skadden): https://www.skadden.com/-/media/files/publications/2019/08/video-gaming-egaming-law-update/fn12_onderzoeksrapportlootboxenengelspublicatie.pdf
25. NOS: Raad van State ruling on EA / FIFA packs (2022-03-09): https://nos.nl/l/2420438
26. Mondaq: China Ministry of Culture online game regulation (2016/2017): https://www.mondaq.com/china/gaming/558200/china-ministry-of-culture-released-new-regulation-on-online-game-operation
27. Mondaq: China proposes new online gaming regulations (Dec 2023 draft): https://www.mondaq.com/china/gaming/1415594/china-proposes-new-regulations-for-online-gaming
28. UK Government response on loot boxes (2022): https://www.gov.uk/government/consultations/loot-boxes-in-video-games-call-for-evidence/outcome/government-response-to-the-call-for-evidence-on-loot-boxes-in-video-games
29. GameAnalytics 2026 Mobile & PC Benchmarks (PDF mirror): https://investgame.net/wp-content/uploads/2026/01/2026-01-27-2026-mobile-pc-benchmarks_compressed.pdf
30. PocketGamer.biz: under 2% of mobile gamers make an IAP (Unity 2024 report): https://www.pocketgamer.biz/less-than-2-of-mobile-gamers-make-an-in-app-purchase/
31. PocketGamer.biz: GameRefinery on battle passes in top-grossing games (2022): https://www.pocketgamer.biz/news/78958/gamerefinery-battle-pass-implementation-in-top-grossing-mobile-games/
32. Liftoff / Singular 2025 Casual Gaming Apps Report: https://liftoff.ai/?p=34267
33. Steamworks: Steam Direct app fee: https://partner.steamgames.com/doc/gettingstarted/appfee
34. MCV/DEVELOP: Valve's revenue-share tiers: https://www.mcvuk.com/business-news/valves-new-steam-distribution-agreement-lets-big-game-devs-keep-more-of-their-profits/
35. US Copyright Office: Copyright and AI, Part 2 (Copyrightability) announcement: https://www.copyright.gov/newsnet/2025/1060.html
36. IPWatchdog: D.C. Circuit upholds human authorship (Thaler v. Perlmutter): https://ipwatchdog.com/2025/03/24/d-c-circuit-upholds-human-authorship-requirement-thaler-v-perlmutter/
37. Steamworks: Content Survey (AI disclosure): https://partner.steamgames.com/doc/gettingstarted/contentsurvey
38. PocketGamer.biz: soft-launch trends (2016): https://www.pocketgamer.biz/soft-launch-trends/
39. GameAnalytics: soft launch guide (updated 2025): https://www.gameanalytics.com/blog/soft-launch-guide
40. GameDiscoverCo: what makes for a good game publishing deal (2020): https://newsletter.gamediscover.co/p/what-makes-for-a-good-game-publishing
41. Apple: Apple Arcade for developers: https://developer.apple.com/apple-arcade/
42. RevenueCat docs: Google Play Pass: https://www.revenuecat.com/docs/platform-resources/google-platform-resources/google-play-pass
43. Mobilegamer.biz: inside Apple Arcade (2024): https://mobilegamer.biz/inside-apple-arcade-axed-games-declining-payouts-disillusioned-studios-and-an-uncertain-future/
44. How To Market A Game: TikTok tips for indie games (2022): https://howtomarketagame.com/2022/02/07/seven-great-tips-for-marketing-your-indie-game-on-tiktok/
45. MCV: Mike Rose on using Discord to sell your game (2018): https://www.mcvuk.com/business-news/no-more-robots-mike-rose-on-why-you-should-use-discord-to-sell-your-game/
46. GameDev Reports: GameDiscoverCo, the state of Steam (2025 wishlist conversion): https://gamedevreports.substack.com/p/gamediscoverco-the-state-of-steam
47. Steamworks: Steam Next Fest: https://partner.steamgames.com/doc/marketing/upcoming_events/nextfest
48. Google Play Help: testing requirements for new personal accounts (as cited in RESEARCH-open-source.md, retrieved 2026-10-20): https://support.google.com/googleplay/android-developer/answer/14151465
49. Google Play Console registration fee (as cited in RESEARCH-open-source.md, retrieved 2026-10-20): https://support.google.com/googleplay/android-developer/answer/6112435
50. Apple Developer enrollment (as cited in RESEARCH-open-source.md, retrieved 2026-10-20): https://developer.apple.com/support/enrollment/
51. Apple upcoming requirements, Xcode 26 (as cited in RESEARCH-open-source.md, retrieved 2026-10-20): https://developer.apple.com/news/upcoming-requirements/
52. GameSoundCon 2025 audio survey (as cited in RESEARCH-open-source.md, retrieved 2026-10-20): https://www.gamesoundcon.com/post/gamesoundcon-game-audio-industry-survey-2025
53. Freelancer.com game-art profiles (as cited in RESEARCH-open-source.md, retrieved 2026-10-20): https://www.freelancer.com/hire/game-art
54. Freelancer.com 2D-animation profiles (as cited in RESEARCH-open-source.md, retrieved 2026-10-20): https://www.freelancer.com/hire/2d-animation
55. Freelancer.com sound-design profiles (as cited in RESEARCH-open-source.md, retrieved 2026-10-20): https://www.freelancer.com/hire/sound-design
56. Codemagic pricing (as cited in RESEARCH-open-source.md, retrieved 2026-10-20): https://docs.codemagic.io/billing/pricing/
57. Pocket Tactics: Nintendo v. Pocketpair patent suit (as cited in IP-CHECK.md): https://www.pockettactics.com/palworld/lawsuit
58. Wikipedia: Sigil (mod), Romero Games (as cited in IP-CHECK.md): https://en.wikipedia.org/wiki/Sigil_(mod)
59. Yugipedia: Yu-Gi-Oh! Capsule Monster Coliseum (as cited in IP-CHECK.md): https://yugipedia.com/wiki/Yu-Gi-Oh!_Capsule_Monster_Coliseum

Pages were opened by the research team on 2026-10-21 unless marked "as cited in" (retrieved by the project docs on 2026-10-20). Project facts: README.md, HANDOFF.md, docs/ROADMAP.md, docs/IP-CHECK.md, docs/BALANCE-REPORT.md, RESEARCH-open-source.md, game/data/game_rules.json.

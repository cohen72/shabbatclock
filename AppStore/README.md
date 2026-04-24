# App Store Listing — Shabbat Clock

App Store Connect copy for both locales. Each file corresponds to a specific field in ASC.

## Folder layout

```
AppStore/
├── README.md              ← this file
├── en-US/
│   ├── name.txt           ← 30 char limit
│   ├── subtitle.txt       ← 30 char limit
│   ├── promo.txt          ← 170 char limit (editable anytime without resubmit)
│   ├── keywords.txt       ← 100 char limit, comma-separated, no spaces
│   └── description.txt    ← 4000 char limit
└── he/
    ├── name.txt
    ├── subtitle.txt
    ├── promo.txt
    ├── keywords.txt
    └── description.txt
```

## ASO strategy notes

- **Spelling coverage:** App name is "Shabbat Clock" and subtitle uses "Shabbos" — both spellings indexed for free without repeating words.
- **Keywords rule:** Apple indexes title + subtitle automatically. Never repeat those words in the keywords field — waste of characters.
- **Promo text** can be updated anytime without app review. Use it for seasonal messaging later (e.g., "Get ready for the High Holidays").
- **Competitors identified:** Shabbat Alarm Clock (Gerber), Shabbos Clock, Chabat Clock, Smart Alarm: Shabbos clock, MyZmanim, Ultimate Zmanim, Hebrew Calendar, YidKit. Our wedge: real system alarms (AlarmKit) + zmanim + Shabbat dashboard in one app — no competitor combines all three.

## City placeholders

The description mentions "from Jerusalem to Teaneck" (en) and "מירושלים עד תל אביב" (he). Swap for whichever cities fit your users — Lakewood, Monsey, Boro Park, Bnei Brak, Modiin, etc.

## What's still missing

- Screenshot copy (captions + feature callouts)
- "What's New" text for each version
- App Review notes (reviewer instructions for testing premium)
- Privacy nutrition labels
- Subscription localized display names + descriptions (ASC subscriptions section, separate from main listing)

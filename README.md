# Held 2.4.4

Held is an iPhone-first SwiftUI collector app for identifying, researching, and organizing trading cards, sports cards, coins, wine, and other labeled collectibles.

The 2.0 rebuild turns the original single-screen search prototype into a complete collector experience:

- Premium scan-first navigation and a cohesive dark visual system
- One-tap category tiles on Home that open the scanner in the selected mode
- On-device camera OCR using AVFoundation and Apple Vision
- Pokémon English / Japanese scan switch, with English selected by default
- Low-light collector-number rescue pass with footer upscaling and multi-frame agreement
- Full Pokémon title recognition for ex, EX, V, VMAX, VSTAR, V-UNION, GX, BREAK, LV.X, LEGEND, Radiant, Mega, Tera, and classic name modifiers
- Exact-printing search by card name, collector number, rarity, and game
- Persistent personal collection with quantity, condition, purchase metadata, and known value
- Dashboard with collection value, game coverage, and recent additions
- Rich card detail pages with explicit set/number verification and third-party market sources
- CardSight player-name catalogue search with up to 40 real sports-card candidates per query
- Multi-pass sports-card OCR for player, year, brand, set, card number, serial stamp, parallel, rookie and autograph clues, including tiny and vertical text
- Coin OCR plus optional Numista catalogue matching
- Wine-label OCR plus Open Food Facts catalogue matching
- Flexible collectible OCR for maker, item name, year, model, or issue clues
- Optional PriceCharting/SportsCardsPro condition prices for Pokémon, sports cards, coins, and supported collectibles
- Copy-level grading company, certification number, purchase price, and custom current value
- Local-only collection storage in the current build
- No API secrets committed to source control

## Requirements

- Xcode 16 or newer
- iOS 17 or newer
- A physical iPhone for camera scanning

## Run the app

```bash
open CardSense.xcodeproj
```

Choose your development team in Signing & Capabilities, select an iPhone target, and run.

The repository includes a ready-to-open Xcode project. [XcodeGen](https://github.com/yonaskolb/XcodeGen) is optional and only needed if you want to regenerate that project from `project.yml`.

## Data sources

| Game | Catalogue | Current price fields |
| --- | --- | --- |
| Pokémon | Pokémon TCG API plus TCGdex for new English releases, Japanese, and Western-language fallback | TCGplayer/Cardmarket fields when supplied, plus optional PriceCharting lookup |
| Magic | Scryfall | Scryfall USD/EUR price fields |
| Yu-Gi-Oh! | YGOPRODeck | Marketplace snapshots supplied by the catalogue |
| Sports cards | CardSight catalogue plus SportsCardsPro pricing | Real player/set/card-number candidates; optional condition prices |
| Coins | Numista (optional key) | PriceCharting values when configured; research links otherwise |
| Wine | Open Food Facts | Product metadata; Wine-Searcher research link and manual value |
| Other collectibles | OCR research record | PriceCharting values when matched; completed-sales research otherwise |

Market values are informational estimates. Printing, language, foil treatment, grade, condition, timing, and the underlying marketplace can materially change a card's value.

Pokémon scanning opens in English mode. That mode also includes German, Spanish, French, Italian, and Brazilian Portuguese OCR hints and falls back to the matching TCGdex catalogues when the primary English catalogue has no match. English TCGdex is also checked for newly released cards that have not reached the primary catalogue yet. The Japanese switch uses Japanese OCR and the `ja` catalogue. Localized results retain their printed name while using the same TCGdex card ID to obtain an English market-search query when available.

If a live quote is not yet published for a newly released item, Held provides exact-item research links to PriceCharting, TCGplayer where applicable, and completed eBay sales instead of showing a dead-end empty panel.

## Pokémon API configuration

The Pokémon TCG API works without a key at a lower public rate limit. For local development only, create an untracked `Config.local.xcconfig`:

```text
POKEMON_TCG_API_KEY = your-development-key
```

Do not ship a private provider key inside an iOS app. A production release that needs authenticated or paid APIs should call a backend proxy that owns the credentials, enforces rate limits, and normalizes provider responses.

The old public key from the original repository must be rotated because removing it from the latest commit does not erase it from Git history.

## Optional CardSight, PriceCharting, and Numista configuration

CardSight offers a free API tier for real sports-card catalogue results. Save its key from Held Settings or add it to the ignored `Config.local.xcconfig`. PriceCharting/SportsCardsPro live pricing requires a paid provider subscription. Numista catalogue access requires an API key:

```text
CARDSIGHT_API_KEY = your-free-cardsight-key
PRICECHARTING_API_TOKEN = your-40-character-token
NUMISTA_API_KEY = your-numista-api-key
```

When a CardSight key is present, typing a player name returns up to 40 real catalogued sports cards. When a PriceCharting token is present, Held can request current ungraded and grade-specific values for supported catalogue items. The provider limits API traffic to one request per second, so the app serializes those requests. Without a pricing token, sports cards, coins, and other collectibles retain direct research links and support a manually verified current value.

Never commit production provider credentials or ship valuable static secrets inside a public iOS binary. A production version should route licensed APIs through a backend proxy.

## Architecture

```text
CardSenseApp
└── ContentView
    ├── HomeView
    ├── DiscoverView ── CardSearchViewModel ── MultigameService
    │   ├── TCG providers
    │   ├── PriceCharting + SportsCardsPro
    │   ├── Numista
    │   ├── Open Food Facts
    │   └── Completed-sales research
    ├── ScannerView ── CardScannerEngine (on-device Vision OCR)
    ├── CollectionView ── CollectionStore (local Codable persistence)
    ├── CardDetailView
    └── SettingsView
```

Provider models are mapped into the shared `UICard` type, keeping the interface independent from raw API response schemas.

## Product decisions

- The scanner reads identifying text on-device, then verifies against configured catalogues. It does not claim image-authentication, counterfeit detection, wine authentication, or professional grading.
- The exact set and collector number are shown before saving because parallels and reprints are a major source of incorrect valuations.
- Sports cards expose parallel, rookie, autograph and serial-number clues before saving.
- Coins require year, mint mark, denomination, composition, and both sides to be verified manually; the current camera path is OCR-based, not Numista's paid image-identification endpoint.
- Wine matches are community catalogue records. Storage, provenance, bottle condition, and fill level must be assessed separately.
- The flexible “Other” mode creates a searchable OCR research record; it does not claim automatic visual authentication or a guaranteed catalogue match.
- Collection totals include provider values or a user-confirmed current value; unpriced items remain visible without inflating the total.
- Marketplace buying and selling are intentionally out of scope for this build. Accurate identification and dependable collection management come first.

## Name check

Held is the selected working brand and the installed display name. Several unrelated apps already use variants of “Held,” so complete App Store and trademark clearance and use a descriptive App Store subtitle before release. The internal Xcode target remains `CardSense` to avoid unnecessary project-file churn.

<img width="1024" height="1024" alt="HeldIcon-Tinted" src="https://github.com/user-attachments/assets/b3f18d2d-7562-40b1-ba39-80962bc76ea9" />
<img width="660" height="1434" alt="IMG_5951" src="https://github.com/user-attachments/assets/cc6bffa0-d93d-4c51-a4e6-b5dde862a3bb" />
<img width="660" height="1434" alt="IMG_5980" src="https://github.com/user-attachments/assets/ac5a5306-abfc-4a04-b5ca-eb0165c650de" />
<img width="660" height="1434" alt="IMG_5999" src="https://github.com/user-attachments/assets/f6ce33ec-d75b-4b4d-aba1-9239ec670085" />
<img width="660" height="1434" alt="IMG_5974" src="https://github.com/user-attachments/assets/2c019e6f-8cc3-4333-9881-b60e87a789b9" />
<img width="660" height="1434" alt="IMG_5994" src="https://github.com/user-attachments/assets/8ff17e92-a032-471d-a0ba-010eec107a5b" />
<img width="660" height="1434" alt="IMG_5993" src="https://github.com/user-attachments/assets/d1ed1931-f024-48fd-998f-f75af0c79598" />
<img width="660" height="1434" alt="IMG_5954 2" src="https://github.com/user-attachments/assets/254fd5fb-af74-4b6c-9ee5-36adad06a0b3" />
<img width="660" height="1434" alt="IMG_5955 2" src="https://github.com/user-attachments/assets/d6aecffb-0829-4fe5-8111-1cf29b945ff5" />
<img width="660" height="1434" alt="IMG_5992" src="https://github.com/user-attachments/assets/d07ae68c-bde3-4ea5-9544-134d904d7c09" />
<img width="660" height="1434" alt="IMG_5972 2" src="https://github.com/user-attachments/assets/52c1e13c-ce39-4f65-824f-dee692c124bb" />
<img width="660" height="1434" alt="IMG_5963 2" src="https://github.com/user-attachments/assets/c5b0d01a-56a5-45d5-89d8-c443f0cf8e65" />
<img width="660" height="1434" alt="IMG_5964" src="https://github.com/user-attachments/assets/05c44cdb-8fa7-4948-b130-5e7e85414060" />
<img width="660" height="1434" alt="IMG_5997" src="https://github.com/user-attachments/assets/27cd5d1c-7285-4077-b17e-7867acaeee25" />
<img width="660" height="1434" alt="IMG_5996" src="https://github.com/user-attachments/assets/9a8527cd-f2cc-4aa3-bba9-816eccf13115" />


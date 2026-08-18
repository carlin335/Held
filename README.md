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
<img width="660" height="1434" alt="IMG_6016" src="https://github.com/user-attachments/assets/7323e833-714e-4595-8fda-0a69f22a44a5" />
<img width="660" height="1434" alt="IMG_6015" src="https://github.com/user-attachments/assets/251d9132-d323-4e7f-95a8-c4303fec27be" />
<img width="660" height="1434" alt="IMG_5995" src="https://github.com/user-attachments/assets/e770b7fa-2f19-4471-b3de-e27f0ca8cacf" />
<img width="660" height="1434" alt="IMG_5975" src="https://github.com/user-attachments/assets/3ccdf65e-9c53-4722-9514-4487228cdfe1" />
<img width="660" height="1434" alt="IMG_5955" src="https://github.com/user-attachments/assets/40790de4-a294-4140-858a-8689023d3a89" />
<img width="660" height="1434" alt="IMG_6016" src="https://github.com/user-attachments/assets/986dad03-ae68-4a52-b129-337a001d896a" />
<img width="660" height="1434" alt="IMG_5996" src="https://github.com/user-attachments/assets/f265d0b1-345e-418a-873b-f510c53156e1" />
<img width="660" height="1434" alt="IMG_5976" src="https://github.com/user-attachments/assets/c038d0d5-4a7f-4183-9438-158c319cdc90" />
<img width="660" height="1434" alt="IMG_5963" src="https://github.com/user-attachments/assets/67504905-99f9-4971-8b7d-224e16b4637d" />
<img width="660" height="1434" alt="IMG_6017" src="https://github.com/user-attachments/assets/f13c76f9-3681-49eb-a521-7baf8056e4fd" />
<img width="660" height="1434" alt="IMG_5997" src="https://github.com/user-attachments/assets/ff7cfe07-f411-4fad-ad32-0f849777fb9a" />
<img width="660" height="1434" alt="IMG_5980" src="https://github.com/user-attachments/assets/ca0345f0-05ee-43b4-b9e7-2de28bae844a" />
<img width="660" height="1434" alt="IMG_5964 2" src="https://github.com/user-attachments/assets/9ce0e932-308b-4680-834b-4ca58c4fe612" />
<img width="660" height="1434" alt="Screenshot 2026-08-17 at 22 24 09" src="https://github.com/user-attachments/assets/619879e2-f894-4f58-ba31-ce7c9ca1a3f7" />
<img width="660" height="1434" alt="IMG_6019" src="https://github.com/user-attachments/assets/0d0c1c4f-5314-484f-9433-1fe1a6d0e36f" />
<img width="660" height="1434" alt="IMG_5999" src="https://github.com/user-attachments/assets/f8fc96c5-5c93-4faf-bc5e-9122d6d753ff" />
<img width="660" height="1434" alt="IMG_5992" src="https://github.com/user-attachments/assets/81fd5b26-a1d8-4859-b7c6-a527bf2c4646" />
<img width="660" height="1434" alt="IMG_5969" src="https://github.com/user-attachments/assets/344b302a-e528-4092-9366-a838c15575b1" />
<img width="660" height="1434" alt="IMG_6013" src="https://github.com/user-attachments/assets/e8cb55f7-6aa8-4c90-83b5-b24db79228de" />
<img width="660" height="1434" alt="IMG_5993" src="https://github.com/user-attachments/assets/c6199635-c0c3-4f01-9253-b7da94c2c9b9" />
<img width="660" height="1434" alt="IMG_5973" src="https://github.com/user-attachments/assets/13792d5f-9bce-4af3-a544-839edc68342c" />
<img width="660" height="1434" alt="IMG_5954" src="https://github.com/user-attachments/assets/e6fcdd2a-f17e-4f1d-a503-3a9e52ddf0ec" />
<img width="660" height="1434" alt="Screenshot 2026-08-17 at 22 22 56" src="https://github.com/user-attachments/assets/3df01345-f1ac-44a8-b3a1-06f8535345f5" />


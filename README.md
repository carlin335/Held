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
<img width="660" height="1434" alt="IMG_5951 2" src="https://github.com/user-attachments/assets/069e490e-d60f-43a8-8c92-5afae66b61d8" />
<img width="660" height="1434" alt="IMG_6045" src="https://github.com/user-attachments/assets/df0646f8-d162-4c6f-a28c-16022ac81d01" />
<img width="660" height="1434" alt="IMG_6015" src="https://github.com/user-attachments/assets/4cf3633c-6f2f-457b-87c6-cc4bb6320dd1" />
<img width="660" height="1434" alt="IMG_5995" src="https://github.com/user-attachments/assets/7f2c3e5a-c598-42af-a572-befc4801ff88" />
<img width="660" height="1434" alt="IMG_5975" src="https://github.com/user-attachments/assets/b31a1472-fa36-41ff-bea8-66a36802e35d" />
<img width="660" height="1434" alt="IMG_5955" src="https://github.com/user-attachments/assets/33b41746-d1ed-4dce-becd-9858e1d61b9e" />
<img width="660" height="1434" alt="Screenshot 2026-08-17 at 22 21 47" src="https://github.com/user-attachments/assets/8d6a9a6a-400e-4da4-b240-d5b07058727f" />
<img width="660" height="1434" alt="IMG_6016" src="https://github.com/user-attachments/assets/4176819f-4c28-4376-b25e-c869774e1eed" />
<img width="660" height="1434" alt="IMG_5996" src="https://github.com/user-attachments/assets/5576f495-4ad5-4fc1-939a-a81373571328" />
<img width="660" height="1434" alt="IMG_5976" src="https://github.com/user-attachments/assets/a5632cc0-7c70-4a27-91c8-6929338d7a19" />
<img width="660" height="1434" alt="IMG_5963" src="https://github.com/user-attachments/assets/485cd0c6-e7d1-4f6e-bb9f-ca3e6c4656a1" />
<img width="660" height="1434" alt="Screenshot 2026-08-17 at 22 22 56" src="https://github.com/user-attachments/assets/926f42ea-1bda-4c4f-a135-1d2fb6b8f276" />
<img width="660" height="1434" alt="IMG_6017" src="https://github.com/user-attachments/assets/34546ecb-8ab2-4f53-b54f-307d0c010674" />
<img width="660" height="1434" alt="IMG_5997" src="https://github.com/user-attachments/assets/b883e8a7-3f07-4700-ad3c-a060b369195f" />
<img width="660" height="1434" alt="IMG_5980" src="https://github.com/user-attachments/assets/3edb3e9b-475a-4744-9740-6d4eb6999642" />
<img width="660" height="1434" alt="IMG_5964 2" src="https://github.com/user-attachments/assets/2f884660-190a-4864-a0c4-ff84e462249a" />
<img width="660" height="1434" alt="Screenshot 2026-08-17 at 22 24 09" src="https://github.com/user-attachments/assets/d9eba3f5-546c-4021-a1b3-268fe933ca85" />
<img width="660" height="1434" alt="IMG_6019" src="https://github.com/user-attachments/assets/3cde5b5d-f1ef-4847-ad1b-f5ed797a1ae1" />
<img width="660" height="1434" alt="IMG_5999" src="https://github.com/user-attachments/assets/8252c08a-5c74-4351-8ca9-67cd9c259cf5" />
<img width="660" height="1434" alt="IMG_5992" src="https://github.com/user-attachments/assets/762594a9-2f72-405b-91da-36b3384ef6bc" />
<img width="660" height="1434" alt="IMG_5969" src="https://github.com/user-attachments/assets/b414a90a-5afe-4f82-aa50-3d95b4b8b29f" />
<img width="660" height="1434" alt="IMG_6013" src="https://github.com/user-attachments/assets/70574831-a0d9-4add-909f-6219fce33ae1" />
<img width="660" height="1434" alt="IMG_5993" src="https://github.com/user-attachments/assets/6b44ec0d-3836-44a2-aedb-0481483fce64" />
<img width="660" height="1434" alt="IMG_5973" src="https://github.com/user-attachments/assets/d41488cb-468d-48df-915d-b5ccb32f42f8" />
<img width="660" height="1434" alt="IMG_5954" src="https://github.com/user-attachments/assets/d3c7c037-0f47-4409-ba5f-4b441b8f6c5d" />

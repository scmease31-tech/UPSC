# Attribution & Licences

Everything UPSC Daily Edge ships or pulls in, and the terms it is used under.

A user-facing version of this lives in the app at **Profile → Credits & Licences**.
That matters: some licences here (the Flaticon free licence in particular)
require the credit to be visible to end users, not just recorded in the source
tree.

---

## ⚠️ Open item — 23 icons need their source URLs

`assets/flaticon_pngs/` ships 24 icons. **23 of them have no recorded source.**

Flaticon's free licence permits commercial use *only with attribution*, so
shipping them uncredited is a licence breach, however small.

The author of a Flaticon icon cannot be recovered from the PNG file, so this has
to come from whoever downloaded them — the Flaticon account's download history
lists every icon and its author.

Needing a source URL:

```
brain, compass, economy, fire, geography, history, international, lightbulb,
lightning, military_badge, muscle, newspaper, people_community, polity,
scales_justice, science, shield, star, target_mixed, theater_masks, thumbs_up,
trophy, wheat_agriculture
```

Three ways to close it:

1. **Recover the URLs** from the Flaticon account and add them to the table below.
2. **Buy a Flaticon subscription** — paid plans waive the attribution requirement.
3. **Replace them with Material Icons**, which are built into Flutter under
   Apache 2.0 and need no attribution.

Until then, the app credits Flaticon generically, which is weaker than the
licence asks for.

*(19 further icons were removed in this pass — they were bundled but never
referenced by any code, so they added app size and licence obligations for
nothing.)*

---

## Typography

Bundled in `assets/fonts/`. Licence texts ship alongside them and are surfaced
in-app through `LicenseRegistry`.

| Font | Author | Licence |
|---|---|---|
| [Inter](https://github.com/rsms/inter) | Rasmus Andersson & the Inter Project Authors | SIL Open Font License 1.1 |
| [Plus Jakarta Sans](https://github.com/tokotype/PlusJakartaSans) | Tokotype & the Plus Jakarta Sans Project Authors | SIL Open Font License 1.1 |

Both are variable fonts, taken from the upstream
[google/fonts](https://github.com/google/fonts) repository. The OFL permits
bundling and redistribution provided the licence travels with the font — it does,
in `assets/fonts/OFL-*.txt`.

## Icons

| Source | Use | Licence |
|---|---|---|
| [Flaticon](https://www.flaticon.com) | Subject and feature icons (`assets/flaticon_pngs/`) | Flaticon Free Licence — **attribution required**, see the open item above |
| [Material Icons](https://fonts.google.com/icons) | Interface icons, built into Flutter | Apache License 2.0 |

Documented Flaticon icons:

| File | Icon | Source |
|---|---|---|
| environment.png | Environment | https://www.flaticon.com/free-icon/environment_2820612 |

## Photography

| Source | Use | Licence |
|---|---|---|
| [Unsplash](https://unsplash.com/license) | Banner and background photography, loaded remotely (see `lib/config/app_images.dart`) | Unsplash Licence — free for commercial use, attribution appreciated but not required |

## Animations

| Source | Use | Licence |
|---|---|---|
| Lottie animation files (`assets/animations/`) | Loading, empty-state and celebration animations | **Provenance unconfirmed** — see note |
| [lottie](https://pub.dev/packages/lottie) (the renderer) | Playback | MIT |

> **Note:** the origin of the individual `.lottie` / `.json` files is not
> recorded anywhere in this repository. If they came from LottieFiles, free
> assets there carry per-asset terms — some require attribution. Worth
> confirming before release. Three unused animation files
> (`book_loading.lottie`, `no_data.lottie`, `success_confetti.lottie`) are
> bundled but never referenced.

## Content sources

The app does not own this content. It is aggregated, and rights remain with the
original publishers.

| Source | How it is used |
|---|---|
| [The Hindu](https://www.thehindu.com), [The Indian Express](https://indianexpress.com), [LiveMint](https://www.livemint.com), India Today | Public RSS feeds — headlines and summaries in the "Live from Web" feed, each linking back to the publisher |
| [Google News](https://news.google.com) | RSS search, same treatment |
| [Drishti IAS](https://www.drishtiias.com), [Insights on India](https://www.insightsonindia.com) | Scraped by `backend/content-scraper` into the daily current-affairs collections |
| [Wikipedia](https://en.wikipedia.org) / Wikimedia Commons | Background reference and imagery — text is CC BY-SA, which requires attribution and share-alike |
| [upsc.gov.in](https://www.upsc.gov.in), Press Information Bureau | Official notifications and government scheme data |
| [Free Dictionary API](https://dictionaryapi.dev) | Word definitions in the vocabulary module |
| [Google Gemini API](https://ai.google.dev) | AI search, using a key the user supplies themselves |

> **Unresolved:** the Drishti IAS and Insights on India material is the app's
> core daily content and is taken from commercial coaching publishers without a
> licensing arrangement. Google Play acts on IP complaints by removing apps.
> This is a business decision, not a technical one, and it is still open.

> **Unresolved:** `books/` in this repository holds NCERT textbooks and works by
> R.S. Sharma, Bipan Chandra and Satish Chandra, processed by the OCR pipeline in
> `backend/`. These are copyrighted publications. Free download from NCERT for
> personal use is not the same as redistribution inside an app.

## Software

Flutter itself is BSD 3-Clause. Every bundled Dart package's licence is rendered
in-app under **Credits & Licences → Open-source licences**, generated
automatically by Flutter's `showLicensePage` so it can never drift out of date
as dependencies change.

Principal direct dependencies: Firebase (Core, Auth, Firestore, Messaging,
Storage), Google Sign-In, Google Mobile Ads, provider, flutter_svg,
cached_network_image, shimmer, http, share_plus, url_launcher, intl,
flutter_local_notifications, percent_indicator, shared_preferences, timezone,
lottie, package_info_plus.

## Trademarks

UPSC Daily Edge is an independent study aid. It is **not affiliated with,
endorsed by, or connected to** the Union Public Service Commission or any
government body. "UPSC" is used only to describe the examination the app helps
users prepare for. All trademarks belong to their respective owners.

This disclaimer also appears in-app on the Credits screen, and should appear in
the Play Store listing description — exam-prep apps using an examining body's
name are a common target of Play's impersonation policy.

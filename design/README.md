# Figma designs

Every screen of the customer app (390 × 844) and the owner dashboard (1440 × 960), as editable vector SVGs.

| File | Screen |
|---|---|
| `figma/00-design-system.svg` | colors, type, buttons, pills, tags, cart bar, pizza illustration |
| `figma/01-welcome.svg` … `16-account.svg` | customer app: welcome, sign-up (X to skip), location, pickup/delivery, home, menu, pizza builder, "complete your meal" popup, cart, checkout, Apple Pay sheet, tracking, driver chat, orders, deals, account |
| `figma/20-owner-login.svg` … `27-owner-settings.svg` | owner dashboard: sign in, dashboard, live orders, menu & prep times, promo codes, customers, reports, settings |
| `figma/all-screens.svg` | everything on one board |

## Import into Figma

1. Open a Figma file → drag the `.svg` files onto the canvas (or **File → Import**).
2. Each screen arrives as a frame with named layers (`Button / Checkout`, `Pizza`, `Tab bar`, `KPI / Orders`…). Text stays editable and uses **Fredoka** (headings) and **Nunito** (body) — both are in Figma's built-in Google Fonts.
3. Optional: right-click a repeated layer (tab bar, buttons, pills) → **Create component** to reuse it across frames.

## Regenerate

The SVGs are generated from `generate_figma.py` with the same tokens as `lib/core/theme.dart`, so they stay in step with the app:

```bash
python design/generate_figma.py
```

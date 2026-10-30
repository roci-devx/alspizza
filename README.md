# Al's Pizza — online ordering

One codebase for the **customer app** (iOS, Android, web), the **owner app** (web dashboard + native Android/iOS app "Al's Owner"), and the **API** that ties them to payments, delivery couriers and the restaurant's POS.

```
als/
├─ lib/
│  ├─ main.dart            customer app entry  (iOS · Android · web)
│  ├─ main_owner.dart      owner app entry (web; the native app in owner_app/ runs the same code)
│  ├─ core/                shared: API client, realtime, models, theme, food illustrations
│  ├─ customer/            onboarding, menu, pizza builder, cart, checkout, tracking, chat…
│  └─ owner/               dashboard, live orders, menu & prep times, promos, customers, reports, settings
├─ owner_app/              native Android/iOS shell for the owner app ("Al's Owner", com.alspizza.owner)
├─ backend/                Node + TypeScript API (Express, Prisma, WebSockets, Excel reports)
│  └─ public/stock/        stock food photos served at /media/stock/… (owner uploads go to public/uploads/)
├─ design/                 Figma-importable screen designs (SVG)
└─ assets/                 logo, app icons, splash
```

Everything runs locally with **zero accounts**: payments run in demo mode and deliveries use a simulated courier (live GPS, chat replies) until you add real keys.

---

## Quick start

**1 · API** (Node 20.12+)

```bash
cd backend
npm install
cp .env.example .env          # then set JWT_SECRET
npm run setup                 # creates the SQLite DB + seeds 3 stores, the menu, 60 days of orders
npm run dev                   # http://localhost:4000  (ws://localhost:4000/ws)
```

**2 · Customer app**

```bash
flutter pub get
flutter run -d chrome --web-port 5000          # web
flutter run -d <android-device>                 # Android (see "Testing on a phone")
```

**3 · Owner app**

```bash
flutter run -d chrome --web-port 5001 -t lib/main_owner.dart   # web dashboard
cd owner_app && flutter run -d <android-device>                  # native "Al's Owner" app
```

| Login | |
|---|---|
| Owner | `owner@alspizza.com` / the `OWNER_PASSWORD` you set in `backend/.env` before `npm run setup` |
| Demo owner (one-tap "Use demo account" button) | `demo.owner@alspizza.com` / `demo1234` |
| Demo customer with order history (one-tap button on sign-in) | `demo@alspizza.com` / `pizza1234` |

The one-tap demo buttons appear only while the API runs with `DEMO_ACCOUNTS` on (the default outside production). The owner password is never stored in the code.

### Builds

```bash
flutter build web -t lib/main.dart -o build/customer_web
flutter build web -t lib/main_owner.dart -o build/owner_web
flutter build apk --release --dart-define=API_URL=https://api.yourdomain.com
flutter build ipa --release --dart-define=API_URL=https://api.yourdomain.com   # on a Mac
cd owner_app && flutter build apk --release --dart-define=API_URL=https://api.yourdomain.com   # owner app
```

`API_URL` defaults to `localhost:4000` (web uses the page's host, the Android emulator uses `10.0.2.2`).

### Testing on a phone

Plug in an Android phone with USB debugging on, then route the phone's `localhost` to your PC over the cable — this works even on campus/office Wi-Fi that blocks device-to-device traffic:

```bash
adb reverse tcp:4000 tcp:4000      # API
adb reverse tcp:5001 tcp:5001      # owner dashboard (served locally)
flutter build apk --profile --dart-define=API_URL=http://localhost:4000
adb install -r build/app/outputs/flutter-apk/app-profile.apk
# owner app, side by side with the customer app:
(cd owner_app && flutter build apk --profile --dart-define=API_URL=http://localhost:4000)
adb install -r owner_app/build/app/outputs/flutter-apk/app-profile.apk
```

Debug and profile builds allow plain HTTP to your dev machine; release builds are HTTPS-only. iPhones need a Mac to build; meanwhile both apps work in Safari as web apps.

---

## How the customer flow works

1. **Welcome → account (optional).** The X skips sign-up; everyone gets a guest session automatically. Signing up later upgrades the guest so past orders stay attached. Sign-up asks "How did you hear about Al's?" — that feeds the owner's marketing report.
2. **Location.** Share location or type an address → nearest stores with distance, hours and pickup ETA.
3. **Pickup or delivery** — or "decide later".
4. **Menu → builder.** Size, crust (availability per size, e.g. Stuffed is Large-only), sauce, cheese, toppings. The pizza illustration updates live; toppings drop on with an animation.
5. **"Complete your meal?"** popup offers sides, desserts and drinks after a main is added.
6. **Cart** — server-priced, promo codes, swipe to remove.
7. **Checkout** asks pickup/delivery again, confirms the address, shows the ETA, delivery fee and driver tip, then pays.
8. **Tracking** — kitchen progress, ETA, live courier map, message/call the driver.

### Pickup ETA

`slowest item's prep time (owner-set per food type, overridable per item) + queue minutes × orders already in the kitchen`.
Owners edit prep times under **Menu & prep times**. Every order records `paidAt`/`readyAt`, so a learned estimate (the "use customer feedback" idea) can replace this formula later without changing the app.

### Delivery (white-label)

The customer only ever sees Al's. Behind the scenes (`backend/src/services/delivery.service.ts`), the store's **Settings → Delivery** mode chooses the courier:

| Mode | Routing |
|---|---|
| Auto (default) | own drivers when any are on duty → DoorDash Drive → Uber Direct |
| Own drivers | staff assign a driver on the Live Orders board |
| DoorDash / Uber | that network first, the other as backup |

DoorDash Drive flow: quote at checkout (fee + ETA, valid 5 min) → accept the quote when payment succeeds (or create a fresh delivery if it expired) → status by webhook, courier GPS by polling. DoorDash's own SMS to the customer is disabled. Owners can "take back" an order from the courier for an in-house driver, or hand an unassigned one to a courier.

**Driver chat:** messages are stored and shown in the app and dashboard. With Twilio configured, our Twilio number is given to the courier as the drop-off phone, so courier texts arrive in the app and app messages are texted to the courier; courier calls are forwarded to the customer.

### Payments

| | iOS / Android | Web |
|---|---|---|
| Stripe | native PaymentSheet — cards, Apple Pay, Google Pay | hosted Stripe Checkout (wallets appear automatically) |
| PayPal | approval page in an in-app browser | redirect |
| Pay at pickup | optional per store | optional per store |

Totals are always computed on the server. Webhooks and an app-side "sync" both confirm payments (idempotent).

### POS

Paid orders are pushed to the POS chosen in **Settings → Point of sale** (`backend/src/integrations/pos/`):

- **Square** — Orders API with a PICKUP/DELIVERY fulfillment, payment recorded as external so it shows as paid in Square POS/KDS. A Square webhook syncs kitchen status back to the app.
- **Clover** — Atomic Orders API (prints on Clover devices).
- **Toast** — Orders API; requires Toast partner approval and a menu-GUID map (`TOAST_ITEM_MAP`).
- **None** — the owner dashboard's Live Orders board *is* the kitchen display.

For restaurants on other systems, an aggregator such as Otter, Deliverect or Checkmate connects one API to 50+ POS brands; add it as another adapter next to `square.ts`.

### Owner app (web, Android, iOS)

Same screens everywhere: a sidebar on desktop, bottom tabs (Dashboard · Orders · Menu · Reports · More) on phones, and the phone buzzes when a new order lands.

- **Menu portal** — add/edit/delete items; upload a photo (camera or library) or paste a link; edit ingredients (default toppings, sauce, cheese, crust), prices per size or custom size options ("6 pc / 12 pc"), choice groups (wing sauce, free dip…), combo contents, tags, calories, prep time, sold-out; create, rename, reorder and delete **menu types**; edit the shared **pizza options** (sizes, crusts per size with upcharges, sauces, cheese levels, toppings — new toppings pick a "looks like" drawing for the live pizza preview).
- **Dashboard** — net sales (hero), orders, average order, app users, repeat-customer rate, orders in the kitchen, with deltas vs the previous period; sales trend, orders by hour, pickup/delivery split, courier split, platform split, top sellers, **which marketing worked** (promo codes are tagged with a channel), promo performance, payment methods, sign-up sources. Every chart has a table view.
- **Live orders** — kanban board that updates in real time; start/ready/complete, assign drivers, send to courier, cancel & refund, read the customer↔driver chat.
- **Menu & prep times**, **Promo codes**, **Customers** (repeat customers matched by phone), **Reports**, **Settings**.

### End-of-day Excel report

Each store's report is generated automatically at its closing time (default 23:30 store time) and emailed if SMTP is configured; owners can also generate any date on demand. Sheets: **Summary** (net sales, discounts, fees, tips, tax, courier fees, net after fees, AOV, customers, kitchen and delivery times), **Orders**, **Items**, **Promo Codes**, **Hourly**, **Payments**.

---

## Going live — integration checklist

All keys go in `backend/.env` (see `.env.example`). Anything left blank keeps its demo behavior.

| Integration | Where | Webhook to register |
|---|---|---|
| Stripe | dashboard.stripe.com → API keys | `/api/webhooks/stripe` — `payment_intent.succeeded`, `checkout.session.completed`, `charge.refunded` |
| Apple Pay | Apple Developer merchant ID + Stripe → Settings → Apple Pay; add the Apple Pay capability in Xcode | — |
| Google Pay | enabled through Stripe; set `testEnv: false` for production (automatic with live keys) | — |
| PayPal | developer.paypal.com → app credentials | return URLs are built in |
| DoorDash Drive | developer.doordash.com → Credentials (developer ID, key ID, signing secret) | `/api/webhooks/doordash` with an `Authorization` value matching `DOORDASH_WEBHOOK_AUTH` |
| Uber Direct | direct.uber.com → client ID/secret, customer ID | `/api/webhooks/uber` |
| Twilio | buy a number; set SMS + Voice webhooks | `/api/webhooks/twilio/sms`, `/api/webhooks/twilio/voice` |
| Square | developer.squareup.com → access token; location ID in Settings | `/api/webhooks/square` — `order.fulfillment.updated` |
| Google Maps | Geocoding API key (production address search; dev uses OpenStreetMap) | — |
| SMTP | any SMTP URL for nightly report emails | — |

Production notes: set `NODE_ENV=production`, a strong `JWT_SECRET`, `CORS_ORIGINS`, `API_PUBLIC_URL`, `WEB_APP_URL`; switch Prisma to PostgreSQL (`provider = "postgresql"` in `backend/prisma/schema.prisma`); host the API behind HTTPS (webhooks require it). Re-running `flutter_native_splash` rewrites the Android themes — keep their parents on `Theme.AppCompat.Light.NoActionBar` (Stripe needs it).

## Menu & photos

The starter menu (`backend/src/menu/catalog.ts`) mirrors a big national chain's structure — Original Pan / Hand-Tossed / Thin & Crispy / Stuffed / NY / Gluten-Free crusts, specialty pizzas, wings, sides, pasta, desserts, drinks, combo boxes — with Al's own names. Competitors' menu names (e.g. "Meat Lover's®") are trademarks, so they aren't used. Everything is editable from the owner app's Menu portal.

Pizzas, combos and wings start with free stock photos (Unsplash / Pexels licenses — see `backend/public/stock/CREDITS.md`); swap in real photos of Al's food from the Menu portal. Items without a photo show a drawn illustration that matches their toppings, and the pizza builder always shows a live drawing of the customer's build.

## Roadmap ideas

Push notifications (order ready / driver arriving) · saved cards (Stripe customers) · loyalty points · learned ETA from actual ready times and customer feedback · a driver app for in-house drivers (GPS into the same tracking map) · scheduled orders · catering.

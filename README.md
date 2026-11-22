# ScoreLine (Scorehub)

A multi-sport live scores app prototype, in the spirit of FotMob: live scores, match centre, league tables, favourite teams and goal alerts. It starts with football and extends to other sports (basketball included).

> **Prototype:** all scores, lineups, stats and tables are **simulated demo data**, not real results. Live matches advance one match minute every 3 seconds.

## Run it

It's a single self-contained file with no build step and no dependencies.

- Open `index.html` in any modern browser, or
- serve the folder: `npx serve .` or `python3 -m http.server`, then visit the printed URL.

## Features

- **Onboarding:** Quick Setup, then follow teams (Local / Suggested / All tabs with search), then follow competitions. Local is picked from your time zone.
- **Matches:** date tabs (±7 days), Live / Following filters, sport filter, collapsible league cards with flags, "Your teams" pinned at the top, and a team search bar.
- **Match centre:** live event timeline (goals, assists, cards, subs, VAR reversals), lineups on a pitch with live player ratings, stats (possession, xG, shots and more), head-to-head and form, league table. Basketball gets quarter scores and a box score.
- **Leagues:** 17 competitions grouped by region, including the Premier League, LaLiga, Bundesliga, Serie A, Ligue 1, Eredivisie, Liga Portugal, Scottish Premiership, MLS, Saudi Pro League, J1, K League 1, A-League, Singapore Premier League, Malaysia Super League, Thai League 1 and the NBA, with tables, fixtures and top scorers.
- **Teams:** next match, form, recent results, squad.
- **Alerts:** in-app notifications for followed teams, leagues and matches, with per-type toggles and a "big moments only" mode.
- **Search** across teams, players and competitions, with nicknames, short codes and typo tolerance.
- Light and dark themes; favourites and settings saved in the browser (`localStorage`).

## Crests and logos

Teams show original two-colour shield placeholders. Official club logos are trademarked and need a licence. Most sports data providers include crest image URLs in their team feeds. Once you have them, and your contract allows display, pass them in:

```js
setTeamLogos({ ars: 'https://…/arsenal.png', fcb: 'https://…/bayern.png' });
```

A logo replaces the shield everywhere. If an image fails to load, the shield stays.

## Moving to real data

The data layer is kept separate from the views so it can be swapped for a real provider:

| In the prototype | Replace with |
| --- | --- |
| `getDay()` / `makeMatch()`: seeded fixtures | Provider fixtures API (by date) |
| `step()` simulation in the `setInterval` ticker | WebSocket / SSE stream from your backend |
| `standings()`, `topScorers()`, `squad()` | Provider standings, stats and squad endpoints |
| `note()` in-app toasts | Push notifications (APNs / FCM) from a push service |
| `localStorage` follows | User accounts and a follows API |

See the product requirements document for the full roadmap, architecture and data model.

## Tech

Plain HTML, CSS and JavaScript in one file. No framework, no external requests.

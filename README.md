# FilmFrei24 für iPhone, iPad und Apple TV

Ein gemeinsamer SwiftUI-Code (`Shared/`) für zwei Apps:

| Ziel | Plattform | Bundle-ID | ab |
|---|---|---|---|
| FilmFrei24 | iPhone/iPad | com.filmfrei24.app | iOS 16 |
| FilmFrei24TV | Apple TV | com.filmfrei24.tv | tvOS 17 |

Design und Funktionen wie filmfrei24.com bzw. die Android-App 2.1.0: Startseite mit Hero, Weiterschauen, Merkliste,
Top 10, Neu, Genres; Filme/Serien mit Sortierung und Genres; Detailseite mit Staffeln/Folgen; Suche; Konto, Einstellungen,
Nachrichten; Wünsche mit Warenkorb (Bezahlung: iPhone → Stripe im Browser, Apple TV → QR-Code fürs Handy); Support-Tickets;
IPTV; Anmelden/Registrieren/Passwort vergessen (Google-Login nur iPhone, im Browser-Fenster).
Player: AVPlayer mit AirPlay/Bild-in-Bild, Forced-Untertitel, „Intro überspringen“, „Nächste Folge“, Fortschritt alle 10 s.
Kontrollzentrum: nur Titel + Poster, nach dem Schließen leer.

Server-Schnittstellen: `beta/api.php` (Katalog, Serien, play, wishctx, iptv), `api/app.php` (Login, Profil, Google, Passwort-Reset)
und die bestehenden `api/*.php` (progress, watchlist, inbox, wishlist, wishlist_checkout, support, report, …).

## Bauen (Mac mit Xcode 15+)

```bash
brew install xcodegen
cd ff24-ios
xcodegen generate          # erzeugt FilmFrei24.xcodeproj
open FilmFrei24.xcodeproj
```

In Xcode bei beiden Zielen unter *Signing & Capabilities* das eigene Team wählen, dann bauen.
IPA: *Product → Archive → Distribute App* (TestFlight/App Store, Ad Hoc oder Development).

## Ohne Mac: GitHub Actions

`.github/workflows/build.yml` baut auf einem macOS-Server von GitHub **unsignierte** IPAs (iOS + tvOS) als Download.
Unsigniert heißt: Installation nur per Sideloading (AltStore/Sideloadly mit eigener Apple-ID, alle 7 Tage neu signieren).
Für TestFlight/dauerhafte Installation braucht es ein Apple-Entwicklerkonto (99 €/Jahr); dann Zertifikat + Profil als
GitHub-Secrets hinterlegen und den Export-Schritt auf signiert umstellen.

## Stand

Code vollständig, aber **noch nie kompiliert** (auf dem Linux-Server gibt es kein Xcode). Nur die Datenschicht
(`API.swift`, `Models.swift`) wurde mit dem Swift-Compiler geprüft. Beim ersten Bauen auf dem Mac mit kleinen
Compilerfehlern rechnen.

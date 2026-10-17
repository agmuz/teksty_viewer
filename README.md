# teksty_viewer

Aplikacja Android do przeglądania i organizowania **tekstów piosenek** (PDF, JPG, TXT) 
z **banków na Dysku Google**.

## Funkcje

- **Banki** — wiele folderów z Dysku Google (import przez SAF)
- **Playlisty** — własne zestawy na koncert (drag & drop, edycja)
- **Przeglądarka PDF** — pdfrx, swipe, **pedał BT** (strzałki / PageUp / PageDown)
- **Generator PDF** — łączy playlistę w jeden PDF, **pierwsza strona = spis utworów** (numer + tytuł + **tonacja** z pierwszej strony każdego utworu), polskie znaki (Roboto TTF)
- **Zapis zoomu** — długie przytrzymanie (per plik)
- **Auto-hide pasków** — scroll w górę = paski chowają się
- **Fullscreen** (immersiveSticky)
- **Miotełki** — czyszczenie oznaczeń (piaskowe kafelki)
- **Model Bank z UUID** — playlisty przypisane po id
- **Auto-skalowanie** kafelków i czcionki
- **Ciemny motyw** — granatowy

## Instalacja

1. Pobierz APK: [app-release.apk](https://github.com/agmuz/teksty_viewer/releases/latest/download/app-release.apk)
2. Włącz „Zainstaluj z nieznanych źródeł" na Androidzie
3. Otwórz APK i zainstaluj

## Wymagania

- Android 8.0+ (API 26+)
- Uprawnienia: dostęp do plików (Dysk Google przez SAF)

## Wersje

- **10.17** (2026-10-17) — model Bank(id) + Playlist(bankId), auto-hide pasków, editMode + drag & drop, miotełki, fullscreen, chipy „+ Listy" / „+ Banki", auto-skalowanie kafelków
- **v12** (2026-10-16) — pasek menu chowany przy scrollu
- **v10** (2026-10-11) — nowy model banków (id), playlisty per-bank
- **v9** (2026-09-28) — sortowanie numeryczne, banki SAF
- **v1** (2026-09-29) — zapamiętywanie zoomu PDF

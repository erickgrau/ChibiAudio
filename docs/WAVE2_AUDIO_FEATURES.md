# Wave 2 — on-device audio similarity (deferred)

ChibiAudio **v1 multi-seed playlists** Soft PASS without bundling large ML models.

## What v1 ships

1. Embedded metadata (genre, year, album, artist) from library scans  
2. Free MusicBrainz / ListenBrainz HTTP APIs when online (`User-Agent: ChibiAudio/…`, ~1 req/s)  
3. Local scoring: shared genre / era / artist, playlist co-occurrence, recents  
4. Optional `PlaylistLLMEnriching` hook for a later Stiki / house LLM — **no paid LLM keys required**  
5. Candidates only from owned sources (local / cloud folders, Plex, Bandcamp Subsonic)

## Deferred to Wave 2 (too heavy for v1)

| Option | Why deferred |
|---|---|
| **Essentia** (tempo, key, loudness, embeddings) | Large native binary / model footprint; non-trivial iOS packaging |
| **CLAP** / similar audio-text embeddings | Multi‑100 MB models; download or on-device inference cost |
| Full on-device neural playlist models | Battery + storage; needs careful Core ML conversion |

Wave 2 can plug into `PlaylistScoringEngine` as an extra score channel (e.g. embedding cosine) without changing the seed-picker UI. Keep the offline metadata path as the always-on baseline.

## Hook points

- `PlaylistLLMEnriching` — text/artist enrichment  
- `PlaylistScoringEngine.score` — add an optional similarity term  
- Do **not** scrape Spotify / Apple Music catalogs for candidates

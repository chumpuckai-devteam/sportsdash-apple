#!/usr/bin/env python3
"""Mirror SportsDash MovieDetection / XmltvCategory rules for offline verification.

Keep in sync with:
  SportsDash/Core/Models/EpgProgram.swift (XmltvCategory)
  SportsDash/Core/Models/MovieRating.swift (MovieFlagSignals / MovieDetection)
"""
from __future__ import annotations

import re
import sys

MOVIE_TOKENS = [
    "movie", "movies", "film", "films", "cinema", "feature", "feature film",
    "película", "pelicula", "cine", "kino", "filme",
]
NON_MOVIE_TOKENS = [
    "sport", "sports", "news", "weather", "series", "tvshow", "tv show",
    "episode", "soap", "telenovela", "talk", "reality", "game show",
    "children", "kids", "cartoon", "anime", "documentary series",
    "music video", "paid programming", "infomercial", "shopping",
]
SPORTS = [
    "sport", "espn", "nfl", "nba", "mlb", "nhl", "soccer", "football", "tennis",
    "golf", "ufc", "racing", "f1", "nascar", "wwe", "boxing", "olympics",
    "premier league", "la liga", "serie a", "bundesliga", "cricket", "rugby",
]
NEWS = ["news", "weather", "cnn", "msnbc", "fox news", "cnbc", "bloomberg"]
MOVIE_CH = [
    "hbo", "showtime", "starz", "cinemax", "movie", "movies", "film", "films",
    "cinema", "mgm", "tcm", "epix", "amc", "fxm", "indie",
    "hollywood", "paramount", "stars", "sky cinema", "cineplex",
    "hallmark", "lifetime movies", "sony movies", "freeform",
    "24/7 movie", "hollywood 24", "hollywoodbox", "vod",
]
SOFT = ["entertainment", "premium", "hollywood", "vod"]
SKIP = [
    "no information", "no info", "no program", "to be announced", "tba", "tbd",
    "program data", "unknown", "n/a", "off air", "off-air", "sign off", "test card",
    "paid programming", "infomercial",
]


def blob(cats: list[str]) -> str:
    return " | ".join(c.strip().lower() for c in cats if c.strip())


def says_movie(cats: list[str]) -> bool:
    b = blob(cats)
    return bool(b) and any(t in b for t in MOVIE_TOKENS)


def says_non_movie(cats: list[str]) -> bool:
    b = blob(cats)
    return bool(b) and any(t in b for t in NON_MOVIE_TOKENS)


def parse_title(raw: str) -> tuple[str, int | None]:
    t = raw.strip()
    lower = t.lower()
    for p in ["movie:", "film:", "cinema:", "mov:", "movies -", "movie -"]:
        if lower.startswith(p):
            t = t[len(p):].strip()
            break
    year = None
    m = re.search(r"\((\d{4})\)\s*$", t)
    if m:
        year = int(m.group(1))
        t = t[: m.start()].strip()
    t = re.sub(r"\[(.*?)\]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t, year


def is_movie(title: str, categories: list[str] | None = None, group: str | None = None, name: str | None = None) -> bool:
    categories = categories or []
    clean, year = parse_title(title)
    t = clean.lower()
    if len(clean) < 2:
        return False
    if any(t == s or t.startswith(s) for s in SKIP):
        return False
    g = (group or "").lower()
    ch = (name or "").lower()
    bag = g + " " + ch
    if any(s in bag for s in SPORTS) or any(s in bag for s in NEWS) or any(s in t for s in SPORTS):
        return False
    cat_movie = says_movie(categories)
    cat_non = (not cat_movie) and says_non_movie(categories)
    if cat_movie:
        return True
    if cat_non:
        return False
    if any(h in g or h in ch for h in MOVIE_CH):
        return True
    if t.startswith("movie:") or t.startswith("film:") or title.lower().startswith("movie:") or title.lower().startswith("film:"):
        return True
    if year is not None or re.search(r"\(\d{4}\)", title):
        return True
    if any(h in g or h in ch for h in SOFT) and len(clean) >= 4:
        return True
    words = clean.split()
    if not categories and len(words) >= 2 and len(clean) >= 8:
        return True
    return False


CASES = [
    # title, categories, group, name, expected
    ("Inception", ["Movie", "Drama"], "Premium", "HBO", True),
    ("Inception", ["Film"], None, "General", True),
    ("Monday Night Football", ["Sports"], "Sports", "ESPN", False),
    ("Some Drama Show", ["Series"], "Entertainment", "NBC", False),
    ("The Dark Knight HD", [], "USA", "USA Network", True),  # multi-word, no cat
    ("The Dark Knight HD", ["Series"], "USA", "USA Network", False),
    ("Lakers vs Celtics", [], "Sports", "NBA TV", False),
    ("Movie: Dune (2021)", [], "Other", "Ch1", True),
    ("No Information", ["Movie"], "Movies", "HBO", False),
    ("Random Show", ["News"], "News", "CNN", False),
    ("Película de acción", ["Cine"], None, None, True),
]


def main() -> int:
    failed = 0
    for title, cats, group, name, exp in CASES:
        got = is_movie(title, cats, group, name)
        ok = got == exp
        mark = "OK" if ok else "FAIL"
        if not ok:
            failed += 1
        print(f"[{mark}] movie={got!s:5} exp={exp!s:5} | {title!r} cats={cats} group={group!r} name={name!r}")
    print(f"\n{len(CASES) - failed}/{len(CASES)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env bash
# Top-ranked page's file does NOT exist in the fixture source; the lower one does.
# Exercises the relevance-floor anchor: the floor must attach to the first READABLE
# page (note-beta), not the unreadable top, or note-beta gets wrongly cut.
echo "[0.99] does-not-exist-page --"
echo "[0.40] note-beta --"

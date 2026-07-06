#!/usr/bin/env bash
# `query` returns a top slug that is NOT in the fixture mirror; `get` of that slug
# DOES return a body — exercises the bounded gbrain-get fallback for mirror misses.
if [ "$1" = "query" ]; then
  echo "[0.90] live-only-page --"
elif [ "$1" = "get" ] && [ "$2" = "live-only-page" ]; then
  echo "This page exists only in the full brain, not the mirror. Live-fetched body."
fi

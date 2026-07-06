#!/usr/bin/env bash
# `query` returns THREE top slugs, all absent from the fixture mirror; each `get`
# returns a distinct body — exercises the PARALLEL multi-miss prefetch and the cap.
if [ "$1" = "query" ]; then
  echo "[0.90] miss-one --"
  echo "[0.85] miss-two --"
  echo "[0.80] miss-three --"
elif [ "$1" = "get" ]; then
  case "$2" in
    miss-one) echo "Body of the first live-only page." ;;
    miss-two) echo "Body of the second live-only page." ;;
    miss-three) echo "Body of the third live-only page." ;;
  esac
fi

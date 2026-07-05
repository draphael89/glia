# Deploying the site

The site is a static Next.js export (`output: 'export'` → `out/`). It contains
**only aggregate experiment numbers** — no private brain content. Verified
deploy-ready: `next build` succeeds and exports 4 static pages.

## Vercel (one command)

Requires a one-time login (browser/email — only you can do this):

```bash
cd site
npx vercel login          # first time only
npx vercel --prod         # builds (next build) and publishes
```

Vercel auto-detects Next.js and serves the static export. That's it.

- Preview first (not indexed, shareable): `npx vercel` (no `--prod`).
- Promote a preview to production later from the Vercel dashboard, or re-run
  `npx vercel --prod`.

## Any static host (no Vercel)

```bash
cd site && npm run build      # produces ./out
# then serve or upload ./out anywhere (Netlify drop, S3, GitHub Pages, `npx serve out`)
```

## What's published

`app/results.ts` holds the numbers shown — Borda scores, blind pairwise
win-rates, rubric averages, control pass rates. All aggregate. The raw
per-answer results (which contain personal material) live in
`experiments/psyche-injection/results/raw/` and are **gitignored**, never built
into the site.

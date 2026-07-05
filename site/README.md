# glia.dev — the psyche-injection thesis, published

Static Next.js site presenting the [experiment](../experiments/psyche-injection)
and the [Glia](../) stack.

## Local
```bash
npm install && npm run dev      # http://localhost:3000
npm run build                   # static export → out/
```

## Deploy (Vercel)
```bash
npx vercel --prod               # or: connect the repo, root = site/
```
Static export (`output: 'export'`), no server, no external calls — deploys anywhere.

#include <metal_stdlib>
using namespace metal;

// Shared with GraphRenderer.swift — keep layouts in lockstep.

struct Uniforms {
    float2 viewport;      // drawable size in pixels
    float2 center;        // camera center in world units
    float  zoom;          // pixels per world unit
    float  time;          // seconds, for subtle animation
    float  dimStrength;   // 0..1, how hard non-focused elements dim
    float  _pad;
};

struct NodeInstance {
    float2 position;      // world
    float  radius;        // world units
    float  flags;         // bit0 selected, bit1 hovered, bit2 dimmed
    float4 color;         // straight alpha
};

struct EdgeInstance {
    float2 a;
    float2 b;
    float4 color;         // straight alpha; dimming baked CPU-side
};

// ─────────────────────────────── Background ───────────────────────────────
// Fullscreen deep-space gradient with a soft center bloom and vignette.

struct BGOut {
    float4 position [[position]];
    float2 uv;
};

vertex BGOut bg_vertex(uint vid [[vertex_id]]) {
    // fullscreen triangle
    float2 pos[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    BGOut out;
    out.position = float4(pos[vid], 0, 1);
    out.uv = pos[vid] * 0.5 + 0.5;
    return out;
}

static inline float hash21(float2 p) {
    p = fract(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

// One parallax layer of world-anchored star dust. `depth` < 1 pans slower
// than the graph — the brain floats in front of a deeper sky.
static float starLayer(float2 fragPx, constant Uniforms& u,
                       float depth, float cellPx, float seed) {
    // world position of this fragment, at a layer that zooms at sqrt(zoom) so stars
    // never blow up in SIZE. But size and PAN must be decoupled: a star's screen pan
    // rate is (pan coeff)·layerZoom, so panning at `u.center·depth` gives depth·sqrt(zoom)·8,
    // whose ratio to the graph's own pan rate (u.zoom) is depth·8/sqrt(zoom) — that
    // exceeds 1 at normal zoom, so the "distant sky" slid FASTER than the brain. Drive
    // the pan by the graph's zoom instead (÷layerZoom cancels the size scaling), so the
    // on-screen rate is exactly depth·u.zoom — a depth<1 layer always pans slower.
    float layerZoom = max(sqrt(u.zoom) * 8.0, 0.001);
    float2 world = (fragPx - u.viewport * 0.5) / layerZoom
                 + u.center * depth * (u.zoom / layerZoom);
    float2 cell = floor(world / cellPx);
    float h = hash21(cell + seed);
    if (h > 0.22) return 0.0;                       // sparse
    float2 starPos = (cell + float2(hash21(cell + seed + 1.7),
                                    hash21(cell + seed + 4.2))) * cellPx;
    float distPx = length(world - starPos) * layerZoom;
    float twinkle = 0.75 + 0.25 * sin(u.time * (0.6 + h * 3.0) + h * 40.0);
    float bright = (0.35 + 0.65 * hash21(cell + seed + 9.1)) * twinkle;
    return bright * exp(-distPx * distPx * 0.9);
}

fragment float4 bg_fragment(BGOut in [[stage_in]],
                            constant Uniforms& u [[buffer(0)]]) {
    float2 p = in.uv - 0.5;
    p.x *= u.viewport.x / u.viewport.y;
    float r = length(p);
    // base: near-black indigo, gently brighter toward center
    float3 base = float3(0.043, 0.051, 0.071);            // #0B0D12
    float3 deep = float3(0.024, 0.027, 0.039);
    float3 col = mix(base, deep, smoothstep(0.15, 0.95, r));
    // whisper of violet bloom in the center
    col += float3(0.10, 0.08, 0.18) * exp(-r * r * 6.0) * 0.35;

    // two parallax dust layers, one faint violet, one cool white
    float2 fragPx = in.uv * u.viewport;
    float far = starLayer(fragPx, u, 0.30, 26.0, 3.0);
    float near = starLayer(fragPx, u, 0.55, 42.0, 11.0);
    col += float3(0.55, 0.55, 0.72) * far * 0.14;
    col += float3(0.70, 0.66, 0.92) * near * 0.20;

    return float4(col, 1.0);
}

// ────────────────────────────────── Edges ─────────────────────────────────
// Each edge is an instanced quad expanded to screen-space width.

struct EdgeOut {
    float4 position [[position]];
    float4 color;
    float  across;   // -1..1 across the line, for soft AA falloff
};

vertex EdgeOut edge_vertex(uint vid [[vertex_id]],
                           uint iid [[instance_id]],
                           const device EdgeInstance* edges [[buffer(0)]],
                           constant Uniforms& u [[buffer(1)]]) {
    EdgeInstance e = edges[iid];
    float2 aPx = (e.a - u.center) * u.zoom;
    float2 bPx = (e.b - u.center) * u.zoom;
    float2 dir = bPx - aPx;
    float len = max(length(dir), 0.001);
    dir /= len;
    float2 normal = float2(-dir.y, dir.x);

    // Width: hairline that breathes with zoom — thicker when you dive in
    // (tangibility), clamped for AA head-room.
    float w = clamp(0.55 * sqrt(u.zoom), 0.6, 2.4);

    // vid: 0..3 -> (a,-1) (a,+1) (b,-1) (b,+1), triangle strip
    bool atB = (vid >= 2);
    float side = (vid & 1) ? 1.0 : -1.0;
    float2 px = (atB ? bPx : aPx) + normal * side * (w + 1.0); // +1px AA apron

    EdgeOut out;
    out.position = float4(2.0 * px.x / u.viewport.x, -2.0 * px.y / u.viewport.y, 0, 1);
    out.color = e.color;
    out.across = side * (w + 1.0) / w;
    return out;
}

fragment float4 edge_fragment(EdgeOut in [[stage_in]],
                              constant Uniforms& u [[buffer(0)]]) {
    float d = abs(in.across);
    // Fade the web slightly at far zoom so clusters read as shapes,
    // full presence once you dive toward a neighborhood.
    float zoomFactor = mix(0.55, 1.0, smoothstep(0.4, 3.0, u.zoom));
    float alpha = in.color.a * zoomFactor * saturate(1.0 - smoothstep(0.75, 1.0, d));
    return float4(in.color.rgb * alpha, alpha);   // premultiplied
}

// ────────────────────────────────── Nodes ─────────────────────────────────
// Instanced quads; SDF disc with rim light and an outer glow halo.

struct NodeOut {
    float4 position [[position]];
    float2 local;        // -1..1 quad space
    float4 color;
    float  screenRadius; // px
    float  flags;
};

vertex NodeOut node_vertex(uint vid [[vertex_id]],
                           uint iid [[instance_id]],
                           const device NodeInstance* nodes [[buffer(0)]],
                           constant Uniforms& u [[buffer(1)]]) {
    NodeInstance n = nodes[iid];
    float2 corners[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
    float2 corner = corners[vid];

    float screenR = max(n.radius * u.zoom, 1.6);
    bool hovered = (int(n.flags) & 2) != 0;
    bool selected = (int(n.flags) & 1) != 0;
    bool starred = (int(n.flags) & 32) != 0;
    if (hovered) screenR *= 1.18;
    // starred nodes stay a legible beacon even in a distant overview
    if (starred) screenR = max(screenR, 3.2);

    // glow apron: quad extends past the disc so the halo has room
    float apron = (selected || starred) ? 3.2 : 2.2;
    float2 centerPx = (n.position - u.center) * u.zoom;
    float2 px = centerPx + corner * screenR * apron;

    NodeOut out;
    out.position = float4(2.0 * px.x / u.viewport.x, -2.0 * px.y / u.viewport.y, 0, 1);
    out.local = corner * apron;
    out.color = n.color;
    out.screenRadius = screenR;
    out.flags = n.flags;
    return out;
}

fragment float4 node_fragment(NodeOut in [[stage_in]],
                              constant Uniforms& u [[buffer(0)]]) {
    float r = length(in.local);            // 1.0 == disc edge
    int flags = int(in.flags);
    bool selected = (flags & 1) != 0;
    bool hovered  = (flags & 2) != 0;
    bool dimmed   = (flags & 4) != 0;
    bool dust     = (flags & 16) != 0;

    if (dust) {
        // dark-matter points: a soft speck, no glow, no lighting
        float aaD = 1.5 / max(in.screenRadius, 1.0);
        float body = 1.0 - smoothstep(1.0 - aaD, 1.0 + aaD, r);
        float alpha = in.color.a * body * 0.13;
        return float4(in.color.rgb * alpha * 0.8, alpha);
    }

    float aa = 1.5 / max(in.screenRadius, 1.0);   // px-accurate AA band

    // disc body with a soft inner gradient (lit from upper-left).
    // Blend the lit term in away from the center — normalize() degenerates
    // at r→0 and reads as a cone artifact otherwise.
    float body = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
    float2 lightDir = normalize(float2(-0.45, -0.6));
    float2 n2 = in.local / max(r, 1e-3);
    float lit = 0.86 + 0.14 * saturate(dot(n2, -lightDir));
    float lambert = mix(1.0, lit, smoothstep(0.08, 0.55, r));
    float3 fill = in.color.rgb * lambert;

    // rim light
    float rim = smoothstep(0.72, 0.97, r) * (1.0 - smoothstep(0.97, 1.0 + aa, r));
    fill += in.color.rgb * rim * 0.55 + float3(rim * 0.08);

    // outer glow halo
    bool newborn = (flags & 8) != 0;
    float glowSpan = selected ? 2.9 : (newborn ? 2.6 : 1.9);
    float glow = exp(-max(r - 1.0, 0.0) * (4.5 / glowSpan));
    float glowAmp = selected ? 0.50 : (hovered ? 0.34 : 0.16);
    if (newborn) glowAmp += 0.42;
    // gentle breathing on selection
    if (selected) glowAmp *= 0.9 + 0.1 * sin(u.time * 2.2);

    float alpha = in.color.a * body;
    float3 col = fill * alpha + in.color.rgb * glow * glowAmp * (1.0 - body) * in.color.a;
    float outAlpha = alpha + glow * glowAmp * (1.0 - body) * in.color.a;

    // starred (identity collection): a warm-gold glow beacon + crisp rim so
    // your curated "who I am" set is findable across the whole constellation,
    // at any zoom. Glow reads even when the disc is a couple of pixels.
    bool starred = (flags & 32) != 0;
    if (starred) {
        float3 gold = float3(1.0, 0.82, 0.35);
        float ring = smoothstep(0.80, 0.98, r) * (1.0 - smoothstep(0.98, 1.06, r));
        float goldGlow = exp(-max(r - 1.0, 0.0) * 2.4) * (1.0 - body);
        col += gold * (ring * 0.7 + goldGlow * 0.6);
        outAlpha += ring * 0.7 + goldGlow * 0.6;
    }

    if (dimmed) { col *= (1.0 - u.dimStrength * 0.82); outAlpha *= (1.0 - u.dimStrength * 0.72); }
    return float4(col, outAlpha);          // premultiplied
}

#!/usr/bin/env python3
"""Build caladan_automation_guide.html from the canonical markdown.

Produces a single self-contained file: dark Unraid-adjacent styling, six inline
SVG diagrams, no external dependencies (no CDN, no webfonts, no JS libraries).
"""

import re
import markdown

SRC = "caladan_automation_guide.md"
DST = "caladan_automation_guide.html"

# ---------------------------------------------------------------------------
# Palette (kept in one place so the SVGs and CSS cannot drift apart)
# ---------------------------------------------------------------------------
C = {
    "bg":      "#16181a",
    "panel":   "#1e2124",
    "panel2":  "#25292d",
    "border":  "#33383d",
    "text":    "#dfe3e6",
    "muted":   "#8a9299",
    "accent":  "#ff8c2b",   # Unraid orange
    "green":   "#5cc97a",
    "red":     "#e5544b",
    "blue":    "#4d9de0",
    "purple":  "#a98bdc",
    "yellow":  "#e0b64d",
}

# ---------------------------------------------------------------------------
# SVG diagrams
# ---------------------------------------------------------------------------

SVG_PIPELINE = f"""
<figure class="diagram">
<svg viewBox="0 0 980 460" xmlns="http://www.w3.org/2000/svg" role="img"
     aria-label="End-to-end media pipeline from Prowlarr through the seedbox to Plex and Tdarr">
  <defs>
    <marker id="ah" markerWidth="9" markerHeight="9" refX="8" refY="3"
            orient="auto" markerUnits="strokeWidth">
      <path d="M0,0 L0,6 L9,3 z" fill="{C['muted']}"/>
    </marker>
    <marker id="ahg" markerWidth="9" markerHeight="9" refX="8" refY="3"
            orient="auto" markerUnits="strokeWidth">
      <path d="M0,0 L0,6 L9,3 z" fill="{C['green']}"/>
    </marker>
  </defs>

  <rect x="8" y="8" width="452" height="200" rx="8"
        fill="none" stroke="{C['border']}" stroke-dasharray="4 4"/>
  <text x="24" y="30" fill="{C['muted']}" font-size="12" font-weight="600"
        letter-spacing="1.2">SEEDBOX — ibiza.seedhost.eu</text>

  <rect x="520" y="8" width="452" height="440" rx="8"
        fill="none" stroke="{C['border']}" stroke-dasharray="4 4"/>
  <text x="536" y="30" fill="{C['muted']}" font-size="12" font-weight="600"
        letter-spacing="1.2">CALADAN — 192.168.1.12</text>

  <!-- seedbox side -->
  <rect x="32" y="48" width="180" height="46" rx="6" fill="{C['panel2']}" stroke="{C['border']}"/>
  <text x="122" y="70" fill="{C['text']}" font-size="14" text-anchor="middle">Prowlarr</text>
  <text x="122" y="86" fill="{C['muted']}" font-size="11" text-anchor="middle">indexer search</text>

  <rect x="32" y="130" width="180" height="46" rx="6" fill="{C['panel2']}" stroke="{C['accent']}"/>
  <text x="122" y="152" fill="{C['text']}" font-size="14" text-anchor="middle">qBittorrent</text>
  <text x="122" y="168" fill="{C['muted']}" font-size="11" text-anchor="middle">14-day seed limit</text>

  <rect x="256" y="130" width="180" height="46" rx="6" fill="{C['panel2']}" stroke="{C['border']}"/>
  <text x="346" y="152" fill="{C['text']}" font-size="14" text-anchor="middle">~/Media-sync/</text>
  <text x="346" y="168" fill="{C['muted']}" font-size="11" text-anchor="middle">sonarr · radarr · lidarr</text>

  <line x1="122" y1="94" x2="122" y2="126" stroke="{C['muted']}" marker-end="url(#ah)"/>
  <line x1="212" y1="153" x2="250" y2="153" stroke="{C['muted']}" marker-end="url(#ah)"/>

  <!-- transport -->
  <line x1="436" y1="153" x2="540" y2="153" stroke="{C['green']}" stroke-width="2" marker-end="url(#ahg)"/>
  <text x="488" y="144" fill="{C['green']}" font-size="11" text-anchor="middle">Syncthing</text>
  <text x="488" y="172" fill="{C['muted']}" font-size="10" text-anchor="middle">Send → Receive Only</text>

  <!-- manual path -->
  <path d="M346 176 L346 300 L540 300" fill="none" stroke="{C['purple']}"
        stroke-width="2" stroke-dasharray="5 4" marker-end="url(#ah)"/>
  <text x="352" y="286" fill="{C['purple']}" font-size="11">FileZilla FTP — from prowlarr/</text>

  <!-- caladan side -->
  <rect x="544" y="130" width="192" height="46" rx="6" fill="{C['panel2']}" stroke="{C['green']}"/>
  <text x="640" y="152" fill="{C['text']}" font-size="13" text-anchor="middle">download/sync/</text>
  <text x="640" y="168" fill="{C['muted']}" font-size="11" text-anchor="middle">Receive Only</text>

  <rect x="544" y="278" width="192" height="46" rx="6" fill="{C['panel2']}" stroke="{C['purple']}"/>
  <text x="640" y="300" fill="{C['text']}" font-size="13" text-anchor="middle">download/manual/</text>
  <text x="640" y="316" fill="{C['muted']}" font-size="11" text-anchor="middle">outside sync tree</text>

  <rect x="770" y="94" width="180" height="42" rx="6" fill="{C['panel2']}" stroke="{C['border']}"/>
  <text x="860" y="112" fill="{C['text']}" font-size="13" text-anchor="middle">Unpackerr</text>
  <text x="860" y="127" fill="{C['muted']}" font-size="10" text-anchor="middle">RAR extract</text>

  <rect x="770" y="152" width="180" height="42" rx="6" fill="{C['panel2']}" stroke="{C['border']}"/>
  <text x="860" y="170" fill="{C['text']}" font-size="13" text-anchor="middle">arr-rescans</text>
  <text x="860" y="185" fill="{C['muted']}" font-size="10" text-anchor="middle">every 5 min</text>

  <line x1="736" y1="145" x2="764" y2="118" stroke="{C['muted']}" marker-end="url(#ah)"/>
  <line x1="736" y1="160" x2="764" y2="170" stroke="{C['muted']}" marker-end="url(#ah)"/>

  <rect x="640" y="352" width="290" height="44" rx="6" fill="{C['panel2']}" stroke="{C['accent']}"/>
  <text x="785" y="374" fill="{C['text']}" font-size="13" text-anchor="middle">Sonarr · Radarr · Lidarr</text>
  <text x="785" y="389" fill="{C['muted']}" font-size="10" text-anchor="middle">8989 · 7878 · 8686</text>

  <path d="M860 194 L860 340" fill="none" stroke="{C['muted']}" marker-end="url(#ah)"/>
  <path d="M640 324 L640 340" fill="none" stroke="{C['purple']}" stroke-dasharray="5 4" marker-end="url(#ah)"/>

  <rect x="640" y="414" width="140" height="30" rx="6" fill="{C['panel2']}" stroke="{C['border']}"/>
  <text x="710" y="434" fill="{C['text']}" font-size="12" text-anchor="middle">Plex / Jellyfin</text>
  <rect x="796" y="414" width="134" height="30" rx="6" fill="{C['panel2']}" stroke="{C['border']}"/>
  <text x="863" y="434" fill="{C['text']}" font-size="12" text-anchor="middle">Tdarr</text>

  <line x1="740" y1="396" x2="712" y2="410" stroke="{C['muted']}" marker-end="url(#ah)"/>
  <line x1="830" y1="396" x2="861" y2="410" stroke="{C['muted']}" marker-end="url(#ah)"/>
</svg>
<figcaption>Two ingest paths converge on the *arrs: the automated Syncthing route (green) and the
manual FileZilla route (violet), which bypasses the Syncthing tree entirely.</figcaption>
</figure>
"""

SVG_STIGNORE = f"""
<figure class="diagram">
<svg viewBox="0 0 900 350" xmlns="http://www.w3.org/2000/svg" role="img"
     aria-label="Correct versus incorrect .stignore rule ordering">
  <text x="20" y="26" fill="{C['green']}" font-size="13" font-weight="700">CORRECT — first match wins</text>
  <rect x="20" y="38" width="400" height="252" rx="6" fill="{C['panel2']}" stroke="{C['green']}"/>

  <rect x="36" y="54" width="368" height="66" rx="4" fill="{C['bg']}" stroke="{C['border']}"/>
  <text x="48" y="74" fill="{C['red']}" font-size="12" font-weight="600">1 · EXCLUSIONS</text>
  <text x="48" y="92" fill="{C['muted']}" font-size="11" font-family="monospace">(?d)*.nfo  (?d)*.!qB</text>
  <text x="48" y="108" fill="{C['muted']}" font-size="11" font-family="monospace">(?d)/sonarr/**/*.jpg</text>

  <rect x="36" y="132" width="368" height="66" rx="4" fill="{C['bg']}" stroke="{C['border']}"/>
  <text x="48" y="152" fill="{C['blue']}" font-size="12" font-weight="600">2 · INCLUDES</text>
  <text x="48" y="170" fill="{C['muted']}" font-size="11" font-family="monospace">!/sonarr    !/sonarr/**</text>
  <text x="48" y="186" fill="{C['muted']}" font-size="11" font-family="monospace">!/radarr    !/lidarr</text>

  <rect x="36" y="210" width="368" height="42" rx="4" fill="{C['bg']}" stroke="{C['border']}"/>
  <text x="48" y="230" fill="{C['accent']}" font-size="12" font-weight="600">3 · CATCH-ALL</text>
  <text x="48" y="246" fill="{C['muted']}" font-size="11" font-family="monospace">*</text>

  <text x="36" y="276" fill="{C['green']}" font-size="11">✓ every rule is reachable</text>

  <text x="480" y="26" fill="{C['red']}" font-size="13" font-weight="700">WRONG — exclusions below includes</text>
  <rect x="480" y="38" width="400" height="252" rx="6" fill="{C['panel2']}" stroke="{C['red']}"/>

  <rect x="496" y="54" width="368" height="66" rx="4" fill="{C['bg']}" stroke="{C['border']}"/>
  <text x="508" y="74" fill="{C['blue']}" font-size="12" font-weight="600">1 · INCLUDES</text>
  <text x="508" y="92" fill="{C['muted']}" font-size="11" font-family="monospace">!/sonarr/**</text>
  <text x="508" y="108" fill="{C['muted']}" font-size="11" font-family="monospace">matches everything below</text>

  <rect x="496" y="132" width="368" height="66" rx="4" fill="{C['bg']}"
        stroke="{C['red']}" stroke-dasharray="4 3"/>
  <text x="508" y="152" fill="{C['red']}" font-size="12" font-weight="600">2 · EXCLUSIONS — DEAD CODE</text>
  <text x="508" y="170" fill="{C['muted']}" font-size="11" font-family="monospace"
        text-decoration="line-through">(?d)/sonarr/**/*.jpg</text>
  <text x="508" y="186" fill="{C['muted']}" font-size="11" font-family="monospace"
        text-decoration="line-through">(?d)*.nfo</text>

  <rect x="496" y="210" width="368" height="42" rx="4" fill="{C['bg']}" stroke="{C['border']}"/>
  <text x="508" y="234" fill="{C['muted']}" font-size="11" font-family="monospace">*</text>

  <text x="496" y="276" fill="{C['red']}" font-size="11">✗ .jpg and .nfo sync anyway — never evaluated</text>

  <rect x="20" y="306" width="860" height="32" rx="5" fill="{C['panel']}" stroke="{C['yellow']}"/>
  <text x="36" y="326" fill="{C['yellow']}" font-size="11">
    Recursive form alone is insufficient: /sonarr/**/*.jpg does not match a .jpg at the root of sonarr/. Both variants are required.
  </text>
</svg>
<figcaption>Syncthing evaluates <code>.stignore</code> top-down and stops at the first match. An exclusion
placed after an include never runs.</figcaption>
</figure>
"""

SVG_PATHMAP = f"""
<figure class="diagram">
<svg viewBox="0 0 960 400" xmlns="http://www.w3.org/2000/svg" role="img"
     aria-label="Host to container path mapping across the arr applications and Unpackerr">
  <defs>
    <marker id="ah2" markerWidth="9" markerHeight="9" refX="8" refY="3"
            orient="auto" markerUnits="strokeWidth">
      <path d="M0,0 L0,6 L9,3 z" fill="{C['muted']}"/>
    </marker>
  </defs>

  <text x="20" y="26" fill="{C['muted']}" font-size="12" font-weight="700" letter-spacing="1.2">HOST</text>
  <text x="600" y="26" fill="{C['muted']}" font-size="12" font-weight="700" letter-spacing="1.2">CONTAINER</text>

  <rect x="20" y="40" width="420" height="26" rx="4" fill="{C['panel2']}" stroke="{C['border']}"/>
  <text x="32" y="58" fill="{C['text']}" font-size="12" font-family="monospace">/mnt/user/media/download/sync/</text>

  <rect x="48" y="78" width="392" height="26" rx="4" fill="{C['bg']}" stroke="{C['accent']}"/>
  <text x="60" y="96" fill="{C['accent']}" font-size="12" font-family="monospace">├── sonarr/</text>
  <rect x="48" y="112" width="392" height="26" rx="4" fill="{C['bg']}" stroke="{C['blue']}"/>
  <text x="60" y="130" fill="{C['blue']}" font-size="12" font-family="monospace">├── radarr/</text>
  <rect x="48" y="146" width="392" height="26" rx="4" fill="{C['bg']}" stroke="{C['green']}"/>
  <text x="60" y="164" fill="{C['green']}" font-size="12" font-family="monospace">├── lidarr/</text>
  <rect x="48" y="180" width="392" height="26" rx="4" fill="{C['bg']}"
        stroke="{C['border']}" stroke-dasharray="4 3"/>
  <text x="60" y="198" fill="{C['muted']}" font-size="12" font-family="monospace">└── prowlarr/   (ignored)</text>

  <rect x="20" y="230" width="420" height="26" rx="4" fill="{C['panel2']}" stroke="{C['purple']}"/>
  <text x="32" y="248" fill="{C['purple']}" font-size="12" font-family="monospace">/mnt/user/media/download/manual/</text>

  <rect x="20" y="290" width="420" height="26" rx="4" fill="{C['panel2']}" stroke="{C['border']}"/>
  <text x="32" y="308" fill="{C['text']}" font-size="12" font-family="monospace">/mnt/cache/appdata/&lt;app&gt;/</text>

  <!-- arrows -->
  <line x1="440" y1="91"  x2="596" y2="70"  stroke="{C['accent']}" marker-end="url(#ah2)"/>
  <line x1="440" y1="125" x2="596" y2="118" stroke="{C['blue']}"   marker-end="url(#ah2)"/>
  <line x1="440" y1="159" x2="596" y2="166" stroke="{C['green']}"  marker-end="url(#ah2)"/>
  <line x1="440" y1="53"  x2="596" y2="220" stroke="{C['muted']}"  stroke-dasharray="4 3" marker-end="url(#ah2)"/>
  <line x1="440" y1="243" x2="596" y2="268" stroke="{C['purple']}" marker-end="url(#ah2)"/>
  <line x1="440" y1="303" x2="596" y2="316" stroke="{C['muted']}"  marker-end="url(#ah2)"/>

  <rect x="600" y="52" width="340" height="34" rx="5" fill="{C['panel2']}" stroke="{C['accent']}"/>
  <text x="614" y="74" fill="{C['text']}" font-size="12" font-family="monospace">Sonarr    /downloads</text>

  <rect x="600" y="100" width="340" height="34" rx="5" fill="{C['panel2']}" stroke="{C['blue']}"/>
  <text x="614" y="122" fill="{C['text']}" font-size="12" font-family="monospace">Radarr    /downloads</text>

  <rect x="600" y="148" width="340" height="34" rx="5" fill="{C['panel2']}" stroke="{C['green']}"/>
  <text x="614" y="170" fill="{C['text']}" font-size="12" font-family="monospace">Lidarr    /downloads</text>

  <rect x="600" y="200" width="340" height="40" rx="5" fill="{C['panel2']}" stroke="{C['yellow']}"/>
  <text x="614" y="219" fill="{C['yellow']}" font-size="12" font-family="monospace">Unpackerr /downloads</text>
  <text x="614" y="234" fill="{C['muted']}" font-size="10">mounted at sync ROOT — sees all subdirs</text>

  <rect x="600" y="252" width="340" height="34" rx="5" fill="{C['panel2']}" stroke="{C['purple']}"/>
  <text x="614" y="274" fill="{C['text']}" font-size="12" font-family="monospace">all *arrs  /manual</text>

  <rect x="600" y="300" width="340" height="34" rx="5" fill="{C['panel2']}" stroke="{C['border']}"/>
  <text x="614" y="322" fill="{C['text']}" font-size="12" font-family="monospace">all *arrs  /config</text>

  <rect x="20" y="350" width="920" height="38" rx="5" fill="{C['panel']}" stroke="{C['yellow']}"/>
  <text x="36" y="368" fill="{C['yellow']}" font-size="11" font-weight="600">Each *arr consumes its own path segment.</text>
  <text x="36" y="383" fill="{C['muted']}" font-size="11">
    /downloads on Sonarr IS sync/sonarr/ — so Sonarr cannot see prowlarr/. Unpackerr alone is mounted at the root. Remote path mappings must therefore be app-specific.
  </text>
</svg>
<figcaption>Mount scoping explains both the app-specific remote path mappings and the need for a
separate <code>/manual</code> staging mount.</figcaption>
</figure>
"""

SVG_PINNED = f"""
<figure class="diagram">
<svg viewBox="0 0 920 330" xmlns="http://www.w3.org/2000/svg" role="img"
     aria-label="Correct and incorrect deletion lifecycle for a Receive Only Syncthing folder">
  <defs>
    <marker id="ah3" markerWidth="9" markerHeight="9" refX="8" refY="3"
            orient="auto" markerUnits="strokeWidth">
      <path d="M0,0 L0,6 L9,3 z" fill="{C['green']}"/>
    </marker>
    <marker id="ah4" markerWidth="9" markerHeight="9" refX="8" refY="3"
            orient="auto" markerUnits="strokeWidth">
      <path d="M0,0 L0,6 L9,3 z" fill="{C['red']}"/>
    </marker>
  </defs>

  <text x="20" y="24" fill="{C['green']}" font-size="13" font-weight="700">✓ CORRECT — deletion originates on the seedbox</text>
  <rect x="20" y="34" width="880" height="106" rx="6" fill="{C['panel2']}" stroke="{C['green']}"/>

  <rect x="40" y="56" width="180" height="62" rx="5" fill="{C['bg']}" stroke="{C['border']}"/>
  <text x="130" y="80" fill="{C['text']}" font-size="12" text-anchor="middle">qBittorrent</text>
  <text x="130" y="96" fill="{C['muted']}" font-size="10" text-anchor="middle">14 days elapsed</text>
  <text x="130" y="110" fill="{C['muted']}" font-size="10" text-anchor="middle">RemoveWithContent</text>

  <rect x="290" y="56" width="180" height="62" rx="5" fill="{C['bg']}" stroke="{C['border']}"/>
  <text x="380" y="82" fill="{C['text']}" font-size="12" text-anchor="middle">Seedbox files gone</text>
  <text x="380" y="102" fill="{C['muted']}" font-size="10" text-anchor="middle">global.deleted = true</text>

  <rect x="540" y="56" width="180" height="62" rx="5" fill="{C['bg']}" stroke="{C['border']}"/>
  <text x="630" y="82" fill="{C['text']}" font-size="12" text-anchor="middle">Syncthing propagates</text>
  <text x="630" y="102" fill="{C['muted']}" font-size="10" text-anchor="middle">deletion inward</text>

  <rect x="750" y="56" width="130" height="62" rx="5" fill="{C['bg']}" stroke="{C['green']}"/>
  <text x="815" y="82" fill="{C['green']}" font-size="12" text-anchor="middle">Caladan clean</text>
  <text x="815" y="102" fill="{C['muted']}" font-size="10" text-anchor="middle">counter drains</text>

  <line x1="220" y1="87" x2="284" y2="87" stroke="{C['green']}" marker-end="url(#ah3)"/>
  <line x1="470" y1="87" x2="534" y2="87" stroke="{C['green']}" marker-end="url(#ah3)"/>
  <line x1="720" y1="87" x2="744" y2="87" stroke="{C['green']}" marker-end="url(#ah3)"/>

  <text x="20" y="176" fill="{C['red']}" font-size="13" font-weight="700">✗ WRONG — deletion originates locally</text>
  <rect x="20" y="186" width="880" height="106" rx="6" fill="{C['panel2']}" stroke="{C['red']}"/>

  <rect x="40" y="208" width="180" height="62" rx="5" fill="{C['bg']}" stroke="{C['border']}"/>
  <text x="130" y="234" fill="{C['text']}" font-size="12" text-anchor="middle">rm on Caladan</text>
  <text x="130" y="254" fill="{C['muted']}" font-size="10" text-anchor="middle">or Move-mode import</text>

  <rect x="290" y="208" width="180" height="62" rx="5" fill="{C['bg']}" stroke="{C['border']}"/>
  <text x="380" y="234" fill="{C['text']}" font-size="12" text-anchor="middle">Receive Only folder</text>
  <text x="380" y="254" fill="{C['muted']}" font-size="10" text-anchor="middle">diverges from global</text>

  <rect x="540" y="208" width="180" height="62" rx="5" fill="{C['bg']}" stroke="{C['red']}"/>
  <text x="630" y="234" fill="{C['red']}" font-size="12" text-anchor="middle">Re-fetched from remote</text>
  <text x="630" y="254" fill="{C['muted']}" font-size="10" text-anchor="middle">next scan cycle</text>

  <rect x="750" y="208" width="130" height="62" rx="5" fill="{C['bg']}" stroke="{C['red']}"/>
  <text x="815" y="234" fill="{C['red']}" font-size="12" text-anchor="middle">Pinned delete</text>
  <text x="815" y="254" fill="{C['muted']}" font-size="10" text-anchor="middle">never resolves</text>

  <line x1="220" y1="239" x2="284" y2="239" stroke="{C['red']}" marker-end="url(#ah4)"/>
  <line x1="470" y1="239" x2="534" y2="239" stroke="{C['red']}" marker-end="url(#ah4)"/>
  <line x1="720" y1="239" x2="744" y2="239" stroke="{C['red']}" marker-end="url(#ah4)"/>

  <rect x="20" y="302" width="880" height="24" rx="4" fill="{C['panel']}" stroke="{C['yellow']}"/>
  <text x="34" y="318" fill="{C['yellow']}" font-size="11">
    Corollary: import from the sync tree with mode COPY. Import from /manual with mode MOVE — that path is outside the tree.
  </text>
</svg>
<figcaption>The pinned-delete lifecycle. Deletions must flow inward from the seedbox; anything
originating on Caladan is undone on the next sync.</figcaption>
</figure>
"""

SVG_GUARDS = f"""
<figure class="diagram">
<svg viewBox="0 0 760 560" xmlns="http://www.w3.org/2000/svg" role="img"
     aria-label="arr-rescans guard chain evaluated per candidate item">
  <defs>
    <marker id="ah5" markerWidth="9" markerHeight="9" refX="8" refY="3"
            orient="auto" markerUnits="strokeWidth">
      <path d="M0,0 L0,6 L9,3 z" fill="{C['muted']}"/>
    </marker>
  </defs>

  <rect x="248" y="12" width="264" height="38" rx="19" fill="{C['panel2']}" stroke="{C['accent']}"/>
  <text x="380" y="36" fill="{C['accent']}" font-size="13" text-anchor="middle" font-weight="600">candidate item</text>

  <g font-size="12">
    <!-- rows: y, label, detail, outcome-colour -->
    <rect x="200" y="70" width="360" height="42" rx="6" fill="{C['panel2']}" stroke="{C['border']}"/>
    <text x="216" y="88" fill="{C['text']}">1 · empty directory?</text>
    <text x="216" y="104" fill="{C['muted']}" font-size="10">leftover _unpackerred husk</text>

    <rect x="200" y="128" width="360" height="42" rx="6" fill="{C['panel2']}" stroke="{C['border']}"/>
    <text x="216" y="146" fill="{C['text']}">2 · *sync-conflict*?</text>
    <text x="216" y="162" fill="{C['muted']}" font-size="10">folder- and file-shaped variants</text>

    <rect x="200" y="186" width="360" height="42" rx="6" fill="{C['panel2']}" stroke="{C['border']}"/>
    <text x="216" y="204" fill="{C['text']}">3 · *_unpackerred?</text>
    <text x="216" y="220" fill="{C['muted']}" font-size="10">v4.6.1 — never a valid scan target</text>

    <rect x="200" y="244" width="360" height="42" rx="6" fill="{C['panel2']}" stroke="{C['border']}"/>
    <text x="216" y="262" fill="{C['text']}">4 · in import history?</text>
    <text x="216" y="278" fill="{C['muted']}" font-size="10">eventType=3 · data.droppedPath</text>

    <rect x="200" y="302" width="360" height="42" rx="6" fill="{C['panel2']}" stroke="{C['red']}"/>
    <text x="216" y="320" fill="{C['text']}">5 · suspicious files?</text>
    <text x="216" y="336" fill="{C['muted']}" font-size="10">.exe .bat .com .scr .js .vbs → alert once</text>

    <rect x="200" y="360" width="360" height="42" rx="6" fill="{C['panel2']}" stroke="{C['blue']}"/>
    <text x="216" y="378" fill="{C['text']}">6 · settle guard</text>
    <text x="216" y="394" fill="{C['muted']}" font-size="10">byte signature stable N cycles — NOT mtime</text>

    <rect x="200" y="418" width="360" height="42" rx="6" fill="{C['panel2']}" stroke="{C['yellow']}"/>
    <text x="216" y="436" fill="{C['text']}">7 · RAR guard</text>
    <text x="216" y="452" fill="{C['muted']}" font-size="10">rars present AND no settled video → defer</text>
  </g>

  <line x1="380" y1="50"  x2="380" y2="66"  stroke="{C['muted']}" marker-end="url(#ah5)"/>
  <line x1="380" y1="112" x2="380" y2="124" stroke="{C['muted']}" marker-end="url(#ah5)"/>
  <line x1="380" y1="170" x2="380" y2="182" stroke="{C['muted']}" marker-end="url(#ah5)"/>
  <line x1="380" y1="228" x2="380" y2="240" stroke="{C['muted']}" marker-end="url(#ah5)"/>
  <line x1="380" y1="286" x2="380" y2="298" stroke="{C['muted']}" marker-end="url(#ah5)"/>
  <line x1="380" y1="344" x2="380" y2="356" stroke="{C['muted']}" marker-end="url(#ah5)"/>
  <line x1="380" y1="402" x2="380" y2="414" stroke="{C['muted']}" marker-end="url(#ah5)"/>
  <line x1="380" y1="460" x2="380" y2="480" stroke="{C['green']}" marker-end="url(#ah5)"/>

  <rect x="236" y="484" width="288" height="38" rx="19" fill="{C['panel2']}" stroke="{C['green']}"/>
  <text x="380" y="508" fill="{C['green']}" font-size="13" text-anchor="middle" font-weight="600">
    queue DownloadedEpisodesScan
  </text>

  <g font-size="11">
    <text x="576" y="96"  fill="{C['muted']}">skip</text>
    <text x="576" y="154" fill="{C['muted']}">skip</text>
    <text x="576" y="212" fill="{C['muted']}">skip</text>
    <text x="576" y="270" fill="{C['muted']}">skip</text>
    <text x="576" y="328" fill="{C['red']}">skip + alert</text>
    <text x="576" y="386" fill="{C['blue']}">defer</text>
    <text x="576" y="444" fill="{C['yellow']}">defer + alert @120m</text>
  </g>
  <g stroke="{C['border']}" stroke-dasharray="3 3">
    <line x1="560" y1="91"  x2="572" y2="91"/>
    <line x1="560" y1="149" x2="572" y2="149"/>
    <line x1="560" y1="207" x2="572" y2="207"/>
    <line x1="560" y1="265" x2="572" y2="265"/>
    <line x1="560" y1="323" x2="572" y2="323"/>
    <line x1="560" y1="381" x2="572" y2="381"/>
    <line x1="560" y1="439" x2="572" y2="439"/>
  </g>

  <rect x="16" y="360" width="170" height="100" rx="6" fill="{C['panel']}" stroke="{C['blue']}"/>
  <text x="30" y="380" fill="{C['blue']}" font-size="11" font-weight="600">Why size, not mtime?</text>
  <text x="30" y="398" fill="{C['muted']}" font-size="10">Syncthing preserves the</text>
  <text x="30" y="412" fill="{C['muted']}" font-size="10">SOURCE mtime, so a file</text>
  <text x="30" y="426" fill="{C['muted']}" font-size="10">that landed 30s ago can</text>
  <text x="30" y="440" fill="{C['muted']}" font-size="10">carry an hours-old stamp.</text>
  <text x="30" y="454" fill="{C['muted']}" font-size="10">Byte count is local truth.</text>

  <rect x="16" y="176" width="170" height="72" rx="6" fill="{C['panel']}" stroke="{C['red']}"/>
  <text x="30" y="196" fill="{C['red']}" font-size="11" font-weight="600">OPEN GAP</text>
  <text x="30" y="214" fill="{C['muted']}" font-size="10">No .syncthing.*.tmp check.</text>
  <text x="30" y="228" fill="{C['muted']}" font-size="10">A 24/26-complete pack can</text>
  <text x="30" y="242" fill="{C['muted']}" font-size="10">pass the settle guard.</text>
</svg>
<figcaption>Guards are evaluated in order and short-circuit. Gates 1–5 skip permanently; gates 6–7
defer and retry on the next five-minute cycle.</figcaption>
</figure>
"""

SVG_TRIAGE = f"""
<figure class="diagram">
<svg viewBox="0 0 940 520" xmlns="http://www.w3.org/2000/svg" role="img"
     aria-label="Triage flow for a release that has not imported">
  <defs>
    <marker id="ah6" markerWidth="9" markerHeight="9" refX="8" refY="3"
            orient="auto" markerUnits="strokeWidth">
      <path d="M0,0 L0,6 L9,3 z" fill="{C['muted']}"/>
    </marker>
  </defs>

  <rect x="350" y="10" width="240" height="36" rx="18" fill="{C['panel2']}" stroke="{C['accent']}"/>
  <text x="470" y="33" fill="{C['accent']}" font-size="13" text-anchor="middle" font-weight="600">
    release has not imported
  </text>

  <rect x="330" y="70" width="280" height="40" rx="6" fill="{C['panel2']}" stroke="{C['border']}"/>
  <text x="470" y="88" fill="{C['text']}" font-size="12" text-anchor="middle">files present on disk?</text>
  <text x="470" y="103" fill="{C['muted']}" font-size="10" text-anchor="middle" font-family="monospace">ls sync/&lt;app&gt;/</text>

  <rect x="30" y="150" width="250" height="72" rx="6" fill="{C['panel2']}" stroke="{C['blue']}"/>
  <text x="155" y="170" fill="{C['blue']}" font-size="12" text-anchor="middle" font-weight="600">NO — still transferring</text>
  <text x="46" y="190" fill="{C['muted']}" font-size="10" font-family="monospace">rest/db/completion</text>
  <text x="46" y="205" fill="{C['muted']}" font-size="10">100 + needItems 0 = done</text>
  <text x="46" y="218" fill="{C['muted']}" font-size="10">otherwise: wait, no action</text>

  <rect x="330" y="150" width="280" height="40" rx="6" fill="{C['panel2']}" stroke="{C['border']}"/>
  <text x="470" y="168" fill="{C['text']}" font-size="12" text-anchor="middle">any .syncthing.*.tmp left?</text>
  <text x="470" y="183" fill="{C['muted']}" font-size="10" text-anchor="middle" font-family="monospace">find … -name '.syncthing.*'</text>

  <rect x="330" y="228" width="280" height="40" rx="6" fill="{C['panel2']}" stroke="{C['border']}"/>
  <text x="470" y="246" fill="{C['text']}" font-size="12" text-anchor="middle">manualimport returns clean?</text>
  <text x="470" y="261" fill="{C['muted']}" font-size="10" text-anchor="middle">episodes mapped, zero rejections</text>

  <rect x="660" y="228" width="250" height="72" rx="6" fill="{C['panel2']}" stroke="{C['red']}"/>
  <text x="785" y="248" fill="{C['red']}" font-size="12" text-anchor="middle" font-weight="600">NO — read the rejections</text>
  <text x="676" y="268" fill="{C['muted']}" font-size="10">"meets cutoff" → already at target</text>
  <text x="676" y="282" fill="{C['muted']}" font-size="10">"equal or higher CF score" → profile</text>
  <text x="676" y="295" fill="{C['muted']}" font-size="10">"?x?" → filename did not parse</text>

  <rect x="330" y="306" width="280" height="40" rx="6" fill="{C['panel2']}" stroke="{C['border']}"/>
  <text x="470" y="324" fill="{C['text']}" font-size="12" text-anchor="middle">queue stuck at importPending?</text>
  <text x="470" y="339" fill="{C['muted']}" font-size="10" text-anchor="middle">"No files found are eligible"</text>

  <rect x="300" y="384" width="340" height="58" rx="6" fill="{C['panel2']}" stroke="{C['green']}"/>
  <text x="470" y="404" fill="{C['green']}" font-size="12" text-anchor="middle" font-weight="600">
    stale queue state — message is FALSE
  </text>
  <text x="470" y="422" fill="{C['muted']}" font-size="10" text-anchor="middle">
    POST ManualImport payload built from the manualimport endpoint
  </text>
  <text x="470" y="436" fill="{C['muted']}" font-size="10" text-anchor="middle" font-family="monospace">
    importMode: "copy"   (sync tree)
  </text>

  <rect x="30" y="384" width="250" height="58" rx="6" fill="{C['panel2']}" stroke="{C['yellow']}"/>
  <text x="155" y="404" fill="{C['yellow']}" font-size="12" text-anchor="middle" font-weight="600">RAR present, no video?</text>
  <text x="46" y="422" fill="{C['muted']}" font-size="10">Unpackerr cached a bad path</text>
  <text x="46" y="436" fill="{C['muted']}" font-size="10" font-family="monospace">docker restart unpackerr</text>

  <rect x="300" y="466" width="340" height="42" rx="6" fill="{C['panel2']}" stroke="{C['accent']}"/>
  <text x="470" y="484" fill="{C['accent']}" font-size="12" text-anchor="middle" font-weight="600">then clear stale queue entries</text>
  <text x="470" y="499" fill="{C['muted']}" font-size="10" text-anchor="middle" font-family="monospace">
    DELETE queue/&lt;id&gt;?removeFromClient=false
  </text>

  <line x1="470" y1="46"  x2="470" y2="66"  stroke="{C['muted']}" marker-end="url(#ah6)"/>
  <path d="M330 90 L155 90 L155 146" fill="none" stroke="{C['muted']}" marker-end="url(#ah6)"/>
  <line x1="470" y1="110" x2="470" y2="146" stroke="{C['muted']}" marker-end="url(#ah6)"/>
  <line x1="470" y1="190" x2="470" y2="224" stroke="{C['muted']}" marker-end="url(#ah6)"/>
  <line x1="610" y1="248" x2="656" y2="248" stroke="{C['muted']}" marker-end="url(#ah6)"/>
  <line x1="470" y1="268" x2="470" y2="302" stroke="{C['muted']}" marker-end="url(#ah6)"/>
  <line x1="470" y1="346" x2="470" y2="380" stroke="{C['muted']}" marker-end="url(#ah6)"/>
  <path d="M330 326 L155 326 L155 380" fill="none" stroke="{C['muted']}" marker-end="url(#ah6)"/>
  <line x1="470" y1="442" x2="470" y2="462" stroke="{C['muted']}" marker-end="url(#ah6)"/>

  <text x="622" y="244" fill="{C['red']}" font-size="10">no</text>
  <text x="300" y="86"  fill="{C['blue']}" font-size="10">no</text>
</svg>
<figcaption>Triage order matters: confirm delivery before blaming the importer. A "no files eligible"
message on a complete, cleanly-parsing folder is stale queue state, not an evaluation.</figcaption>
</figure>
"""

# ---------------------------------------------------------------------------
# Injection points — (marker regex, svg, position)
# ---------------------------------------------------------------------------
INJECTIONS = [
    (r'(<h3 id="pipeline">Pipeline</h3>\s*<pre><code>.*?</code></pre>)', SVG_PIPELINE),
    (r'(<h3 id="33-ignore-patterns">3\.3 Ignore Patterns</h3>)', SVG_STIGNORE),
    (r'(<h3 id="36-revert-local-changes-hazard">.*?</h3>)', SVG_PINNED),
    (r'(<h3 id="41-docker-path-mappings">4\.1 Docker Path Mappings</h3>)', SVG_PATHMAP),
    (r'(<h3 id="62-arr-rescans-v461">.*?</h3>)', SVG_GUARDS),
    (r'(<h2 id="8-known-issues-workarounds">.*?</h2>)', SVG_TRIAGE),
]


ANCHOR_REMAP = {
    "8-known-issues--workarounds": "8-known-issues-workarounds",
    "86-arr-rescans-has-no-syncthing-tmp-guard": "86-arr-rescans-has-no-syncthingtmp-guard",
}


def check_links(doc):
    ids = set(re.findall(r'<h[1-6] id="([^"]+)"', doc))
    links = re.findall(r'href="#([^"]+)"', doc)
    broken = sorted({l for l in links if l not in ids})
    if broken:
        raise SystemExit(f"  FAIL: broken internal anchors: {broken}")
    print(f"  {len(links)} internal links, all resolve")


def lint_source(md_text):
    """python-markdown's fenced_code preprocessor runs before blockquote
    parsing, so a fence prefixed with '>' is never detected: the block leaks as
    raw text and any '#' comment inside becomes a heading. Fail loudly."""
    bad = [i for i, line in enumerate(md_text.splitlines(), 1)
           if line.lstrip().startswith("> ```")]
    if bad:
        raise SystemExit(
            f"  FAIL: fenced code inside a blockquote at line(s) {bad}. "
            "Move the code block outside the '>' quote."
        )
    print("  source lint clean")


def build():
    with open(SRC, encoding="utf-8") as fh:
        md_text = fh.read()

    lint_source(md_text)

    html_body = markdown.markdown(
        md_text,
        extensions=["tables", "fenced_code", "toc", "attr_list", "sane_lists"],
        extension_configs={"toc": {"permalink": False}},
    )

    # GitHub and python-markdown slugify '&' and '.' differently. The markdown
    # source uses GitHub-style anchors (correct in the repo); remap them here so
    # the standalone HTML resolves too. Verified by the link check in build().
    for gh_anchor, pmd_anchor in ANCHOR_REMAP.items():
        html_body = html_body.replace(f'href="#{gh_anchor}"', f'href="#{pmd_anchor}"')

    injected = 0
    for pattern, svg in INJECTIONS:
        new_body, n = re.subn(
            pattern, lambda m: m.group(1) + svg, html_body, count=1, flags=re.S
        )
        if n:
            html_body = new_body
            injected += 1
        else:
            print(f"  WARN: no match for {pattern[:60]}…")
    print(f"  injected {injected}/{len(INJECTIONS)} diagrams")

    doc = TEMPLATE.replace("{{BODY}}", html_body)
    check_links(doc)
    with open(DST, "w", encoding="utf-8") as fh:
        fh.write(doc)
    print(f"  wrote {DST} ({len(doc):,} bytes)")


TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Caladan Media Automation — Configuration &amp; Rebuild Guide</title>
<style>
  :root {
    --bg: %(bg)s;
    --panel: %(panel)s;
    --panel2: %(panel2)s;
    --border: %(border)s;
    --text: %(text)s;
    --muted: %(muted)s;
    --accent: %(accent)s;
    --green: %(green)s;
    --red: %(red)s;
    --blue: %(blue)s;
    --yellow: %(yellow)s;
    --mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas,
            "Liberation Mono", monospace;
  }
  * { box-sizing: border-box; }
  html { scroll-behavior: smooth; }
  body {
    margin: 0;
    background: var(--bg);
    color: var(--text);
    font: 15px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
          "Helvetica Neue", Arial, sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  .wrap { max-width: 1060px; margin: 0 auto; padding: 40px 28px 120px; }

  h1 {
    font-size: 30px; line-height: 1.25; margin: 0 0 6px;
    color: #fff; letter-spacing: -0.3px;
  }
  h1 + p { color: var(--muted); margin-top: 0; }

  h2 {
    font-size: 22px; margin: 52px 0 16px; padding-bottom: 9px;
    border-bottom: 2px solid var(--accent); color: #fff;
    letter-spacing: -0.2px;
  }
  h3 {
    font-size: 17px; margin: 32px 0 10px; color: var(--accent);
    font-weight: 600;
  }
  h4 { font-size: 15px; margin: 22px 0 8px; color: var(--text); }

  p { margin: 0 0 14px; }
  a { color: var(--blue); text-decoration: none; }
  a:hover { text-decoration: underline; }

  code {
    font-family: var(--mono); font-size: 0.875em;
    background: var(--panel2); border: 1px solid var(--border);
    border-radius: 4px; padding: 1px 5px; color: #f0d9a8;
  }
  pre {
    background: var(--panel); border: 1px solid var(--border);
    border-left: 3px solid var(--accent);
    border-radius: 6px; padding: 14px 16px; overflow-x: auto;
    margin: 0 0 18px;
  }
  pre code {
    background: none; border: 0; padding: 0; color: #d6dde3;
    font-size: 12.5px; line-height: 1.6;
  }

  table {
    border-collapse: collapse; width: 100%%; margin: 0 0 20px;
    font-size: 13.5px; background: var(--panel);
    border: 1px solid var(--border); border-radius: 6px;
    overflow: hidden;
  }
  th {
    background: var(--panel2); color: var(--accent);
    text-align: left; padding: 9px 12px; font-weight: 600;
    border-bottom: 1px solid var(--border); white-space: nowrap;
  }
  td {
    padding: 8px 12px; border-bottom: 1px solid var(--border);
    vertical-align: top;
  }
  tr:last-child td { border-bottom: 0; }
  tr:hover td { background: rgba(255,255,255,0.022); }
  td code { font-size: 12px; }

  blockquote {
    margin: 0 0 18px; padding: 12px 16px;
    background: var(--panel); border-left: 3px solid var(--yellow);
    border-radius: 0 6px 6px 0; color: #d9dde0;
  }
  blockquote p:last-child { margin-bottom: 0; }
  blockquote strong { color: var(--yellow); }

  ul, ol { margin: 0 0 16px; padding-left: 24px; }
  li { margin-bottom: 5px; }
  li input[type=checkbox] { margin-right: 6px; }

  hr { border: 0; border-top: 1px solid var(--border); margin: 40px 0; }

  strong { color: #fff; font-weight: 600; }

  figure.diagram {
    margin: 24px 0 28px; padding: 20px 20px 14px;
    background: var(--panel); border: 1px solid var(--border);
    border-radius: 8px;
  }
  figure.diagram svg { width: 100%%; height: auto; display: block; }
  figure.diagram figcaption {
    margin-top: 14px; padding-top: 12px;
    border-top: 1px solid var(--border);
    font-size: 12.5px; color: var(--muted); line-height: 1.55;
  }
  figure.diagram figcaption code {
    font-size: 11.5px; background: var(--panel2);
  }

  /* Table of contents */
  h2#table-of-contents + ol {
    background: var(--panel); border: 1px solid var(--border);
    border-radius: 6px; padding: 16px 16px 16px 40px;
    columns: 2; column-gap: 32px;
  }
  h2#table-of-contents + ol li { break-inside: avoid; }

  @media (max-width: 720px) {
    .wrap { padding: 24px 16px 80px; }
    h1 { font-size: 24px; }
    h2 { font-size: 19px; }
    table { font-size: 12.5px; }
    h2#table-of-contents + ol { columns: 1; }
  }
  @media print {
    body { background: #fff; color: #000; }
    .wrap { max-width: none; }
    pre, table, figure.diagram { break-inside: avoid; }
  }
</style>
</head>
<body>
<div class="wrap">
{{BODY}}
</div>
</body>
</html>
""" % C


if __name__ == "__main__":
    build()

# Architecture Plan: The "Iron-Rust" Plant Encyclopedia

## 1. Core Philosophy: Server-Authoritative "Storefront"

We treat the browser as a "Storefront" and the Server as the "Factory".

- **Logic:** Stays 100% on the Server (Rust). Secure, fast, up-to-date.
- **UI:** Rendered as HTML. Enhanced with "Sprinkles" of JS for feel.
- **State:** Lives in the Database/URL, not in the browser memory.

## 2. The Stack (H.A.R.M.)

- **H**TMX: Handling network interactions (The "AJAX" layer).
- **A**xum: The Async Web Server.
- **R**ust: The brain.
- **M**aud / **A**skama: The HTML Renderer (Compile-time speed).

## 3. Frontend UX Strategy ("Bells & Whistles")

### A. The "Gamified" Guild Builder

- **Interaction:** Drag-and-Drop.
- **Library:** **SortableJS** (Client-side).
- **Flow:**
  1. **User Drags:** SortableJS moves the DOM element *instantly*. (0ms latency).
  2. **Event:** SortableJS triggers htmx.trigger('#guild-list', 'update').
  3. **Network:** HTMX sends POST /guild/update with the new plant order.
  4. **Server:** Rust recalculates Synergy Score using DataFusion.
  5. **Response:** Server returns specific HTML snippets (e.g., `<div id="score">98%</div>`).
  6. **Update:** HTMX swaps *only* the score number.
- **Result:** Feels native. No full page reloads.

### B. The "Beautiful" Encyclopedia & Gallery

- **Interaction:** Navigation & Media Viewing.
- **Technology:** **View Transitions API** + CSS + **Lazy Loading**.
- **Flow:**
  1. User clicks a plant card.
  2. HTMX fetches the detail page.
  3. **Photos:** The HTML contains standard `<img>` tags pointing to your R2 Media CDN.
     - `<img src="https://media.yourdomain.com/tomato_01.webp" loading="lazy">`
  4. **Transition:** Browser *morphs* the thumbnail into the full-size hero image using View Transitions.
- **Result:** App-like feel. Images load directly from the Edge (R2), saving your VPS bandwidth.

### C. Client-Side "Sprinkles"

- **Library:** **Alpine.js**.
- **Use Case:** Toggles, Dropdowns, Modals, "Dark Mode," **Image Carousels**.
- **Rule:** If it doesn't need database data, handle it in Alpine.

### D. The Zero-Build Asset Strategy (No NPM)

We avoid the complexity of node_modules, Webpack, and Vite.

1. **Vendoring:** We download the .min.js files for HTMX, Alpine, and SortableJS once.
2. **Storage:** These files live in the /assets/js/ folder of the Rust project.
3. **Serving:** The Axum server embeds these files into the binary (using rust-embed) or serves them from disk.
4. **Benefit:** The entire application is a **single self-contained executable**. You can SCP the binary to a server, and it "just works" without needing npm install on the server.

### E. Styling & Visuals (The "High-End" Look)

A Monolith does not mean "Plain Text." You can use modern design tools seamlessly.

- **Tailwind CSS:** Run the Tailwind CLI in "watch" mode during development. It scans your Rust templates (.html or .rs) and generates a single styles.css file.
  - *Deployment:* This tiny CSS file is embedded into your Rust binary.
- **Graphics:** Use inline SVGs in your templates. Rust templates (Askama) handle SVG text just like HTML, allowing you to dynamically color icons based on "Plant Synergy" (e.g., leaf turns green if nitrogen is high).
- **Fonts:** Serve .woff2 font files directly from your binary. Zero dependency on Google Fonts (privacy-friendly).

## 4. Data Flow & Logic

### Engine A: The "Brain" (Read-Only)

- **Tech:** Apache DataFusion + Parquet.
- **Role:** Stores 11.7K plant metadata + Synergy Rules.
- **Location:** Local NVMe Disk (Memory Mapped).
- **Speed:** Instant.

### Engine B: The "Memory" (Read-Write)

- **Tech:** Turso (libSQL Embedded Replica).
- **Role:** Stores User Guilds, Settings, Logs.
- **Location:** Local SQLite File (Synced to Cloud).

## Engine C: The "Media Library" (Storage)

- **Tech:** **Cloudflare R2** (Object Storage).
- **Role:** Stores ~117,000 Plant Photos (10 per plant).
- **Location:** Global Distributed Network (CDN).
- **Why:**
  - **Zero Egress Fees:** You pay nothing when users view photos.
  - **Zero Server Load:** Your Rust CPU is never touched by image traffic.
  - **Infinite Scale:** You can add 1 million photos without upgrading your VPS disk.

## 5. Infrastructure Map

### The "Edge" (Delivery)

- **Nodes:** 3-4 High-Performance VPS (Tokyo, Sydney, Frankfurt, US-East).
- **Software:** Single Rust Binary (Axum).
- **Role:** Low-latency content delivery and user interaction.
- **Static Assets (JS/CSS):** Embedded in the binary.
- **Media Assets (Images):** Served via **Cloudflare R2**.

### The "Core" (Build & Batch)

- **Node:** Home Server (Living Room) - **Bare Metal**.
- **Role:**
  - Compiles Rust Binaries (Heavy CPU load).
  - Ingests/Cleans raw data -> Parquet.
  - Optimizes Images (WebP conversion) -> Uploads to R2.
  - Deploys to Edge via WireGuard Mesh.

## 6. Future Evolution: The Farm Management SaaS

When you add complex farm management features, the architecture expands rather than breaks.

### A. The "Write-Heavy" Split (CQRS)

- **User Action:** Farmer uploads 500MB of drone imagery or 10k sensor logs.
- **Routing:** These requests bypass the Edge Nodes (Tokyo/Sydney) and go directly to the **Core** (Germany/Home).
- **Why:** Keeps the Edge nodes fast for encyclopedia readers.
- **Storage:** Images go to **Cloudflare R2**. Logs go to **PostgreSQL/TimescaleDB** on the Core server.

### B. The Native Mobile App (Offline Field Mode)

This is a separate build for offline reliability, connecting to the same backend logic.

- **Technology:** **Tauri Mobile** (Rust) or **Flutter**.
  - *Why Tauri?* It allows you to reuse your Rust business logic types and sync logic directly on the phone.
- **Architecture:** "Dual-Head" Backend.
  - **Web Users:** Axum returns **HTML** (via Askama).
  - **Mobile Users:** Axum returns **JSON** (via Serde) from the *exact same* functions.
- **Data Sync:** The mobile app downloads a subset of the Turso/SQLite DB to the phone's storage for offline use. When back online, it pushes changes to the API.

## 7. Why this beats Google Cloud Run & React

1. **The "95% Compiler" Safety Net:** Unlike a JavaScript stack where data errors (undefined is not a function) explode in the user's browser at runtime, **95%** of your stack **passes through rustc**.
   - If your HTML template references a missing field? **Compile Error.**
   - If your SQL query expects a String but gets an Int? **Compile Error.**
   - This level of safety eliminates entire classes of bugs before they ever reach production.

2. **True Simplicity vs. "Seeming" Simplicity:**
   - **Svelte/React:** Looks simple initially, but hides massive complexity: Syncing Client State vs Server State, hydration bugs, npm audit vulnerabilities, and build-chain fragility.
   - **Iron-Rust:** Is visually "raw" (writing HTML strings), but structurally simple. There is **one** state (Server). There is **one** Logic Language (Rust). There is **one** artifact (The Binary). It is easier to reason about 5 years from now.

3. **No "Stale Logic":** You update the synergy formula in Rust *once*, and every user globally gets the new math instantly. No waiting for them to clear browser cache.

4. **IP Protection:** Your complex guild math never leaves your server. Competitors can't steal it.

5. **Cost:** ~$22/mo total vs $300+ for comparable Cloud Run performance.

## 8. Complexity Analysis & Career Value

### The "Alphabet Soup" vs. The "Black Box"

You expressed concern about using multiple tools (HTMX, Alpine, Axum, Askama). It is important to distinguish between **Visible Complexity** and **Hidden Complexity**.

| Feature | Modern JS Stack (Svelte/React) | Iron-Rust Stack (Your Plan) |
|---------|--------------------------------|----------------------------|
| **Components** | Node.js + Vite + Babel + Webpack + NPM + Library + Framework | Rust Binary + 3 JS Files |
| **Failure Points** | Infinite (Dependency hell, breaking updates) | Minimal (Rust compiler checks everything) |
| **Mental Model** | "How do I sync the client state with the server state?" | "The Server is the only state." |
| **Longevity** | Code rots in 1-2 years due to ecosystem churn. | Code runs for 10+ years with minimal updates. |

### The "Resume Signal"

Choosing this stack sends a specific signal to hiring managers:

- **"Hybrid Infrastructure Management"**: You didn't just click "Deploy" on Vercel. You architected a distributed system across **Bare Metal (Home/Core)** and **Virtual (Cloud/Edge)** environments.
- **"Systems Engineering":** You understand how computers actually work (memory, IO, latency) rather than just how to glue API calls together.
- **"Cost Optimization":** You saved the company 90% on cloud bills by avoiding managed services and architecting for raw Linux performance.
- **"Self-Hosted / Homelab Experience":** You have hands-on experience with the messy reality of networking (WireGuard, DNS, Firewalls), which is increasingly rare in "Cloud-Native" developers.

**Verdict:** This is a "Senior/Staff Engineer" portfolio piece. A standard React app is a "Junior" portfolio piece.

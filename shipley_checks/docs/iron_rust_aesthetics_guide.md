# Iron-Rust Aesthetics Guide

## Design Philosophy

**"Organic Digital"** — A design language rooted in nature that feels alive in both daylight and moonlight.

Core principles:
- **Grounded**: Earth tones, natural materials, organic shapes
- **Readable**: Encyclopedia content needs clarity above all
- **Adaptive**: Same design DNA in light and dark modes
- **Restrained**: Let the plant data be the hero, not the UI

---

## 1. Color System

### 1.1 Semantic Palette

Colors derive from nature: soil, leaves, bark, sky, flowers.

| Token | Purpose | Light Mode | Dark Mode |
|-------|---------|------------|-----------|
| `--color-leaf` | Primary actions, links | `#2D5A3D` | `#86EFAC` |
| `--color-bark` | Secondary, borders | `#6B5B4F` | `#A1887F` |
| `--color-soil` | Neutral text | `#3D3529` | `#E7E5E4` |
| `--color-sky` | Info states | `#3B82F6` | `#60A5FA` |
| `--color-sun` | Warnings, light indicator | `#D97706` | `#FBBF24` |
| `--color-clay` | Errors, stress indicator | `#B45309` | `#F87171` |
| `--color-petal` | Accent, pollinator badge | `#A855F7` | `#C4B5FD` |

### 1.2 Surface Colors

| Token | Light Mode | Dark Mode |
|-------|------------|-----------|
| `--surface-ground` | `#FDFBF7` (cream) | `#1C1917` (deep brown) |
| `--surface-raised` | `#FFFFFF` | `#292524` |
| `--surface-sunken` | `#F5F0E8` | `#0C0A09` |
| `--surface-overlay` | `#FFFFFF` | `#44403C` |

### 1.3 DaisyUI Theme Configuration

```javascript
// tailwind.config.js
module.exports = {
  daisyui: {
    themes: [
      {
        organic: {
          "primary": "#2D5A3D",
          "primary-content": "#FFFFFF",
          "secondary": "#6B5B4F",
          "secondary-content": "#FFFFFF",
          "accent": "#A855F7",
          "accent-content": "#FFFFFF",
          "neutral": "#3D3529",
          "neutral-content": "#FDFBF7",
          "base-100": "#FDFBF7",
          "base-200": "#F5F0E8",
          "base-300": "#E8E0D4",
          "base-content": "#3D3529",
          "info": "#3B82F6",
          "success": "#22C55E",
          "warning": "#D97706",
          "error": "#DC2626",
        },
      },
      {
        "organic-dark": {
          "primary": "#86EFAC",
          "primary-content": "#1C1917",
          "secondary": "#A1887F",
          "secondary-content": "#1C1917",
          "accent": "#C4B5FD",
          "accent-content": "#1C1917",
          "neutral": "#E7E5E4",
          "neutral-content": "#1C1917",
          "base-100": "#1C1917",
          "base-200": "#292524",
          "base-300": "#44403C",
          "base-content": "#E7E5E4",
          "info": "#60A5FA",
          "success": "#4ADE80",
          "warning": "#FBBF24",
          "error": "#F87171",
        },
      },
    ],
  },
}
```

---

## 2. Typography

### 2.1 Font Stack

```css
/* Primary: readable, organic, slightly warm */
--font-body: 'DM Sans', system-ui, sans-serif;

/* Scientific names: italic distinction */
--font-species: 'DM Sans', system-ui, sans-serif; /* italic weight */

/* Monospace: data tables, codes */
--font-mono: 'JetBrains Mono', ui-monospace, monospace;
```

**Why DM Sans?** Geometric but softened corners. Professional without being cold. Good italic for species names.

### 2.2 Type Scale

| Name | Size | Weight | Use |
|------|------|--------|-----|
| `text-hero` | 3rem (48px) | 700 | Home page title |
| `text-h1` | 2rem (32px) | 600 | Page titles |
| `text-h2` | 1.5rem (24px) | 600 | Section headers |
| `text-h3` | 1.25rem (20px) | 500 | Card titles |
| `text-body` | 1rem (16px) | 400 | Paragraphs |
| `text-small` | 0.875rem (14px) | 400 | Captions, metadata |
| `text-micro` | 0.75rem (12px) | 500 | Badges, labels |

### 2.3 Species Name Convention

Scientific names always italic:

```html
<span class="font-medium"><em>Quercus robur</em></span>
<span class="text-base-content/60">English Oak</span>
```

---

## 3. Component Patterns

### 3.1 Cards

Organic cards have subtle warmth and natural shadows.

```html
<article class="card bg-base-100 shadow-md hover:shadow-lg
               transition-shadow duration-200 rounded-2xl">
  <div class="card-body">
    <!-- content -->
  </div>
</article>
```

**Rules:**
- Rounded corners: `rounded-2xl` (16px) for cards, `rounded-xl` (12px) for nested elements
- Shadows: Warm-tinted in light mode (`shadow-stone-200`), subtle in dark
- Hover: Gentle lift, not dramatic

### 3.2 Buttons

```html
<!-- Primary action -->
<button class="btn btn-primary rounded-xl">Search Plants</button>

<!-- Secondary -->
<button class="btn btn-outline btn-secondary rounded-xl">Cancel</button>

<!-- Ghost (navigation) -->
<button class="btn btn-ghost rounded-xl">Learn More</button>
```

### 3.3 Input Fields

```html
<input type="text"
       class="input input-bordered rounded-xl bg-base-200
              focus:bg-base-100 focus:border-primary
              placeholder:text-base-content/40">
```

### 3.4 Badges (EIVE Indicators)

Ecological indicators use nature-derived colors:

```html
<!-- Light indicator -->
<div class="badge bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200">
  L: 7.2
</div>

<!-- Moisture indicator -->
<div class="badge bg-sky-100 text-sky-800 dark:bg-sky-900 dark:text-sky-200">
  M: 5.4
</div>

<!-- Nitrogen fixer (special) -->
<div class="badge bg-emerald-100 text-emerald-800 dark:bg-emerald-900 dark:text-emerald-200">
  N-Fixer
</div>
```

---

## 4. Guild Score Visualization

### 4.1 Score Color Scale

Scores map to a natural gradient (stressed → thriving):

| Range | Meaning | Light Color | Dark Color | CSS Class |
|-------|---------|-------------|------------|-----------|
| 0-20 | Poor | `#FEE2E2` bg, `#991B1B` text | `#7F1D1D` bg, `#FECACA` text | `score-poor` |
| 21-40 | Weak | `#FEF3C7` bg, `#92400E` text | `#78350F` bg, `#FDE68A` text | `score-weak` |
| 41-60 | Fair | `#FEF9C3` bg, `#854D0E` text | `#713F12` bg, `#FEF08A` text | `score-fair` |
| 61-80 | Good | `#DCFCE7` bg, `#166534` text | `#14532D` bg, `#BBF7D0` text | `score-good` |
| 81-100 | Excellent | `#D1FAE5` bg, `#065F46` text | `#064E3B` bg, `#A7F3D0` text | `score-excellent` |

### 4.2 Score Display Component

```html
<div class="stats shadow rounded-2xl">
  <div class="stat">
    <div class="stat-title text-base-content/60">Guild Score</div>
    <div class="stat-value text-primary">78%</div>
    <div class="stat-desc text-success">Good compatibility</div>
  </div>
</div>
```

### 4.3 Metric Bars

```html
<div class="space-y-3">
  <!-- Single metric -->
  <div class="flex items-center gap-3">
    <span class="text-sm w-32 text-base-content/70">Phylo Diversity</span>
    <div class="flex-1 h-2 bg-base-200 rounded-full overflow-hidden">
      <div class="h-full bg-primary rounded-full" style="width: 72%"></div>
    </div>
    <span class="text-sm font-medium w-10 text-right">72%</span>
  </div>
</div>
```

---

## 5. Dark Mode Implementation

### 5.1 Theme Toggle

```html
<!-- In base.html -->
<html data-theme="organic" class="light">

<!-- Toggle button -->
<button
  x-data="{ dark: localStorage.getItem('theme') === 'organic-dark' }"
  x-init="$watch('dark', val => {
    document.documentElement.dataset.theme = val ? 'organic-dark' : 'organic';
    document.documentElement.classList.toggle('dark', val);
    localStorage.setItem('theme', val ? 'organic-dark' : 'organic');
  })"
  @click="dark = !dark"
  class="btn btn-ghost btn-circle">
  <svg x-show="!dark" class="w-5 h-5"><!-- sun icon --></svg>
  <svg x-show="dark" class="w-5 h-5"><!-- moon icon --></svg>
</button>
```

### 5.2 System Preference Detection

```html
<script>
  // Run before page renders to prevent flash
  (function() {
    const stored = localStorage.getItem('theme');
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    const theme = stored || (prefersDark ? 'organic-dark' : 'organic');
    document.documentElement.dataset.theme = theme;
    if (theme === 'organic-dark') document.documentElement.classList.add('dark');
  })();
</script>
```

### 5.3 Tailwind Dark Variants

For custom styling beyond DaisyUI:

```html
<!-- Example: custom hover states -->
<div class="bg-stone-100 dark:bg-stone-800
            text-stone-700 dark:text-stone-200
            hover:bg-stone-200 dark:hover:bg-stone-700">
```

---

## 6. Iconography

### 6.1 Icon Style

Use outline icons (not filled) for organic feel. Recommended: **Lucide Icons** (MIT license).

```html
<!-- Download as SVG, inline in templates -->
<svg class="w-5 h-5 stroke-current" viewBox="0 0 24 24" fill="none" stroke-width="2">
  <!-- icon path -->
</svg>
```

### 6.2 Key Icons

| Concept | Icon | Usage |
|---------|------|-------|
| Search | `search` | Search input |
| Plant | `leaf` or `flower-2` | Plant cards |
| Guild | `users` or `git-merge` | Guild builder |
| Light | `sun` | EIVE-L indicator |
| Water | `droplets` | EIVE-M indicator |
| Temperature | `thermometer` | EIVE-T indicator |
| Nitrogen | `zap` | N-fixer badge |
| Score up | `trending-up` | Good score |
| Score down | `trending-down` | Poor score |
| Dark mode | `moon` | Theme toggle |
| Light mode | `sun` | Theme toggle |

---

## 7. Spacing & Layout

### 7.1 Spacing Scale

Use Tailwind's default scale, prefer multiples of 4:

| Token | Value | Use |
|-------|-------|-----|
| `gap-2` | 8px | Inline elements, badges |
| `gap-4` | 16px | Card grid, form fields |
| `gap-6` | 24px | Sections within card |
| `gap-8` | 32px | Major sections |
| `py-16` | 64px | Page sections |

### 7.2 Container Width

```html
<main class="container mx-auto px-4 max-w-6xl">
```

### 7.3 Responsive Grid

```html
<!-- Plant card grid -->
<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">

<!-- Guild builder layout -->
<div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
  <div class="lg:col-span-2"><!-- Search --></div>
  <div class="lg:col-span-1"><!-- Guild panel --></div>
</div>
```

---

## 8. Motion & Transitions

### 8.1 Timing

```css
/* Standard transition */
transition-all duration-200 ease-out

/* Hover lift */
transition-shadow duration-200

/* Theme switch */
transition-colors duration-300
```

### 8.2 HTMX Loading States

```css
/* Subtle pulse while loading */
.htmx-request {
  opacity: 0.7;
  pointer-events: none;
}

.htmx-request .htmx-indicator {
  display: inline-flex;
}
```

---

## 9. Accessibility

### 9.1 Color Contrast

All text meets WCAG AA (4.5:1 for body, 3:1 for large text):
- Light mode: `#3D3529` on `#FDFBF7` = 10.5:1
- Dark mode: `#E7E5E4` on `#1C1917` = 12.3:1

### 9.2 Focus States

```css
/* Visible focus ring */
.btn:focus-visible,
.input:focus-visible {
  @apply outline-none ring-2 ring-primary ring-offset-2 ring-offset-base-100;
}
```

### 9.3 Reduced Motion

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

---

## 10. Asset Checklist

### Fonts (self-hosted)
- [ ] DM Sans (400, 500, 600, 700, 400 italic) → `assets/fonts/`
- [ ] JetBrains Mono (400) → `assets/fonts/`

### Icons (inline SVG)
- [ ] Lucide icon subset → embedded in templates

### CSS
- [ ] `input.css` with theme config
- [ ] `tailwindcss` CLI generates `assets/css/styles.css`

---

## Quick Reference: Class Snippets

```html
<!-- Primary card -->
card bg-base-100 shadow-md rounded-2xl

<!-- Plant name -->
font-medium italic

<!-- EIVE badge -->
badge bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200

<!-- Score excellent -->
badge bg-emerald-100 text-emerald-800 dark:bg-emerald-900 dark:text-emerald-200

<!-- Section header -->
text-h2 font-semibold text-base-content

<!-- Muted text -->
text-base-content/60

<!-- Page container -->
container mx-auto px-4 max-w-6xl py-8
```

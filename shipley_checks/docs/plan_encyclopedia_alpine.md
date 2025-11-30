# Encyclopedia Alpine.js Integration Plan

## Current State Analysis

### What's Working
- **V2 templates ARE active** - Route `/plant/:wfo_id/encyclopedia` uses `encyclopedia_page_v2`
- **Alpine.js is loaded** in `base.html` but barely used (only theme toggle)
- **DaisyUI styling** applied but inconsistently
- **View models** (`view_models.rs`) are well-structured

### Root Causes of "Ugly Formatting"

1. **Checkbox-based collapse** - Uses `<input type="checkbox">` hack:
   - Creates awkward click targets
   - No smooth height transitions
   - No proper ARIA states for accessibility
   - Content jumps abruptly

2. **Empty sections still render** - Many conditionals check `is_empty()` but outer containers still render with padding/margins

3. **Excessive spacing** - `space-y-4` and `space-y-8` compound into large gaps

4. **Static cards without visual hierarchy** - All sections look identical, no progressive disclosure

5. **No interactive polish** - Missing hover states, transitions, loading feedback

---

## Alpine.js Central Architecture

### Design Principles

1. **Alpine for local UI state** - Dropdowns, tabs, accordions, tooltips
2. **HTMX for server communication** - Search, location changes, data fetching
3. **DaisyUI for styling foundation** - But override collapse behavior with Alpine

### Component Patterns

#### 1. Accordion/Collapse with Alpine
Replace checkbox hack with proper Alpine component:

```html
<div x-data="{ open: false }" class="card bg-base-100 shadow-md rounded-xl overflow-hidden">
  <button
    @click="open = !open"
    :aria-expanded="open"
    class="w-full flex items-center justify-between p-5 text-left hover:bg-base-200/50 transition-colors"
  >
    <span class="flex items-center gap-3 font-medium">
      <svg>...</svg>
      Temperature
    </span>
    <svg
      class="w-5 h-5 stroke-current transition-transform duration-200"
      :class="{ 'rotate-180': open }"
      viewBox="0 0 24 24" fill="none" stroke-width="2"
    >
      <path d="m6 9 6 6 6-6"/>
    </svg>
  </button>

  <div
    x-show="open"
    x-collapse
    class="border-t border-base-200"
  >
    <div class="p-5">
      <!-- Content -->
    </div>
  </div>
</div>
```

#### 2. Tabs Component
For sections with multiple views (e.g., Requirements by category):

```html
<div x-data="{ tab: 'light' }">
  <div class="tabs tabs-boxed bg-base-200 p-1 rounded-xl">
    <button
      @click="tab = 'light'"
      :class="{ 'tab-active': tab === 'light' }"
      class="tab"
    >Light</button>
    <button
      @click="tab = 'temperature'"
      :class="{ 'tab-active': tab === 'temperature' }"
      class="tab"
    >Temperature</button>
    <!-- ... -->
  </div>

  <div class="mt-4">
    <div x-show="tab === 'light'" x-transition>
      <!-- Light content -->
    </div>
    <div x-show="tab === 'temperature'" x-transition>
      <!-- Temperature content -->
    </div>
  </div>
</div>
```

#### 3. Tooltip for Data Points
For EIVE values, CSR scores:

```html
<span
  x-data="{ show: false }"
  @mouseenter="show = true"
  @mouseleave="show = false"
  class="relative cursor-help"
>
  <span class="font-mono">{{ value }}</span>
  <div
    x-show="show"
    x-transition
    class="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 px-3 py-2 bg-base-300 rounded-lg text-sm shadow-lg z-10 whitespace-nowrap"
  >
    {{ tooltip_text }}
  </div>
</span>
```

#### 4. Card with Expandable Details

```html
<div
  x-data="{ expanded: false }"
  class="card bg-base-100 shadow-md rounded-xl"
>
  <div class="card-body p-5">
    <!-- Always visible summary -->
    <div class="flex items-center justify-between">
      <h3 class="font-medium">Pollinators</h3>
      <span class="badge badge-ghost">{{ count }} species</span>
    </div>

    <!-- Expandable detail -->
    <template x-if="expanded">
      <div class="mt-4 pt-4 border-t border-base-200">
        <!-- Full list -->
      </div>
    </template>

    <button
      @click="expanded = !expanded"
      class="btn btn-ghost btn-sm mt-2"
      x-text="expanded ? 'Show less' : 'Show more'"
    ></button>
  </div>
</div>
```

---

## Implementation Tasks

### Phase 1: Fix Spacing & Empty States
1. [ ] Add `x-show` guards to prevent empty section rendering
2. [ ] Replace `space-y-*` with consistent gap system
3. [ ] Add `@empty` states with helpful messages

### Phase 2: Replace Collapse Components
4. [ ] Create Alpine accordion component in `_requirements.html`
5. [ ] Migrate Temperature, Moisture, Soil sections
6. [ ] Add `x-collapse` plugin or CSS transitions

### Phase 3: Add Interactive Features
7. [ ] Tabbed interface for Requirements section
8. [ ] Tooltips for technical values (EIVE, CSR)
9. [ ] Expandable organism lists
10. [ ] Smooth transitions on all show/hide

### Phase 4: Polish
11. [ ] Hover states on all interactive elements
12. [ ] Loading indicators for HTMX requests
13. [ ] Keyboard navigation for accordions
14. [ ] Focus management

---

## File Changes Required

### Templates to Modify

| File | Changes |
|------|---------|
| `encyclopedia/_requirements.html` | Replace checkbox collapse with Alpine |
| `encyclopedia/_maintenance.html` | Add Alpine expand for tasks |
| `encyclopedia/_interactions.html` | Expandable organism lists |
| `encyclopedia/_services.html` | Tooltip for ecosystem service scores |
| `encyclopedia/_identity_card.html` | Minor polish |
| `encyclopedia/_companion.html` | Expandable companions |

### New Files

| File | Purpose |
|------|---------|
| `assets/js/components/accordion.js` | Reusable accordion Alpine component |
| `assets/css/transitions.css` | Smooth expand/collapse animations |

### Alpine Plugin Consideration

For smooth height animations, consider adding **Alpine Collapse plugin**:
```html
<script defer src="https://cdn.jsdelivr.net/npm/@alpinejs/collapse@3.x.x/dist/cdn.min.js"></script>
```

Or use CSS-based transitions with `grid-template-rows` trick.

---

## CSS Improvements

```css
/* Smooth collapse using grid trick */
.collapse-content {
  display: grid;
  grid-template-rows: 0fr;
  transition: grid-template-rows 0.3s ease-out;
}

.collapse-content.open {
  grid-template-rows: 1fr;
}

.collapse-content > div {
  overflow: hidden;
}
```

---

## Priority Order

1. **High Impact, Low Effort**
   - Fix empty state rendering
   - Replace checkbox collapses with Alpine

2. **High Impact, Medium Effort**
   - Tabbed requirements interface
   - Smooth transitions

3. **Medium Impact, Medium Effort**
   - Tooltips for data
   - Expandable lists

4. **Polish**
   - Keyboard navigation
   - Focus states

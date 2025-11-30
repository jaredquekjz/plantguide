# Encyclopedia Page Redesign Plan

## Problem Statement

Current approach generates markdown → converts to HTML → applies generic prose styles. Result: unprofessional, no visual hierarchy, no components.

## Solution: Structured Template Rendering

Replace markdown generation with structured Rust data types and dedicated Askama templates for each section.

---

## Architecture

### Current Flow (problematic)
```
plant_data → S1-S6 markdown generators → join → pulldown-cmark → HTML string → prose classes
```

### New Flow (proposed)
```
plant_data → EncyclopediaData struct → Askama template → rendered HTML with DaisyUI components
```

---

## Implementation Steps

### Phase 1: Data Structures (src/encyclopedia/view_models.rs)

Create view model structs for template rendering:

```rust
pub struct EncyclopediaPageData {
    pub identity: IdentityCard,
    pub requirements: RequirementsSection,
    pub maintenance: MaintenanceSection,
    pub services: EcosystemServices,
    pub interactions: InteractionsSection,
    pub companion: CompanionSection,
    pub location: LocationInfo,
}

pub struct IdentityCard {
    pub wfo_id: String,
    pub scientific_name: String,
    pub common_names: Vec<String>,
    pub chinese_names: Option<String>,
    pub family: String,
    pub growth_type: String,
    pub native_climate: Option<String>,
    pub height_m: Option<f64>,
    pub height_desc: String,
    pub leaf_desc: Option<String>,
    pub seed_desc: Option<String>,
    pub relatives: Vec<RelativeSpecies>,
    pub genus_count: usize,
}

pub struct RequirementsSection {
    pub light: LightRequirement,
    pub temperature: TemperatureEnvelope,
    pub moisture: MoistureEnvelope,
    pub soil: SoilEnvelope,
    pub local_comparison: Option<LocalComparison>,
}

// ... similar for other sections
```

### Phase 2: Template Structure

Create modular Askama templates:

```
templates/
├── pages/
│   └── encyclopedia.html          # Main page layout
└── encyclopedia/
    ├── _identity_card.html        # S1: Hero card with plant identity
    ├── _requirements.html         # S2: Collapsible requirements sections
    ├── _requirements_table.html   # Reusable comparison table
    ├── _maintenance.html          # S3: Maintenance cards
    ├── _services.html             # S4: Ecosystem service badges
    ├── _interactions.html         # S5: Organism interaction lists
    ├── _companion.html            # S6: Guild compatibility
    └── _suitability_badge.html    # Reusable fit indicator
```

### Phase 3: Component Designs

#### S1 Identity Card (Hero)
```html
<article class="card bg-base-100 shadow-lg rounded-2xl">
  <div class="card-body">
    <div class="flex items-start gap-6">
      <!-- Plant Icon (SVG) -->
      <div class="w-20 h-20 bg-primary/10 rounded-2xl flex items-center justify-center">
        <svg><!-- tree/shrub/herb icon based on growth form --></svg>
      </div>

      <!-- Identity Info -->
      <div class="flex-1">
        <h1 class="text-3xl font-semibold">
          <em>{{ identity.scientific_name }}</em>
        </h1>
        <p class="text-lg text-base-content/60 mt-1">
          {{ identity.common_names | join("; ") }}
        </p>

        <!-- Quick badges -->
        <div class="flex flex-wrap gap-2 mt-4">
          <span class="badge badge-outline">{{ identity.family }}</span>
          <span class="badge badge-primary">{{ identity.growth_type }}</span>
          {% if identity.height_desc %}
          <span class="badge badge-ghost">{{ identity.height_desc }}</span>
          {% endif %}
        </div>
      </div>
    </div>
  </div>
</article>
```

#### S2 Requirements (Collapsible Cards)
```html
<section class="space-y-4">
  <h2 class="text-xl font-semibold flex items-center gap-2">
    <svg><!-- settings icon --></svg>
    Growing Requirements
  </h2>

  <!-- Temperature Card -->
  <div class="collapse collapse-arrow bg-base-100 shadow rounded-xl">
    <input type="checkbox" checked />
    <div class="collapse-title font-medium flex items-center gap-2">
      <svg><!-- thermometer --></svg>
      Temperature
    </div>
    <div class="collapse-content">
      <!-- Data table with styled rows -->
      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr class="bg-base-200">
              <th>Parameter</th>
              <th>Your Location</th>
              <th>Plant Range</th>
              <th>Fit</th>
            </tr>
          </thead>
          <tbody>
            {% for row in requirements.temperature.comparisons %}
            <tr>
              <td>{{ row.label }}</td>
              <td class="font-mono">{{ row.local_value }}</td>
              <td class="font-mono text-base-content/60">{{ row.range }}</td>
              <td>{% include "_suitability_badge.html" %}</td>
            </tr>
            {% endfor %}
          </tbody>
        </table>
      </div>
    </div>
  </div>

  <!-- Moisture Card, Soil Card... similar -->
</section>
```

#### Suitability Badge Component
```html
<!-- _suitability_badge.html -->
{% match fit %}
  {% when EnvelopeFit::Optimal %}
    <span class="badge bg-emerald-100 text-emerald-800 dark:bg-emerald-900 dark:text-emerald-200">
      <svg class="w-3 h-3 mr-1"><!-- check --></svg> Ideal
    </span>
  {% when EnvelopeFit::Within %}
    <span class="badge bg-sky-100 text-sky-800 dark:bg-sky-900 dark:text-sky-200">
      ✓ Good
    </span>
  {% when EnvelopeFit::Marginal %}
    <span class="badge bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200">
      ↓ Marginal
    </span>
  {% when EnvelopeFit::Outside %}
    <span class="badge bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200">
      ✗ Outside
    </span>
{% endmatch %}
```

#### S4 Ecosystem Services (Visual Cards)
```html
<section class="grid grid-cols-2 md:grid-cols-3 gap-4">
  {% for service in services.items %}
  <div class="card bg-base-100 shadow-sm rounded-xl p-4">
    <div class="flex items-center gap-3">
      <div class="w-10 h-10 rounded-full bg-{{ service.color }}-100 dark:bg-{{ service.color }}-900
                  flex items-center justify-center">
        <svg class="w-5 h-5 text-{{ service.color }}-600"><!-- service icon --></svg>
      </div>
      <div>
        <p class="font-medium">{{ service.name }}</p>
        <p class="text-sm text-base-content/60">{{ service.value }}</p>
      </div>
    </div>
  </div>
  {% endfor %}
</section>
```

---

## SVG Icon Set (Lucide)

Key icons to embed:

| Concept | Icon | Usage |
|---------|------|-------|
| Tree | `tree-deciduous` | Tree growth form |
| Shrub | `shrub` | Shrub growth form |
| Flower | `flower-2` | Herb/flowering plant |
| Sun | `sun` | Light requirements |
| Thermometer | `thermometer` | Temperature |
| Droplets | `droplets` | Moisture |
| Mountain | `mountain` | Soil |
| Bug | `bug` | Pest insects |
| Butterfly | `butterfly` | Pollinators |
| Shield | `shield-check` | Disease resistance |
| Leaf | `leaf` | Nitrogen fixer |
| Check | `check` | Good fit |
| X | `x` | Poor fit |
| AlertTriangle | `alert-triangle` | Warning |

---

## Migration Strategy

1. **Keep existing markdown generator** for backward compatibility (CLI tool, reports)
2. **Add new view_models.rs** with structured types
3. **Add converter function** `plant_data_to_view_model()` that populates structs
4. **Create new template files** in `templates/encyclopedia/`
5. **Update handler** to use view models instead of markdown
6. **Test incrementally** section by section

---

## File Changes Summary

### New Files
- `src/encyclopedia/view_models.rs` - View model structs
- `src/encyclopedia/view_builder.rs` - HashMap → ViewModels converter
- `templates/encyclopedia/_identity_card.html`
- `templates/encyclopedia/_requirements.html`
- `templates/encyclopedia/_maintenance.html`
- `templates/encyclopedia/_services.html`
- `templates/encyclopedia/_interactions.html`
- `templates/encyclopedia/_companion.html`
- `templates/encyclopedia/_suitability_badge.html`

### Modified Files
- `templates/pages/encyclopedia.html` - Use includes instead of prose content
- `src/web/handlers/pages.rs` - Use view builder instead of markdown

---

## Estimated Effort

- Phase 1 (Data Structures): Create view model structs
- Phase 2 (View Builder): Convert plant data to view models
- Phase 3 (Templates): Create 7-8 template partials with DaisyUI components
- Phase 4 (Handler): Wire up new rendering path
- Phase 5 (Polish): Icons, colors, responsive tweaks

---

## Benefits

1. **Professional appearance** - DaisyUI components, proper typography
2. **Semantic structure** - Cards, badges, tables with meaning
3. **Interactive elements** - Collapsible sections, tooltips
4. **Icons & visuals** - SVG icons for each concept
5. **Maintainable** - Templates separate from logic
6. **Type-safe** - Rust structs catch errors at compile time

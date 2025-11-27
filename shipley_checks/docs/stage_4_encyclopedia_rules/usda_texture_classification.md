# USDA Soil Texture Classification

Reference implementation based on [ggsoiltexture](https://github.com/Saryace/ggsoiltexture) R package.

## Implementation Status

**Status**: Implemented and tested
**Module**: `src/encyclopedia/utils/texture.rs`
**Integration**: `src/encyclopedia/sections/s2_requirements.rs`

The USDA soil texture triangle classifies soil into 12 texture classes based on the percentages of sand, silt, and clay particles. This document describes the polygon-based classification algorithm.

## Coordinate Systems

### 1. Ternary Coordinates (Input)
- `clay`: Clay percentage (0-100)
- `sand`: Sand percentage (0-100)
- `silt`: Silt percentage (0-100)
- Constraint: `clay + sand + silt = 100`

### 2. Cartesian Coordinates (For Polygon Calculations)
Transform ternary to 2D Cartesian for point-in-polygon testing:
```
x = 0.5 * clay + silt
y = clay
```

This places:
- 100% sand at origin (0, 0)
- 100% silt at (100, 0)
- 100% clay at (50, 100)

## USDA Texture Classes (12 Classes)

### Polygon Definitions

Each polygon is defined by vertices in order. The polygon is implicitly closed (last vertex connects to first).

#### 1. Sand
| Vertex | Clay | Sand | Silt | x | y |
|--------|------|------|------|---|---|
| 1 | 10 | 90 | 0 | 5 | 10 |
| 2 | 0 | 100 | 0 | 0 | 0 |
| 3 | 0 | 85 | 15 | 15 | 0 |

**Boundaries**: >85% sand, <10% clay

#### 2. Loamy Sand
| Vertex | Clay | Sand | Silt | x | y |
|--------|------|------|------|---|---|
| 1 | 15 | 85 | 0 | 7.5 | 15 |
| 2 | 10 | 90 | 0 | 5 | 10 |
| 3 | 0 | 85 | 15 | 15 | 0 |
| 4 | 0 | 70 | 30 | 30 | 0 |

**Boundaries**: 70-90% sand, <15% clay

#### 3. Sandy Loam
| Vertex | Clay | Sand | Silt | x | y |
|--------|------|------|------|---|---|
| 1 | 20 | 80 | 0 | 10 | 20 |
| 2 | 15 | 85 | 0 | 7.5 | 15 |
| 3 | 0 | 70 | 30 | 30 | 0 |
| 4 | 0 | 50 | 50 | 50 | 0 |
| 5 | 5 | 45 | 50 | 52.5 | 5 |
| 6 | 5 | 52.5 | 42.5 | 45 | 5 |
| 7 | 20 | 52.5 | 27.5 | 37.5 | 20 |

**Boundaries**: Complex polygon, generally 43-85% sand, <20% clay

#### 4. Loam
| Vertex | Clay | Sand | Silt | x | y |
|--------|------|------|------|---|---|
| 1 | 27.5 | 45 | 27.5 | 41.25 | 27.5 |
| 2 | 20 | 52.5 | 27.5 | 37.5 | 20 |
| 3 | 5 | 52.5 | 42.5 | 45 | 5 |
| 4 | 5 | 45 | 50 | 52.5 | 5 |
| 5 | 27.5 | 22.5 | 50 | 63.75 | 27.5 |

**Boundaries**: 23-52% sand, 7-27% clay, 28-50% silt

#### 5. Silt Loam
| Vertex | Clay | Sand | Silt | x | y |
|--------|------|------|------|---|---|
| 1 | 27.5 | 22.5 | 50 | 63.75 | 27.5 |
| 2 | 0 | 50 | 50 | 50 | 0 |
| 3 | 0 | 20 | 80 | 80 | 0 |
| 4 | 12.5 | 7.5 | 80 | 86.25 | 12.5 |
| 5 | 12.5 | 0 | 87.5 | 93.75 | 12.5 |
| 6 | 27.5 | 0 | 72.5 | 86.25 | 27.5 |

**Boundaries**: <50% sand, <27% clay, 50-88% silt

#### 6. Silt
| Vertex | Clay | Sand | Silt | x | y |
|--------|------|------|------|---|---|
| 1 | 12.5 | 7.5 | 80 | 86.25 | 12.5 |
| 2 | 0 | 20 | 80 | 80 | 0 |
| 3 | 0 | 0 | 100 | 100 | 0 |
| 4 | 12.5 | 0 | 87.5 | 93.75 | 12.5 |

**Boundaries**: <12.5% clay, <20% sand, >80% silt

#### 7. Sandy Clay Loam
| Vertex | Clay | Sand | Silt | x | y |
|--------|------|------|------|---|---|
| 1 | 35 | 65 | 0 | 17.5 | 35 |
| 2 | 20 | 80 | 0 | 10 | 20 |
| 3 | 20 | 52.5 | 27.5 | 37.5 | 20 |
| 4 | 27.5 | 45 | 27.5 | 41.25 | 27.5 |
| 5 | 35 | 45 | 20 | 37.5 | 35 |

**Boundaries**: 45-80% sand, 20-35% clay

#### 8. Clay Loam
| Vertex | Clay | Sand | Silt | x | y |
|--------|------|------|------|---|---|
| 1 | 40 | 45 | 15 | 35 | 40 |
| 2 | 27.5 | 45 | 27.5 | 41.25 | 27.5 |
| 3 | 27.5 | 20 | 52.5 | 66.25 | 27.5 |
| 4 | 40 | 20 | 40 | 60 | 40 |

**Boundaries**: 20-45% sand, 27-40% clay

#### 9. Silty Clay Loam
| Vertex | Clay | Sand | Silt | x | y |
|--------|------|------|------|---|---|
| 1 | 40 | 20 | 40 | 60 | 40 |
| 2 | 27.5 | 20 | 52.5 | 66.25 | 27.5 |
| 3 | 27.5 | 0 | 72.5 | 86.25 | 27.5 |
| 4 | 40 | 0 | 60 | 80 | 40 |

**Boundaries**: <20% sand, 27-40% clay

#### 10. Sandy Clay
| Vertex | Clay | Sand | Silt | x | y |
|--------|------|------|------|---|---|
| 1 | 55 | 45 | 0 | 27.5 | 55 |
| 2 | 35 | 65 | 0 | 17.5 | 35 |
| 3 | 35 | 45 | 20 | 37.5 | 35 |

**Boundaries**: 45-65% sand, 35-55% clay

#### 11. Silty Clay
| Vertex | Clay | Sand | Silt | x | y |
|--------|------|------|------|---|---|
| 1 | 60 | 0 | 40 | 70 | 60 |
| 2 | 40 | 20 | 40 | 60 | 40 |
| 3 | 40 | 0 | 60 | 80 | 40 |

**Boundaries**: <20% sand, 40-60% clay

#### 12. Clay
| Vertex | Clay | Sand | Silt | x | y |
|--------|------|------|------|---|---|
| 1 | 100 | 0 | 0 | 50 | 100 |
| 2 | 55 | 45 | 0 | 27.5 | 55 |
| 3 | 40 | 45 | 15 | 35 | 40 |
| 4 | 40 | 20 | 40 | 60 | 40 |
| 5 | 60 | 0 | 40 | 70 | 60 |

**Boundaries**: >40% clay

---

## Rust Implementation Plan

### 1. Data Structures

```rust
/// A single vertex in the texture triangle
#[derive(Clone, Copy, Debug)]
pub struct TextureVertex {
    pub clay: f64,
    pub sand: f64,
    pub silt: f64,
    pub x: f64,  // Transformed x coordinate
    pub y: f64,  // Transformed y coordinate
}

/// A texture class polygon
pub struct TextureClass {
    pub name: &'static str,
    pub vertices: &'static [TextureVertex],
}

/// Classification result
pub struct TextureClassification {
    pub class_name: String,
    pub input_clay: f64,
    pub input_sand: f64,
    pub input_silt: f64,
    pub transformed_x: f64,
    pub transformed_y: f64,
}
```

### 2. Static Polygon Data

Define all 12 polygons as static data (see Appendix A for complete vertex data).

### 3. Point-in-Polygon Algorithm

Use the ray casting algorithm (crossing number):

```rust
/// Transform ternary coordinates to Cartesian
fn to_cartesian(clay: f64, silt: f64) -> (f64, f64) {
    let x = 0.5 * clay + silt;
    let y = clay;
    (x, y)
}

/// Ray casting algorithm for point-in-polygon test
fn point_in_polygon(x: f64, y: f64, vertices: &[TextureVertex]) -> bool {
    let n = vertices.len();
    let mut inside = false;

    let mut j = n - 1;
    for i in 0..n {
        let xi = vertices[i].x;
        let yi = vertices[i].y;
        let xj = vertices[j].x;
        let yj = vertices[j].y;

        if ((yi > y) != (yj > y)) &&
           (x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
            inside = !inside;
        }
        j = i;
    }

    inside
}

/// Classify soil texture
pub fn classify_texture(clay: f64, sand: f64, silt: f64) -> Option<TextureClassification> {
    // Validate input
    let sum = clay + sand + silt;
    if (sum - 100.0).abs() > 0.5 {
        return None;  // Invalid: doesn't sum to 100%
    }

    let (x, y) = to_cartesian(clay, silt);

    for class in TEXTURE_CLASSES.iter() {
        if point_in_polygon(x, y, class.vertices) {
            return Some(TextureClassification {
                class_name: class.name.to_string(),
                input_clay: clay,
                input_sand: sand,
                input_silt: silt,
                transformed_x: x,
                transformed_y: y,
            });
        }
    }

    None  // Edge case: point exactly on boundary
}
```

### 4. Encyclopedia Output

#### Actual Markdown Output

Example from Quercus robur (tree, using 30-60cm depth):

```markdown
**Soil Texture**

| Component | Typical | Range |
|-----------|---------|-------|
| Sand | 43% | 34-56% |
| Silt | 33% | 14-50% |
| Clay | 24% | 16-30% |

**USDA Class**: Loam
*Drainage: Good | Water retention: Good - Ideal soil; balanced drainage and retention; suits most plants*

**Triangle Coordinates**: x=44.7, y=24.1
*For plotting on USDA texture triangle; x = 0.5×clay + silt, y = clay*

**Organic Carbon**: 1 g/kg (1-3 g/kg across locations)
*Very low - Poor soil structure; add compost and organic mulch annually*
```

#### JSON Output (Future UI)

```json
{
  "texture": {
    "sand": { "q50": 43, "q05": 34, "q95": 56 },
    "silt": { "q50": 33, "q05": 14, "q95": 50 },
    "clay": { "q50": 24, "q05": 16, "q95": 30 },
    "class": "Loam",
    "coordinates": { "x": 44.7, "y": 24.1 },
    "polygon_vertices": [
      {"x": 41.25, "y": 27.5},
      {"x": 37.5, "y": 20},
      {"x": 45, "y": 5},
      {"x": 52.5, "y": 5},
      {"x": 63.75, "y": 27.5}
    ]
  }
}
```

### 5. Horticultural Advice by Texture Class

| Class | Drainage | Water Retention | Advice |
|-------|----------|-----------------|--------|
| Sand | Excellent | Very poor | Add organic matter; water frequently; nutrients leach quickly |
| Loamy Sand | Very good | Poor | Light soil; frequent watering; may need amendments |
| Sandy Loam | Good | Fair | Good general-purpose soil; most plants thrive |
| Loam | Good | Good | Ideal soil; balanced drainage and retention |
| Silt Loam | Moderate | Good | Rich soil; may compact; avoid overwatering |
| Silt | Poor | Very good | Compacts easily; improve structure with organic matter |
| Sandy Clay Loam | Moderate | Moderate | Variable; benefits from organic amendments |
| Clay Loam | Slow | High | Heavy but fertile; improve drainage with grit |
| Silty Clay Loam | Slow | High | Fertile but heavy; needs careful water management |
| Sandy Clay | Poor | High | Difficult; prone to waterlogging; amend heavily |
| Silty Clay | Very poor | Very high | Very heavy; challenging drainage; raised beds help |
| Clay | Very poor | Very high | Heavy soil; cracks when dry; needs significant amendment |

---

## Appendix A: Complete Vertex Data (Rust Static Array)

```rust
pub static USDA_POLYGONS: &[TextureClass] = &[
    TextureClass {
        name: "Sand",
        vertices: &[
            TextureVertex { clay: 10.0, sand: 90.0, silt: 0.0, x: 5.0, y: 10.0 },
            TextureVertex { clay: 0.0, sand: 100.0, silt: 0.0, x: 0.0, y: 0.0 },
            TextureVertex { clay: 0.0, sand: 85.0, silt: 15.0, x: 15.0, y: 0.0 },
        ],
    },
    TextureClass {
        name: "Loamy Sand",
        vertices: &[
            TextureVertex { clay: 15.0, sand: 85.0, silt: 0.0, x: 7.5, y: 15.0 },
            TextureVertex { clay: 10.0, sand: 90.0, silt: 0.0, x: 5.0, y: 10.0 },
            TextureVertex { clay: 0.0, sand: 85.0, silt: 15.0, x: 15.0, y: 0.0 },
            TextureVertex { clay: 0.0, sand: 70.0, silt: 30.0, x: 30.0, y: 0.0 },
        ],
    },
    TextureClass {
        name: "Sandy Loam",
        vertices: &[
            TextureVertex { clay: 20.0, sand: 80.0, silt: 0.0, x: 10.0, y: 20.0 },
            TextureVertex { clay: 15.0, sand: 85.0, silt: 0.0, x: 7.5, y: 15.0 },
            TextureVertex { clay: 0.0, sand: 70.0, silt: 30.0, x: 30.0, y: 0.0 },
            TextureVertex { clay: 0.0, sand: 50.0, silt: 50.0, x: 50.0, y: 0.0 },
            TextureVertex { clay: 5.0, sand: 45.0, silt: 50.0, x: 52.5, y: 5.0 },
            TextureVertex { clay: 5.0, sand: 52.5, silt: 42.5, x: 45.0, y: 5.0 },
            TextureVertex { clay: 20.0, sand: 52.5, silt: 27.5, x: 37.5, y: 20.0 },
        ],
    },
    TextureClass {
        name: "Loam",
        vertices: &[
            TextureVertex { clay: 27.5, sand: 45.0, silt: 27.5, x: 41.25, y: 27.5 },
            TextureVertex { clay: 20.0, sand: 52.5, silt: 27.5, x: 37.5, y: 20.0 },
            TextureVertex { clay: 5.0, sand: 52.5, silt: 42.5, x: 45.0, y: 5.0 },
            TextureVertex { clay: 5.0, sand: 45.0, silt: 50.0, x: 52.5, y: 5.0 },
            TextureVertex { clay: 27.5, sand: 22.5, silt: 50.0, x: 63.75, y: 27.5 },
        ],
    },
    TextureClass {
        name: "Silt Loam",
        vertices: &[
            TextureVertex { clay: 27.5, sand: 22.5, silt: 50.0, x: 63.75, y: 27.5 },
            TextureVertex { clay: 0.0, sand: 50.0, silt: 50.0, x: 50.0, y: 0.0 },
            TextureVertex { clay: 0.0, sand: 20.0, silt: 80.0, x: 80.0, y: 0.0 },
            TextureVertex { clay: 12.5, sand: 7.5, silt: 80.0, x: 86.25, y: 12.5 },
            TextureVertex { clay: 12.5, sand: 0.0, silt: 87.5, x: 93.75, y: 12.5 },
            TextureVertex { clay: 27.5, sand: 0.0, silt: 72.5, x: 86.25, y: 27.5 },
        ],
    },
    TextureClass {
        name: "Silt",
        vertices: &[
            TextureVertex { clay: 12.5, sand: 7.5, silt: 80.0, x: 86.25, y: 12.5 },
            TextureVertex { clay: 0.0, sand: 20.0, silt: 80.0, x: 80.0, y: 0.0 },
            TextureVertex { clay: 0.0, sand: 0.0, silt: 100.0, x: 100.0, y: 0.0 },
            TextureVertex { clay: 12.5, sand: 0.0, silt: 87.5, x: 93.75, y: 12.5 },
        ],
    },
    TextureClass {
        name: "Sandy Clay Loam",
        vertices: &[
            TextureVertex { clay: 35.0, sand: 65.0, silt: 0.0, x: 17.5, y: 35.0 },
            TextureVertex { clay: 20.0, sand: 80.0, silt: 0.0, x: 10.0, y: 20.0 },
            TextureVertex { clay: 20.0, sand: 52.5, silt: 27.5, x: 37.5, y: 20.0 },
            TextureVertex { clay: 27.5, sand: 45.0, silt: 27.5, x: 41.25, y: 27.5 },
            TextureVertex { clay: 35.0, sand: 45.0, silt: 20.0, x: 37.5, y: 35.0 },
        ],
    },
    TextureClass {
        name: "Clay Loam",
        vertices: &[
            TextureVertex { clay: 40.0, sand: 45.0, silt: 15.0, x: 35.0, y: 40.0 },
            TextureVertex { clay: 27.5, sand: 45.0, silt: 27.5, x: 41.25, y: 27.5 },
            TextureVertex { clay: 27.5, sand: 20.0, silt: 52.5, x: 66.25, y: 27.5 },
            TextureVertex { clay: 40.0, sand: 20.0, silt: 40.0, x: 60.0, y: 40.0 },
        ],
    },
    TextureClass {
        name: "Silty Clay Loam",
        vertices: &[
            TextureVertex { clay: 40.0, sand: 20.0, silt: 40.0, x: 60.0, y: 40.0 },
            TextureVertex { clay: 27.5, sand: 20.0, silt: 52.5, x: 66.25, y: 27.5 },
            TextureVertex { clay: 27.5, sand: 0.0, silt: 72.5, x: 86.25, y: 27.5 },
            TextureVertex { clay: 40.0, sand: 0.0, silt: 60.0, x: 80.0, y: 40.0 },
        ],
    },
    TextureClass {
        name: "Sandy Clay",
        vertices: &[
            TextureVertex { clay: 55.0, sand: 45.0, silt: 0.0, x: 27.5, y: 55.0 },
            TextureVertex { clay: 35.0, sand: 65.0, silt: 0.0, x: 17.5, y: 35.0 },
            TextureVertex { clay: 35.0, sand: 45.0, silt: 20.0, x: 37.5, y: 35.0 },
        ],
    },
    TextureClass {
        name: "Silty Clay",
        vertices: &[
            TextureVertex { clay: 60.0, sand: 0.0, silt: 40.0, x: 70.0, y: 60.0 },
            TextureVertex { clay: 40.0, sand: 20.0, silt: 40.0, x: 60.0, y: 40.0 },
            TextureVertex { clay: 40.0, sand: 0.0, silt: 60.0, x: 80.0, y: 40.0 },
        ],
    },
    TextureClass {
        name: "Clay",
        vertices: &[
            TextureVertex { clay: 100.0, sand: 0.0, silt: 0.0, x: 50.0, y: 100.0 },
            TextureVertex { clay: 55.0, sand: 45.0, silt: 0.0, x: 27.5, y: 55.0 },
            TextureVertex { clay: 40.0, sand: 45.0, silt: 15.0, x: 35.0, y: 40.0 },
            TextureVertex { clay: 40.0, sand: 20.0, silt: 40.0, x: 60.0, y: 40.0 },
            TextureVertex { clay: 60.0, sand: 0.0, silt: 40.0, x: 70.0, y: 60.0 },
        ],
    },
];
```

---

## Appendix B: Boundary Edge Cases

When a point falls exactly on a polygon boundary:
1. The ray casting algorithm may return false positives/negatives
2. Solution: Check adjacent polygons and return the first match
3. For encyclopedia purposes, this edge case is rare and acceptable

## Appendix C: Silt Calculation

If silt is not available in the dataset but clay and sand are:
```rust
let silt = 100.0 - clay - sand;
```

Validate that all three components are non-negative.

---

## References

- USDA Natural Resources Conservation Service. Soil Texture Calculator.
- ggsoiltexture R package: https://github.com/Saryace/ggsoiltexture
- soiltexture R package: https://cran.r-project.org/web/packages/soiltexture/

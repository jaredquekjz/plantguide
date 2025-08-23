# Run 8 — Gaussian Copula Adequacy (Quick Check)

Pairs checked: from results/MAG_Run8/mag_copulas.json

| Pair | n | rho | tau_emp | tau_gauss | hi_emp | hi_mc | lo_emp | lo_mc | CV logc/obs |
|------|---:|----:|--------:|----------:|-------:|------:|-------:|------:|------------:|
| T:R | 1045 | 0.328 | 0.237 | 0.213 | 0.0172 | 0.0227 | 0.0287 | 0.0225 | 0.0569 |
| L:M | 1045 | -0.279 | -0.196 | -0.180 | 0.0057 | 0.0034 | 0.0010 | 0.0032 | 0.0387 |

Heuristics:
- tau alignment within ~0.05 and tail co-occurrence within ~20% relative indicate Gaussian copula is adequate for joint gardening usage.
- Positive CV log-copula per-observation implies generalization over independence.


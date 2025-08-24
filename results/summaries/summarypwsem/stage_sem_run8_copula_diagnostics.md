# Run 8 — Gaussian Copula Adequacy (Quick Check)

Pairs checked: from results/MAG_Run8/mag_copulas.json

| Pair | n | rho | tau_emp | tau_gauss | hi_emp | hi_mc | lo_emp | lo_mc | CV logc/obs |
|------|---:|----:|--------:|----------:|-------:|------:|-------:|------:|------------:|
| L:M | 1045 | -0.184 | -0.141 | -0.118 | 0.0105 | 0.0054 | 0.0010 | 0.0051 | 0.0140 |
| T:R | 1045 | 0.328 | 0.237 | 0.213 | 0.0172 | 0.0233 | 0.0287 | 0.0231 | 0.0570 |
| T:M | 1045 | -0.389 | -0.289 | -0.254 | 0.0019 | 0.0017 | 0.0029 | 0.0019 | 0.0825 |
| M:R | 1045 | -0.269 | -0.188 | -0.173 | 0.0038 | 0.0034 | 0.0029 | 0.0035 | 0.0362 |
| M:N | 1045 | 0.183 | 0.124 | 0.117 | 0.0096 | 0.0167 | 0.0239 | 0.0167 | 0.0150 |

Heuristics:
- tau alignment within ~0.05 and tail co-occurrence within ~20% relative indicate Gaussian copula is adequate for joint gardening usage.
- Positive CV log-copula per-observation implies generalization over independence.

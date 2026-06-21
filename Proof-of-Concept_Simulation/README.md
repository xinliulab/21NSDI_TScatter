# Proof-of-Concept Simulation

This folder contains only the mathematics-level proof-of-concept scripts.
These scripts do not use the 802.11n protocol stack.  They are meant to be
read like derivations: define matrices, generate simple vectors, verify the
model, and recover the tag bits in a noiseless setting.

## Scripts

```text
Full_TScatter_PoC.m
Lite_TScatter_PoC.m
```

Run either script directly from MATLAB.

## Full TScatter PoC

`Full_TScatter_PoC.m` explains sample-level Full TScatter:

```text
N = 64 useful OFDM time samples
v in {+1,-1}^(64x1)
v(1:48)   = unknown backscatter phases
v(49:64)  = known/predefined phases, fixed to +1
```

The script explicitly constructs the DFT matrix `W`, inverse DFT matrix
`Winv`, forward channel `H_f`, backward channel `H_b`, and sample-level tag
matrix `D(v)`.

The physical receive model is:

```text
y = exp(j*beta) H_b W D(v) W^{-1} H_f x
```

After ordinary cascaded channel compensation:

```text
z = (H_f H_b)^(-1) y
  = exp(j*beta) H_f^(-1) W D(v) W^(-1) H_f x
```

The key algebraic step is:

```text
D(v) = v_1 D(e_1) + v_2 D(e_2) + ... + v_64 D(e_64)
```

where each `D(e_i)` is a diagonal matrix with exactly one nonzero diagonal
entry.  Therefore each fixed contribution can become one column of the
decoder matrix:

```text
A(:,i) = H_f^(-1) W D(e_i) W^(-1) H_f x
z      = exp(j*beta) A v
```

The script also includes pilot/Gamma compensation:

```text
Psi      = angle(sum over pilots of z_k conj(x_k))
zbar     = exp(-j*Psi) z
Gamma(v) = sum over pilots of (A v)_k conj(x_k)
c(v)     = conj(Gamma(v)) / |Gamma(v)|
zbar     ~= c(v) A v
```

## Lite TScatter PoC

`Lite_TScatter_PoC.m` explains Lite TScatter with one simple tag phase per
whole OFDM block:

```text
64 useful samples + 16 CP samples = 80 time samples
one Lite tag phase b_m in {+1,-1} per 80-sample block
```

This is intentionally simpler than Full TScatter:

```text
Lite: one tag phase per 80-sample block
Full: one tag phase per useful time sample
```

The Lite receiver uses one predefined reference block to remove the common
phase, then recovers the signs of the following Lite tag blocks by projection
onto the known WiFi samples.

## Why the scripts compute the same signal twice

Several lines intentionally compute the same mathematical object in two
different ways and compare the relative error:

```text
relative_error = norm(model_1 - model_2) / norm(model_1)
```

These are sanity checks, not duplicate algorithm steps.  They verify:

```text
1. W and Winv are inverse DFT matrices.
2. Channel compensation removes H_b but leaves the H_f structure.
3. The physical Full TScatter chain equals exp(j*beta) A v.
4. Pilot/Gamma compensation gives zbar ~= c(v) A v.
5. Lite reference compensation removes the common phase.
```

If future changes add CP, CFO, noise, or a different tag mapping, these
checks show exactly which matrix relationship stopped matching.

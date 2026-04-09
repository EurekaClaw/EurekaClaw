# TASK INSTRUCTIONS

## What We Have Formalized

### SLT/GaussianSobolevDense/Density.lean  

We have formalized:
- strong Gaussian Sobolev function class (1D specialized version):
```lean4
def MemW12GaussianReal (f : ℝ → ℝ) (γ : Measure ℝ) : Prop :=
  MemLp f 2 γ ∧ MemLp (fun x ↦ fderiv ℝ f x) 2 γ
```
**NOTICE THAT YOU CAN PROVE MOST INTEGRABILITY OR FINITENESS FROM `MemW12GaussianReal`**
- strong Gaussian Sobolev norm squared
```lean4
noncomputable def GaussianSobolevNormSqReal (f : ℝ → ℝ) (γ : Measure ℝ) : ℝ≥0∞ :=
  eLpNorm f 2 γ ^ 2 + eLpNorm (fun x ↦ ‖fderiv ℝ f x‖) 2 γ ^ 2
```
- existence of a sequence of smooth compactly supported functions converging to any continuously differentiable f ∈ W^{1,2}(γ) in the 1D Gaussian Sobolev norm
```lean4
theorem exists_smooth_compactSupport_seq_tendsto_real (f : ℝ → ℝ)
    (hf : MemW12GaussianReal f (gaussianReal 0 1))
    (hf_diff : Differentiable ℝ f) (hf_grad_cont : Continuous (fun x => fderiv ℝ f x)) :
    ∃ g : ℕ → (ℝ → ℝ),
      (∀ k, ContDiff ℝ (⊤ : ℕ∞) (g k)) ∧
      (∀ k, HasCompactSupport (g k)) ∧
      Tendsto (fun k => GaussianSobolevNormSqReal (f - g k) (gaussianReal 0 1)) atTop (nhds 0) := by
```

### SLT/GaussianLSI/Entropy.lean 

We have formalized:
- definition of entropy
```lean4
def entropy (μ : Measure Ω) (f : Ω → ℝ) : ℝ :=
  ∫ ω, f ω * log (f ω) ∂μ - (∫ ω, f ω ∂μ) * log (∫ ω, f ω ∂μ)
```
- entropy of f² with respect to the normalization
```lean4
def entropySquare (μ : Measure Ω) (f : Ω → ℝ) : ℝ :=
  entropy μ (fun ω => (f ω)^2)
```
- properties of entropy (please check signatures carefully if needed):
  1. `entropy_const`: Entropy of a constant function is zero.
  2. `entropy_congr`: If f = g a.e., then their entropies are equal.
  3. `jensen_mul_log`: Jensen's inequality for the convex function x * log(x).
  4. `entropy_nonneg`: Entropy is nonnegative for probability measures and nonnegative integrands.
  5. `entropySquare_eq`: The entropy of f² is always well-defined in the sense that the integrand f² * log(f²) = 2 * f² * log|f| is measurable when f is.
  6. `entropy_sq_normalized`, `log_sq_eq_two_mul_log_abs`
  7. `entropy_sq_abs_log`: Entropy of f² in terms of 2 * f² * log|f|.

### SLT/GaussianSobolevDense/LiminfContEnt.lean

We have formalized:
- phi(t) = t * log(t) is bounded below by -1/e for t ≥ 0:
```lean4
lemma mul_log_ge_neg_inv_exp (t : ℝ) (ht : 0 ≤ t) : -(1 / Real.exp 1) ≤ t * Real.log t := by
```
- convergence in Gaussian Sobolev norm (squared) implies convergence in $L^2(\gamma)$:
```lean4
lemma tendsto_eLpNorm_sub_of_sobolev (f : ℝ → ℝ) (g : ℕ → ℝ → ℝ) (μ : Measure ℝ)
    (h_tend : Tendsto (fun k => GaussianSobolevNormSqReal (f - g k) μ) atTop (nhds 0)) :
    Tendsto (fun k => eLpNorm (f - g k) 2 μ) atTop (nhds 0) := by
```
- convergence in $L^2(\gamma)$ of real-valued functions implies convergence in $L^1(\gamma)$ of their pointwise squares:
```lean4
lemma tendsto_eLpNorm_sub_of_sobolev (f : ℝ → ℝ) (g : ℕ → ℝ → ℝ) (μ : Measure ℝ)
    (h_tend : Tendsto (fun k => GaussianSobolevNormSqReal (f - g k) μ) atTop (nhds 0)) :
    Tendsto (fun k => eLpNorm (f - g k) 2 μ) atTop (nhds 0) := by
```
- convergence in Gaussian Sobolev norm (squared) implies convergence of gradient in $L^2(\gamma)$:
```lean4
lemma tendsto_integral_norm_fderiv_sq_of_sobolev (f : ℝ → ℝ) (g : ℕ → ℝ → ℝ) (μ : Measure ℝ)
    (hf_diff : Differentiable ℝ f) (hf_grad_cont : Continuous (fun x => fderiv ℝ f x))
    (hg_diff : ∀ k, Differentiable ℝ (g k))
    (hg_grad_cont : ∀ k, Continuous (fun x => fderiv ℝ (g k) x))
    (hf_mem : MemLp (fun x => ‖fderiv ℝ f x‖) 2 μ)
    (hg_mem : ∀ k, MemLp (fun x => ‖fderiv ℝ (g k) x‖) 2 μ)
    (h_tend : Tendsto (fun k => GaussianSobolevNormSqReal (f - g k) μ) atTop (nhds 0)) :
    Tendsto (fun k => ∫ x, ‖fderiv ℝ (g k) x‖^2 ∂μ) atTop
      (nhds (∫ x, ‖fderiv ℝ f x‖^2 ∂μ)) := by
```

### SLT/GaussianLSI/OneDimGLSI.lean 

We have formalized the one-dimensional Gaussian logarithmic Sobolev inequality for twice-differentiable functions with compact support
```lean4
theorem gaussian_logSobolev_CompSmo_fderiv {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    LogSobolev.entropy stdGaussianMeasure (fun x => (f x)^2) ≤
    2 * ∫ x, ‖fderiv ℝ f x‖^2 ∂stdGaussianMeasure := by
```

### SLT/ConvergenceL1Subseq.lean

Convergence in $L^1(\mu)$ yields an a.e.-convergent subsequence
```lean4
theorem exists_seq_tendsto_ae_of_tendsto_eLpNorm_one
    [NormedAddCommGroup E] {f : ℕ → α → E} {g : α → E}
    (hf : ∀ n, AEStronglyMeasurable (f n) mu)
    (hg : AEStronglyMeasurable g mu)
    (hfg : Tendsto (fun n => eLpNorm (f n - g) (1 : ENNReal) mu) atTop (nhds 0)) :
    ∃ ns : ℕ → ℕ, StrictMono ns ∧
      ∀ᵐ x ∂mu, Tendsto (fun i => f (ns i) x) atTop (nhds (g x)) := by
```

---

## Target Theorem Statement

By `exists_smooth_compactSupport_seq_tendsto_real`, we can construct a sequence of smooth compactly supported functions $\{g_k\}_{k=1}^\infty \subset C_c^\infty(\mathbb{R})$ converging to any $f$ in the strong Gaussian Sobolev function class ($f\in W^{1,2}(\gamma)$ with $f\in C^1(\mathbb{R})$) in the 1D Gaussian Sobolev norm.

Your task is to extend the one-dimensional Gaussian logarithmic Sobolev inequality from twice-differentiable functions with compact support to strong Gaussian Sobolev function class ($f\in W^{1,2}(\gamma)$ with $f\in C^1(\mathbb{R})$).

**`STRONG` MEANS THE FUNCTION IS CONTINUOUSLY DIFFERENTIABLE**

Therefore, our **TARGET THEOREM** is:

> For any continuously differentiable ($f\in C^1$) function $f : \mathbb{R} \to \mathbb{R}$ with $f\in W^{1,2}(\gamma)$, we have
> $$\text{Ent}(f^2) \leq 2\mathbf{E}\left[\|\nabla f(X)\|^2\right].$$

---

## Optimal Proof for Formalization

### Step 1: Preliminaries about ($x\log x$), WELL-FORMALIZED

Define $\phi:[0,\infty)\to\mathbb R$ by $\phi(x)=x\log x$ (has been formalized as `def phi`).

#### Fact 1 (continuity)

$\phi$ is continuous on $[0,\infty)$. This has been formalized as `phi_continuous`.

#### Fact 2 (bounded below)

$$
\inf_{x\ge 0} \phi(x) = -\frac1e.
$$
Hence
$$
\phi(x)+\frac1e \ge 0\quad\text{for all }x\ge 0.
\tag{1}
$$
This “shift to nonnegativity” is what makes Fatou immediately applicable, which has been formalized in `mul_log_ge_neg_inv_exp`.

---

### Step 2: A subsequence lemma (from (L^{1}) to a.e.), WELL-FORMALIZED

#### Lemma (a.e. convergent subsequence)

Convergence in $L^1(\mu)$ yields an a.e.-convergent subsequence, has been formalized as `exists_seq_tendsto_ae_of_tendsto_eLpNorm_one` in SLT/ConvergenceL1Subseq.lean .

---

### Step 3: Lower semicontinuity of $\int g\log g$ via Fatou's lemma

**IMPORTANT: FROM HERE, WE WORK IN ENNREAL!!!**

#### Proposition (lower semicontinuity)

Assume $q_k\ge 0$ and $q_k\to q$ in $L^{1}(\gamma)$. Then
$$
\int \phi(q)\,d\gamma \le \liminf_{k\to\infty}\int \phi(q_k)\,d\gamma,
\quad\text{i.e.}\quad
\int q\log q\,d\gamma \le \liminf_{k\to\infty}\int q_k\log q_k\,d\gamma,
\tag{3}
$$
**allowing the value $+\infty$ on either side.** (We will set $q_k=g^2_k$, $q=f^2$ later)

##### Proof

Let
$$
L:=\liminf_{k\to\infty}\int \phi(q_k)\,d\gamma \in [-1/e,\infty].
$$
Choose a subsequence (still denoted $q_k$ for simplicity) such that
$$
\int \phi(q_k)\,d\gamma \to L.
\tag{4}
$$
(4) can be proven via:
Set
$$
a_k := \int \phi(q_k)\,d\mu \in \left[-\frac1e,\infty\right]\quad\text{where }\phi(x)=x\log x.
$$
Let
$$
L := \liminf_{k\to\infty} a_k \in \left[-\frac1e,\infty\right].
$$
If $L<\infty$, then there exists a subsequence $(a_{k_j}^*)_{j\ge1}$ such that
$$
a^*_{k_j}\to L.
$$
If $L=\infty$, then there is nothing to choose: “$\le \liminf$” is automatic whenever the right-hand side is $+\infty$.

Define the tail infima
$$
b_j := \inf_{k\ge j} a_k.
$$
Then $(b_j)$ is nondecreasing and $b_j\uparrow L$ by definition of $\liminf$.

For each $j$, by the definition of infimum, there exists some index $k_j\ge j$ such that
$$
a_{k_j} \le b_j + \frac1j.
$$
Then,
$$
b_j \le a_{k_j} \le b_j+\frac1j,
$$
so as $j\to\infty$,
$$
a_{k_j}\to L.
$$
This is the subsequence you used. It is a standard “almost minimizer of tail infimum” construction.

Given $q_k\to q$ in $L^{1}(\gamma)$, apply the lemma `exists_seq_tendsto_ae_of_tendsto_eLpNorm_one` to extract a **subsequence** such that $q_k\to q$ a.e.

By continuity of $\phi$ (Fact 1), we have $\phi(q_k)\to \phi(q)$ a.e., hence
$$
\phi(q) \le \liminf_{k\to\infty}\phi(q_k)\quad\text{a.e.}
\tag{5}
$$
Now shift to nonnegativity using (1): define
$$
h_k := \phi(q_k)+\frac1e \ge 0,\qquad h:=\phi(q)+\frac1e\ge 0.
$$
From (5), $$h \le \liminf_k h_k\quad a.e.$$
Fatou’s lemma for nonnegative functions **(`lintegral_liminf_le`!!!)** gives
$$
\int h\,d\gamma \le \liminf_{k\to\infty}\int h_k\,d\gamma.
$$
Subtract $1/e$ from both sides (note $\gamma$ is a probability measure, so $\int \tfrac1e d\gamma=\tfrac1e$) to get
$$
\int \phi(q)\,d\gamma \le \liminf_{k\to\infty}\int \phi(q_k)\,d\gamma.
$$
Using (4), the right-hand side equals $L$, which is $\liminf_{k}\int\phi(g_k)$. This proves (3). ∎

**Integrability remarks.**

* We did **not** assume $\phi(g_k)\in L^1$. If $\int \phi(g_k)=+\infty$ along a subsequence, Fatou still applies because $h_k\ge0$ and the integrals are allowed to be $+\infty$.
* The negative part is never a problem because $\phi\ge -1/e$; that is exactly why the shift works.

---

### Step 4: Lower semicontinuity of entropy

Define, for $q\ge0$,
$$
Ent(q)=\int q\log q\,d\gamma - m\log m,\qquad m:=\int q\,d\gamma.
$$

#### Corollary

If $q_k\ge0$ and $q_k\to q$ in $L^1(\gamma)$, then
$$
Ent(q) \le \liminf_{k\to\infty}Ent(q_k).
\tag{6}
$$

##### Proof

From $L^1$-convergence, $m_k:=\int q_k\,d\gamma \to \int q\,d\gamma = m$. The map $x\mapsto x\log x$ is continuous on $[0,\infty)$, so
$$
m_k\log m_k \to m\log m.
\tag{7}
$$
From the proposition,
$$
\int q\log q\,d\gamma \le \liminf_{k\to\infty} \int q_k\log q_k\,d\gamma.
\tag{8}
$$
Combine (7)–(8):
$$
Ent(q)
= \int q\log q\,d\gamma - m\log m
\le \liminf_k \int q_k\log q_k\,d\gamma - \lim_k m_k\log m_k
= \liminf_k Ent(q_k).
$$
∎

---

### Step 5: Application in Our Case

Take $q_k=f_k^2$ and $q=f^2$. So the corollary gives
$$
Ent(f^2)\le \liminf_{k\to\infty}Ent(g_k^2),
$$
which is the exact lower semicontinuity.

---

### Step 6: Back to Real Space

By `tendsto_integral_norm_fderiv_sq_of_sobolev` and `gaussian_logSobolev_CompSmo_fderiv`, we can obtain
$$
\liminf_{k\to\infty}Ent(g_k)
\le
\liminf_{k\to\infty} 2\int |\nabla g_k|^2\,d\gamma
=2\int |\nabla f|^2\,d\gamma
< \infty. \tag{*}
$$
Now combine (*) with

$$
Ent(f^2)\le \liminf_{k\to\infty}Ent(g_k^2),
$$

to get all finiteness, then we can convert back to real space.

---

### Step 7: Conclude the Limit

$$\text{Ent}(f^2) \leq 2\mathbf{E}\left[\|\nabla f(X)\|^2\right]$$
follows from results formalized, add the proof by yourself.

---

## Rules

1. Write all formalization code in OneDimGLSI.lean . 
2. **Success = `lake build` passes + zero sorries + zero custom axioms.** Theorems with sorries/axioms are scaffolding, not results.
3. Use the file outline tool **STRICTLY** to check declaration signatures, and **DO NOT** open, read, or infer from the underlying source file contents.
4. DO NOT BE AFRAID OF COMPLEXITY OR LACK OF INFRASTRUCTURES. IF COMPLEX, TRY TO USE A LEMMA-BASED MODULAR APPROACH, DECOMPOSE THE PROOF INTO LEMMAS THEN SOLVE ONE-BY-ONE. IF LACK OF INFRASTRUCTURES, BUILD REQUIRED INFRASTRUCTURES ONE-BY-ONE.
5. DO NOT FREQUENTLY CHANGE PROOF, YOU ONLY NEED TO DO THIS WHEN YOU'RE CONFIDENT THAT IT IS WRONG. TRY TO FIX ERRORS ONE-BY-ONE.

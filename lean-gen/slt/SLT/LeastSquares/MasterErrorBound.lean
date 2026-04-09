/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.LeastSquares.BasicInequality
import SLT.LeastSquares.Localization
import SLT.LeastSquares.CriticalRadius
import SLT.GaussianLipConcen

/-!
# Master Error Bound for Least Squares Regression

## Main definitions

* `Z_supremum`: The random variable Z(u) = sup_{‖g‖_n = u} |σ/n Σᵢ wᵢ g(xᵢ)|.
* `badEvent`: The bad event A(u) where empirical process exceeds threshold.
* `goodEvent`: Complement of bad event at level √(tδ*).

## Main results

* `bad_event_probability_bound`: For u ≥ δ*, P(A(u)) ≤ exp(-nu²/(2σ²)).
* `master_error_bound`: With probability ≥ 1 - exp(-ntδ*/(2σ²)), ‖f̂ - f*‖_n² ≤ 16tδ*.

## Key lemmas

* `Z_supremum_lipschitz`: Z(u) is Lipschitz with constant σu/√n (w.r.t. L2 norm).
* `Z_expectation_bound`: E[Z(u)] ≤ uδ* (using monotonicity of G_n(δ)/δ).
-/

open MeasureTheory Finset BigOperators Real ProbabilityTheory GaussianMeasure

namespace LeastSquares

variable {n : ℕ} {X : Type*}

/-!
## Definitions for Bad Event and Z(u)
-/

/-- The sphere in function space: functions with exact empirical norm u -/
def empiricalSphere (n : ℕ) (H : Set (X → ℝ)) (u : ℝ) (x : Fin n → X) : Set (X → ℝ) :=
  {g ∈ H | empiricalNorm n (fun i => g (x i)) = u}

/-- The outer region in function space: functions with empirical norm ≥ u -/
def empiricalOuterRegion (n : ℕ) (H : Set (X → ℝ)) (u : ℝ) (x : Fin n → X) : Set (X → ℝ) :=
  {g ∈ H | u ≤ empiricalNorm n (fun i => g (x i))}

/-- The random variable Z(u) = sup_{g ∈ H, ‖g‖_n = u} |σ/n Σᵢ wᵢ g(xᵢ)| -/
noncomputable def Z_supremum (n : ℕ) (σ : ℝ) (H : Set (X → ℝ)) (u : ℝ) (x : Fin n → X)
    (w : Fin n → ℝ) : ℝ :=
  ⨆ g ∈ empiricalSphere n H u x, |σ / n * ∑ i, w i * g (x i)|

/-- The bad event A(u): exists g with ‖g‖_n ≥ u such that the empirical process
    exceeds 2‖g‖_n u -/
def badEvent (n : ℕ) (σ : ℝ) (H : Set (X → ℝ)) (u : ℝ) (x : Fin n → X) : Set (Fin n → ℝ) :=
  {w | ∃ g ∈ empiricalOuterRegion n H u x,
    |σ / n * ∑ i, w i * g (x i)| ≥ 2 * empiricalNorm n (fun i => g (x i)) * u}

/-!
## Z(u) is Lipschitz

Z(u) = sup_g |⟨w, (σ/n) g(x₁,...,xₙ)⟩| is a supremum of linear functions, hence Lipschitz with
constant sup_g ‖(σ/n) g(x₁,...,xₙ)‖₂ = σu/√n when restricted to ‖g‖_n = u.
-/

/-- The Euclidean norm of g(x₁,...,xₙ) equals √n · ‖g‖_n. -/
lemma euclidean_norm_eq_sqrt_n_mul_empiricalNorm (hn : 0 < n) (g : X → ℝ) (x : Fin n → X) :
    Real.sqrt (∑ i, (g (x i))^2) = Real.sqrt n * empiricalNorm n (fun i => g (x i)) := by
  unfold empiricalNorm
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have hn_ne : (n : ℝ) ≠ 0 := ne_of_gt hn_pos
  -- RHS = √n * √(n⁻¹ * ∑ g²) = √(n * (n⁻¹ * ∑ g²)) = √(∑ g²) = LHS
  symm
  rw [← Real.sqrt_mul (Nat.cast_nonneg n)]
  congr 1
  have h_sum_nonneg : 0 ≤ ∑ k : Fin n, (fun i => g (x i)) k ^ 2 :=
    sum_nonneg (fun i _ => sq_nonneg _)
  field_simp

/-- For g with ‖g‖_n = u, ‖(σ/n) g(x₁,...,xₙ)‖₂ = σu/√n. -/
lemma coefficient_euclidean_norm (hn : 0 < n) (σ u : ℝ) (hσ : 0 < σ)
    (g : X → ℝ) (x : Fin n → X) (hg : empiricalNorm n (fun i => g (x i)) = u) :
    Real.sqrt (∑ i, (σ / n * g (x i))^2) = σ * u / Real.sqrt n := by
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have hsqrt_ne : Real.sqrt n ≠ 0 := Real.sqrt_ne_zero'.mpr hn_pos
  have hn_ne : (n : ℝ) ≠ 0 := ne_of_gt hn_pos
  have h1 : ∑ i, (σ / n * g (x i))^2 = (σ / n)^2 * ∑ i, (g (x i))^2 := by
    simp_rw [mul_pow]
    rw [← Finset.mul_sum]
  rw [h1, Real.sqrt_mul (sq_nonneg _), Real.sqrt_sq (by positivity)]
  rw [euclidean_norm_eq_sqrt_n_mul_empiricalNorm hn g x, hg]
  -- Goal: σ / n * (√n * u) = σ * u / √n
  have hsqrt_sq : Real.sqrt n * Real.sqrt n = n := Real.mul_self_sqrt (Nat.cast_nonneg n)
  calc σ / n * (Real.sqrt n * u)
      = σ / n * Real.sqrt n * u := by ring
    _ = σ * Real.sqrt n / n * u := by rw [div_mul_eq_mul_div]
    _ = σ * Real.sqrt n / (Real.sqrt n * Real.sqrt n) * u := by rw [hsqrt_sq]
    _ = σ / Real.sqrt n * u := by rw [mul_div_mul_right _ _ hsqrt_ne]
    _ = σ * u / Real.sqrt n := by ring

/-- Z(u) is Lipschitz with constant σu/√n w.r.t. L2 norm.

Z(u) is a supremum of linear functions ⟨a_g, w⟩ with ‖a_g‖₂ ≤ σu/√n. -/
lemma Z_supremum_lipschitz (hn : 0 < n) (σ u : ℝ) (hσ : 0 < σ) (hu : 0 < u)
    (H : Set (X → ℝ)) (x : Fin n → X)
    (hne : (empiricalSphere n H u x).Nonempty)
    (hbdd : ∀ w : Fin n → ℝ, BddAbove {y | ∃ g ∈ empiricalSphere n H u x, y = |σ / n * ∑ i, w i * g (x i)|}) :
    LipschitzWith (Real.toNNReal (σ * u / Real.sqrt n))
      (Z_supremum n σ H u x ∘ (EuclideanSpace.equiv (Fin n) ℝ)) := by
  rw [lipschitzWith_iff_dist_le_mul]
  intro v₁ v₂
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have hL_nonneg : 0 ≤ σ * u / Real.sqrt n := by positivity
  rw [Real.coe_toNNReal _ hL_nonneg]
  -- Convert to Fin n → ℝ
  let e := EuclideanSpace.equiv (Fin n) ℝ
  let w₁ := e v₁
  let w₂ := e v₂
  -- The key: dist on EuclideanSpace is L2 distance
  have h_dist_L2 : dist v₁ v₂ = Real.sqrt (∑ i, (w₁ i - w₂ i)^2) := by
    rw [EuclideanSpace.dist_eq]
    congr 1
    apply Finset.sum_congr rfl
    intro i _
    simp only [Real.dist_eq, sq_abs]
    rfl
  -- Z(u)(w₁) - Z(u)(w₂) ≤ sup_g |⟨w₁ - w₂, (σ/n) g⟩| ≤ ‖w₁ - w₂‖_L2 * L
  show dist (Z_supremum n σ H u x w₁) (Z_supremum n σ H u x w₂) ≤ _
  unfold Z_supremum
  -- For supremum of linear functions, |sup f(w₁) - sup f(w₂)| ≤ sup |f(w₁) - f(w₂)|
  -- ≤ sup_g ‖a_g‖ * ‖w₁ - w₂‖ ≤ L * ‖w₁ - w₂‖
  have h_diff : ∀ g : X → ℝ, |σ / n * ∑ i, w₁ i * g (x i)| - |σ / n * ∑ i, w₂ i * g (x i)| ≤
      |σ / n * ∑ i, (w₁ i - w₂ i) * g (x i)| := by
    intro g
    have h1 : σ / n * ∑ i, w₁ i * g (x i) - σ / n * ∑ i, w₂ i * g (x i) =
        σ / n * ∑ i, (w₁ i - w₂ i) * g (x i) := by
      rw [← mul_sub]
      congr 1
      rw [← Finset.sum_sub_distrib]
      apply sum_congr rfl
      intro i _
      ring
    calc |σ / n * ∑ i, w₁ i * g (x i)| - |σ / n * ∑ i, w₂ i * g (x i)|
        ≤ |σ / n * ∑ i, w₁ i * g (x i) - σ / n * ∑ i, w₂ i * g (x i)| :=
          abs_sub_abs_le_abs_sub _ _
      _ = |σ / n * ∑ i, (w₁ i - w₂ i) * g (x i)| := by rw [h1]
  -- Cauchy-Schwarz: |⟨w₁ - w₂, a_g⟩| ≤ ‖w₁ - w₂‖_L2 * ‖a_g‖_L2
  have h_cs : ∀ g ∈ empiricalSphere n H u x,
      |σ / n * ∑ i, (w₁ i - w₂ i) * g (x i)| ≤
      Real.sqrt (∑ i, (w₁ i - w₂ i)^2) * (σ * u / Real.sqrt n) := by
    intro g hg
    have hg_norm : empiricalNorm n (fun i => g (x i)) = u := hg.2
    have h_inner : σ / n * ∑ i, (w₁ i - w₂ i) * g (x i) =
        ∑ i, (w₁ i - w₂ i) * (σ / n * g (x i)) := by
      rw [Finset.mul_sum]
      congr 1
      ext i
      ring
    rw [h_inner]
    have h_cs_inner := abs_sum_le_sqrt_sq_mul_sqrt_sq (fun i => w₁ i - w₂ i) (fun i => σ / n * g (x i))
    calc |∑ i, (w₁ i - w₂ i) * (σ / n * g (x i))|
        ≤ Real.sqrt (∑ i, (w₁ i - w₂ i)^2) * Real.sqrt (∑ i, (σ / n * g (x i))^2) := h_cs_inner
      _ = Real.sqrt (∑ i, (w₁ i - w₂ i)^2) * (σ * u / Real.sqrt n) := by
          congr 1
          exact coefficient_euclidean_norm hn σ u hσ g x hg_norm
  -- Now bound dist
  rw [dist_eq_norm]
  -- Goal: ‖(⨆ g ∈ sphere, |..w₁..| ) - ⨆ g ∈ sphere, |..w₂..|‖ ≤ L * dist v₁ v₂
  rw [Real.norm_eq_abs]
  have hbdd₁ := hbdd w₁
  have hbdd₂ := hbdd w₂
  -- For each g on sphere, bound the individual term
  have h_each_bound : ∀ g ∈ empiricalSphere n H u x,
      |σ / n * ∑ i, w₁ i * g (x i)| ≤
      (⨆ h ∈ empiricalSphere n H u x, |σ / n * ∑ i, w₂ i * h (x i)|) +
      σ * u / Real.sqrt n * dist v₁ v₂ := by
    intro g hg
    -- |f(w₁)| ≤ |f(w₂)| + |f(w₁) - f(w₂)| ≤ Z(w₂) + L * dist
    have h1 : |σ / n * ∑ i, w₁ i * g (x i)| ≤
        |σ / n * ∑ i, w₂ i * g (x i)| + |σ / n * ∑ i, (w₁ i - w₂ i) * g (x i)| := by
      have := abs_sub_abs_le_abs_sub (σ / n * ∑ i, w₁ i * g (x i)) (σ / n * ∑ i, w₂ i * g (x i))
      have h_eq : σ / n * ∑ i, w₁ i * g (x i) - σ / n * ∑ i, w₂ i * g (x i) =
          σ / n * ∑ i, (w₁ i - w₂ i) * g (x i) := by
        rw [← mul_sub, ← Finset.sum_sub_distrib]
        congr 1
        apply Finset.sum_congr rfl
        intro i _
        ring
      linarith [this, (h_diff g)]
    -- |f(w₂)| ≤ Z(w₂)
    have h2 : |σ / n * ∑ i, w₂ i * g (x i)| ≤
        ⨆ h ∈ empiricalSphere n H u x, |σ / n * ∑ i, w₂ i * h (x i)| := by
      have hbdd₂' : BddAbove (Set.range fun h => ⨆ _ : h ∈ empiricalSphere n H u x,
          |σ / n * ∑ i, w₂ i * h (x i)|) := by
        use sSup {y | ∃ g ∈ empiricalSphere n H u x, y = |σ / n * ∑ i, w₂ i * g (x i)|}
        intro y hy
        obtain ⟨h, rfl⟩ := hy
        by_cases hh : h ∈ empiricalSphere n H u x
        · show (⨆ _ : h ∈ empiricalSphere n H u x, |σ / n * ∑ i, w₂ i * h (x i)|) ≤ _
          rw [ciSup_pos hh]
          apply le_csSup hbdd₂
          exact ⟨h, hh, rfl⟩
        · show (⨆ _ : h ∈ empiricalSphere n H u x, |σ / n * ∑ i, w₂ i * h (x i)|) ≤ _
          rw [ciSup_neg hh, Real.sSup_empty]
          apply Real.sSup_nonneg
          intro y ⟨g, _, hy⟩
          exact hy ▸ abs_nonneg _
      apply le_ciSup_of_le hbdd₂' g
      rw [ciSup_pos hg]
    -- |f(w₁-w₂)| ≤ L * dist
    have h3 : |σ / n * ∑ i, (w₁ i - w₂ i) * g (x i)| ≤ σ * u / Real.sqrt n * dist v₁ v₂ := by
      calc |σ / n * ∑ i, (w₁ i - w₂ i) * g (x i)|
          ≤ Real.sqrt (∑ i, (w₁ i - w₂ i)^2) * (σ * u / Real.sqrt n) := h_cs g hg
        _ = σ * u / Real.sqrt n * Real.sqrt (∑ i, (w₁ i - w₂ i)^2) := by ring
        _ = σ * u / Real.sqrt n * dist v₁ v₂ := by rw [← h_dist_L2]
    linarith
  -- Z(w₁) ≤ Z(w₂) + L * dist
  have h_sub₁ : (⨆ g ∈ empiricalSphere n H u x, |σ / n * ∑ i, w₁ i * g (x i)|) ≤
      (⨆ g ∈ empiricalSphere n H u x, |σ / n * ∑ i, w₂ i * g (x i)|) +
      σ * u / Real.sqrt n * dist v₁ v₂ := by
    apply ciSup_le
    intro g
    by_cases hg : g ∈ empiricalSphere n H u x
    · calc (⨆ _ : g ∈ empiricalSphere n H u x, |σ / n * ∑ i, w₁ i * g (x i)|)
          = |σ / n * ∑ i, w₁ i * g (x i)| := ciSup_pos hg
        _ ≤ _ := h_each_bound g hg
    · simp only [ciSup_neg hg, Real.sSup_empty]
      apply add_nonneg
      · obtain ⟨g₀, hg₀⟩ := hne
        apply le_ciSup_of_le _ g₀
        · rw [ciSup_pos hg₀]
          exact abs_nonneg _
        · exact ⟨sSup {y | ∃ g ∈ empiricalSphere n H u x, y = |σ / n * ∑ i, w₂ i * g (x i)|},
            fun y ⟨h, heq⟩ => by
              rw [← heq]; dsimp only []
              by_cases hh : h ∈ empiricalSphere n H u x
              · rw [ciSup_pos hh]; apply le_csSup hbdd₂; exact ⟨h, hh, rfl⟩
              · rw [ciSup_neg hh, Real.sSup_empty]; apply Real.sSup_nonneg; intro y ⟨_, _, hy⟩; exact hy ▸ abs_nonneg _⟩
      · apply mul_nonneg hL_nonneg dist_nonneg
  -- Z(w₂) ≤ Z(w₁) + L * dist (by symmetry)
  have h_sub₂ : (⨆ g ∈ empiricalSphere n H u x, |σ / n * ∑ i, w₂ i * g (x i)|) ≤
      (⨆ g ∈ empiricalSphere n H u x, |σ / n * ∑ i, w₁ i * g (x i)|) +
      σ * u / Real.sqrt n * dist v₁ v₂ := by
    have h_dist_symm : dist v₁ v₂ = dist v₂ v₁ := dist_comm v₁ v₂
    rw [h_dist_symm]
    have h_dist_L2' : dist v₂ v₁ = Real.sqrt (∑ i, (w₂ i - w₁ i)^2) := by
      rw [EuclideanSpace.dist_eq]
      congr 1
      apply Finset.sum_congr rfl
      intro i _
      simp only [Real.dist_eq, sq_abs]
      rfl
    -- Similar to above, but with w₁ and w₂ swapped
    have h_each_bound' : ∀ g ∈ empiricalSphere n H u x,
        |σ / n * ∑ i, w₂ i * g (x i)| ≤
        (⨆ h ∈ empiricalSphere n H u x, |σ / n * ∑ i, w₁ i * h (x i)|) +
        σ * u / Real.sqrt n * dist v₂ v₁ := by
      intro g hg
      have h1' : |σ / n * ∑ i, w₂ i * g (x i)| ≤
          |σ / n * ∑ i, w₁ i * g (x i)| + |σ / n * ∑ i, (w₂ i - w₁ i) * g (x i)| := by
        have := abs_sub_abs_le_abs_sub (σ / n * ∑ i, w₂ i * g (x i)) (σ / n * ∑ i, w₁ i * g (x i))
        have h_eq : σ / n * ∑ i, w₂ i * g (x i) - σ / n * ∑ i, w₁ i * g (x i) =
            σ / n * ∑ i, (w₂ i - w₁ i) * g (x i) := by
          rw [← mul_sub, ← Finset.sum_sub_distrib]
          congr 1
          apply Finset.sum_congr rfl
          intro i _
          ring
        have h_diff' : |σ / n * ∑ i, w₂ i * g (x i)| - |σ / n * ∑ i, w₁ i * g (x i)| ≤
            |σ / n * ∑ i, (w₂ i - w₁ i) * g (x i)| := by
          calc |σ / n * ∑ i, w₂ i * g (x i)| - |σ / n * ∑ i, w₁ i * g (x i)|
              ≤ |σ / n * ∑ i, w₂ i * g (x i) - σ / n * ∑ i, w₁ i * g (x i)| :=
                abs_sub_abs_le_abs_sub _ _
            _ = |σ / n * ∑ i, (w₂ i - w₁ i) * g (x i)| := by rw [h_eq]
        linarith
      have h2' : |σ / n * ∑ i, w₁ i * g (x i)| ≤
          ⨆ h ∈ empiricalSphere n H u x, |σ / n * ∑ i, w₁ i * h (x i)| := by
        have hbdd₁' : BddAbove (Set.range fun h => ⨆ _ : h ∈ empiricalSphere n H u x,
            |σ / n * ∑ i, w₁ i * h (x i)|) := by
          use sSup {y | ∃ g ∈ empiricalSphere n H u x, y = |σ / n * ∑ i, w₁ i * g (x i)|}
          intro y hy
          obtain ⟨h, heq⟩ := hy
          rw [← heq]; dsimp only []
          by_cases hh : h ∈ empiricalSphere n H u x
          · rw [ciSup_pos hh]; apply le_csSup hbdd₁; exact ⟨h, hh, rfl⟩
          · rw [ciSup_neg hh, Real.sSup_empty]; apply Real.sSup_nonneg; intro y ⟨_, _, hy⟩; exact hy ▸ abs_nonneg _
        apply le_ciSup_of_le hbdd₁' g
        rw [ciSup_pos hg]
      have h3' : |σ / n * ∑ i, (w₂ i - w₁ i) * g (x i)| ≤ σ * u / Real.sqrt n * dist v₂ v₁ := by
        have h_cs' : |σ / n * ∑ i, (w₂ i - w₁ i) * g (x i)| ≤
            Real.sqrt (∑ i, (w₂ i - w₁ i)^2) * (σ * u / Real.sqrt n) := by
          -- Use Cauchy-Schwarz (same as h_cs but with w₂ - w₁)
          have hg_norm : empiricalNorm n (fun i => g (x i)) = u := hg.2
          have h_inner : σ / n * ∑ i, (w₂ i - w₁ i) * g (x i) =
              ∑ i, (w₂ i - w₁ i) * (σ / n * g (x i)) := by
            rw [Finset.mul_sum]
            congr 1
            ext i
            ring
          rw [h_inner]
          have h_cs_inner := abs_sum_le_sqrt_sq_mul_sqrt_sq (fun i => w₂ i - w₁ i) (fun i => σ / n * g (x i))
          calc |∑ i, (w₂ i - w₁ i) * (σ / n * g (x i))|
              ≤ Real.sqrt (∑ i, (w₂ i - w₁ i)^2) * Real.sqrt (∑ i, (σ / n * g (x i))^2) := h_cs_inner
            _ = Real.sqrt (∑ i, (w₂ i - w₁ i)^2) * (σ * u / Real.sqrt n) := by
                congr 1
                exact coefficient_euclidean_norm hn σ u hσ g x hg_norm
        calc |σ / n * ∑ i, (w₂ i - w₁ i) * g (x i)|
            ≤ Real.sqrt (∑ i, (w₂ i - w₁ i)^2) * (σ * u / Real.sqrt n) := h_cs'
          _ = σ * u / Real.sqrt n * Real.sqrt (∑ i, (w₂ i - w₁ i)^2) := by ring
          _ = σ * u / Real.sqrt n * dist v₂ v₁ := by rw [← h_dist_L2']
      linarith
    apply ciSup_le
    intro g
    by_cases hg : g ∈ empiricalSphere n H u x
    · calc (⨆ _ : g ∈ empiricalSphere n H u x, |σ / n * ∑ i, w₂ i * g (x i)|)
          = |σ / n * ∑ i, w₂ i * g (x i)| := ciSup_pos hg
        _ ≤ _ := h_each_bound' g hg
    · simp only [ciSup_neg hg, Real.sSup_empty]
      apply add_nonneg
      · obtain ⟨g₀, hg₀⟩ := hne
        apply le_ciSup_of_le _ g₀
        · rw [ciSup_pos hg₀]
          exact abs_nonneg _
        · exact ⟨sSup {y | ∃ g ∈ empiricalSphere n H u x, y = |σ / n * ∑ i, w₁ i * g (x i)|},
            fun y ⟨h, heq⟩ => by
              rw [← heq]; dsimp only []
              by_cases hh : h ∈ empiricalSphere n H u x
              · rw [ciSup_pos hh]; apply le_csSup hbdd₁; exact ⟨h, hh, rfl⟩
              · rw [ciSup_neg hh, Real.sSup_empty]; apply Real.sSup_nonneg; intro y ⟨_, _, hy⟩; exact hy ▸ abs_nonneg _⟩
      · apply mul_nonneg hL_nonneg dist_nonneg
  -- Combine to get |Z(w₁) - Z(w₂)| ≤ L * dist
  rw [abs_sub_le_iff]
  constructor
  · linarith
  · linarith

where
  abs_sum_le_sqrt_sq_mul_sqrt_sq (a b : Fin n → ℝ) :
      |∑ i, a i * b i| ≤ Real.sqrt (∑ i, (a i)^2) * Real.sqrt (∑ i, (b i)^2) := by
    -- Cauchy-Schwarz inequality (direct form from Mathlib)
    rw [abs_le]
    constructor
    · -- -√... ≤ ∑ a i * b i
      have h := Real.sum_mul_le_sqrt_mul_sqrt Finset.univ (fun i => -a i) b
      simp_rw [neg_mul, sum_neg_distrib, neg_sq] at h
      linarith
    · -- ∑ a i * b i ≤ √...
      exact Real.sum_mul_le_sqrt_mul_sqrt Finset.univ a b

/-- The empirical sphere is a subset of the localized ball -/
lemma empiricalSphere_subset_localizedBall (H : Set (X → ℝ)) (u : ℝ) (x : Fin n → X) :
    empiricalSphere n H u x ⊆ localizedBall H u x := by
  intro g hg
  constructor
  · exact hg.1
  · rw [hg.2]

/-- Convert ball boundedness with n⁻¹ to sphere boundedness with σ/n.
    This is useful for applying Z_supremum_lipschitz when the hypothesis uses n⁻¹ without σ. -/
lemma sphere_bddAbove_with_sigma {H : Set (X → ℝ)} {u σ : ℝ} {x : Fin n → X} (hσ : 0 < σ)
    (hbdd : ∀ w : Fin n → ℝ, BddAbove {y | ∃ h ∈ localizedBall H u x,
        y = |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|}) :
    ∀ w : Fin n → ℝ, BddAbove {y | ∃ g ∈ empiricalSphere n H u x,
        y = |σ / n * ∑ i, w i * g (x i)|} := by
  intro w
  have h_subset := empiricalSphere_subset_localizedBall H u x
  obtain ⟨M, hM⟩ := hbdd w
  use σ * M
  intro y hy
  obtain ⟨g, hg_sphere, hy_eq⟩ := hy
  rw [hy_eq]
  have hg_ball := h_subset hg_sphere
  have h_bound := hM ⟨g, hg_ball, rfl⟩
  -- |σ/n * ∑| = σ * |n⁻¹ * ∑| (since σ > 0)
  have h_eq : |σ / n * ∑ i, w i * g (x i)| = σ * |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)| := by
    rw [div_eq_mul_inv]
    -- σ * n⁻¹ * ∑ = σ * (n⁻¹ * ∑)
    rw [mul_assoc]
    rw [abs_mul, abs_of_pos hσ]
  rw [h_eq]
  exact mul_le_mul_of_nonneg_left h_bound (le_of_lt hσ)

/-!
## Expectation Bound for Z(u)

E[Z(u)] ≤ σ·G_n(u) = σ·u·(G_n(u)/u) ≤ σ·u·(G_n(δ*)/δ*) ≤ σ·u·(δ*/(2σ)) = uδ*/2.
-/

/-- Z(u) ≤ σ * (local Gaussian complexity at radius u)

Note: Z(u) uses sphere while G_n uses ball, so Z(u) ≤ σ * G_n(u). -/
lemma Z_le_sigma_mul_localComplexity (n : ℕ) (hn : 0 < n) (σ : ℝ) (H : Set (X → ℝ)) (u : ℝ)
    (x : Fin n → X) (w : Fin n → ℝ) (hσ : 0 < σ) :
    Z_supremum n σ H u x w ≤ σ * (⨆ g ∈ localizedBall H u x, |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)|) := by
  unfold Z_supremum
  -- The sphere is a subset of the ball
  have h_subset : empiricalSphere n H u x ⊆ localizedBall H u x := by
    intro g hg
    constructor
    · exact hg.1
    · rw [hg.2]
  -- sup over subset ≤ sup over superset
  have h1 : ⨆ g ∈ empiricalSphere n H u x, |σ / n * ∑ i, w i * g (x i)| ≤
      ⨆ g ∈ localizedBall H u x, |σ / n * ∑ i, w i * g (x i)| := by
    -- Sphere ⊆ Ball, so sup over sphere ≤ sup over ball
    -- Since sphere ⊆ ball, {f g | g ∈ sphere} ⊆ {f g | g ∈ ball}
    -- So sSup of former ≤ sSup of latter
    let f := fun g : X → ℝ => |σ / n * ∑ i, w i * g (x i)|
    -- biSup S f = sSup (Set.range (fun g : S => f g))
    -- Use the subtype approach
    have h_sphere_le : ∀ g : X → ℝ, g ∈ empiricalSphere n H u x →
        f g ≤ ⨆ h ∈ localizedBall H u x, f h := by
      intro g hg
      have hg_ball := h_subset hg
      -- u ≥ 0 since empiricalNorm = √(...) ≥ 0 and empiricalNorm n (g ∘ x) = u
      have hu_nonneg : 0 ≤ u := by
        have h_eq := hg.2  -- empiricalNorm n (fun i => g (x i)) = u
        rw [← h_eq]
        exact empiricalNorm_nonneg n (fun i => g (x i))
      -- f g ≤ sup over ball
      apply le_csSup
      · -- BddAbove for ball - use Cauchy-Schwarz bound
        -- |σ/n * ∑ w_i g(x_i)| ≤ |σ|/n * ‖w‖ * ‖g∘x‖ ≤ σ * u * ‖w‖ / √n
        let bound := |σ| * u * Real.sqrt (∑ i, (w i)^2) / Real.sqrt n + 1
        use bound
        intro y hy
        simp only [Set.mem_range] at hy
        obtain ⟨h, rfl⟩ := hy
        by_cases hh : h ∈ localizedBall H u x
        · simp only [ciSup_pos hh]
          -- |σ/n * ∑ w_i h(x_i)| ≤ bound
          have h_cs : |∑ i, w i * h (x i)| ≤ Real.sqrt (∑ i, (w i)^2) * Real.sqrt (∑ i, (h (x i))^2) := by
            rw [abs_le]
            constructor
            · have h' := Real.sum_mul_le_sqrt_mul_sqrt Finset.univ (fun i => -w i) (fun i => h (x i))
              simp_rw [neg_mul, Finset.sum_neg_distrib, neg_sq] at h'
              linarith
            · exact Real.sum_mul_le_sqrt_mul_sqrt Finset.univ w (fun i => h (x i))
          have h_norm : Real.sqrt (∑ i, (h (x i))^2) ≤ Real.sqrt n * u := by
            have hh_norm := hh.2
            rw [empiricalNorm] at hh_norm
            -- From √((n⁻¹) * ∑ h(x)²) ≤ u, we get ∑ h(x)² ≤ n * u²
            have h_sum_nonneg : 0 ≤ ∑ i, (h (x i))^2 := Finset.sum_nonneg (fun i _ => sq_nonneg _)
            have h_sqrt_nonneg : 0 ≤ Real.sqrt ((n : ℝ)⁻¹ * ∑ i, (h (x i))^2) := Real.sqrt_nonneg _
            have h_u_nonneg : 0 ≤ u := le_trans h_sqrt_nonneg hh_norm
            have h_sum : ∑ i, (h (x i))^2 ≤ n * u^2 := by
              have h_sq := sq_le_sq' (by linarith) hh_norm
              rw [sq_sqrt (by positivity : 0 ≤ (n : ℝ)⁻¹ * ∑ i, (h (x i))^2)] at h_sq
              have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
              calc ∑ i, (h (x i))^2 = n * ((n : ℝ)⁻¹ * ∑ i, (h (x i))^2) := by field_simp
                _ ≤ n * u^2 := by nlinarith [sq_nonneg u]
            calc Real.sqrt (∑ i, (h (x i))^2) ≤ Real.sqrt (n * u^2) := Real.sqrt_le_sqrt h_sum
              _ = Real.sqrt n * |u| := Real.sqrt_mul (Nat.cast_nonneg n) (u^2) ▸ Real.sqrt_sq_eq_abs u ▸ rfl
              _ = Real.sqrt n * u := by rw [abs_of_nonneg h_u_nonneg]
          calc |σ / n * ∑ i, w i * h (x i)| = |σ| / n * |∑ i, w i * h (x i)| := by
                rw [abs_mul, abs_div]
                congr 2
                exact abs_of_nonneg (Nat.cast_nonneg n)
            _ ≤ |σ| / n * (Real.sqrt (∑ i, (w i)^2) * Real.sqrt (∑ i, (h (x i))^2)) := by
                apply mul_le_mul_of_nonneg_left h_cs; positivity
            _ ≤ |σ| / n * (Real.sqrt (∑ i, (w i)^2) * (Real.sqrt n * u)) := by
                apply mul_le_mul_of_nonneg_left; apply mul_le_mul_of_nonneg_left h_norm; positivity; positivity
            _ = |σ| * u * Real.sqrt (∑ i, (w i)^2) / Real.sqrt n := by
                field_simp
                rw [Real.sq_sqrt (Nat.cast_nonneg n)]
                ring
            _ ≤ bound := le_add_of_nonneg_right (by linarith)
        · -- When h ∉ ball, the inner iSup is sSup ∅ = 0 in ℝ
          have h_iSup_eq : (⨆ _ : h ∈ localizedBall H u x, |σ / n * ∑ i, w i * h (x i)|) = 0 := by
            have h_range_empty : Set.range (fun _ : h ∈ localizedBall H u x => |σ / n * ∑ i, w i * h (x i)|) = ∅ := by
              ext y
              simp only [Set.mem_range, Set.mem_empty_iff_false, iff_false]
              intro ⟨hmem, _⟩
              exact hh hmem
            simp only [iSup, h_range_empty, Real.sSup_empty]
          rw [h_iSup_eq]
          calc (0 : ℝ) ≤ |σ| * u * Real.sqrt (∑ i, (w i)^2) / Real.sqrt n := by positivity
            _ ≤ bound := le_add_of_nonneg_right (by linarith)
      · simp only [Set.mem_range]
        refine ⟨g, ?_⟩
        simp only [ciSup_pos hg_ball]
    -- Now use csSup_le
    apply csSup_le
    · -- Range nonempty: the range of (fun g => ⨆ _ : g ∈ sphere, f g) is always nonempty
      -- since for any g, we get some value (either f g or sSup ∅ = 0)
      use 0
      simp only [Set.mem_range]
      -- Need: ∃ g, ⨆ _ : g ∈ sphere, f g = 0
      -- This is true when g ∉ sphere (then inner iSup = sSup ∅ = 0)
      by_cases hne : (empiricalSphere n H u x).Nonempty
      · obtain ⟨g₀, hg₀⟩ := hne
        use fun _ => 0  -- the zero function
        have h0_not_in_sphere : (fun _ => (0 : ℝ)) ∉ empiricalSphere n H u x ∨
                                 (fun _ => (0 : ℝ)) ∈ empiricalSphere n H u x := by tauto
        rcases h0_not_in_sphere with h0_out | h0_in
        · -- 0 ∉ sphere, so inner iSup = sSup ∅ = 0
          have h_range_empty : Set.range (fun _ : (fun _ => (0 : ℝ)) ∈ empiricalSphere n H u x =>
              |σ / n * ∑ i, w i * (fun _ => (0 : ℝ)) (x i)|) = ∅ := by
            ext y
            simp only [Set.mem_range, Set.mem_empty_iff_false, iff_false]
            intro ⟨hmem, _⟩
            exact h0_out hmem
          simp only [iSup, h_range_empty, Real.sSup_empty]
        · -- 0 ∈ sphere, so inner iSup = f 0 = |σ/n * 0| = 0
          have h0_val : (⨆ _ : (fun _ => (0 : ℝ)) ∈ empiricalSphere n H u x,
              |σ / n * ∑ i, w i * (fun _ => (0 : ℝ)) (x i)|) = 0 := by
            rw [ciSup_pos h0_in]
            simp
          exact h0_val
      · -- Sphere is empty, use any function
        simp only [Set.not_nonempty_iff_eq_empty] at hne
        use fun _ => 0
        have h_range_empty : Set.range (fun _ : (fun _ => (0 : ℝ)) ∈ empiricalSphere n H u x =>
            |σ / n * ∑ i, w i * (fun _ => (0 : ℝ)) (x i)|) = ∅ := by
          ext y
          simp only [Set.mem_range, Set.mem_empty_iff_false, iff_false]
          intro ⟨hmem, _⟩
          rw [hne] at hmem
          exact hmem
        simp only [iSup, h_range_empty, Real.sSup_empty]
    · intro y hy
      simp only [Set.mem_range] at hy
      obtain ⟨g, rfl⟩ := hy
      -- Need: ⨆ _ : g ∈ sphere, f g ≤ ⨆ h ∈ ball, f h
      by_cases hg : g ∈ empiricalSphere n H u x
      · -- g ∈ sphere: ⨆ _ : g ∈ sphere, f g = f g ≤ sup over ball
        rw [ciSup_pos hg]
        exact h_sphere_le g hg
      · -- g ∉ sphere: ⨆ _ : g ∈ sphere, f g = sSup ∅ = 0 ≤ anything nonneg
        have h_inner_zero : (⨆ _ : g ∈ empiricalSphere n H u x, f g) = 0 := by
          have h_range_empty : Set.range (fun _ : g ∈ empiricalSphere n H u x => f g) = ∅ := by
            ext y
            simp only [Set.mem_range, Set.mem_empty_iff_false, iff_false]
            intro ⟨hmem, _⟩
            exact hg hmem
          simp only [iSup, h_range_empty, Real.sSup_empty]
        rw [h_inner_zero]
        -- 0 ≤ ⨆ h ∈ ball, f h
        apply Real.sSup_nonneg
        intro y hy
        simp only [Set.mem_range] at hy
        obtain ⟨h, rfl⟩ := hy
        by_cases hh_ball : h ∈ localizedBall H u x
        · simp only [ciSup_pos hh_ball]
          exact abs_nonneg _
        · have h_inner_zero' : (⨆ _ : h ∈ localizedBall H u x, f h) = 0 := by
            have h_range_empty' : Set.range (fun _ : h ∈ localizedBall H u x => f h) = ∅ := by
              ext y
              simp only [Set.mem_range, Set.mem_empty_iff_false, iff_false]
              intro ⟨hmem, _⟩
              exact hh_ball hmem
            simp only [iSup, h_range_empty', Real.sSup_empty]
          rw [h_inner_zero']
  -- Now factor out σ
  have h2 : ⨆ g ∈ localizedBall H u x, |σ / n * ∑ i, w i * g (x i)| =
      σ * ⨆ g ∈ localizedBall H u x, |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)| := by
    have h_factor : ∀ g : X → ℝ, |σ / n * ∑ i, w i * g (x i)| = σ * |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)| := by
      intro g
      rw [div_eq_mul_inv, mul_assoc, abs_mul, abs_of_pos hσ]
    conv_lhs =>
      arg 1
      ext g
      arg 1
      ext _
      rw [h_factor g]
    simp only [Real.mul_iSup_of_nonneg (le_of_lt hσ)]
  linarith [h1, le_of_eq h2.symm]

/-- E[Z(u)] ≤ u·δ* when u ≥ δ* and critical inequality holds.

**Proof**: E[Z(u)] ≤ σ·G_n(u) = σ·u·(G_n(u)/u) ≤ σ·u·(G_n(δ*)/δ*) ≤ σ·u·(δ*/(2σ)) = uδ*/2. -/
lemma Z_expectation_bound (hn : 0 < n) {σ δ_star u : ℝ}
    (hσ : 0 < σ) (hδ : 0 < δ_star) (hu : 0 < u) (hδu : δ_star ≤ u)
    (H : Set (X → ℝ)) (hH : IsStarShaped H) (x : Fin n → X)
    (hCI : satisfiesCriticalInequality n σ δ_star H x)
    -- Integrability and boundedness hypotheses
    (hint_u : Integrable (fun w => ⨆ h ∈ localizedBall H u x,
        |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|) (stdGaussianPi n))
    (hint_δ : Integrable (fun w => ⨆ h ∈ localizedBall H δ_star x,
        |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|) (stdGaussianPi n))
    (hbdd : ∀ w : Fin n → ℝ, BddAbove {y | ∃ h ∈ localizedBall H u x,
        y = |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|}) :
    ∫ w, Z_supremum n σ H u x w ∂(stdGaussianPi n) ≤ u * δ_star := by
  -- Step 1: E[Z(u)] ≤ σ G_n(u)
  have h1 : ∫ w, Z_supremum n σ H u x w ∂(stdGaussianPi n) ≤
      σ * LocalGaussianComplexity n H u x := by
    have h_pw : ∀ w, Z_supremum n σ H u x w ≤
        σ * (⨆ g ∈ localizedBall H u x, |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)|) :=
      fun w => Z_le_sigma_mul_localComplexity n hn σ H u x w hσ
    have h_int_bound : ∫ w, Z_supremum n σ H u x w ∂(stdGaussianPi n) ≤
        ∫ w, σ * (⨆ g ∈ localizedBall H u x, |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)|) ∂(stdGaussianPi n) := by
      apply integral_mono_of_nonneg
      · -- Z is nonneg
        apply ae_of_all
        intro w
        unfold Z_supremum
        apply Real.iSup_nonneg
        intro g
        apply Real.iSup_nonneg
        intro _
        exact abs_nonneg _
      · -- σ * sup is integrable
        exact hint_u.const_mul σ
      · -- pointwise bound
        apply ae_of_all
        exact h_pw
    -- Factor out σ from integral
    rw [integral_const_mul] at h_int_bound
    exact h_int_bound
  -- Step 2: Use monotonicity to get G_n(u)/u ≤ G_n(δ*)/δ*
  have h_mono : LocalGaussianComplexity n H u x / u ≤
      LocalGaussianComplexity n H δ_star x / δ_star :=
    gaussian_complexity_monotone hH hδ hu hδu hint_u hint_δ hbdd
  -- Step 3: Use critical inequality G_n(δ*)/δ* ≤ δ*/(2σ)
  have h_CI : LocalGaussianComplexity n H δ_star x / δ_star ≤ δ_star / (2 * σ) := hCI
  -- Step 4: Chain the inequalities
  calc ∫ w, Z_supremum n σ H u x w ∂(stdGaussianPi n)
      ≤ σ * LocalGaussianComplexity n H u x := h1
    _ = σ * u * (LocalGaussianComplexity n H u x / u) := by field_simp
    _ ≤ σ * u * (LocalGaussianComplexity n H δ_star x / δ_star) := by
        apply mul_le_mul_of_nonneg_left h_mono; positivity
    _ ≤ σ * u * (δ_star / (2 * σ)) := by
        apply mul_le_mul_of_nonneg_left h_CI; positivity
    _ = u * δ_star / 2 := by field_simp
    _ ≤ u * δ_star := by linarith [mul_pos hu hδ]

/-!
## Bad Event Probability Bound (Lemma 2)

The main concentration argument using Gaussian Lipschitz concentration.
-/

/-- For u ≥ δ*, P(A(u)) ≤ exp(-nu²/(2σ²)).

**Proof**:
1. Reduce to P(Z(u) ≥ 2u²)
2. Use E[Z(u)] ≤ uδ* ≤ u² to get P(Z(u) - E[Z(u)] ≥ u²)
3. Apply Gaussian Lipschitz concentration with L = σu/√n -/
theorem bad_event_probability_bound (hn : 0 < n) {σ δ_star u : ℝ}
    (hσ : 0 < σ) (hδ : 0 < δ_star) (hu : 0 < u) (hδu : δ_star ≤ u)
    (H : Set (X → ℝ)) (hH : IsStarShaped H) (x : Fin n → X)
    (hCI : satisfiesCriticalInequality n σ δ_star H x)
    -- Technical hypotheses
    (hne : (empiricalSphere n H u x).Nonempty)
    (hint_u : Integrable (fun w => ⨆ h ∈ localizedBall H u x,
        |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|) (stdGaussianPi n))
    (hint_δ : Integrable (fun w => ⨆ h ∈ localizedBall H δ_star x,
        |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|) (stdGaussianPi n))
    (hbdd : ∀ w : Fin n → ℝ, BddAbove {y | ∃ h ∈ localizedBall H u x,
        y = |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|}) :
    (stdGaussianPi n (badEvent n σ H u x)).toReal ≤ exp (-n * u^2 / (2 * σ^2)) := by
  -- The bad event is contained in {Z(u) ≥ 2u²}
  -- Which is contained in {Z(u) - E[Z(u)] ≥ u²} since E[Z(u)] ≤ uδ* ≤ u²
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have hL : 0 < σ * u / Real.sqrt n := by positivity

  -- First, bound bad event by Z(u) ≥ 2u²
  have h_subset : badEvent n σ H u x ⊆ {w | 2 * u^2 ≤ Z_supremum n σ H u x w} := by
    intro w hw
    simp only [Set.mem_setOf_eq]
    obtain ⟨g, hg_mem, hg_bound⟩ := hw
    -- g ∈ outer region means ‖g‖_n ≥ u
    have hg_norm : u ≤ empiricalNorm n (fun i => g (x i)) := hg_mem.2
    -- The bound gives |...| ≥ 2 ‖g‖_n u ≥ 2u²
    have h1 : 2 * empiricalNorm n (fun i => g (x i)) * u ≥ 2 * u * u := by
      nlinarith [empiricalNorm_nonneg n (fun i => g (x i))]
    have h2 : 2 * u^2 ≤ |σ / n * ∑ i, w i * g (x i)| := by
      calc 2 * u^2 = 2 * u * u := by ring
        _ ≤ 2 * empiricalNorm n (fun i => g (x i)) * u := h1
        _ ≤ |σ / n * ∑ i, w i * g (x i)| := hg_bound
    -- Z(u) is sup over sphere with norm = u
    -- But we need to relate to g which may have norm > u
    -- For star-shaped H, we can scale g down to the sphere
    -- Let t = ‖g‖_n and α = u/t ∈ (0,1], then g' = α • g is on the sphere
    set t := empiricalNorm n (fun i => g (x i)) with ht_def
    have ht_pos : 0 < t := lt_of_lt_of_le hu hg_norm
    set α := u / t with hα_def
    have hα_pos : 0 < α := div_pos hu ht_pos
    have hα_le_one : α ≤ 1 := (div_le_one ht_pos).mpr hg_norm
    -- g' = α • g is in H by star-shapedness
    set g' := fun y => α * g y with hg'_def
    have hg_in_H : g ∈ H := hg_mem.1
    have hg'_in_H : g' ∈ H := by
      have hsmul : (α • g) ∈ H := hH.2 g hg_in_H α (le_of_lt hα_pos) hα_le_one
      exact hsmul
    -- ‖g'‖_n = u
    have hg'_norm : empiricalNorm n (fun i => g' (x i)) = u := by
      unfold empiricalNorm
      have h_sum : ∑ k, (g' (x k))^2 = α^2 * ∑ k, (g (x k))^2 := by
        simp only [hg'_def, mul_pow]
        rw [Finset.mul_sum]
      have ht_sq : (n : ℝ)⁻¹ * ∑ k, (g (x k))^2 = t^2 :=
        (empiricalNorm_sq n (fun i => g (x i))).symm
      calc Real.sqrt ((n : ℝ)⁻¹ * ∑ k, (g' (x k))^2)
          = Real.sqrt ((n : ℝ)⁻¹ * (α^2 * ∑ k, (g (x k))^2)) := by rw [h_sum]
        _ = Real.sqrt (α^2 * ((n : ℝ)⁻¹ * ∑ k, (g (x k))^2)) := by ring_nf
        _ = Real.sqrt (α^2 * t^2) := by rw [ht_sq]
        _ = Real.sqrt ((α * t)^2) := by ring_nf
        _ = |α * t| := Real.sqrt_sq_eq_abs (α * t)
        _ = α * t := abs_of_pos (mul_pos hα_pos ht_pos)
        _ = (u / t) * t := by rw [hα_def]
        _ = u := by field_simp
    -- g' is on the sphere
    have hg'_sphere : g' ∈ empiricalSphere n H u x := ⟨hg'_in_H, hg'_norm⟩
    -- The sum scales: ∑ w_i g'(x_i) = α * ∑ w_i g(x_i)
    have h_sum_scale : ∑ i, w i * g' (x i) = α * ∑ i, w i * g (x i) := by
      simp only [hg'_def]
      have h_each : ∀ i, w i * (α * g (x i)) = α * (w i * g (x i)) := fun i => by ring
      simp_rw [h_each, ← Finset.mul_sum]
    -- |σ/n * ∑ w_i g'(x_i)| = α * |σ/n * ∑ w_i g(x_i)| ≥ α * 2tu = 2u²
    have h_scaled_bound : |σ / n * ∑ i, w i * g' (x i)| ≥ 2 * u^2 := by
      rw [h_sum_scale]
      have h_eq : σ / n * (α * ∑ i, w i * g (x i)) = α * (σ / n * ∑ i, w i * g (x i)) := by ring
      rw [h_eq, abs_mul, abs_of_pos hα_pos]
      calc α * |σ / n * ∑ i, w i * g (x i)| ≥ α * (2 * t * u) := by
            apply mul_le_mul_of_nonneg_left hg_bound (le_of_lt hα_pos)
        _ = (u / t) * (2 * t * u) := by rw [hα_def]
        _ = 2 * u^2 := by field_simp
    -- Z(u) ≥ |σ/n * ∑ w_i g'(x_i)| since g' is on the sphere
    unfold Z_supremum
    calc 2 * u^2 ≤ |σ / n * ∑ i, w i * g' (x i)| := h_scaled_bound
      _ ≤ ⨆ h ∈ empiricalSphere n H u x, |σ / n * ∑ i, w i * h (x i)| := by
          apply le_csSup
          · -- BddAbove
            use |σ| * u * Real.sqrt (∑ i, (w i)^2) / Real.sqrt n + 1
            intro y hy
            simp only [Set.mem_range] at hy
            obtain ⟨h, rfl⟩ := hy
            by_cases hh : h ∈ empiricalSphere n H u x
            · simp only [ciSup_pos hh]
              -- Bound using Cauchy-Schwarz (same as in Z_le_sigma_mul_localComplexity)
              have h_cs : |∑ i, w i * h (x i)| ≤ Real.sqrt (∑ i, (w i)^2) * Real.sqrt (∑ i, (h (x i))^2) := by
                rw [abs_le]
                constructor
                · have h' := Real.sum_mul_le_sqrt_mul_sqrt Finset.univ (fun i => -w i) (fun i => h (x i))
                  simp_rw [neg_mul, Finset.sum_neg_distrib, neg_sq] at h'
                  linarith
                · exact Real.sum_mul_le_sqrt_mul_sqrt Finset.univ w (fun i => h (x i))
              have h_norm_eq : Real.sqrt (∑ i, (h (x i))^2) = Real.sqrt n * u := by
                have hh_norm := hh.2
                rw [empiricalNorm] at hh_norm
                have h_sum : ∑ i, (h (x i))^2 = n * u^2 := by
                  have h_inner_nonneg : 0 ≤ (n : ℝ)⁻¹ * ∑ i, (h (x i))^2 := by positivity
                  have h_eq : (n : ℝ)⁻¹ * ∑ i, (h (x i))^2 = u^2 := by
                    calc (n : ℝ)⁻¹ * ∑ i, (h (x i))^2
                        = Real.sqrt ((n : ℝ)⁻¹ * ∑ i, (h (x i))^2) ^ 2 := (sq_sqrt h_inner_nonneg).symm
                      _ = u ^ 2 := by rw [hh_norm]
                  have hn_pos' : (0 : ℝ) < n := Nat.cast_pos.mpr hn
                  field_simp at h_eq ⊢
                  linarith
                rw [h_sum, Real.sqrt_mul (Nat.cast_nonneg n), Real.sqrt_sq (le_of_lt hu)]
              calc |σ / n * ∑ i, w i * h (x i)| = |σ| / n * |∑ i, w i * h (x i)| := by
                    have h_abs_quot : |σ / ↑n| = |σ| / ↑n := by
                      rw [abs_div]
                      congr 1
                      exact abs_of_pos (Nat.cast_pos.mpr hn)
                    rw [abs_mul, h_abs_quot]
                _ ≤ |σ| / n * (Real.sqrt (∑ i, (w i)^2) * Real.sqrt (∑ i, (h (x i))^2)) := by
                    apply mul_le_mul_of_nonneg_left h_cs; positivity
                _ = |σ| / n * (Real.sqrt (∑ i, (w i)^2) * (Real.sqrt n * u)) := by rw [h_norm_eq]
                _ = |σ| * u * Real.sqrt (∑ i, (w i)^2) / Real.sqrt n := by
                    field_simp; rw [Real.sq_sqrt (Nat.cast_nonneg n)]; ring
                _ ≤ |σ| * u * Real.sqrt (∑ i, (w i)^2) / Real.sqrt n + 1 := le_add_of_nonneg_right (by linarith)
            · -- h ∉ sphere, so inner iSup = sSup ∅ = 0
              have h_eq_zero : (⨆ _ : h ∈ empiricalSphere n H u x, |σ / n * ∑ i, w i * h (x i)|) = 0 := by
                have h_range_empty : Set.range (fun _ : h ∈ empiricalSphere n H u x => |σ / n * ∑ i, w i * h (x i)|) = ∅ := by
                  ext y; simp only [Set.mem_range, Set.mem_empty_iff_false, iff_false]
                  intro ⟨hmem, _⟩; exact hh hmem
                simp only [iSup, h_range_empty, Real.sSup_empty]
              rw [h_eq_zero]; positivity
          · -- Member of range
            simp only [Set.mem_range]
            exact ⟨g', ciSup_pos hg'_sphere⟩

  -- Now apply Gaussian Lipschitz concentration

  -- Define lifted function on EuclideanSpace
  let e := EuclideanSpace.equiv (Fin n) ℝ
  let μ_E := stdGaussianE n
  let Z_E : EuclideanSpace ℝ (Fin n) → ℝ := Z_supremum n σ H u x ∘ e

  -- Derive hZ_E_lip from Z_supremum_lipschitz using hne and sphere boundedness
  -- Z_supremum_lipschitz directly gives Lipschitz for Z_E = Z_supremum ∘ e on EuclideanSpace
  have hbdd_sphere := sphere_bddAbove_with_sigma hσ hbdd
  have hZ_E_lip : LipschitzWith (Real.toNNReal (σ * u / Real.sqrt n)) Z_E :=
    Z_supremum_lipschitz hn σ u hσ hu H x hne hbdd_sphere

  -- Convert Lipschitz constant to ℝ≥0 for the concentration lemma
  have hL_pos : (0 : NNReal) < (σ * u / Real.sqrt n).toNNReal := by
    exact Real.toNNReal_pos.mpr hL

  -- Apply general Lipschitz concentration on EuclideanSpace
  have h_conc_E := GaussianLipConcen.gaussian_lipschitz_concentration_one_sided
      hn hL_pos hZ_E_lip (u^2) (sq_pos_of_pos hu)

  -- Transfer: integrals match by change of variables
  have h_int_eq : ∫ y, Z_E y ∂μ_E = ∫ w, Z_supremum n σ H u x w ∂(stdGaussianPi n) := by
    rw [integral_stdGaussianE_eq]
    congr 1

  -- Transfer: measures of sets match
  have h_meas_eq : μ_E {y | u^2 ≤ Z_E y - ∫ z, Z_E z ∂μ_E} =
      stdGaussianPi n {w | u^2 ≤ Z_supremum n σ H u x w - ∫ z, Z_supremum n σ H u x z ∂(stdGaussianPi n)} := by
    -- First rewrite the integral using h_int_eq
    conv_lhs => rw [h_int_eq]
    simp only [μ_E, stdGaussianE]
    rw [Measure.map_apply]
    · congr 1
    · exact e.symm.continuous.measurable
    · apply measurableSet_le measurable_const
      apply Measurable.sub
      -- Z_E = Z_supremum ∘ e is measurable (from Lipschitz)
      · exact hZ_E_lip.continuous.measurable
      · exact measurable_const

  -- The concentration bound transfers
  have h_conc : (stdGaussianPi n {w | u^2 ≤ Z_supremum n σ H u x w -
      ∫ z, Z_supremum n σ H u x z ∂(stdGaussianPi n)}).toReal ≤
      exp (-(u^2)^2 / (2 * (σ * u / Real.sqrt n)^2)) := by
    rw [← h_meas_eq]
    convert h_conc_E using 2
    simp only [Real.coe_toNNReal _ (le_of_lt hL)]

  -- The exponent simplifies: -u⁴/(2(σu/√n)²) = -u⁴/(2σ²u²/n) = -nu²/(2σ²)
  have h_exp_eq : -(u^2)^2 / (2 * (σ * u / Real.sqrt n)^2) = -n * u^2 / (2 * σ^2) := by
    have hsqrt_ne : Real.sqrt n ≠ 0 := Real.sqrt_ne_zero'.mpr hn_pos
    have hsqrt_sq : Real.sqrt n ^ 2 = n := Real.sq_sqrt (le_of_lt hn_pos)
    field_simp
    rw [hsqrt_sq]

  -- Monotonicity of measure
  calc (stdGaussianPi n (badEvent n σ H u x)).toReal
      ≤ (stdGaussianPi n {w | 2 * u^2 ≤ Z_supremum n σ H u x w}).toReal := by
        apply ENNReal.toReal_mono (measure_ne_top _ _)
        exact measure_mono h_subset
    _ ≤ (stdGaussianPi n {w | u^2 ≤ Z_supremum n σ H u x w -
        ∫ y, Z_supremum n σ H u x y ∂(stdGaussianPi n)}).toReal := by
        -- Use expectation bound: E[Z(u)] ≤ uδ* ≤ u² (since δ* ≤ u)
        apply ENNReal.toReal_mono (measure_ne_top _ _)
        apply measure_mono
        intro w hw
        simp only [Set.mem_setOf_eq] at hw ⊢
        have h_exp := Z_expectation_bound hn hσ hδ hu hδu H hH x hCI hint_u hint_δ hbdd
        have h_exp' : ∫ y, Z_supremum n σ H u x y ∂(stdGaussianPi n) ≤ u * δ_star := h_exp
        have h_exp'' : u * δ_star ≤ u^2 := by nlinarith
        linarith
    _ ≤ exp (-(u^2)^2 / (2 * (σ * u / Real.sqrt n)^2)) := h_conc
    _ = exp (-n * u^2 / (2 * σ^2)) := by rw [h_exp_eq]

/-!
## Master Error Bound (Theorem 1)

Combines the basic inequality with the bad event probability bound.
-/

/-- Good event: complement of bad event at level √(tδ*) -/
def goodEvent (n : ℕ) (σ : ℝ) (H : Set (X → ℝ)) (t δ_star : ℝ) (x : Fin n → X) :
    Set (Fin n → ℝ) :=
  (badEvent n σ H (Real.sqrt (t * δ_star)) x)ᶜ

/-- On the good event, the empirical process is bounded for all g with ‖g‖_n ≥ √(tδ*) -/
lemma goodEvent_implies_process_bound {n : ℕ} {σ t δ_star : ℝ}
    {H : Set (X → ℝ)} {x : Fin n → X} {w : Fin n → ℝ}
    (hw : w ∈ goodEvent n σ H t δ_star x)
    (g : X → ℝ) (hg : g ∈ empiricalOuterRegion n H (Real.sqrt (t * δ_star)) x) :
    |σ / n * ∑ i, w i * g (x i)| < 2 * empiricalNorm n (fun i => g (x i)) * Real.sqrt (t * δ_star) := by
  simp only [goodEvent, Set.mem_compl_iff, badEvent, Set.mem_setOf_eq] at hw
  push_neg at hw
  exact hw g hg

/-- For t ≥ δ*, P(‖f̂ - f*‖_n² ≤ 16tδ*) ≥ 1 - exp(-ntδ*/(2σ²)).

**Proof**:
1. Basic inequality: (1/2)‖Δ‖_n² ≤ (σ/n) Σ wᵢΔ(xᵢ)
2. On good event A(√(tδ*))ᶜ, the RHS is bounded
3. Case split on ‖Δ‖_n vs √(tδ*) -/
theorem master_error_bound (hn : 0 < n)
    (M : RegressionModel n X) (F : Set (X → ℝ))
    (hF_star : M.f_star ∈ F)
    -- δ_star is the critical radius for the shifted class
    (δ_star : ℝ) (hδ : 0 < δ_star)
    (hCI : satisfiesCriticalInequality n M.σ δ_star (shiftedClass F M.f_star) M.x)
    (hH_star : IsStarShaped (shiftedClass F M.f_star))
    -- t ≥ δ_star
    (t : ℝ) (ht : δ_star ≤ t)
    -- Least squares estimator (depends on noise realization w)
    (f_hat : (Fin n → ℝ) → (X → ℝ))
    (hf_hat : ∀ w, isLeastSquaresEstimator (M.response w) F M.x (f_hat w))
    -- Technical hypotheses for the probability bound
    (hne : (empiricalSphere n (shiftedClass F M.f_star) (Real.sqrt (t * δ_star)) M.x).Nonempty)
    (hint_u : Integrable (fun w => ⨆ h ∈ localizedBall (shiftedClass F M.f_star)
        (Real.sqrt (t * δ_star)) M.x, |(n : ℝ)⁻¹ * ∑ i, w i * h (M.x i)|) (stdGaussianPi n))
    (hint_δ : Integrable (fun w => ⨆ h ∈ localizedBall (shiftedClass F M.f_star) δ_star M.x,
        |(n : ℝ)⁻¹ * ∑ i, w i * h (M.x i)|) (stdGaussianPi n))
    (hbdd : ∀ w : Fin n → ℝ, BddAbove {y | ∃ h ∈ localizedBall (shiftedClass F M.f_star)
        (Real.sqrt (t * δ_star)) M.x, y = |(n : ℝ)⁻¹ * ∑ i, w i * h (M.x i)|}) :
    (stdGaussianPi n {w | (empiricalNorm n (fun i => f_hat w (M.x i) - M.f_star (M.x i)))^2 ≤
        16 * t * δ_star}).toReal ≥
      1 - exp (-n * t * δ_star / (2 * M.σ^2)) := by
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have ht_pos : 0 < t := lt_of_lt_of_le hδ ht
  have htδ_pos : 0 < t * δ_star := mul_pos ht_pos hδ
  have hsqrt_pos : 0 < Real.sqrt (t * δ_star) := Real.sqrt_pos.mpr htδ_pos

  set u := Real.sqrt (t * δ_star) with hu_def
  set H := shiftedClass F M.f_star with hH_def

  -- δ_star ≤ u when t ≥ δ_star and δ_star > 0
  have hδu : δ_star ≤ u := by
    rw [hu_def]
    have h_sq : δ_star^2 ≤ t * δ_star := by nlinarith
    calc δ_star = Real.sqrt (δ_star^2) := (Real.sqrt_sq (le_of_lt hδ)).symm
      _ ≤ Real.sqrt (t * δ_star) := Real.sqrt_le_sqrt h_sq

  -- Probability of bad event
  have h_bad := bad_event_probability_bound hn M.hσ_pos hδ hsqrt_pos hδu H hH_star M.x hCI
      hne hint_u hint_δ hbdd

  -- Simplify the exponent: -n * u² / (2σ²) = -n * tδ* / (2σ²)
  have h_exp_eq : -n * u^2 / (2 * M.σ^2) = -n * t * δ_star / (2 * M.σ^2) := by
    rw [hu_def, Real.sq_sqrt (le_of_lt htδ_pos)]
    ring

  -- The good event implies the bound
  have h_good_implies : goodEvent n M.σ H t δ_star M.x ⊆
      {w | (empiricalNorm n (fun i => f_hat w (M.x i) - M.f_star (M.x i)))^2 ≤ 16 * t * δ_star} := by
    intro w hw
    simp only [Set.mem_setOf_eq]
    -- Set Δ = f_hat - f_star
    set Δ := fun i => f_hat w (M.x i) - M.f_star (M.x i) with hΔ_def
    set norm_Δ := empiricalNorm n Δ with hnorm_def

    -- Case analysis on ‖Δ‖_n
    by_cases hcase : norm_Δ ≤ u
    · -- Case 1: ‖Δ‖_n ≤ √(tδ*)
      calc norm_Δ^2 ≤ u^2 := sq_le_sq' (by linarith [empiricalNorm_nonneg n Δ]) hcase
        _ = t * δ_star := Real.sq_sqrt (le_of_lt htδ_pos)
        _ ≤ 16 * t * δ_star := by linarith [htδ_pos]
    · -- Case 2: ‖Δ‖_n > √(tδ*)
      push_neg at hcase
      -- Δ = f_hat - f_star is in the shifted class
      have hΔ_in_H : (fun y => f_hat w y - M.f_star y) ∈ H := by
        rw [hH_def]
        exact mem_shiftedClass_of_mem (hf_hat w).1
      -- Δ is in the outer region
      have hΔ_outer : (fun y => f_hat w y - M.f_star y) ∈ empiricalOuterRegion n H u M.x := by
        constructor
        · exact hΔ_in_H
        · simp only [hnorm_def, hΔ_def] at hcase
          exact le_of_lt hcase

      -- Use the good event bound
      have h_process_bound := goodEvent_implies_process_bound hw (fun y => f_hat w y - M.f_star y) hΔ_outer

      -- Use basic inequality
      have h_basic := basic_inequality hn M F (f_hat w) w (hf_hat w) hF_star

      have h_norm_pos : 0 < norm_Δ := lt_trans hsqrt_pos hcase

      -- From h_process_bound, adjusting for the σ factor
      have h1 : M.σ / ↑n * ∑ i : Fin n, w i * (f_hat w (M.x i) - M.f_star (M.x i)) ≤
          2 * norm_Δ * u := by
        have h_abs := h_process_bound
        -- |σ/n Σ wᵢΔᵢ| < 2‖Δ‖_n u
        calc M.σ / ↑n * ∑ i, w i * (f_hat w (M.x i) - M.f_star (M.x i))
            ≤ |M.σ / ↑n * ∑ i, w i * (f_hat w (M.x i) - M.f_star (M.x i))| := le_abs_self _
          _ ≤ 2 * empiricalNorm n (fun i => (fun y => f_hat w y - M.f_star y) (M.x i)) * u := le_of_lt h_abs
          _ = 2 * norm_Δ * u := by simp only [hnorm_def, hΔ_def]

      -- From basic inequality: (1/2)‖Δ‖_n² ≤ (σ/n) Σ wᵢΔᵢ
      have h2 : (1 / 2) * norm_Δ^2 ≤ 2 * norm_Δ * u := by
        calc (1 / 2) * norm_Δ^2
            = (1 / 2) * (empiricalNorm n (fun i => f_hat w (M.x i) - M.f_star (M.x i)))^2 := by
              simp only [hnorm_def, hΔ_def]
          _ ≤ M.σ / ↑n * ∑ i : Fin n, w i * (f_hat w (M.x i) - M.f_star (M.x i)) := h_basic
          _ ≤ 2 * norm_Δ * u := h1

      -- Simplify: ‖Δ‖_n² ≤ 4‖Δ‖_n u, so ‖Δ‖_n ≤ 4u (since ‖Δ‖_n > 0)
      have h3 : norm_Δ ≤ 4 * u := by
        have h := mul_le_mul_of_nonneg_left h2 (by norm_num : (0 : ℝ) ≤ 2)
        simp only [mul_assoc] at h
        have h' : norm_Δ^2 ≤ 4 * norm_Δ * u := by linarith
        have h'' : norm_Δ^2 = norm_Δ * norm_Δ := sq norm_Δ
        rw [h''] at h'
        have h''' : norm_Δ * norm_Δ ≤ 4 * u * norm_Δ := by linarith
        have h4 := le_of_mul_le_mul_right h''' h_norm_pos
        linarith

      -- Final bound: ‖Δ‖_n² ≤ 16 u² = 16 tδ*
      calc norm_Δ^2 ≤ (4 * u)^2 := sq_le_sq' (by linarith [empiricalNorm_nonneg n Δ]) h3
        _ = 16 * u^2 := by ring
        _ = 16 * (t * δ_star) := by rw [Real.sq_sqrt (le_of_lt htδ_pos)]
        _ = 16 * t * δ_star := by ring

  -- Probability bound
  have h_prob : (stdGaussianPi n (goodEvent n M.σ H t δ_star M.x)).toReal ≥
      1 - exp (-n * t * δ_star / (2 * M.σ^2)) := by
    haveI : IsProbabilityMeasure (stdGaussianPi n) := stdGaussianPi_isProbabilityMeasure
    -- Good event is complement of bad event
    have h_good_bad : goodEvent n M.σ H t δ_star M.x = (badEvent n M.σ H u M.x)ᶜ := rfl
    -- P(good) = 1 - P(bad) for any set (using ENNReal arithmetic)
    have h_compl : (stdGaussianPi n (goodEvent n M.σ H t δ_star M.x)).toReal ≥
        1 - (stdGaussianPi n (badEvent n M.σ H u M.x)).toReal := by
      rw [h_good_bad]
      have h_le_one : stdGaussianPi n (badEvent n M.σ H u M.x) ≤ 1 := prob_le_one
      have h_bad_ne_top : stdGaussianPi n (badEvent n M.σ H u M.x) ≠ ⊤ :=
        measure_ne_top _ _
      -- μ(Aᶜ) ≥ 1 - μ(A) is equivalent to μ(A) + μ(Aᶜ) ≥ 1
      have h_add : stdGaussianPi n (badEvent n M.σ H u M.x ∪ (badEvent n M.σ H u M.x)ᶜ) ≤
          stdGaussianPi n (badEvent n M.σ H u M.x) + stdGaussianPi n (badEvent n M.σ H u M.x)ᶜ :=
        measure_union_le _ _
      have h_univ : Set.univ ⊆ (badEvent n M.σ H u M.x) ∪ (badEvent n M.σ H u M.x)ᶜ := by
        intro x _
        simp only [Set.mem_union, Set.mem_compl_iff]
        exact Classical.em _
      have h_ge_one : 1 ≤ stdGaussianPi n (badEvent n M.σ H u M.x) +
          stdGaussianPi n (badEvent n M.σ H u M.x)ᶜ :=
        le_trans (le_trans (le_of_eq measure_univ.symm) (measure_mono h_univ)) h_add
      -- Convert to toReal
      have h_compl_ne_top : stdGaussianPi n (badEvent n M.σ H u M.x)ᶜ ≠ ⊤ :=
        measure_ne_top _ _
      rw [ge_iff_le, sub_le_iff_le_add, add_comm, ← ENNReal.toReal_add h_bad_ne_top h_compl_ne_top]
      exact ENNReal.toReal_mono (ENNReal.add_ne_top.mpr ⟨h_bad_ne_top, h_compl_ne_top⟩) h_ge_one
    calc (stdGaussianPi n (goodEvent n M.σ H t δ_star M.x)).toReal
        ≥ 1 - (stdGaussianPi n (badEvent n M.σ H u M.x)).toReal := h_compl
      _ ≥ 1 - exp (-n * t * δ_star / (2 * M.σ^2)) := by
        have h := h_bad
        rw [hu_def, h_exp_eq] at h
        linarith

  calc (stdGaussianPi n {w | (empiricalNorm n (fun i => f_hat w (M.x i) - M.f_star (M.x i)))^2 ≤
        16 * t * δ_star}).toReal
      ≥ (stdGaussianPi n (goodEvent n M.σ H t δ_star M.x)).toReal := by
        apply ENNReal.toReal_mono (measure_ne_top _ _)
        exact measure_mono h_good_implies
    _ ≥ 1 - exp (-n * t * δ_star / (2 * M.σ^2)) := h_prob

end LeastSquares

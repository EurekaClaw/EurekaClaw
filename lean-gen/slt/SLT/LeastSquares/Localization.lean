/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.LeastSquares.Defs

/-!
# Localization and Gaussian Complexity Monotonicity

This file establishes that the Gaussian complexity ratio G_n(δ)/δ is non-increasing
for star-shaped hypothesis classes H.

## Main Results

* `gaussian_complexity_monotone` - For star-shaped H, G_n(t)/t ≤ G_n(δ)/δ when δ ≤ t

## Key Lemmas

* `IsStarShaped.smul_mem` - Star-shaped sets are closed under scaling by [0,1]
* `empiricalNorm_smul_of_nonneg` - Empirical norm scales: ‖α • h‖_n = α * ‖h‖_n for α ≥ 0
* `localizedBall_smul_mem` - Scaling maps B_n(t) into B_n(δ) when δ ≤ t

-/

open MeasureTheory Finset BigOperators Real GaussianMeasure

namespace LeastSquares

variable {n : ℕ} {X : Type*}

/-!
## Star-Shaped Set Properties

These lemmas establish that star-shaped sets are closed under scaling.
-/

/-- For star-shaped H, h ∈ H and α ∈ [0,1] implies α • h ∈ H -/
lemma IsStarShaped.smul_mem {H : Set (X → ℝ)} (hH : IsStarShaped H)
    {h : X → ℝ} (hh : h ∈ H) {α : ℝ} (hα0 : 0 ≤ α) (hα1 : α ≤ 1) :
    α • h ∈ H :=
  hH.2 h hh α hα0 hα1

/-- Zero is in any star-shaped set -/
lemma IsStarShaped.zero_mem {H : Set (X → ℝ)} (hH : IsStarShaped H) :
    (0 : X → ℝ) ∈ H :=
  hH.1

/-!
## Ratio Properties

For 0 < δ ≤ t, the ratio δ/t is in (0, 1].
-/

/-- For 0 < δ ≤ t, we have 0 < δ/t -/
lemma ratio_pos {δ t : ℝ} (hδ : 0 < δ) (ht : 0 < t) : 0 < δ / t :=
  div_pos hδ ht

/-- For 0 < δ ≤ t, we have 0 ≤ δ/t -/
lemma ratio_nonneg {δ t : ℝ} (hδ : 0 < δ) (ht : 0 < t) : 0 ≤ δ / t :=
  le_of_lt (ratio_pos hδ ht)

/-- For 0 < δ ≤ t, we have δ/t ≤ 1 -/
lemma ratio_le_one {δ t : ℝ} (hδt : δ ≤ t) (ht : 0 < t) : δ / t ≤ 1 :=
  div_le_one_of_le₀ hδt (le_of_lt ht)

/-!
## Empirical Norm Scaling

The empirical norm scales linearly for non-negative scalars.
-/

/-- For α ≥ 0, ‖α • h‖_n = α * ‖h‖_n -/
lemma empiricalNorm_smul_of_nonneg {f : Fin n → ℝ} {α : ℝ} (hα : 0 ≤ α) :
    empiricalNorm n (α • f) = α * empiricalNorm n f := by
  unfold empiricalNorm
  simp only [Pi.smul_apply, smul_eq_mul]
  have h1 : ∀ i, (α * f i) ^ 2 = α ^ 2 * f i ^ 2 := fun i => by ring
  simp only [h1]
  rw [← Finset.mul_sum]
  -- Goal: √(n⁻¹ * (α² * Σf²)) = α * √(n⁻¹ * Σf²)
  have h2 : (n : ℝ)⁻¹ * (α ^ 2 * ∑ i : Fin n, f i ^ 2) = α ^ 2 * ((n : ℝ)⁻¹ * ∑ i : Fin n, f i ^ 2) := by
    ring
  rw [h2]
  rw [Real.sqrt_mul (sq_nonneg α)]
  rw [Real.sqrt_sq hα]

/-!
## Localized Ball Scaling

Scaling by δ/t maps B_n(t; H) into B_n(δ; H) for star-shaped H.
-/

/-- For star-shaped H, h ∈ H, and 0 < δ ≤ t: (δ/t) • h ∈ H -/
lemma IsStarShaped.smul_ratio_mem {H : Set (X → ℝ)} (hH : IsStarShaped H)
    {h : X → ℝ} (hh : h ∈ H) {δ t : ℝ} (hδ : 0 < δ) (ht : 0 < t) (hδt : δ ≤ t) :
    (δ / t) • h ∈ H :=
  hH.smul_mem hh (ratio_nonneg hδ ht) (ratio_le_one hδt ht)

/-- Scaled norm bound -/
lemma smul_ratio_empiricalNorm_le {f : Fin n → ℝ} {δ t : ℝ}
    (hδ : 0 < δ) (ht : 0 < t)
    (hf : empiricalNorm n f ≤ t) :
    empiricalNorm n ((δ / t) • f) ≤ δ := by
  rw [empiricalNorm_smul_of_nonneg (ratio_nonneg hδ ht)]
  calc (δ / t) * empiricalNorm n f
      ≤ (δ / t) * t := by apply mul_le_mul_of_nonneg_left hf (ratio_nonneg hδ ht)
    _ = δ := div_mul_cancel₀ δ (ne_of_gt ht)

/-- Scaling maps localized ball B_n(t) into B_n(δ) -/
lemma localizedBall_smul_mem {H : Set (X → ℝ)} (hH : IsStarShaped H)
    {x : Fin n → X} {h : X → ℝ} {δ t : ℝ}
    (hδ : 0 < δ) (ht : 0 < t) (hδt : δ ≤ t)
    (hh : h ∈ localizedBall H t x) :
    (δ / t) • h ∈ localizedBall H δ x := by
  constructor
  · exact hH.smul_ratio_mem hh.1 hδ ht hδt
  · have h_eval : ∀ i, ((δ / t) • h) (x i) = (δ / t) * h (x i) := fun i => rfl
    simp only [h_eval]
    have h_smul : (fun i => (δ / t) * h (x i)) = (δ / t) • (fun i => h (x i)) := rfl
    rw [h_smul]
    exact smul_ratio_empiricalNorm_le hδ ht hh.2

/-!
## Process Scaling

Scaling properties for the empirical process.
-/

/-- Process scaling identity -/
lemma process_smul_eq {w : Fin n → ℝ} {h : X → ℝ} {x : Fin n → X} {α : ℝ} :
    α * ((n : ℝ)⁻¹ * ∑ i, w i * h (x i)) =
    (n : ℝ)⁻¹ * ∑ i, w i * (α • h) (x i) := by
  simp only [Pi.smul_apply, smul_eq_mul]
  -- Goal: α * (n⁻¹ * Σ wᵢh(xᵢ)) = n⁻¹ * Σ wᵢ(α * h(xᵢ))
  have h1 : ∀ i, w i * (α * h (x i)) = α * (w i * h (x i)) := fun i => by ring
  simp only [h1]
  rw [← Finset.mul_sum]
  ring

/-- Absolute value scaling for non-negative -/
lemma abs_smul_of_nonneg {α x : ℝ} (hα : 0 ≤ α) :
    |α * x| = α * |x| := by
  rw [abs_mul, abs_of_nonneg hα]

/-!
## Supremum Scaling Lemmas

Key lemmas for the monotonicity proof.
-/

/-- The zero function is in the localized ball for any positive radius -/
lemma zero_mem_localizedBall {H : Set (X → ℝ)} (hH : IsStarShaped H)
    {δ : ℝ} (hδ : 0 < δ) {x : Fin n → X} :
    (0 : X → ℝ) ∈ localizedBall H δ x := by
  constructor
  · exact hH.zero_mem
  · unfold empiricalNorm
    simp only [Pi.zero_apply, sq, mul_zero, Finset.sum_const_zero, mul_zero, Real.sqrt_zero]
    exact le_of_lt hδ

/-- The localized ball is nonempty for star-shaped H and positive radius -/
lemma localizedBall_nonempty {H : Set (X → ℝ)} (hH : IsStarShaped H)
    {δ : ℝ} (hδ : 0 < δ) {x : Fin n → X} :
    (localizedBall H δ x).Nonempty :=
  ⟨0, zero_mem_localizedBall hH hδ⟩

/-- Localized balls are monotone in radius: B_n(δ; H) ⊆ B_n(t; H) when δ ≤ t -/
lemma localizedBall_mono {H : Set (X → ℝ)} {δ t : ℝ} (hδt : δ ≤ t) {x : Fin n → X} :
    localizedBall H δ x ⊆ localizedBall H t x := by
  intro _ hh
  exact ⟨hh.1, le_trans hh.2 hδt⟩

/-- The empirical process at zero is zero -/
lemma process_at_zero {w : Fin n → ℝ} {x : Fin n → X} :
    (n : ℝ)⁻¹ * ∑ i, w i * (0 : X → ℝ) (x i) = 0 := by
  simp only [Pi.zero_apply, mul_zero, Finset.sum_const_zero, mul_zero]

/-- Scaled supremum bound (pointwise in w).

For any w, the scaled supremum over B_n(t;H) is bounded by the supremum over B_n(δ;H).

Key idea: For each h ∈ B_n(t;H), the scaled function g = (δ/t)•h ∈ B_n(δ;H),
and (δ/t) * |process(h)| = |process(g)| ≤ sup over B_n(δ). -/
lemma scaled_biSup_le {H : Set (X → ℝ)} (hH : IsStarShaped H)
    {x : Fin n → X} {w : Fin n → ℝ} {δ t : ℝ}
    (hδ : 0 < δ) (ht : 0 < t) (hδt : δ ≤ t)
    (hbdd : BddAbove {y | ∃ h ∈ localizedBall H t x, y = |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|}) :
    (δ / t) * (⨆ h ∈ localizedBall H t x, |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|) ≤
    ⨆ g ∈ localizedBall H δ x, |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)| := by
  have hr_nonneg : 0 ≤ δ / t := le_of_lt (div_pos hδ ht)

  -- The RHS is always non-negative (supremum of absolute values)
  have hRHS_nonneg : 0 ≤ ⨆ g ∈ localizedBall H δ x, |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)| := by
    apply Real.iSup_nonneg
    intro g
    apply Real.iSup_nonneg
    intro _
    exact abs_nonneg _

  -- If the t-ball is empty, the LHS is 0 ≤ RHS
  by_cases hne_t : (localizedBall H t x).Nonempty
  swap
  · simp only [Set.not_nonempty_iff_eq_empty] at hne_t
    rw [hne_t]
    simp only [Set.mem_empty_iff_false]
    -- ⨆ h, ⨆ (_ : False), f h = ⨆ h, 0 = 0 (since iSup_false gives 0 for ℝ)
    have h_inner_zero : ∀ h : X → ℝ, (⨆ _ : False, |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|) = 0 := by
      intro h
      simp only [iSup_of_empty']
      exact Real.sSup_empty
    simp only [h_inner_zero, ciSup_const, mul_zero]
    exact hRHS_nonneg

  -- For each h ∈ B_n(t), (δ/t) * |process(h)| = |process((δ/t)•h)| where (δ/t)•h ∈ B_n(δ)
  have h_each_bounded : ∀ h ∈ localizedBall H t x,
      (δ / t) * |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)| ≤
      ⨆ g ∈ localizedBall H δ x, |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)| := by
    intro h hh
    set g := (δ / t) • h with hg_def
    have hg_mem : g ∈ localizedBall H δ x := localizedBall_smul_mem hH hδ ht hδt hh
    -- (δ/t) * |process(h)| = |process(g)|
    have h_eq : (δ / t) * |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)| =
        |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)| := by
      rw [← abs_smul_of_nonneg hr_nonneg]
      congr 1
      simp only [hg_def, Pi.smul_apply, smul_eq_mul]
      have h1 : ∀ i, w i * ((δ / t) * h (x i)) = (δ / t) * (w i * h (x i)) := fun i => by ring
      simp only [h1]
      rw [← Finset.mul_sum]
      ring
    rw [h_eq]
    -- Need to show |process(g)| ≤ sup over B_n(δ)
    -- Since g ∈ B_n(δ), this follows from le_ciSup
    have hbdd_δ : BddAbove (Set.range fun (g : X → ℝ) =>
        ⨆ (_ : g ∈ localizedBall H δ x), |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)|) := by
      obtain ⟨M, hM⟩ := hbdd
      -- First, show M ≥ 0 from the fact that 0 is in the t-ball
      have hM_nonneg : 0 ≤ M := by
        have h0_mem : (0 : X → ℝ) ∈ localizedBall H t x := zero_mem_localizedBall hH ht
        have h0_val : |(n : ℝ)⁻¹ * ∑ i, w i * (0 : X → ℝ) (x i)| = 0 := by
          simp only [Pi.zero_apply, mul_zero, Finset.sum_const_zero, mul_zero, abs_zero]
        have h0_in : (0 : ℝ) ∈ {y | ∃ h ∈ localizedBall H t x, y = |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|} := by
          exact ⟨0, h0_mem, h0_val.symm⟩
        exact le_trans (le_refl 0) (hM h0_in)
      use M  -- Same bound works since localizedBall δ ⊆ localizedBall t
      intro y hy
      obtain ⟨g', rfl⟩ := hy
      by_cases hg'_mem : g' ∈ localizedBall H δ x
      · simp only [hg'_mem]
        -- g' ∈ B_n(δ) ⊆ B_n(t), so the bound M applies
        have hg'_in_t : g' ∈ localizedBall H t x := localizedBall_mono hδt hg'_mem
        have := hM ⟨g', hg'_in_t, rfl⟩
        -- Need to show ⨆ (_ : True), |...| ≤ M from `this : |...| ≤ M`
        apply ciSup_le
        intro _
        exact this
      · simp only [hg'_mem]
        -- Need to show ⨆ (_ : False), |...| ≤ M. This equals 0 ≤ M
        have h_zero : (⨆ _ : False, |(n : ℝ)⁻¹ * ∑ i, w i * g' (x i)|) = 0 := by
          simp only [iSup_of_empty']
          exact Real.sSup_empty
        rw [h_zero]
        exact hM_nonneg
    apply le_ciSup_of_le hbdd_δ g
    -- Need to show |process(g)| ≤ ⨆ (_ : g ∈ localizedBall H δ x), |process(g)|
    -- Since g ∈ localizedBall H δ x, this is True, and we need x ≤ ⨆ (_ : True), x
    have hbdd_inner : BddAbove (Set.range fun _ : g ∈ localizedBall H δ x =>
        |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)|) := by
      use |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)|
      intro y hy
      obtain ⟨_, rfl⟩ := hy
      exact le_refl _
    exact le_ciSup_of_le hbdd_inner hg_mem (le_refl _)

  -- The biSup ⨆ h ∈ S, f h is the same as ⨆ h, ⨆ (_ : h ∈ S), f h
  -- We use Real.iSup_mul_of_nonneg to distribute multiplication, then ciSup_le

  -- Step 1: Use Real.iSup_mul_of_nonneg to distribute multiplication
  -- Goal: (δ/t) * (⨆ h ∈ B_t, f h) ≤ (⨆ g ∈ B_δ, f g)
  -- After mul_comm: (⨆ h ∈ B_t, f h) * (δ/t) ≤ ...
  -- Use Real.iSup_mul_of_nonneg: (⨆ i, f i) * r = ⨆ i, f i * r
  rw [mul_comm, Real.iSup_mul_of_nonneg hr_nonneg]

  -- Step 2: Apply ciSup_le (need Nonempty)
  haveI : Nonempty (X → ℝ) := ⟨0⟩
  apply ciSup_le
  intro h
  rw [Real.iSup_mul_of_nonneg hr_nonneg]
  -- Handle the inner iSup over the proposition (h ∈ localizedBall H t x)
  by_cases hh : h ∈ localizedBall H t x
  · -- If h ∈ B_n(t), use h_each_bounded
    -- The iSup over (h ∈ B_t) when h ∈ B_t is bounded by the value times h_each_bounded
    have hbdd_inner : BddAbove (Set.range fun _ : h ∈ localizedBall H t x =>
        |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)| * (δ / t)) := by
      use |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)| * (δ / t)
      intro y hy
      obtain ⟨_, rfl⟩ := hy
      exact le_refl _
    -- Show iSup ≤ the value at hh
    have h_eq : (⨆ _ : h ∈ localizedBall H t x, |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)| * (δ / t)) =
        |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)| * (δ / t) := by
      apply le_antisymm
      · haveI : Nonempty (h ∈ localizedBall H t x) := ⟨hh⟩
        apply ciSup_le
        intro _
        exact le_refl _
      · exact le_ciSup_of_le hbdd_inner hh (le_refl _)
    rw [h_eq, mul_comm]
    exact h_each_bounded h hh
  · -- If h ∉ B_n(t), the inner iSup is 0 ≤ RHS
    -- Since h ∉ B_n(t), the Prop (h ∈ B_n(t)) is False, so iSup over False = 0
    have h_empty : IsEmpty (h ∈ localizedBall H t x) := by
      rw [isEmpty_Prop]
      exact hh
    have h_zero : (⨆ _ : h ∈ localizedBall H t x, |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)| * (δ / t)) = 0 := by
      simp only [iSup_of_empty']
      exact Real.sSup_empty
    rw [h_zero]
    exact hRHS_nonneg

/-!
## Main Monotonicity Theorem

The Gaussian complexity ratio G_n(δ)/δ is non-increasing for star-shaped H.
-/

/-- Gaussian complexity monotonicity.

For star-shaped H and 0 < δ ≤ t:
  G_n(t; H) / t ≤ G_n(δ; H) / δ

This says the function δ ↦ G_n(δ)/δ is non-increasing.

The proof uses:
1. scaled_biSup_le to show pointwise (δ/t) * sup_h |...| ≤ sup_g |...|
2. Integration preserves this inequality
3. Linearity of integration with scalars
-/
theorem gaussian_complexity_monotone {H : Set (X → ℝ)} (hH : IsStarShaped H)
    {x : Fin n → X} {δ t : ℝ}
    (hδ : 0 < δ) (ht : 0 < t) (hδt : δ ≤ t)
    -- Integrability hypotheses (required for measure-theoretic argument)
    (hint_t : Integrable (fun w => ⨆ h ∈ localizedBall H t x,
        |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|) (stdGaussianPi n))
    (hint_δ : Integrable (fun w => ⨆ h ∈ localizedBall H δ x,
        |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|) (stdGaussianPi n))
    -- Boundedness hypothesis (for supremum to be well-defined)
    (hbdd : ∀ w : Fin n → ℝ, BddAbove {y | ∃ h ∈ localizedBall H t x,
        y = |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|}) :
    LocalGaussianComplexity n H t x / t ≤ LocalGaussianComplexity n H δ x / δ := by
  unfold LocalGaussianComplexity
  rw [div_le_div_iff₀ ht hδ]

  -- Goal: (∫ sup_t) * δ ≤ (∫ sup_δ) * t
  -- Equivalently: (δ/t) * ∫ sup_t ≤ ∫ sup_δ

  -- Rewrite LHS using scalar multiplication
  have h_lhs : (∫ w, ⨆ h ∈ localizedBall H t x, |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|
      ∂(stdGaussianPi n)) * δ =
      t * ((δ / t) * ∫ w, ⨆ h ∈ localizedBall H t x, |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|
      ∂(stdGaussianPi n)) := by
    field_simp

  rw [h_lhs]

  -- Rewrite RHS to have t on the left: (∫ sup_δ) * t = t * (∫ sup_δ)
  rw [mul_comm (∫ w, ⨆ h ∈ localizedBall H δ x, |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)| ∂(stdGaussianPi n)) t]

  -- It suffices to show (δ/t) * ∫ sup_t ≤ ∫ sup_δ, then multiply by t
  apply mul_le_mul_of_nonneg_left _ (le_of_lt ht)

  -- Pull scalar into the integral: c * ∫ f = ∫ c • f
  have h_smul_eq : δ / t * (∫ w, ⨆ h ∈ localizedBall H t x, |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|
      ∂(stdGaussianPi n)) =
      ∫ w, (δ / t) * (⨆ h ∈ localizedBall H t x, |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|) ∂(stdGaussianPi n) := by
    rw [← smul_eq_mul, ← integral_smul]
    simp only [smul_eq_mul]
  rw [h_smul_eq]

  -- Apply integral monotonicity
  apply integral_mono (hint_t.const_mul (δ / t)) hint_δ
  intro w

  -- Apply pointwise bound
  exact scaled_biSup_le hH hδ ht hδt (hbdd w)

end LeastSquares

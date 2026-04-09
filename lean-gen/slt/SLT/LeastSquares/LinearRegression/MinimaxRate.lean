/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.LeastSquares.MasterErrorBound
import SLT.LeastSquares.LinearRegression.GaussianComplexity
import SLT.LeastSquares.DudleyApplication

/-!
# Minimax Rate for Linear Regression

This file establishes the minimax optimal rate O(σ² d / n) for d-dimensional linear regression
with n samples under the least squares framework.

## Main Results

* `linear_minimax_rate` - With probability ≥ 1 - exp(-C₂·d), the squared L²-error satisfies:
    ‖f̂ - f*‖²_n ≤ C₁ · σ² · d / n

## Key Lemmas

* `linear_shiftedClass_isStarShaped` - The shifted linear predictor class is star-shaped
* `linear_critical_inequality` - Critical inequality G_n(δ)/δ ≤ δ/(2σ) at δ_star
* `linear_empiricalSphere_nonempty` - Empirical sphere at positive radius is nonempty
* `linear_integrable_at_radius` - Integrability of supremum empirical process
* `linear_bddAbove_at_radius` - Boundedness of empirical process values

## Mathematical Background

From `linear_local_gaussian_complexity_bound`:
  G_n(δ) ≤ (96 · √2) · δ · √d / √n

The critical inequality G_n(δ)/δ ≤ δ/(2σ) is satisfied when:
  δ_star = 192 · √2 · σ · √d / √n

Substituting into the master error bound:
  ‖f̂ - f*‖²_n ≤ 16 · δ_star² = O(σ² · d / n)

-/

open MeasureTheory Finset BigOperators Real ProbabilityTheory GaussianMeasure

namespace LeastSquares

variable {n d : ℕ}

/-! ### Helper Lemmas -/

/-- For f_star ∈ linearPredictorClass d, the shifted class is star-shaped.
This follows because the shifted class equals the original for linear predictors. -/
lemma linear_shiftedClass_isStarShaped {f_star : EuclideanSpace ℝ (Fin d) → ℝ}
    (hf_star : f_star ∈ linearPredictorClass d) :
    IsStarShaped (shiftedClass (linearPredictorClass d) f_star) := by
  rw [shiftedClass_eq_self_of_linear hf_star]
  exact linearPredictorClass_isStarShaped

/-- The constant C₁ = 96 * √2 from the local Gaussian complexity bound -/
noncomputable def linear_C1 : ℝ := 96 * Real.sqrt 2

/-- The critical radius δ_star = 2σ * C₁ * √d / √n = 192√2 * σ * √d / √n -/
noncomputable def linear_δ_star (σ : ℝ) (d n : ℕ) : ℝ :=
  2 * σ * linear_C1 * Real.sqrt d / Real.sqrt n

lemma linear_δ_star_eq (σ : ℝ) (d n : ℕ) :
    linear_δ_star σ d n = 192 * Real.sqrt 2 * σ * Real.sqrt d / Real.sqrt n := by
  unfold linear_δ_star linear_C1
  ring

/-- The critical radius is positive when σ > 0, d > 0, n > 0 -/
lemma linear_δ_star_pos {σ : ℝ} (hσ : 0 < σ) (hd : 0 < d) (hn : 0 < n) :
    0 < linear_δ_star σ d n := by
  unfold linear_δ_star linear_C1
  positivity

/-- The critical inequality is satisfied at δ_star for linear predictors.

From linear_local_gaussian_complexity_bound:
  G_n(δ) ≤ (96 · √2) · δ · √d / √n = C₁ · δ · √d / √n

We need G_n(δ)/δ ≤ δ/(2σ), i.e., C₁ · √d / √n ≤ δ/(2σ)
Solving: δ ≥ 2σ · C₁ · √d / √n = δ_star -/
lemma linear_critical_inequality (hn : 0 < n) (hd : 0 < d)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) (σ : ℝ) (hσ : 0 < σ)
    (hinj : Function.Injective (designMatrixMul x))
    {f_star : EuclideanSpace ℝ (Fin d) → ℝ} (hf_star : f_star ∈ linearPredictorClass d) :
    satisfiesCriticalInequality n σ (linear_δ_star σ d n)
      (shiftedClass (linearPredictorClass d) f_star) x := by
  -- Use shiftedClass_eq_self_of_linear to simplify
  rw [shiftedClass_eq_self_of_linear hf_star]
  -- Unfold the critical inequality
  unfold satisfiesCriticalInequality
  -- Get the local Gaussian complexity bound
  have h_bound := linear_local_gaussian_complexity_bound n d hn hd x
    (linear_δ_star_pos hσ hd hn) hinj
  -- Setup positivity facts
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have hsqrtn : 0 < Real.sqrt n := Real.sqrt_pos.mpr hn_pos
  have hδ_pos := linear_δ_star_pos hσ hd hn
  have hδ_ne : linear_δ_star σ d n ≠ 0 := ne_of_gt hδ_pos
  have hσ_ne : σ ≠ 0 := ne_of_gt hσ
  have hsqrtn_ne : Real.sqrt n ≠ 0 := ne_of_gt hsqrtn
  -- LHS: G_n(δ_star) / δ_star ≤ C₁ * √d / √n
  have h_lhs : LocalGaussianComplexity n (linearPredictorClass d) (linear_δ_star σ d n) x /
      (linear_δ_star σ d n) ≤ linear_C1 * Real.sqrt d / Real.sqrt n := by
    calc LocalGaussianComplexity n (linearPredictorClass d) (linear_δ_star σ d n) x /
          (linear_δ_star σ d n)
        ≤ ((96 * Real.sqrt 2) * (linear_δ_star σ d n) * Real.sqrt d / Real.sqrt n) /
            (linear_δ_star σ d n) := by
          apply div_le_div_of_nonneg_right h_bound (le_of_lt hδ_pos)
      _ = (96 * Real.sqrt 2) * Real.sqrt d / Real.sqrt n := by
          field_simp
      _ = linear_C1 * Real.sqrt d / Real.sqrt n := rfl
  -- RHS: δ_star / (2σ) = C₁ * √d / √n
  have h_rhs : linear_δ_star σ d n / (2 * σ) = linear_C1 * Real.sqrt d / Real.sqrt n := by
    unfold linear_δ_star
    field_simp
  -- Combine
  calc LocalGaussianComplexity n (linearPredictorClass d) (linear_δ_star σ d n) x /
        (linear_δ_star σ d n)
      ≤ linear_C1 * Real.sqrt d / Real.sqrt n := h_lhs
    _ = linear_δ_star σ d n / (2 * σ) := h_rhs.symm

/-- The localized ball at any positive radius contains the zero function for linear predictors. -/
lemma linear_localizedBall_nonempty {δ : ℝ} (hδ : 0 ≤ δ)
    (x : Fin n → EuclideanSpace ℝ (Fin d))
    {f_star : EuclideanSpace ℝ (Fin d) → ℝ} (hf_star : f_star ∈ linearPredictorClass d) :
    (localizedBall (shiftedClass (linearPredictorClass d) f_star) δ x).Nonempty := by
  rw [shiftedClass_eq_self_of_linear hf_star]
  use 0
  constructor
  · exact zero_mem_linearPredictorClass
  · -- Need to show empiricalNorm n (fun i => 0 (x i)) ≤ δ
    -- Since 0 is the zero function, 0 (x i) = 0 for all i
    have h_eq : (fun i => (0 : EuclideanSpace ℝ (Fin d) → ℝ) (x i)) = (fun _ => (0 : ℝ)) := by
      ext i; rfl
    rw [h_eq]
    have h_zero : empiricalNorm n (fun _ : Fin n => (0 : ℝ)) = 0 := by
      unfold empiricalNorm
      simp only [sq, mul_zero, sum_const_zero, mul_zero, Real.sqrt_zero]
    rw [h_zero]
    exact hδ

/-- Scaling lemma: if θ achieves empirical norm r, then c•θ achieves empirical norm |c|*r. -/
lemma empiricalNorm_smul_linear
    (x : Fin n → EuclideanSpace ℝ (Fin d)) (θ : EuclideanSpace ℝ (Fin d))
    {c : ℝ} (hc : 0 ≤ c) :
    empiricalNorm n (fun i => c * @inner ℝ _ _ θ (x i)) =
    c * empiricalNorm n (fun i => @inner ℝ _ _ θ (x i)) := by
  unfold empiricalNorm
  have h_sq : ∀ i, (c * @inner ℝ _ _ θ (x i))^2 = c^2 * (@inner ℝ _ _ θ (x i))^2 := by
    intro i; ring
  simp_rw [h_sq]
  rw [← Finset.mul_sum]
  -- Goal: √(n⁻¹ * (c² * ∑ i, inner θ (x i)²)) = c * √(n⁻¹ * ∑ i, inner θ (x i)²)
  have h_assoc : (n : ℝ)⁻¹ * (c^2 * ∑ i : Fin n, (@inner ℝ _ _ θ (x i))^2) =
      c^2 * ((n : ℝ)⁻¹ * ∑ i : Fin n, (@inner ℝ _ _ θ (x i))^2) := by ring
  rw [h_assoc]
  rw [Real.sqrt_mul (sq_nonneg c)]
  rw [Real.sqrt_sq hc]

/-- The empirical sphere at any positive radius is nonempty for linear predictors
    when the design matrix is injective. -/
lemma linear_empiricalSphere_nonempty (hn : 0 < n) (hd : 0 < d)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {u : ℝ} (hu : 0 < u)
    (hinj : Function.Injective (designMatrixMul x))
    {f_star : EuclideanSpace ℝ (Fin d) → ℝ} (hf_star : f_star ∈ linearPredictorClass d) :
    (empiricalSphere n (shiftedClass (linearPredictorClass d) f_star) u x).Nonempty := by
  rw [shiftedClass_eq_self_of_linear hf_star]
  -- We need to find θ such that empiricalNorm(⟨θ,·⟩) = u
  -- Strategy: Find any θ₀ with nonzero empirical norm, then scale
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  -- Get a nonzero vector: the first standard basis vector
  let j₀ : Fin d := ⟨0, hd⟩
  let e₀ : EuclideanSpace ℝ (Fin d) := EuclideanSpace.single j₀ 1
  have he₀_ne : e₀ ≠ 0 := by
    intro h
    rw [EuclideanSpace.single_eq_zero_iff] at h
    exact one_ne_zero h
  -- Since hinj is injective, designMatrixMul x e₀ ≠ 0
  have hXe₀_ne : designMatrixMul x e₀ ≠ 0 := by
    intro h
    apply he₀_ne
    have h0 : designMatrixMul x 0 = 0 := by
      have : (0 : EuclideanSpace ℝ (Fin d)) = (0 : ℝ) • e₀ := by simp
      rw [this, designMatrixMul_smul, zero_smul]
    exact hinj (h.trans h0.symm)
  -- Thus ‖designMatrixMul x e₀‖ > 0
  have hXe₀_norm_pos : 0 < ‖designMatrixMul x e₀‖ := norm_pos_iff.mpr hXe₀_ne
  -- The linear function has positive empirical norm
  have h_emp_norm_pos : 0 < empiricalNorm n (fun i => @inner ℝ _ _ e₀ (x i)) := by
    rw [empiricalNorm_linear x e₀]
    apply mul_pos
    · exact Real.sqrt_pos.mpr (inv_pos.mpr hn_pos)
    · exact hXe₀_norm_pos
  -- Scale to get exact norm u
  let r := empiricalNorm n (fun i => @inner ℝ _ _ e₀ (x i))
  let c := u / r
  have hc_pos : 0 < c := div_pos hu h_emp_norm_pos
  let θ := c • e₀
  -- The function f(z) = ⟨θ, z⟩ is in linearPredictorClass
  use fun z => @inner ℝ _ _ θ z
  constructor
  · -- f ∈ linearPredictorClass d
    have he₀_mem : (fun z => @inner ℝ _ _ e₀ z) ∈ linearPredictorClass d := ⟨e₀, rfl⟩
    have h_smul : (fun z => @inner ℝ _ _ θ z) = c • (fun z => @inner ℝ _ _ e₀ z) := by
      ext z
      simp only [θ, Pi.smul_apply, smul_eq_mul, inner_smul_left, RCLike.conj_to_real]
    rw [h_smul]
    exact smul_mem_linearPredictorClass he₀_mem
  · -- empiricalNorm = u
    show empiricalNorm n (fun i => @inner ℝ _ _ θ (x i)) = u
    have h_inner_smul : ∀ z, @inner ℝ _ _ θ z = c * @inner ℝ _ _ e₀ z := by
      intro z
      simp only [θ, inner_smul_left, RCLike.conj_to_real]
    simp_rw [h_inner_smul]
    rw [empiricalNorm_smul_linear x e₀ (le_of_lt hc_pos)]
    simp only [c, r]
    rw [div_mul_cancel₀]
    exact ne_of_gt h_emp_norm_pos

/-- Integrability of the absolute supremum empirical process at positive radius for linear predictors.
This uses the general `localGaussianComplexity_integrand_integrable` lemma for star-shaped sets. -/
lemma linear_integrable_at_radius
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ : ℝ} (hδ : 0 < δ)
    {f_star : EuclideanSpace ℝ (Fin d) → ℝ} (hf_star : f_star ∈ linearPredictorClass d) :
    Integrable (fun w => ⨆ h ∈ localizedBall (shiftedClass (linearPredictorClass d) f_star) δ x,
      |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|) (stdGaussianPi n) := by
  rw [shiftedClass_eq_self_of_linear hf_star]
  exact localGaussianComplexity_integrand_integrable n (linearPredictorClass d) δ hδ x

/-- Boundedness of empirical process values at any positive radius for linear predictors.
The bound follows from Cauchy-Schwarz: the empirical process is bounded by ‖w‖ · u. -/
lemma linear_bddAbove_at_radius (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {u : ℝ} (hu : 0 < u)
    {f_star : EuclideanSpace ℝ (Fin d) → ℝ} (hf_star : f_star ∈ linearPredictorClass d) :
    ∀ w : Fin n → ℝ, BddAbove {y | ∃ h ∈ localizedBall (shiftedClass (linearPredictorClass d) f_star) u x,
      y = |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|} := by
  rw [shiftedClass_eq_self_of_linear hf_star]
  intro w
  -- Bound: |n⁻¹ ∑ w_i h(x_i)| ≤ n⁻¹ · ‖w‖₂ · ‖(h(x_i))‖₂ ≤ n⁻¹ · ‖w‖₂ · √n · u
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  -- Interpret w as EuclideanSpace for Cauchy-Schwarz
  let w' : EuclideanSpace ℝ (Fin n) := (WithLp.equiv 2 (Fin n → ℝ)).symm w
  use (n : ℝ)⁻¹ * Real.sqrt n * ‖w'‖ * u
  intro y hy
  obtain ⟨h, ⟨_, hh_norm⟩, rfl⟩ := hy
  -- Interpret h(x_i) as EuclideanSpace for Cauchy-Schwarz
  let hx : EuclideanSpace ℝ (Fin n) := (WithLp.equiv 2 (Fin n → ℝ)).symm (fun i => h (x i))
  -- |n⁻¹ * ∑ w_i h(x_i)| ≤ n⁻¹ * √n * ‖w‖ * u
  have h_sum_eq : ∑ i, w i * h (x i) = @inner ℝ _ _ w' hx := by
    simp only [w', hx, EuclideanSpace.inner_eq_star_dotProduct]
    simp only [WithLp.equiv_symm_apply_ofLp]
    -- For real numbers, star w = w (trivial star)
    have h_star : star w = w := by ext i; simp [star_trivial]
    rw [h_star, dotProduct_comm]
    rfl
  have h_sum_bound : |∑ i, w i * h (x i)| ≤ Real.sqrt n * ‖w'‖ * u := by
    rw [h_sum_eq]
    calc |@inner ℝ _ _ w' hx|
        ≤ ‖w'‖ * ‖hx‖ := abs_real_inner_le_norm w' hx
      _ ≤ ‖w'‖ * (Real.sqrt n * u) := by
          apply mul_le_mul_of_nonneg_left _ (norm_nonneg w')
          -- ‖hx‖ ≤ √n · u from empiricalNorm h ≤ u
          have h_emp : empiricalNorm n (fun i => h (x i)) ≤ u := hh_norm
          unfold empiricalNorm at h_emp
          have h_hx_norm : ‖hx‖ = Real.sqrt (∑ i, (h (x i))^2) := by
            simp only [hx, EuclideanSpace.norm_eq]
            congr 1
            simp only [WithLp.equiv_symm_apply_ofLp]
            simp_rw [Real.norm_eq_abs, sq_abs]
          rw [h_hx_norm]
          have h_sqrt : Real.sqrt ((n : ℝ)⁻¹ * ∑ i, (h (x i))^2) ≤ u := h_emp
          have h_nonneg : 0 ≤ (n : ℝ)⁻¹ * ∑ i, (h (x i))^2 := by positivity
          have h_sqrt_nonneg : 0 ≤ Real.sqrt ((n : ℝ)⁻¹ * ∑ i, (h (x i))^2) := Real.sqrt_nonneg _
          have h_neg_u : -u ≤ Real.sqrt ((n : ℝ)⁻¹ * ∑ i, (h (x i))^2) := by linarith
          have h_ineq : (n : ℝ)⁻¹ * ∑ i, (h (x i))^2 ≤ u^2 := by
            calc (n : ℝ)⁻¹ * ∑ i, (h (x i))^2
                = (Real.sqrt ((n : ℝ)⁻¹ * ∑ i, (h (x i))^2))^2 := by
                  rw [Real.sq_sqrt h_nonneg]
              _ ≤ u^2 := sq_le_sq' h_neg_u h_sqrt
          have h_sum : ∑ i, (h (x i))^2 ≤ n * u^2 := by
            have hmul := mul_le_mul_of_nonneg_left h_ineq (le_of_lt hn_pos)
            have h_cancel : (n : ℝ) * ((n : ℝ)⁻¹ * ∑ i, (h (x i))^2) = ∑ i, (h (x i))^2 := by
              field_simp
            rwa [h_cancel] at hmul
          calc Real.sqrt (∑ i, (h (x i))^2)
              ≤ Real.sqrt (n * u^2) := Real.sqrt_le_sqrt h_sum
            _ = Real.sqrt n * u := by rw [Real.sqrt_mul (Nat.cast_nonneg n), Real.sqrt_sq (le_of_lt hu)]
      _ = Real.sqrt n * ‖w'‖ * u := by ring
  calc |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|
      = (n : ℝ)⁻¹ * |∑ i, w i * h (x i)| := by
        rw [abs_mul, abs_of_pos (inv_pos.mpr hn_pos)]
    _ ≤ (n : ℝ)⁻¹ * (Real.sqrt n * ‖w'‖ * u) := by
        apply mul_le_mul_of_nonneg_left h_sum_bound (le_of_lt (inv_pos.mpr hn_pos))
    _ = (n : ℝ)⁻¹ * Real.sqrt n * ‖w'‖ * u := by ring

/-! ### Main Theorem -/

/-- The error bound constant C₁ = 16 · (192√2)² for the minimax rate. -/
noncomputable def linear_C₁ : ℝ := 16 * (192 * Real.sqrt 2)^2

lemma linear_C₁_pos : 0 < linear_C₁ := by
  unfold linear_C₁
  positivity

/-- The exponent constant C₂ = (192√2)² / 2 for the probability bound. -/
noncomputable def linear_C₂ : ℝ := (192 * Real.sqrt 2)^2 / 2

lemma linear_C₂_pos : 0 < linear_C₂ := by
  unfold linear_C₂
  positivity

/-- Main theorem: Linear regression achieves the minimax optimal rate O(σ²d/n).

There exist constants C₁, C₂ > 0 such that with probability at least 1 - exp(-C₂·d),
the squared L²-error satisfies:
  ‖f̂ - f*‖²_n ≤ C₁ · σ² · d / n

This is the **minimax optimal rate** for d-dimensional linear regression with n samples. -/
theorem linear_minimax_rate (hn : 0 < n) (hd : 0 < d)
    (M : RegressionModel n (EuclideanSpace ℝ (Fin d)))
    (hf_star : M.f_star ∈ linearPredictorClass d)
    (hinj : Function.Injective (designMatrixMul M.x))
    (f_hat : (Fin n → ℝ) → (EuclideanSpace ℝ (Fin d) → ℝ))
    (hf_hat : ∀ w, isLeastSquaresEstimator (M.response w) (linearPredictorClass d) M.x (f_hat w)) :
    ∃ C₁ C₂ : ℝ, C₁ > 0 ∧ C₂ > 0 ∧
      (stdGaussianPi n {w | (empiricalNorm n (fun i => f_hat w (M.x i) - M.f_star (M.x i)))^2 ≤
          C₁ * M.σ^2 * d / n}).toReal ≥ 1 - exp (-C₂ * d) := by
  refine ⟨linear_C₁, linear_C₂, linear_C₁_pos, linear_C₂_pos, ?_⟩
  -- Define δ_star and t
  set δ_star := linear_δ_star M.σ d n with hδ_star_def
  have hδ_star_pos := linear_δ_star_pos M.hσ_pos hd hn
  -- For the main theorem, we take t = δ_star (simplest case of master error bound)
  -- Step 1: Verify all hypotheses of master_error_bound
  have hCI := linear_critical_inequality hn hd M.x M.σ M.hσ_pos hinj hf_star
  have hH_star := linear_shiftedClass_isStarShaped hf_star
  -- For t = δ_star, √(t·δ_star) = √(δ_star²) = δ_star
  have h_sqrt_eq : Real.sqrt (δ_star * δ_star) = δ_star := by
    rw [← sq]
    exact Real.sqrt_sq (le_of_lt hδ_star_pos)
  -- Nonemptiness of empirical sphere at √(δ_star²) = δ_star
  have hne : (empiricalSphere n (shiftedClass (linearPredictorClass d) M.f_star) (Real.sqrt (δ_star * δ_star)) M.x).Nonempty := by
    rw [h_sqrt_eq]
    exact linear_empiricalSphere_nonempty hn hd M.x hδ_star_pos hinj hf_star
  -- Integrability at √(t·δ_star) = δ_star
  have hint_u : Integrable (fun w => ⨆ h ∈ localizedBall (shiftedClass (linearPredictorClass d) M.f_star)
      (Real.sqrt (δ_star * δ_star)) M.x, |(n : ℝ)⁻¹ * ∑ i, w i * h (M.x i)|) (stdGaussianPi n) := by
    rw [h_sqrt_eq]
    exact linear_integrable_at_radius M.x hδ_star_pos hf_star
  -- Integrability at δ_star
  have hint_δ : Integrable (fun w => ⨆ h ∈ localizedBall (shiftedClass (linearPredictorClass d) M.f_star)
      δ_star M.x, |(n : ℝ)⁻¹ * ∑ i, w i * h (M.x i)|) (stdGaussianPi n) :=
    linear_integrable_at_radius M.x hδ_star_pos hf_star
  -- Boundedness at √(t·δ_star) = δ_star
  have hbdd : ∀ w : Fin n → ℝ, BddAbove {y | ∃ h ∈ localizedBall (shiftedClass (linearPredictorClass d) M.f_star)
      (Real.sqrt (δ_star * δ_star)) M.x, y = |(n : ℝ)⁻¹ * ∑ i, w i * h (M.x i)|} := by
    rw [h_sqrt_eq]
    exact linear_bddAbove_at_radius hn M.x hδ_star_pos hf_star
  -- Step 2: Apply master_error_bound with t = δ_star
  have h_master := master_error_bound hn M (linearPredictorClass d) hf_star δ_star hδ_star_pos
    hCI hH_star δ_star (le_refl δ_star) f_hat hf_hat hne hint_u hint_δ hbdd
  -- Step 3: Show the bound 16·δ_star² = linear_C₁ · σ² · d / n
  have h_bound_eq : 16 * δ_star * δ_star = linear_C₁ * M.σ^2 * d / n := by
    rw [hδ_star_def, linear_δ_star_eq]
    unfold linear_C₁
    have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
    have hsqrt_n_sq : Real.sqrt n ^ 2 = n := Real.sq_sqrt (Nat.cast_nonneg n)
    have hsqrt_d_sq : Real.sqrt d ^ 2 = d := Real.sq_sqrt (Nat.cast_nonneg d)
    have hn_ne : (n : ℝ) ≠ 0 := Nat.cast_ne_zero.mpr (Nat.pos_iff_ne_zero.mp hn)
    have hsqrt_n_ne : Real.sqrt n ≠ 0 := Real.sqrt_ne_zero'.mpr hn_pos
    field_simp
    -- After field_simp, simplify sqrt terms and use ring
    rw [hsqrt_d_sq, hsqrt_n_sq]
    ring
  -- Step 4: Show the exponent n·δ_star²/(2σ²) = linear_C₂ · d
  have h_exp_eq : -n * δ_star * δ_star / (2 * M.σ^2) = -linear_C₂ * d := by
    rw [hδ_star_def, linear_δ_star_eq]
    unfold linear_C₂
    have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
    have hsqrt_n_sq : Real.sqrt n ^ 2 = n := Real.sq_sqrt (Nat.cast_nonneg n)
    have hsqrt_d_sq : Real.sqrt d ^ 2 = d := Real.sq_sqrt (Nat.cast_nonneg d)
    have hsqrt_n_ne : Real.sqrt n ≠ 0 := Real.sqrt_ne_zero'.mpr hn_pos
    have hσ_ne : M.σ ≠ 0 := ne_of_gt M.hσ_pos
    field_simp
    -- After field_simp, simplify sqrt terms
    rw [hsqrt_d_sq, hsqrt_n_sq]
  -- Step 5: Apply the result
  calc (stdGaussianPi n {w | (empiricalNorm n (fun i => f_hat w (M.x i) - M.f_star (M.x i)))^2 ≤
          linear_C₁ * M.σ^2 * d / n}).toReal
      ≥ (stdGaussianPi n {w | (empiricalNorm n (fun i => f_hat w (M.x i) - M.f_star (M.x i)))^2 ≤
          16 * δ_star * δ_star}).toReal := by
        apply ENNReal.toReal_mono
        · apply ne_of_lt
          exact measure_lt_top _ _
        · apply MeasureTheory.measure_mono
          intro w hw
          simp only [Set.mem_setOf_eq] at hw ⊢
          calc (empiricalNorm n (fun i => f_hat w (M.x i) - M.f_star (M.x i)))^2
              ≤ 16 * δ_star * δ_star := hw
            _ = linear_C₁ * M.σ^2 * d / n := h_bound_eq
    _ ≥ 1 - exp (-n * δ_star * δ_star / (2 * M.σ^2)) := h_master
    _ = 1 - exp (-linear_C₂ * d) := by rw [h_exp_eq]

/-- Explicit form of the minimax rate with the concrete constant structure.
This form shows explicitly how the bound scales with the problem parameters. -/
theorem linear_minimax_rate_explicit (hn : 0 < n) (hd : 0 < d)
    (M : RegressionModel n (EuclideanSpace ℝ (Fin d)))
    (hf_star : M.f_star ∈ linearPredictorClass d)
    (hinj : Function.Injective (designMatrixMul M.x))
    (f_hat : (Fin n → ℝ) → (EuclideanSpace ℝ (Fin d) → ℝ))
    (hf_hat : ∀ w, isLeastSquaresEstimator (M.response w) (linearPredictorClass d) M.x (f_hat w)) :
    (stdGaussianPi n {w | (empiricalNorm n (fun i => f_hat w (M.x i) - M.f_star (M.x i)))^2 ≤
        16 * (linear_δ_star M.σ d n)^2}).toReal ≥
      1 - exp (-n * (linear_δ_star M.σ d n)^2 / (2 * M.σ^2)) := by
  have hδ_pos := linear_δ_star_pos M.hσ_pos hd hn
  -- Apply master_error_bound
  set δ_star := linear_δ_star M.σ d n
  have hCI := linear_critical_inequality hn hd M.x M.σ M.hσ_pos hinj hf_star
  have hH_star := linear_shiftedClass_isStarShaped hf_star
  have h_sqrt_eq : Real.sqrt (δ_star * δ_star) = δ_star := by
    rw [← sq]
    exact Real.sqrt_sq (le_of_lt hδ_pos)
  have hne : (empiricalSphere n (shiftedClass (linearPredictorClass d) M.f_star) (Real.sqrt (δ_star * δ_star)) M.x).Nonempty := by
    rw [h_sqrt_eq]
    exact linear_empiricalSphere_nonempty hn hd M.x hδ_pos hinj hf_star
  have hint_u : Integrable (fun w => ⨆ h ∈ localizedBall (shiftedClass (linearPredictorClass d) M.f_star)
      (Real.sqrt (δ_star * δ_star)) M.x, |(n : ℝ)⁻¹ * ∑ i, w i * h (M.x i)|) (stdGaussianPi n) := by
    rw [h_sqrt_eq]
    exact linear_integrable_at_radius M.x hδ_pos hf_star
  have hint_δ : Integrable (fun w => ⨆ h ∈ localizedBall (shiftedClass (linearPredictorClass d) M.f_star)
      δ_star M.x, |(n : ℝ)⁻¹ * ∑ i, w i * h (M.x i)|) (stdGaussianPi n) :=
    linear_integrable_at_radius M.x hδ_pos hf_star
  have hbdd : ∀ w : Fin n → ℝ, BddAbove {y | ∃ h ∈ localizedBall (shiftedClass (linearPredictorClass d) M.f_star)
      (Real.sqrt (δ_star * δ_star)) M.x, y = |(n : ℝ)⁻¹ * ∑ i, w i * h (M.x i)|} := by
    rw [h_sqrt_eq]
    exact linear_bddAbove_at_radius hn M.x hδ_pos hf_star
  have h_master := master_error_bound hn M (linearPredictorClass d) hf_star δ_star hδ_pos
    hCI hH_star δ_star (le_refl δ_star) f_hat hf_hat hne hint_u hint_δ hbdd
  -- Convert using sq = mul self
  have h_sq_eq : δ_star^2 = δ_star * δ_star := sq δ_star
  have h_bound_eq : 16 * δ_star^2 = 16 * δ_star * δ_star := by rw [h_sq_eq]; ring
  have h_exp_eq : -n * δ_star^2 / (2 * M.σ^2) = -n * δ_star * δ_star / (2 * M.σ^2) := by
    rw [h_sq_eq]; ring
  rw [h_bound_eq, h_exp_eq]
  exact h_master

/-! ### Rank-based Theorems

These theorems generalize the main results by replacing the full-rank assumption
`hinj : Function.Injective (designMatrixMul x)` with the weaker assumption
`hr : 0 < designMatrixRank x`. The rate becomes O(σ²·r/n) where r = rank(X).
-/

/-- The critical radius using rank: δ_star = 2σ * C₁ * √r / √n = 192√2 * σ * √r / √n -/
noncomputable def linear_δ_star_rank (σ : ℝ) (r n : ℕ) : ℝ :=
  2 * σ * linear_C1 * Real.sqrt r / Real.sqrt n

lemma linear_δ_star_rank_eq (σ : ℝ) (r n : ℕ) :
    linear_δ_star_rank σ r n = 192 * Real.sqrt 2 * σ * Real.sqrt r / Real.sqrt n := by
  unfold linear_δ_star_rank linear_C1
  ring

/-- The critical radius using rank is positive when σ > 0, r > 0, n > 0 -/
lemma linear_δ_star_rank_pos {σ : ℝ} (hσ : 0 < σ) {r : ℕ} (hr : 0 < r) (hn : 0 < n) :
    0 < linear_δ_star_rank σ r n := by
  unfold linear_δ_star_rank linear_C1
  positivity

/-- The critical inequality using rank is satisfied at δ_star for linear predictors.

This generalizes `linear_critical_inequality` by using the Gaussian complexity bound
with rank instead of dimension d. -/
lemma linear_critical_inequality_rank (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) (σ : ℝ) (hσ : 0 < σ)
    (hr : 0 < designMatrixRank x)
    {f_star : EuclideanSpace ℝ (Fin d) → ℝ} (hf_star : f_star ∈ linearPredictorClass d) :
    satisfiesCriticalInequality n σ (linear_δ_star_rank σ (designMatrixRank x) n)
      (shiftedClass (linearPredictorClass d) f_star) x := by
  rw [shiftedClass_eq_self_of_linear hf_star]
  unfold satisfiesCriticalInequality
  -- Get the local Gaussian complexity bound using rank
  have h_bound := linear_local_gaussian_complexity_bound_rank n d hn x
    (linear_δ_star_rank_pos hσ hr hn) hr
  -- Setup positivity facts
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have hsqrtn : 0 < Real.sqrt n := Real.sqrt_pos.mpr hn_pos
  have hδ_pos := linear_δ_star_rank_pos hσ hr hn
  have hδ_ne : linear_δ_star_rank σ (designMatrixRank x) n ≠ 0 := ne_of_gt hδ_pos
  have hσ_ne : σ ≠ 0 := ne_of_gt hσ
  have hsqrtn_ne : Real.sqrt n ≠ 0 := ne_of_gt hsqrtn
  -- LHS: G_n(δ_star) / δ_star ≤ C₁ * √r / √n
  have h_lhs : LocalGaussianComplexity n (linearPredictorClass d)
      (linear_δ_star_rank σ (designMatrixRank x) n) x /
      (linear_δ_star_rank σ (designMatrixRank x) n) ≤
      linear_C1 * Real.sqrt (designMatrixRank x) / Real.sqrt n := by
    calc LocalGaussianComplexity n (linearPredictorClass d)
          (linear_δ_star_rank σ (designMatrixRank x) n) x /
          (linear_δ_star_rank σ (designMatrixRank x) n)
        ≤ ((96 * Real.sqrt 2) * (linear_δ_star_rank σ (designMatrixRank x) n) *
            Real.sqrt (designMatrixRank x) / Real.sqrt n) /
            (linear_δ_star_rank σ (designMatrixRank x) n) := by
          apply div_le_div_of_nonneg_right h_bound (le_of_lt hδ_pos)
      _ = (96 * Real.sqrt 2) * Real.sqrt (designMatrixRank x) / Real.sqrt n := by
          field_simp
      _ = linear_C1 * Real.sqrt (designMatrixRank x) / Real.sqrt n := rfl
  -- RHS: δ_star / (2σ) = C₁ * √r / √n
  have h_rhs : linear_δ_star_rank σ (designMatrixRank x) n / (2 * σ) =
      linear_C1 * Real.sqrt (designMatrixRank x) / Real.sqrt n := by
    unfold linear_δ_star_rank
    field_simp
  -- Combine
  calc LocalGaussianComplexity n (linearPredictorClass d)
        (linear_δ_star_rank σ (designMatrixRank x) n) x /
        (linear_δ_star_rank σ (designMatrixRank x) n)
      ≤ linear_C1 * Real.sqrt (designMatrixRank x) / Real.sqrt n := h_lhs
    _ = linear_δ_star_rank σ (designMatrixRank x) n / (2 * σ) := h_rhs.symm

/-- The empirical sphere at any positive radius is nonempty for linear predictors
    when the design matrix has positive rank.

This generalizes `linear_empiricalSphere_nonempty` by using `0 < designMatrixRank x`
instead of `hinj : Function.Injective (designMatrixMul x)`. -/
lemma linear_empiricalSphere_nonempty_rank (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {u : ℝ} (hu : 0 < u)
    (hr : 0 < designMatrixRank x)
    {f_star : EuclideanSpace ℝ (Fin d) → ℝ} (hf_star : f_star ∈ linearPredictorClass d) :
    (empiricalSphere n (shiftedClass (linearPredictorClass d) f_star) u x).Nonempty := by
  rw [shiftedClass_eq_self_of_linear hf_star]
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  -- From positive rank, get θ₀ with designMatrixMul x θ₀ ≠ 0
  rw [designMatrixRank_pos_iff] at hr
  obtain ⟨θ₀, hθ₀_ne⟩ := hr
  -- Thus ‖designMatrixMul x θ₀‖ > 0
  have hXθ₀_norm_pos : 0 < ‖designMatrixMul x θ₀‖ := norm_pos_iff.mpr hθ₀_ne
  -- The linear function has positive empirical norm
  have h_emp_norm_pos : 0 < empiricalNorm n (fun i => @inner ℝ _ _ θ₀ (x i)) := by
    rw [empiricalNorm_linear x θ₀]
    apply mul_pos
    · exact Real.sqrt_pos.mpr (inv_pos.mpr hn_pos)
    · exact hXθ₀_norm_pos
  -- Scale to get exact norm u
  let r := empiricalNorm n (fun i => @inner ℝ _ _ θ₀ (x i))
  let c := u / r
  have hc_pos : 0 < c := div_pos hu h_emp_norm_pos
  let θ := c • θ₀
  -- The function f(z) = ⟨θ, z⟩ is in linearPredictorClass
  use fun z => @inner ℝ _ _ θ z
  constructor
  · -- f ∈ linearPredictorClass d
    have hθ₀_mem : (fun z => @inner ℝ _ _ θ₀ z) ∈ linearPredictorClass d := ⟨θ₀, rfl⟩
    have h_smul : (fun z => @inner ℝ _ _ θ z) = c • (fun z => @inner ℝ _ _ θ₀ z) := by
      ext z
      simp only [θ, Pi.smul_apply, smul_eq_mul, inner_smul_left, RCLike.conj_to_real]
    rw [h_smul]
    exact smul_mem_linearPredictorClass hθ₀_mem
  · -- empiricalNorm = u
    show empiricalNorm n (fun i => @inner ℝ _ _ θ (x i)) = u
    have h_inner_smul : ∀ z, @inner ℝ _ _ θ z = c * @inner ℝ _ _ θ₀ z := by
      intro z
      simp only [θ, inner_smul_left, RCLike.conj_to_real]
    simp_rw [h_inner_smul]
    rw [empiricalNorm_smul_linear x θ₀ (le_of_lt hc_pos)]
    simp only [c, r]
    rw [div_mul_cancel₀]
    exact ne_of_gt h_emp_norm_pos

/-- The error bound constant C₁_rank for the rank-based minimax rate. -/
noncomputable def linear_C₁_rank : ℝ := 16 * (192 * Real.sqrt 2)^2

lemma linear_C₁_rank_pos : 0 < linear_C₁_rank := by
  unfold linear_C₁_rank
  positivity

/-- The exponent constant C₂_rank for the rank-based probability bound. -/
noncomputable def linear_C₂_rank : ℝ := (192 * Real.sqrt 2)^2 / 2

lemma linear_C₂_rank_pos : 0 < linear_C₂_rank := by
  unfold linear_C₂_rank
  positivity

/-- Main theorem with rank: Linear regression achieves the rate O(σ²r/n).

This generalizes `linear_minimax_rate` by replacing the full-rank assumption
`hinj` with the weaker assumption `0 < designMatrixRank M.x`.

There exist constants C₁, C₂ > 0 such that with probability at least 1 - exp(-C₂·r),
the squared L²-error satisfies:
  ‖f̂ - f*‖²_n ≤ C₁ · σ² · r / n

where r = designMatrixRank x is the rank of the design matrix. -/
theorem linear_minimax_rate_rank (hn : 0 < n)
    (M : RegressionModel n (EuclideanSpace ℝ (Fin d)))
    (hf_star : M.f_star ∈ linearPredictorClass d)
    (hr : 0 < designMatrixRank M.x)
    (f_hat : (Fin n → ℝ) → (EuclideanSpace ℝ (Fin d) → ℝ))
    (hf_hat : ∀ w, isLeastSquaresEstimator (M.response w) (linearPredictorClass d) M.x (f_hat w)) :
    ∃ C₁ C₂ : ℝ, C₁ > 0 ∧ C₂ > 0 ∧
      (stdGaussianPi n {w | (empiricalNorm n (fun i => f_hat w (M.x i) - M.f_star (M.x i)))^2 ≤
          C₁ * M.σ^2 * (designMatrixRank M.x) / n}).toReal ≥
        1 - exp (-C₂ * (designMatrixRank M.x)) := by
  refine ⟨linear_C₁_rank, linear_C₂_rank, linear_C₁_rank_pos, linear_C₂_rank_pos, ?_⟩
  -- Define δ_star using rank
  set r := designMatrixRank M.x
  set δ_star := linear_δ_star_rank M.σ r n with hδ_star_def
  have hδ_star_pos := linear_δ_star_rank_pos M.hσ_pos hr hn
  -- Step 1: Verify all hypotheses of master_error_bound
  have hCI := linear_critical_inequality_rank hn M.x M.σ M.hσ_pos hr hf_star
  have hH_star := linear_shiftedClass_isStarShaped hf_star
  -- For t = δ_star, √(t·δ_star) = √(δ_star²) = δ_star
  have h_sqrt_eq : Real.sqrt (δ_star * δ_star) = δ_star := by
    rw [← sq]
    exact Real.sqrt_sq (le_of_lt hδ_star_pos)
  -- Nonemptiness of empirical sphere at √(δ_star²) = δ_star
  have hne : (empiricalSphere n (shiftedClass (linearPredictorClass d) M.f_star)
      (Real.sqrt (δ_star * δ_star)) M.x).Nonempty := by
    rw [h_sqrt_eq]
    exact linear_empiricalSphere_nonempty_rank hn M.x hδ_star_pos hr hf_star
  -- Integrability at √(t·δ_star) = δ_star
  have hint_u : Integrable (fun w => ⨆ h ∈ localizedBall (shiftedClass (linearPredictorClass d) M.f_star)
      (Real.sqrt (δ_star * δ_star)) M.x, |(n : ℝ)⁻¹ * ∑ i, w i * h (M.x i)|) (stdGaussianPi n) := by
    rw [h_sqrt_eq]
    exact linear_integrable_at_radius M.x hδ_star_pos hf_star
  -- Integrability at δ_star
  have hint_δ : Integrable (fun w => ⨆ h ∈ localizedBall (shiftedClass (linearPredictorClass d) M.f_star)
      δ_star M.x, |(n : ℝ)⁻¹ * ∑ i, w i * h (M.x i)|) (stdGaussianPi n) :=
    linear_integrable_at_radius M.x hδ_star_pos hf_star
  -- Boundedness at √(t·δ_star) = δ_star
  have hbdd : ∀ w : Fin n → ℝ, BddAbove {y | ∃ h ∈ localizedBall (shiftedClass (linearPredictorClass d) M.f_star)
      (Real.sqrt (δ_star * δ_star)) M.x, y = |(n : ℝ)⁻¹ * ∑ i, w i * h (M.x i)|} := by
    rw [h_sqrt_eq]
    exact linear_bddAbove_at_radius hn M.x hδ_star_pos hf_star
  -- Step 2: Apply master_error_bound with t = δ_star
  have h_master := master_error_bound hn M (linearPredictorClass d) hf_star δ_star hδ_star_pos
    hCI hH_star δ_star (le_refl δ_star) f_hat hf_hat hne hint_u hint_δ hbdd
  -- Step 3: Show the bound 16·δ_star² = linear_C₁_rank · σ² · r / n
  have h_bound_eq : 16 * δ_star * δ_star = linear_C₁_rank * M.σ^2 * r / n := by
    rw [hδ_star_def, linear_δ_star_rank_eq]
    unfold linear_C₁_rank
    have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
    have hsqrt_n_sq : Real.sqrt n ^ 2 = n := Real.sq_sqrt (Nat.cast_nonneg n)
    have hsqrt_r_sq : Real.sqrt r ^ 2 = r := Real.sq_sqrt (Nat.cast_nonneg r)
    have hn_ne : (n : ℝ) ≠ 0 := Nat.cast_ne_zero.mpr (Nat.pos_iff_ne_zero.mp hn)
    have hsqrt_n_ne : Real.sqrt n ≠ 0 := Real.sqrt_ne_zero'.mpr hn_pos
    field_simp
    rw [hsqrt_r_sq, hsqrt_n_sq]
    ring
  -- Step 4: Show the exponent n·δ_star²/(2σ²) = linear_C₂_rank · r
  have h_exp_eq : -n * δ_star * δ_star / (2 * M.σ^2) = -linear_C₂_rank * r := by
    rw [hδ_star_def, linear_δ_star_rank_eq]
    unfold linear_C₂_rank
    have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
    have hsqrt_n_sq : Real.sqrt n ^ 2 = n := Real.sq_sqrt (Nat.cast_nonneg n)
    have hsqrt_r_sq : Real.sqrt r ^ 2 = r := Real.sq_sqrt (Nat.cast_nonneg r)
    have hsqrt_n_ne : Real.sqrt n ≠ 0 := Real.sqrt_ne_zero'.mpr hn_pos
    have hσ_ne : M.σ ≠ 0 := ne_of_gt M.hσ_pos
    field_simp
    rw [hsqrt_r_sq, hsqrt_n_sq]
  -- Step 5: Apply the result
  calc (stdGaussianPi n {w | (empiricalNorm n (fun i => f_hat w (M.x i) - M.f_star (M.x i)))^2 ≤
          linear_C₁_rank * M.σ^2 * r / n}).toReal
      ≥ (stdGaussianPi n {w | (empiricalNorm n (fun i => f_hat w (M.x i) - M.f_star (M.x i)))^2 ≤
          16 * δ_star * δ_star}).toReal := by
        apply ENNReal.toReal_mono
        · apply ne_of_lt
          exact measure_lt_top _ _
        · apply MeasureTheory.measure_mono
          intro w hw
          simp only [Set.mem_setOf_eq] at hw ⊢
          calc (empiricalNorm n (fun i => f_hat w (M.x i) - M.f_star (M.x i)))^2
              ≤ 16 * δ_star * δ_star := hw
            _ = linear_C₁_rank * M.σ^2 * r / n := h_bound_eq
    _ ≥ 1 - exp (-n * δ_star * δ_star / (2 * M.σ^2)) := h_master
    _ = 1 - exp (-linear_C₂_rank * r) := by rw [h_exp_eq]

end LeastSquares

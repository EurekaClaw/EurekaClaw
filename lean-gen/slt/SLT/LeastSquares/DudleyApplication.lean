/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import Mathlib
import SLT.LeastSquares.Defs
import SLT.LeastSquares.SubGaussianity
import SLT.Dudley
import SLT.MetricEntropy
import SLT.GaussianMeasure

/-!
# Application of Dudley's Entropy Integral to Local Gaussian Complexity

This file applies Dudley's chaining argument to bound the local Gaussian complexity
of empirical processes over function classes.

## Main definitions

* `evalAtSample`: Evaluation map embedding functions into finite-dimensional space
* `empiricalDist`: Pseudo-metric on functions induced by empirical norm
* `innerProductProcess`: The Gaussian process Z_v(w) = (1/n) Σᵢ wᵢvᵢ
* `euclideanNorm`: L2 norm on Fin n → ℝ

## Main results

* `localizedBall_diam`: Diameter of localized ball B_n(δ; H) is at most 2δ
* `innerProductProcess_isSubGaussianProcess`: Inner product process is σ-sub-Gaussian with σ = 1/√n
* `gaussian_complexity_ratio_antitone`: δ ↦ G_n(δ)/δ is non-increasing for star-shaped classes
* `dudley_empiricalProcess`: Dudley bound E[sup_{g∈G} Z_g] ≤ (12√2)/√n · entropy integral
* `local_gaussian_complexity_bound`: G_n(δ) ≤ (24√2)/√n · entropy integral

-/

open MeasureTheory Finset BigOperators Real ProbabilityTheory Metric GaussianMeasure

namespace LeastSquares

variable {X : Type*}

/-! ## Gaussian Negation Symmetry -/

/-- Gaussian measure with mean 0 is invariant under negation -/
lemma gaussianReal_zero_map_neg (v : NNReal) :
    (gaussianReal (0 : ℝ) v).map (fun x => -x) = gaussianReal 0 v := by
  have h := @gaussianReal_map_const_mul (0 : ℝ) v (-1)
  simp only [neg_mul, one_mul, neg_zero] at h
  have h2 : (⟨(-1 : ℝ) ^ 2, sq_nonneg _⟩ : NNReal) = (1 : NNReal) := by
    ext
    simp
  rw [h2, one_mul] at h
  convert h using 2

/-- Standard Gaussian is negation-invariant -/
instance gaussianReal_zero_IsNegInvariant (v : NNReal) : (gaussianReal (0 : ℝ) v).IsNegInvariant where
  neg_eq_self := by
    rw [Measure.neg_def, gaussianReal_zero_map_neg]

/-! ## Empirical Metric Structure -/

/-- Evaluation map: sends a function g to its values at sample points.
This is the key embedding into the metric space structure. -/
def evalAtSample (n : ℕ) (x : Fin n → X) (g : X → ℝ) : Fin n → ℝ :=
  fun i => g (x i)

/-- The empirical distance between two functions is the empirical norm of their difference -/
noncomputable def empiricalDist (n : ℕ) (x : Fin n → X) (g₁ g₂ : X → ℝ) : ℝ :=
  empiricalNorm n (fun i => g₁ (x i) - g₂ (x i))

/-- Empirical distance is non-negative -/
lemma empiricalDist_nonneg (n : ℕ) (x : Fin n → X) (g₁ g₂ : X → ℝ) :
    0 ≤ empiricalDist n x g₁ g₂ :=
  empiricalNorm_nonneg n _

/-- Empirical distance is symmetric -/
lemma empiricalDist_comm (n : ℕ) (x : Fin n → X) (g₁ g₂ : X → ℝ) :
    empiricalDist n x g₁ g₂ = empiricalDist n x g₂ g₁ := by
  unfold empiricalDist empiricalNorm
  congr 1
  apply congr_arg
  congr 1
  ext i
  ring

/-- Empirical distance from a function to itself is zero -/
lemma empiricalDist_self (n : ℕ) (x : Fin n → X) (g : X → ℝ) :
    empiricalDist n x g g = 0 := by
  unfold empiricalDist empiricalNorm
  simp only [sub_self, sq, mul_zero, sum_const_zero, mul_zero, Real.sqrt_zero]

/-- Norm on EuclideanSpace in terms of sum of squares -/
lemma euclidean_norm_sq (n : ℕ) (a : EuclideanSpace ℝ (Fin n)) :
    ‖a‖ = Real.sqrt (∑ i : Fin n, (a i)^2) := by
  rw [EuclideanSpace.norm_eq]
  congr 1
  apply Finset.sum_congr rfl
  intro i _
  rw [Real.norm_eq_abs, sq_abs]

/-- Helper: Minkowski inequality for empirical norm (addition form) -/
lemma empiricalNorm_add_le (n : ℕ) (a b : Fin n → ℝ) :
    Real.sqrt ((n : ℝ)⁻¹ * ∑ i, (a i + b i)^2) ≤
    Real.sqrt ((n : ℝ)⁻¹ * ∑ i, (a i)^2) + Real.sqrt ((n : ℝ)⁻¹ * ∑ i, (b i)^2) := by
  by_cases hn : n = 0
  · simp [hn]
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr (Nat.pos_of_ne_zero hn)
  have hn_inv_nonneg : 0 ≤ (n : ℝ)⁻¹ := inv_nonneg.mpr (le_of_lt hn_pos)
  have h_factor : ∀ f : Fin n → ℝ, Real.sqrt ((n : ℝ)⁻¹ * ∑ i, (f i)^2) =
      Real.sqrt (n : ℝ)⁻¹ * Real.sqrt (∑ i, (f i)^2) := fun f => by
    rw [Real.sqrt_mul hn_inv_nonneg]
  rw [h_factor (fun i => a i + b i), h_factor a, h_factor b, ← mul_add]
  apply mul_le_mul_of_nonneg_left _ (Real.sqrt_nonneg _)
  let a' : EuclideanSpace ℝ (Fin n) := (EuclideanSpace.equiv (Fin n) ℝ).symm a
  let b' : EuclideanSpace ℝ (Fin n) := (EuclideanSpace.equiv (Fin n) ℝ).symm b
  have ha_norm : Real.sqrt (∑ i, (a i)^2) = ‖a'‖ := by rw [euclidean_norm_sq]; congr 1
  have hb_norm : Real.sqrt (∑ i, (b i)^2) = ‖b'‖ := by rw [euclidean_norm_sq]; congr 1
  have hab_norm : Real.sqrt (∑ i, (a i + b i)^2) = ‖a' + b'‖ := by rw [euclidean_norm_sq]; congr 1
  rw [ha_norm, hb_norm, hab_norm]
  exact norm_add_le a' b'

/-- Triangle inequality: ‖a - b‖ ≤ ‖a‖ + ‖b‖ for empirical norm -/
lemma empiricalNorm_sub_le (n : ℕ) (a b : Fin n → ℝ) :
    empiricalNorm n (fun i => a i - b i) ≤ empiricalNorm n a + empiricalNorm n b := by
  unfold empiricalNorm
  by_cases hn : n = 0
  · simp [hn]
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr (Nat.pos_of_ne_zero hn)
  have hn_inv_nonneg : 0 ≤ (n : ℝ)⁻¹ := inv_nonneg.mpr (le_of_lt hn_pos)
  have h_factor : ∀ f : Fin n → ℝ, Real.sqrt ((n : ℝ)⁻¹ * ∑ i, (f i)^2) =
      Real.sqrt (n : ℝ)⁻¹ * Real.sqrt (∑ i, (f i)^2) := fun f => by
    rw [Real.sqrt_mul hn_inv_nonneg]
  rw [h_factor (fun i => a i - b i), h_factor a, h_factor b, ← mul_add]
  apply mul_le_mul_of_nonneg_left _ (Real.sqrt_nonneg _)
  let a' : EuclideanSpace ℝ (Fin n) := (EuclideanSpace.equiv (Fin n) ℝ).symm a
  let b' : EuclideanSpace ℝ (Fin n) := (EuclideanSpace.equiv (Fin n) ℝ).symm b
  have ha_norm : Real.sqrt (∑ i, (a i)^2) = ‖a'‖ := by rw [euclidean_norm_sq]; congr 1
  have hb_norm : Real.sqrt (∑ i, (b i)^2) = ‖b'‖ := by rw [euclidean_norm_sq]; congr 1
  have hab_norm : Real.sqrt (∑ i, (a i - b i)^2) = ‖a' - b'‖ := by rw [euclidean_norm_sq]; congr 1
  rw [ha_norm, hb_norm, hab_norm]
  exact norm_sub_le a' b'

/-- Empirical distance satisfies triangle inequality -/
lemma empiricalDist_triangle (n : ℕ) (x : Fin n → X) (g₁ g₂ g₃ : X → ℝ) :
    empiricalDist n x g₁ g₃ ≤ empiricalDist n x g₁ g₂ + empiricalDist n x g₂ g₃ := by
  unfold empiricalDist empiricalNorm
  -- Key: (g₁ - g₃) = (g₁ - g₂) + (g₂ - g₃), so use Minkowski
  have h_sum_eq : ∑ i : Fin n, (g₁ (x i) - g₃ (x i))^2 =
      ∑ i : Fin n, ((g₁ (x i) - g₂ (x i)) + (g₂ (x i) - g₃ (x i)))^2 := by
    apply Finset.sum_congr rfl
    intro i _
    congr 1
    ring
  rw [h_sum_eq]
  exact empiricalNorm_add_le n (fun i => g₁ (x i) - g₂ (x i)) (fun i => g₂ (x i) - g₃ (x i))

/-! ## Localized Ball Diameter Bound -/

/-- **Lemma 5.1**: The diameter of a localized ball B_n(δ; H) is at most 2δ.

For g₁, g₂ ∈ B_n(δ), we have:
‖g₁ - g₂‖_n ≤ ‖g₁‖_n + ‖g₂‖_n ≤ δ + δ = 2δ -/
lemma localizedBall_diam_bound (n : ℕ) (H : Set (X → ℝ)) (δ : ℝ) (x : Fin n → X)
    (g₁ g₂ : X → ℝ) (hg₁ : g₁ ∈ localizedBall H δ x) (hg₂ : g₂ ∈ localizedBall H δ x) :
    empiricalDist n x g₁ g₂ ≤ 2 * δ := by
  -- g₁ ∈ B_n(δ) means ‖g₁‖_n ≤ δ
  -- g₂ ∈ B_n(δ) means ‖g₂‖_n ≤ δ
  have hg₁_norm : empiricalNorm n (fun i => g₁ (x i)) ≤ δ := hg₁.2
  have hg₂_norm : empiricalNorm n (fun i => g₂ (x i)) ≤ δ := hg₂.2
  -- By triangle inequality: ‖g₁ - g₂‖_n ≤ ‖g₁‖_n + ‖g₂‖_n ≤ 2δ
  unfold empiricalDist
  calc empiricalNorm n (fun i => g₁ (x i) - g₂ (x i))
      ≤ empiricalNorm n (fun i => g₁ (x i)) + empiricalNorm n (fun i => g₂ (x i)) :=
        empiricalNorm_sub_le n (fun i => g₁ (x i)) (fun i => g₂ (x i))
    _ ≤ δ + δ := add_le_add hg₁_norm hg₂_norm
    _ = 2 * δ := by ring

/-- **Lemma 5.1 (Metric.diam version)**: The diameter of the image of a localized ball
under empiricalMetricImage is at most 2δ.

This upgrades localizedBall_diam_bound from a pointwise bound to a Metric.diam statement. -/
lemma localizedBall_diam (n : ℕ) (H : Set (X → ℝ)) (δ : ℝ) (hδ : 0 ≤ δ) (x : Fin n → X) :
    Metric.diam (empiricalMetricImage n x '' localizedBall H δ x) ≤ 2 * δ := by
  apply Metric.diam_le_of_forall_dist_le (by linarith : 0 ≤ 2 * δ)
  intro v₁ hv₁ v₂ hv₂
  -- v₁ = empiricalMetricImage n x g₁ for some g₁ ∈ localizedBall H δ x
  obtain ⟨g₁, hg₁, rfl⟩ := hv₁
  obtain ⟨g₂, hg₂, rfl⟩ := hv₂
  -- dist(v₁, v₂) = empiricalDist n x g₁ g₂
  rw [dist_empiricalMetricImage]
  -- Use the pointwise bound
  have h := localizedBall_diam_bound n H δ x g₁ g₂ hg₁ hg₂
  unfold empiricalDist at h
  exact h

/-! ## Sub-Gaussian Bridge to EmpiricalSpace -/

/-- The inner product process over EmpiricalSpace:
Z_v(w) = (1/n) Σᵢ wᵢ vᵢ

This is the empirical process written directly in terms of EmpiricalSpace vectors. -/
noncomputable def innerProductProcess (n : ℕ) (v : EmpiricalSpace n) (w : Fin n → ℝ) : ℝ :=
  (n : ℝ)⁻¹ * ∑ i, w i * v i

/-- Inner product process is linear in v -/
lemma innerProductProcess_sub (n : ℕ) (v₁ v₂ : EmpiricalSpace n) (w : Fin n → ℝ) :
    innerProductProcess n v₁ w - innerProductProcess n v₂ w =
    innerProductProcess n (v₁ - v₂) w := by
  unfold innerProductProcess
  rw [← mul_sub, ← Finset.sum_sub_distrib]
  congr 1
  apply Finset.sum_congr rfl
  intro i _
  -- (v₁ - v₂) i = v₁ i - v₂ i by definition of EmpiricalSpace.Sub
  have h_sub : (v₁ - v₂) i = v₁ i - v₂ i := rfl
  rw [h_sub]
  ring

/-- Key: The empirical process Z_g equals the inner product process applied to empiricalMetricImage -/
lemma empiricalProcess_eq_innerProductProcess (n : ℕ) (x : Fin n → X) (g : X → ℝ) (w : Fin n → ℝ) :
    empiricalProcess n x g w = innerProductProcess n (empiricalMetricImage n x g) w := by
  unfold empiricalProcess innerProductProcess empiricalMetricImage
  rfl

/-- The inner product process Z_v(w) = (1/n)Σᵢ wᵢvᵢ is sub-Gaussian with parameter σ = 1/√n.

This bridges sub-Gaussianity from function space to EmpiricalSpace via the MGF bound. -/
lemma innerProductProcess_isSubGaussianProcess (n : ℕ) (hn : 0 < n) :
    let μ := stdGaussianPi n
    let Z := fun (v : EmpiricalSpace n) (w : Fin n → ℝ) => innerProductProcess n v w
    let σ := subGaussianParam n  -- = 1/√n
    IsSubGaussianProcess μ Z σ := by
  intro μ Z σ v₁ v₂ t
  have h_diff : ∀ w, Z v₁ w - Z v₂ w = innerProductProcess n (v₁ - v₂) w :=
    innerProductProcess_sub n v₁ v₂
  simp_rw [h_diff]
  have h_dist : dist v₁ v₂ = empiricalNorm n (v₁ - v₂) := rfl
  rw [h_dist]
  set d := v₁ - v₂
  set a : Fin n → ℝ := fun i => (n : ℝ)⁻¹ * d i with ha_def
  haveI : NeZero n := ⟨ne_of_gt hn⟩
  have h_inner_eq_sum : ∀ w : Fin n → ℝ, innerProductProcess n d w = ∑ i, a i * w i := fun w => by
    unfold innerProductProcess
    rw [Finset.mul_sum]
    congr 1
    ext i
    rw [ha_def]
    ring
  conv_lhs => arg 2; ext w; rw [h_inner_eq_sum]
  have h_exp_form : ∀ w : Fin n → ℝ, t * ∑ i, a i * w i = ∑ i, t * a i * w i := fun w => by
    rw [Finset.mul_sum]
    congr 1; ext i; ring
  have h_exp_prod : ∀ w : Fin n → ℝ,
      Real.exp (∑ i, t * a i * w i) = ∏ i : Fin n, Real.exp (t * a i * w i) := fun w => by
    exact Real.exp_sum (Finset.univ) (fun i => t * a i * w i)
  conv_lhs => arg 2; ext w; rw [h_exp_form, h_exp_prod]
  have h_fubini : (∫ w : (i : Fin n) → ℝ, ∏ i, Real.exp (t * a i * w i) ∂(stdGaussianPi n)) =
      ∏ i : Fin n, ∫ x : ℝ, Real.exp (t * a i * x) ∂(gaussianReal 0 1) := by
    have h := @integral_fin_nat_prod_eq_prod ℝ _ n (fun _ => ℝ) _ (fun _ => gaussianReal 0 1) _
        (fun i x => Real.exp (t * a i * x))
    convert h using 1
  rw [h_fubini]
  have h_mgf : ∀ i : Fin n, ∫ x : ℝ, Real.exp (t * a i * x) ∂(gaussianReal 0 1) =
      Real.exp ((t * a i)^2 / 2) := fun i => by
    have h_map : Measure.map id (gaussianReal 0 1) = gaussianReal 0 1 := Measure.map_id
    have hmgf := mgf_gaussianReal h_map (t * a i)
    simp only [mgf, id_eq, zero_mul, NNReal.coe_one, zero_add, one_mul] at hmgf
    convert hmgf using 2
  simp_rw [h_mgf]
  rw [← Real.exp_sum]
  apply le_of_eq; congr 1
  have h_sum_sq : ∑ i : Fin n, (t * a i)^2 / 2 = t^2 / 2 * ∑ i, (a i)^2 := by
    rw [Finset.mul_sum]; congr 1; ext i; ring
  rw [h_sum_sq]
  have h_a_sq : ∑ i : Fin n, (a i)^2 = (n : ℝ)⁻¹ * (n : ℝ)⁻¹ * ∑ i, (d i)^2 := by
    simp_rw [ha_def, mul_pow, ← Finset.mul_sum]; ring
  rw [h_a_sq]
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have h_norm_sq : (empiricalNorm n d)^2 = (n : ℝ)⁻¹ * ∑ i, (d i)^2 := empiricalNorm_sq n d
  rw [h_norm_sq]
  have hσ_sq : σ^2 = 1 / n := by
    show (subGaussianParam n)^2 = 1 / n
    simp only [subGaussianParam, div_pow, one_pow, sq_sqrt (le_of_lt hn_pos)]
  rw [hσ_sq]; ring

/-! ## Monotonicity of G_n(δ)/δ -/

/-- Empirical process is linear under scalar multiplication of the function -/
lemma empiricalProcess_smul (n : ℕ) (x : Fin n → X) (α : ℝ) (g : X → ℝ) (w : Fin n → ℝ) :
    empiricalProcess n x (α • g) w = α * empiricalProcess n x g w := by
  unfold empiricalProcess
  simp only [Pi.smul_apply, smul_eq_mul, Finset.mul_sum]
  ring_nf
  congr 1
  ext i
  ring

/-- Empirical norm scales by absolute value of the scalar -/
lemma empiricalNorm_smul (n : ℕ) (α : ℝ) (f : Fin n → ℝ) :
    empiricalNorm n (α • f) = |α| * empiricalNorm n f := by
  unfold empiricalNorm
  simp only [Pi.smul_apply, smul_eq_mul, mul_pow]
  rw [← Finset.mul_sum]
  have h_rearrange : (n : ℝ)⁻¹ * (α ^ 2 * ∑ i, f i ^ 2) = α ^ 2 * ((n : ℝ)⁻¹ * ∑ i, f i ^ 2) := by
    ring
  rw [h_rearrange, Real.sqrt_mul (sq_nonneg α), Real.sqrt_sq_eq_abs]

/-- For non-negative scalar, norm scales directly -/
lemma empiricalNorm_smul_nonneg (n : ℕ) (α : ℝ) (hα : 0 ≤ α) (f : Fin n → ℝ) :
    empiricalNorm n (α • f) = α * empiricalNorm n f := by
  rw [empiricalNorm_smul, abs_of_nonneg hα]

/-- Scaled function stays in localized ball -/
lemma smul_mem_localizedBall_of_starShaped (n : ℕ) (H : Set (X → ℝ)) (δ t : ℝ)
    (hδ : 0 < δ) (ht : 0 < t) (hδt : δ ≤ t) (x : Fin n → X) (hH : IsStarShaped H)
    (h : X → ℝ) (hh : h ∈ localizedBall H t x) :
    ((δ / t) • h) ∈ localizedBall H δ x := by
  constructor
  · -- (δ/t) • h ∈ H because H is star-shaped
    have hα_nonneg : 0 ≤ δ / t := div_nonneg (le_of_lt hδ) (le_of_lt ht)
    have hα_le_one : δ / t ≤ 1 := div_le_one_of_le₀ hδt (le_of_lt ht)
    exact hH.2 h hh.1 (δ / t) hα_nonneg hα_le_one
  · -- ‖(δ/t) • h‖_n ≤ δ
    have hα_nonneg : 0 ≤ δ / t := div_nonneg (le_of_lt hδ) (le_of_lt ht)
    -- Show the evaluation equals the scaled version
    have h_norm_eq : empiricalNorm n (fun i => ((δ / t) • h) (x i)) =
        empiricalNorm n ((δ / t) • (fun i => h (x i))) := rfl
    rw [h_norm_eq, empiricalNorm_smul_nonneg n (δ / t) hα_nonneg]
    calc (δ / t) * empiricalNorm n (fun i => h (x i))
        ≤ (δ / t) * t := by
          apply mul_le_mul_of_nonneg_left hh.2 hα_nonneg
      _ = δ := by field_simp

/-- If H is star-shaped with 0 ∈ H, then 0 ∈ B_n(δ; H) for any δ ≥ 0 -/
lemma zero_mem_localizedBall_of_starShaped (n : ℕ) (H : Set (X → ℝ)) (δ : ℝ) (hδ : 0 ≤ δ)
    (x : Fin n → X) (hH : IsStarShaped H) :
    (0 : X → ℝ) ∈ localizedBall H δ x := by
  constructor
  · exact hH.1  -- 0 ∈ H from star-shaped property
  · -- ‖0‖_n = 0 ≤ δ
    simp only [Pi.zero_apply]
    unfold empiricalNorm
    simp only [sq, mul_zero, sum_const_zero, mul_zero, Real.sqrt_zero]
    exact hδ

/-! ## Gaussian Integrability -/

/-- Euclidean norm (L2 norm) for Fin n → ℝ -/
noncomputable def euclideanNorm (n : ℕ) (v : Fin n → ℝ) : ℝ :=
  Real.sqrt (∑ i, v i ^ 2)

lemma euclideanNorm_nonneg (n : ℕ) (v : Fin n → ℝ) : 0 ≤ euclideanNorm n v :=
  Real.sqrt_nonneg _

/-- Euclidean norm of Gaussian vector is integrable (Fernique's theorem consequence).
Uses lemmas from GaussianConcentration.lean. -/
lemma euclideanNorm_integrable_stdGaussianPi (n : ℕ) :
    Integrable (fun w : Fin n → ℝ => euclideanNorm n w) (stdGaussianPi n) := by
  -- Strategy: √(∑ wᵢ²) ≤ 1 + ∑ wᵢ², and ∑ wᵢ² is integrable under Gaussian product measure
  -- First, the sum of squares is integrable (using integrable_sq_eval_stdGaussianPi)
  have h_sum_sq_int : Integrable (fun w : Fin n → ℝ => ∑ i, w i ^ 2) (stdGaussianPi n) := by
    apply integrable_finset_sum
    intro i _
    exact integrable_sq_eval_stdGaussianPi i
  -- Bound: √x ≤ 1 + x for x ≥ 0
  have h_sqrt_bound : ∀ x : ℝ, 0 ≤ x → Real.sqrt x ≤ 1 + x := by
    intro x hx
    by_cases hx1 : x ≤ 1
    · -- For x ≤ 1, √x ≤ 1 ≤ 1 + x
      calc Real.sqrt x ≤ 1 := Real.sqrt_le_one.mpr hx1
        _ ≤ 1 + x := by linarith
    · -- For x > 1, √x ≤ x ≤ 1 + x
      push_neg at hx1
      calc Real.sqrt x ≤ x := by rw [Real.sqrt_le_left (by linarith : 0 ≤ x)]; nlinarith
        _ ≤ 1 + x := by linarith
  -- Apply integrability
  apply Integrable.mono' ((integrable_const (1 : ℝ)).add h_sum_sq_int)
  · -- AEStronglyMeasurable
    apply Measurable.aestronglyMeasurable
    apply Measurable.sqrt
    apply Finset.measurable_sum
    intro i _
    exact (measurable_pi_apply i).pow_const 2
  · -- ae bound
    filter_upwards with w
    rw [Real.norm_eq_abs, abs_of_nonneg (euclideanNorm_nonneg n w)]
    unfold euclideanNorm
    have hsum_nonneg : 0 ≤ ∑ i : Fin n, w i ^ 2 := Finset.sum_nonneg (fun i _ => sq_nonneg _)
    simp only [Pi.add_apply]
    exact h_sqrt_bound _ hsum_nonneg

/-- Cauchy-Schwarz for sums: |Σ a_i b_i| ≤ √(Σ aᵢ²) * √(Σ bᵢ²) -/
lemma inner_abs_le_norm_mul_norm' (n : ℕ) (a b : Fin n → ℝ) :
    |∑ i, a i * b i| ≤ Real.sqrt (∑ i, a i ^ 2) * Real.sqrt (∑ i, b i ^ 2) := by
  -- Use Real.sum_mul_le_sqrt_mul_sqrt for the upper bound
  have h_upper : ∑ i : Fin n, a i * b i ≤ √(∑ i, a i ^ 2) * √(∑ i, b i ^ 2) :=
    Real.sum_mul_le_sqrt_mul_sqrt Finset.univ a b
  -- For the lower bound, apply to (-a) and b: ∑(-a)b ≤ √(∑a²) * √(∑b²)
  have h_neg : ∑ i : Fin n, (-a i) * b i ≤ √(∑ i, (-a i) ^ 2) * √(∑ i, b i ^ 2) :=
    Real.sum_mul_le_sqrt_mul_sqrt Finset.univ (fun i => -a i) b
  -- Simplify: ∑(-a)b = -∑ab and (-a)² = a²
  have h_sum_neg : ∑ i : Fin n, (-a i) * b i = -∑ i, a i * b i := by
    simp only [neg_mul, Finset.sum_neg_distrib]
  have h_sq_neg : ∑ i : Fin n, (-a i) ^ 2 = ∑ i, a i ^ 2 := by
    apply Finset.sum_congr rfl
    intro i _; ring
  rw [h_sum_neg, h_sq_neg] at h_neg
  -- Combine: -(∑ab) ≤ √... means -√... ≤ ∑ab
  rw [abs_le]
  constructor
  · linarith [mul_nonneg (Real.sqrt_nonneg (∑ i : Fin n, a i ^ 2)) (Real.sqrt_nonneg (∑ i : Fin n, b i ^ 2))]
  · exact h_upper

/-- Empirical process is bounded by δ times normalized w norm -/
lemma empiricalProcess_le_delta_norm (n : ℕ) (hn : 0 < n) (x : Fin n → X) (H : Set (X → ℝ))
    (δ : ℝ) (hδ : 0 < δ) (g : X → ℝ) (hg : g ∈ localizedBall H δ x) (w : Fin n → ℝ) :
    |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)| ≤ δ / Real.sqrt n * euclideanNorm n w := by
  rw [abs_mul]
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have hn_ne : (n : ℝ) ≠ 0 := ne_of_gt hn_pos
  rw [abs_inv, abs_of_pos hn_pos]
  -- Define gx for cleaner notation
  let gx : Fin n → ℝ := fun i => g (x i)
  -- Cauchy-Schwarz: |∑ wᵢgᵢ| ≤ √(Σ wᵢ²) * √(Σ gᵢ²)
  have h_cs : |∑ i, w i * gx i| ≤ euclideanNorm n w * euclideanNorm n gx :=
    inner_abs_le_norm_mul_norm' n w gx
  -- euclideanNorm gx = √(Σ gᵢ²), and empiricalNorm = √(n⁻¹ Σ gᵢ²), so euclideanNorm = √n * empiricalNorm
  have h_norm_gx_sq : (euclideanNorm n gx)^2 = n * (empiricalNorm n gx)^2 := by
    unfold euclideanNorm empiricalNorm
    rw [sq_sqrt, sq_sqrt]
    · ring_nf
      rw [mul_inv_cancel₀ hn_ne, one_mul]
    · apply mul_nonneg (inv_nonneg.mpr (Nat.cast_nonneg n))
      exact Finset.sum_nonneg (fun i _ => sq_nonneg _)
    · exact Finset.sum_nonneg (fun i _ => sq_nonneg _)
  have h_norm_gx : euclideanNorm n gx ≤ Real.sqrt n * δ := by
    have h_sq : (euclideanNorm n gx)^2 ≤ n * δ^2 := by
      rw [h_norm_gx_sq]
      apply mul_le_mul_of_nonneg_left _ (Nat.cast_nonneg n)
      -- empiricalNorm n gx ≤ δ means empiricalNorm^2 ≤ δ^2 since both are non-negative
      have h1 : empiricalNorm n gx ≤ δ := hg.2
      have h2 : 0 ≤ empiricalNorm n gx := empiricalNorm_nonneg n gx
      exact sq_le_sq' (by linarith) h1
    have h_sqrt : euclideanNorm n gx ≤ Real.sqrt (n * δ^2) := by
      rw [← Real.sqrt_sq (euclideanNorm_nonneg _ _)]
      exact Real.sqrt_le_sqrt h_sq
    rw [Real.sqrt_mul (Nat.cast_nonneg n), Real.sqrt_sq (le_of_lt hδ)] at h_sqrt
    exact h_sqrt
  calc (n : ℝ)⁻¹ * |∑ i, w i * g (x i)|
      = (n : ℝ)⁻¹ * |∑ i, w i * gx i| := rfl
    _ ≤ (n : ℝ)⁻¹ * (euclideanNorm n w * euclideanNorm n gx) := by
        apply mul_le_mul_of_nonneg_left h_cs (inv_nonneg.mpr (Nat.cast_nonneg n))
    _ ≤ (n : ℝ)⁻¹ * (euclideanNorm n w * (Real.sqrt n * δ)) := by
        apply mul_le_mul_of_nonneg_left _ (inv_nonneg.mpr (Nat.cast_nonneg n))
        apply mul_le_mul_of_nonneg_left h_norm_gx (euclideanNorm_nonneg _ _)
    _ = δ / Real.sqrt n * euclideanNorm n w := by
        have hsqrt_pos : 0 < Real.sqrt n := Real.sqrt_pos.mpr hn_pos
        have hsqrt_ne : Real.sqrt n ≠ 0 := ne_of_gt hsqrt_pos
        -- n⁻¹ * (euclideanNorm * (√n * δ)) = δ / √n * euclideanNorm
        -- = n⁻¹ * √n * δ * euclideanNorm = (√n / n) * δ * euclideanNorm
        -- = (1 / √n) * δ * euclideanNorm = δ / √n * euclideanNorm
        calc (↑n)⁻¹ * (euclideanNorm n w * (√↑n * δ))
            = (↑n)⁻¹ * √↑n * δ * euclideanNorm n w := by ring
          _ = (√↑n)⁻¹ * δ * euclideanNorm n w := by
              -- n⁻¹ * √n = (√n * √n)⁻¹ * √n = (√n)⁻¹ * (√n)⁻¹ * √n = (√n)⁻¹
              have h : (↑n)⁻¹ * √↑n = (√↑n)⁻¹ := by
                have hn_eq : (↑n : ℝ) = √↑n * √↑n := (Real.mul_self_sqrt (Nat.cast_nonneg n)).symm
                rw [hn_eq]
                field_simp
                rw [Real.sqrt_sq (Real.sqrt_nonneg _)]
              rw [h]
          _ = δ / √↑n * euclideanNorm n w := by rw [div_eq_mul_inv, mul_comm δ]

/-- Helper: The supremum of |Z_g| over a localized ball is integrable under stdGaussianPi.

This follows from Cauchy-Schwarz: sup_{g ∈ B_n(δ)} |Z w g| ≤ δ * ‖w‖ / √n,
and the Gaussian norm is integrable by Fernique's theorem. -/
lemma localGaussianComplexity_integrand_integrable (n : ℕ) (H : Set (X → ℝ)) (δ : ℝ) (hδ : 0 < δ) (x : Fin n → X) :
    Integrable (fun w => ⨆ g ∈ localizedBall H δ x, |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)|) (stdGaussianPi n) := by
  by_cases hn : n = 0
  case pos =>
    subst hn
    convert integrable_zero (Fin 0 → ℝ) ℝ (stdGaussianPi 0) using 1
    ext w
    simp only [Nat.cast_zero, inv_zero, zero_mul, abs_zero]
    conv_lhs => rw [show (fun g => ⨆ (_ : g ∈ localizedBall H δ x), (0 : ℝ)) = fun _ => 0 from by
      ext g; by_cases hg : g ∈ localizedBall H δ x <;> simp [ciSup_neg, *]]
    exact Real.iSup_const_zero
  case neg =>
    push_neg at hn
    have hn_pos : 0 < n := Nat.pos_of_ne_zero hn
    have h_bound_int : Integrable (fun w => δ / Real.sqrt n * euclideanNorm n w) (stdGaussianPi n) :=
      (euclideanNorm_integrable_stdGaussianPi n).const_mul _
    apply Integrable.mono' h_bound_int
    · set F : (Fin n → ℝ) → ℝ := fun w => ⨆ g ∈ localizedBall H δ x, |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)|
      set f : (X → ℝ) → (Fin n → ℝ) → ℝ := fun g w => ⨆ (_ : g ∈ localizedBall H δ x),
          |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)|
      have h_bdd : ∀ w, BddAbove (Set.range fun g => f g w) := fun w => by
        use δ / Real.sqrt n * euclideanNorm n w
        intro r hr
        obtain ⟨g, rfl⟩ := hr
        by_cases hg : g ∈ localizedBall H δ x
        · show f g w ≤ _
          simp only [f, ciSup_pos hg]
          exact empiricalProcess_le_delta_norm n hn_pos x H δ hδ g hg w
        · show f g w ≤ _
          simp only [f, ciSup_neg hg, Real.sSup_empty]
          apply mul_nonneg (div_nonneg (le_of_lt hδ) (Real.sqrt_nonneg _)) (euclideanNorm_nonneg _ _)
      have h_lsc : LowerSemicontinuous F := by
        have heq : F = fun w => ⨆ g, f g w := by ext w; rfl
        rw [heq]; apply lowerSemicontinuous_ciSup h_bdd; intro g
        by_cases hg : g ∈ localizedBall H δ x
        · have heq2 : f g = (fun w => |(n : ℝ)⁻¹ * ∑ i : Fin n, w i * (g (x i))|) := by
            ext w; simp only [f, ciSup_pos hg]
          rw [heq2]; apply Continuous.lowerSemicontinuous; apply Continuous.abs
          apply continuous_const.mul; apply continuous_finset_sum _ (fun i _ => ?_)
          exact continuous_apply i |>.mul continuous_const
        · have heq2 : f g = (fun _ => (0 : ℝ)) := by
            ext w; simp only [f, ciSup_neg hg, Real.sSup_empty]
          rw [heq2]; exact lowerSemicontinuous_const
      exact h_lsc.measurable.aestronglyMeasurable
    · filter_upwards with w
      rw [Real.norm_eq_abs]
      have h_sup_nonneg : 0 ≤ ⨆ g ∈ localizedBall H δ x, |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)| := by
        apply Real.iSup_nonneg; intro g
        by_cases hg : g ∈ localizedBall H δ x
        · simp only [ciSup_pos hg]; exact abs_nonneg _
        · rw [ciSup_neg hg, Real.sSup_empty]
      rw [abs_of_nonneg h_sup_nonneg]
      apply Real.iSup_le
      · intro g; by_cases hg : g ∈ localizedBall H δ x
        · simp only [ciSup_pos hg]; exact empiricalProcess_le_delta_norm n hn_pos x H δ hδ g hg w
        · rw [ciSup_neg hg, Real.sSup_empty]
          apply mul_nonneg (div_nonneg (le_of_lt hδ) (Real.sqrt_nonneg _)) (euclideanNorm_nonneg _ _)
      · apply mul_nonneg (div_nonneg (le_of_lt hδ) (Real.sqrt_nonneg _)) (euclideanNorm_nonneg _ _)

/-- For star-shaped H, the function δ ↦ G_n(δ;H)/δ is non-increasing.

**Proof sketch**: Scaling h ↦ (δ/t)h maps B_n(t) into B_n(δ) and Z scales linearly. -/
lemma gaussian_complexity_ratio_antitone (n : ℕ) (H : Set (X → ℝ)) (x : Fin n → X)
    (hH : IsStarShaped H) (δ t : ℝ) (hδ : 0 < δ) (ht : 0 < t) (hδt : δ ≤ t) :
    LocalGaussianComplexity n H t x / t ≤ LocalGaussianComplexity n H δ x / δ := by
  unfold LocalGaussianComplexity
  have ht_ne : t ≠ 0 := ne_of_gt ht
  have hδ_ne : δ ≠ 0 := ne_of_gt hδ
  have hα : 0 < δ / t := div_pos hδ ht
  have htδ : 0 < t / δ := div_pos ht hδ
  have htδ_nonneg : 0 ≤ t / δ := le_of_lt htδ
  have h0_mem_t : (0 : X → ℝ) ∈ localizedBall H t x :=
    zero_mem_localizedBall_of_starShaped n H t (le_of_lt ht) x hH
  have h0_mem_δ : (0 : X → ℝ) ∈ localizedBall H δ x :=
    zero_mem_localizedBall_of_starShaped n H δ (le_of_lt hδ) x hH
  have hne_t : (localizedBall H t x).Nonempty := ⟨0, h0_mem_t⟩
  have hne_δ : (localizedBall H δ x).Nonempty := ⟨0, h0_mem_δ⟩
  set Z := fun (w : Fin n → ℝ) (g : X → ℝ) => |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)| with hZ_def
  have h_pointwise : ∀ w : Fin n → ℝ,
      ⨆ h ∈ localizedBall H t x, Z w h ≤ (t / δ) * ⨆ g ∈ localizedBall H δ x, Z w g := by
    intro w
    have h_rhs_nonneg : 0 ≤ (t / δ) * ⨆ g ∈ localizedBall H δ x, Z w g := by
      apply mul_nonneg htδ_nonneg
      apply Real.iSup_nonneg; intro g; apply Real.iSup_nonneg; intro _; exact abs_nonneg _
    apply Real.iSup_le _ h_rhs_nonneg; intro h
    apply Real.iSup_le _ h_rhs_nonneg; intro hh
    have h_scaled_mem : ((δ / t) • h) ∈ localizedBall H δ x :=
      smul_mem_localizedBall_of_starShaped n H δ t hδ ht hδt x hH h hh
    have h_Z_scale : Z w ((δ / t) • h) = (δ / t) * Z w h := by
      simp only [hZ_def, Pi.smul_apply, smul_eq_mul]
      have h_sum_eq : ∑ i : Fin n, w i * (δ / t * h (x i)) = (δ / t) * ∑ i, w i * h (x i) := by
        rw [Finset.mul_sum]; apply Finset.sum_congr rfl; intro i _; ring
      rw [h_sum_eq, ← mul_assoc, abs_mul, abs_mul, abs_of_pos hα, abs_mul]; ring
    have h_abs_scale : Z w h = (t / δ) * Z w ((δ / t) • h) := by
      rw [h_Z_scale]
      have h_td : t / δ * (δ / t) = 1 := by field_simp
      symm; calc t / δ * (δ / t * Z w h) = (t / δ * (δ / t)) * Z w h := by ring
        _ = 1 * Z w h := by rw [h_td]
        _ = Z w h := by ring
    rw [h_abs_scale]
    apply mul_le_mul_of_nonneg_left _ htδ_nonneg
    have hbdd : BddAbove (Set.range fun g => ⨆ (_ : g ∈ localizedBall H δ x), Z w g) := by
      use δ * empiricalNorm n (fun i => w i) + 1
      intro y hy
      obtain ⟨g, rfl⟩ := hy
      by_cases hg : g ∈ localizedBall H δ x
      · simp only [ciSup_pos hg]
        trans (δ * empiricalNorm n (fun i => w i))
        · -- Cauchy-Schwarz bound
          simp only [hZ_def]
          by_cases hn : n = 0
          · subst hn
            simp only [Nat.cast_zero, inv_zero, zero_mul, abs_zero]
            apply mul_nonneg (le_of_lt hδ) (empiricalNorm_nonneg 0 _)
          have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr (Nat.pos_of_ne_zero hn)
          have hn_nonneg : (0 : ℝ) ≤ n := le_of_lt hn_pos
          have hinv_nonneg : (0 : ℝ) ≤ (n : ℝ)⁻¹ := inv_nonneg.mpr hn_nonneg
          have hCS_upper := Real.sum_mul_le_sqrt_mul_sqrt Finset.univ (fun i => w i) (fun i => g (x i))
          have hCS_neg : ∑ i : Fin n, (-(w i)) * g (x i) ≤ √(∑ i : Fin n, (-(w i)) ^ 2) * √(∑ i : Fin n, g (x i) ^ 2) :=
            Real.sum_mul_le_sqrt_mul_sqrt Finset.univ (fun i => -(w i)) (fun i => g (x i))
          have hCS_neg' : -(∑ i : Fin n, w i * g (x i)) ≤ √(∑ i : Fin n, w i ^ 2) * √(∑ i : Fin n, g (x i) ^ 2) := by
            have h1 : ∑ i : Fin n, (-(w i)) * g (x i) = -(∑ i : Fin n, w i * g (x i)) := by
              simp only [neg_mul, Finset.sum_neg_distrib]
            have h2 : ∑ i : Fin n, (-(w i)) ^ 2 = ∑ i : Fin n, w i ^ 2 := by
              apply Finset.sum_congr rfl
              intro i _; ring
            rw [h1, h2] at hCS_neg
            exact hCS_neg
          have hCS : |∑ i : Fin n, w i * g (x i)| ≤ √(∑ i : Fin n, w i ^ 2) * √(∑ i : Fin n, g (x i) ^ 2) := by
            rw [abs_le]
            constructor
            · linarith [mul_nonneg (Real.sqrt_nonneg (∑ i : Fin n, w i ^ 2)) (Real.sqrt_nonneg (∑ i : Fin n, g (x i) ^ 2))]
            · exact hCS_upper
          calc |(n : ℝ)⁻¹ * ∑ i : Fin n, w i * g (x i)|
              = (n : ℝ)⁻¹ * |∑ i : Fin n, w i * g (x i)| := by
                rw [abs_mul, abs_of_nonneg hinv_nonneg]
            _ ≤ (n : ℝ)⁻¹ * (√(∑ i : Fin n, w i ^ 2) * √(∑ i : Fin n, g (x i) ^ 2)) := by
                apply mul_le_mul_of_nonneg_left hCS hinv_nonneg
            _ = (n : ℝ)⁻¹ * (√n * empiricalNorm n (fun i => w i)) *
                  (√n * empiricalNorm n (fun i => g (x i))) := by
                have heq : ∀ f : Fin n → ℝ, √(∑ i : Fin n, f i ^ 2) = √n * empiricalNorm n f := by
                  intro f
                  unfold empiricalNorm
                  symm
                  calc √n * √((n : ℝ)⁻¹ * ∑ i : Fin n, f i ^ 2)
                      = √n * (√((n : ℝ)⁻¹) * √(∑ i : Fin n, f i ^ 2)) := by
                        rw [Real.sqrt_mul (inv_nonneg.mpr hn_nonneg)]
                    _ = √n * ((√n)⁻¹ * √(∑ i : Fin n, f i ^ 2)) := by
                        rw [Real.sqrt_inv (n : ℝ)]
                    _ = (√n * (√n)⁻¹) * √(∑ i : Fin n, f i ^ 2) := by ring
                    _ = 1 * √(∑ i : Fin n, f i ^ 2) := by
                        rw [mul_inv_cancel₀ (Real.sqrt_ne_zero'.mpr hn_pos)]
                    _ = √(∑ i : Fin n, f i ^ 2) := by ring
                rw [heq, heq]
                ring
            _ = empiricalNorm n (fun i => w i) * empiricalNorm n (fun i => g (x i)) := by
                have hsqrt_cancel : (n : ℝ)⁻¹ * √n * √n = 1 := by
                  rw [mul_assoc, Real.mul_self_sqrt hn_nonneg]
                  exact inv_mul_cancel₀ (ne_of_gt hn_pos)
                calc (n : ℝ)⁻¹ * (√n * empiricalNorm n (fun i => w i)) *
                      (√n * empiricalNorm n (fun i => g (x i)))
                    = (n : ℝ)⁻¹ * √n * √n * empiricalNorm n (fun i => w i) *
                        empiricalNorm n (fun i => g (x i)) := by ring
                  _ = 1 * empiricalNorm n (fun i => w i) * empiricalNorm n (fun i => g (x i)) := by
                      rw [hsqrt_cancel]
                  _ = empiricalNorm n (fun i => w i) * empiricalNorm n (fun i => g (x i)) := by
                      ring
            _ ≤ empiricalNorm n (fun i => w i) * δ := by
                apply mul_le_mul_of_nonneg_left hg.2 (empiricalNorm_nonneg n _)
            _ = δ * empiricalNorm n (fun i => w i) := by ring
        · linarith
      · simp only [ciSup_neg hg]
        rw [Real.sSup_empty]
        apply add_nonneg
        · apply mul_nonneg (le_of_lt hδ) (empiricalNorm_nonneg _ _)
        · linarith
    apply le_ciSup_of_le hbdd ((δ / t) • h)
    simp only [ciSup_pos h_scaled_mem]
    exact le_refl _
  rw [div_le_div_iff₀ ht hδ]
  have hZ_eq_t : ∀ w, (⨆ h ∈ localizedBall H t x, |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)|) =
      ⨆ h ∈ localizedBall H t x, Z w h := by intro w; rfl
  have hZ_eq_δ : ∀ w, (⨆ g ∈ localizedBall H δ x, |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)|) =
      ⨆ g ∈ localizedBall H δ x, Z w g := by intro w; rfl
  simp only [hZ_eq_t, hZ_eq_δ]
  calc (∫ w, ⨆ h ∈ localizedBall H t x, Z w h ∂stdGaussianPi n) * δ
      ≤ (∫ w, (t / δ) * ⨆ g ∈ localizedBall H δ x, Z w g ∂stdGaussianPi n) * δ := by
        apply mul_le_mul_of_nonneg_right _ (le_of_lt hδ)
        apply integral_mono_of_nonneg
        · apply ae_of_all; intro w; exact Real.iSup_nonneg (fun _ => Real.iSup_nonneg (fun _ => abs_nonneg _))
        · apply Integrable.const_mul
          exact localGaussianComplexity_integrand_integrable n H δ hδ x
        · exact ae_of_all _ h_pointwise
    _ = (t / δ) * (∫ w, ⨆ g ∈ localizedBall H δ x, Z w g ∂stdGaussianPi n) * δ := by
        rw [← integral_const_mul]
    _ = (∫ w, ⨆ g ∈ localizedBall H δ x, Z w g ∂stdGaussianPi n) * t := by
        field_simp

/-! ## Absolute Value Bound (Integral Version) -/

/-- Gaussian symmetry: w and -w have the same distribution under stdGaussianPi.
This follows from the fact that gaussianReal 0 1 is symmetric under negation
(using gaussianReal_map_const_mul with c = -1) and this extends to product measures. -/
lemma stdGaussianPi_neg_symm (n : ℕ) :
    (stdGaussianPi n).map (fun w => -w) = stdGaussianPi n := by
  unfold stdGaussianPi
  -- Each gaussianReal 0 1 is neg-invariant, so the product measure is too
  have h_neg_inv : (Measure.pi fun _ : Fin n => gaussianReal (0 : ℝ) 1).IsNegInvariant :=
    Measure.pi.isNegInvariant _
  exact Measure.map_neg_eq_self _

/-- Z_0(w) = 0 for any w -/
lemma empiricalProcess_zero (n : ℕ) (x : Fin n → X) (w : Fin n → ℝ) :
    empiricalProcess n x 0 w = 0 := by
  unfold empiricalProcess
  simp

/-- For star-shaped H, E[sup |Z_g|] ≤ 2 E[sup Z_g] under Gaussian measure.

Uses Gaussian symmetry: E[sup(-Z_g)] = E[sup Z_g] since w and -w have the same distribution. -/
lemma integral_abs_sup_le_two_mul_integral_sup_of_starShaped (n : ℕ) (H : Set (X → ℝ)) (x : Fin n → X)
    (hH : IsStarShaped H)
    (hint_pos : Integrable (fun w => ⨆ g ∈ H, empiricalProcess n x g w) (stdGaussianPi n))
    (hint_neg : Integrable (fun w => ⨆ g ∈ H, -empiricalProcess n x g w) (stdGaussianPi n)) :
    ∫ w, ⨆ g ∈ H, |empiricalProcess n x g w| ∂(stdGaussianPi n) ≤
    2 * ∫ w, ⨆ g ∈ H, empiricalProcess n x g w ∂(stdGaussianPi n) := by
  let μ := stdGaussianPi n
  let Z := fun (g : X → ℝ) (w : Fin n → ℝ) => empiricalProcess n x g w
  have h0_mem : (0 : X → ℝ) ∈ H := hH.1
  have hZ0 : ∀ w, Z 0 w = 0 := fun w => empiricalProcess_zero n x w

  have h_nonneg_sup : ∀ (f : (X → ℝ) → ℝ), f 0 = 0 →
      (∀ hbdd : BddAbove (Set.range fun g => ⨆ (_ : g ∈ H), f g), 0 ≤ ⨆ g ∈ H, f g) := by
    intro f hf0 hbdd
    have : f 0 ≤ ⨆ g ∈ H, f g := by
      calc f 0 = ⨆ (_ : (0 : X → ℝ) ∈ H), f 0 := by simp [h0_mem]
        _ ≤ ⨆ g ∈ H, f g := le_ciSup hbdd 0
    linarith [hf0]

  have h_pointwise : ∀ w, ⨆ g ∈ H, |Z g w| ≤ (⨆ g ∈ H, Z g w) + (⨆ g ∈ H, -Z g w) := by
    intro w
    by_cases hbdd_abs : BddAbove (Set.range fun g => ⨆ (_ : g ∈ H), |Z g w|)
    case neg =>
      rw [Real.iSup_of_not_bddAbove hbdd_abs]
      apply add_nonneg
      · by_cases hbdd_pos : BddAbove (Set.range fun g => ⨆ (_ : g ∈ H), Z g w)
        · exact h_nonneg_sup (fun g => Z g w) (hZ0 w) hbdd_pos
        · rw [Real.iSup_of_not_bddAbove hbdd_pos]
      · by_cases hbdd_neg : BddAbove (Set.range fun g => ⨆ (_ : g ∈ H), -Z g w)
        · exact h_nonneg_sup (fun g => -Z g w) (by simp [hZ0 w]) hbdd_neg
        · rw [Real.iSup_of_not_bddAbove hbdd_neg]
    case pos =>
      have hbdd_pos : BddAbove (Set.range fun g => ⨆ (_ : g ∈ H), Z g w) := by
        obtain ⟨M, hM⟩ := hbdd_abs
        refine ⟨M, ?_⟩
        rintro _ ⟨g, rfl⟩
        by_cases hg : g ∈ H
        · simp only [ciSup_pos hg]
          have := hM ⟨g, rfl⟩
          simp only [ciSup_pos hg] at this
          exact (le_abs_self _).trans this
        · simp only [ciSup_neg hg, Real.sSup_empty]
          have := hM ⟨0, rfl⟩
          simp only [ciSup_pos h0_mem, abs_zero, hZ0] at this
          linarith
      have hbdd_neg : BddAbove (Set.range fun g => ⨆ (_ : g ∈ H), -Z g w) := by
        obtain ⟨M, hM⟩ := hbdd_abs
        refine ⟨M, ?_⟩
        rintro _ ⟨g, rfl⟩
        by_cases hg : g ∈ H
        · simp only [ciSup_pos hg]
          have := hM ⟨g, rfl⟩
          simp only [ciSup_pos hg] at this
          calc -Z g w ≤ |-Z g w| := le_abs_self _
            _ = |Z g w| := abs_neg _
            _ ≤ M := this
        · simp only [ciSup_neg hg, Real.sSup_empty]
          have := hM ⟨0, rfl⟩
          simp only [ciSup_pos h0_mem, abs_zero, hZ0] at this
          linarith

      have h_nonneg_pos : 0 ≤ ⨆ g ∈ H, Z g w := h_nonneg_sup (fun g => Z g w) (hZ0 w) hbdd_pos
      have h_nonneg_neg : 0 ≤ ⨆ g ∈ H, -Z g w := h_nonneg_sup (fun g => -Z g w) (by simp [hZ0 w]) hbdd_neg

      apply ciSup_le
      intro g
      by_cases hg : g ∈ H
      case neg =>
        simp only [ciSup_neg hg, Real.sSup_empty]
        exact add_nonneg h_nonneg_pos h_nonneg_neg
      case pos =>
        simp only [ciSup_pos hg]
        cases' abs_cases (Z g w) with h h
        · rw [h.1]
          have h1 : Z g w ≤ ⨆ h ∈ H, Z h w := by
            have : Z g w ≤ ⨆ (_ : g ∈ H), Z g w := by rw [ciSup_pos hg]
            exact le_ciSup_of_le hbdd_pos g this
          linarith
        · rw [h.1]
          have h1 : -Z g w ≤ ⨆ h ∈ H, -Z h w := by
            have : -Z g w ≤ ⨆ (_ : g ∈ H), -Z g w := by rw [ciSup_pos hg]
            exact le_ciSup_of_le hbdd_neg g this
          linarith

  calc ∫ w, ⨆ g ∈ H, |Z g w| ∂μ
      ≤ ∫ w, ((⨆ g ∈ H, Z g w) + (⨆ g ∈ H, -Z g w)) ∂μ := by
        apply integral_mono_of_nonneg
        · apply Filter.Eventually.of_forall
          intro w
          apply Real.iSup_nonneg
          intro g
          by_cases hg : g ∈ H
          · simp only [ciSup_pos hg]; exact abs_nonneg _
          · simp only [ciSup_neg hg, Real.sSup_empty]; exact le_refl 0
        · exact hint_pos.add hint_neg
        · exact Filter.Eventually.of_forall h_pointwise
    _ = ∫ w, (⨆ g ∈ H, Z g w) ∂μ + ∫ w, (⨆ g ∈ H, -Z g w) ∂μ := integral_add hint_pos hint_neg
    _ = ∫ w, (⨆ g ∈ H, Z g w) ∂μ + ∫ w, (⨆ g ∈ H, Z g w) ∂μ := by
        -- Gaussian symmetry: ∫ sup(-Z(w)) dμ = ∫ sup(Z(w)) dμ
        congr 1
        have h_neg_eq : ∀ g w, -Z g w = Z g (-w) := fun g w => by
          simp only [Z]; exact (empiricalProcess_neg_w n x g w).symm
        conv_lhs =>
          arg 2; ext w
          rw [show (⨆ g ∈ H, -Z g w) = (⨆ g ∈ H, Z g (-w)) by
            congr 1; ext g; congr 1; ext _; exact h_neg_eq g w]
        have h_map_eq : μ.map (fun w => -w) = μ := stdGaussianPi_neg_symm n
        have hmeas_neg : Measurable (fun w : Fin n → ℝ => -w) := measurable_neg
        have hf_aes : AEStronglyMeasurable (fun w => ⨆ g ∈ H, Z g w) μ :=
          hint_pos.aestronglyMeasurable
        have hf_aes' : AEStronglyMeasurable (fun w => ⨆ g ∈ H, Z g w) (μ.map (fun w => -w)) := by
          rw [h_map_eq]; exact hf_aes
        calc ∫ w, ⨆ g ∈ H, Z g (-w) ∂μ
            = ∫ w, ⨆ g ∈ H, Z g w ∂(μ.map (fun w => -w)) := by
              symm
              exact integral_map hmeas_neg.aemeasurable hf_aes'
          _ = ∫ w, ⨆ g ∈ H, Z g w ∂μ := by rw [h_map_eq]
    _ = 2 * ∫ w, (⨆ g ∈ H, Z g w) ∂μ := by ring

/-! ## Dudley's Bound for Empirical Process -/

/-- Key bound: |v i|² ≤ n · empiricalNorm² n v for any coordinate i -/
lemma EmpiricalSpace.coord_sq_le (n : ℕ) (i : Fin n) (v : EmpiricalSpace n) :
    (v i)^2 ≤ n * (empiricalNorm n v)^2 := by
  have hn_pos : 0 < n := Fin.pos i
  have hn_ne : (n : ℝ) ≠ 0 := Nat.cast_ne_zero.mpr (ne_of_gt hn_pos)
  unfold empiricalNorm
  rw [sq_sqrt (by positivity : 0 ≤ (n : ℝ)⁻¹ * ∑ j : Fin n, (v j)^2)]
  have h_single : (v i : ℝ)^2 ≤ ∑ j : Fin n, (v j : ℝ)^2 := by
    exact Finset.single_le_sum (f := fun j => (v j : ℝ)^2) (fun j _ => sq_nonneg _) (Finset.mem_univ i)
  calc (v i)^2 ≤ ∑ j : Fin n, (v j)^2 := h_single
    _ = n * ((n : ℝ)⁻¹ * ∑ j : Fin n, (v j)^2) := by field_simp

/-- Coordinate projection is continuous in EmpiricalSpace.
    The key bound is |v i| ≤ √n · empiricalNorm n v. -/
lemma EmpiricalSpace.continuous_coord (n : ℕ) (i : Fin n) :
    Continuous (fun v : EmpiricalSpace n => v i) := by
  rw [Metric.continuous_iff]
  intro v ε hε
  have hn_pos : 0 < (n : ℝ) := Nat.cast_pos.mpr (Fin.pos i)
  use ε / (Real.sqrt n + 1)
  refine ⟨by positivity, fun v' hdist => ?_⟩
  -- Need: |v' i - v i| < ε
  -- Key bound: |v' i - v i| ≤ √n · dist v' v
  have h_coord_bound : |v' i - v i| ≤ Real.sqrt n * dist v' v := by
    have h_sq : (v' i - v i)^2 ≤ n * (dist v' v)^2 := by
      have h := EmpiricalSpace.coord_sq_le n i (v' - v)
      simp at h
      convert h using 2
    have h1 : Real.sqrt ((v' i - v i)^2) ≤ Real.sqrt (n * (dist v' v)^2) :=
      Real.sqrt_le_sqrt h_sq
    have h2 : Real.sqrt (n * (dist v' v)^2) = Real.sqrt n * Real.sqrt ((dist v' v)^2) :=
      Real.sqrt_mul (Nat.cast_nonneg n) _
    have h3 : Real.sqrt ((dist v' v)^2) = |dist v' v| := Real.sqrt_sq_eq_abs _
    have h4 : |dist v' v| = dist v' v := abs_of_nonneg (EmpiricalSpace.dist_nonneg n v' v)
    rw [Real.sqrt_sq_eq_abs] at h1
    rw [h2, h3, h4] at h1
    exact h1
  have h_sqrt_pos : 0 < Real.sqrt n := Real.sqrt_pos.mpr hn_pos
  calc |v' i - v i|
      ≤ Real.sqrt n * dist v' v := h_coord_bound
    _ < Real.sqrt n * (ε / (Real.sqrt n + 1)) := by
        apply mul_lt_mul_of_pos_left hdist h_sqrt_pos
    _ ≤ ε := by
        have h1 : Real.sqrt n ≤ Real.sqrt n + 1 := le_add_of_nonneg_right (by norm_num)
        have h2 : Real.sqrt n + 1 > 0 := by linarith
        calc Real.sqrt n * (ε / (Real.sqrt n + 1))
            = ε * (Real.sqrt n / (Real.sqrt n + 1)) := by ring
          _ ≤ ε * 1 := by nlinarith [div_le_one_of_le₀ h1 (le_of_lt h2)]
          _ = ε := mul_one ε

/-- Auxiliary: innerProductProcess is Lipschitz continuous in v for fixed w -/
lemma innerProductProcess_continuous_v (n : ℕ) (w : Fin n → ℝ) :
    Continuous (fun v : EmpiricalSpace n => innerProductProcess n v w) := by
  unfold innerProductProcess
  refine Continuous.mul continuous_const ?_
  refine continuous_finset_sum _ (fun i _ => ?_)
  exact Continuous.mul continuous_const (EmpiricalSpace.continuous_coord n i)

/-- Auxiliary: innerProductProcess differences are integrable under stdGaussianPi -/
lemma innerProductProcess_diff_integrable (n : ℕ) (v₁ v₂ : EmpiricalSpace n) :
    Integrable (fun w => innerProductProcess n v₁ w - innerProductProcess n v₂ w)
      (stdGaussianPi n) := by
  have h_eq : ∀ w, innerProductProcess n v₁ w - innerProductProcess n v₂ w =
      innerProductProcess n (v₁ - v₂) w := innerProductProcess_sub n v₁ v₂
  simp_rw [h_eq]
  unfold innerProductProcess
  apply Integrable.const_mul
  apply integrable_finset_sum
  intro i _
  -- ∫ wᵢ * (v₁ - v₂)ᵢ dμ: linear in wᵢ, which has finite second moment
  apply Integrable.mul_const
  exact integrable_eval_stdGaussianPi i

/-- Auxiliary: innerProductProcess has centered increments under stdGaussianPi -/
lemma innerProductProcess_increment_centered (n : ℕ) (v₁ v₂ : EmpiricalSpace n) :
    ∫ w, (innerProductProcess n v₁ w - innerProductProcess n v₂ w) ∂(stdGaussianPi n) = 0 := by
  have h_eq : ∀ w, innerProductProcess n v₁ w - innerProductProcess n v₂ w =
      innerProductProcess n (v₁ - v₂) w := innerProductProcess_sub n v₁ v₂
  simp_rw [h_eq]
  unfold innerProductProcess
  rw [integral_const_mul]
  have h : ∫ w, ∑ i, w i * (v₁ - v₂) i ∂(stdGaussianPi n) = 0 := by
    rw [integral_finset_sum]
    · apply Finset.sum_eq_zero
      intro i _
      rw [integral_mul_const]
      have h_eval_zero := integral_eval_stdGaussianPi i
      rw [h_eval_zero, zero_mul]
    · intro i _
      apply Integrable.mul_const
      exact integrable_eval_stdGaussianPi i
  rw [h, mul_zero]

/-- Auxiliary: innerProductProcess exp integrability for MGF bound -/
lemma innerProductProcess_exp_integrable (n : ℕ) (v₁ v₂ : EmpiricalSpace n) (l : ℝ) :
    Integrable (fun w => Real.exp (l * (innerProductProcess n v₁ w - innerProductProcess n v₂ w)))
      (stdGaussianPi n) := by
  have h_eq : ∀ w, innerProductProcess n v₁ w - innerProductProcess n v₂ w =
      innerProductProcess n (v₁ - v₂) w := innerProductProcess_sub n v₁ v₂
  simp_rw [h_eq]
  -- The exponent is a linear combination of Gaussians, so exp is integrable
  -- Use integrable_exp_mul_linear_stdGaussianPi from GaussianConcentration.lean
  unfold innerProductProcess
  -- l * (n⁻¹ * ∑ wᵢ dᵢ) = l * ∑ (n⁻¹ * dᵢ) * wᵢ, which matches the linear form
  -- Set d = v₁ - v₂ and a = n⁻¹ * d
  set d : EmpiricalSpace n := v₁ - v₂
  set a : Fin n → ℝ := fun i => (n : ℝ)⁻¹ * d i with ha_def
  have h_rewrite : ∀ w : Fin n → ℝ, l * ((n : ℝ)⁻¹ * ∑ i, w i * d i) = l * ∑ i, a i * w i := by
    intro w
    simp only [ha_def]
    rw [Finset.mul_sum]
    congr 1
    apply Finset.sum_congr rfl
    intro i _
    ring
  simp_rw [h_rewrite]
  exact integrable_exp_mul_linear_stdGaussianPi a l

/-- Auxiliary: innerProductProcess is measurable -/
lemma innerProductProcess_measurable (n : ℕ) (v : EmpiricalSpace n) :
    Measurable (fun w => innerProductProcess n v w) := by
  unfold innerProductProcess
  apply Measurable.const_mul
  apply Finset.measurable_sum
  intro i _
  apply Measurable.mul
  · exact measurable_pi_apply i
  · exact measurable_const

/-- Dudley's bound for the empirical process:
E[sup_{g ∈ G} Z_g] ≤ (12√2)/√n · ∫₀^D √(log N(ε, G_x)) dε. -/
lemma dudley_empiricalProcess (n : ℕ) (hn : 0 < n) (x : Fin n → X)
    (G : Set (X → ℝ))
    (hG_tb : TotallyBounded (empiricalMetricImage n x '' G))
    (D : ℝ) (hD : 0 < D)
    (hdiam : Metric.diam (empiricalMetricImage n x '' G) ≤ D)
    -- Base point hypotheses
    (g₀ : X → ℝ) (hg₀ : g₀ ∈ G) (hcenter : ∀ i, g₀ (x i) = 0)
    -- Entropy finiteness
    (hfinite : entropyIntegralENNReal (empiricalMetricImage n x '' G) D ≠ ⊤)
    -- Continuity in index
    (hcont : ∀ w, Continuous (fun (v : ↥(empiricalMetricImage n x '' G)) =>
      innerProductProcess n v.1 w)) :
    ∫ w, ⨆ g ∈ G, empiricalProcess n x g w ∂(stdGaussianPi n) ≤
    (12 * Real.sqrt 2) * (1 / Real.sqrt n) * entropyIntegral (empiricalMetricImage n x '' G) D := by
  -- Setup
  let μ := stdGaussianPi n
  let Gx := empiricalMetricImage n x '' G
  let Z := fun (v : EmpiricalSpace n) (w : Fin n → ℝ) => innerProductProcess n v w
  let σ := subGaussianParam n
  let v₀ := empiricalMetricImage n x g₀
  -- Key facts
  haveI : IsProbabilityMeasure μ := stdGaussianPi_isProbabilityMeasure
  have hσ : 0 < σ := by
    unfold σ subGaussianParam
    apply div_pos one_pos
    exact Real.sqrt_pos.mpr (Nat.cast_pos.mpr hn)
  -- Derive G.Nonempty from hg₀
  have hG_ne : G.Nonempty := ⟨g₀, hg₀⟩
  have hv₀_mem : v₀ ∈ Gx := ⟨g₀, hg₀, rfl⟩
  have hv₀_center : ∀ w, Z v₀ w = 0 := by
    intro w
    unfold Z v₀ innerProductProcess empiricalMetricImage
    simp only [hcenter, mul_zero, Finset.sum_const_zero, mul_zero]
  have hX : IsSubGaussianProcess μ Z σ := innerProductProcess_isSubGaussianProcess n hn
  have hX_meas : ∀ v, Measurable (Z v) := innerProductProcess_measurable n
  have hX_int_exp : ∀ v₁ v₂ : EmpiricalSpace n, ∀ l : ℝ,
      Integrable (fun w => Real.exp (l * (Z v₁ w - Z v₂ w))) μ :=
    innerProductProcess_exp_integrable n
  have hcont' : ∀ w, Continuous (fun (v : ↥Gx) => Z v.1 w) := hcont
  have h_sup_eq : ∀ w, (⨆ g ∈ G, empiricalProcess n x g w) =
      ⨆ v ∈ Gx, innerProductProcess n v w := fun w => by
    have h_eq : ∀ g, empiricalProcess n x g w = innerProductProcess n (empiricalMetricImage n x g) w :=
      fun g => empiricalProcess_eq_innerProductProcess n x g w
    simp_rw [h_eq]
    simp only [Gx]
    have hG_nonempty : G.Nonempty := hG_ne
    have h_bdd : BddAbove (Set.range fun (g : ↥G) => innerProductProcess n (empiricalMetricImage n x g.1) w) := by
      use Real.sqrt (∑ i, (w i)^2) * D + 1
      intro y hy
      obtain ⟨⟨g, hg⟩, rfl⟩ := hy
      unfold innerProductProcess empiricalMetricImage
      simp only
      have h_cs_upper : ∑ i : Fin n, w i * g (x i) ≤
          Real.sqrt (∑ i, (w i)^2) * Real.sqrt (∑ i, (g (x i))^2) :=
        Real.sum_mul_le_sqrt_mul_sqrt Finset.univ (fun i => w i) (fun i => g (x i))
      have h_cs_lower : -∑ i : Fin n, w i * g (x i) ≤
          Real.sqrt (∑ i, (w i)^2) * Real.sqrt (∑ i, (g (x i))^2) := by
        have h : ∑ i : Fin n, (-w i) * g (x i) ≤
            Real.sqrt (∑ i, (-w i)^2) * Real.sqrt (∑ i, (g (x i))^2) :=
          Real.sum_mul_le_sqrt_mul_sqrt Finset.univ (fun i => -w i) (fun i => g (x i))
        simp only [neg_sq, neg_mul, Finset.sum_neg_distrib] at h
        exact h
      have h_cs : |∑ i, w i * g (x i)| ≤ Real.sqrt (∑ i, (w i)^2) * Real.sqrt (∑ i, (g (x i))^2) :=
        abs_le.mpr ⟨by linarith, h_cs_upper⟩
      have h_mem : empiricalMetricImage n x g ∈ Gx := ⟨g, hg, rfl⟩
      have h_diam := Metric.dist_le_diam_of_mem (TotallyBounded.isBounded hG_tb) hv₀_mem h_mem
      have hv₀_zero : v₀ = 0 := by
        funext i
        simp only [v₀, empiricalMetricImage]
        exact hcenter i
      rw [hv₀_zero] at h_diam
      have h_dist_zero : dist (0 : EmpiricalSpace n) (empiricalMetricImage n x g) =
          empiricalNorm n (fun i => g (x i)) := by
        have h_dist_eq : dist (0 : EmpiricalSpace n) (empiricalMetricImage n x g) =
            empiricalNorm n ((0 : EmpiricalSpace n) - empiricalMetricImage n x g) := rfl
        rw [h_dist_eq]
        have h_sub : (0 : EmpiricalSpace n) - empiricalMetricImage n x g =
            -(empiricalMetricImage n x g) := by
          funext i
          show (0 : ℝ) - empiricalMetricImage n x g i = -(empiricalMetricImage n x g i)
          ring
        rw [h_sub, empiricalNorm_neg]
        rfl
      rw [h_dist_zero] at h_diam
      have h_norm_bound : empiricalNorm n (fun i => g (x i)) ≤ D := le_trans h_diam hdiam
      have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
      have hD_nonneg : 0 ≤ D := le_of_lt hD
      have h_sum_sq : ∑ i, (g (x i))^2 ≤ n * D^2 := by
        have h1 : empiricalNorm n (fun i => g (x i)) = Real.sqrt ((n : ℝ)⁻¹ * ∑ i, (g (x i))^2) := rfl
        have h_norm_nonneg : 0 ≤ empiricalNorm n (fun i => g (x i)) := by
          unfold empiricalNorm
          positivity
        have h2 : (empiricalNorm n (fun i => g (x i)))^2 ≤ D^2 := by
          apply sq_le_sq'
          · linarith
          · exact h_norm_bound
        rw [h1, sq_sqrt (by positivity)] at h2
        have h3 : (n : ℝ)⁻¹ * ∑ i, (g (x i))^2 ≤ D^2 := h2
        have hn_ne : (n : ℝ) ≠ 0 := ne_of_gt hn_pos
        calc ∑ i, (g (x i))^2 = n * ((n : ℝ)⁻¹ * ∑ i, (g (x i))^2) := by field_simp
          _ ≤ n * D^2 := by apply mul_le_mul_of_nonneg_left h3 (le_of_lt hn_pos)
      have h_sqrt_sum : Real.sqrt (∑ i, (g (x i))^2) ≤ Real.sqrt n * D := by
        have h1 : Real.sqrt n * D = Real.sqrt n * Real.sqrt (D^2) := by
          rw [Real.sqrt_sq hD_nonneg]
        have h2 : Real.sqrt n * Real.sqrt (D^2) = Real.sqrt (n * D^2) := by
          rw [← Real.sqrt_mul (Nat.cast_nonneg n)]
        rw [h1, h2]
        exact Real.sqrt_le_sqrt h_sum_sq
      have hn_inv_nonneg : 0 ≤ (n : ℝ)⁻¹ := by positivity
      have hsqrt_w_nonneg : 0 ≤ Real.sqrt (∑ i, (w i)^2) := Real.sqrt_nonneg _
      have h_abs_bound : |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)| ≤ Real.sqrt (∑ i, (w i)^2) * D := by
        calc |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)|
            = (n : ℝ)⁻¹ * |∑ i, w i * g (x i)| := by rw [abs_mul, abs_of_nonneg hn_inv_nonneg]
          _ ≤ (n : ℝ)⁻¹ * (Real.sqrt (∑ i, (w i)^2) * Real.sqrt (∑ i, (g (x i))^2)) := by
              apply mul_le_mul_of_nonneg_left h_cs hn_inv_nonneg
          _ ≤ (n : ℝ)⁻¹ * (Real.sqrt (∑ i, (w i)^2) * (Real.sqrt n * D)) := by
              apply mul_le_mul_of_nonneg_left _ hn_inv_nonneg
              apply mul_le_mul_of_nonneg_left h_sqrt_sum hsqrt_w_nonneg
          _ = Real.sqrt (∑ i, (w i)^2) * D / Real.sqrt n := by
              rw [mul_comm (Real.sqrt n) D, ← mul_assoc]
              have hsqrt_ne : Real.sqrt n ≠ 0 := Real.sqrt_ne_zero'.mpr hn_pos
              have h_sqrt_sq : Real.sqrt n * Real.sqrt n = n := Real.mul_self_sqrt (le_of_lt hn_pos)
              field_simp
              rw [sq, h_sqrt_sq]; ring
          _ ≤ Real.sqrt (∑ i, (w i)^2) * D := by
              have h_prod_nonneg : 0 ≤ Real.sqrt (∑ i, (w i)^2) * D := by positivity
              apply div_le_self h_prod_nonneg
              have h_one_le_n : 1 ≤ (n : ℝ) := Nat.one_le_cast.mpr hn
              exact Real.one_le_sqrt.mpr h_one_le_n
      have h_lt : (n : ℝ)⁻¹ * ∑ i, w i * g (x i) < Real.sqrt (∑ i, (w i)^2) * D + 1 :=
        calc (n : ℝ)⁻¹ * ∑ i, w i * g (x i)
            ≤ |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)| := le_abs_self _
          _ ≤ Real.sqrt (∑ i, (w i)^2) * D := h_abs_bound
          _ < Real.sqrt (∑ i, (w i)^2) * D + 1 := by linarith
      exact le_of_lt h_lt
    have h_ssup : sSup ∅ ≤ ⨆ (g : ↥G), innerProductProcess n (empiricalMetricImage n x g.1) w := by
      simp only [Real.sSup_empty]
      obtain ⟨g', hg'⟩ := hG_nonempty
      calc (0 : ℝ) = innerProductProcess n v₀ w := (hv₀_center w).symm
        _ ≤ ⨆ (g : ↥G), innerProductProcess n (empiricalMetricImage n x g.1) w := by
            apply le_ciSup h_bdd ⟨g₀, hg₀⟩
    haveI : Nonempty (X → ℝ) := ⟨fun _ => 0⟩
    haveI : Nonempty (EmpiricalSpace n) := ⟨0⟩
    have h_ciSup := @ciSup_image ℝ (X → ℝ) (EmpiricalSpace n) _ _ _ G hG_nonempty
      (empiricalMetricImage n x) (fun v => innerProductProcess n v w) h_bdd h_ssup
    exact h_ciSup.symm
  conv_lhs =>
    arg 2
    ext w
    rw [h_sup_eq w]
  have h_dudley := @dudley (Fin n → ℝ) _ (EmpiricalSpace n) _ μ _ Z σ hσ hX
    Gx hG_tb D hD hdiam v₀ hv₀_mem hv₀_center hX_meas hX_int_exp hfinite hcont'
  have hσ_eq : σ = 1 / Real.sqrt n := rfl
  rw [hσ_eq] at h_dudley
  calc ∫ w, ⨆ v ∈ Gx, Z v w ∂μ
      ≤ (12 * Real.sqrt 2) * σ * entropyIntegral Gx D := h_dudley
    _ = (12 * Real.sqrt 2) * (1 / Real.sqrt n) * entropyIntegral Gx D := by rw [hσ_eq]

/-! ## Local Gaussian Complexity Bound -/

/-- The localized ball inherits star-shapedness from the parent set -/
lemma localizedBall_isStarShaped (n : ℕ) (H : Set (X → ℝ)) (δ : ℝ) (hδ : 0 ≤ δ) (x : Fin n → X)
    (hH : IsStarShaped H) : IsStarShaped (localizedBall H δ x) := by
  constructor
  · constructor
    · exact hH.1
    · have h : (fun i : Fin n => (0 : X → ℝ) (x i)) = 0 := by ext; simp
      rw [h, empiricalNorm_zero]
      exact hδ
  · intro h ⟨hh_mem, hh_norm⟩ α hα_nonneg hα_le
    constructor
    · exact hH.2 h hh_mem α hα_nonneg hα_le
    · have h_scale : empiricalNorm n (fun i => (α • h) (x i)) =
          |α| * empiricalNorm n (fun i => h (x i)) := by
        simp only [Pi.smul_apply, smul_eq_mul]
        exact empiricalNorm_smul n α _
      rw [h_scale]
      calc |α| * empiricalNorm n (fun i => h (x i))
          ≤ 1 * empiricalNorm n (fun i => h (x i)) := by
            apply mul_le_mul_of_nonneg_right (abs_le.mpr ⟨_, hα_le⟩) (empiricalNorm_nonneg _ _)
            linarith
        _ = empiricalNorm n (fun i => h (x i)) := one_mul _
        _ ≤ δ := hh_norm

/-- Local Gaussian complexity is bounded by entropy integral times (24√2)/√n.

This is Lemma 5.2 from the plan: combines Dudley's bound with the |Z| ≤ 2·sup Z bound. -/
lemma local_gaussian_complexity_bound (n : ℕ) (hn : 0 < n) (H : Set (X → ℝ))
    (δ : ℝ) (hδ : 0 < δ) (x : Fin n → X)
    (hH_star : IsStarShaped H)
    -- Hypotheses for Dudley application
    (hH_tb : TotallyBounded (empiricalMetricImage n x '' localizedBall H δ x))
    (hfinite : entropyIntegralENNReal (empiricalMetricImage n x '' localizedBall H δ x) (2*δ) ≠ ⊤)
    (hcont : ∀ w, Continuous (fun (v : ↥(empiricalMetricImage n x '' localizedBall H δ x)) =>
      innerProductProcess n v.1 w))
    -- Integrability hypotheses for the |Z| ≤ 2·sup Z bound
    (hint_pos : Integrable (fun w => ⨆ g ∈ localizedBall H δ x, empiricalProcess n x g w)
      (stdGaussianPi n))
    (hint_neg : Integrable (fun w => ⨆ g ∈ localizedBall H δ x, -empiricalProcess n x g w)
      (stdGaussianPi n)) :
    LocalGaussianComplexity n H δ x ≤
    (24 * Real.sqrt 2) / Real.sqrt n * entropyIntegral (empiricalMetricImage n x '' localizedBall H δ x) (2*δ) := by
  let G := localizedBall H δ x
  let Gx := empiricalMetricImage n x '' G
  let μ := stdGaussianPi n
  haveI : IsProbabilityMeasure μ := stdGaussianPi_isProbabilityMeasure
  have hG_star : IsStarShaped G := localizedBall_isStarShaped n H δ (le_of_lt hδ) x hH_star
  have h0_G : (0 : X → ℝ) ∈ G := hG_star.1
  have hD : 0 < 2 * δ := by linarith
  have hdiam : Metric.diam Gx ≤ 2 * δ := localizedBall_diam n H δ (le_of_lt hδ) x
  have h0_center : ∀ i, (0 : X → ℝ) (x i) = 0 := fun _ => rfl
  unfold LocalGaussianComplexity
  have h_abs_bound := integral_abs_sup_le_two_mul_integral_sup_of_starShaped n G x hG_star hint_pos hint_neg
  have h_dudley := dudley_empiricalProcess n hn x G hH_tb (2*δ) hD hdiam
    (0 : X → ℝ) h0_G h0_center hfinite hcont
  calc ∫ w, ⨆ h ∈ G, |(n : ℝ)⁻¹ * ∑ i, w i * h (x i)| ∂μ
      = ∫ w, ⨆ h ∈ G, |empiricalProcess n x h w| ∂μ := by congr 1
    _ ≤ 2 * ∫ w, ⨆ h ∈ G, empiricalProcess n x h w ∂μ := h_abs_bound
    _ ≤ 2 * ((12 * Real.sqrt 2) * (1 / Real.sqrt n) * entropyIntegral Gx (2*δ)) := by
        apply mul_le_mul_of_nonneg_left h_dudley (by norm_num : (0 : ℝ) ≤ 2)
    _ = (24 * Real.sqrt 2) / Real.sqrt n * entropyIntegral Gx (2*δ) := by ring

end LeastSquares


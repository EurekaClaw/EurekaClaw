/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import Mathlib
import SLT.LeastSquares.Defs
import SLT.GaussianMeasure

/-!
# Sub-Gaussianity of the Empirical Process

This file establishes that the empirical process Z_g = (1/n) Σᵢ wᵢ g(xᵢ)
is sub-Gaussian with parameter τ = 1/√n when w ~ stdGaussianPi n.

## Main Results

* `empiricalProcess` - Definition of Z_g = (1/n) Σᵢ wᵢ g(xᵢ)
* `empiricalProcess_increment_mgf` - MGF of Z_{g₁} - Z_{g₂}
* `empiricalProcess_isSubGaussian` - Z_g is sub-Gaussian with τ = 1/√n

-/

open MeasureTheory Finset BigOperators Real ProbabilityTheory GaussianMeasure

namespace LeastSquares

variable {X : Type*}

/-! ## Empirical Process -/

/-- The empirical process Z_g = (1/n) Σᵢ wᵢ g(xᵢ).
This is the key object whose sub-Gaussianity we establish. -/
noncomputable def empiricalProcess (n : ℕ) (x : Fin n → X) (g : X → ℝ) (w : Fin n → ℝ) : ℝ :=
  (n : ℝ)⁻¹ * ∑ i, w i * g (x i)

/-- Alternative form: empiricalProcess as sum with coefficients -/
lemma empiricalProcess_eq_sum (n : ℕ) (x : Fin n → X) (g : X → ℝ) (w : Fin n → ℝ) :
    empiricalProcess n x g w = ∑ i, (n : ℝ)⁻¹ * g (x i) * w i := by
  unfold empiricalProcess
  rw [Finset.mul_sum]
  apply sum_congr rfl
  intro i _
  ring

/-- Empirical process is linear in g -/
lemma empiricalProcess_sub (n : ℕ) (x : Fin n → X) (g₁ g₂ : X → ℝ) (w : Fin n → ℝ) :
    empiricalProcess n x g₁ w - empiricalProcess n x g₂ w =
    empiricalProcess n x (fun y => g₁ y - g₂ y) w := by
  simp only [empiricalProcess, ← Finset.sum_sub_distrib, ← mul_sub, mul_comm (w _), sub_mul]

/-- Negating w negates the empirical process -/
lemma empiricalProcess_neg_w (n : ℕ) (x : Fin n → X) (g : X → ℝ) (w : Fin n → ℝ) :
    empiricalProcess n x g (fun i => -(w i)) = -empiricalProcess n x g w := by
  unfold empiricalProcess
  simp only [neg_mul, Finset.sum_neg_distrib, mul_neg]


/-! ## Empirical Process Increment Distribution

The increment Z_{g₁} - Z_{g₂} has MGF matching a centered Gaussian with variance ‖g₁ - g₂‖_n²/n.
-/

/-- Helper: the difference function values -/
def diffValues (n : ℕ) (x : Fin n → X) (g₁ g₂ : X → ℝ) : Fin n → ℝ :=
  fun i => g₁ (x i) - g₂ (x i)

/-- The increment Z_{g₁} - Z_{g₂} equals the weighted sum (1/n) Σᵢ wᵢ dᵢ
where dᵢ = g₁(xᵢ) - g₂(xᵢ) -/
lemma empiricalProcess_increment_eq_weighted_sum (n : ℕ) (x : Fin n → X)
    (g₁ g₂ : X → ℝ) (w : Fin n → ℝ) :
    empiricalProcess n x g₁ w - empiricalProcess n x g₂ w =
    ∑ i, (n : ℝ)⁻¹ * (diffValues n x g₁ g₂ i) * w i := by
  rw [empiricalProcess_sub, empiricalProcess_eq_sum]
  unfold diffValues
  rfl

/-- Variance of the increment equals ‖g₁ - g₂‖_n² / n -/
lemma empiricalProcess_increment_variance (n : ℕ) (x : Fin n → X)
    (g₁ g₂ : X → ℝ) :
    ∑ i, ((n : ℝ)⁻¹ * (diffValues n x g₁ g₂ i))^2 =
    (empiricalNorm n (diffValues n x g₁ g₂))^2 / n := by
  rw [empiricalNorm_sq n (diffValues n x g₁ g₂)]
  -- Expand LHS: ∑ (n⁻¹ * d_i)² = ∑ n⁻² * d_i² = n⁻² * ∑ d_i²
  have h_lhs : ∑ i, ((n : ℝ)⁻¹ * diffValues n x g₁ g₂ i)^2 =
      (n : ℝ)⁻¹ * (n : ℝ)⁻¹ * ∑ i, (diffValues n x g₁ g₂ i)^2 := by
    simp_rw [mul_pow, ← Finset.mul_sum]
    ring
  rw [h_lhs, div_eq_mul_inv]
  ring

/-! ## MGF Bound for Empirical Process

We show E[exp(t (Z_{g₁} - Z_{g₂}))] = exp(t² ‖g₁-g₂‖_n² / (2n))
which is exactly exp(t² τ² ‖g₁-g₂‖_n² / 2) with τ = 1/√n.
-/

/-- MGF of the empirical process increment. -/
lemma empiricalProcess_increment_mgf (n : ℕ) [NeZero n] (x : Fin n → X)
    (g₁ g₂ : X → ℝ) (t : ℝ) :
    ∫ w, Real.exp (t * (empiricalProcess n x g₁ w - empiricalProcess n x g₂ w))
      ∂(stdGaussianPi n) =
    Real.exp (t^2 * (empiricalNorm n (diffValues n x g₁ g₂))^2 / (2 * n)) := by
  -- Expand the increment as weighted sum
  conv_lhs =>
    arg 2
    ext w
    rw [empiricalProcess_increment_eq_weighted_sum]
  -- Set up coefficients a_i = d_i / n
  set a : Fin n → ℝ := fun i => (n : ℝ)⁻¹ * (diffValues n x g₁ g₂ i)
  -- Step 1: Convert exponent to form t * ∑ᵢ aᵢ * wᵢ
  have h_exp_form : ∀ w : Fin n → ℝ, t * ∑ i, a i * w i = ∑ i, t * a i * w i := fun w => by
    rw [Finset.mul_sum]
    congr 1
    ext i
    ring
  -- Step 2: Use exp_sum to convert exp(∑) to ∏ exp
  have h_exp_prod : ∀ w : Fin n → ℝ,
      Real.exp (∑ i, t * a i * w i) = ∏ i : Fin n, Real.exp (t * a i * w i) := fun w => by
    exact Real.exp_sum (Finset.univ) (fun i => t * a i * w i)
  -- Step 3: Rewrite the integral
  conv_lhs =>
    arg 2
    ext w
    rw [h_exp_form, h_exp_prod]
  -- Step 4: Expand stdGaussianPi and use Fubini
  unfold stdGaussianPi
  -- Use integral_fin_nat_prod_eq_prod to factor the integral
  have h_fubini : (∫ w : (i : Fin n) → ℝ, ∏ i, Real.exp (t * a i * w i) ∂(Measure.pi fun _ => gaussianReal 0 1)) =
      ∏ i : Fin n, ∫ x : ℝ, Real.exp (t * a i * x) ∂(gaussianReal 0 1) := by
    exact integral_fin_nat_prod_eq_prod (fun i x => Real.exp (t * a i * x))
  rw [h_fubini]
  -- Step 5: Compute each factor using mgf_gaussianReal
  -- Each integral ∫ exp(t * aᵢ * x) d(gaussianReal 0 1) = exp((t * aᵢ)² / 2)
  have h_mgf : ∀ i : Fin n, ∫ x : ℝ, Real.exp (t * a i * x) ∂(gaussianReal 0 1) =
      Real.exp ((t * a i)^2 / 2) := fun i => by
    have h_map : Measure.map id (gaussianReal 0 1) = gaussianReal 0 1 := Measure.map_id
    have hmgf := mgf_gaussianReal h_map (t * a i)
    simp only [mgf, id_eq, zero_mul, NNReal.coe_one, zero_add, one_mul] at hmgf
    convert hmgf using 2
  simp_rw [h_mgf]
  -- Step 6: Convert ∏ exp back to exp ∑ using exp_sum
  rw [← Real.exp_sum]
  -- Step 7: Simplify the exponent
  congr 1
  -- We need: ∑ i, (t * a i)² / 2 = t² * ‖d‖_n² / (2n)
  have h_sum_sq : ∑ i : Fin n, (t * a i)^2 / 2 = t^2 / 2 * ∑ i, (a i)^2 := by
    rw [Finset.mul_sum]
    congr 1
    ext i
    ring
  rw [h_sum_sq]
  -- Use empiricalProcess_increment_variance to finish
  have h_var := empiricalProcess_increment_variance n x g₁ g₂
  -- Convert a i to the explicit form
  have h_a_eq : ∀ i, a i = (n : ℝ)⁻¹ * diffValues n x g₁ g₂ i := fun i => rfl
  simp_rw [h_a_eq] at h_var ⊢
  rw [h_var]
  ring

/-- The sub-Gaussian parameter τ = 1/√n -/
noncomputable def subGaussianParam (n : ℕ) : ℝ := 1 / Real.sqrt n

/-- Key rewriting: ‖d‖_n²/(2n) = τ² ‖d‖_n² / 2 where τ = 1/√n -/
lemma subGaussian_exponent_eq (n : ℕ) (hn : 0 < n) (d : ℝ) :
    d^2 / (2 * n) = (subGaussianParam n)^2 * d^2 / 2 := by
  unfold subGaussianParam
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have h1 : (1 / Real.sqrt n)^2 = 1 / n := by
    rw [div_pow, one_pow, sq_sqrt (le_of_lt hn_pos)]
  rw [h1]
  ring

/-- **Main Theorem**: The empirical process is sub-Gaussian with parameter τ = 1/√n.

This is formulated as: for all g₁, g₂ and all t,
  E[exp(t (Z_{g₁} - Z_{g₂}))] ≤ exp(t² τ² ‖g₁ - g₂‖_n² / 2)
where τ = 1/√n.

Note: For Gaussian, the bound is actually EQUALITY, making this immediate. -/
theorem empiricalProcess_isSubGaussian (n : ℕ) (hn : 0 < n) (x : Fin n → X) :
    let μ := stdGaussianPi n
    let τ := subGaussianParam n
    ∀ g₁ g₂ : X → ℝ, ∀ t : ℝ,
      ∫ w, Real.exp (t * (empiricalProcess n x g₁ w - empiricalProcess n x g₂ w)) ∂μ ≤
      Real.exp (t^2 * τ^2 * (empiricalNorm n (diffValues n x g₁ g₂))^2 / 2) := by
  intro μ τ g₁ g₂ t
  -- Use the MGF formula we proved
  haveI : NeZero n := ⟨hn.ne'⟩
  rw [empiricalProcess_increment_mgf n x g₁ g₂ t]
  -- Show equality (which implies ≤) - both expressions are equal
  apply le_of_eq
  -- Rewrite τ^2 = 1/n
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have hτ : τ^2 = 1 / n := by
    show (subGaussianParam n)^2 = 1 / n
    simp only [subGaussianParam, div_pow, one_pow, sq_sqrt (le_of_lt hn_pos)]
  rw [hτ]
  congr 1; ring

/-- Corollary: The empirical process increment satisfies the IsSubGaussianProcess definition
when we embed functions into a metric space with the empirical norm. -/
lemma empiricalProcess_subGaussian_bound (n : ℕ) (hn : 0 < n) (x : Fin n → X)
    (g₁ g₂ : X → ℝ) (t : ℝ) :
    ∫ w, Real.exp (t * (empiricalProcess n x g₁ w - empiricalProcess n x g₂ w))
      ∂(stdGaussianPi n) ≤
    Real.exp (t^2 * (1 / n) * (empiricalNorm n (diffValues n x g₁ g₂))^2 / 2) := by
  haveI : NeZero n := ⟨hn.ne'⟩
  rw [empiricalProcess_increment_mgf n x g₁ g₂ t]
  apply le_of_eq
  congr 1
  ring

end LeastSquares


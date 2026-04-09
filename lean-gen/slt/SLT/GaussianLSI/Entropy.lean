/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import Mathlib.MeasureTheory.Integral.Bochner.Basic
import Mathlib.Analysis.SpecialFunctions.Log.Basic
import Mathlib.Analysis.SpecialFunctions.Log.NegMulLog
import Mathlib.Analysis.Convex.Integral
import Mathlib.Analysis.Convex.SpecificFunctions.Basic

/-!
# Entropy Functional

This file defines the entropy functional for the log-Sobolev inequality and proves
its basic properties.

## Main definitions

* `LogSobolev.entropy`: The entropy of a nonnegative function f with respect to a measure μ,
  defined as Ent_μ(f) = ∫ f log f dμ - (∫ f dμ) log(∫ f dμ).

## Main results

* `LogSobolev.entropy_nonneg`: Entropy is nonnegative for probability measures.

-/

open MeasureTheory ProbabilityTheory Real Set Filter
open scoped ENNReal NNReal BigOperators

noncomputable section

namespace LogSobolev

variable {Ω : Type*} [MeasurableSpace Ω] {μ : Measure Ω}

/-!
## Definition of Entropy
-/

/-- The entropy of a nonnegative function f with respect to measure μ.
    Ent_μ(f) = ∫ f * log(f) dμ - (∫ f dμ) * log(∫ f dμ)

    This measures the "spread" of f relative to a constant function with the same integral.
    When ∫ f dμ = 1 (f is a probability density), this reduces to the negative
    of Shannon entropy: Ent_μ(f) = ∫ f log f dμ. -/
def entropy (μ : Measure Ω) (f : Ω → ℝ) : ℝ :=
  ∫ ω, f ω * log (f ω) ∂μ - (∫ ω, f ω ∂μ) * log (∫ ω, f ω ∂μ)

/-- Alternative notation: Ent_μ(f) -/
notation "Ent[" f "; " μ "]" => entropy μ f

/-!
## Basic Properties
-/

/-- Entropy of a constant function is zero. -/
theorem entropy_const (μ : Measure Ω) [IsProbabilityMeasure μ] (c : ℝ) :
    entropy μ (fun _ => c) = 0 := by
  simp only [entropy, integral_const, probReal_univ, smul_eq_mul, one_mul]
  ring

/-- If f = g a.e., then their entropies are equal. -/
theorem entropy_congr {f g : Ω → ℝ}
    (hfg : f =ᵐ[μ] g) : entropy μ f = entropy μ g := by
  unfold entropy
  have h1 : ∫ ω, f ω * log (f ω) ∂μ = ∫ ω, g ω * log (g ω) ∂μ := by
    apply integral_congr_ae
    filter_upwards [hfg] with ω hω
    rw [hω]
  have h2 : ∫ ω, f ω ∂μ = ∫ ω, g ω ∂μ := integral_congr_ae hfg
  rw [h1, h2]

/-!
## Nonnegativity of Entropy

The key insight is that x * log(x) is convex on [0, ∞), so by Jensen's inequality,
∫ f log f dμ ≥ (∫ f dμ) log(∫ f dμ) when μ is a probability measure and f ≥ 0.
-/

/-- Jensen's inequality for the convex function x * log(x).
    For a probability measure μ and nonnegative integrable f,
    (∫ f dμ) * log(∫ f dμ) ≤ ∫ f * log(f) dμ. -/
theorem jensen_mul_log [IsProbabilityMeasure μ] {f : Ω → ℝ}
    (hf_nn : 0 ≤ᵐ[μ] f)
    (hf_int : Integrable f μ)
    (hf_log_int : Integrable (fun ω => f ω * log (f ω)) μ) :
    (∫ ω, f ω ∂μ) * log (∫ ω, f ω ∂μ) ≤ ∫ ω, f ω * log (f ω) ∂μ := by
  -- The function φ(x) = x * log(x) is convex on [0, ∞)
  have hφ_convex : ConvexOn ℝ (Ici 0) (fun x => x * log x) := Real.convexOn_mul_log
  -- Apply Jensen's inequality
  by_cases hf_zero : ∫ ω, f ω ∂μ = 0
  · -- If ∫ f = 0, then f = 0 a.e., so both sides are 0
    simp only [hf_zero, zero_mul, log_zero]
    have hf_ae_zero : f =ᵐ[μ] 0 := (integral_eq_zero_iff_of_nonneg_ae hf_nn hf_int).mp hf_zero
    have : ∫ ω, f ω * log (f ω) ∂μ = 0 := by
      calc ∫ ω, f ω * log (f ω) ∂μ
          = ∫ ω, (0 : ℝ) * log 0 ∂μ := by
            apply integral_congr_ae
            filter_upwards [hf_ae_zero] with ω hω
            simp [hω]
        _ = 0 := by simp
    linarith
  · -- If ∫ f > 0, apply convexity: φ(∫ f) ≤ ∫ φ(f) when f maps into the convex domain
    have hcont : ContinuousOn (fun x => x * log x) (Ici 0) :=
      Real.continuous_mul_log.continuousOn
    have hclosed : IsClosed (Ici (0 : ℝ)) := isClosed_Ici
    have hmem : ∀ᵐ x ∂μ, f x ∈ Ici (0 : ℝ) := hf_nn
    exact hφ_convex.map_integral_le hcont hclosed hmem hf_int hf_log_int

/-- Entropy is nonnegative for probability measures and nonnegative integrands.
    This is the fundamental property of entropy. -/
theorem entropy_nonneg [IsProbabilityMeasure μ] {f : Ω → ℝ}
    (hf_nn : 0 ≤ᵐ[μ] f)
    (hf_int : Integrable f μ)
    (hf_log_int : Integrable (fun ω => f ω * log (f ω)) μ) :
    0 ≤ entropy μ f := by
  unfold entropy
  linarith [jensen_mul_log hf_nn hf_int hf_log_int]

/-- Entropy of f² with respect to the normalization.
    This is the form that appears in the log-Sobolev inequality. -/
def entropySquare (μ : Measure Ω) (f : Ω → ℝ) : ℝ :=
  entropy μ (fun ω => (f ω)^2)

/-!
## Entropy and Squared Functions

For the log-Sobolev inequality, we work with entropy of f².
-/

/-- The entropy of f² is always well-defined in the sense that the integrand
    f² * log(f²) = 2 * f² * log|f| is measurable when f is. -/
theorem entropySquare_eq (μ : Measure Ω) (f : Ω → ℝ) :
    entropySquare μ f = entropy μ (f · ^2) := rfl

/-- For f² with ∫f² dμ = 1, entropy simplifies. -/
theorem entropy_sq_normalized [IsProbabilityMeasure μ] {f : Ω → ℝ}
    (hf_norm : ∫ ω, (f ω)^2 ∂μ = 1) :
    entropy μ (f · ^2) = ∫ ω, (f ω)^2 * log ((f ω)^2) ∂μ := by
  simp only [entropy, hf_norm, log_one, mul_zero, sub_zero]

/-- log(x^2) = 2 * log|x| for nonzero x. -/
theorem log_sq_eq_two_mul_log_abs {x : ℝ} (hx : x ≠ 0) : log (x^2) = 2 * log |x| := by
  rw [sq, log_mul hx hx]
  simp only [log_abs]
  ring

/-- Entropy of f² in terms of 2 * f² * log|f|.
    This is sometimes a more convenient form. -/
theorem entropy_sq_abs_log [IsProbabilityMeasure μ] {f : Ω → ℝ}
    (hf_norm : ∫ ω, (f ω)^2 ∂μ = 1)
    (hf_pos : ∀ᵐ ω ∂μ, f ω ≠ 0) :
    entropy μ (f · ^2) = 2 * ∫ ω, (f ω)^2 * log |f ω| ∂μ := by
  rw [entropy_sq_normalized hf_norm]
  rw [← integral_const_mul]
  apply integral_congr_ae
  filter_upwards [hf_pos] with ω hω
  rw [log_sq_eq_two_mul_log_abs hω]
  ring

end LogSobolev

end


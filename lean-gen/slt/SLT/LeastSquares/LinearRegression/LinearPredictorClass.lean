/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import Mathlib
import SLT.LeastSquares.Defs

/-!
# Linear Predictor Class

This file defines the linear predictor class F = {f_θ(·) = ⟨θ, ·⟩ : θ ∈ ℝ^d} and proves
its basic closure properties and star-shaped structure.

## Main Definitions

* `linearPredictorClass`: The class of linear predictors

## Main Results

* `zero_mem_linearPredictorClass`: Zero function is a linear predictor
* `add_mem_linearPredictorClass`: Linear predictors are closed under addition
* `smul_mem_linearPredictorClass`: Linear predictors are closed under scalar multiplication
* `neg_mem_linearPredictorClass`: Linear predictors are closed under negation
* `sub_mem_linearPredictorClass`: Linear predictors are closed under subtraction
* `shiftedClass_eq_self_of_linear`: For a linear predictor f*, the shifted class equals the original
* `linearPredictorClass_isStarShaped`: The linear predictor class is star-shaped

-/

open MeasureTheory Finset BigOperators Real ProbabilityTheory Metric Set
open scoped NNReal ENNReal

namespace LeastSquares

variable {n d : ℕ}

/-! ## Linear Predictor Class

The class of linear predictors F = {f_θ(·) = ⟨θ, ·⟩ : θ ∈ ℝ^d}
-/

/-- The class of linear predictors: functions of the form x ↦ ⟨θ, x⟩ for θ ∈ ℝ^d.
We represent this as the range of the map θ ↦ (x ↦ inner θ x). -/
def linearPredictorClass (d : ℕ) : Set ((EuclideanSpace ℝ (Fin d)) → ℝ) :=
  {f | ∃ θ : EuclideanSpace ℝ (Fin d), f = fun x => @inner ℝ _ _ θ x}

/-- Zero function is a linear predictor (with θ = 0) -/
lemma zero_mem_linearPredictorClass : (0 : (EuclideanSpace ℝ (Fin d)) → ℝ) ∈ linearPredictorClass d := by
  use 0
  ext x
  simp only [Pi.zero_apply, inner_zero_left]

/-- Linear predictors are closed under addition -/
lemma add_mem_linearPredictorClass {f g : (EuclideanSpace ℝ (Fin d)) → ℝ}
    (hf : f ∈ linearPredictorClass d) (hg : g ∈ linearPredictorClass d) :
    f + g ∈ linearPredictorClass d := by
  obtain ⟨θ₁, rfl⟩ := hf
  obtain ⟨θ₂, rfl⟩ := hg
  use θ₁ + θ₂
  ext x
  simp only [Pi.add_apply, inner_add_left]

/-- Linear predictors are closed under scalar multiplication -/
lemma smul_mem_linearPredictorClass {f : (EuclideanSpace ℝ (Fin d)) → ℝ} {c : ℝ}
    (hf : f ∈ linearPredictorClass d) :
    c • f ∈ linearPredictorClass d := by
  obtain ⟨θ, rfl⟩ := hf
  use c • θ
  ext x
  simp only [Pi.smul_apply, smul_eq_mul, inner_smul_left, RCLike.conj_to_real]

/-- Linear predictors are closed under negation -/
lemma neg_mem_linearPredictorClass {f : (EuclideanSpace ℝ (Fin d)) → ℝ}
    (hf : f ∈ linearPredictorClass d) :
    -f ∈ linearPredictorClass d := by
  have : -f = (-1 : ℝ) • f := by ext x; simp
  rw [this]
  exact smul_mem_linearPredictorClass hf

/-- Linear predictors are closed under subtraction -/
lemma sub_mem_linearPredictorClass {f g : (EuclideanSpace ℝ (Fin d)) → ℝ}
    (hf : f ∈ linearPredictorClass d) (hg : g ∈ linearPredictorClass d) :
    f - g ∈ linearPredictorClass d := by
  have hsub : f - g = f + (-g) := sub_eq_add_neg f g
  rw [hsub]
  exact add_mem_linearPredictorClass hf (neg_mem_linearPredictorClass hg)

/-! ## Shifted Class Properties

For a linear class F, the shifted class F* = F - {f*} = F.
-/

/-- For a linear predictor f*, the shifted class equals the original class -/
theorem shiftedClass_eq_self_of_linear {f_star : (EuclideanSpace ℝ (Fin d)) → ℝ}
    (hf_star : f_star ∈ linearPredictorClass d) :
    shiftedClass (linearPredictorClass d) f_star = linearPredictorClass d := by
  ext g
  constructor
  · -- g ∈ shiftedClass → g ∈ linearPredictorClass
    intro ⟨f, hf, hfg⟩
    rw [hfg]
    exact sub_mem_linearPredictorClass hf hf_star
  · -- g ∈ linearPredictorClass → g ∈ shiftedClass
    intro hg
    use g + f_star
    constructor
    · exact add_mem_linearPredictorClass hg hf_star
    · ext x
      simp only [Pi.add_apply, Pi.sub_apply]
      ring

/-- The linear predictor class is star-shaped (closed under [0,1] scaling with 0 ∈ F) -/
theorem linearPredictorClass_isStarShaped : IsStarShaped (linearPredictorClass d) := by
  constructor
  · exact zero_mem_linearPredictorClass
  · intro f hf α _ _
    exact smul_mem_linearPredictorClass hf

end LeastSquares

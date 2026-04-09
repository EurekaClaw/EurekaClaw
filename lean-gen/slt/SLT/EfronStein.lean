/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import Mathlib.Probability.Moments.Variance
import Mathlib.MeasureTheory.Integral.Pi
import Mathlib.MeasureTheory.Integral.Prod
import Mathlib.MeasureTheory.Constructions.Pi
import Mathlib.Analysis.SpecialFunctions.Pow.Real

/-!
# Efron-Stein Inequality

This file formalizes the Efron-Stein inequality for independent random variables.

## Main Results

* `efronStein`: For independent X₁, ..., Xₙ on probability space (Ω, μ) and
  a square-integrable function f : Ωⁿ → ℝ, we have:
  ```
  Var(f) ≤ ∑ᵢ E[(f - E^{(i)}f)²]
  ```
  where E^{(i)}f is the conditional expectation given all variables except Xᵢ.
-/

open MeasureTheory ProbabilityTheory

variable {n : ℕ} {Ω : Type*} [MeasurableSpace Ω]
variable {μs : Fin n → Measure Ω} [∀ i, IsProbabilityMeasure (μs i)]

-- Product measure notation
local notation "μˢ" => Measure.pi μs

/-!
## Conditional Expectation Definitions

We define conditional expectations by direct integration.
-/

/-- Conditional expectation of f given all variables except coordinate i.
    E^{(i)}f(x) = ∫ f(update x i y) dμᵢ(y) -/
noncomputable def condExpExceptCoord (i : Fin n) (f : (Fin n → Ω) → ℝ) : (Fin n → Ω) → ℝ :=
  fun x => ∫ y, f (Function.update x i y) ∂(μs i)

/-- Conditional expectation of f given the first k coordinates (unused, for reference). -/
noncomputable def condExpFirstCoords (k : Fin (n + 1)) (f : (Fin n → Ω) → ℝ)
    (μ : Measure Ω) : (Fin k → Ω) → ℝ :=
  fun xk => ∫ y : Ω, f (fun i =>
    if h : i.val < k.val then xk ⟨i.val, h⟩ else y) ∂μ

/-!
## Basic Properties of Conditional Expectations
-/

section BasicProperties

variable (i : Fin n) (f : (Fin n → Ω) → ℝ)

/-- The conditional expectation E^{(i)}f is strongly measurable when f is strongly measurable. -/
lemma condExpExceptCoord_stronglyMeasurable (hf : StronglyMeasurable f) :
    StronglyMeasurable (condExpExceptCoord (μs := μs) i f) := by
  unfold condExpExceptCoord
  apply StronglyMeasurable.integral_prod_right
  exact hf.comp_measurable (measurable_pi_lambda _ (fun j => by
    by_cases h : j = i
    · subst h
      simp only [Function.update_self]
      exact measurable_snd
    · have : (fun c : (Fin n → Ω) × Ω => Function.update c.1 i c.2 j) =
             (fun c => c.1 j) := by
        ext c
        exact Function.update_of_ne h c.2 c.1
      rw [this]
      exact (measurable_pi_apply j).comp measurable_fst))

omit [∀ (i : Fin n), IsProbabilityMeasure (μs i)] in
/-- E^{(i)}f is constant in coordinate i: changing x_i doesn't affect the value -/
lemma condExpExceptCoord_update (x : Fin n → Ω) (y : Ω) :
    condExpExceptCoord (μs := μs) i f (Function.update x i y) =
    condExpExceptCoord (μs := μs) i f x := by
  unfold condExpExceptCoord
  congr 1 with z
  -- update (update x i y) i z = update x i z by Function.update_idem
  rw [Function.update_idem]

-- Helper: (y, x) ↦ update x i y pushes forward (μs i).prod μˢ to μˢ
lemma map_update_prod_pi :
    Measure.map (fun p : Ω × (Fin n → Ω) => Function.update p.2 i p.1) ((μs i).prod μˢ) = μˢ := by
  symm
  apply Measure.pi_eq
  intro s hs
  rw [Measure.map_apply]
  · have preimage_eq : (fun p : Ω × (Fin n → Ω) => Function.update p.2 i p.1) ⁻¹' (Set.univ.pi s) =
        (s i) ×ˢ (Set.univ.pi (fun j => if j = i then Set.univ else s j)) := by
      ext ⟨y, x⟩
      simp only [Set.mem_preimage, Set.mem_pi, Set.mem_univ, true_implies, Set.mem_prod]
      constructor
      · intro h
        constructor
        · have := h i; simp only [Function.update_self] at this; exact this
        · intro j
          by_cases hj : j = i
          · simp [hj]
          · have := h j; simp only [Function.update_of_ne hj] at this
            simp [hj, this]
      · intro ⟨hy, hx⟩ j
        by_cases hj : j = i
        · subst hj; simp only [Function.update_self]; exact hy
        · simp only [Function.update_of_ne hj]
          have := hx j; simp only [hj, ↓reduceIte] at this; exact this
    rw [preimage_eq, Measure.prod_prod]
    have pi_eq : μˢ (Set.univ.pi (fun j => if j = i then Set.univ else s j)) =
        ∏ j : Fin n, (if j = i then 1 else μs j (s j)) := by
      rw [Measure.pi_pi]
      congr 1 with j
      by_cases hj : j = i
      · subst hj; simp only [↓reduceIte, measure_univ]
      · simp only [hj, ↓reduceIte]
    rw [pi_eq]
    have h_ite : ∀ j, (if j = i then (1 : ENNReal) else μs j (s j)) =
                      (if j ∈ Finset.univ.erase i then μs j (s j) else 1) := by
      intro j
      by_cases hj : j = i
      · simp [hj]
      · simp [hj]
    simp_rw [h_ite]
    rw [Fintype.prod_extend_by_one, mul_comm, Finset.prod_erase_mul _ _ (Finset.mem_univ i)]
  · have : (fun p : Ω × (Fin n → Ω) => Function.update p.2 i p.1) =
           (fun q : (Fin n → Ω) × Ω => Function.update q.1 i q.2) ∘ Prod.swap := rfl
    rw [this]
    exact (measurable_update' (a := i)).comp measurable_swap
  · exact MeasurableSet.univ_pi (fun j => hs j)

/-- Averaging f(update x i y) over both x and y gives the same as averaging f over μˢ. -/
lemma integral_update_eq_integral (hf : Integrable f μˢ) :
    ∫ y, ∫ x, f (Function.update x i y) ∂μˢ ∂(μs i) = ∫ z, f z ∂μˢ := by
  set g : Ω × (Fin n → Ω) → ℝ := fun p => f (Function.update p.2 i p.1) with hg_def
  have h1 : ∫ y, ∫ x, f (Function.update x i y) ∂μˢ ∂(μs i) = ∫ p, g p ∂((μs i).prod μˢ) := by
    rw [integral_prod]
    have hmp : MeasurePreserving (fun p : Ω × (Fin n → Ω) => Function.update p.2 i p.1)
               ((μs i).prod μˢ) μˢ := by
      constructor
      · have : (fun p : Ω × (Fin n → Ω) => Function.update p.2 i p.1) =
               (fun q : (Fin n → Ω) × Ω => Function.update q.1 i q.2) ∘ Prod.swap := rfl
        rw [this]
        exact (measurable_update' (a := i)).comp measurable_swap
      · exact map_update_prod_pi i
    exact hmp.integrable_comp hf.aestronglyMeasurable |>.mpr hf
  rw [h1, hg_def, ← integral_map]
  · rw [map_update_prod_pi]
  · have : (fun p : Ω × (Fin n → Ω) => Function.update p.2 i p.1) =
           (fun q : (Fin n → Ω) × Ω => Function.update q.1 i q.2) ∘ Prod.swap := rfl
    rw [this]
    exact ((measurable_update' (a := i)).comp measurable_swap).aemeasurable
  · rw [map_update_prod_pi]; exact hf.aestronglyMeasurable

/-- Tower property: E[E^{(i)}f] = E[f] -/
lemma condExpExceptCoord_expectation (hf : Integrable f μˢ) :
    ∫ x, condExpExceptCoord (μs := μs) i f x ∂μˢ = ∫ x, f x ∂μˢ := by
  simp only [condExpExceptCoord]
  rw [integral_integral_swap]
  exact integral_update_eq_integral i f hf
  · have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
               (μˢ.prod (μs i)) μˢ := by
      constructor
      · exact measurable_update' (a := i)
      · have hg : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
          (measurable_update' (a := i)).comp measurable_swap
        calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
              (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
              rw [Measure.prod_swap]
          _ = μˢ := map_update_prod_pi i
    exact hmp.integrable_comp hf.aestronglyMeasurable |>.mpr hf

/-- The difference f - E^{(i)}f has zero expectation with respect to coordinate i. -/
lemma condExpExceptCoord_sub_self_integral_coord (x : Fin n → Ω)
    (hf_slice : Integrable (fun y => f (Function.update x i y)) (μs i)) :
    ∫ y, (f (Function.update x i y) - condExpExceptCoord (μs := μs) i f (Function.update x i y)) ∂(μs i) = 0 := by
  simp only [condExpExceptCoord]
  rw [integral_sub]
  · simp_rw [Function.update_idem]
    rw [integral_const, probReal_univ, one_smul]
    exact sub_self _
  · exact hf_slice
  · simp_rw [Function.update_idem]; exact integrable_const _

end BasicProperties

/-!
## Variance Decomposition

We prove the variance decomposition via telescoping sums.
-/

section VarianceDecomposition

variable (f : (Fin n → Ω) → ℝ)

/-- Conditional variance with respect to coordinate i -/
noncomputable def condVarExceptCoord (i : Fin n) (f : (Fin n → Ω) → ℝ) : (Fin n → Ω) → ℝ :=
  fun x => ∫ y, (f (Function.update x i y) - condExpExceptCoord (μs := μs) i f x)^2 ∂(μs i)

/-- E[(f - E^{(i)}f)²] equals E[Var^{(i)}(f)] -/
lemma expectation_sq_diff_eq_expectation_condVar (i : Fin n) (_hf : Integrable f μˢ)
    (hf2 : Integrable (fun x => (f x - condExpExceptCoord (μs := μs) i f x)^2) μˢ) :
    ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μˢ =
    ∫ x, condVarExceptCoord (μs := μs) i f x ∂μˢ := by
  unfold condVarExceptCoord
  have hconst : ∀ x y, condExpExceptCoord (μs := μs) i f (Function.update x i y) =
                       condExpExceptCoord (μs := μs) i f x := fun x y => by
    simp only [condExpExceptCoord, Function.update_idem]
  set G := fun z : Fin n → Ω => (f z - condExpExceptCoord (μs := μs) i f z)^2 with hG_def
  have hG_eq : ∀ x y, (f (Function.update x i y) - condExpExceptCoord (μs := μs) i f x)^2 =
                      G (Function.update x i y) := fun x y => by
    simp only [hG_def, hconst]
  simp_rw [hG_eq]
  symm
  rw [integral_integral_swap]
  · simp_rw [integral_update_eq_integral i G hf2]
  · have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
               (μˢ.prod (μs i)) μˢ := by
      constructor
      · exact measurable_update' (a := i)
      · have hg : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
          (measurable_update' (a := i)).comp measurable_swap
        calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
              (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
              rw [Measure.prod_swap]
          _ = μˢ := map_update_prod_pi i
    exact hmp.integrable_comp hf2.aestronglyMeasurable |>.mpr hf2

end VarianceDecomposition

/-!
## Key Inequality (Lemma 2)

The key step: E[Var^{(i)}(Eᵢf)] ≤ E[Var^{(i)}(f)]

This follows from the duality formula for variance:
  Var(Y) = sup_T (2 Cov(Y,T) - Var(T))
-/

section KeyInequality

/-- From Var(Y-T) ≥ 0: Var(Y) ≥ 2Cov(Y,T) - Var(T). -/
lemma variance_ge_two_cov_sub_variance {Ω' : Type*} [MeasurableSpace Ω'] {μ : Measure Ω'}
    [IsFiniteMeasure μ] {Y T : Ω' → ℝ} (hY : MemLp Y 2 μ) (hT : MemLp T 2 μ) :
    variance Y μ ≥ 2 * covariance Y T μ - variance T μ := by
  have h := variance_nonneg (Y - T) μ
  rw [variance_sub hY hT] at h
  linarith

/-- Conditional expectation given first k coordinates: Eₖf(x) integrates over coords ≥ k. -/
noncomputable def condExpFirstK (k : Fin (n + 1)) (f : (Fin n → Ω) → ℝ) : (Fin n → Ω) → ℝ :=
  fun x => ∫ y, f (fun j => if j.val < k.val then x j else y j) ∂μˢ

/-- Projection property: E[f * E^{(i)}f] = E[(E^{(i)}f)²]
    This holds because E^{(i)}f doesn't depend on coordinate i. -/
lemma integral_mul_condExpExceptCoord (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf : Integrable f μˢ) (hf2 : Integrable (f^2) μˢ) :
    ∫ x, f x * condExpExceptCoord (μs := μs) i f x ∂μˢ =
    ∫ x, (condExpExceptCoord (μs := μs) i f x)^2 ∂μˢ := by
  set D := fun z : Fin n → Ω =>
    f z * condExpExceptCoord (μs := μs) i f z - (condExpExceptCoord (μs := μs) i f z)^2 with hD_def
  have hcond_int : Integrable (condExpExceptCoord (μs := μs) i f) μˢ := by
    have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
               (μˢ.prod (μs i)) μˢ := by
      constructor
      · exact measurable_update' (a := i)
      · have hg : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
          (measurable_update' (a := i)).comp measurable_swap
        calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
              (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
              rw [Measure.prod_swap]
          _ = μˢ := map_update_prod_pi i
    have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => f (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
      hmp.integrable_comp hf.aestronglyMeasurable |>.mpr hf
    convert hg_int.integral_prod_left
  have hcond_sq_int : Integrable (condExpExceptCoord (μs := μs) i (f ^ 2)) μˢ := by
    have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
               (μˢ.prod (μs i)) μˢ := by
      constructor
      · exact measurable_update' (a := i)
      · have hg : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
          (measurable_update' (a := i)).comp measurable_swap
        calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
              (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
              rw [Measure.prod_swap]
          _ = μˢ := map_update_prod_pi i
    have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => (f ^ 2) (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
      hmp.integrable_comp hf2.aestronglyMeasurable |>.mpr hf2
    convert hg_int.integral_prod_left
  -- A.e. slice integrability for f² (needed for Jensen bound)
  have hf2_slice_ae : ∀ᵐ x ∂μˢ, Integrable (fun y => f (Function.update x i y) ^ 2) (μs i) := by
    have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
               (μˢ.prod (μs i)) μˢ := by
      constructor
      · exact measurable_update' (a := i)
      · have hg : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
          (measurable_update' (a := i)).comp measurable_swap
        calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
              (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
              rw [Measure.prod_swap]
          _ = μˢ := map_update_prod_pi i
    have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => (f ^ 2) (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
      hmp.integrable_comp hf2.aestronglyMeasurable |>.mpr hf2
    exact hg_int.prod_right_ae
  -- A.e. slice integrability for f (from hcond_int proof)
  have hf_slice_ae' : ∀ᵐ x ∂μˢ, Integrable (fun y => f (Function.update x i y)) (μs i) := by
    have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
               (μˢ.prod (μs i)) μˢ := by
      constructor
      · exact measurable_update' (a := i)
      · have hg : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
          (measurable_update' (a := i)).comp measurable_swap
        calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
              (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
              rw [Measure.prod_swap]
          _ = μˢ := map_update_prod_pi i
    have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => f (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
      hmp.integrable_comp hf.aestronglyMeasurable |>.mpr hf
    exact hg_int.prod_right_ae
  have hsq_int : Integrable (fun z => (condExpExceptCoord (μs := μs) i f z)^2) μˢ := by
    -- Use the bound: (condExpExceptCoord i f x)² ≤ condExpExceptCoord i (f²) x
    -- This follows from Jensen: (E[X])² ≤ E[X²] applied to f(update · i ·)
    apply Integrable.mono' hcond_sq_int
    · -- AEStronglyMeasurable
      exact hcond_int.aestronglyMeasurable.pow 2
    · -- Pointwise bound from Jensen (a.e.)
      filter_upwards [hf_slice_ae', hf2_slice_ae] with x hslice_int hslice_sq_int
      rw [Real.norm_eq_abs, abs_sq]
      -- (∫ y, f(update x i y) dμ)² ≤ ∫ y, (f(update x i y))² dμ
      -- This is Jensen for convex function x² on ℝ (probability measure)
      -- Use variance_nonneg: Var(X) ≥ 0 ⟺ E[X²] ≥ (E[X])²
      have hslice_memLp : MemLp (fun y => f (Function.update x i y)) 2 (μs i) := by
        rw [memLp_two_iff_integrable_sq hslice_int.aestronglyMeasurable]
        exact hslice_sq_int
      have hvar := variance_nonneg (fun y => f (Function.update x i y)) (μs i)
      rw [variance_eq_sub hslice_memLp] at hvar
      simp only [condExpExceptCoord, Pi.pow_apply] at *
      linarith
  have hprod_int : Integrable (fun z => f z * condExpExceptCoord (μs := μs) i f z) μˢ := by
    -- f ∈ L², condExpExceptCoord i f ∈ L², so product is L¹
    have hf_memLp : MemLp f 2 μˢ := (memLp_two_iff_integrable_sq hf.aestronglyMeasurable).mpr hf2
    have hcond_memLp : MemLp (condExpExceptCoord (μs := μs) i f) 2 μˢ := by
      rw [memLp_two_iff_integrable_sq hcond_int.aestronglyMeasurable]
      exact hsq_int
    exact hf_memLp.integrable_mul hcond_memLp
  have hD_int : Integrable D μˢ := hprod_int.sub hsq_int

  -- It suffices to show ∫ D = 0
  suffices h_zero : ∫ z, D z ∂μˢ = 0 by
    have : ∫ z, D z ∂μˢ = ∫ z, f z * condExpExceptCoord (μs := μs) i f z ∂μˢ -
                          ∫ z, (condExpExceptCoord (μs := μs) i f z)^2 ∂μˢ :=
      integral_sub hprod_int hsq_int
    linarith [h_zero, this]

  -- Rewrite D as E^{(i)}f * (f - E^{(i)}f)
  have hD_factor : ∀ z, D z = condExpExceptCoord (μs := μs) i f z * (f z - condExpExceptCoord (μs := μs) i f z) := by
    intro z
    simp only [hD_def, sq]
    ring

  -- Slice integrability: for a.e. x, f ∘ update x i is integrable
  -- This follows from Fubini theorem applied to the product measure
  have hf_slice_ae : ∀ᵐ x ∂μˢ, Integrable (fun y => f (Function.update x i y)) (μs i) := by
    -- Use Fubini: if f is integrable on the product, slices are a.e. integrable
    have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
               (μˢ.prod (μs i)) μˢ := by
      constructor
      · exact measurable_update' (a := i)
      · have hg : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
          (measurable_update' (a := i)).comp measurable_swap
        calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
              (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
              rw [Measure.prod_swap]
          _ = μˢ := map_update_prod_pi i
    have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => f (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
      hmp.integrable_comp hf.aestronglyMeasurable |>.mpr hf
    exact hg_int.prod_right_ae

  -- For a.e. x, the inner integral over y is 0
  have h_inner_zero_ae : ∀ᵐ x ∂μˢ, ∫ y, D (Function.update x i y) ∂(μs i) = 0 := by
    filter_upwards [hf_slice_ae] with x hf_slice_x
    simp_rw [hD_factor]
    -- D(update x i y) = E^{(i)}f(update x i y) * (f(update x i y) - E^{(i)}f(update x i y))
    --                 = E^{(i)}f(x) * (f(update x i y) - E^{(i)}f(x))
    simp_rw [condExpExceptCoord_update]
    -- Now E^{(i)}f(x) is constant in y, so we can factor it out
    rw [integral_const_mul]
    -- Inner integral: ∫ y, (f(update x i y) - E^{(i)}f(x)) ∂μ = 0
    rw [integral_sub hf_slice_x (integrable_const _)]
    -- ∫ f(update x i y) dμ = E^{(i)}f(x) by definition
    simp only [condExpExceptCoord, integral_const, probReal_univ, one_smul]
    ring

  -- Use integral_update_eq_integral: ∫ D dμˢ = ∫ y, (∫ x, D(update x i y) dμˢ) dμ
  -- Then swap order and use h_inner_zero_ae
  have hD_uncurry_int : Integrable (Function.uncurry (fun y x => D (Function.update x i y))) ((μs i).prod μˢ) := by
    -- Transform to composition with Prod.swap
    have hmp : MeasurePreserving (fun p : Ω × (Fin n → Ω) => Function.update p.2 i p.1)
               ((μs i).prod μˢ) μˢ := by
      constructor
      · exact (measurable_update' (a := i)).comp measurable_swap
      · exact map_update_prod_pi i
    exact hmp.integrable_comp hD_int.aestronglyMeasurable |>.mpr hD_int
  calc ∫ z, D z ∂μˢ
      = ∫ y, ∫ x, D (Function.update x i y) ∂μˢ ∂(μs i) := (integral_update_eq_integral i D hD_int).symm
    _ = ∫ x, ∫ y, D (Function.update x i y) ∂(μs i) ∂μˢ := by
        rw [integral_integral_swap hD_uncurry_int]
    _ = ∫ x, 0 ∂μˢ := by
        apply integral_congr_ae
        exact h_inner_zero_ae
    _ = 0 := integral_zero _ _

/-- Total variance identity: Var(f) = E[Var^{(i)}(f)] + Var(E^{(i)}f)
    In our notation: Var(f) = E[condVarExceptCoord i f] + Var(condExpExceptCoord i f) -/
lemma total_variance_identity (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf : MemLp f 2 μˢ) :
    variance f μˢ = ∫ x, condVarExceptCoord (μs := μs) i f x ∂μˢ +
                   variance (condExpExceptCoord (μs := μs) i f) μˢ := by
  -- Expand variances using variance_eq_sub
  rw [variance_eq_sub hf]
  -- For the second variance, need MemLp for condExpExceptCoord i f
  have hcond_memLp : MemLp (condExpExceptCoord (μs := μs) i f) 2 μˢ := by
    -- First show integrability of condExpExceptCoord
    have hcond_int : Integrable (condExpExceptCoord (μs := μs) i f) μˢ := by
      have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
                 (μˢ.prod (μs i)) μˢ := by
        constructor
        · exact measurable_update' (a := i)
        · have hg : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
            (measurable_update' (a := i)).comp measurable_swap
          calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
                (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
                rw [Measure.prod_swap]
            _ = μˢ := map_update_prod_pi i
      have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => f (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
        hmp.integrable_comp (hf.integrable one_le_two).aestronglyMeasurable |>.mpr (hf.integrable one_le_two)
      convert hg_int.integral_prod_left
    -- Show (condExpExceptCoord)² is integrable via Jensen bound
    have hf2 := hf.integrable_sq
    have hcond_sq_int : Integrable (condExpExceptCoord (μs := μs) i (f ^ 2)) μˢ := by
      have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
                 (μˢ.prod (μs i)) μˢ := by
        constructor
        · exact measurable_update' (a := i)
        · have hg : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
            (measurable_update' (a := i)).comp measurable_swap
          calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
                (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
                rw [Measure.prod_swap]
            _ = μˢ := map_update_prod_pi i
      have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => (f ^ 2) (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
        hmp.integrable_comp hf2.aestronglyMeasurable |>.mpr hf2
      convert hg_int.integral_prod_left
    have hf2_slice_ae : ∀ᵐ x ∂μˢ, Integrable (fun y => f (Function.update x i y) ^ 2) (μs i) := by
      have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
                 (μˢ.prod (μs i)) μˢ := by
        constructor
        · exact measurable_update' (a := i)
        · have hg : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
            (measurable_update' (a := i)).comp measurable_swap
          calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
                (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
                rw [Measure.prod_swap]
            _ = μˢ := map_update_prod_pi i
      have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => (f ^ 2) (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
        hmp.integrable_comp hf2.aestronglyMeasurable |>.mpr hf2
      exact hg_int.prod_right_ae
    have hf_slice_ae : ∀ᵐ x ∂μˢ, Integrable (fun y => f (Function.update x i y)) (μs i) := by
      have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
                 (μˢ.prod (μs i)) μˢ := by
        constructor
        · exact measurable_update' (a := i)
        · have hg : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
            (measurable_update' (a := i)).comp measurable_swap
          calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
                (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
                rw [Measure.prod_swap]
            _ = μˢ := map_update_prod_pi i
      have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => f (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
        hmp.integrable_comp (hf.integrable one_le_two).aestronglyMeasurable |>.mpr (hf.integrable one_le_two)
      exact hg_int.prod_right_ae
    have hsq_int : Integrable (fun z => (condExpExceptCoord (μs := μs) i f z)^2) μˢ := by
      apply Integrable.mono' hcond_sq_int
      · exact hcond_int.aestronglyMeasurable.pow 2
      · filter_upwards [hf_slice_ae, hf2_slice_ae] with x hslice_int hslice_sq_int
        rw [Real.norm_eq_abs, abs_sq]
        have hslice_memLp : MemLp (fun y => f (Function.update x i y)) 2 (μs i) := by
          rw [memLp_two_iff_integrable_sq hslice_int.aestronglyMeasurable]
          exact hslice_sq_int
        have hvar := variance_nonneg (fun y => f (Function.update x i y)) (μs i)
        rw [variance_eq_sub hslice_memLp] at hvar
        simp only [condExpExceptCoord, Pi.pow_apply] at *
        linarith
    rw [memLp_two_iff_integrable_sq hcond_int.aestronglyMeasurable]
    exact hsq_int
  rw [variance_eq_sub hcond_memLp]
  have htower := condExpExceptCoord_expectation (μs := μs) i f (hf.integrable one_le_two)
  rw [htower]
  have hf2_int : Integrable (fun x => (f x - condExpExceptCoord (μs := μs) i f x)^2) μˢ := by
    have hdiff_memLp : MemLp (fun x => f x - condExpExceptCoord (μs := μs) i f x) 2 μˢ :=
      hf.sub hcond_memLp
    exact hdiff_memLp.integrable_sq
  have hcondVar := expectation_sq_diff_eq_expectation_condVar (f := f) i (hf.integrable one_le_two) hf2_int
  rw [← hcondVar]
  have h_expand : ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μˢ =
      ∫ x, (f x)^2 ∂μˢ - 2 * ∫ x, f x * condExpExceptCoord (μs := μs) i f x ∂μˢ +
      ∫ x, (condExpExceptCoord (μs := μs) i f x)^2 ∂μˢ := by
    have hf2_int' := hf.integrable_sq
    have hsq_int : Integrable (fun x => (condExpExceptCoord (μs := μs) i f x)^2) μˢ :=
      hcond_memLp.integrable_sq
    have hprod_int : Integrable (fun x => f x * condExpExceptCoord (μs := μs) i f x) μˢ :=
      hf.integrable_mul hcond_memLp
    have h2prod_int : Integrable (fun x => 2 * f x * condExpExceptCoord (μs := μs) i f x) μˢ := by
      have : (fun x => 2 * f x * condExpExceptCoord (μs := μs) i f x) =
             (fun x => 2 * (f x * condExpExceptCoord (μs := μs) i f x)) := by ext x; ring
      rw [this]; exact hprod_int.const_mul 2
    have h_sq_expand : ∀ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 =
        (f x)^2 - 2 * f x * condExpExceptCoord (μs := μs) i f x +
        (condExpExceptCoord (μs := μs) i f x)^2 := by
      intro x; ring
    calc ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μˢ
        = ∫ x, ((f x)^2 - 2 * f x * condExpExceptCoord (μs := μs) i f x +
              (condExpExceptCoord (μs := μs) i f x)^2) ∂μˢ := by
          congr 1 with x; exact h_sq_expand x
      _ = ∫ x, ((f x)^2 - 2 * f x * condExpExceptCoord (μs := μs) i f x) ∂μˢ +
          ∫ x, (condExpExceptCoord (μs := μs) i f x)^2 ∂μˢ := by
          apply integral_add _ hsq_int
          exact hf2_int'.sub h2prod_int
      _ = ∫ x, (f x)^2 ∂μˢ - ∫ x, 2 * f x * condExpExceptCoord (μs := μs) i f x ∂μˢ +
          ∫ x, (condExpExceptCoord (μs := μs) i f x)^2 ∂μˢ := by
          rw [integral_sub hf2_int' h2prod_int]
      _ = ∫ x, (f x)^2 ∂μˢ - 2 * ∫ x, f x * condExpExceptCoord (μs := μs) i f x ∂μˢ +
          ∫ x, (condExpExceptCoord (μs := μs) i f x)^2 ∂μˢ := by
          congr 1
          have : ∫ x, 2 * f x * condExpExceptCoord (μs := μs) i f x ∂μˢ =
                 2 * ∫ x, f x * condExpExceptCoord (μs := μs) i f x ∂μˢ := by
            have heq : (fun x => 2 * f x * condExpExceptCoord (μs := μs) i f x) =
                       (fun x => 2 * (f x * condExpExceptCoord (μs := μs) i f x)) := by ext x; ring
            rw [heq, integral_const_mul]
          linarith [this]
  have hproj := integral_mul_condExpExceptCoord (μs := μs) i f (hf.integrable one_le_two)
                  hf.integrable_sq
  have h_key : ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μˢ =
      ∫ x, (f x)^2 ∂μˢ - ∫ x, (condExpExceptCoord (μs := μs) i f x)^2 ∂μˢ := by
    rw [h_expand, hproj]; ring
  simp only [Pi.pow_apply]
  rw [h_key]
  ring

/-- Sum of variances of conditional expectations is at most (n-1) * Var(f). -/
lemma sum_variance_condExp_le (f : (Fin n → Ω) → ℝ) (hf : MemLp f 2 μˢ)
    (hefron : variance f μˢ ≤ ∑ i : Fin n, ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μˢ) :
    ∑ i : Fin n, variance (condExpExceptCoord (μs := μs) i f) μˢ ≤ (n - 1) * variance f μˢ := by
  have htotal : ∀ i, variance (condExpExceptCoord (μs := μs) i f) μˢ =
      variance f μˢ - ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μˢ := by
    intro i
    have htv := total_variance_identity (μs := μs) i f hf
    have hcond_memLp : MemLp (condExpExceptCoord (μs := μs) i f) 2 μˢ := by
      have hcond_int : Integrable (condExpExceptCoord (μs := μs) i f) μˢ := by
        have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
                   (μˢ.prod (μs i)) μˢ := by
          constructor
          · exact measurable_update' (a := i)
          · have hg : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
              (measurable_update' (a := i)).comp measurable_swap
            calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
              _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
                  (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
              _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
                  rw [Measure.prod_swap]
              _ = μˢ := map_update_prod_pi i
        have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => f (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
          hmp.integrable_comp (hf.integrable one_le_two).aestronglyMeasurable |>.mpr (hf.integrable one_le_two)
        convert hg_int.integral_prod_left
      have hf2 := hf.integrable_sq
      have hcond_sq_int : Integrable (condExpExceptCoord (μs := μs) i (f ^ 2)) μˢ := by
        have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
                   (μˢ.prod (μs i)) μˢ := by
          constructor
          · exact measurable_update' (a := i)
          · have hg : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
              (measurable_update' (a := i)).comp measurable_swap
            calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
              _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
                  (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
              _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
                  rw [Measure.prod_swap]
              _ = μˢ := map_update_prod_pi i
        have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => (f ^ 2) (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
          hmp.integrable_comp hf2.aestronglyMeasurable |>.mpr hf2
        convert hg_int.integral_prod_left
      have hf2_slice_ae : ∀ᵐ x ∂μˢ, Integrable (fun y => f (Function.update x i y) ^ 2) (μs i) := by
        have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
                   (μˢ.prod (μs i)) μˢ := by
          constructor
          · exact measurable_update' (a := i)
          · have hg : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
              (measurable_update' (a := i)).comp measurable_swap
            calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
              _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
                  (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
              _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
                  rw [Measure.prod_swap]
              _ = μˢ := map_update_prod_pi i
        have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => (f ^ 2) (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
          hmp.integrable_comp hf2.aestronglyMeasurable |>.mpr hf2
        exact hg_int.prod_right_ae
      have hf_slice_ae : ∀ᵐ x ∂μˢ, Integrable (fun y => f (Function.update x i y)) (μs i) := by
        have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
                   (μˢ.prod (μs i)) μˢ := by
          constructor
          · exact measurable_update' (a := i)
          · have hg : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
              (measurable_update' (a := i)).comp measurable_swap
            calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
              _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
                  (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
              _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
                  rw [Measure.prod_swap]
              _ = μˢ := map_update_prod_pi i
        have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => f (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
          hmp.integrable_comp (hf.integrable one_le_two).aestronglyMeasurable |>.mpr (hf.integrable one_le_two)
        exact hg_int.prod_right_ae
      have hsq_int : Integrable (fun z => (condExpExceptCoord (μs := μs) i f z)^2) μˢ := by
        apply Integrable.mono' hcond_sq_int
        · exact hcond_int.aestronglyMeasurable.pow 2
        · filter_upwards [hf_slice_ae, hf2_slice_ae] with x hslice_int hslice_sq_int
          rw [Real.norm_eq_abs, abs_sq]
          have hslice_memLp : MemLp (fun y => f (Function.update x i y)) 2 (μs i) := by
            rw [memLp_two_iff_integrable_sq hslice_int.aestronglyMeasurable]
            exact hslice_sq_int
          have hvar := variance_nonneg (fun y => f (Function.update x i y)) (μs i)
          rw [variance_eq_sub hslice_memLp] at hvar
          simp only [condExpExceptCoord, Pi.pow_apply] at *
          linarith
      rw [memLp_two_iff_integrable_sq hcond_int.aestronglyMeasurable]
      exact hsq_int
    have hdiff_memLp : MemLp (fun x => f x - condExpExceptCoord (μs := μs) i f x) 2 μˢ :=
      hf.sub hcond_memLp
    have hf2_int : Integrable (fun x => (f x - condExpExceptCoord (μs := μs) i f x)^2) μˢ :=
      hdiff_memLp.integrable_sq
    have hcondVar := expectation_sq_diff_eq_expectation_condVar (f := f) i (hf.integrable one_le_two) hf2_int
    linarith
  -- Sum: ∑ Var(E^{(i)}f) = n * Var(f) - ∑ E[(f - E^{(i)}f)²]
  have hsum_eq : ∑ i, variance (condExpExceptCoord (μs := μs) i f) μˢ =
      n * variance f μˢ - ∑ i, ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μˢ := by
    simp_rw [htotal]
    rw [Finset.sum_sub_distrib, Finset.sum_const, Finset.card_fin]
    simp only [nsmul_eq_mul]
  rw [hsum_eq]
  -- Using Efron-Stein: ∑ E[(f - E^{(i)}f)²] ≥ Var(f)
  linarith

end KeyInequality

/-!
## Tensorization Helpers

These lemmas are used for the inductive step in the Efron-Stein proof.
-/

section Tensorization

/-- A.e. commutativity of conditional expectations: E^{(i)}(E^{(j)}f) = E^{(j)}(E^{(i)}f) a.e. for i ≠ j.
    This follows from Fubini since the conditional expectations integrate over independent coordinates. -/
lemma condExpExceptCoord_comm_ae {i j : Fin n} (hij : i ≠ j) (f : (Fin n → Ω) → ℝ)
    (hf : Integrable f μˢ) :
    condExpExceptCoord (μs := μs) i (condExpExceptCoord (μs := μs) j f) =ᶠ[ae μˢ]
    condExpExceptCoord (μs := μs) j (condExpExceptCoord (μs := μs) i f) := by
  -- Both sides don't depend on coordinates i and j
  -- For the a.e. equality, we use Fubini to swap integration orders
  unfold condExpExceptCoord
  -- The key is that updates on different coordinates commute
  have hcomm : ∀ x y z, f (Function.update (Function.update x i y) j z) =
      f (Function.update (Function.update x j z) i y) := by
    intros x y z
    rw [Function.update_comm hij]
  -- Define the map φ : μˢ × μ × μ → μˢ that updates coordinates i and j
  -- The function (x, y, z) ↦ f(update (update x i y) j z) is integrable on μˢ × μ × μ
  -- by measure-preserving composition
  have hmp : MeasurePreserving
      (fun p : (Fin n → Ω) × Ω × Ω => Function.update (Function.update p.1 i p.2.1) j p.2.2)
      (μˢ.prod ((μs i).prod (μs j))) μˢ := by
    constructor
    · -- Measurability: compose update operations
      have h1 : Measurable (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) := measurable_update' (a := i)
      have h2 : Measurable (fun p : (Fin n → Ω) × Ω => Function.update p.1 j p.2) := measurable_update' (a := j)
      have h3 : Measurable (fun p : (Fin n → Ω) × Ω × Ω => (p.1, p.2.1)) :=
        Measurable.prodMk measurable_fst (measurable_fst.comp measurable_snd)
      have h4 : Measurable (fun p : (Fin n → Ω) × Ω × Ω => (Function.update p.1 i p.2.1, p.2.2)) :=
        Measurable.prodMk (h1.comp h3) (measurable_snd.comp measurable_snd)
      exact h2.comp h4
    · -- The map is measure-preserving since it's a product structure
      -- Use Measure.pi_eq to prove equality via rectangle sets
      symm
      apply Measure.pi_eq
      intro s hs
      rw [Measure.map_apply]
      · -- Compute preimage of rectangle set
        -- Preimage of ∏ₖ s(k) under (x, (y, z)) ↦ update (update x i y) j z
        -- The result at coord k is: if k = j then z, else if k = i then y, else x(k)
        -- So preimage is {(x, (y, z)) : z ∈ s j, y ∈ s i, ∀ k ≠ i,j, x(k) ∈ s(k)}
        have preimage_eq : (fun p : (Fin n → Ω) × Ω × Ω =>
            Function.update (Function.update p.1 i p.2.1) j p.2.2) ⁻¹' (Set.univ.pi s) =
            (Set.univ.pi (fun k => if k = i ∨ k = j then Set.univ else s k)) ×ˢ ((s i) ×ˢ (s j)) := by
          ext ⟨x, y, z⟩
          simp only [Set.mem_preimage, Set.mem_pi, Set.mem_univ, true_implies, Set.mem_prod]
          constructor
          · intro h
            constructor
            · intro k
              by_cases hki : k = i
              · simp [hki]
              · by_cases hkj : k = j
                · simp [hkj]
                · have := h k
                  simp only [Function.update_of_ne hkj, Function.update_of_ne hki] at this
                  simp [hki, hkj, this]
            · constructor
              · have := h i
                rw [Function.update_of_ne hij, Function.update_self] at this
                exact this
              · have := h j
                rw [Function.update_self] at this
                exact this
          · intro ⟨hx, hy, hz⟩ k
            by_cases hkj : k = j
            · subst hkj; simp only [Function.update_self]; exact hz
            · by_cases hki : k = i
              · subst hki; rw [Function.update_of_ne hij, Function.update_self]; exact hy
              · simp only [Function.update_of_ne hkj, Function.update_of_ne hki]
                have := hx k; simp only [hki, hkj, or_self, ↓reduceIte] at this; exact this
        rw [preimage_eq]
        -- Measure of product set
        rw [Measure.prod_prod, Measure.prod_prod]
        -- Compute the pi measure factor
        have pi_eq : μˢ (Set.univ.pi (fun k => if k = i ∨ k = j then Set.univ else s k)) =
            ∏ k : Fin n, (if k = i ∨ k = j then 1 else (μs k) (s k)) := by
          rw [Measure.pi_pi]
          congr 1 with k
          by_cases hki : k = i
          · simp [hki]
          · by_cases hkj : k = j
            · simp [hkj]
            · simp [hki, hkj]
        rw [pi_eq]
        -- Goal: (∏ k, if k=i∨k=j then 1 else μ(s k)) * (μ(s i) * μ(s j)) = ∏ k, μ(s k)
        -- Extract i and j from the product
        have h1 : ∏ k : Fin n, (if k = i ∨ k = j then (1 : ENNReal) else (μs k) (s k)) =
                  ∏ k ∈ (Finset.univ.erase i).erase j, (μs k) (s k) := by
          rw [← Fintype.prod_extend_by_one ((Finset.univ.erase i).erase j) (fun k => (μs k) (s k))]
          congr 1 with k
          simp only [Finset.mem_erase, Finset.mem_univ, and_true, ne_eq]
          by_cases hki : k = i
          · simp [hki]
          · by_cases hkj : k = j
            · simp [hkj]
            · simp [hki, hkj]
        rw [h1]
        -- Now: (∏_{k≠i,j} μ(s k)) * μ(s i) * μ(s j) = ∏_k μ(s k)
        have hmemi : i ∈ Finset.univ.erase j := Finset.mem_erase.mpr ⟨hij, Finset.mem_univ i⟩
        have hmemj : j ∈ Finset.univ := Finset.mem_univ j
        calc (∏ k ∈ (Finset.univ.erase i).erase j, (μs k) (s k)) * ((μs i) (s i) * (μs j) (s j))
          _ = (∏ k ∈ (Finset.univ.erase i).erase j, (μs k) (s k)) * (μs i) (s i) * (μs j) (s j) := by ring
          _ = (∏ k ∈ Finset.univ.erase j, (μs k) (s k)) * (μs j) (s j) := by
              have : (Finset.univ.erase j).erase i = (Finset.univ.erase i).erase j :=
                Finset.erase_right_comm
              rw [← this, Finset.prod_erase_mul _ _ hmemi]
          _ = ∏ k, (μs k) (s k) := Finset.prod_erase_mul _ _ hmemj
      · -- Measurability of the map
        have h1 : Measurable (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) := measurable_update' (a := i)
        have h2 : Measurable (fun p : (Fin n → Ω) × Ω => Function.update p.1 j p.2) := measurable_update' (a := j)
        have h3 : Measurable (fun p : (Fin n → Ω) × Ω × Ω => (p.1, p.2.1)) :=
          Measurable.prodMk measurable_fst (measurable_fst.comp measurable_snd)
        have h4 : Measurable (fun p : (Fin n → Ω) × Ω × Ω => (Function.update p.1 i p.2.1, p.2.2)) :=
          Measurable.prodMk (h1.comp h3) (measurable_snd.comp measurable_snd)
        exact h2.comp h4
      · exact MeasurableSet.univ_pi (fun k => hs k)
  have hint : Integrable (fun p : (Fin n → Ω) × Ω × Ω =>
      f (Function.update (Function.update p.1 i p.2.1) j p.2.2)) (μˢ.prod ((μs i).prod (μs j))) :=
    hmp.integrable_comp hf.aestronglyMeasurable |>.mpr hf
  -- Get a.e. slice integrability on the outer variable
  have hslice_ae : ∀ᵐ x ∂μˢ, Integrable (fun p : Ω × Ω =>
      f (Function.update (Function.update x i p.1) j p.2)) ((μs i).prod (μs j)) := by
    have := hint.prod_right_ae
    filter_upwards [this] with x hx
    convert hx using 1
  filter_upwards [hslice_ae] with x hx_int
  -- Now we can apply Fubini since we have integrability
  have hfub : ∫ y, ∫ z, f (Function.update (Function.update x i y) j z) ∂(μs j) ∂(μs i) =
              ∫ z, ∫ y, f (Function.update (Function.update x i y) j z) ∂(μs i) ∂(μs j) := by
    rw [integral_integral_swap]
    convert hx_int using 1
  rw [hfub]
  simp_rw [hcomm]

/-- Jensen: E[(E^{(j)}g)²] ≤ E[g²]. Pointwise (E^{(j)}g)² ≤ E^{(j)}[g²], then tower property. -/
lemma jensen_sq_condExpExceptCoord (j : Fin n) (g : (Fin n → Ω) → ℝ)
    (hg : Integrable g μˢ) (hg2 : Integrable (g^2) μˢ) :
    ∫ x, (condExpExceptCoord (μs := μs) j g x)^2 ∂μˢ ≤ ∫ x, (g x)^2 ∂μˢ := by
  have hcond_sq_upper : ∀ᵐ x ∂μˢ, (condExpExceptCoord (μs := μs) j g x)^2 ≤
      condExpExceptCoord (μs := μs) j (g^2) x := by
    have hf_slice_ae : ∀ᵐ x ∂μˢ, Integrable (fun y => g (Function.update x j y)) (μs j) := by
      have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 j p.2)
                 (μˢ.prod (μs j)) μˢ := by
        constructor
        · exact measurable_update' (a := j)
        · have hh : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1) :=
            (measurable_update' (a := j)).comp measurable_swap
          calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 j p.2) (μˢ.prod (μs j))
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1)
                (Measure.map Prod.swap (μˢ.prod (μs j))) := (Measure.map_map hh measurable_swap).symm
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1) ((μs j).prod μˢ) := by
                rw [Measure.prod_swap]
            _ = μˢ := map_update_prod_pi j
      have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => g (Function.update p.1 j p.2)) (μˢ.prod (μs j)) :=
        hmp.integrable_comp hg.aestronglyMeasurable |>.mpr hg
      exact hg_int.prod_right_ae
    have hf2_slice_ae : ∀ᵐ x ∂μˢ, Integrable (fun y => (g (Function.update x j y))^2) (μs j) := by
      have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 j p.2)
                 (μˢ.prod (μs j)) μˢ := by
        constructor
        · exact measurable_update' (a := j)
        · have hh : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1) :=
            (measurable_update' (a := j)).comp measurable_swap
          calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 j p.2) (μˢ.prod (μs j))
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1)
                (Measure.map Prod.swap (μˢ.prod (μs j))) := (Measure.map_map hh measurable_swap).symm
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1) ((μs j).prod μˢ) := by
                rw [Measure.prod_swap]
            _ = μˢ := map_update_prod_pi j
      have hg2_int : Integrable (fun p : (Fin n → Ω) × Ω => (g^2) (Function.update p.1 j p.2)) (μˢ.prod (μs j)) :=
        hmp.integrable_comp hg2.aestronglyMeasurable |>.mpr hg2
      exact hg2_int.prod_right_ae
    filter_upwards [hf_slice_ae, hf2_slice_ae] with x hslice_int hslice_sq_int
    -- Jensen: (∫ h dμ)² ≤ ∫ h² dμ for probability measure μ
    -- Equivalently: Var(h) ≥ 0 gives E[h²] ≥ (E[h])²
    have hslice_memLp : MemLp (fun y => g (Function.update x j y)) 2 (μs j) := by
      rw [memLp_two_iff_integrable_sq hslice_int.aestronglyMeasurable]
      exact hslice_sq_int
    have hvar := variance_nonneg (fun y => g (Function.update x j y)) (μs j)
    rw [variance_eq_sub hslice_memLp] at hvar
    simp only [condExpExceptCoord, Pi.pow_apply] at *
    linarith
  have hcond_sq_int : Integrable (condExpExceptCoord (μs := μs) j (g^2)) μˢ := by
    have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 j p.2)
               (μˢ.prod (μs j)) μˢ := by
      constructor
      · exact measurable_update' (a := j)
      · have hh : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1) :=
          (measurable_update' (a := j)).comp measurable_swap
        calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 j p.2) (μˢ.prod (μs j))
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1)
              (Measure.map Prod.swap (μˢ.prod (μs j))) := (Measure.map_map hh measurable_swap).symm
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1) ((μs j).prod μˢ) := by
              rw [Measure.prod_swap]
          _ = μˢ := map_update_prod_pi j
    have hg2_int : Integrable (fun p : (Fin n → Ω) × Ω => (g^2) (Function.update p.1 j p.2)) (μˢ.prod (μs j)) :=
      hmp.integrable_comp hg2.aestronglyMeasurable |>.mpr hg2
    convert hg2_int.integral_prod_left

  have hcond_int : Integrable (condExpExceptCoord (μs := μs) j g) μˢ := by
    have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 j p.2)
               (μˢ.prod (μs j)) μˢ := by
      constructor
      · exact measurable_update' (a := j)
      · have hh : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1) :=
          (measurable_update' (a := j)).comp measurable_swap
        calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 j p.2) (μˢ.prod (μs j))
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1)
              (Measure.map Prod.swap (μˢ.prod (μs j))) := (Measure.map_map hh measurable_swap).symm
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1) ((μs j).prod μˢ) := by
              rw [Measure.prod_swap]
          _ = μˢ := map_update_prod_pi j
    have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => g (Function.update p.1 j p.2)) (μˢ.prod (μs j)) :=
      hmp.integrable_comp hg.aestronglyMeasurable |>.mpr hg
    convert hg_int.integral_prod_left

  have hcond_sq_int' : Integrable (fun x => (condExpExceptCoord (μs := μs) j g x)^2) μˢ := by
    have hf2_slice_ae' : ∀ᵐ x ∂μˢ, Integrable (fun y => (g (Function.update x j y))^2) (μs j) := by
      have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 j p.2)
                 (μˢ.prod (μs j)) μˢ := by
        constructor
        · exact measurable_update' (a := j)
        · have hh : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1) :=
            (measurable_update' (a := j)).comp measurable_swap
          calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 j p.2) (μˢ.prod (μs j))
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1)
                (Measure.map Prod.swap (μˢ.prod (μs j))) := (Measure.map_map hh measurable_swap).symm
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1) ((μs j).prod μˢ) := by
                rw [Measure.prod_swap]
            _ = μˢ := map_update_prod_pi j
      have hg2_int : Integrable (fun p : (Fin n → Ω) × Ω => (g^2) (Function.update p.1 j p.2)) (μˢ.prod (μs j)) :=
        hmp.integrable_comp hg2.aestronglyMeasurable |>.mpr hg2
      exact hg2_int.prod_right_ae
    have hf_slice_ae' : ∀ᵐ x ∂μˢ, Integrable (fun y => g (Function.update x j y)) (μs j) := by
      have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 j p.2)
                 (μˢ.prod (μs j)) μˢ := by
        constructor
        · exact measurable_update' (a := j)
        · have hh : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1) :=
            (measurable_update' (a := j)).comp measurable_swap
          calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 j p.2) (μˢ.prod (μs j))
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1)
                (Measure.map Prod.swap (μˢ.prod (μs j))) := (Measure.map_map hh measurable_swap).symm
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 j q.1) ((μs j).prod μˢ) := by
                rw [Measure.prod_swap]
            _ = μˢ := map_update_prod_pi j
      have hg_int : Integrable (fun p : (Fin n → Ω) × Ω => g (Function.update p.1 j p.2)) (μˢ.prod (μs j)) :=
        hmp.integrable_comp hg.aestronglyMeasurable |>.mpr hg
      exact hg_int.prod_right_ae
    apply Integrable.mono' hcond_sq_int
    · exact hcond_int.aestronglyMeasurable.pow 2
    · filter_upwards [hf_slice_ae', hf2_slice_ae'] with x hslice_int hslice_sq_int
      rw [Real.norm_eq_abs, abs_sq]
      have hslice_memLp : MemLp (fun y => g (Function.update x j y)) 2 (μs j) := by
        rw [memLp_two_iff_integrable_sq hslice_int.aestronglyMeasurable]
        exact hslice_sq_int
      have hvar := variance_nonneg (fun y => g (Function.update x j y)) (μs j)
      rw [variance_eq_sub hslice_memLp] at hvar
      simp only [condExpExceptCoord, Pi.pow_apply] at *
      linarith

  calc ∫ x, (condExpExceptCoord (μs := μs) j g x)^2 ∂μˢ
    _ ≤ ∫ x, condExpExceptCoord (μs := μs) j (g^2) x ∂μˢ := by
        apply integral_mono_ae hcond_sq_int' hcond_sq_int hcond_sq_upper
    _ = ∫ x, (g x)^2 ∂μˢ := by
        -- Tower property: E[E^{(j)}[g²]] = E[g²]
        have htower := condExpExceptCoord_expectation (μs := μs) j (g^2) hg2
        simp only [Pi.pow_apply] at htower
        exact htower

/-- Conditional expectation preserves L² membership. If f ∈ L²(μˢ), then E^{(i)}f ∈ L²(μˢ).
    This follows from Jensen's inequality: E[(E^{(i)}f)²] ≤ E[f²]. -/
lemma memLp_condExpExceptCoord (i : Fin n) (f : (Fin n → Ω) → ℝ) (hf : MemLp f 2 μˢ) :
    MemLp (condExpExceptCoord (μs := μs) i f) 2 μˢ := by
  have hf_int := hf.integrable one_le_two
  have hf2 : Integrable (f^2) μˢ := hf.integrable_sq
  -- Get strong measurability - use AEStronglyMeasurable directly
  have hcond_asm : AEStronglyMeasurable (condExpExceptCoord (μs := μs) i f) μˢ := by
    -- Need StronglyMeasurable f, but we only have AEStronglyMeasurable
    -- The condExpExceptCoord of the mk equals condExpExceptCoord of f ae
    have hf_sm := hf.aestronglyMeasurable.stronglyMeasurable_mk
    have hae := hf.aestronglyMeasurable.ae_eq_mk
    have hsm := condExpExceptCoord_stronglyMeasurable (μs := μs) i
      (hf.aestronglyMeasurable.mk f) hf_sm
    -- Show condExpExceptCoord i f = condExpExceptCoord i (mk f) a.e.
    -- This follows from: f = mk f μˢ-a.e. implies the slice integrals are equal a.e.
    have hae_cond : condExpExceptCoord (μs := μs) i f =ᶠ[ae μˢ]
                    condExpExceptCoord (μs := μs) i (hf.aestronglyMeasurable.mk f) := by
      -- The update map preserves measure from μˢ × μ to μˢ
      have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
                 (μˢ.prod (μs i)) μˢ := by
        constructor
        · exact measurable_update' (a := i)
        · have hh : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
            (measurable_update' (a := i)).comp measurable_swap
          calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
                (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hh measurable_swap).symm
            _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
                rw [Measure.prod_swap]
            _ = μˢ := map_update_prod_pi i
      -- f = mk f on μˢ-a.e., so f ∘ update = (mk f) ∘ update on (μˢ × μ)-a.e.
      have hae_prod : (fun p : (Fin n → Ω) × Ω => f (Function.update p.1 i p.2)) =ᶠ[ae (μˢ.prod (μs i))]
                      (fun p => hf.aestronglyMeasurable.mk f (Function.update p.1 i p.2)) := by
        have := hmp.quasiMeasurePreserving.ae_eq hae
        filter_upwards [this] with p hp
        exact hp
      -- By Fubini: for μˢ-a.e. x, the slice functions are μ-a.e. equal
      have hslice_ae : ∀ᵐ x ∂μˢ, (fun y => f (Function.update x i y)) =ᶠ[ae (μs i)]
                       (fun y => hf.aestronglyMeasurable.mk f (Function.update x i y)) := by
        exact Measure.ae_ae_eq_curry_of_prod hae_prod
      -- Therefore the integrals are a.e. equal
      filter_upwards [hslice_ae] with x hx
      simp only [condExpExceptCoord]
      exact integral_congr_ae hx
    -- Apply AEStronglyMeasurable.congr
    exact hsm.aestronglyMeasurable.congr hae_cond.symm
  -- Use memLp_two_iff_integrable_sq
  rw [memLp_two_iff_integrable_sq hcond_asm]
  -- Need: ∫ (condExp f)² is finite
  -- We have hbound: ∫ (condExp f)² ≤ ∫ f², and ∫ f² is finite (from hf2)
  -- So ∫ (condExp f)² is finite, hence integrable
  have hcond_sq_int : Integrable (fun x => (condExpExceptCoord (μs := μs) i f x)^2) μˢ := by
    -- The conditional expectation of f² is integrable
    have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
               (μˢ.prod (μs i)) μˢ := by
      constructor
      · exact measurable_update' (a := i)
      · have hh : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
          (measurable_update' (a := i)).comp measurable_swap
        calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
              (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hh measurable_swap).symm
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
              rw [Measure.prod_swap]
          _ = μˢ := map_update_prod_pi i
    have hf2_prod : Integrable (fun p : (Fin n → Ω) × Ω => (f^2) (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
      hmp.integrable_comp hf2.aestronglyMeasurable |>.mpr hf2
    have hcondE_sq_int : Integrable (condExpExceptCoord (μs := μs) i (f^2)) μˢ := by
      convert hf2_prod.integral_prod_left
    -- Now use that (condExp f)² ≤ condExp(f²) ae (Jensen pointwise)
    -- First get slice integrability
    have hf_prod : Integrable (fun p : (Fin n → Ω) × Ω => f (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
      hmp.integrable_comp hf_int.aestronglyMeasurable |>.mpr hf_int
    have hf_slice_ae : ∀ᵐ x ∂μˢ, Integrable (fun y => f (Function.update x i y)) (μs i) :=
      hf_prod.prod_right_ae
    have hf2_slice_ae : ∀ᵐ x ∂μˢ, Integrable (fun y => (f^2) (Function.update x i y)) (μs i) :=
      hf2_prod.prod_right_ae
    -- Jensen pointwise
    have hjensen_ae : ∀ᵐ x ∂μˢ, (condExpExceptCoord (μs := μs) i f x)^2 ≤
        condExpExceptCoord (μs := μs) i (f^2) x := by
      filter_upwards [hf_slice_ae, hf2_slice_ae] with x hslice_int hslice_sq_int
      simp only [condExpExceptCoord, Pi.pow_apply]
      have hslice_sq_int' : Integrable (fun y => (f (Function.update x i y))^2) (μs i) := by
        have := hslice_sq_int
        simp only [Pi.pow_apply] at this
        exact this
      have hslice_memLp : MemLp (fun y => f (Function.update x i y)) 2 (μs i) := by
        rw [memLp_two_iff_integrable_sq hslice_int.aestronglyMeasurable]
        exact hslice_sq_int'
      have hvar := variance_nonneg (fun y => f (Function.update x i y)) (μs i)
      rw [variance_eq_sub hslice_memLp] at hvar
      simp only [Pi.pow_apply] at hvar
      linarith
    -- Bound by integrable function
    apply Integrable.mono' hcondE_sq_int
    · exact hcond_asm.pow 2
    · filter_upwards [hjensen_ae] with x hx
      -- Goal: ‖(condExpExceptCoord i f x)^2‖ ≤ condExpExceptCoord i (f^2) x
      rw [Real.norm_of_nonneg (sq_nonneg _)]
      exact hx
  exact hcond_sq_int

/-- Bound on composed conditional expectation deviations:
    E[(E^{(0)}f - E^{(j)}(E^{(0)}f))²] ≤ E[(f - E^{(j)}f)²] for j ≠ 0.
    This uses commutativity, linearity, and Jensen. -/
lemma sq_diff_condExpExceptCoord_bound [NeZero n] {j : Fin n} (h0j : (0 : Fin n) ≠ j)
    (f : (Fin n → Ω) → ℝ) (hf : MemLp f 2 μˢ) :
    ∫ x, (condExpExceptCoord (μs := μs) (0 : Fin n) f x -
          condExpExceptCoord (μs := μs) j (condExpExceptCoord (μs := μs) (0 : Fin n) f) x)^2 ∂μˢ ≤
    ∫ x, (f x - condExpExceptCoord (μs := μs) j f x)^2 ∂μˢ := by
  -- Linearity: E^{(0)}f - E^{(0)}(E^{(j)}f) = E^{(0)}(f - E^{(j)}f) a.e.
  have hlin : (fun x => condExpExceptCoord (μs := μs) (0 : Fin n) f x -
               condExpExceptCoord (μs := μs) (0 : Fin n) (condExpExceptCoord (μs := μs) j f) x) =ᶠ[ae μˢ]
              (fun x => condExpExceptCoord (μs := μs) (0 : Fin n) (fun y => f y - condExpExceptCoord (μs := μs) j f y) x) := by
    -- First establish a.e. slice integrability
    have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 (0 : Fin n) p.2)
               (μˢ.prod (μs 0)) μˢ := by
      constructor
      · exact measurable_update' (a := (0 : Fin n))
      · have hh : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 (0 : Fin n) q.1) :=
          (measurable_update' (a := (0 : Fin n))).comp measurable_swap
        calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 (0 : Fin n) p.2) (μˢ.prod (μs 0))
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 (0 : Fin n) q.1)
              (Measure.map Prod.swap (μˢ.prod (μs 0))) := (Measure.map_map hh measurable_swap).symm
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 (0 : Fin n) q.1) ((μs 0).prod μˢ) := by
              rw [Measure.prod_swap]
          _ = μˢ := map_update_prod_pi (0 : Fin n)
    have hf_prod : Integrable (fun p : (Fin n → Ω) × Ω => f (Function.update p.1 (0 : Fin n) p.2)) (μˢ.prod (μs 0)) :=
      hmp.integrable_comp (hf.integrable one_le_two).aestronglyMeasurable |>.mpr (hf.integrable one_le_two)
    have hint_f : ∀ᵐ x ∂μˢ, Integrable (fun y => f (Function.update x (0 : Fin n) y)) (μs 0) :=
      hf_prod.prod_right_ae
    have hcond_f := memLp_condExpExceptCoord j f hf
    have hcond_prod : Integrable (fun p : (Fin n → Ω) × Ω => condExpExceptCoord (μs := μs) j f (Function.update p.1 (0 : Fin n) p.2)) (μˢ.prod (μs 0)) :=
      hmp.integrable_comp (hcond_f.integrable one_le_two).aestronglyMeasurable |>.mpr (hcond_f.integrable one_le_two)
    have hint_cond : ∀ᵐ x ∂μˢ, Integrable (fun y => condExpExceptCoord (μs := μs) j f (Function.update x (0 : Fin n) y)) (μs 0) :=
      hcond_prod.prod_right_ae
    -- Now use filter_upwards with both ae integrability hypotheses
    filter_upwards [hint_f, hint_cond] with x hx_f hx_cond
    show ∫ y, f (Function.update x 0 y) ∂(μs 0) - ∫ y, condExpExceptCoord (μs := μs) j f (Function.update x 0 y) ∂(μs 0) =
         ∫ y, (f (Function.update x 0 y) - condExpExceptCoord (μs := μs) j f (Function.update x 0 y)) ∂(μs 0)
    exact (integral_sub hx_f hx_cond).symm
  -- Apply Jensen to g = f - E^{(j)}f
  let g := fun y => f y - condExpExceptCoord (μs := μs) j f y
  have hg : MemLp g 2 μˢ := hf.sub (memLp_condExpExceptCoord j f hf)
  have hg_int := hg.integrable one_le_two
  have hg2 := hg.integrable_sq
  have hjensenG := jensen_sq_condExpExceptCoord (0 : Fin n) g hg_int hg2
  -- Need to connect the LHS with condExp of g
  have hae_eq : (fun x => condExpExceptCoord (μs := μs) (0 : Fin n) f x -
                 condExpExceptCoord (μs := μs) j (condExpExceptCoord (μs := μs) (0 : Fin n) f) x) =ᶠ[ae μˢ]
                (fun x => condExpExceptCoord (μs := μs) (0 : Fin n) g x) := by
    have hcomm' := condExpExceptCoord_comm_ae h0j f (hf.integrable one_le_two)
    filter_upwards [hcomm', hlin] with x hx1 hx2
    rw [← hx1, hx2]
  calc ∫ x, (condExpExceptCoord (μs := μs) (0 : Fin n) f x -
             condExpExceptCoord (μs := μs) j (condExpExceptCoord (μs := μs) (0 : Fin n) f) x)^2 ∂μˢ
    _ = ∫ x, (condExpExceptCoord (μs := μs) (0 : Fin n) g x)^2 ∂μˢ := by
        apply integral_congr_ae
        filter_upwards [hae_eq] with x hx
        rw [hx]
    _ ≤ ∫ x, (g x)^2 ∂μˢ := hjensenG
    _ = ∫ x, (f x - condExpExceptCoord (μs := μs) j f x)^2 ∂μˢ := rfl

/-- Generalized contraction: E[(E^{(i)}f - E^{(j)}(E^{(i)}f))²] ≤ E[(f - E^{(j)}f)²] for any i ≠ j.
    This extends sq_diff_condExpExceptCoord_bound to arbitrary pairs of coordinates. -/
lemma sq_diff_condExpExceptCoord_bound_gen [NeZero n] {i j : Fin n} (hij : i ≠ j)
    (f : (Fin n → Ω) → ℝ) (hf : MemLp f 2 μˢ) :
    ∫ x, (condExpExceptCoord (μs := μs) i f x -
          condExpExceptCoord (μs := μs) j (condExpExceptCoord (μs := μs) i f) x)^2 ∂μˢ ≤
    ∫ x, (f x - condExpExceptCoord (μs := μs) j f x)^2 ∂μˢ := by
  -- Linearity: E^{(i)}f - E^{(i)}(E^{(j)}f) = E^{(i)}(f - E^{(j)}f) a.e.
  have hlin : (fun x => condExpExceptCoord (μs := μs) i f x -
               condExpExceptCoord (μs := μs) i (condExpExceptCoord (μs := μs) j f) x) =ᶠ[ae μˢ]
              (fun x => condExpExceptCoord (μs := μs) i (fun y => f y - condExpExceptCoord (μs := μs) j f y) x) := by
    have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
               (μˢ.prod (μs i)) μˢ := by
      constructor
      · exact measurable_update' (a := i)
      · have hh : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
          (measurable_update' (a := i)).comp measurable_swap
        calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
              (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hh measurable_swap).symm
          _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
              rw [Measure.prod_swap]
          _ = μˢ := map_update_prod_pi i
    have hf_prod : Integrable (fun p : (Fin n → Ω) × Ω => f (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
      hmp.integrable_comp (hf.integrable one_le_two).aestronglyMeasurable |>.mpr (hf.integrable one_le_two)
    have hint_f : ∀ᵐ x ∂μˢ, Integrable (fun y => f (Function.update x i y)) (μs i) :=
      hf_prod.prod_right_ae
    have hcond_f := memLp_condExpExceptCoord j f hf
    have hcond_prod : Integrable (fun p : (Fin n → Ω) × Ω => condExpExceptCoord (μs := μs) j f (Function.update p.1 i p.2)) (μˢ.prod (μs i)) :=
      hmp.integrable_comp (hcond_f.integrable one_le_two).aestronglyMeasurable |>.mpr (hcond_f.integrable one_le_two)
    have hint_cond : ∀ᵐ x ∂μˢ, Integrable (fun y => condExpExceptCoord (μs := μs) j f (Function.update x i y)) (μs i) :=
      hcond_prod.prod_right_ae
    filter_upwards [hint_f, hint_cond] with x hx_f hx_cond
    show ∫ y, f (Function.update x i y) ∂(μs i) - ∫ y, condExpExceptCoord (μs := μs) j f (Function.update x i y) ∂(μs i) =
         ∫ y, (f (Function.update x i y) - condExpExceptCoord (μs := μs) j f (Function.update x i y)) ∂(μs i)
    exact (integral_sub hx_f hx_cond).symm
  -- Apply Jensen to g = f - E^{(j)}f
  let g := fun y => f y - condExpExceptCoord (μs := μs) j f y
  have hg : MemLp g 2 μˢ := hf.sub (memLp_condExpExceptCoord j f hf)
  have hg_int := hg.integrable one_le_two
  have hg2 := hg.integrable_sq
  have hjensenG := jensen_sq_condExpExceptCoord i g hg_int hg2
  have hae_eq : (fun x => condExpExceptCoord (μs := μs) i f x -
                 condExpExceptCoord (μs := μs) j (condExpExceptCoord (μs := μs) i f) x) =ᶠ[ae μˢ]
                (fun x => condExpExceptCoord (μs := μs) i g x) := by
    have hcomm' := condExpExceptCoord_comm_ae hij f (hf.integrable one_le_two)
    filter_upwards [hcomm', hlin] with x hx1 hx2
    rw [← hx1, hx2]
  calc ∫ x, (condExpExceptCoord (μs := μs) i f x -
             condExpExceptCoord (μs := μs) j (condExpExceptCoord (μs := μs) i f) x)^2 ∂μˢ
    _ = ∫ x, (condExpExceptCoord (μs := μs) i g x)^2 ∂μˢ := by
        apply integral_congr_ae
        filter_upwards [hae_eq] with x hx
        rw [hx]
    _ ≤ ∫ x, (g x)^2 ∂μˢ := hjensenG
    _ = ∫ x, (f x - condExpExceptCoord (μs := μs) j f x)^2 ∂μˢ := rfl

/-- Idempotence of conditional expectation: E^{(i)}(E^{(i)}f) = E^{(i)}f.
    Since E^{(i)}f doesn't depend on coordinate i, integrating over i again gives the same result. -/
lemma condExpExceptCoord_idempotent (i : Fin n) (f : (Fin n → Ω) → ℝ) :
    condExpExceptCoord (μs := μs) i (condExpExceptCoord (μs := μs) i f) =
    condExpExceptCoord (μs := μs) i f := by
  ext x
  simp only [condExpExceptCoord]
  have hinner : ∀ y, ∫ z, f (Function.update (Function.update x i y) i z) ∂(μs i) =
      ∫ z, f (Function.update x i z) ∂(μs i) := by
    intro y
    congr 1 with z
    rw [Function.update_idem]
  simp_rw [hinner]
  rw [integral_const]
  have hprob : (μs i).real Set.univ = 1 := by
    rw [Measure.real, IsProbabilityMeasure.measure_univ, ENNReal.toReal_one]
  rw [hprob, one_smul]

end Tensorization

/-!
## Main Theorem: Efron-Stein Inequality
-/

section MainTheorem

/-- **Efron-Stein Inequality**

For independent random variables and a square-integrable function f:
  Var(f) ≤ ∑ᵢ E[(f - E^{(i)}f)²]

where E^{(i)}f is the conditional expectation given all variables except Xᵢ. -/
theorem efronStein (f : (Fin n → Ω) → ℝ) (hf : MemLp f 2 μˢ) :
    variance f μˢ ≤ ∑ i : Fin n, ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μˢ := by
  -- Capture the section instance before pattern matching (avoids shadowing issues)
  have hPM_section : ∀ i : Fin n, IsProbabilityMeasure (μs i) := inferInstance
  -- Case analysis on n (no induction hypothesis is needed)
  match n with
  | 0 =>
    simp only [Fin.sum_univ_zero]
    have hconst : f = fun _ => f default :=
      funext (fun x => congr_arg f (Subsingleton.elim x default))
    haveI : ∀ i : Fin 0, IsProbabilityMeasure (μs i) := fun i => i.elim0
    haveI : IsProbabilityMeasure μˢ := inferInstance
    rw [hconst, variance, evariance]
    simp only [integral_const, probReal_univ, one_smul, sq, sub_self]
    simp
  | 1 =>
    rw [Fin.sum_univ_one]
    let μ_pi : Measure (Fin 1 → Ω) := Measure.pi μs
    by_cases hne : Nonempty Ω
    case neg =>
      simp only [not_nonempty_iff] at hne
      have hemp : IsEmpty (Fin 1 → Ω) := ⟨fun f' => hne.elim (f' 0)⟩
      simp [variance, evariance, integral_of_isEmpty]
    case pos =>
      obtain ⟨ω₀⟩ := hne
      have hupd : ∀ (x : Fin 1 → Ω) (y : Ω), Function.update x 0 y = fun _ : Fin 1 => y := by
        intro x y; ext i; fin_cases i
        simp only [Function.update, Fin.zero_eta, dite_eq_ite, ↓reduceIte, Fin.isValue]
      have hexp_const : ∀ x₁ x₂ : Fin 1 → Ω, condExpExceptCoord (μs := μs) (0 : Fin 1) f x₁ =
          condExpExceptCoord (μs := μs) (0 : Fin 1) f x₂ := by
        intro x₁ x₂
        simp only [condExpExceptCoord, hupd]
      let x₀ : Fin 1 → Ω := fun _ => ω₀
      set c := condExpExceptCoord (μs := μs) (0 : Fin 1) f x₀ with hc_def
      have hexp : ∀ x, condExpExceptCoord (μs := μs) (0 : Fin 1) f x = c := fun x => hexp_const x x₀
      conv_lhs => rw [variance_eq_integral hf.aemeasurable]
      conv_rhs => simp only [hexp]
      suffices hc_eq : c = ∫ z, f z ∂μ_pi by simp only [hc_eq, μ_pi]; exact le_rfl
      simp only [hc_def, condExpExceptCoord]
      simp_rw [hupd]
      let e := MeasurableEquiv.funUnique (Fin 1) Ω
      have hμ_eq : Measure.pi μs = Measure.pi (fun _ : Fin 1 => μs 0) := by
        congr 1; ext i; fin_cases i; rfl
      have hmp := measurePreserving_funUnique (μs 0) (Fin 1)
      have hpi_map : Measure.pi (fun _ : Fin 1 => μs 0) = (μs 0).map e.symm := by
        have h1 := hmp.map_eq
        have h2 : (Measure.map e (Measure.pi (fun _ : Fin 1 => μs 0))).map e.symm = (μs 0).map e.symm := by
          rw [h1]
        rw [MeasurableEquiv.map_symm_map] at h2
        exact h2
      have hf_ae : AEStronglyMeasurable f ((μs 0).map e.symm) := by
        rw [← hpi_map, ← hμ_eq]
        exact hf.aestronglyMeasurable
      have heq : ∫ z, f z ∂μ_pi = ∫ y, f (e.symm y) ∂(μs 0) := by
        calc ∫ z, f z ∂μ_pi = ∫ z, f z ∂Measure.pi μs := rfl
          _ = ∫ z, f z ∂Measure.pi (fun _ : Fin 1 => μs 0) := by rw [hμ_eq]
          _ = ∫ z, f z ∂(μs 0).map e.symm := by rw [hpi_map]
          _ = ∫ y, f (e.symm y) ∂(μs 0) := integral_map e.symm.measurable.aemeasurable hf_ae
      rw [heq]
      congr 1 with y
  | k + 2 =>
    let μ_curr : Measure (Fin (k+2) → Ω) := Measure.pi μs
    haveI hPM : ∀ i : Fin (k+2), IsProbabilityMeasure (μs i) := hPM_section
    haveI : IsProbabilityMeasure μ_curr := inferInstance
    haveI : SFinite μ_curr := inferInstance
    haveI : ∀ i : Fin (k+2), SFinite (μs i) := fun i => inferInstance
    haveI : ∀ i : Fin (k+2), IsFiniteMeasure (μs i) := fun i => inferInstance

    have hcond_int_i : ∀ i : Fin ((k+1)+1), Integrable (condExpExceptCoord (μs := μs) i f) μ_curr := by
      intro i
      have hmp : MeasurePreserving (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 i p.2)
                 (μ_curr.prod (μs i)) μ_curr := by
        constructor
        · exact measurable_update' (a := i)
        · have hg : Measurable (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1) :=
            (measurable_update' (a := i)).comp measurable_swap
          calc Measure.map (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 i p.2) (μ_curr.prod (μs i))
            _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1)
                (Measure.map Prod.swap (μ_curr.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
            _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1) ((μs i).prod μ_curr) := by
                rw [Measure.prod_swap]
            _ = μ_curr := map_update_prod_pi i
      have hg_int : Integrable (fun p : (Fin ((k+1)+1) → Ω) × Ω => f (Function.update p.1 i p.2)) (μ_curr.prod (μs i)) :=
        hmp.integrable_comp (hf.integrable one_le_two).aestronglyMeasurable |>.mpr (hf.integrable one_le_two)
      convert hg_int.integral_prod_left

    have hsum_nonneg : 0 ≤ ∑ i : Fin ((k+1)+1), ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μ_curr := by
      apply Finset.sum_nonneg
      intro i _
      apply integral_nonneg (fun x => sq_nonneg _)

    have heach_term : ∀ i : Fin ((k+1)+1), ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μ_curr ≤
        variance f μ_curr := by
      intro i
      have htv := total_variance_identity (μs := μs) i f hf
      have hvar_cond := variance_nonneg (condExpExceptCoord (μs := μs) i f) μ_curr
      have hf2' := hf.integrable_sq
      have hcond_sq_int : Integrable (condExpExceptCoord (μs := μs) i (f ^ 2)) μ_curr := by
        have hmp : MeasurePreserving (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 i p.2)
                   (μ_curr.prod (μs i)) μ_curr := by
          constructor
          · exact measurable_update' (a := i)
          · have hg : Measurable (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1) :=
              (measurable_update' (a := i)).comp measurable_swap
            calc Measure.map (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 i p.2) (μ_curr.prod (μs i))
              _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1)
                  (Measure.map Prod.swap (μ_curr.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
              _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1) ((μs i).prod μ_curr) := by
                  rw [Measure.prod_swap]
              _ = μ_curr := map_update_prod_pi i
        have hg_int : Integrable (fun p : (Fin ((k+1)+1) → Ω) × Ω => (f ^ 2) (Function.update p.1 i p.2)) (μ_curr.prod (μs i)) :=
          hmp.integrable_comp hf2'.aestronglyMeasurable |>.mpr hf2'
        convert hg_int.integral_prod_left
      have hf2_slice_ae : ∀ᵐ x ∂μ_curr, Integrable (fun y => f (Function.update x i y) ^ 2) (μs i) := by
        have hmp : MeasurePreserving (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 i p.2)
                   (μ_curr.prod (μs i)) μ_curr := by
          constructor
          · exact measurable_update' (a := i)
          · have hg : Measurable (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1) :=
              (measurable_update' (a := i)).comp measurable_swap
            calc Measure.map (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 i p.2) (μ_curr.prod (μs i))
              _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1)
                  (Measure.map Prod.swap (μ_curr.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
              _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1) ((μs i).prod μ_curr) := by
                  rw [Measure.prod_swap]
              _ = μ_curr := map_update_prod_pi i
        have hg_int : Integrable (fun p : (Fin ((k+1)+1) → Ω) × Ω => (f ^ 2) (Function.update p.1 i p.2)) (μ_curr.prod (μs i)) :=
          hmp.integrable_comp hf2'.aestronglyMeasurable |>.mpr hf2'
        exact hg_int.prod_right_ae
      have hf_slice_ae : ∀ᵐ x ∂μ_curr, Integrable (fun y => f (Function.update x i y)) (μs i) := by
        have hmp : MeasurePreserving (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 i p.2)
                   (μ_curr.prod (μs i)) μ_curr := by
          constructor
          · exact measurable_update' (a := i)
          · have hg : Measurable (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1) :=
              (measurable_update' (a := i)).comp measurable_swap
            calc Measure.map (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 i p.2) (μ_curr.prod (μs i))
              _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1)
                  (Measure.map Prod.swap (μ_curr.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
              _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1) ((μs i).prod μ_curr) := by
                  rw [Measure.prod_swap]
              _ = μ_curr := map_update_prod_pi i
        have hg_int : Integrable (fun p : (Fin ((k+1)+1) → Ω) × Ω => f (Function.update p.1 i p.2)) (μ_curr.prod (μs i)) :=
          hmp.integrable_comp (hf.integrable one_le_two).aestronglyMeasurable |>.mpr (hf.integrable one_le_two)
        exact hg_int.prod_right_ae
      have hsq_int : Integrable (fun z => (condExpExceptCoord (μs := μs) i f z)^2) μ_curr := by
        apply Integrable.mono' hcond_sq_int
        · exact (hcond_int_i i).aestronglyMeasurable.pow 2
        · filter_upwards [hf_slice_ae, hf2_slice_ae] with x hslice_int hslice_sq_int
          rw [Real.norm_eq_abs, abs_sq]
          have hslice_memLp : MemLp (fun y => f (Function.update x i y)) 2 (μs i) := by
            rw [memLp_two_iff_integrable_sq hslice_int.aestronglyMeasurable]
            exact hslice_sq_int
          have hvar := variance_nonneg (fun y => f (Function.update x i y)) (μs i)
          rw [variance_eq_sub hslice_memLp] at hvar
          simp only [condExpExceptCoord, Pi.pow_apply] at *
          linarith
      have hcond_memLp : MemLp (condExpExceptCoord (μs := μs) i f) 2 μ_curr := by
        rw [memLp_two_iff_integrable_sq (hcond_int_i i).aestronglyMeasurable]
        exact hsq_int
      have hdiff_memLp : MemLp (fun x => f x - condExpExceptCoord (μs := μs) i f x) 2 μ_curr :=
        hf.sub hcond_memLp
      have hf2_int : Integrable (fun x => (f x - condExpExceptCoord (μs := μs) i f x)^2) μ_curr :=
        hdiff_memLp.integrable_sq
      have hcondVar := expectation_sq_diff_eq_expectation_condVar (f := f) i (hf.integrable one_le_two) hf2_int
      linarith

    have h_condVar : ∀ i, ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μ_curr =
        variance f μ_curr - variance (condExpExceptCoord (μs := μs) i f) μ_curr := by
      intro i
      have htv := total_variance_identity (μs := μs) i f hf
      have hf2' := hf.integrable_sq
      have hcond_sq_int : Integrable (condExpExceptCoord (μs := μs) i (f ^ 2)) μ_curr := by
        have hmp : MeasurePreserving (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 i p.2)
                   (μ_curr.prod (μs i)) μ_curr := by
          constructor
          · exact measurable_update' (a := i)
          · have hg : Measurable (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1) :=
              (measurable_update' (a := i)).comp measurable_swap
            calc Measure.map (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 i p.2) (μ_curr.prod (μs i))
              _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1)
                  (Measure.map Prod.swap (μ_curr.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
              _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1) ((μs i).prod μ_curr) := by
                  rw [Measure.prod_swap]
              _ = μ_curr := map_update_prod_pi i
        have hg_int : Integrable (fun p : (Fin ((k+1)+1) → Ω) × Ω => (f ^ 2) (Function.update p.1 i p.2)) (μ_curr.prod (μs i)) :=
          hmp.integrable_comp hf2'.aestronglyMeasurable |>.mpr hf2'
        convert hg_int.integral_prod_left
      have hf2_slice_ae : ∀ᵐ x ∂μ_curr, Integrable (fun y => f (Function.update x i y) ^ 2) (μs i) := by
        have hmp : MeasurePreserving (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 i p.2)
                   (μ_curr.prod (μs i)) μ_curr := by
          constructor
          · exact measurable_update' (a := i)
          · have hg : Measurable (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1) :=
              (measurable_update' (a := i)).comp measurable_swap
            calc Measure.map (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 i p.2) (μ_curr.prod (μs i))
              _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1)
                  (Measure.map Prod.swap (μ_curr.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
              _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1) ((μs i).prod μ_curr) := by
                  rw [Measure.prod_swap]
              _ = μ_curr := map_update_prod_pi i
        have hg_int : Integrable (fun p : (Fin ((k+1)+1) → Ω) × Ω => (f ^ 2) (Function.update p.1 i p.2)) (μ_curr.prod (μs i)) :=
          hmp.integrable_comp hf2'.aestronglyMeasurable |>.mpr hf2'
        exact hg_int.prod_right_ae
      have hf_slice_ae : ∀ᵐ x ∂μ_curr, Integrable (fun y => f (Function.update x i y)) (μs i) := by
        have hmp : MeasurePreserving (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 i p.2)
                   (μ_curr.prod (μs i)) μ_curr := by
          constructor
          · exact measurable_update' (a := i)
          · have hg : Measurable (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1) :=
              (measurable_update' (a := i)).comp measurable_swap
            calc Measure.map (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 i p.2) (μ_curr.prod (μs i))
              _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1)
                  (Measure.map Prod.swap (μ_curr.prod (μs i))) := (Measure.map_map hg measurable_swap).symm
              _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 i q.1) ((μs i).prod μ_curr) := by
                  rw [Measure.prod_swap]
              _ = μ_curr := map_update_prod_pi i
        have hg_int : Integrable (fun p : (Fin ((k+1)+1) → Ω) × Ω => f (Function.update p.1 i p.2)) (μ_curr.prod (μs i)) :=
          hmp.integrable_comp (hf.integrable one_le_two).aestronglyMeasurable |>.mpr (hf.integrable one_le_two)
        exact hg_int.prod_right_ae
      have hsq_int : Integrable (fun z => (condExpExceptCoord (μs := μs) i f z)^2) μ_curr := by
        apply Integrable.mono' hcond_sq_int
        · exact (hcond_int_i i).aestronglyMeasurable.pow 2
        · filter_upwards [hf_slice_ae, hf2_slice_ae] with x hslice_int hslice_sq_int
          rw [Real.norm_eq_abs, abs_sq]
          have hslice_memLp : MemLp (fun y => f (Function.update x i y)) 2 (μs i) := by
            rw [memLp_two_iff_integrable_sq hslice_int.aestronglyMeasurable]
            exact hslice_sq_int
          have hvar := variance_nonneg (fun y => f (Function.update x i y)) (μs i)
          rw [variance_eq_sub hslice_memLp] at hvar
          simp only [condExpExceptCoord, Pi.pow_apply] at *
          linarith
      have hcond_memLp : MemLp (condExpExceptCoord (μs := μs) i f) 2 μ_curr := by
        rw [memLp_two_iff_integrable_sq (hcond_int_i i).aestronglyMeasurable]
        exact hsq_int
      have hdiff_memLp : MemLp (fun x => f x - condExpExceptCoord (μs := μs) i f x) 2 μ_curr :=
        hf.sub hcond_memLp
      have hf2_int : Integrable (fun x => (f x - condExpExceptCoord (μs := μs) i f x)^2) μ_curr :=
        hdiff_memLp.integrable_sq
      have hcondVar := expectation_sq_diff_eq_expectation_condVar (f := f) i (hf.integrable one_le_two) hf2_int
      linarith

    have h_sum : ∑ i : Fin ((k + 1) + 1), ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μ_curr =
        ((k + 1) + 1 : ℕ) * variance f μ_curr -
        ∑ i, variance (condExpExceptCoord (μs := μs) i f) μ_curr := by
      simp_rw [h_condVar]
      rw [Finset.sum_sub_distrib, Finset.sum_const, Finset.card_fin]
      simp only [nsmul_eq_mul, Nat.cast_add, Nat.cast_one]

    have hvar_cond_nonneg : ∀ i, 0 ≤ variance (condExpExceptCoord (μs := μs) i f) μ_curr := by
      intro i
      exact variance_nonneg _ _

    have hvar_nonneg := variance_nonneg f μ_curr

    have hvar_cond_le : ∀ i, variance (condExpExceptCoord (μs := μs) i f) μ_curr ≤ variance f μ_curr := by
      intro i
      have hcv := h_condVar i
      have h_nonneg : 0 ≤ ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μ_curr :=
        integral_nonneg (fun x => sq_nonneg _)
      linarith

    have htv0 := total_variance_identity (μs := μs) (0 : Fin ((k+1)+1)) f hf

    have hfirst : ∫ x, (f x - condExpExceptCoord (μs := μs) 0 f x)^2 ∂μ_curr =
        variance f μ_curr - variance (condExpExceptCoord (μs := μs) 0 f) μ_curr :=
      h_condVar 0

    have hrest_nonneg : 0 ≤ ∑ i : Fin ((k+1)+1) with i ≠ 0,
        ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μ_curr := by
      apply Finset.sum_nonneg
      intro i _
      apply integral_nonneg (fun x => sq_nonneg _)

    have hsplit : ∑ i : Fin ((k+1)+1), ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μ_curr =
        ∫ x, (f x - condExpExceptCoord (μs := μs) 0 f x)^2 ∂μ_curr +
        ∑ i : Fin ((k+1)+1) with i ≠ 0, ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μ_curr := by
      rw [← Finset.add_sum_erase _ _ (Finset.mem_univ (0 : Fin ((k+1)+1)))]
      congr 1
      apply Finset.sum_congr
      · ext i
        simp only [Finset.mem_erase, Finset.mem_univ, Finset.mem_filter, and_true, ne_eq]
        tauto
      · intro _ _; rfl

    have hrest_eq : ∑ i : Fin ((k+1)+1) with i ≠ 0,
        ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μ_curr =
        (k + 1 : ℕ) * variance f μ_curr -
        ∑ i : Fin ((k+1)+1) with i ≠ 0, variance (condExpExceptCoord (μs := μs) i f) μ_curr := by
      have hstep : ∑ i : Fin ((k+1)+1) with i ≠ 0, ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μ_curr =
          ∑ i : Fin ((k+1)+1) with i ≠ 0, (variance f μ_curr - variance (condExpExceptCoord (μs := μs) i f) μ_curr) := by
        apply Finset.sum_congr rfl
        intro i _
        exact h_condVar i
      rw [hstep, Finset.sum_sub_distrib]
      congr 1
      rw [Finset.sum_const]
      have hcard : (Finset.filter (fun i => i ≠ 0) (Finset.univ : Finset (Fin ((k+1)+1)))).card = k + 1 := by
        rw [Finset.filter_ne', Finset.card_erase_of_mem (Finset.mem_univ (0 : Fin ((k+1)+1)))]
        simp only [Finset.card_univ, Fintype.card_fin]
        omega
      simp only [hcard, nsmul_eq_mul]

    -- Key bound via tensorization: Var(E^{(0)}f) ≤ ∑_{i≠0} E[(f - E^{(i)}f)²]
    have hkey_bound : variance (condExpExceptCoord (μs := μs) (0 : Fin ((k+1)+1)) f) μ_curr ≤
        ∑ i : Fin ((k+1)+1) with i ≠ 0,
          ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μ_curr := by
      let g := condExpExceptCoord (μs := μs) (0 : Fin ((k+1)+1)) f

      have h_sq_bound : ∀ j : Fin ((k+1)+1), j ≠ 0 →
          ∫ x, (g x - condExpExceptCoord (μs := μs) j g x)^2 ∂μ_curr ≤
          ∫ x, (f x - condExpExceptCoord (μs := μs) j f x)^2 ∂μ_curr := by
        intro j hj
        exact sq_diff_condExpExceptCoord_bound (Ne.symm hj) f hf

      have h_sum_bound : ∑ j : Fin ((k+1)+1) with j ≠ 0,
          ∫ x, (g x - condExpExceptCoord (μs := μs) j g x)^2 ∂μ_curr ≤
          ∑ j : Fin ((k+1)+1) with j ≠ 0,
          ∫ x, (f x - condExpExceptCoord (μs := μs) j f x)^2 ∂μ_curr := by
        apply Finset.sum_le_sum
        intro j hj
        simp only [Finset.mem_filter, Finset.mem_univ, true_and] at hj
        exact h_sq_bound j hj

      have h_idem_term : ∫ x, (g x - condExpExceptCoord (μs := μs) 0 g x)^2 ∂μ_curr = 0 := by
        have hidem : condExpExceptCoord (μs := μs) (0 : Fin ((k+1)+1)) g = g := by
          exact condExpExceptCoord_idempotent 0 f
        simp only [hidem, sub_self, sq, mul_zero, integral_zero]

      have hg_memLp : MemLp g 2 μ_curr := memLp_condExpExceptCoord 0 f hf

      have hg_condVar : ∀ j : Fin ((k+1)+1),
          ∫ x, (g x - condExpExceptCoord (μs := μs) j g x)^2 ∂μ_curr =
          variance g μ_curr - variance (condExpExceptCoord (μs := μs) j g) μ_curr := by
        intro j
        have htv := total_variance_identity (μs := μs) j g hg_memLp
        have hg_int := hg_memLp.integrable one_le_two
        have hg2 := hg_memLp.integrable_sq
        have hcond_g_int : Integrable (condExpExceptCoord (μs := μs) j g) μ_curr := by
          have hmp : MeasurePreserving (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 j p.2)
                     (μ_curr.prod (μs j)) μ_curr := by
            constructor
            · exact measurable_update' (a := j)
            · have hgg : Measurable (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 j q.1) :=
                (measurable_update' (a := j)).comp measurable_swap
              calc Measure.map (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 j p.2) (μ_curr.prod (μs j))
                _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 j q.1)
                    (Measure.map Prod.swap (μ_curr.prod (μs j))) := (Measure.map_map hgg measurable_swap).symm
                _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 j q.1) ((μs j).prod μ_curr) := by
                    rw [Measure.prod_swap]
                _ = μ_curr := map_update_prod_pi j
          have hg_prod_int : Integrable (fun p : (Fin ((k+1)+1) → Ω) × Ω => g (Function.update p.1 j p.2)) (μ_curr.prod (μs j)) :=
            hmp.integrable_comp hg_int.aestronglyMeasurable |>.mpr hg_int
          convert hg_prod_int.integral_prod_left
        have hcond_g_sq_int : Integrable (condExpExceptCoord (μs := μs) j (g ^ 2)) μ_curr := by
          have hmp : MeasurePreserving (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 j p.2)
                     (μ_curr.prod (μs j)) μ_curr := by
            constructor
            · exact measurable_update' (a := j)
            · have hgg : Measurable (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 j q.1) :=
                (measurable_update' (a := j)).comp measurable_swap
              calc Measure.map (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 j p.2) (μ_curr.prod (μs j))
                _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 j q.1)
                    (Measure.map Prod.swap (μ_curr.prod (μs j))) := (Measure.map_map hgg measurable_swap).symm
                _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 j q.1) ((μs j).prod μ_curr) := by
                    rw [Measure.prod_swap]
                _ = μ_curr := map_update_prod_pi j
          have hg_prod_int : Integrable (fun p : (Fin ((k+1)+1) → Ω) × Ω => (g ^ 2) (Function.update p.1 j p.2)) (μ_curr.prod (μs j)) :=
            hmp.integrable_comp hg2.aestronglyMeasurable |>.mpr hg2
          convert hg_prod_int.integral_prod_left
        have hg2_slice_ae : ∀ᵐ x ∂μ_curr, Integrable (fun y => g (Function.update x j y) ^ 2) (μs j) := by
          have hmp : MeasurePreserving (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 j p.2)
                     (μ_curr.prod (μs j)) μ_curr := by
            constructor
            · exact measurable_update' (a := j)
            · have hgg : Measurable (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 j q.1) :=
                (measurable_update' (a := j)).comp measurable_swap
              calc Measure.map (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 j p.2) (μ_curr.prod (μs j))
                _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 j q.1)
                    (Measure.map Prod.swap (μ_curr.prod (μs j))) := (Measure.map_map hgg measurable_swap).symm
                _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 j q.1) ((μs j).prod μ_curr) := by
                    rw [Measure.prod_swap]
                _ = μ_curr := map_update_prod_pi j
          have hg_prod_int : Integrable (fun p : (Fin ((k+1)+1) → Ω) × Ω => (g ^ 2) (Function.update p.1 j p.2)) (μ_curr.prod (μs j)) :=
            hmp.integrable_comp hg2.aestronglyMeasurable |>.mpr hg2
          exact hg_prod_int.prod_right_ae
        have hg_slice_ae : ∀ᵐ x ∂μ_curr, Integrable (fun y => g (Function.update x j y)) (μs j) := by
          have hmp : MeasurePreserving (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 j p.2)
                     (μ_curr.prod (μs j)) μ_curr := by
            constructor
            · exact measurable_update' (a := j)
            · have hgg : Measurable (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 j q.1) :=
                (measurable_update' (a := j)).comp measurable_swap
              calc Measure.map (fun p : (Fin ((k+1)+1) → Ω) × Ω => Function.update p.1 j p.2) (μ_curr.prod (μs j))
                _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 j q.1)
                    (Measure.map Prod.swap (μ_curr.prod (μs j))) := (Measure.map_map hgg measurable_swap).symm
                _ = Measure.map (fun q : Ω × (Fin ((k+1)+1) → Ω) => Function.update q.2 j q.1) ((μs j).prod μ_curr) := by
                    rw [Measure.prod_swap]
                _ = μ_curr := map_update_prod_pi j
          have hg_prod_int : Integrable (fun p : (Fin ((k+1)+1) → Ω) × Ω => g (Function.update p.1 j p.2)) (μ_curr.prod (μs j)) :=
            hmp.integrable_comp hg_int.aestronglyMeasurable |>.mpr hg_int
          exact hg_prod_int.prod_right_ae
        have hsq_int : Integrable (fun z => (condExpExceptCoord (μs := μs) j g z)^2) μ_curr := by
          apply Integrable.mono' hcond_g_sq_int
          · exact hcond_g_int.aestronglyMeasurable.pow 2
          · filter_upwards [hg_slice_ae, hg2_slice_ae] with x hslice_int hslice_sq_int
            rw [Real.norm_eq_abs, abs_sq]
            have hslice_memLp : MemLp (fun y => g (Function.update x j y)) 2 (μs j) := by
              rw [memLp_two_iff_integrable_sq hslice_int.aestronglyMeasurable]
              exact hslice_sq_int
            have hvar := variance_nonneg (fun y => g (Function.update x j y)) (μs j)
            rw [variance_eq_sub hslice_memLp] at hvar
            simp only [condExpExceptCoord, Pi.pow_apply] at *
            linarith
        have hcond_g_memLp : MemLp (condExpExceptCoord (μs := μs) j g) 2 μ_curr := by
          rw [memLp_two_iff_integrable_sq hcond_g_int.aestronglyMeasurable]
          exact hsq_int
        have hdiff_memLp : MemLp (fun x => g x - condExpExceptCoord (μs := μs) j g x) 2 μ_curr :=
          hg_memLp.sub hcond_g_memLp
        have hg2_int' : Integrable (fun x => (g x - condExpExceptCoord (μs := μs) j g x)^2) μ_curr :=
          hdiff_memLp.integrable_sq
        have hcondVar := expectation_sq_diff_eq_expectation_condVar (f := g) j hg_int hg2_int'
        linarith

      have hg_sum : ∑ j : Fin ((k+1)+1), ∫ x, (g x - condExpExceptCoord (μs := μs) j g x)^2 ∂μ_curr =
          ((k+1)+1 : ℕ) * variance g μ_curr - ∑ j, variance (condExpExceptCoord (μs := μs) j g) μ_curr := by
        simp_rw [hg_condVar]
        rw [Finset.sum_sub_distrib, Finset.sum_const, Finset.card_fin]
        simp only [nsmul_eq_mul, Nat.cast_add, Nat.cast_one]

      have hvar_cond_g_nonneg : ∀ j, 0 ≤ variance (condExpExceptCoord (μs := μs) j g) μ_curr := by
        intro j; exact variance_nonneg _ _

      have hvar_g_nonneg : 0 ≤ variance g μ_curr := variance_nonneg _ _

      have hterm_nonneg : ∀ j : Fin ((k+1)+1), 0 ≤ ∫ x, (g x - condExpExceptCoord (μs := μs) j g x)^2 ∂μ_curr := by
        intro j; apply integral_nonneg (fun x => sq_nonneg _)

      have hg_split : ∑ j : Fin ((k+1)+1), ∫ x, (g x - condExpExceptCoord (μs := μs) j g x)^2 ∂μ_curr =
          ∫ x, (g x - condExpExceptCoord (μs := μs) 0 g x)^2 ∂μ_curr +
          ∑ j : Fin ((k+1)+1) with j ≠ 0, ∫ x, (g x - condExpExceptCoord (μs := μs) j g x)^2 ∂μ_curr := by
        rw [← Finset.add_sum_erase _ _ (Finset.mem_univ (0 : Fin ((k+1)+1)))]
        congr 1
        apply Finset.sum_congr
        · ext i; simp only [Finset.mem_erase, Finset.mem_univ, Finset.mem_filter, and_true, ne_eq]; tauto
        · intro _ _; rfl

      rw [hg_split, h_idem_term, zero_add] at hg_sum

      have h1 : (1 : Fin ((k+1)+1)) ≠ 0 := by simp only [ne_eq, Fin.one_eq_zero_iff]; omega
      have htv_g_1 := total_variance_identity (μs := μs) (1 : Fin ((k+1)+1)) g hg_memLp
      have hg_condVar_1 := hg_condVar 1
      have hvar_e1g_nonneg := hvar_cond_g_nonneg 1

      have hrest_g_nonneg : 0 ≤ ∑ j : Fin ((k+1)+1) with j ≠ 0 ∧ j ≠ 1,
          ∫ x, (g x - condExpExceptCoord (μs := μs) j g x)^2 ∂μ_curr := by
        apply Finset.sum_nonneg; intro j _; exact hterm_nonneg j

      have hg_split2 : ∑ j : Fin ((k+1)+1) with j ≠ 0,
          ∫ x, (g x - condExpExceptCoord (μs := μs) j g x)^2 ∂μ_curr =
          ∫ x, (g x - condExpExceptCoord (μs := μs) 1 g x)^2 ∂μ_curr +
          ∑ j : Fin ((k+1)+1) with j ≠ 0 ∧ j ≠ 1,
          ∫ x, (g x - condExpExceptCoord (μs := μs) j g x)^2 ∂μ_curr := by
        have h1_in : (1 : Fin ((k+1)+1)) ∈ Finset.filter (fun j => j ≠ 0) Finset.univ := by
          simp only [Finset.mem_filter, Finset.mem_univ, true_and, ne_eq]
          exact h1
        rw [← Finset.add_sum_erase _ _ h1_in]
        congr 1
        apply Finset.sum_congr
        · ext i
          simp only [Finset.mem_erase, Finset.mem_filter, Finset.mem_univ, true_and, ne_eq]
          constructor
          · intro ⟨hi1, hi0⟩; exact ⟨hi0, hi1⟩
          · intro ⟨hi0, hi1⟩; exact ⟨hi1, hi0⟩
        · intro _ _; rfl

      have hvar_proj_le : ∀ j : Fin ((k+1)+1), variance (condExpExceptCoord (μs := μs) j g) μ_curr ≤ variance g μ_curr := by
        intro j
        have hcv := hg_condVar j
        have h_nonneg := hterm_nonneg j
        linarith

      have hvar_e0g : variance (condExpExceptCoord (μs := μs) (0 : Fin ((k+1)+1)) g) μ_curr = variance g μ_curr := by
        have hidem : condExpExceptCoord (μs := μs) (0 : Fin ((k+1)+1)) g = g := condExpExceptCoord_idempotent 0 f
        simp only [hidem]

      have hsum_var_bound : ∑ j : Fin ((k+1)+1) with j ≠ 0,
          variance (condExpExceptCoord (μs := μs) j g) μ_curr ≤ (k+1 : ℕ) * variance g μ_curr := by
        calc ∑ j : Fin ((k+1)+1) with j ≠ 0, variance (condExpExceptCoord (μs := μs) j g) μ_curr
          _ ≤ ∑ j : Fin ((k+1)+1) with j ≠ 0, variance g μ_curr := by
              apply Finset.sum_le_sum; intro j _; exact hvar_proj_le j
          _ = (Finset.filter (fun j => j ≠ 0) (Finset.univ : Finset (Fin ((k+1)+1)))).card * variance g μ_curr := by
              rw [Finset.sum_const, nsmul_eq_mul]
          _ = (k+1 : ℕ) * variance g μ_curr := by
              congr 1
              rw [Finset.filter_ne', Finset.card_erase_of_mem (Finset.mem_univ (0 : Fin ((k+1)+1)))]
              simp only [Finset.card_univ, Fintype.card_fin]
              rfl

      have hsum_var_split : ∑ j : Fin ((k+1)+1), variance (condExpExceptCoord (μs := μs) j g) μ_curr =
          variance g μ_curr + ∑ j : Fin ((k+1)+1) with j ≠ 0,
          variance (condExpExceptCoord (μs := μs) j g) μ_curr := by
        rw [← Finset.add_sum_erase _ _ (Finset.mem_univ (0 : Fin ((k+1)+1))), hvar_e0g]
        congr 1
        apply Finset.sum_congr
        · ext i; simp only [Finset.mem_erase, Finset.mem_univ, Finset.mem_filter, and_true, ne_eq]; tauto
        · intro _ _; rfl

      rw [hsum_var_split] at hg_sum
      have hg_sum' : ∑ j : Fin ((k+1)+1) with j ≠ 0,
          ∫ x, (g x - condExpExceptCoord (μs := μs) j g x)^2 ∂μ_curr =
          (k+1 : ℕ) * variance g μ_curr - ∑ j : Fin ((k+1)+1) with j ≠ 0,
          variance (condExpExceptCoord (μs := μs) j g) μ_curr := by
        have heq : ((k+1+1) : ℕ) * variance g μ_curr - (variance g μ_curr + ∑ j : Fin ((k+1)+1) with j ≠ 0,
            variance (condExpExceptCoord (μs := μs) j g) μ_curr) =
            ((k+1) : ℕ) * variance g μ_curr - ∑ j : Fin ((k+1)+1) with j ≠ 0,
            variance (condExpExceptCoord (μs := μs) j g) μ_curr := by
          push_cast
          ring
        exact hg_sum.trans heq

      rcases Nat.eq_zero_or_pos k with hk0 | hk_pos
      · subst hk0
        have hsum_singleton : ∑ j : Fin 2 with j ≠ 0,
            ∫ x, (f x - condExpExceptCoord (μs := μs) j f x)^2 ∂μ_curr =
            ∫ x, (f x - condExpExceptCoord (μs := μs) (1 : Fin 2) f x)^2 ∂μ_curr := by
          have hfilt : Finset.filter (fun j : Fin 2 => j ≠ 0) Finset.univ = {1} := by
            ext j; fin_cases j <;> simp
          simp only [hfilt, Finset.sum_singleton]
        rw [hsum_singleton]
        have hg_indep : ∀ x y, g (Function.update x (0 : Fin 2) y) = g x := fun x y =>
          condExpExceptCoord_update (μs := μs) (0 : Fin 2) f x y
        have he1g_indep0 : ∀ x y, condExpExceptCoord (μs := μs) (1 : Fin 2) g (Function.update x 0 y) =
            condExpExceptCoord (μs := μs) (1 : Fin 2) g x := by
          intro x y
          simp only [condExpExceptCoord]
          congr 1 with w
          have hcomm : Function.update (Function.update x 0 y) 1 w =
              Function.update (Function.update x 1 w) 0 y := by
            ext i; fin_cases i <;> simp [Function.update]
          rw [hcomm, hg_indep]
        have he1g_indep1 : ∀ x y, condExpExceptCoord (μs := μs) (1 : Fin 2) g (Function.update x 1 y) =
            condExpExceptCoord (μs := μs) (1 : Fin 2) g x := fun x y =>
          condExpExceptCoord_update (μs := μs) (1 : Fin 2) g x y
        by_cases hne : Nonempty (Fin 2 → Ω)
        case neg =>
          simp only [not_nonempty_iff] at hne
          have hemp : IsEmpty (Fin 2 → Ω) := hne
          simp [variance, evariance, integral_of_isEmpty]
        case pos =>
          obtain ⟨x₀⟩ := hne
          have hconst : ∀ x, condExpExceptCoord (μs := μs) (1 : Fin 2) g x =
              condExpExceptCoord (μs := μs) (1 : Fin 2) g x₀ := by
            intro x
            have hx_eq : x = Function.update (Function.update x₀ 0 (x 0)) 1 (x 1) := by
              ext i; fin_cases i <;> simp [Function.update]
            rw [hx_eq, he1g_indep1, he1g_indep0]
          have hvar_const : variance (condExpExceptCoord (μs := μs) (1 : Fin 2) g) μ_curr = 0 := by
            have hconst_fn : condExpExceptCoord (μs := μs) (1 : Fin 2) g =
                fun _ => condExpExceptCoord (μs := μs) (1 : Fin 2) g x₀ := funext hconst
            rw [hconst_fn, variance, evariance]
            simp only [integral_const, probReal_univ, one_smul, sub_self, sq, mul_zero,
              enorm_zero, lintegral_zero, ENNReal.toReal_zero]
          have heq := hg_condVar 1
          rw [hvar_const, sub_zero] at heq
          calc variance g μ_curr
            _ = ∫ x, (g x - condExpExceptCoord (μs := μs) (1 : Fin 2) g x)^2 ∂μ_curr := heq.symm
            _ ≤ ∫ x, (f x - condExpExceptCoord (μs := μs) (1 : Fin 2) f x)^2 ∂μ_curr := by
                have h1ne0 : (1 : Fin 2) ≠ 0 := by simp
                exact h_sq_bound 1 h1ne0
      · have hkey : variance g μ_curr ≤
            ∑ j : Fin ((k+1)+1) with j ≠ 0, ∫ x, (g x - condExpExceptCoord (μs := μs) j g x)^2 ∂μ_curr := by
          let h : ℕ → ((Fin ((k+1)+1) → Ω) → ℝ) := fun m =>
            Nat.recOn m g (fun m' h_prev =>
              if hm' : m' + 1 < (k+1)+1 then
                condExpExceptCoord (μs := μs) ⟨m' + 1, hm'⟩ h_prev
              else h_prev)

          have hh0 : h 0 = g := rfl
          have hh_succ : ∀ m (hm : m < k + 1),
              h (m + 1) = condExpExceptCoord (μs := μs) ⟨m + 1, Nat.add_lt_add_right hm 1⟩ (h m) := by
            intro m hm
            simp only [h]
            have hcond : m + 1 < (k+1)+1 := by omega
            simp only [hcond, ↓reduceDIte]

          have hh_memLp : ∀ m, m ≤ k + 1 → MemLp (h m) 2 μ_curr := by
            intro m
            induction m with
            | zero => intro _; exact hg_memLp
            | succ m' ih =>
              intro hm
              have hm' : m' ≤ k + 1 := by omega
              have hm'_lt : m' < k + 1 := by omega
              rw [hh_succ m' hm'_lt]
              exact memLp_condExpExceptCoord _ _ (ih (by omega))

          have htv_step : ∀ m (hm : m < k + 1),
              variance (h m) μ_curr =
              ∫ x, ((h m) x - (h (m+1)) x)^2 ∂μ_curr +
              variance (h (m+1)) μ_curr := by
            intro m hm
            have hm_le : m ≤ k + 1 := by omega
            have htv := total_variance_identity (μs := μs) ⟨m + 1, by omega⟩ (h m) (hh_memLp m hm_le)
            have hcv := expectation_sq_diff_eq_expectation_condVar
                (f := h m) ⟨m + 1, by omega⟩
                ((hh_memLp m hm_le).integrable one_le_two)
                (((hh_memLp m hm_le).sub (memLp_condExpExceptCoord ⟨m + 1, by omega⟩ _ (hh_memLp m hm_le))).integrable_sq)
            have heq : condExpExceptCoord (μs := μs) ⟨m + 1, by omega⟩ (h m) = h (m + 1) := by
              rw [hh_succ m hm]
            rw [heq] at htv hcv
            rw [← hcv] at htv
            exact htv

          have hcontract : ∀ m (hm : m < k + 1),
              ∫ x, ((h m) x - (h (m+1)) x)^2 ∂μ_curr ≤
              ∫ x, (g x - condExpExceptCoord (μs := μs) ⟨m + 1, by omega⟩ g x)^2 ∂μ_curr := by
            intro m hm
            rw [hh_succ m hm]
            induction m with
            | zero => rw [hh0]
            | succ m' ih =>
              have hm'_lt : m' < k + 1 := by omega
              have hm'_le : m' ≤ k + 1 := by omega
              rw [hh_succ m' hm'_lt]
              have hij : (⟨m' + 1, by omega⟩ : Fin ((k+1)+1)) ≠ ⟨m' + 2, by omega⟩ := by
                simp only [ne_eq, Fin.ext_iff]; omega
              have hstep1 := sq_diff_condExpExceptCoord_bound_gen hij (h m') (hh_memLp m' hm'_le)
              calc ∫ x, (condExpExceptCoord (μs := μs) ⟨m' + 1, by omega⟩ (h m') x -
                         condExpExceptCoord (μs := μs) ⟨m' + 2, by omega⟩
                           (condExpExceptCoord (μs := μs) ⟨m' + 1, by omega⟩ (h m')) x)^2 ∂μ_curr
                _ ≤ ∫ x, ((h m') x - condExpExceptCoord (μs := μs) ⟨m' + 2, by omega⟩ (h m') x)^2 ∂μ_curr := hstep1
                _ ≤ ∫ x, (g x - condExpExceptCoord (μs := μs) ⟨m' + 2, by omega⟩ g x)^2 ∂μ_curr := by
                    clear ih
                    have hbound : ∀ m'' (hm''_le : m'' ≤ k + 1) (j : ℕ) (hj_bound : j ≤ k + 1)
                        (hj_ne : ∀ i, i ≤ m'' → j ≠ i),
                        ∫ x, ((h m'') x - condExpExceptCoord (μs := μs) ⟨j, by omega⟩ (h m'') x)^2 ∂μ_curr ≤
                        ∫ x, (g x - condExpExceptCoord (μs := μs) ⟨j, by omega⟩ g x)^2 ∂μ_curr := by
                      intro m''
                      induction m'' with
                      | zero =>
                        intro _ j _ _
                        rw [hh0]
                      | succ m''' ih_inner =>
                        intro hm'''_le j hj_bound hj_ne
                        have hm'''_lt : m''' < k + 1 := by omega
                        have hm'''_le' : m''' ≤ k + 1 := by omega
                        rw [hh_succ m''' hm'''_lt]
                        have hj_ne_succ : j ≠ m''' + 1 := hj_ne (m''' + 1) (le_refl _)
                        have hij' : (⟨m''' + 1, by omega⟩ : Fin ((k+1)+1)) ≠ ⟨j, by omega⟩ := by
                          simp only [ne_eq, Fin.ext_iff]
                          omega
                        have hstep := sq_diff_condExpExceptCoord_bound_gen hij' (h m''') (hh_memLp m''' hm'''_le')
                        calc ∫ x, (condExpExceptCoord (μs := μs) ⟨m''' + 1, by omega⟩ (h m''') x -
                                   condExpExceptCoord (μs := μs) ⟨j, by omega⟩
                                     (condExpExceptCoord (μs := μs) ⟨m''' + 1, by omega⟩ (h m''')) x)^2 ∂μ_curr
                          _ ≤ ∫ x, ((h m''') x - condExpExceptCoord (μs := μs) ⟨j, by omega⟩ (h m''') x)^2 ∂μ_curr := hstep
                          _ ≤ ∫ x, (g x - condExpExceptCoord (μs := μs) ⟨j, by omega⟩ g x)^2 ∂μ_curr := by
                              apply ih_inner hm'''_le' j hj_bound
                              intro i hi
                              have := hj_ne i (by omega : i ≤ m''' + 1)
                              exact this
                    apply hbound m' hm'_le (m' + 2) (by omega)
                    intro i hi
                    omega

          have hsum_eq : ∑ j : Fin ((k+1)+1) with j ≠ 0,
              ∫ x, (g x - condExpExceptCoord (μs := μs) j g x)^2 ∂μ_curr =
              ∑ m : Fin (k+1), ∫ x, (g x - condExpExceptCoord (μs := μs) ⟨m.val + 1, by omega⟩ g x)^2 ∂μ_curr := by
            rw [show Finset.filter (· ≠ 0) Finset.univ =
                Finset.map ⟨Fin.succ, Fin.succ_injective _⟩ Finset.univ by
              ext j
              simp only [Finset.mem_filter, Finset.mem_univ, true_and, Finset.mem_map,
                         Function.Embedding.coeFn_mk]
              constructor
              · intro hj
                use ⟨j.val - 1, by omega⟩
                ext
                simp only [Fin.val_succ]
                have : 1 ≤ j.val := Fin.pos_of_ne_zero hj
                omega
              · intro ⟨i, hi⟩
                rw [← hi]
                exact Fin.succ_ne_zero i]
            rw [Finset.sum_map]
            apply Finset.sum_congr rfl
            intro m _
            congr

          have htelescope : variance g μ_curr ≤
              ∑ m : Fin (k+1), ∫ x, ((h m.val) x - (h (m.val + 1)) x)^2 ∂μ_curr := by
            have htelescope_eq : ∀ n (hn : n ≤ k + 1),
                variance (h 0) μ_curr =
                ∑ m : Fin n, ∫ x, ((h m.val) x - (h (m.val + 1)) x)^2 ∂μ_curr +
                variance (h n) μ_curr := by
              intro n
              induction n with
              | zero => intro _; simp
              | succ n' ihn' =>
                intro hn'
                have hn'' : n' ≤ k + 1 := by omega
                have hn'_lt : n' < k + 1 := by omega
                rw [ihn' hn'']
                rw [htv_step n' hn'_lt]
                rw [Fin.sum_univ_succ]
                suffices hsuff : ∑ m : Fin n', ∫ x, (h ↑m x - h (↑m + 1) x)^2 ∂μ_curr +
                    ∫ x, (h n' x - h (n' + 1) x)^2 ∂μ_curr =
                    ∫ x, (h 0 x - h 1 x)^2 ∂μ_curr +
                    ∑ i : Fin n', ∫ x, (h ↑i.succ x - h (↑i.succ + 1) x)^2 ∂μ_curr by
                  rw [← add_assoc]
                  rw [hsuff]
                  simp only [Fin.val_zero, Fin.val_succ]
                have hlhs : ∑ m : Fin n', ∫ x, (h ↑m x - h (↑m + 1) x)^2 ∂μ_curr +
                    ∫ x, (h n' x - h (n' + 1) x)^2 ∂μ_curr =
                    ∑ m : Fin (n' + 1), ∫ x, (h ↑m x - h (↑m + 1) x)^2 ∂μ_curr := by
                  rw [Fin.sum_univ_castSucc]
                  simp only [Fin.val_castSucc, Fin.val_last]
                have hrhs : ∫ x, (h 0 x - h 1 x)^2 ∂μ_curr +
                    ∑ i : Fin n', ∫ x, (h ↑i.succ x - h (↑i.succ + 1) x)^2 ∂μ_curr =
                    ∑ m : Fin (n' + 1), ∫ x, (h ↑m x - h (↑m + 1) x)^2 ∂μ_curr := by
                  rw [Fin.sum_univ_succ]
                  simp only [Fin.val_zero, Fin.val_succ]
                linarith [hlhs, hrhs]
            have h_eq := htelescope_eq (k + 1) (le_refl _)
            simp only [hh0] at h_eq
            have hvar_hkp1_zero : variance (h (k + 1)) μ_curr = 0 := by
              have h_indep : ∀ m (hm : m ≤ k + 1) (j : Fin ((k+1)+1)) (hj : j.val ≤ m) (x : Fin ((k+1)+1) → Ω) (y : Ω),
                  h m (Function.update x j y) = h m x := by
                intro m
                induction m with
                | zero =>
                  intro _ j hj x y
                  have hj0 : j.val = 0 := Nat.le_zero.mp hj
                  have hj_eq : j = 0 := Fin.ext hj0
                  subst hj_eq
                  simp only [hh0]
                  exact condExpExceptCoord_update (μs := μs) (0 : Fin ((k+1)+1)) f x y
                | succ m' ihm' =>
                  intro hm' j hj x y
                  rcases Nat.lt_or_eq_of_le hj with hj_lt | hj_eq
                  · have hm'' : m' ≤ k + 1 := by omega
                    have hm'_lt : m' < k + 1 := by omega
                    rw [hh_succ m' hm'_lt]
                    simp only [condExpExceptCoord]
                    congr 1 with z
                    have hne : j ≠ (⟨m' + 1, by omega⟩ : Fin ((k+1)+1)) := by
                      simp only [ne_eq, Fin.ext_iff]; omega
                    rw [Function.update_comm hne]
                    have hj_le : j.val ≤ m' := by omega
                    exact ihm' hm'' j hj_le _ y
                  · have hj_fin : j = ⟨m' + 1, by omega⟩ := Fin.ext hj_eq
                    have hm'_lt : m' < k + 1 := by omega
                    rw [hj_fin, hh_succ m' hm'_lt]
                    exact condExpExceptCoord_update (μs := μs) ⟨m' + 1, by omega⟩ (h m') x y
              by_cases hne : Nonempty (Fin ((k+1)+1) → Ω)
              case neg =>
                simp only [not_nonempty_iff] at hne
                simp [variance, evariance, integral_of_isEmpty]
              case pos =>
                obtain ⟨x₀⟩ := hne
                have hconst : ∀ x, h (k + 1) x = h (k + 1) x₀ := by
                  intro x
                  have hchain : ∀ n (hn : n ≤ (k+1)+1) (y : Fin ((k+1)+1) → Ω),
                      (∀ j : Fin ((k+1)+1), j.val < n → y j = x₀ j) →
                      h (k + 1) y = h (k + 1) x₀ := by
                    intro n
                    induction n with
                    | zero =>
                      intro _ y hy
                      have hrev : ∀ m (hm : m ≤ (k+1)+1),
                          h (k + 1) (fun j => if j.val < m then x₀ j else y j) = h (k + 1) y := by
                        intro m
                        induction m with
                        | zero => intro _; simp
                        | succ m' ihm' =>
                          intro hm'
                          have hm'' : m' ≤ (k+1)+1 := by omega
                          have heq : (fun j => if j.val < m' + 1 then x₀ j else y j) =
                              Function.update (fun j => if j.val < m' then x₀ j else y j)
                                ⟨m', by omega⟩ (x₀ ⟨m', by omega⟩) := by
                            ext j
                            by_cases hjm : j.val < m'
                            · have hjm1 : j.val < m' + 1 := Nat.lt_succ_of_lt hjm
                              have hne : j ≠ ⟨m', by omega⟩ := by
                                simp only [ne_eq, Fin.ext_iff]; omega
                              simp only [hjm, hjm1, ↓reduceIte, Function.update, hne, ↓reduceDIte]
                            · by_cases hjeq : j.val = m'
                              · have hj_eq : j = ⟨m', by omega⟩ := Fin.ext hjeq
                                rw [hj_eq]
                                simp only [↓reduceIte, Nat.lt_succ_self, Function.update_self]
                              · have hjgt : j.val > m' := Nat.lt_of_le_of_ne (Nat.not_lt.mp hjm) (Ne.symm hjeq)
                                have hnjm : ¬(j.val < m') := Nat.not_lt.mpr (Nat.le_of_lt hjgt)
                                have hnjm1 : ¬(j.val < m' + 1) := Nat.not_lt.mpr (Nat.succ_le_of_lt hjgt)
                                have hne : j ≠ ⟨m', by omega⟩ := by
                                  simp only [ne_eq, Fin.ext_iff]; omega
                                simp only [hnjm, hnjm1, ↓reduceIte, Function.update, hne, ↓reduceDIte]
                          rw [heq, h_indep (k+1) (le_refl _) ⟨m', by omega⟩ (by omega : m' ≤ k+1), ihm' hm'']
                      have hfinal : (fun j => if j.val < (k+1)+1 then x₀ j else y j) = x₀ := by
                        ext j; simp [j.isLt]
                      rw [← hfinal, ← hrev ((k+1)+1) (le_refl _)]
                    | succ n' ihn' =>
                      intro hn' y hy
                      exact ihn' (by omega) y (fun j hj => hy j (Nat.lt_succ_of_lt hj))
                  exact hchain 0 (Nat.zero_le _) x (fun _ h => absurd h (Nat.not_lt_zero _))
                have hh_const_fn : h (k + 1) = fun _ => h (k + 1) x₀ := funext hconst
                rw [hh_const_fn]
                simp only [variance, evariance]
                simp only [integral_const, probReal_univ, one_smul, sub_self, enorm_zero,
                  zero_pow two_ne_zero, lintegral_zero, ENNReal.toReal_zero]
            rw [h_eq, hvar_hkp1_zero, add_zero]

          calc variance g μ_curr
            _ ≤ ∑ m : Fin (k+1), ∫ x, ((h m.val) x - (h (m.val + 1)) x)^2 ∂μ_curr := htelescope
            _ ≤ ∑ m : Fin (k+1), ∫ x, (g x - condExpExceptCoord (μs := μs) ⟨m.val + 1, by omega⟩ g x)^2 ∂μ_curr := by
                apply Finset.sum_le_sum
                intro m _
                exact hcontract m.val (by have := m.isLt; omega)
            _ = ∑ j : Fin ((k+1)+1) with j ≠ 0, ∫ x, (g x - condExpExceptCoord (μs := μs) j g x)^2 ∂μ_curr := hsum_eq.symm

        calc variance g μ_curr
          _ ≤ ∑ j : Fin ((k+1)+1) with j ≠ 0, ∫ x, (g x - condExpExceptCoord (μs := μs) j g x)^2 ∂μ_curr := hkey
          _ ≤ ∑ j : Fin ((k+1)+1) with j ≠ 0, ∫ x, (f x - condExpExceptCoord (μs := μs) j f x)^2 ∂μ_curr := h_sum_bound

    rw [hsplit]
    have hcondvar_eq := expectation_sq_diff_eq_expectation_condVar (f := f) (0 : Fin ((k+1)+1))
        (hf.integrable one_le_two) ((hf.sub (memLp_condExpExceptCoord (0 : Fin ((k+1)+1)) f hf)).integrable_sq)

    calc variance f μ_curr
      _ = ∫ x, condVarExceptCoord (μs := μs) (0 : Fin ((k+1)+1)) f x ∂μ_curr +
          variance (condExpExceptCoord (μs := μs) (0 : Fin ((k+1)+1)) f) μ_curr := htv0
      _ = ∫ x, (f x - condExpExceptCoord (μs := μs) (0 : Fin ((k+1)+1)) f x)^2 ∂μ_curr +
          variance (condExpExceptCoord (μs := μs) (0 : Fin ((k+1)+1)) f) μ_curr := by rw [hcondvar_eq]
      _ ≤ ∫ x, (f x - condExpExceptCoord (μs := μs) (0 : Fin ((k+1)+1)) f x)^2 ∂μ_curr +
          ∑ i : Fin ((k+1)+1) with i ≠ 0, ∫ x, (f x - condExpExceptCoord (μs := μs) i f x)^2 ∂μ_curr := by
          linarith [hkey_bound]

end MainTheorem

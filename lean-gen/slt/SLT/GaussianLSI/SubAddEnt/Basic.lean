/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.EfronStein
import SLT.GaussianLSI.Entropy

/-!
# Conditional Entropy for Product Spaces

Defines conditional entropy `condEntExceptCoord` for product probability spaces.

## Main Definitions

* `condEntExceptCoord`: Conditional entropy given all variables except coordinate i.

## Main Results

* `condEntExceptCoord_nonneg`: Conditional entropy is nonnegative (Jensen's inequality).
* `condExpExceptCoord_mul_log_integrable`: Integrability of E^{(i)}[f] · log(E^{(i)}[f]).
* `integral_condExpExceptCoord_mul_log`: Tower property for f log f.
-/

open MeasureTheory ProbabilityTheory Real Set Filter

open scoped ENNReal NNReal BigOperators

noncomputable section

namespace SubAddEnt

variable {n : ℕ} {Ω : Type*} [MeasurableSpace Ω]
variable {μs : Fin n → Measure Ω} [∀ i, IsProbabilityMeasure (μs i)]

-- Product measure notation (consistent with EfronStein.lean)
local notation "μˢ" => Measure.pi μs

/-!
## Definition of Conditional Entropy
-/

/-- Conditional entropy Ent^{(i)}(f)(x) = E^{(i)}[f log f](x) - E^{(i)}[f](x) · log(E^{(i)}[f](x)). -/
noncomputable def condEntExceptCoord (i : Fin n) (f : (Fin n → Ω) → ℝ) : (Fin n → Ω) → ℝ :=
  fun x => condExpExceptCoord (μs := μs) i (fun z => f z * log (f z)) x -
           condExpExceptCoord (μs := μs) i f x * log (condExpExceptCoord (μs := μs) i f x)

/-!
## Basic Properties
-/

omit [∀ (i : Fin n), IsProbabilityMeasure (μs i)] in
/-- Conditional entropy is constant in coordinate i. -/
theorem condEntExceptCoord_update (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (x : Fin n → Ω) (y : Ω) :
    condEntExceptCoord (μs := μs) i f (Function.update x i y) =
    condEntExceptCoord (μs := μs) i f x := by
  unfold condEntExceptCoord
  rw [condExpExceptCoord_update, condExpExceptCoord_update]

/-! ## Nonnegativity of Conditional Entropy -/

/-- Conditional Jensen: E^{(i)}[φ(f)] ≥ φ(E^{(i)}[f]) for φ(t) = t log t. -/
theorem condExpExceptCoord_mul_log_ge_at (i : Fin n) (f : (Fin n → Ω) → ℝ) (x : Fin n → Ω)
    (hf_nn_slice : ∀ᵐ y ∂(μs i), 0 ≤ f (Function.update x i y))
    (hf_slice_int : Integrable (fun y => f (Function.update x i y)) (μs i))
    (hf_log_slice_int : Integrable (fun y => f (Function.update x i y) *
                                          log (f (Function.update x i y))) (μs i)) :
    condExpExceptCoord (μs := μs) i f x * log (condExpExceptCoord (μs := μs) i f x) ≤
    condExpExceptCoord (μs := μs) i (fun z => f z * log (f z)) x := by
  unfold condExpExceptCoord
  -- Apply Jensen's inequality for convex φ(t) = t * log(t) on [0, ∞)
  set g := fun y => f (Function.update x i y)
  -- We need: (∫ g dμ) * log(∫ g dμ) ≤ ∫ (g * log g) dμ
  have hφ_convex : ConvexOn ℝ (Ici 0) (fun t => t * log t) := Real.convexOn_mul_log
  have hcont : ContinuousOn (fun t => t * log t) (Ici 0) :=
    Real.continuous_mul_log.continuousOn
  have hclosed : IsClosed (Ici (0 : ℝ)) := isClosed_Ici
  -- Need to show g maps into [0, ∞) a.e.
  have hmem : ∀ᵐ y ∂(μs i), g y ∈ Ici (0 : ℝ) := hf_nn_slice
  exact hφ_convex.map_integral_le hcont hclosed hmem hf_slice_int hf_log_slice_int

theorem condExpExceptCoord_mul_log_ge (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_nn_slice : ∀ x, ∀ᵐ y ∂(μs i), 0 ≤ f (Function.update x i y))
    (hf_slice_int : ∀ x, Integrable (fun y => f (Function.update x i y)) (μs i))
    (hf_log_slice_int : ∀ x, Integrable (fun y => f (Function.update x i y) *
                                          log (f (Function.update x i y))) (μs i))
    (x : Fin n → Ω) :
    condExpExceptCoord (μs := μs) i f x * log (condExpExceptCoord (μs := μs) i f x) ≤
    condExpExceptCoord (μs := μs) i (fun z => f z * log (f z)) x :=
  condExpExceptCoord_mul_log_ge_at i f x (hf_nn_slice x) (hf_slice_int x) (hf_log_slice_int x)

/-- Pointwise nonnegativity of conditional entropy. -/
theorem condEntExceptCoord_nonneg_at (i : Fin n) (f : (Fin n → Ω) → ℝ) (x : Fin n → Ω)
    (hf_nn_slice : ∀ᵐ y ∂(μs i), 0 ≤ f (Function.update x i y))
    (hf_slice_int : Integrable (fun y => f (Function.update x i y)) (μs i))
    (hf_log_slice_int : Integrable (fun y => f (Function.update x i y) *
                                          log (f (Function.update x i y))) (μs i)) :
    0 ≤ condEntExceptCoord (μs := μs) i f x := by
  unfold condEntExceptCoord
  have h := condExpExceptCoord_mul_log_ge_at i f x hf_nn_slice hf_slice_int hf_log_slice_int
  linarith

theorem condEntExceptCoord_nonneg (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_nn_slice : ∀ x, ∀ᵐ y ∂(μs i), 0 ≤ f (Function.update x i y))
    (hf_slice_int : ∀ x, Integrable (fun y => f (Function.update x i y)) (μs i))
    (hf_log_slice_int : ∀ x, Integrable (fun y => f (Function.update x i y) *
                                          log (f (Function.update x i y))) (μs i))
    (x : Fin n → Ω) :
    0 ≤ condEntExceptCoord (μs := μs) i f x :=
  condEntExceptCoord_nonneg_at i f x (hf_nn_slice x) (hf_slice_int x) (hf_log_slice_int x)

/-!
## Integrability Lemmas
-/

/-- The conditional expectation of f is integrable when f is integrable. -/
lemma condExpExceptCoord_integrable (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_int : Integrable f μˢ) :
    Integrable (condExpExceptCoord (μs := μs) i f) μˢ := by
  -- condExpExceptCoord i f x = ∫ y, f (update x i y) dμs
  -- Use Fubini: show f ∘ update is integrable on μˢ.prod μ, then apply integral_prod_left
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
    hmp.integrable_comp hf_int.aestronglyMeasurable |>.mpr hf_int
  convert hg_int.integral_prod_left

/-- Helper: if f is integrable over the product, slices are integrable -/
lemma integrable_update_slice (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_int : Integrable f μˢ) :
    ∀ᵐ x ∂μˢ, Integrable (fun y => f (Function.update x i y)) (μs i) := by
  -- This follows from Fubini: if f is integrable over the product,
  -- then a.e. slice is integrable
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
    hmp.integrable_comp hf_int.aestronglyMeasurable |>.mpr hf_int
  exact hg_int.prod_right_ae

/-- A.e. nonnegativity of slice functions from global nonnegativity -/
lemma ae_nonneg_slice_of_ae_nonneg (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_nn : 0 ≤ᵐ[μˢ] f) :
    ∀ᵐ x ∂μˢ, ∀ᵐ y ∂(μs i), 0 ≤ f (Function.update x i y) := by
  -- The map (x, y) ↦ update x i y pushes forward μˢ × (μs i) to μˢ
  -- So if f ≥ 0 a.e. on μˢ, then f ∘ update ≥ 0 a.e. on μˢ × (μs i)
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
  -- Transfer the a.e. condition through the measure-preserving map
  have hprod_ae : ∀ᵐ p ∂(μˢ.prod (μs i)), 0 ≤ f (Function.update p.1 i p.2) := by
    -- Direct proof: preimage of null set under measure-preserving map is null
    -- hf_nn: μˢ {z | ¬(0 ≤ f z)} = 0
    have h_null : μˢ {z | ¬(0 ≤ f z)} = 0 := ae_iff.mp hf_nn
    have h_preimage : (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) ⁻¹' {z | ¬(0 ≤ f z)} =
                      {p | ¬(0 ≤ f (Function.update p.1 i p.2))} := rfl
    rw [ae_iff]
    show (μˢ.prod (μs i)) {p | ¬(0 ≤ f (Function.update p.1 i p.2))} = 0
    rw [← h_preimage]
    -- Use measure_preimage: for measure-preserving f, μa(f⁻¹'(s)) = μb(s) when s is null-measurable
    have hs_null_meas : NullMeasurableSet {z | ¬(0 ≤ f z)} μˢ :=
      NullMeasurableSet.of_null h_null
    rw [hmp.measure_preimage hs_null_meas]
    exact h_null
  -- By Fubini (ae_ae_of_ae_prod), this gives the desired a.e. a.e. property
  exact Measure.ae_ae_of_ae_prod hprod_ae

/-- E^{(i)}[f] ≥ 0 a.e. when f ≥ 0 a.e. -/
lemma condExpExceptCoord_nonneg_ae (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_nn : 0 ≤ᵐ[μˢ] f) :
    0 ≤ᵐ[μˢ] condExpExceptCoord (μs := μs) i f := by
  have hslice_nn := ae_nonneg_slice_of_ae_nonneg i f hf_nn
  filter_upwards [hslice_nn] with x hx
  exact integral_nonneg_of_ae hx

/-- Integrability of E^{(i)}[f] · log(E^{(i)}[f]) via Jensen's inequality. -/
lemma condExpExceptCoord_mul_log_integrable (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_meas : Measurable f)
    (hf_nn : 0 ≤ᵐ[μˢ] f)
    (hf_int : Integrable f μˢ)
    (hf_log_int : Integrable (fun x => f x * log (f x)) μˢ) :
    Integrable (fun x => condExpExceptCoord (μs := μs) i f x *
                         log (condExpExceptCoord (μs := μs) i f x)) μˢ := by
  -- Define g = condExpExceptCoord i f for readability
  set g := condExpExceptCoord (μs := μs) i f
  -- Define h = condExpExceptCoord i (f * log f)
  set h := condExpExceptCoord (μs := μs) i (fun z => f z * log (f z))

  -- g is nonnegative a.e.
  have hg_nn : 0 ≤ᵐ[μˢ] g := condExpExceptCoord_nonneg_ae i f hf_nn

  -- h is integrable (by condExpExceptCoord_integrable)
  have hh_int : Integrable h μˢ := condExpExceptCoord_integrable i (fun z => f z * log (f z)) hf_log_int

  -- g is strongly measurable
  have hg_sm : StronglyMeasurable g :=
    condExpExceptCoord_stronglyMeasurable i f (hf_meas.stronglyMeasurable)

  -- g is measurable
  have hg_meas : Measurable g := hg_sm.measurable

  -- By Jensen's inequality: g * log g ≤ h a.e.
  have h_jensen : ∀ᵐ x ∂μˢ, g x * log (g x) ≤ h x := by
    have hnn_ae := ae_nonneg_slice_of_ae_nonneg i f hf_nn
    have hint_ae := integrable_update_slice i f hf_int
    have hlogint_ae := integrable_update_slice i (fun z => f z * log (f z)) hf_log_int
    filter_upwards [hnn_ae, hint_ae, hlogint_ae] with x hnn hint hlogint
    exact condExpExceptCoord_mul_log_ge_at i f x hnn hint hlogint

  -- The bounding function: |h| + 1
  have hbound_int : Integrable (fun x => |h x| + 1) μˢ := hh_int.abs.add (integrable_const 1)

  -- g * log g is AEStronglyMeasurable
  have hglog_aesm : AEStronglyMeasurable (fun x => g x * log (g x)) μˢ :=
    (hg_meas.mul (measurable_log.comp hg_meas)).aestronglyMeasurable

  apply Integrable.mono' hbound_int hglog_aesm
  -- The bound: ‖g * log g‖ ≤ |h| + 1
  filter_upwards [hg_nn, h_jensen] with x hg_x_nn hj_x
  rw [Real.norm_eq_abs]
  -- Need: |g x * log (g x)| ≤ |h x| + 1
  by_cases hgx_le_one : g x ≤ 1
  · -- Case: g x ≤ 1
    by_cases hgx_pos : 0 < g x
    · -- 0 < g x ≤ 1: use |x log x| < 1
      have hbound : |g x * log (g x)| < 1 := by
        rw [mul_comm]
        exact Real.abs_log_mul_self_lt (g x) hgx_pos hgx_le_one
      linarith [abs_nonneg (h x)]
    · -- g x = 0 (since g x ≥ 0 and ¬(0 < g x))
      push_neg at hgx_pos
      have hgx_zero : g x = 0 := le_antisymm hgx_pos hg_x_nn
      simp only [hgx_zero, zero_mul, abs_zero]
      linarith [abs_nonneg (h x)]
  · -- Case: g x > 1: g * log g ≥ 0 and g * log g ≤ h, so |g * log g| ≤ |h|
    push_neg at hgx_le_one
    have hglog_nn : 0 ≤ g x * log (g x) := Real.mul_log_nonneg (le_of_lt hgx_le_one)
    have : |g x * log (g x)| = g x * log (g x) := abs_of_nonneg hglog_nn
    rw [this]
    calc g x * log (g x) ≤ h x := hj_x
      _ ≤ |h x| := le_abs_self _
      _ ≤ |h x| + 1 := by linarith

/-!
## Integral of Conditional Entropy
-/

/-- Tower property: ∫ E^{(i)}[f log f] dμ = ∫ f log f dμ. -/
lemma integral_condExpExceptCoord_mul_log (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_log_int : Integrable (fun x => f x * log (f x)) μˢ) :
    ∫ x, condExpExceptCoord (μs := μs) i (fun z => f z * log (f z)) x ∂μˢ =
    ∫ x, f x * log (f x) ∂μˢ :=
  condExpExceptCoord_expectation i (fun z => f z * log (f z)) hf_log_int

/-!
## Conditional Entropy Integrable
-/

/-- The conditional entropy is integrable when f and f log f are integrable -/
lemma condEntExceptCoord_integrable' (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_log_int : Integrable (fun x => f x * log (f x)) μˢ)
    (hEf_log_int : Integrable (fun x => condExpExceptCoord (μs := μs) i f x *
                                        log (condExpExceptCoord (μs := μs) i f x)) μˢ) :
    Integrable (condEntExceptCoord (μs := μs) i f) μˢ := by
  unfold condEntExceptCoord
  apply Integrable.sub
  · -- E^{(i)}[f log f] is integrable
    exact condExpExceptCoord_integrable i (fun z => f z * log (f z)) hf_log_int
  · -- E^{(i)}[f] * log(E^{(i)}[f]) is integrable
    exact hEf_log_int

end SubAddEnt

end

/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.GaussianLSI.SubAddEnt.Decomposition
import SLT.GaussianLSI.DualEntApp

/-!
# Subadditivity of Entropy

This file proves the subadditivity of entropy inequality:
  Ent(f) ≤ ∑_{i=1}^n E[Ent^{(i)}(f)]

where f is a nonnegative measurable function of n independent random variables,
and Ent^{(i)}(f) is the conditional entropy given all variables except X_i.

## Main Results

* `entropy_subadditive`: The main subadditivity inequality

-/

open MeasureTheory ProbabilityTheory Real Set Filter

open scoped ENNReal NNReal BigOperators EReal

noncomputable section

namespace SubAddEnt

variable {n : ℕ} {Ω : Type*} [MeasurableSpace Ω]
variable {μs : Fin n → Measure Ω} [∀ i, IsProbabilityMeasure (μs i)]

-- Product measure notation
local notation "μˢ" => Measure.pi μs

/-!
## Tower Property

The key identity: E_k[f] = E^{(k)}[E_{k+1}[f]]
-/

omit [MeasurableSpace Ω] in
/-- Helper: the integrand for condExpFirstK doesn't depend on coordinates 0, ..., k-1
    when we've already substituted x for those coordinates. -/
lemma condExpFirstK_integrand_indep_low_coords (k : Fin (n + 1)) (f : (Fin n → Ω) → ℝ)
    (x : Fin n → Ω) (y w : Fin n → Ω)
    (hw : ∀ j : Fin n, k.val ≤ j.val → w j = y j) :
    f (fun j => if j.val < k.val then x j else y j) =
    f (fun j => if j.val < k.val then x j else w j) := by
  congr 1 with j
  by_cases h : j.val < k.val
  · simp [h]
  · simp [h, hw j (Nat.le_of_not_lt h)]

/-- The map φ(p) = (fun j => if j.val < k.val then p.1 j else p.2 j) is measure-preserving
    from μˢ.prod μˢ to μˢ. -/
lemma map_select_coords_prod_pi (k : Fin (n + 1)) :
    Measure.map (fun p : (Fin n → Ω) × (Fin n → Ω) =>
      fun j : Fin n => if j.val < k.val then p.1 j else p.2 j) (μˢ.prod μˢ) = μˢ := by
  -- Use Measure.pi_eq to prove equality via rectangle sets
  symm
  apply Measure.pi_eq
  intro s hs
  -- Define the selection map
  set φ := fun p : (Fin n → Ω) × (Fin n → Ω) =>
    (fun j : Fin n => if j.val < k.val then p.1 j else p.2 j) with hφ_def
  -- φ is measurable
  have hφ_meas : Measurable φ := by
    apply measurable_pi_lambda
    intro j
    by_cases h : j.val < k.val
    · simp only [hφ_def, if_pos h]; exact measurable_fst.eval
    · simp only [hφ_def, if_neg h]; exact measurable_snd.eval
  rw [Measure.map_apply hφ_meas (MeasurableSet.univ_pi (fun j => hs j))]
  -- Preimage of ∏ⱼ s j under φ
  -- {p : p.1 j ∈ s j for j < k, p.2 j ∈ s j for j ≥ k}
  have preimage_eq : φ ⁻¹' (Set.univ.pi s) =
      (Set.univ.pi (fun j => if j.val < k.val then s j else Set.univ)) ×ˢ
      (Set.univ.pi (fun j => if j.val < k.val then Set.univ else s j)) := by
    ext ⟨x, y⟩
    simp only [Set.mem_preimage, Set.mem_pi, Set.mem_univ, true_implies, Set.mem_prod, hφ_def]
    constructor
    · intro h
      constructor
      · intro j
        by_cases hj : j.val < k.val
        · simp only [if_pos hj]; have := h j; simp only [if_pos hj] at this; exact this
        · simp [hj]
      · intro j
        by_cases hj : j.val < k.val
        · simp [hj]
        · simp only [if_neg hj]; have := h j; simp only [if_neg hj] at this; exact this
    · intro ⟨hx, hy⟩ j
      by_cases hj : j.val < k.val
      · simp only [if_pos hj]; have := hx j; simp only [if_pos hj] at this; exact this
      · simp only [if_neg hj]; have := hy j; simp only [if_neg hj] at this; exact this
  rw [preimage_eq]
  -- Measure of product set: μˢ.prod μˢ (s₁ ×ˢ s₂) = μˢ s₁ * μˢ s₂
  rw [Measure.prod_prod]
  -- First factor: ∏ⱼ (if j < k then μs j (s j) else 1)
  have factor1 : μˢ (Set.univ.pi (fun j => if j.val < k.val then s j else Set.univ)) =
      ∏ j : Fin n, (if j.val < k.val then μs j (s j) else 1) := by
    rw [Measure.pi_pi]
    congr 1 with j
    by_cases hj : j.val < k.val
    · simp [hj]
    · simp only [if_neg hj, measure_univ]
  -- Second factor: ∏ⱼ (if j < k then 1 else μs j (s j))
  have factor2 : μˢ (Set.univ.pi (fun j => if j.val < k.val then Set.univ else s j)) =
      ∏ j : Fin n, (if j.val < k.val then 1 else μs j (s j)) := by
    rw [Measure.pi_pi]
    congr 1 with j
    by_cases hj : j.val < k.val
    · simp only [if_pos hj, measure_univ]
    · simp [hj]
  rw [factor1, factor2]
  -- Product of factors: ∏ⱼ (if j<k then μ else 1) * ∏ⱼ (if j<k then 1 else μ) = ∏ⱼ μ
  rw [← Finset.prod_mul_distrib]
  congr 1 with j
  by_cases hj : j.val < k.val
  · simp [hj]
  · simp [hj]

/-- For a.e. x, condExpFirstK k f x ≥ 0 when f ≥ 0 a.e.
    This follows from Fubini: the slice f(x_{<k}, ·) ≥ 0 a.e. on coordinates ≥ k. -/
lemma condExpFirstK_nonneg_ae (k : Fin (n + 1)) (f : (Fin n → Ω) → ℝ)
    (hf_nn : 0 ≤ᵐ[μˢ] f) :
    0 ≤ᵐ[μˢ] condExpFirstK (μs := μs) k f := by
  unfold condExpFirstK

  -- Define the substitution map for product
  set φ := fun (p : (Fin n → Ω) × (Fin n → Ω)) =>
    (fun j : Fin n => if j.val < k.val then p.1 j else p.2 j) with hφ_def

  -- φ is measurable
  have hφ_meas : Measurable φ := by
    apply measurable_pi_lambda
    intro j
    by_cases h : j.val < k.val
    · simp only [hφ_def, if_pos h]; exact measurable_fst.eval
    · simp only [hφ_def, if_neg h]; exact measurable_snd.eval

  -- The map φ : μˢ × μˢ → μˢ is measure-preserving (mixes coordinates from x and y)
  have hφ_ae : ∀ᵐ (p : (Fin n → Ω) × (Fin n → Ω)) ∂(μˢ.prod μˢ), 0 ≤ f (φ p) := by
    -- Construct MeasurePreserving from our lemma
    have hφ_mp : MeasurePreserving φ (μˢ.prod μˢ) μˢ := ⟨hφ_meas, map_select_coords_prod_pi k⟩
    -- Use QuasiMeasurePreserving to transfer a.e. property
    exact hφ_mp.quasiMeasurePreserving.ae hf_nn

  -- Now use Fubini: for a.e. x, ∀ᵐ y, f(φ(x,y)) ≥ 0
  have h_fubini : ∀ᵐ x ∂μˢ, ∀ᵐ y ∂μˢ, 0 ≤ f (φ (x, y)) := by
    exact Measure.ae_ae_of_ae_prod hφ_ae
  filter_upwards [h_fubini] with x hx
  apply integral_nonneg_of_ae
  -- Goal: ∀ᵐ y ∂μˢ, 0 ≤ f (fun j => if j.val < k.val then x j else y j)
  convert hx using 1

/-- Integrability of condExpFirstK: if f is integrable, so is condExpFirstK k f.
    This follows from Fubini and the triangle inequality. -/
lemma condExpFirstK_integrable (k : Fin (n + 1)) (f : (Fin n → Ω) → ℝ)
    (hf_int : Integrable f μˢ) :
    Integrable (condExpFirstK (μs := μs) k f) μˢ := by
  unfold condExpFirstK
  -- The substitution map φ : μˢ × μˢ → μˢ that selects coords based on k
  set φ := fun (p : (Fin n → Ω) × (Fin n → Ω)) =>
    (fun j : Fin n => if j.val < k.val then p.1 j else p.2 j) with hφ_def
  -- φ is measurable
  have hφ_meas : Measurable φ := by
    apply measurable_pi_lambda
    intro j
    by_cases h : j.val < k.val
    · simp only [hφ_def, if_pos h]; exact measurable_fst.eval
    · simp only [hφ_def, if_neg h]; exact measurable_snd.eval
  -- Key: φ is measure-preserving from μˢ.prod μˢ to μˢ
  have hφ_mp : MeasurePreserving φ (μˢ.prod μˢ) μˢ := ⟨hφ_meas, map_select_coords_prod_pi k⟩
  -- f ∘ φ is integrable on μˢ.prod μˢ because f is integrable on μˢ
  have hcomp_int : Integrable (f ∘ φ) (μˢ.prod μˢ) :=
    hφ_mp.integrable_comp_of_integrable hf_int
  -- Now use Fubini: x ↦ ∫ f(φ(x, y)) dμˢ(y) is integrable on μˢ
  exact hcomp_int.integral_prod_left

/-- Measurability of condExpFirstK: if f is measurable, so is condExpFirstK k f.
    This follows from Fubini measurability for parametric integrals. -/
lemma condExpFirstK_measurable (k : Fin (n + 1)) (f : (Fin n → Ω) → ℝ)
    (hf_meas : Measurable f) :
    Measurable (condExpFirstK (μs := μs) k f) := by
  unfold condExpFirstK
  -- The substitution map φ : μˢ × μˢ → μˢ that selects coords based on k
  set φ := fun (p : (Fin n → Ω) × (Fin n → Ω)) =>
    (fun j : Fin n => if j.val < k.val then p.1 j else p.2 j) with hφ_def
  -- φ is measurable
  have hφ_meas' : Measurable φ := by
    apply measurable_pi_lambda
    intro j
    by_cases h : j.val < k.val
    · simp only [hφ_def, if_pos h]; exact measurable_fst.eval
    · simp only [hφ_def, if_neg h]; exact measurable_snd.eval
  -- f ∘ φ is measurable
  have hcomp_meas : Measurable (f ∘ φ) := hf_meas.comp hφ_meas'
  -- StronglyMeasurable version for the integral result
  have hsm : StronglyMeasurable (Function.uncurry (fun x y => f (φ (x, y)))) := by
    apply Measurable.stronglyMeasurable
    exact hcomp_meas
  -- Use StronglyMeasurable.integral_prod_right
  exact (hsm.integral_prod_right).measurable

/-- Integrability of T * log(T) where T = condExpFirstK k f. -/
lemma condExpFirstK_mul_log_integrable (k : Fin (n + 1)) (f : (Fin n → Ω) → ℝ)
    (hf_meas : Measurable f)
    (hf_nn : 0 ≤ᵐ[μˢ] f)
    (hf_int : Integrable f μˢ)
    (hf_log_int : Integrable (fun x => f x * log (f x)) μˢ) :
    Integrable (fun x => condExpFirstK (μs := μs) k f x *
                         log (condExpFirstK (μs := μs) k f x)) μˢ := by
  -- Define T = condExpFirstK k f for readability
  set T := condExpFirstK (μs := μs) k f
  -- Define h = condExpFirstK k (f * log f)
  set h := condExpFirstK (μs := μs) k (fun z => f z * log (f z))

  -- T is nonnegative a.e.
  have hT_nn : 0 ≤ᵐ[μˢ] T := condExpFirstK_nonneg_ae k f hf_nn

  -- h is integrable (by condExpFirstK_integrable)
  have hh_int : Integrable h μˢ := condExpFirstK_integrable k (fun z => f z * log (f z)) hf_log_int

  -- T is measurable
  have hT_meas : Measurable T := condExpFirstK_measurable k f hf_meas

  -- By Jensen's inequality: T * log T ≤ h a.e.
  -- This follows from the convexity of t * log t
  have h_jensen : ∀ᵐ x ∂μˢ, T x * log (T x) ≤ h x := by
    -- The substitution map φ : μˢ × μˢ → μˢ that selects coords based on k
    set φ := fun (p : (Fin n → Ω) × (Fin n → Ω)) =>
      (fun j : Fin n => if j.val < k.val then p.1 j else p.2 j) with hφ_def
    -- φ is measurable
    have hφ_meas : Measurable φ := by
      apply measurable_pi_lambda
      intro j
      by_cases h : j.val < k.val
      · simp only [hφ_def, if_pos h]; exact measurable_fst.eval
      · simp only [hφ_def, if_neg h]; exact measurable_snd.eval
    -- φ is measure-preserving
    have hφ_mp : MeasurePreserving φ (μˢ.prod μˢ) μˢ := ⟨hφ_meas, map_select_coords_prod_pi k⟩
    -- f ∘ φ satisfies the nonnegativity condition a.e.
    have hfφ_nn : 0 ≤ᵐ[μˢ.prod μˢ] (f ∘ φ) := hφ_mp.quasiMeasurePreserving.ae hf_nn
    have hfφ_ae_ae : ∀ᵐ x ∂μˢ, ∀ᵐ y ∂μˢ, 0 ≤ f (φ (x, y)) := Measure.ae_ae_of_ae_prod hfφ_nn
    -- f ∘ φ is integrable
    have hfφ_int : Integrable (f ∘ φ) (μˢ.prod μˢ) := hφ_mp.integrable_comp_of_integrable hf_int
    have hint_ae : ∀ᵐ x ∂μˢ, Integrable (fun y => f (φ (x, y))) μˢ := hfφ_int.prod_right_ae
    -- f * log f ∘ φ is integrable
    have hflogφ_int : Integrable ((fun z => f z * log (f z)) ∘ φ) (μˢ.prod μˢ) :=
      hφ_mp.integrable_comp_of_integrable hf_log_int
    have hlogint_ae : ∀ᵐ x ∂μˢ, Integrable (fun y => f (φ (x, y)) * log (f (φ (x, y)))) μˢ :=
      hflogφ_int.prod_right_ae
    -- Apply Jensen's inequality slicewise
    filter_upwards [hfφ_ae_ae, hint_ae, hlogint_ae] with x hnn hint hlogint
    -- At this point, we need Jensen for the conditional expectation
    have hφ_convex : ConvexOn ℝ (Ici 0) (fun t => t * log t) := Real.convexOn_mul_log
    have hcont : ContinuousOn (fun t => t * log t) (Ici 0) := Real.continuous_mul_log.continuousOn
    have hclosed : IsClosed (Ici (0 : ℝ)) := isClosed_Ici
    -- The slice function
    set g := fun y => f (φ (x, y))
    have hmem : ∀ᵐ y ∂μˢ, g y ∈ Ici (0 : ℝ) := hnn
    -- T x = ∫ g dμˢ
    have hT_eq : T x = ∫ y, g y ∂μˢ := by
      simp only [T, condExpFirstK, hφ_def, g]
    -- h x = ∫ g * log g dμˢ
    have hh_eq : h x = ∫ y, g y * log (g y) ∂μˢ := by
      simp only [h, condExpFirstK, hφ_def, g]
    rw [hT_eq, hh_eq]
    exact hφ_convex.map_integral_le hcont hclosed hmem hint hlogint

  -- The bounding function: |h| + 1
  have hbound_int : Integrable (fun x => |h x| + 1) μˢ := hh_int.abs.add (integrable_const 1)

  -- T * log T is AEStronglyMeasurable
  have hTlog_aesm : AEStronglyMeasurable (fun x => T x * log (T x)) μˢ :=
    (hT_meas.mul (measurable_log.comp hT_meas)).aestronglyMeasurable

  apply Integrable.mono' hbound_int hTlog_aesm
  -- The bound: ‖T * log T‖ ≤ |h| + 1
  filter_upwards [hT_nn, h_jensen] with x hT_x_nn hj_x
  rw [Real.norm_eq_abs]
  -- Need: |T x * log (T x)| ≤ |h x| + 1
  by_cases hTx_le_one : T x ≤ 1
  · -- Case: T x ≤ 1
    by_cases hTx_pos : 0 < T x
    · -- 0 < T x ≤ 1: use |x log x| < 1
      have hbound : |T x * log (T x)| < 1 := by
        rw [mul_comm]
        exact Real.abs_log_mul_self_lt (T x) hTx_pos hTx_le_one
      linarith [abs_nonneg (h x)]
    · -- T x = 0 (since T x ≥ 0 and ¬(0 < T x))
      push_neg at hTx_pos
      have hTx_zero : T x = 0 := le_antisymm hTx_pos hT_x_nn
      simp only [hTx_zero, zero_mul, abs_zero]
      linarith [abs_nonneg (h x)]
  · -- Case: T x > 1: T * log T ≥ 0 and T * log T ≤ h, so |T * log T| ≤ |h|
    push_neg at hTx_le_one
    have hTlog_nn : 0 ≤ T x * log (T x) := Real.mul_log_nonneg (le_of_lt hTx_le_one)
    have : |T x * log (T x)| = T x * log (T x) := abs_of_nonneg hTlog_nn
    rw [this]
    calc T x * log (T x) ≤ h x := hj_x
      _ ≤ |h x| := le_abs_self _
      _ ≤ |h x| + 1 := by linarith

/-- Integrability of f * log(T) where T = condExpFirstK k f. -/
lemma f_mul_log_condExpFirstK_integrable (k : Fin (n + 1)) (f : (Fin n → Ω) → ℝ)
    (hf_meas : Measurable f)
    (hf_nn : 0 ≤ᵐ[μˢ] f)
    (hf_int : Integrable f μˢ)
    (hf_log_int : Integrable (fun x => f x * log (f x)) μˢ) :
    Integrable (fun x => f x * log (condExpFirstK (μs := μs) k f x)) μˢ := by
  -- Define T = condExpFirstK k f for readability
  set T := condExpFirstK (μs := μs) k f
  -- T is nonnegative a.e.
  have hT_nn : 0 ≤ᵐ[μˢ] T := condExpFirstK_nonneg_ae k f hf_nn
  -- T is measurable
  have hT_meas : Measurable T := condExpFirstK_measurable k f hf_meas
  -- T * log T is integrable
  have hTlogT_int : Integrable (fun x => T x * log (T x)) μˢ :=
    condExpFirstK_mul_log_integrable k f hf_meas hf_nn hf_int hf_log_int

  -- The substitution map φ : μˢ × μˢ → μˢ that selects coords based on k
  set φ := fun (p : (Fin n → Ω) × (Fin n → Ω)) =>
    (fun j : Fin n => if j.val < k.val then p.1 j else p.2 j) with hφ_def
  -- φ is measurable
  have hφ_meas : Measurable φ := by
    apply measurable_pi_lambda
    intro j
    by_cases h : j.val < k.val
    · simp only [hφ_def, if_pos h]; exact measurable_fst.eval
    · simp only [hφ_def, if_neg h]; exact measurable_snd.eval
  -- φ is measure-preserving
  have hφ_mp : MeasurePreserving φ (μˢ.prod μˢ) μˢ := ⟨hφ_meas, map_select_coords_prod_pi k⟩

  -- Key observation: T(φ(x, y)) = T(x) because T only depends on the first k coordinates
  have hT_first_k : ∀ x y, T (φ (x, y)) = T x := by
    intro x y
    simp only [T, condExpFirstK, hφ_def]
    congr 1 with w
    congr 1 with j
    by_cases hj : j.val < k.val
    · simp only [hj, ↓reduceIte]
    · simp only [hj, ↓reduceIte]

  -- f ∘ φ is integrable
  have hfφ_int : Integrable (f ∘ φ) (μˢ.prod μˢ) := hφ_mp.integrable_comp_of_integrable hf_int

  -- The product function (x, y) ↦ f(φ(x,y)) * log(T(x)) is integrable
  have hprod_int : Integrable (fun p : (Fin n → Ω) × (Fin n → Ω) => f (φ p) * log (T p.1)) (μˢ.prod μˢ) := by

    -- Use Fubini for integrability
    have hprod_aesm : AEStronglyMeasurable (fun p => f (φ p) * log (T p.1)) (μˢ.prod μˢ) := by
      apply AEStronglyMeasurable.mul
      · exact (hf_meas.comp hφ_meas).aestronglyMeasurable
      · exact (measurable_log.comp (hT_meas.comp measurable_fst)).aestronglyMeasurable

    have hfφ_nn : 0 ≤ᵐ[μˢ.prod μˢ] (f ∘ φ) := hφ_mp.quasiMeasurePreserving.ae hf_nn
    have hfφ_ae_ae : ∀ᵐ x ∂μˢ, ∀ᵐ y ∂μˢ, 0 ≤ f (φ (x, y)) := Measure.ae_ae_of_ae_prod hfφ_nn
    have hint_ae : ∀ᵐ x ∂μˢ, Integrable (fun y => f (φ (x, y))) μˢ := hfφ_int.prod_right_ae

    -- For a.e. x, the inner integral ∫ |f(φ(x,y)) * log(T(x))| dμˢ(y) = |log(T(x))| * T(x)
    have h_inner : ∀ᵐ x ∂μˢ, ∫ y, ‖f (φ (x, y)) * log (T x)‖ ∂μˢ = ‖T x * log (T x)‖ := by
      filter_upwards [hfφ_ae_ae, hint_ae, hT_nn] with x hnn hint hT_x_nn
      have h1 : ∫ y, ‖f (φ (x, y)) * log (T x)‖ ∂μˢ = ∫ y, ‖f (φ (x, y))‖ * ‖log (T x)‖ ∂μˢ := by
        apply integral_congr_ae
        filter_upwards with y
        rw [norm_mul]
      rw [h1]
      have h2 : ∫ y, ‖f (φ (x, y))‖ * ‖log (T x)‖ ∂μˢ = ‖log (T x)‖ * ∫ y, ‖f (φ (x, y))‖ ∂μˢ := by
        have heq : ∀ y, ‖f (φ (x, y))‖ * ‖log (T x)‖ = ‖log (T x)‖ * ‖f (φ (x, y))‖ := fun y => mul_comm _ _
        simp_rw [heq]
        exact integral_const_mul _ _
      rw [h2]
      -- ∫ ‖f(φ(x,y))‖ dμˢ = ∫ f(φ(x,y)) dμˢ = T(x) when f ≥ 0 a.e.
      have h3 : ∫ y, ‖f (φ (x, y))‖ ∂μˢ = ∫ y, f (φ (x, y)) ∂μˢ := by
        apply integral_congr_ae
        filter_upwards [hnn] with y hy
        rw [Real.norm_eq_abs, abs_of_nonneg hy]
      rw [h3]
      -- ∫ f(φ(x,y)) dμˢ = T(x)
      have h4 : ∫ y, f (φ (x, y)) ∂μˢ = T x := by
        simp only [T, condExpFirstK, hφ_def]
      rw [h4]
      -- |log(T x)| * T x = |T x * log(T x)| when T x ≥ 0
      rw [Real.norm_eq_abs, Real.norm_eq_abs]
      by_cases hTx_zero : T x = 0
      · simp [hTx_zero]
      · have hTx_pos : 0 < T x := lt_of_le_of_ne hT_x_nn (Ne.symm hTx_zero)
        rw [abs_mul, abs_of_nonneg (le_of_lt hTx_pos), mul_comm]

    -- Now use Fubini: if iterated integral is finite, then the product is integrable
    rw [Integrable, and_iff_right hprod_aesm]
    calc ∫⁻ p, ‖f (φ p) * log (T p.1)‖₊ ∂(μˢ.prod μˢ)
        = ∫⁻ x, ∫⁻ y, ‖f (φ (x, y)) * log (T x)‖₊ ∂μˢ ∂μˢ := by
            rw [MeasureTheory.lintegral_prod _ hprod_aesm.aemeasurable.nnnorm.coe_nnreal_ennreal]
      _ = ∫⁻ x, ENNReal.ofReal (∫ y, ‖f (φ (x, y)) * log (T x)‖ ∂μˢ) ∂μˢ := by
            apply lintegral_congr_ae
            filter_upwards [hint_ae] with x hint
            -- Convert nnnorm to ofReal norm
            have hnorm_eq : ∀ y, (‖f (φ (x, y)) * log (T x)‖₊ : ℝ≥0∞) =
                ENNReal.ofReal ‖f (φ (x, y)) * log (T x)‖ := fun y => by
              rw [← enorm_eq_nnnorm, ← ofReal_norm_eq_enorm]
            simp_rw [hnorm_eq]
            rw [ofReal_integral_eq_lintegral_ofReal]
            · -- Integrability of the norm function
              have heq : (fun y => ‖f (φ (x, y)) * log (T x)‖) = (fun y => ‖f (φ (x, y))‖ * ‖log (T x)‖) := by
                ext y; exact norm_mul _ _
              rw [heq]
              exact hint.norm.mul_const _
            · filter_upwards with y; exact norm_nonneg _
      _ = ∫⁻ x, ENNReal.ofReal ‖T x * log (T x)‖ ∂μˢ := by
            apply lintegral_congr_ae
            filter_upwards [h_inner] with x hx
            rw [hx]
      _ = ∫⁻ x, ‖T x * log (T x)‖₊ ∂μˢ := by
            apply lintegral_congr_ae
            filter_upwards with x
            rw [ofReal_norm_eq_enorm, enorm_eq_nnnorm]
      _ < ⊤ := hTlogT_int.2

  -- Show that the function is dominated by something integrable
  have hflogT_aesm : AEStronglyMeasurable (fun x => f x * log (T x)) μˢ :=
    (hf_meas.mul (measurable_log.comp hT_meas)).aestronglyMeasurable

  -- Use Fubini characterization: the integral ∫ |f * log T| dμˢ = ∫ |T * log T| dμˢ
  rw [Integrable, and_iff_right hflogT_aesm]

  -- Show ∫⁻ |f * log T| dμˢ = ∫⁻ |T * log T| dμˢ via measure-preserving map
  -- Key: T(φ(p)) = T(p.1) by hT_first_k, so f(φ(p)) * log(T(φ(p))) = f(φ(p)) * log(T(p.1))
  have h_eq_integrand : ∀ p : (Fin n → Ω) × (Fin n → Ω),
      ‖f (φ p) * log (T (φ p))‖₊ = ‖f (φ p) * log (T p.1)‖₊ := by
    intro p
    rw [hT_first_k p.1 p.2]
  calc ∫⁻ x, ‖f x * log (T x)‖₊ ∂μˢ
      = ∫⁻ p, ‖f (φ p) * log (T (φ p))‖₊ ∂(μˢ.prod μˢ) := by
          rw [← hφ_mp.lintegral_comp]
          exact (hf_meas.mul (measurable_log.comp hT_meas)).nnnorm.coe_nnreal_ennreal
    _ = ∫⁻ p, ‖f (φ p) * log (T p.1)‖₊ ∂(μˢ.prod μˢ) := by
          apply lintegral_congr
          intro p
          rw [h_eq_integrand p]
    _ < ⊤ := hprod_int.2

/-- Tower property (pointwise, when slice is integrable):
    condExpFirstK k f x = condExpExceptCoord k (condExpFirstK (k+1) f) x

    This version requires the slice at x to be integrable. For the a.e. version
    (which is what's typically needed), see `condExpFirstK_tower_ae`. -/
theorem condExpFirstK_tower_of_integrable_slice (k : Fin n) (f : (Fin n → Ω) → ℝ) (x : Fin n → Ω)
    (hf_meas : Measurable f)
    (hslice : Integrable (fun y => f (fun j => if j.val < k.val then x j else y j)) μˢ) :
    condExpFirstK (μs := μs) k.castSucc f x =
    condExpExceptCoord (μs := μs) k (condExpFirstK (μs := μs) k.succ f) x := by
  unfold condExpFirstK condExpExceptCoord

  -- The MeasurePreserving property for (z, w) ↦ update w k z
  have hmp : MeasurePreserving (fun p : Ω × (Fin n → Ω) => Function.update p.2 k p.1)
             ((μs k).prod μˢ) μˢ := by
    constructor
    · have : (fun p : Ω × (Fin n → Ω) => Function.update p.2 k p.1) =
             (fun q : (Fin n → Ω) × Ω => Function.update q.1 k q.2) ∘ Prod.swap := rfl
      rw [this]
      exact (measurable_update' (a := k)).comp measurable_swap
    · exact map_update_prod_pi k

  -- Define G for clarity
  let G : Ω → (Fin n → Ω) → ℝ := fun z w =>
    f (fun j => if j.val < k.val then x j else if j = k then z else w j)

  -- Note: k.castSucc.val = k.val (castSucc preserves the value)
  have hcast : (k.castSucc : Fin (n + 1)).val = k.val := Fin.val_castSucc k

  -- Show LHS integrand equals G (y k) y
  have hLHS_eq : ∀ y : Fin n → Ω,
      f (fun j => if j.val < (k.castSucc : Fin (n + 1)).val then x j else y j) = G (y k) y := by
    intro y
    congr 1 with j
    simp only [hcast]
    by_cases hj_lt : j.val < k.val
    · simp [hj_lt]
    · simp only [hj_lt, ↓reduceIte]
      by_cases hj_eq : j = k
      · simp [hj_eq]
      · simp [hj_eq]

  -- Show RHS inner integrand equals G z w
  have hRHS_eq : ∀ z : Ω, ∀ w : Fin n → Ω,
      (fun j => if j.val < (k.succ : Fin (n + 1)).val then
           (Function.update x k z) j else w j) = (fun j => if j.val < k.val then x j else if j = k then z else w j) := by
    intro z w
    ext j
    simp only [Fin.val_succ]
    by_cases hj_lt : j.val < k.val
    · -- j < k implies j < k + 1 and j ≠ k
      have hj_lt_succ : j.val < k.val + 1 := Nat.lt_succ_of_lt hj_lt
      have hj_ne : j ≠ k := fun h => by simp [h] at hj_lt
      simp only [hj_lt_succ, ↓reduceIte, hj_lt]
      rw [Function.update_of_ne hj_ne]
    · -- j ≥ k, so either j = k or j > k
      by_cases hj_eq : j = k
      · -- j = k: j.val = k.val < k.val + 1
        simp only [hj_eq, Nat.lt_succ_self, ↓reduceIte, Nat.lt_irrefl]
        rw [hj_eq, Function.update_self]
      · -- j ≠ k and j.val ≥ k.val, so j.val > k.val, so j.val ≥ k.val + 1
        have hj_gt : j.val > k.val := Nat.lt_of_le_of_ne (Nat.le_of_not_lt hj_lt) (fun h => hj_eq (Fin.ext h.symm))
        have hj_ge_succ : ¬(j.val < k.val + 1) := Nat.not_lt_of_ge hj_gt
        simp only [hj_ge_succ, ↓reduceIte, hj_lt, hj_eq]

  -- Rewrite both sides using the simplified forms
  conv_lhs =>
    rw [integral_congr_ae (Eventually.of_forall hLHS_eq)]

  -- For RHS, show the inner integrand equals G z w
  have hRHS_eq_G : ∀ z : Ω, ∀ w : Fin n → Ω,
      f (fun j => if j.val < (k.succ : Fin (n + 1)).val then
           (Function.update x k z) j else w j) = G z w := by
    intro z w
    rw [hRHS_eq]

  -- Show the RHS inner integral has equal integrand to G z w
  have hRHS_inner_eq : ∀ z : Ω, ∀ w : Fin n → Ω,
      f (fun j => if j.val < (k.succ : Fin (n + 1)).val then
           (if j = k then z else x j) else w j) = G z w := by
    intro z w
    congr 1 with j
    simp only [Fin.val_succ]
    by_cases hj_lt : j.val < k.val
    · have hj_ne : j ≠ k := fun h => by simp [h] at hj_lt
      have hj_lt_succ : j.val < k.val + 1 := Nat.lt_succ_of_lt hj_lt
      simp only [hj_lt_succ, ↓reduceIte, hj_ne, hj_lt]
    · by_cases hj_eq : j = k
      · subst hj_eq
        simp only [Nat.lt_succ_self, ↓reduceIte, hj_lt]
      · have hj_gt : j.val > k.val := Nat.lt_of_le_of_ne (Nat.le_of_not_lt hj_lt) (fun h => hj_eq (Fin.ext h.symm))
        have hj_ge_succ : ¬(j.val < k.val + 1) := Nat.not_lt_of_ge hj_gt
        simp only [hj_ge_succ, ↓reduceIte, hj_lt, hj_eq]

  -- Show: for all w, the integrand in the unfolded RHS equals f(...) with (if j = k then z else x j)
  have hRHS_update_eq : ∀ z : Ω, ∀ w : Fin n → Ω, ∀ j : Fin n,
      (if j.val < (k.succ : Fin (n + 1)).val then (Function.update x k z) j else w j) =
      (if j.val < (k.succ : Fin (n + 1)).val then (if j = k then z else x j) else w j) := by
    intro z w j
    by_cases h : j.val < (k.succ : Fin (n + 1)).val
    · simp only [h, ↓reduceIte]
      by_cases hj_eq : j = k
      · subst hj_eq; simp only [Function.update_self, ↓reduceIte]
      · simp only [hj_eq, ↓reduceIte, Function.update_of_ne hj_eq]
    · simp only [h, ↓reduceIte]

  -- Now use the simplified form
  have hRHS_simp : ∀ z : Ω, ∀ w : Fin n → Ω,
      (fun j => if j.val < (k.succ : Fin (n + 1)).val then (Function.update x k z) j else w j) =
      (fun j => if j.val < (k.succ : Fin (n + 1)).val then (if j = k then z else x j) else w j) := by
    intro z w; ext j; exact hRHS_update_eq z w j

  have hRHS_eq_G' : ∀ z : Ω, ∀ w : Fin n → Ω,
      f (fun j => if j.val < (k.succ : Fin (n + 1)).val then
           (Function.update x k z) j else w j) = G z w := by
    intro z w
    rw [hRHS_simp z w]
    exact hRHS_inner_eq z w

  -- Create a version that works with the actual unfolded expression
  have hRHS_int_eq : ∀ z : Ω,
      (fun w : Fin n → Ω => f (fun j => if j.val < (k.succ : Fin (n + 1)).val then
           (Function.update x k z) j else w j)) =
      (fun w : Fin n → Ω => G z w) := by
    intro z; ext w; exact hRHS_eq_G' z w

  conv_rhs =>
    arg 2
    ext z
    -- First beta-reduce the function application
    simp only []
    rw [integral_congr_ae (Eventually.of_forall (fun w => hRHS_eq_G' z w))]

  -- G z (update w k z) = G z w since G ignores coord k in w
  have hG_update : ∀ z : Ω, ∀ w : Fin n → Ω,
      G z (Function.update w k z) = G z w := by
    intro z w
    simp only [G]
    congr 1 with j
    by_cases hj_lt : j.val < k.val
    · simp [hj_lt]
    · by_cases hj_eq : j = k
      · simp [hj_eq]
      · simp only [hj_lt, ↓reduceIte, hj_eq]
        rw [Function.update_of_ne hj_eq]

  -- Establish measurability of G
  have hG_meas : Measurable (fun p : Ω × (Fin n → Ω) => G p.1 p.2) := by
    simp only [G]
    apply hf_meas.comp
    apply measurable_pi_lambda
    intro j
    by_cases hj_lt : j.val < k.val
    · -- j < k: returns x j (constant)
      simp only [hj_lt, ↓reduceIte]
      exact measurable_const
    · by_cases hj_eq : j = k
      · -- j = k: returns z (first component)
        subst hj_eq
        simp only [lt_irrefl, ↓reduceIte]
        exact measurable_fst
      · -- j > k: returns w j (from second component)
        simp only [hj_lt, hj_eq, ↓reduceIte]
        exact (measurable_pi_apply j).comp measurable_snd

  -- Integrability of G on product via measure-preserving map
  have hG_int_prod : Integrable (fun p : Ω × (Fin n → Ω) => G p.1 p.2) ((μs k).prod μˢ) := by
      -- Key: G p.1 p.2 = slice_func (update p.2 k p.1) where slice_func is integrable
      -- Define slice_func
      let slice_func : (Fin n → Ω) → ℝ := fun y => f (fun j => if j.val < k.val then x j else y j)
      -- Show G p.1 p.2 = slice_func (update p.2 k p.1)
      have h_eq : (fun p : Ω × (Fin n → Ω) => G p.1 p.2) =
                  slice_func ∘ (fun p => Function.update p.2 k p.1) := by
        ext p
        simp only [slice_func, G, Function.comp_apply]
        congr 1 with j
        by_cases hj_lt : j.val < k.val
        · simp only [hj_lt, ↓reduceIte]
        · simp only [hj_lt, ↓reduceIte]
          by_cases hj_eq : j = k
          · rw [hj_eq, if_pos rfl, Function.update_self]
          · simp only [if_neg hj_eq, Function.update_of_ne hj_eq]
      rw [h_eq]
      -- slice_func is integrable on μˢ by hslice
      have hslice' : Integrable slice_func μˢ := hslice
      -- Use measure-preserving to transfer integrability
      exact (hmp.integrable_comp hslice'.aestronglyMeasurable).mpr hslice'

  -- Step 1: LHS integral equals product integral via measure-preserving
  have h1 : ∫ y, G (y k) y ∂μˢ = ∫ p, G p.1 (Function.update p.2 k p.1) ∂((μs k).prod μˢ) := by
    have hG_slice_meas : Measurable (fun y => G (y k) y) :=
      hG_meas.comp (Measurable.prodMk (measurable_pi_apply k) measurable_id)
    -- Use measure-preserving and integral_map
    calc ∫ y, G (y k) y ∂μˢ
        = ∫ y, G (y k) y ∂(Measure.map (fun p => Function.update p.2 k p.1) ((μs k).prod μˢ)) := by
            rw [hmp.map_eq]
      _ = ∫ p, G ((Function.update p.2 k p.1) k) (Function.update p.2 k p.1) ∂((μs k).prod μˢ) := by
            rw [integral_map hmp.aemeasurable hG_slice_meas.aestronglyMeasurable]
      _ = ∫ p, G p.1 (Function.update p.2 k p.1) ∂((μs k).prod μˢ) := by
            apply integral_congr_ae
            filter_upwards with p
            simp only [Function.update_self]

  -- Step 2: Simplify using hG_update
  have h2 : ∫ p, G p.1 (Function.update p.2 k p.1) ∂((μs k).prod μˢ) =
            ∫ p, G p.1 p.2 ∂((μs k).prod μˢ) := by
    apply integral_congr_ae
    filter_upwards with p
    exact hG_update p.1 p.2

  -- Step 3: Apply Fubini
  have h3 : ∫ p, G p.1 p.2 ∂((μs k).prod μˢ) = ∫ z, ∫ w, G z w ∂μˢ ∂(μs k) := by
    exact integral_prod (fun p : Ω × (Fin n → Ω) => G p.1 p.2) hG_int_prod

  rw [h1, h2, h3]

/-- Tower property (a.e. version): condExpFirstK k f =ᵐ condExpExceptCoord k (condExpFirstK (k+1) f)

    E_k[f] = E^{(k)}[E_{k+1}[f]] almost everywhere. -/
theorem condExpFirstK_tower (k : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_meas : Measurable f) (_hf_nn : 0 ≤ᵐ[μˢ] f) (hf_int : Integrable f μˢ) :
    (fun x => condExpFirstK (μs := μs) k.castSucc f x) =ᵐ[μˢ]
    (fun x => condExpExceptCoord (μs := μs) k (condExpFirstK (μs := μs) k.succ f) x) := by

  -- The substitution map φ : μˢ × μˢ → μˢ that selects coords based on k
  set φ := fun (p : (Fin n → Ω) × (Fin n → Ω)) =>
    (fun j : Fin n => if j.val < k.val then p.1 j else p.2 j) with hφ_def

  -- φ is measurable
  have hφ_meas : Measurable φ := by
    apply measurable_pi_lambda
    intro j
    by_cases h : j.val < k.val
    · simp only [hφ_def, if_pos h]; exact measurable_fst.eval
    · simp only [hφ_def, if_neg h]; exact measurable_snd.eval

  -- Key: φ is measure-preserving from μˢ.prod μˢ to μˢ
  have hφ_mp : MeasurePreserving φ (μˢ.prod μˢ) μˢ := ⟨hφ_meas, map_select_coords_prod_pi k.castSucc⟩

  -- f ∘ φ is integrable on μˢ.prod μˢ because f is integrable on μˢ
  have hcomp_int : Integrable (f ∘ φ) (μˢ.prod μˢ) :=
    hφ_mp.integrable_comp_of_integrable hf_int

  -- By Fubini, for a.e. x, the slice y ↦ f(φ(x,y)) = f(x_{<k}, y) is integrable
  have hslice_int_ae : ∀ᵐ x ∂μˢ, Integrable (fun y => f (φ (x, y))) μˢ :=
    hcomp_int.prod_right_ae

  -- For those x where the slice is integrable, apply the pointwise theorem
  filter_upwards [hslice_int_ae] with x hslice_x

  -- Verify the slice function matches what we need
  have hslice_eq : (fun y => f (fun j => if j.val < k.val then x j else y j)) =
                   (fun y => f (φ (x, y))) := by
    ext y
    simp only [hφ_def]

  -- Apply the pointwise theorem
  have hslice' : Integrable (fun y => f (fun j => if j.val < k.val then x j else y j)) μˢ := by
    rw [hslice_eq]
    exact hslice_x

  exact condExpFirstK_tower_of_integrable_slice k f x hf_meas hslice'

/-- Integrability of f * log(E^{(i)}[T_{i+1}]) where T_{i+1} = condExpFirstK (i+1) f. -/
lemma f_mul_log_condExpExceptCoord_condExpFirstK_integrable (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_meas : Measurable f) (hf_nn : 0 ≤ᵐ[μˢ] f) (hf_int : Integrable f μˢ)
    (hf_log_int : Integrable (fun x => f x * log (f x)) μˢ) :
    Integrable (fun x => f x *
        log (condExpExceptCoord (μs := μs) i (condExpFirstK (μs := μs) i.succ f) x)) μˢ := by
  -- By tower property: condExpFirstK i.castSucc f =ᵐ condExpExceptCoord i (condExpFirstK i.succ f)
  have h_tower := condExpFirstK_tower i f hf_meas hf_nn hf_int

  -- The target function is a.e. equal to f * log(condExpFirstK i.castSucc f)
  have h_ae_eq : (fun x => f x * log (condExpFirstK (μs := μs) i.castSucc f x)) =ᵐ[μˢ]
      (fun x => f x *
      log (condExpExceptCoord (μs := μs) i (condExpFirstK (μs := μs) i.succ f) x)) := by
    filter_upwards [h_tower] with x hx
    rw [hx]

  -- Apply integrability for f * log(condExpFirstK i.castSucc f)
  have hint := f_mul_log_condExpFirstK_integrable i.castSucc f hf_meas hf_nn hf_int hf_log_int
  exact hint.congr h_ae_eq

/-- Integrability of E^{(i)}[f] * log(E^{(i)}[T_{i+1}]) where T_{i+1} = condExpFirstK (i+1) f. -/
lemma condExpExceptCoord_mul_log_condExpFirstK_integrable (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_meas : Measurable f) (hf_nn : 0 ≤ᵐ[μˢ] f) (hf_int : Integrable f μˢ)
    (hf_log_int : Integrable (fun x => f x * log (f x)) μˢ) :
    Integrable (fun x => condExpExceptCoord (μs := μs) i f x *
        log (condExpExceptCoord (μs := μs) i (condExpFirstK (μs := μs) i.succ f) x)) μˢ := by
  -- By tower property: E^{(i)}[T_{i+1}] = T_i a.e.
  have h_tower := condExpFirstK_tower i f hf_meas hf_nn hf_int

  -- So the target is a.e. equal to E^{(i)}[f] * log(T_i)
  set T_i := condExpFirstK (μs := μs) i.castSucc f
  set E_i_f := condExpExceptCoord (μs := μs) i f

  have h_target_ae : (fun x => E_i_f x *
      log (condExpExceptCoord (μs := μs) i (condExpFirstK (μs := μs) i.succ f) x)) =ᵐ[μˢ]
      (fun x => E_i_f x * log (T_i x)) := by
    filter_upwards [h_tower] with x hx
    rw [hx]

  -- T_i is measurable
  have hT_meas : Measurable T_i := condExpFirstK_measurable i.castSucc f hf_meas
  -- E^{(i)}[f] is integrable (hence AEStronglyMeasurable)
  have hE_int := condExpExceptCoord_integrable i f hf_int

  have hE_aesm : AEStronglyMeasurable E_i_f μˢ := hE_int.aestronglyMeasurable
  have hlogT_aesm : AEStronglyMeasurable (fun x => log (T_i x)) μˢ :=
    (measurable_log.comp hT_meas).aestronglyMeasurable
  have hprod_aesm : AEStronglyMeasurable (fun x => E_i_f x * log (T_i x)) μˢ :=
    hE_aesm.mul hlogT_aesm

  apply Integrable.congr _ h_target_ae.symm
  refine ⟨hprod_aesm, ?_⟩

  -- f * log(T_i) is integrable
  have hflogT_int : Integrable (fun x => f x * log (T_i x)) μˢ :=
    f_mul_log_condExpFirstK_integrable i.castSucc f hf_meas hf_nn hf_int hf_log_int

  -- T_i doesn't depend on coordinate i: T_i(update x i y) = T_i(x)
  have hT_indep_coord_i : ∀ x y, T_i (Function.update x i y) = T_i x := by
    intro x y
    simp only [T_i, condExpFirstK]
    congr 1 with w
    congr 1 with j
    by_cases hj : j.val < i.val
    · simp only [Fin.val_castSucc, hj, ↓reduceIte]
      have hj_ne_i : j ≠ i := Fin.ne_of_val_ne (Nat.ne_of_lt hj)
      rw [Function.update_of_ne hj_ne_i]
    · simp only [Fin.val_castSucc, hj, ↓reduceIte]

  -- The measure-preserving map for update
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

  -- f ∘ update is integrable
  have hf_comp_int : Integrable (fun p : (Fin n → Ω) × Ω => f (Function.update p.1 i p.2))
      (μˢ.prod (μs i)) :=
    hmp.integrable_comp hf_int.aestronglyMeasurable |>.mpr hf_int

  -- Slice integrability: for a.e. x, fun y => f(update x i y) is integrable over μs(i)
  have hslice_int : ∀ᵐ x ∂μˢ, Integrable (fun y => f (Function.update x i y)) (μs i) :=
    hf_comp_int.prod_right_ae

  -- log(T_i(update x i y)) = log(T_i(x)) for all y
  have hlogT_const : ∀ x y, log (T_i (Function.update x i y)) = log (T_i x) := by
    intro x y; rw [hT_indep_coord_i]

  -- The key calculation: ∫ ‖E^{(i)}[f] * log(T_i)‖₊ dμˢ = ∫ ‖f * log(T_i)‖₊ dμˢ
  calc ∫⁻ x, ‖E_i_f x * log (T_i x)‖₊ ∂μˢ
    -- Expand E^{(i)}[f] and use that log(T_i) is constant in coordinate i
    _ = ∫⁻ x, ‖(∫ y, f (Function.update x i y) ∂(μs i)) * log (T_i x)‖₊ ∂μˢ := by
        apply lintegral_congr_ae
        filter_upwards with x
        rfl
    -- Pull log(T_i) inside the integral (it doesn't depend on y)
    _ = ∫⁻ x, ‖∫ y, f (Function.update x i y) * log (T_i x) ∂(μs i)‖₊ ∂μˢ := by
        apply lintegral_congr_ae
        filter_upwards [hslice_int] with x hslice
        congr 1
        rw [← integral_mul_const_of_integrable hslice]
    -- Bound by ∫∫ |f * log(T_i)| via triangle inequality
    _ ≤ ∫⁻ x, ∫⁻ y, ‖f (Function.update x i y) * log (T_i x)‖₊ ∂(μs i) ∂μˢ := by
        apply lintegral_mono_ae
        filter_upwards with x
        calc (‖∫ y, f (Function.update x i y) * log (T_i x) ∂(μs i)‖₊ : ℝ≥0∞)
          _ ≤ ∫⁻ y, ‖f (Function.update x i y) * log (T_i x)‖₊ ∂(μs i) := by
              simp only [← enorm_eq_nnnorm]
              exact enorm_integral_le_lintegral_enorm _
    -- Use Fubini to convert to product integral
    _ = ∫⁻ p, ‖f (Function.update p.1 i p.2) * log (T_i p.1)‖₊ ∂(μˢ.prod (μs i)) := by
        symm
        exact lintegral_prod _ ((hf_meas.comp (measurable_update' (a := i))).mul
            (measurable_log.comp (hT_meas.comp measurable_fst))).nnnorm.coe_nnreal_ennreal.aemeasurable
    -- Use T_i(update x i y) = T_i(x)
    _ = ∫⁻ p, ‖f (Function.update p.1 i p.2) * log (T_i (Function.update p.1 i p.2))‖₊ ∂(μˢ.prod (μs i)) := by
        apply lintegral_congr
        intro p
        rw [hlogT_const p.1 p.2]
    -- Apply measure-preserving property
    _ = ∫⁻ z, ‖f z * log (T_i z)‖₊ ∂μˢ := by
        have h := hmp.lintegral_comp (hf_meas.mul (measurable_log.comp hT_meas)).nnnorm.coe_nnreal_ennreal
        simp only [Function.comp_apply] at h
        exact h
    _ < ⊤ := hflogT_int.2

/-!
## Positivity Preservation for Conditional Expectations
-/

/-- For a.e. slice x, if Y(y) > 0 then T'(y) = condExpFirstK ... > 0. -/
lemma condExpFirstK_pos_on_slice_ae (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_meas : Measurable f) (hf_nn : 0 ≤ᵐ[μˢ] f) (hf_int : Integrable f μˢ) :
    ∀ᵐ x ∂μˢ, ∀ᵐ y ∂(μs i), 0 < f (Function.update x i y) →
      0 < condExpFirstK (μs := μs) i.succ f (Function.update x i y) := by
  -- The integrand g(w, z) = f(if j < i+1 then w_j else z_j)
  let g : (Fin n → Ω) → (Fin n → Ω) → ℝ := fun w z =>
    f (fun j => if j.val < (i.succ : Fin (n+1)).val then w j else z j)

  -- Key: The map (x, y) ↦ update x i y is measure-preserving from μˢ.prod (μs i) to μˢ.
  -- This allows us to transfer a.e. properties from μˢ to the product measure.
  have hmp : MeasurePreserving (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2)
               (μˢ.prod (μs i)) μˢ := by
    constructor
    · exact measurable_update' (a := i)
    · -- map (x, y) ↦ update x i y pushes forward μˢ × (μs i) to μˢ
      have hg' : Measurable (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) :=
        (measurable_update' (a := i)).comp measurable_swap
      calc Measure.map (fun p : (Fin n → Ω) × Ω => Function.update p.1 i p.2) (μˢ.prod (μs i))
        _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1)
            (Measure.map Prod.swap (μˢ.prod (μs i))) := (Measure.map_map hg' measurable_swap).symm
        _ = Measure.map (fun q : Ω × (Fin n → Ω) => Function.update q.2 i q.1) ((μs i).prod μˢ) := by
            rw [Measure.prod_swap]
        _ = μˢ := map_update_prod_pi i

  let bad : (Fin n → Ω) × Ω → Prop := fun p =>
    condExpFirstK (μs := μs) i.succ f (Function.update p.1 i p.2) = 0 ∧
    f (Function.update p.1 i p.2) > 0

  let S : Set (Fin n → Ω) := {z | condExpFirstK (μs := μs) i.succ f z = 0 ∧ f z > 0}

  have hS_meas : MeasurableSet S := by
    apply MeasurableSet.inter
    · exact (condExpFirstK_measurable i.succ f hf_meas) (measurableSet_singleton 0)
    · exact measurableSet_preimage hf_meas measurableSet_Ioi

  have h_bad_eq_preimage : {p : (Fin n → Ω) × Ω | bad p} =
      (fun p => Function.update p.1 i p.2) ⁻¹' S := by
    ext p
    simp only [S, bad, Set.mem_setOf_eq, Set.mem_preimage]

  have hS_null : μˢ S = 0 := by
    set φ := fun p : (Fin n → Ω) × (Fin n → Ω) =>
      (fun j : Fin n => if j.val < i.succ.val then p.1 j else p.2 j) with hφ_def

    have hφ_meas : Measurable φ := by
      apply measurable_pi_lambda
      intro j
      by_cases h : j.val < i.succ.val
      · simp only [hφ_def, if_pos h]; exact measurable_fst.eval
      · simp only [hφ_def, if_neg h]; exact measurable_snd.eval

    have hφ_mp : MeasurePreserving φ (μˢ.prod μˢ) μˢ :=
      ⟨hφ_meas, map_select_coords_prod_pi i.succ⟩

    have hT_φ : ∀ x y, condExpFirstK (μs := μs) i.succ f (φ (x, y)) =
        condExpFirstK (μs := μs) i.succ f x := by
      intro x y
      unfold condExpFirstK
      congr 1 with w
      simp only [hφ_def]
      congr 1 with j
      by_cases hj : j.val < i.succ.val
      · rw [if_pos hj, if_pos hj, if_pos hj]
      · rw [if_neg hj, if_neg hj]

    have hφ_preimage : φ ⁻¹' S = {p : (Fin n → Ω) × (Fin n → Ω) |
        condExpFirstK (μs := μs) i.succ f p.1 = 0 ∧ f (φ p) > 0} := by
      ext ⟨x, y⟩
      simp only [S, Set.mem_preimage, Set.mem_setOf_eq, hT_φ x y]

    have h_meas_eq : μˢ S = (μˢ.prod μˢ) (φ ⁻¹' S) := by
      rw [← Measure.map_apply hφ_meas hS_meas]
      rw [hφ_mp.map_eq]

    rw [h_meas_eq]

    have hfφ_nn : 0 ≤ᵐ[μˢ.prod μˢ] (f ∘ φ) := hφ_mp.quasiMeasurePreserving.ae hf_nn

    have hfφ_ae_ae : ∀ᵐ x ∂μˢ, ∀ᵐ y ∂μˢ, 0 ≤ f (φ (x, y)) := by
      exact Measure.ae_ae_of_ae_prod hfφ_nn

    have hfφ_int : Integrable (f ∘ φ) (μˢ.prod μˢ) :=
      hφ_mp.integrable_comp_of_integrable hf_int

    have hint_ae : ∀ᵐ x ∂μˢ, Integrable (fun y => f (φ (x, y))) μˢ := by
      have := Integrable.prod_right_ae hfφ_int
      filter_upwards [this] with x hx
      exact hx

    have hT_eq_int : ∀ x, condExpFirstK (μs := μs) i.succ f x = ∫ y, f (φ (x, y)) ∂μˢ := by
      intro x
      unfold condExpFirstK
      simp only [hφ_def]

    have h_fiber_null : ∀ᵐ x ∂μˢ, condExpFirstK (μs := μs) i.succ f x = 0 →
        ∀ᵐ y ∂μˢ, f (φ (x, y)) ≤ 0 := by
      filter_upwards [hfφ_ae_ae, hint_ae] with x hnn hint hT_zero
      have h_int_zero : ∫ y, f (φ (x, y)) ∂μˢ = 0 := by
        rw [← hT_eq_int x, hT_zero]
      have h_eq_zero := (integral_eq_zero_iff_of_nonneg_ae hnn hint).mp h_int_zero
      filter_upwards [h_eq_zero] with y hy
      simp only [Pi.zero_apply] at hy
      rw [hy]

    rw [hφ_preimage]

    have hset_meas : MeasurableSet {p : (Fin n → Ω) × (Fin n → Ω) |
        condExpFirstK (μs := μs) i.succ f p.1 = 0 ∧ f (φ p) > 0} := by
      apply MeasurableSet.inter
      · exact (condExpFirstK_measurable i.succ f hf_meas).comp measurable_fst
              (measurableSet_singleton 0)
      · exact (hf_meas.comp hφ_meas) measurableSet_Ioi

    apply Measure.measure_prod_null_of_ae_null hset_meas
    filter_upwards [h_fiber_null, hfφ_ae_ae] with x hfiber hnn
    show μˢ (Prod.mk x ⁻¹' {p | condExpFirstK (μs := μs) i.succ f p.1 = 0 ∧ f (φ p) > 0}) = 0

    have h_fiber_eq : Prod.mk x ⁻¹' {p | condExpFirstK (μs := μs) i.succ f p.1 = 0 ∧ f (φ p) > 0} =
        {y | condExpFirstK (μs := μs) i.succ f x = 0 ∧ f (φ (x, y)) > 0} := rfl
    rw [h_fiber_eq]

    by_cases hT : condExpFirstK (μs := μs) i.succ f x = 0
    · have hfφ_le : ∀ᵐ y ∂μˢ, f (φ (x, y)) ≤ 0 := hfiber hT
      have h_zero_ae : ∀ᵐ y ∂μˢ, f (φ (x, y)) = 0 := by
        filter_upwards [hnn, hfφ_le] with y hge hle
        linarith
      rw [ae_iff] at h_zero_ae
      apply measure_mono_null _ h_zero_ae
      intro y ⟨_, hpos⟩
      exact ne_of_gt hpos
    · have h_empty : {y | condExpFirstK (μs := μs) i.succ f x = 0 ∧ f (φ (x, y)) > 0} = ∅ := by
        ext y
        simp only [Set.mem_setOf_eq, Set.mem_empty_iff_false, iff_false]
        intro ⟨hTeq, _⟩
        exact hT hTeq
      rw [h_empty, measure_empty]

  have h_bad_null : (μˢ.prod (μs i)) {p | bad p} = 0 := by
    rw [h_bad_eq_preimage]
    rw [← Measure.map_apply measurable_update' hS_meas, hmp.map_eq]
    exact hS_null

  have hT_nonneg_ae_prod : ∀ᵐ p ∂(μˢ.prod (μs i)),
      0 ≤ condExpFirstK (μs := μs) i.succ f (Function.update p.1 i p.2) := by
    have hT_nonneg := condExpFirstK_nonneg_ae (μs := μs) i.succ f hf_nn
    have h_bad_null : μˢ {x | ¬(0 ≤ condExpFirstK (μs := μs) i.succ f x)} = 0 := by
      rw [← ae_iff]
      exact hT_nonneg
    rw [ae_iff]
    have h_eq : {p : (Fin n → Ω) × Ω | ¬0 ≤ condExpFirstK (μs := μs) i.succ f (Function.update p.1 i p.2)} =
        (fun p => Function.update p.1 i p.2) ⁻¹' {x | ¬0 ≤ condExpFirstK (μs := μs) i.succ f x} := rfl
    rw [h_eq]
    have hbad_meas : MeasurableSet {x | ¬0 ≤ condExpFirstK (μs := μs) i.succ f x} :=
      (condExpFirstK_measurable i.succ f hf_meas) measurableSet_Ici.compl
    rw [← Measure.map_apply (measurable_update' (a := i)) hbad_meas, hmp.map_eq]
    exact h_bad_null

  have h_T_nonneg_ae_ae := Measure.ae_ae_of_ae_prod hT_nonneg_ae_prod

  have h_ae_ae := @Measure.ae_ae_of_ae_prod _ _ _ _ μˢ (μs i) _ (fun p => ¬bad p) ?_
  · filter_upwards [h_ae_ae, h_T_nonneg_ae_ae] with x hx hTx
    filter_upwards [hx, hTx] with y hy hT_nonneg
    intro hf_pos
    simp only [bad, not_and, not_lt] at hy
    by_contra hT_le
    push_neg at hT_le
    have hT_eq_zero : condExpFirstK (μs := μs) i.succ f (Function.update x i y) = 0 :=
      le_antisymm hT_le hT_nonneg
    have hf_le := hy hT_eq_zero
    linarith
  · rw [ae_iff]
    have h_eq : {a : (Fin n → Ω) × Ω | ¬¬bad a} = {a | bad a} := by
      ext a; simp only [Set.mem_setOf_eq, not_not]
    rw [h_eq]
    exact h_bad_null

/-!
## Term-wise Inequality using Entropy Duality
-/

/-- The integral of f * (log E_{i+1}[f] - log E_i[f]) is bounded by E[Ent^{(i)}(f)].

    This follows from applying entropy duality on each slice (fixing all coords except i). -/
theorem term_le_expected_condEnt (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_meas : Measurable f)
    (hf_nn : 0 ≤ᵐ[μˢ] f)
    (hf_int : Integrable f μˢ)
    (hf_log_int : Integrable (fun x => f x * log (f x)) μˢ) :
    ∫ x, f x * (log (condExpFirstK (μs := μs) i.succ f x) -
                log (condExpFirstK (μs := μs) i.castSucc f x)) ∂μˢ ≤
    ∫ x, condEntExceptCoord (μs := μs) i f x ∂μˢ := by
  -- Derive integrability hypotheses from lemmas
  have hflogT_int : Integrable (fun x => f x * log (condExpFirstK (μs := μs) i.succ f x)) μˢ :=
    f_mul_log_condExpFirstK_integrable i.succ f hf_meas hf_nn hf_int hf_log_int
  have hflogET_int : Integrable (fun x => f x *
      log (condExpExceptCoord (μs := μs) i (condExpFirstK (μs := μs) i.succ f) x)) μˢ :=
    f_mul_log_condExpExceptCoord_condExpFirstK_integrable i f hf_meas hf_nn hf_int hf_log_int
  have hEflogET_int : Integrable (fun x => condExpExceptCoord (μs := μs) i f x *
      log (condExpExceptCoord (μs := μs) i (condExpFirstK (μs := μs) i.succ f) x)) μˢ :=
    condExpExceptCoord_mul_log_condExpFirstK_integrable i f hf_meas hf_nn hf_int hf_log_int
  have hEf_log_int : Integrable (fun x => condExpExceptCoord (μs := μs) i f x *
      log (condExpExceptCoord (μs := μs) i f x)) μˢ :=
    condExpExceptCoord_mul_log_integrable i f hf_meas hf_nn hf_int hf_log_int
  have h_tower : (fun x => condExpFirstK (μs := μs) i.castSucc f x) =ᵐ[μˢ]
      (fun x => condExpExceptCoord (μs := μs) i (condExpFirstK (μs := μs) i.succ f) x) :=
    condExpFirstK_tower i f hf_meas hf_nn hf_int

  have h_rw : (fun x => f x * (log (condExpFirstK (μs := μs) i.succ f x) -
                          log (condExpFirstK (μs := μs) i.castSucc f x))) =ᵐ[μˢ]
              (fun x => f x * (log (condExpFirstK (μs := μs) i.succ f x) -
                     log (condExpExceptCoord (μs := μs) i (condExpFirstK (μs := μs) i.succ f) x))) := by
    filter_upwards [h_tower] with x hx
    rw [hx]

  rw [integral_congr_ae h_rw]

  have h_indep : ∀ x y : Fin n → Ω,
      condExpExceptCoord (μs := μs) i (condExpFirstK (μs := μs) i.succ f) x =
      condExpExceptCoord (μs := μs) i (condExpFirstK (μs := μs) i.succ f) (Function.update x i (y i)) := by
    intro x y
    rw [condExpExceptCoord_update]

  -- Slice-by-slice application of entropy duality via Fubini
  have hnn_ae := ae_nonneg_slice_of_ae_nonneg i f hf_nn
  have hint_ae := integrable_update_slice i f hf_int
  have hlogint_ae := integrable_update_slice i (fun z => f z * log (f z)) hf_log_int

  set T := condExpFirstK (μs := μs) i.succ f with hT_def
  have hT_int : Integrable T μˢ := condExpFirstK_integrable i.succ f hf_int

  have hT_slice_int_ae := integrable_update_slice i T hT_int
  have h_condEnt_nonneg := integral_condEntExceptCoord_nonneg i f hf_nn hf_int hf_log_int

  have h_log_factor : ∀ᵐ x ∂μˢ, f x * log (condExpExceptCoord (μs := μs) i T x) =
      f x * log (condExpFirstK (μs := μs) i.castSucc f x) := by
    filter_upwards [h_tower] with x hx
    rw [← hx]

  have h_nonneg_ae : ∀ᵐ x ∂μˢ, 0 ≤ condEntExceptCoord (μs := μs) i f x := by
    filter_upwards [hnn_ae, hint_ae, hlogint_ae] with x hnn hint hlogint
    exact condEntExceptCoord_nonneg_at i f x hnn hint hlogint
  have h_log_const_factor : ∀ x, ∫ y, f (Function.update x i y) * log (condExpExceptCoord (μs := μs) i T x) ∂(μs i) =
      log (condExpExceptCoord (μs := μs) i T x) * condExpExceptCoord (μs := μs) i f x := by
    intro x
    have h_comm : ∀ y, f (Function.update x i y) * log (condExpExceptCoord (μs := μs) i T x) =
        log (condExpExceptCoord (μs := μs) i T x) * f (Function.update x i y) := by
      intro y; ring
    simp_rw [h_comm, integral_const_mul]
    rfl

  let Ef := condExpExceptCoord (μs := μs) i f
  let ET := condExpExceptCoord (μs := μs) i T
  let EflogT := condExpExceptCoord (μs := μs) i (fun x => f x * log (T x))
  let Eflogf := condExpExceptCoord (μs := μs) i (fun x => f x * log (f x))

  have hT_nn_ae : 0 ≤ᵐ[μˢ] T := condExpFirstK_nonneg_ae i.succ f hf_nn
  have hT_slice_nn_ae := ae_nonneg_slice_of_ae_nonneg i T hT_nn_ae
  have hflogT_slice_int_ae := integrable_update_slice i (fun z => f z * log (T z)) hflogT_int

  have h_slice_bound : ∀ᵐ x ∂μˢ,
      EflogT x - Ef x * log (ET x) ≤ Eflogf x - Ef x * log (Ef x) := by
    filter_upwards [hnn_ae, hint_ae, hlogint_ae, hT_slice_nn_ae, hT_slice_int_ae, hflogT_slice_int_ae, condExpFirstK_pos_on_slice_ae i f hf_meas hf_nn hf_int] with x hnn hint hlogint hT'_nn_ae hT'_int hYlogT'_int_x hT'_pos_on_Y_raw
    set Y := fun y => f (Function.update x i y) with hY_def
    set T' := fun y => T (Function.update x i y) with hT'_def
    have hEf_eq : Ef x = ∫ y, Y y ∂(μs i) := rfl
    have hET_eq : ET x = ∫ y, T' y ∂(μs i) := rfl
    have hEflogT_eq : EflogT x = ∫ y, Y y * log (T' y) ∂(μs i) := rfl
    have hEflogf_eq : Eflogf x = ∫ y, Y y * log (Y y) ∂(μs i) := rfl
    have hT'_nn : ∀ᵐ y ∂(μs i), 0 ≤ T' y := hT'_nn_ae
    by_cases hET_pos : 0 < ET x
    · -- Case: E[T'] > 0, apply entropy_ge_integral_log (Gibbs inequality)
      have hRHS_eq : Eflogf x - Ef x * log (Ef x) = condEntExceptCoord (μs := μs) i f x := rfl
      have hY_meas : Measurable Y := by
        apply hf_meas.comp
        apply measurable_pi_lambda
        intro j
        by_cases hj : j = i
        · subst hj; simp only [Function.update_self]; exact measurable_id
        · simp only [Function.update_of_ne hj]; exact measurable_const
      have hT'_meas : Measurable T' := by
        have hT_meas : Measurable T := by
          simp only [T]
          let g : (Fin n → Ω) → (Fin n → Ω) → ℝ := fun w z =>
              f (fun j => if j.val < (Fin.succ i).val then w j else z j)
          have hg_sm : StronglyMeasurable (Function.uncurry g) := by
            apply StronglyMeasurable.comp_measurable hf_meas.stronglyMeasurable
            apply measurable_pi_lambda
            intro j
            by_cases hj : j.val < (Fin.succ i).val
            · simp only [hj, ↓reduceIte]; exact measurable_fst.eval
            · simp only [hj, ↓reduceIte]; exact measurable_snd.eval
          exact (hg_sm.integral_prod_right).measurable
        apply hT_meas.comp
        apply measurable_pi_lambda
        intro j
        by_cases hj : j = i
        · subst hj; simp only [Function.update_self]; exact measurable_id
        · simp only [Function.update_of_ne hj]; exact measurable_const

      have h_ereal_bound := LogSobolev.entropy_ge_integral_log (μ := μs i)
        Y hY_meas hnn hint hlogint T' hT'_meas hT'_nn hT'_int hET_pos
      have hT'_pos_on_Y : ∀ᵐ y ∂(μs i), 0 < Y y → 0 < T' y := hT'_pos_on_Y_raw
      rw [LogSobolev.integralYLogT_of_pos_on_Y Y T' hT'_pos_on_Y] at h_ereal_bound
      have h_real_bound : ∫ y, Y y * (log (T' y) - log (∫ y', T' y' ∂μs i)) ∂μs i ≤
          LogSobolev.entropy (μs i) Y := EReal.coe_le_coe_iff.mp h_ereal_bound
      have hYlogT'_int : Integrable (fun y => Y y * log (T' y)) (μs i) := hYlogT'_int_x
      set c := log (∫ y', T' y' ∂μs i)
      calc EflogT x - Ef x * log (ET x)
          = ∫ y, Y y * log (T' y) ∂μs i - Ef x * log (ET x) := by rw [hEflogT_eq]
        _ = ∫ y, Y y * log (T' y) ∂μs i - (∫ y, Y y ∂μs i) * log (∫ y, T' y ∂μs i) := by
            rw [hEf_eq, hET_eq]
        _ = ∫ y, Y y * (log (T' y) - c) ∂μs i := by
            have h_const : (∫ y, Y y ∂μs i) * c = ∫ y, Y y * c ∂μs i :=
              (integral_mul_const_of_integrable hint).symm
            rw [h_const]
            symm
            rw [← integral_sub hYlogT'_int (hint.mul_const c)]
            apply integral_congr_ae; filter_upwards with y; ring
        _ ≤ LogSobolev.entropy (μs i) Y := h_real_bound
        _ = Eflogf x - Ef x * log (Ef x) := by
            unfold LogSobolev.entropy
            rw [hEflogf_eq, hEf_eq]

    · -- Case: E[T'] = 0 (since T' ≥ 0), so LHS = 0 ≤ RHS
      have hET_nonneg : 0 ≤ ET x := integral_nonneg_of_ae hT'_nn
      have hET_zero : ET x = 0 := le_antisymm (le_of_not_gt hET_pos) hET_nonneg
      have hT'_zero_ae : ∀ᵐ y ∂(μs i), T' y = 0 := by
        have hint_T' : Integrable T' (μs i) := hT'_int
        exact (integral_eq_zero_iff_of_nonneg_ae hT'_nn hint_T').mp hET_zero
      have hLHS_zero : EflogT x - Ef x * log (ET x) = 0 := by
        have hEflogT_zero : EflogT x = 0 := by
          rw [hEflogT_eq]
          have h_integrand_zero : ∀ᵐ y ∂(μs i), Y y * log (T' y) = 0 := by
            filter_upwards [hT'_zero_ae] with y hy
            simp only [hy, log_zero, mul_zero]
          rw [integral_congr_ae h_integrand_zero, integral_zero]
        simp only [hEflogT_zero, hET_zero, log_zero, mul_zero, sub_zero]
      rw [hLHS_zero]
      exact condEntExceptCoord_nonneg_at i f x hnn hint hlogint
  have hRHS_eq : ∫ x, condEntExceptCoord (μs := μs) i f x ∂μˢ =
      ∫ x, (Eflogf x - Ef x * log (Ef x)) ∂μˢ := by
    apply integral_congr_ae
    filter_upwards with x
    rfl

  have hLHS_eq : ∫ x, f x * (log (T x) - log (condExpExceptCoord (μs := μs) i T x)) ∂μˢ =
      ∫ x, (EflogT x - Ef x * log (ET x)) ∂μˢ := by
    have h1 : ∫ x, f x * (log (T x) - log (condExpExceptCoord (μs := μs) i T x)) ∂μˢ =
              ∫ x, f x * log (T x) ∂μˢ - ∫ x, f x * log (condExpExceptCoord (μs := μs) i T x) ∂μˢ := by
      have h_eq : ∀ x, f x * (log (T x) - log (condExpExceptCoord (μs := μs) i T x)) =
                  f x * log (T x) - f x * log (condExpExceptCoord (μs := μs) i T x) := by
        intro x; ring
      rw [integral_congr_ae (Eventually.of_forall h_eq)]
      exact integral_sub hflogT_int hflogET_int
    have h2 : ∫ x, f x * log (T x) ∂μˢ = ∫ x, EflogT x ∂μˢ := by
      symm
      exact condExpExceptCoord_expectation i (fun x => f x * log (T x)) hflogT_int
    have h3 : ∫ x, f x * log (condExpExceptCoord (μs := μs) i T x) ∂μˢ =
              ∫ x, Ef x * log (ET x) ∂μˢ := by
      have h_commute_l : ∀ x, f x * log (condExpExceptCoord (μs := μs) i T x) =
                              log (condExpExceptCoord (μs := μs) i T x) * f x := by intro x; ring
      have h_commute_r : ∀ x, Ef x * log (ET x) = log (ET x) * Ef x := by intro x; ring
      simp_rw [h_commute_l, h_commute_r]
      have h_cond_exp_factor : ∀ x, condExpExceptCoord (μs := μs) i (fun z => log (ET z) * f z) x =
          log (ET x) * Ef x := by
        intro x
        simp only [condExpExceptCoord, Ef, ET]
        have h_ET_const : ∀ y, condExpExceptCoord (μs := μs) i T (Function.update x i y) =
                               condExpExceptCoord (μs := μs) i T x := by
          intro y
          have := h_indep x (Function.update x i y)
          simp only [Function.update_self] at this
          exact this.symm
        have h_integrand_eq : ∀ y, log (condExpExceptCoord (μs := μs) i T (Function.update x i y)) *
                                   f (Function.update x i y) =
                                   log (condExpExceptCoord (μs := μs) i T x) * f (Function.update x i y) := by
          intro y
          rw [h_ET_const y]
        calc ∫ y, log (condExpExceptCoord i T (Function.update x i y)) * f (Function.update x i y) ∂μs i
            = ∫ y, log (condExpExceptCoord i T x) * f (Function.update x i y) ∂μs i := by
                apply integral_congr_ae; filter_upwards with y; exact h_integrand_eq y
          _ = log (condExpExceptCoord i T x) * ∫ y, f (Function.update x i y) ∂μs i :=
                integral_const_mul _ _
          _ = log (condExpExceptCoord i T x) * condExpExceptCoord i f x := rfl
      calc ∫ x, log (condExpExceptCoord (μs := μs) i T x) * f x ∂μˢ
          = ∫ x, condExpExceptCoord (μs := μs) i (fun z => log (ET z) * f z) x ∂μˢ := by
              symm
              apply condExpExceptCoord_expectation
              have h_comm : (fun x => log (ET x) * f x) = (fun x => f x * log (ET x)) := by
                ext x; ring
              rw [h_comm]
              exact hflogET_int
        _ = ∫ x, log (ET x) * Ef x ∂μˢ := by
              apply integral_congr_ae
              filter_upwards with x
              exact h_cond_exp_factor x
    rw [h1, h2, h3]
    symm
    apply integral_sub
    · exact condExpExceptCoord_integrable i (fun x => f x * log (T x)) hflogT_int
    · exact hEflogET_int

  rw [hRHS_eq, hLHS_eq]
  apply integral_mono_ae
  · apply Integrable.sub
    · exact condExpExceptCoord_integrable i (fun x => f x * log (T x)) hflogT_int
    · exact hEflogET_int
  · exact condEntExceptCoord_integrable' i f hf_log_int hEf_log_int
  · exact h_slice_bound

/-!
## Main Theorem: Subadditivity of Entropy
-/

/-- For a nonnegative measurable function f of n independent random variables,
    the entropy is bounded by the sum of expected conditional entropies:

    Ent(f) ≤ ∑_{i=0}^{n-1} E[Ent^{(i)}(f)] -/
theorem entropy_subadditive (f : (Fin n → Ω) → ℝ)
    (hf_meas : Measurable f)
    (hf_nn : 0 ≤ᵐ[μˢ] f)
    (hf_int : Integrable f μˢ)
    (hf_log_int : Integrable (fun x => f x * log (f x)) μˢ) :
    LogSobolev.entropy μˢ f ≤ ∑ i : Fin n, ∫ x, condEntExceptCoord (μs := μs) i f x ∂μˢ := by
  unfold LogSobolev.entropy

  rcases Nat.eq_zero_or_pos n with hn | hn
  · -- n = 0: f is constant on the trivial space, so Ent(f) = 0
    subst hn
    simp only [Fin.sum_univ_zero]
    have h_const : ∀ x y : Fin 0 → Ω, x = y := fun x y => funext (fun i => Fin.elim0 i)
    have hf_const_val : ∀ x y : Fin 0 → Ω, f x = f y := fun x y => by rw [h_const x y]
    have pt : Fin 0 → Ω := Fin.elim0
    have hf_eq_pt : ∀ x, f x = f pt := fun x => hf_const_val x pt
    have hflog_eq_pt : ∀ x, f x * log (f x) = f pt * log (f pt) := fun x => by rw [hf_eq_pt x]
    conv_lhs =>
      arg 1
      rw [integral_eq_const (Eventually.of_forall hflog_eq_pt)]
    conv_lhs =>
      arg 2
      arg 1
      rw [integral_eq_const (Eventually.of_forall hf_eq_pt)]
    conv_lhs =>
      arg 2
      arg 2
      arg 1
      rw [integral_eq_const (Eventually.of_forall hf_eq_pt)]
    ring_nf
    exact le_refl 0

  · -- n > 0: use telescoping + term bounds
    have h_tele := entropy_telescoping_pointwise (μs := μs) f

    have h_term_bound : ∀ i : Fin n,
        ∫ x, f x * (log (condExpFirstK (μs := μs) i.succ f x) -
                    log (condExpFirstK (μs := μs) i.castSucc f x)) ∂μˢ ≤
        ∫ x, condEntExceptCoord (μs := μs) i f x ∂μˢ := by
      intro i
      exact term_le_expected_condEnt i f hf_meas hf_nn hf_int hf_log_int

    have h_sum_eq_ent : ∫ x, f x * (log (f x) - log (∫ z, f z ∂μˢ)) ∂μˢ =
        ∑ i : Fin n, ∫ x, f x * (log (condExpFirstK (μs := μs) i.succ f x) -
                                  log (condExpFirstK (μs := μs) i.castSucc f x)) ∂μˢ := by
      have h_ae : ∀ x, f x * (log (f x) - log (∫ z, f z ∂μˢ)) =
          ∑ i : Fin n, f x * (log (condExpFirstK (μs := μs) i.succ f x) -
                               log (condExpFirstK (μs := μs) i.castSucc f x)) := h_tele
      rw [integral_congr_ae (Eventually.of_forall h_ae)]
      have h_term_int : ∀ i : Fin n, Integrable (fun x => f x *
          (log (condExpFirstK (μs := μs) i.succ f x) -
           log (condExpFirstK (μs := μs) i.castSucc f x))) μˢ := by
        intro i
        have h_tower : (fun x => condExpFirstK (μs := μs) i.castSucc f x) =ᵐ[μˢ]
            (fun x => condExpExceptCoord (μs := μs) i (condExpFirstK (μs := μs) i.succ f) x) :=
          condExpFirstK_tower i f hf_meas hf_nn hf_int
        have h_eq : (fun x => f x * (log (condExpFirstK (μs := μs) i.succ f x) -
                     log (condExpFirstK (μs := μs) i.castSucc f x))) =ᵐ[μˢ]
            (fun x => f x * (log (condExpFirstK (μs := μs) i.succ f x) -
                     log (condExpExceptCoord (μs := μs) i (condExpFirstK (μs := μs) i.succ f) x))) := by
          filter_upwards [h_tower] with x hx
          rw [hx]
        apply Integrable.congr _ h_eq.symm
        have h_decomp : ∀ x, f x * (log (condExpFirstK (μs := μs) i.succ f x) -
            log (condExpExceptCoord (μs := μs) i (condExpFirstK (μs := μs) i.succ f) x)) =
            f x * log (condExpFirstK (μs := μs) i.succ f x) -
            f x * log (condExpExceptCoord (μs := μs) i (condExpFirstK (μs := μs) i.succ f) x) := by
          intro x; ring
        simp_rw [h_decomp]
        exact Integrable.sub
          (f_mul_log_condExpFirstK_integrable i.succ f hf_meas hf_nn hf_int hf_log_int)
          (f_mul_log_condExpExceptCoord_condExpFirstK_integrable i f hf_meas hf_nn hf_int hf_log_int)
      rw [integral_finset_sum Finset.univ (fun i _ => h_term_int i)]

    have h_ent_eq : LogSobolev.entropy μˢ f =
        ∫ x, f x * (log (f x) - log (∫ z, f z ∂μˢ)) ∂μˢ := by
      unfold LogSobolev.entropy
      rw [sub_eq_iff_eq_add]
      have h_const_factor : ∫ x, f x * log (∫ z, f z ∂μˢ) ∂μˢ =
          log (∫ z, f z ∂μˢ) * ∫ x, f x ∂μˢ := by
        have h1 : ∫ x, f x * log (∫ z, f z ∂μˢ) ∂μˢ = ∫ x, log (∫ z, f z ∂μˢ) * f x ∂μˢ := by
          apply integral_congr_ae
          filter_upwards with x
          ring
        rw [h1, integral_const_mul]
      have h_decomp : ∫ x, f x * (log (f x) - log (∫ z, f z ∂μˢ)) ∂μˢ =
          ∫ x, f x * log (f x) ∂μˢ - ∫ x, f x * log (∫ z, f z ∂μˢ) ∂μˢ := by
        rw [← integral_sub hf_log_int]
        · apply integral_congr_ae
          filter_upwards with x
          ring
        · exact hf_int.mul_const _
      rw [h_decomp, h_const_factor]
      ring

    have h_goal : ∫ x, f x * log (f x) ∂μˢ - (∫ x, f x ∂μˢ) * log (∫ x, f x ∂μˢ) =
        LogSobolev.entropy μˢ f := rfl
    rw [h_goal, h_ent_eq, h_sum_eq_ent]
    apply Finset.sum_le_sum
    intro i _
    exact h_term_bound i

end SubAddEnt

end

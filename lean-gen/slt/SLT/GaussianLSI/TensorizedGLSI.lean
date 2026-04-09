/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.GaussianLSI.OneDimGLSI
import SLT.GaussianLSI.SubAddEnt.Subadditivity
import SLT.GaussianMeasure
import SLT.EfronStein
import Mathlib.Analysis.Calculus.FDeriv.Pi
import Mathlib.Analysis.Calculus.FDeriv.Measurable
import Mathlib.Analysis.Calculus.Deriv.Basic
import Mathlib.MeasureTheory.Integral.Prod

/-!
# Tensorized Gaussian Log-Sobolev Inequality

This file proves the dimension-free Gaussian log-Sobolev inequality for product Gaussians
via tensorization. The key technique reduces the n-dimensional LSI to one-dimensional
slices using entropy subadditivity.

## Main definitions

* `partialDeriv`: Partial derivative along coordinate `i`.
* `gradNormSq`: Squared gradient norm as sum of squared partial derivatives.
* `MemW12GaussianPi`: Sobolev W^{1,2} membership for Gaussian product spaces.
* `sliceFunction`: Function restricted to vary along a single coordinate.

## Main results

* `slice_memW12_ae`: Slices of W^{1,2} functions are a.e. in W^{1,2}(ℝ).
* `condEnt_sq_le_partial_deriv_sq`: Conditional entropy bounded by partial derivative.
* `sum_expected_condEnt_le_grad_norm`: Sum of conditional entropies bounded by gradient norm.
* `gaussian_logSobolev_W12_pi`: Dimension-free Gaussian LSI: Ent(g²) ≤ 2∫‖∇g‖².

-/

noncomputable section

open MeasureTheory ProbabilityTheory Filter Real
open scoped BigOperators ENNReal

namespace GaussianLSI

/-- The partial derivative of `g` at `x` along coordinate `i`. -/
noncomputable def partialDeriv {n : ℕ} (i : Fin n) (g : (Fin n → ℝ) → ℝ) : (Fin n → ℝ) → ℝ :=
  fun x => fderiv ℝ g x (Pi.single i 1)

/-- Squared Euclidean gradient norm: `‖∇g(x)‖² = ∑ᵢ (∂g/∂xᵢ)²`. -/
noncomputable def gradNormSq (n : ℕ) (g : (Fin n → ℝ) → ℝ) : (Fin n → ℝ) → ℝ :=
  fun x => ∑ i : Fin n, (partialDeriv i g x)^2

/-- Sobolev W^{1,2} membership: `g ∈ L²(μ)` and all partial derivatives in `L²(μ)`. -/
def MemW12GaussianPi (n : ℕ) (g : (Fin n → ℝ) → ℝ) (μ : Measure (Fin n → ℝ)) : Prop :=
  MemLp g 2 μ ∧ ∀ i : Fin n, MemLp (fun x => partialDeriv i g x) 2 μ

/-- Slice function `gᵢˣ(y) = g(x₁,...,y,...,xₙ)` with `y` at position `i`. -/
def sliceFunction {n : ℕ} (i : Fin n) (g : (Fin n → ℝ) → ℝ) (x : Fin n → ℝ) : ℝ → ℝ :=
  fun y => g (Function.update x i y)

/-! ## Slice function properties -/

/-- Slices of differentiable functions are differentiable. -/
lemma sliceFunction_differentiable {n : ℕ} (i : Fin n) (g : (Fin n → ℝ) → ℝ)
    (hg_diff : Differentiable ℝ g) (x : Fin n → ℝ) :
    Differentiable ℝ (sliceFunction i g x) := by
  intro y
  have h_update : DifferentiableAt ℝ (fun y => Function.update x i y) y :=
    (hasFDerivAt_update (x := x) (i := i) (y := y)).differentiableAt
  exact (hg_diff (Function.update x i y)).comp y h_update

/-- Derivative of slice equals partial derivative at updated point. -/
lemma deriv_sliceFunction_eq_partialDeriv {n : ℕ} (i : Fin n) (g : (Fin n → ℝ) → ℝ)
    (hg_diff : Differentiable ℝ g) (x : Fin n → ℝ) (y : ℝ) :
    deriv (sliceFunction i g x) y = partialDeriv i g (Function.update x i y) := by
  have h_update : HasFDerivAt (fun y => Function.update x i y)
      (ContinuousLinearMap.pi (Pi.single i (ContinuousLinearMap.id ℝ ℝ))) y := by
    simpa using (hasFDerivAt_update (x := x) (i := i) (y := y))
  have h_g : HasFDerivAt g (fderiv ℝ g (Function.update x i y)) (Function.update x i y) :=
    (hg_diff (Function.update x i y)).hasFDerivAt
  have h_comp : HasFDerivAt (sliceFunction i g x)
      ((fderiv ℝ g (Function.update x i y)).comp
        (ContinuousLinearMap.pi (Pi.single i (ContinuousLinearMap.id ℝ ℝ)))) y :=
    h_g.comp y h_update
  have h_update_apply :
      (ContinuousLinearMap.pi (Pi.single i (ContinuousLinearMap.id ℝ ℝ))) 1 =
        (Pi.single (M := fun _ : Fin n => ℝ) i 1) := by
    ext j
    by_cases hji : j = i
    · subst hji
      simp [ContinuousLinearMap.pi_apply, Pi.single]
    · simp [ContinuousLinearMap.pi_apply, Pi.single, hji]
  have h_deriv_eq := h_comp.hasDerivAt.deriv
  simpa [partialDeriv, ContinuousLinearMap.comp_apply, h_update_apply] using h_deriv_eq

lemma continuous_fderiv_of_continuous_deriv (f : ℝ → ℝ)
    (h_deriv : Continuous (fun x => deriv f x)) :
    Continuous (fun x => fderiv ℝ f x) := by
  have h_smulRight_cont : Continuous (fun a : ℝ => (1 : ℝ →L[ℝ] ℝ).smulRight a) := by
    simpa using (ContinuousLinearMap.continuous
      ((ContinuousLinearMap.smulRightL (𝕜 := ℝ) (E := ℝ) (Fₗ := ℝ))
        (1 : ℝ →L[ℝ] ℝ)))
  have h_eq : (fun x => fderiv ℝ f x) =
      fun x => (1 : ℝ →L[ℝ] ℝ).smulRight (deriv f x) := by
    funext x
    ext
    simp [ContinuousLinearMap.smulRight_apply, mul_comm]
  have h_cont := h_smulRight_cont.comp h_deriv
  simpa [h_eq] using h_cont

lemma slice_fderiv_continuous {n : ℕ} (i : Fin n) (g : (Fin n → ℝ) → ℝ)
    (hg_diff : Differentiable ℝ g)
    (hg_grad_cont : ∀ i, Continuous (fun x => partialDeriv i g x))
    (x : Fin n → ℝ) :
    Continuous (fun y => fderiv ℝ (sliceFunction i g x) y) := by
  have h_update_cont : Continuous (fun y => Function.update x i y) := by
    simpa using (Continuous.update (f := fun _ : ℝ => x) (g := fun y : ℝ => y)
      (i := i) continuous_const continuous_id)
  have h_deriv_cont : Continuous (fun y => deriv (sliceFunction i g x) y) := by
    have h_eq : (fun y => deriv (sliceFunction i g x) y) =
        fun y => partialDeriv i g (Function.update x i y) := by
      funext y
      exact deriv_sliceFunction_eq_partialDeriv i g hg_diff x y
    simpa [h_eq] using (hg_grad_cont i).comp h_update_cont
  exact continuous_fderiv_of_continuous_deriv (f := sliceFunction i g x) h_deriv_cont

/-! ## Conditional entropy and partial derivatives -/

lemma condEntExceptCoord_sq_eq_slice_entropy {n : ℕ} (i : Fin n) (g : (Fin n → ℝ) → ℝ)
    (x : Fin n → ℝ) :
    SubAddEnt.condEntExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
      (fun z => (g z)^2) x =
      LogSobolev.entropy (gaussianReal 0 1) (fun y => (sliceFunction i g x y)^2) := by
  rfl

/-- Slices of W^{1,2} functions are a.e. in the one-dimensional Gaussian Sobolev space. -/
lemma slice_memW12_ae {n : ℕ} (i : Fin n) (g : (Fin n → ℝ) → ℝ)
    (hg : MemW12GaussianPi n g (GaussianMeasure.stdGaussianPi n))
    (hg_diff : Differentiable ℝ g) :
    ∀ᵐ x ∂(GaussianMeasure.stdGaussianPi n),
      GaussianSobolevReal.MemW12GaussianReal (sliceFunction i g x) (gaussianReal 0 1) := by
  have hg_L2 : Integrable (fun z => (g z)^2) (GaussianMeasure.stdGaussianPi n) :=
    (hg.1).integrable_sq
  have hgi_L2 : Integrable (fun z => (partialDeriv i g z)^2) (GaussianMeasure.stdGaussianPi n) :=
    (hg.2 i).integrable_sq
  have h_g_slice :
      ∀ᵐ x ∂(GaussianMeasure.stdGaussianPi n),
        Integrable (fun y => (g (Function.update x i y))^2) (gaussianReal 0 1) := by
    simpa [GaussianMeasure.stdGaussianPi] using
      (SubAddEnt.integrable_update_slice (μs := fun _ : Fin n => gaussianReal 0 1) i
        (fun z => (g z)^2) hg_L2)
  have h_dg_slice :
      ∀ᵐ x ∂(GaussianMeasure.stdGaussianPi n),
        Integrable (fun y => (partialDeriv i g (Function.update x i y))^2) (gaussianReal 0 1) := by
    simpa [GaussianMeasure.stdGaussianPi] using
      (SubAddEnt.integrable_update_slice (μs := fun _ : Fin n => gaussianReal 0 1) i
        (fun z => (partialDeriv i g z)^2) hgi_L2)
  filter_upwards [h_g_slice, h_dg_slice] with x hgx hdx
  have h_slice_cont : Continuous (sliceFunction i g x) :=
    (sliceFunction_differentiable i g hg_diff x).continuous
  have h_slice_aesm : AEStronglyMeasurable (sliceFunction i g x) (gaussianReal 0 1) :=
    h_slice_cont.aestronglyMeasurable
  have h_slice_mem : MemLp (sliceFunction i g x) 2 (gaussianReal 0 1) := by
    refine (MeasureTheory.memLp_two_iff_integrable_sq h_slice_aesm).2 ?_
    simpa [sliceFunction] using hgx
  have h_fderiv_aesm :
      AEStronglyMeasurable (fun y => fderiv ℝ (sliceFunction i g x) y) (gaussianReal 0 1) :=
    (measurable_fderiv (𝕜 := ℝ) (f := sliceFunction i g x)).aestronglyMeasurable
  have h_deriv_sq :
      Integrable (fun y => ‖fderiv ℝ (sliceFunction i g x) y‖^2) (gaussianReal 0 1) := by
    have h_eq : (fun y => ‖fderiv ℝ (sliceFunction i g x) y‖^2) =
        fun y => (partialDeriv i g (Function.update x i y))^2 := by
      funext y
      have h_norm : ‖fderiv ℝ (sliceFunction i g x) y‖ =
          ‖deriv (sliceFunction i g x) y‖ := by
        simpa using
          (norm_deriv_eq_norm_fderiv (f := sliceFunction i g x) (x := y)).symm
      calc
        ‖fderiv ℝ (sliceFunction i g x) y‖^2
            = ‖deriv (sliceFunction i g x) y‖^2 := by
                simp [h_norm]
        _ = (partialDeriv i g (Function.update x i y))^2 := by
            simp [deriv_sliceFunction_eq_partialDeriv (i := i) (g := g) hg_diff x y,
              Real.norm_eq_abs, sq_abs]
    simpa [h_eq] using hdx
  have h_slice_deriv_mem :
      MemLp (fun y => fderiv ℝ (sliceFunction i g x) y) 2 (gaussianReal 0 1) := by
    exact (MeasureTheory.memLp_two_iff_integrable_sq_norm h_fderiv_aesm).2 h_deriv_sq
  exact ⟨h_slice_mem, h_slice_deriv_mem⟩

/-- Conditional entropy of `g²` bounded by `2∫(∂ᵢg)²` via one-dimensional LSI. -/
lemma condEnt_sq_le_partial_deriv_sq {n : ℕ} (i : Fin n) (g : (Fin n → ℝ) → ℝ)
    (hg_diff : Differentiable ℝ g)
    (hg_grad_cont : ∀ i, Continuous (fun x => partialDeriv i g x))
    (x : Fin n → ℝ)
    (hslice : GaussianSobolevReal.MemW12GaussianReal (sliceFunction i g x) (gaussianReal 0 1)) :
    SubAddEnt.condEntExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
        (fun z => (g z)^2) x ≤
      2 * ∫ y, (partialDeriv i g (Function.update x i y))^2 ∂(gaussianReal 0 1) := by
  have h_diff : Differentiable ℝ (sliceFunction i g x) :=
    sliceFunction_differentiable i g hg_diff x
  have h_grad_cont : Continuous (fun y => fderiv ℝ (sliceFunction i g x) y) :=
    slice_fderiv_continuous i g hg_diff hg_grad_cont x
  have h_lsi :=
    GaussianSobolevReal.gaussian_logSobolev_W12_real
      (f := sliceFunction i g x) hslice h_diff h_grad_cont
  have h_lsi' :
      LogSobolev.entropy (gaussianReal 0 1) (fun y => (sliceFunction i g x y)^2) ≤
        2 * ∫ y, ‖fderiv ℝ (sliceFunction i g x) y‖^2 ∂(gaussianReal 0 1) := by
    simpa [GaussianPoincare.stdGaussianMeasure, GaussianPoincare.stdGaussian] using h_lsi
  have h_ent_eq := condEntExceptCoord_sq_eq_slice_entropy (i := i) (g := g) (x := x)
  have h_lsi'' :
      SubAddEnt.condEntExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
          (fun z => (g z)^2) x ≤
        2 * ∫ y, ‖fderiv ℝ (sliceFunction i g x) y‖^2 ∂(gaussianReal 0 1) := by
    simpa [h_ent_eq] using h_lsi'
  have h_integral_eq :
      ∫ y, ‖fderiv ℝ (sliceFunction i g x) y‖^2 ∂(gaussianReal 0 1) =
        ∫ y, (partialDeriv i g (Function.update x i y))^2 ∂(gaussianReal 0 1) := by
    apply integral_congr_ae
    refine Eventually.of_forall ?_
    intro y
    have h_norm : ‖fderiv ℝ (sliceFunction i g x) y‖ =
        ‖deriv (sliceFunction i g x) y‖ := by
      simpa using
        (norm_deriv_eq_norm_fderiv (f := sliceFunction i g x) (x := y)).symm
    calc
      ‖fderiv ℝ (sliceFunction i g x) y‖^2
          = ‖deriv (sliceFunction i g x) y‖^2 := by
              simp [h_norm]
      _ = (partialDeriv i g (Function.update x i y))^2 := by
          simp [deriv_sliceFunction_eq_partialDeriv (i := i) (g := g) hg_diff x y,
            Real.norm_eq_abs, sq_abs]
  calc
    SubAddEnt.condEntExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
        (fun z => (g z)^2) x
        ≤ 2 * ∫ y, ‖fderiv ℝ (sliceFunction i g x) y‖^2 ∂(gaussianReal 0 1) := h_lsi''
    _ = 2 * ∫ y, (partialDeriv i g (Function.update x i y))^2 ∂(gaussianReal 0 1) := by
        simp [h_integral_eq]

/-! ## Main tensorization bound -/

/-- Sum of expected conditional entropies bounded by `2∫‖∇g‖²`. -/
lemma sum_expected_condEnt_le_grad_norm (n : ℕ) (g : (Fin n → ℝ) → ℝ)
    (hg : MemW12GaussianPi n g (GaussianMeasure.stdGaussianPi n))
    (hg_diff : Differentiable ℝ g)
    (hg_grad_cont : ∀ i, Continuous (fun x => partialDeriv i g x))
    (hg_log_int : Integrable (fun x => (g x)^2 * log ((g x)^2)) (GaussianMeasure.stdGaussianPi n)) :
    ∑ i : Fin n,
        ∫ x, SubAddEnt.condEntExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
          (fun z => (g z)^2) x ∂(GaussianMeasure.stdGaussianPi n) ≤
      2 * ∫ x, gradNormSq n g x ∂(GaussianMeasure.stdGaussianPi n) := by
  classical
  have hg_L2 : Integrable (fun z => (g z)^2) (GaussianMeasure.stdGaussianPi n) :=
    (hg.1).integrable_sq
  have hf_meas : Measurable (fun x => (g x)^2) := by
    have h_meas : Measurable g := hg_diff.continuous.measurable
    simpa [pow_two] using h_meas.mul h_meas
  have hf_nn : 0 ≤ᵐ[GaussianMeasure.stdGaussianPi n] (fun x => (g x)^2) :=
    Eventually.of_forall (fun x => sq_nonneg (g x))
  have hEf_log_int :
      ∀ i : Fin n,
        Integrable (fun x =>
          condExpExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
            (fun z => (g z)^2) x *
          log (condExpExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
            (fun z => (g z)^2) x)) (GaussianMeasure.stdGaussianPi n) := by
    intro i
    simpa [GaussianMeasure.stdGaussianPi] using
      (SubAddEnt.condExpExceptCoord_mul_log_integrable (μs := fun _ : Fin n => gaussianReal 0 1)
        i (fun z => (g z)^2) hf_meas hf_nn hg_L2 hg_log_int)
  have h_condEnt_int :
      ∀ i : Fin n,
        Integrable (SubAddEnt.condEntExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
          (fun z => (g z)^2)) (GaussianMeasure.stdGaussianPi n) := by
    intro i
    apply SubAddEnt.condEntExceptCoord_integrable' (μs := fun _ : Fin n => gaussianReal 0 1)
    · simpa [GaussianMeasure.stdGaussianPi] using hg_log_int
    · exact hEf_log_int i
  have h_slice_ae :
      ∀ i : Fin n,
        ∀ᵐ x ∂(GaussianMeasure.stdGaussianPi n),
          GaussianSobolevReal.MemW12GaussianReal (sliceFunction i g x) (gaussianReal 0 1) :=
    fun i => slice_memW12_ae (i := i) (g := g) hg hg_diff
  have h_term_bound :
      ∀ i : Fin n,
        ∫ x, SubAddEnt.condEntExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
          (fun z => (g z)^2) x ∂(GaussianMeasure.stdGaussianPi n) ≤
          2 * ∫ x, (∫ y, (partialDeriv i g (Function.update x i y))^2 ∂(gaussianReal 0 1))
                ∂(GaussianMeasure.stdGaussianPi n) := by
    intro i
    have h_ae :
        ∀ᵐ x ∂(GaussianMeasure.stdGaussianPi n),
          SubAddEnt.condEntExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
              (fun z => (g z)^2) x ≤
            2 * ∫ y, (partialDeriv i g (Function.update x i y))^2 ∂(gaussianReal 0 1) := by
      filter_upwards [h_slice_ae i] with x hx
      exact condEnt_sq_le_partial_deriv_sq i g hg_diff hg_grad_cont x hx
    -- Integrability of the right-hand side
    haveI : SigmaFinite (GaussianMeasure.stdGaussianPi n) :=
      inferInstance
    haveI : SigmaFinite (gaussianReal 0 1) := inferInstance
    have h_update_mp :
        MeasurePreserving (fun p : (Fin n → ℝ) × ℝ => Function.update p.1 i p.2)
          ((GaussianMeasure.stdGaussianPi n).prod (gaussianReal 0 1))
          (GaussianMeasure.stdGaussianPi n) := by
      constructor
      · exact measurable_update' (a := i)
      · have h_map : Measurable (fun q : ℝ × (Fin n → ℝ) => Function.update q.2 i q.1) :=
          (measurable_update' (a := i)).comp measurable_swap
        calc
          Measure.map (fun p : (Fin n → ℝ) × ℝ => Function.update p.1 i p.2)
              ((GaussianMeasure.stdGaussianPi n).prod (gaussianReal 0 1))
              = Measure.map (fun q : ℝ × (Fin n → ℝ) => Function.update q.2 i q.1)
                  (Measure.map Prod.swap ((GaussianMeasure.stdGaussianPi n).prod (gaussianReal 0 1))) := by
                -- update ∘ swap
                rw [Measure.map_map h_map measurable_swap]
                rfl
          _ = Measure.map (fun q : ℝ × (Fin n → ℝ) => Function.update q.2 i q.1)
                ((gaussianReal 0 1).prod (GaussianMeasure.stdGaussianPi n)) := by
                rw [Measure.prod_swap]
          _ = GaussianMeasure.stdGaussianPi n := by
                simpa [GaussianMeasure.stdGaussianPi] using
                  (map_update_prod_pi (μs := fun _ : Fin n => gaussianReal 0 1) (i := i))
    have h_int_prod :
        Integrable (fun p : (Fin n → ℝ) × ℝ =>
          (partialDeriv i g (Function.update p.1 i p.2))^2)
          ((GaussianMeasure.stdGaussianPi n).prod (gaussianReal 0 1)) := by
      have h_int : Integrable (fun z => (partialDeriv i g z)^2) (GaussianMeasure.stdGaussianPi n) :=
        (hg.2 i).integrable_sq
      exact h_update_mp.integrable_comp h_int.aestronglyMeasurable |>.mpr h_int
    have h_right_int :
        Integrable (fun x =>
          ∫ y, (partialDeriv i g (Function.update x i y))^2 ∂(gaussianReal 0 1))
          (GaussianMeasure.stdGaussianPi n) := by
      simpa using
        (Integrable.integral_prod_left (μ := GaussianMeasure.stdGaussianPi n)
          (ν := gaussianReal 0 1)
          (f := fun p : (Fin n → ℝ) × ℝ =>
            (partialDeriv i g (Function.update p.1 i p.2))^2) h_int_prod)
    have h_left_int := h_condEnt_int i
    have h_le := integral_mono_ae h_left_int (h_right_int.const_mul 2) h_ae
    -- simplify constant outside integral
    simpa [integral_const_mul] using h_le
  -- Use Fubini to rewrite the RHS integrals
  have h_fubini :
      ∀ i : Fin n,
        ∫ x, (∫ y, (partialDeriv i g (Function.update x i y))^2 ∂(gaussianReal 0 1))
            ∂(GaussianMeasure.stdGaussianPi n) =
          ∫ z, (partialDeriv i g z)^2 ∂(GaussianMeasure.stdGaussianPi n) := by
    intro i
    have h_int : Integrable (fun z => (partialDeriv i g z)^2) (GaussianMeasure.stdGaussianPi n) :=
      (hg.2 i).integrable_sq
    haveI : SigmaFinite (GaussianMeasure.stdGaussianPi n) :=
      inferInstance
    haveI : SigmaFinite (gaussianReal 0 1) := inferInstance
    have h_int_prod :
        Integrable (fun p : (Fin n → ℝ) × ℝ =>
          (partialDeriv i g (Function.update p.1 i p.2))^2)
          ((GaussianMeasure.stdGaussianPi n).prod (gaussianReal 0 1)) := by
      -- reuse the measure-preserving argument
      have h_update_mp :
          MeasurePreserving (fun p : (Fin n → ℝ) × ℝ => Function.update p.1 i p.2)
            ((GaussianMeasure.stdGaussianPi n).prod (gaussianReal 0 1))
            (GaussianMeasure.stdGaussianPi n) := by
        constructor
        · exact measurable_update' (a := i)
        · have h_map : Measurable (fun q : ℝ × (Fin n → ℝ) => Function.update q.2 i q.1) :=
            (measurable_update' (a := i)).comp measurable_swap
          calc
            Measure.map (fun p : (Fin n → ℝ) × ℝ => Function.update p.1 i p.2)
                ((GaussianMeasure.stdGaussianPi n).prod (gaussianReal 0 1))
                = Measure.map (fun q : ℝ × (Fin n → ℝ) => Function.update q.2 i q.1)
                    (Measure.map Prod.swap ((GaussianMeasure.stdGaussianPi n).prod (gaussianReal 0 1))) := by
                  rw [Measure.map_map h_map measurable_swap]
                  rfl
            _ = Measure.map (fun q : ℝ × (Fin n → ℝ) => Function.update q.2 i q.1)
                  ((gaussianReal 0 1).prod (GaussianMeasure.stdGaussianPi n)) := by
                  rw [Measure.prod_swap]
            _ = GaussianMeasure.stdGaussianPi n := by
                  simpa [GaussianMeasure.stdGaussianPi] using
                    (map_update_prod_pi (μs := fun _ : Fin n => gaussianReal 0 1) (i := i))
      exact h_update_mp.integrable_comp h_int.aestronglyMeasurable |>.mpr h_int
    have h_swap :=
      MeasureTheory.integral_integral_swap
        (μ := GaussianMeasure.stdGaussianPi n) (ν := gaussianReal 0 1)
        (f := fun x y => (partialDeriv i g (Function.update x i y))^2) h_int_prod
    calc
      ∫ x, (∫ y, (partialDeriv i g (Function.update x i y))^2 ∂(gaussianReal 0 1))
          ∂(GaussianMeasure.stdGaussianPi n)
          = ∫ y, (∫ x, (partialDeriv i g (Function.update x i y))^2
                ∂(GaussianMeasure.stdGaussianPi n)) ∂(gaussianReal 0 1) := h_swap
      _ = ∫ z, (partialDeriv i g z)^2 ∂(GaussianMeasure.stdGaussianPi n) := by
        simpa [GaussianMeasure.stdGaussianPi] using
          (integral_update_eq_integral (μs := fun _ : Fin n => gaussianReal 0 1)
            (i := i) (f := fun z => (partialDeriv i g z)^2) h_int)
  have h_sum_bound :
      ∑ i : Fin n,
        ∫ x, SubAddEnt.condEntExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
          (fun z => (g z)^2) x ∂(GaussianMeasure.stdGaussianPi n) ≤
        2 * ∑ i : Fin n, ∫ z, (partialDeriv i g z)^2 ∂(GaussianMeasure.stdGaussianPi n) := by
    have h_each :
        ∀ i : Fin n,
          ∫ x, SubAddEnt.condEntExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
            (fun z => (g z)^2) x ∂(GaussianMeasure.stdGaussianPi n) ≤
            2 * ∫ z, (partialDeriv i g z)^2 ∂(GaussianMeasure.stdGaussianPi n) := by
      intro i
      have h := h_term_bound i
      -- rewrite with Fubini result
      simpa [h_fubini i] using h
    -- sum over i
    have h_sum' :
        ∑ i : Fin n,
          ∫ x, SubAddEnt.condEntExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
            (fun z => (g z)^2) x ∂(GaussianMeasure.stdGaussianPi n)
            ≤
          ∑ i : Fin n, 2 * ∫ z, (partialDeriv i g z)^2 ∂(GaussianMeasure.stdGaussianPi n) := by
      exact Finset.sum_le_sum (fun i _ => h_each i)
    -- factor out the constant 2
    have h_sum'' :
        ∑ i ∈ Finset.univ, 2 * ∫ z, (partialDeriv i g z)^2 ∂(GaussianMeasure.stdGaussianPi n) =
          2 * ∑ i ∈ Finset.univ, ∫ z, (partialDeriv i g z)^2 ∂(GaussianMeasure.stdGaussianPi n) := by
      simpa using
        (Finset.mul_sum (s := Finset.univ)
          (f := fun i => ∫ z, (partialDeriv i g z)^2 ∂(GaussianMeasure.stdGaussianPi n))
          (a := (2 : ℝ))).symm
    have h_sum''' :
        ∑ i ∈ Finset.univ,
          ∫ x, SubAddEnt.condEntExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
            (fun z => (g z)^2) x ∂(GaussianMeasure.stdGaussianPi n) ≤
          2 * ∑ i ∈ Finset.univ, ∫ z, (partialDeriv i g z)^2 ∂(GaussianMeasure.stdGaussianPi n) := by
      simpa [h_sum''] using h_sum'
    convert h_sum''' using 1
  -- convert sum of integrals to integral of sum
  have h_sum_integral :
      ∑ i : Fin n, ∫ z, (partialDeriv i g z)^2 ∂(GaussianMeasure.stdGaussianPi n) =
        ∫ z, ∑ i : Fin n, (partialDeriv i g z)^2 ∂(GaussianMeasure.stdGaussianPi n) := by
    have h_int :
        ∀ i : Fin n, Integrable (fun z => (partialDeriv i g z)^2)
          (GaussianMeasure.stdGaussianPi n) := fun i => (hg.2 i).integrable_sq
    have h_sum :=
      (integral_finset_sum (μ := GaussianMeasure.stdGaussianPi n)
        (s := Finset.univ) (f := fun i z => (partialDeriv i g z)^2)
        (fun i _ => h_int i))
    convert h_sum.symm using 1
  calc
    ∑ i : Fin n,
        ∫ x, SubAddEnt.condEntExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
          (fun z => (g z)^2) x ∂(GaussianMeasure.stdGaussianPi n)
        ≤ 2 * ∑ i : Fin n, ∫ z, (partialDeriv i g z)^2 ∂(GaussianMeasure.stdGaussianPi n) :=
      h_sum_bound
    _ = 2 * ∫ z, gradNormSq n g z ∂(GaussianMeasure.stdGaussianPi n) := by
      simp [h_sum_integral, gradNormSq]

/-- Dimension-free Gaussian log-Sobolev inequality: `Ent_μ(g²) ≤ 2∫‖∇g‖² dμ`. -/
theorem gaussian_logSobolev_W12_pi {n : ℕ} {g : (Fin n → ℝ) → ℝ}
    (hg : MemW12GaussianPi n g (GaussianMeasure.stdGaussianPi n))
    (hg_diff : Differentiable ℝ g)
    (hg_grad_cont : ∀ i, Continuous (fun x => partialDeriv i g x))
    (hg_log_int :
      Integrable (fun x => (g x)^2 * log ((g x)^2)) (GaussianMeasure.stdGaussianPi n)) :
    LogSobolev.entropy (GaussianMeasure.stdGaussianPi n) (fun x => (g x)^2) ≤
      2 * ∫ x, gradNormSq n g x ∂(GaussianMeasure.stdGaussianPi n) := by
  have hf_meas : Measurable (fun x => (g x)^2) := by
    have h_meas : Measurable g := hg_diff.continuous.measurable
    simpa [pow_two] using h_meas.mul h_meas
  have hf_nn : 0 ≤ᵐ[GaussianMeasure.stdGaussianPi n] (fun x => (g x)^2) :=
    Eventually.of_forall (fun x => sq_nonneg (g x))
  have hf_int : Integrable (fun x => (g x)^2) (GaussianMeasure.stdGaussianPi n) :=
    (hg.1).integrable_sq
  have h_subadd :=
    SubAddEnt.entropy_subadditive (μs := fun _ : Fin n => gaussianReal 0 1)
      (f := fun x => (g x)^2) hf_meas hf_nn hf_int (by
        simpa [GaussianMeasure.stdGaussianPi] using hg_log_int)
  have h_bound :=
    sum_expected_condEnt_le_grad_norm n g hg hg_diff hg_grad_cont hg_log_int
  calc
    LogSobolev.entropy (GaussianMeasure.stdGaussianPi n) (fun x => (g x)^2)
        ≤ ∑ i : Fin n,
            ∫ x, SubAddEnt.condEntExceptCoord (μs := fun _ : Fin n => gaussianReal 0 1) i
              (fun z => (g z)^2) x ∂(GaussianMeasure.stdGaussianPi n) := by
          simpa [GaussianMeasure.stdGaussianPi] using h_subadd
    _ ≤ 2 * ∫ x, gradNormSq n g x ∂(GaussianMeasure.stdGaussianPi n) := h_bound

end GaussianLSI

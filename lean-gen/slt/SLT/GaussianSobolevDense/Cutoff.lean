/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.GaussianSobolevDense.Defs

/-!
# Cutoff Lemmas for Gaussian Sobolev Density

This file proves that smooth cutoff at infinity preserves convergence in W^{1,2}(γ).

## Main Results

* `cutoff_L2_convergence` - ‖f - f·χ_R‖_{L²(γ)} → 0 as R → ∞
* `cutoff_gradient_error_bound` - ‖(1-χ_R)∇f‖_{L²(γ)} → 0 as R → ∞
* `cutoff_gradient_extra_term` - ‖f·∇χ_R‖_{L²(γ)} → 0 as R → ∞
* `tendsto_cutoff_W12` - f^(R) → f in W^{1,2}(γ) as R → ∞

-/

open MeasureTheory ProbabilityTheory Filter Topology GaussianMeasure
open scoped ENNReal NNReal Topology

namespace GaussianSobolev

variable {n : ℕ}

/-! ### Helper Lemmas for Cutoff Derivative -/

/-- The derivative of smoothCutoff is bounded.
    This follows from smoothCutoff being smooth with compact support. -/
lemma smoothCutoff_deriv_bounded :
    ∃ C : ℝ, 0 < C ∧ ∀ x : ℝ, ‖deriv smoothCutoff x‖ ≤ C := by
  -- smoothCutoff is smooth with compact support, so its derivative is bounded
  have hsmooth := smoothCutoff_contDiff
  -- The derivative is continuous (smoothCutoff is C^∞)
  have hcont : Continuous (deriv smoothCutoff) :=
    hsmooth.continuous_deriv (WithTop.coe_le_coe.mpr (le_top : (1 : ℕ∞) ≤ ⊤))
  -- The derivative has compact support (support ⊆ [-2, 2] since smoothCutoff is constant outside)
  have hsupp : HasCompactSupport (deriv smoothCutoff) := by
    apply HasCompactSupport.of_support_subset_isCompact (K := Set.Icc (-2) 2) isCompact_Icc
    intro x hx
    rw [Function.mem_support] at hx
    -- x must be in [-2, 2], otherwise deriv = 0
    simp only [Set.mem_Icc]
    constructor <;> by_contra habs <;> push_neg at habs
    · -- Case: x < -2, show deriv = 0 (contradiction with hx)
      have heq : ∀ᶠ y in nhds x, smoothCutoff y = 0 := by
        have hradius : 0 < -x - 2 := by linarith
        refine Metric.eventually_nhds_iff.mpr ⟨-x - 2, hradius, ?_⟩
        intro y hy
        apply smoothCutoff_eq_zero_of_ge
        rw [Real.dist_eq] at hy
        -- x < -2, |y - x| < -x - 2 implies y < -2, hence |y| > 2
        have habs := abs_lt.mp hy
        linarith [abs_of_neg (show y < 0 by linarith)]
      exact hx (HasDerivAt.deriv ((hasDerivAt_const x (0 : ℝ)).congr_of_eventuallyEq heq))
    · -- Case: x > 2, show deriv = 0 (contradiction with hx)
      have heq : ∀ᶠ y in nhds x, smoothCutoff y = 0 := by
        have hradius : 0 < x - 2 := by linarith
        refine Metric.eventually_nhds_iff.mpr ⟨x - 2, hradius, ?_⟩
        intro y hy
        apply smoothCutoff_eq_zero_of_ge
        rw [Real.dist_eq] at hy
        -- x > 2, |y - x| < x - 2 implies y > 2, hence |y| > 2
        have habs := abs_lt.mp hy
        linarith [abs_of_pos (show y > 0 by linarith)]
      exact hx (HasDerivAt.deriv ((hasDerivAt_const x (0 : ℝ)).congr_of_eventuallyEq heq))
  -- Continuous function with compact support is bounded
  have ⟨C, hC⟩ := hsupp.exists_bound_of_continuous hcont
  use max C 1
  constructor
  · exact lt_max_of_lt_right one_pos
  · intro x
    calc ‖deriv smoothCutoff x‖ ≤ C := hC x
      _ ≤ max C 1 := le_max_left C 1

/-- The norm function scaled by 1/R has fderiv with operator norm at most 1/R.
    Proof: ‖·‖/R is (1/R)-Lipschitz, so its fderiv has operator norm ≤ 1/R. -/
lemma fderiv_norm_div_bound {R : ℝ} (hR : 0 < R) (x : E n) :
    ‖fderiv ℝ (fun y : E n => ‖y‖ / R) x‖ ≤ 1 / R := by
  -- The function ‖·‖/R is (1/R)-Lipschitz since ‖·‖ is 1-Lipschitz
  -- By norm_fderiv_le_of_lipschitz, the fderiv has norm ≤ 1/R
  have hLip : LipschitzWith ⟨1 / R, by positivity⟩ (fun y : E n => ‖y‖ / R) :=
    LipschitzWith.of_dist_le_mul fun y z => by
      have h1 : |‖y‖ - ‖z‖| ≤ ‖y - z‖ := abs_norm_sub_norm_le y z
      simp only [NNReal.coe_mk, Real.dist_eq]
      have h2 : ‖y‖ / R - ‖z‖ / R = (‖y‖ - ‖z‖) / R := by ring
      rw [h2, abs_div, abs_of_pos hR]
      calc |‖y‖ - ‖z‖| / R ≤ ‖y - z‖ / R := div_le_div_of_nonneg_right h1 (le_of_lt hR)
        _ = 1 / R * ‖y - z‖ := by ring
        _ = 1 / R * dist y z := by rw [dist_eq_norm]
  exact norm_fderiv_le_of_lipschitz ℝ hLip

/-- The gradient of smoothCutoffR has norm bounded by C/R.
    Proof sketch: χ_R(x) = χ(‖x‖/R), so by chain rule
    ∇χ_R(x) = χ'(‖x‖/R) · ∇(‖·‖/R)(x), and ‖∇(‖·‖/R)‖ ≤ 1/R. -/
lemma smoothCutoffR_fderiv_bound {R : ℝ} (hR : 0 < R) :
    ∃ C : ℝ, 0 < C ∧ ∀ x : E n, ‖fderiv ℝ (smoothCutoffR R) x‖ ≤ C / R := by
  -- Get the bound C from smoothCutoff_deriv_bounded
  obtain ⟨C, hC_pos, hC_bound⟩ := smoothCutoff_deriv_bounded
  use C
  constructor
  · exact hC_pos
  · intro x
    -- Case split: either ‖x‖ < R (locally constant) or ‖x‖ ≥ R (use chain rule)
    by_cases hxR : ‖x‖ < R
    · -- Case: ‖x‖ < R, smoothCutoffR R is locally constant = 1 near x
      have h_eq : ∀ᶠ y in nhds x, smoothCutoffR R y = 1 := by
        have hradius : 0 < R - ‖x‖ := by linarith
        refine Metric.eventually_nhds_iff.mpr ⟨R - ‖x‖, hradius, ?_⟩
        intro y hy
        apply smoothCutoffR_eq_one_of_norm_le hR
        rw [dist_eq_norm] at hy
        have hcalc : ‖y‖ < R := calc ‖y‖ ≤ ‖x‖ + ‖y - x‖ := norm_le_insert' y x
          _ < ‖x‖ + (R - ‖x‖) := add_lt_add_right hy ‖x‖
          _ = R := by ring
        exact le_of_lt hcalc
      have hfderiv_eq : fderiv ℝ (smoothCutoffR R) x = 0 := by
        have hconst : fderiv ℝ (fun _ : E n => (1 : ℝ)) x = 0 := by simp
        exact Filter.EventuallyEq.fderiv_eq (h_eq.mono fun y hy => hy) |>.trans hconst
      rw [hfderiv_eq, norm_zero]
      exact div_nonneg (le_of_lt hC_pos) (le_of_lt hR)
    · -- Case: ‖x‖ ≥ R, use chain rule
      push_neg at hxR
      -- smoothCutoffR R x = smoothCutoff (‖x‖ / R)
      -- By chain rule: fderiv = (deriv smoothCutoff at ‖x‖/R) ∘ fderiv(‖·‖/R)
      have hx_ne : x ≠ 0 := by
        intro habs
        rw [habs, norm_zero] at hxR
        linarith
      -- Differentiability of components
      have h_norm_diff : DifferentiableAt ℝ (fun y : E n => ‖y‖ / R) x := by
        have h1 : DifferentiableAt ℝ (fun y : E n => ‖y‖) x :=
          (contDiffAt_norm ℝ hx_ne).differentiableAt WithTop.top_ne_zero
        have h2 : DifferentiableAt ℝ (fun y : E n => ‖y‖ * R⁻¹) x := h1.mul_const R⁻¹
        convert h2 using 1
      have h_cutoff_diff : DifferentiableAt ℝ smoothCutoff (‖x‖ / R) :=
        smoothCutoff_contDiff.differentiable (WithTop.coe_ne_zero.mpr WithTop.top_ne_zero) (‖x‖ / R)
      -- Chain rule
      have hchain : fderiv ℝ (smoothCutoffR R) x =
          fderiv ℝ smoothCutoff (‖x‖ / R) ∘L fderiv ℝ (fun y : E n => ‖y‖ / R) x := by
        unfold smoothCutoffR
        exact fderiv_comp x h_cutoff_diff h_norm_diff
      rw [hchain]
      -- Bound the composition
      calc ‖fderiv ℝ smoothCutoff (‖x‖ / R) ∘L fderiv ℝ (fun y : E n => ‖y‖ / R) x‖
          ≤ ‖fderiv ℝ smoothCutoff (‖x‖ / R)‖ * ‖fderiv ℝ (fun y : E n => ‖y‖ / R) x‖ :=
            ContinuousLinearMap.opNorm_comp_le _ _
        _ ≤ C * (1 / R) := by
            apply mul_le_mul
            · -- ‖fderiv ℝ smoothCutoff (‖x‖ / R)‖ ≤ C
              -- fderiv of scalar function = deriv times identity
              have heq : fderiv ℝ smoothCutoff (‖x‖ / R) = (deriv smoothCutoff (‖x‖ / R)) • (1 : ℝ →L[ℝ] ℝ) := by
                ext
                simp only [ContinuousLinearMap.smul_apply, ContinuousLinearMap.one_apply, smul_eq_mul]
                rw [fderiv_eq_smul_deriv, smul_eq_mul, mul_comm]
              rw [heq, norm_smul, norm_one, mul_one, Real.norm_eq_abs]
              calc |deriv smoothCutoff (‖x‖ / R)| = ‖deriv smoothCutoff (‖x‖ / R)‖ := (Real.norm_eq_abs _).symm
                _ ≤ C := hC_bound (‖x‖ / R)
            · exact fderiv_norm_div_bound hR x
            · exact norm_nonneg _
            · exact le_of_lt hC_pos
        _ = C / R := by ring

/-! ### L² Convergence Lemmas -/

/-- The cutoff of f converges to f in L²(γ) as R → ∞.
    This follows from dominated convergence: |f - f·χ_R|² ≤ |f|² and
    (1-χ_R)(x) → 0 for all x as R → ∞. -/
lemma cutoff_L2_convergence (f : E n → ℝ) (hf : MemLp f 2 (stdGaussianE n)) :
    Filter.Tendsto (fun R => eLpNorm (f - f * smoothCutoffR R) 2 (stdGaussianE n))
      Filter.atTop (nhds 0) := by
  -- Rewrite: f - f·χ_R = f·(1 - χ_R)
  have heq : ∀ R : ℝ, ∀ x : E n, (f - f * (smoothCutoffR (n := n) R)) x = f x * (1 - smoothCutoffR R x) := by
    intro R x
    simp only [Pi.sub_apply, Pi.mul_apply]
    ring
  -- It suffices to show eLpNorm of f·(1-χ_R) → 0
  simp_rw [funext (heq _)]
  -- Key fact: |1 - χ_R(x)| ≤ 1
  have h_one_sub_bound : ∀ R, ∀ x : E n, |1 - smoothCutoffR R x| ≤ 1 := by
    intro R x
    have h0 : 0 ≤ smoothCutoffR R x := smoothCutoffR_nonneg R x
    have h1 : smoothCutoffR R x ≤ 1 := smoothCutoffR_le_one R x
    rw [abs_le]
    constructor
    · linarith
    · linarith
  -- Pointwise convergence: (1 - χ_R)(x) → 0 for all x
  have h_ptwise : ∀ x : E n, Filter.Tendsto (fun R => 1 - smoothCutoffR (n := n) R x) Filter.atTop (nhds 0) := by
    intro x
    have htends : Filter.Tendsto (fun R => smoothCutoffR R x) Filter.atTop (nhds 1) :=
      smoothCutoffR_tendsto_one x
    have hsub := Filter.Tendsto.sub (tendsto_const_nhds (x := (1 : ℝ))) htends
    simp only [sub_self] at hsub
    exact hsub

  -- First, show that |f|² is integrable (i.e., ∫⁻ |f|² < ∞)
  have hf_sq_int : ∫⁻ x, (‖f x‖₊ : ℝ≥0∞) ^ (2 : ℝ) ∂(stdGaussianE n) < ⊤ := by
    have hlt := hf.eLpNorm_lt_top
    rw [MeasureTheory.eLpNorm_eq_lintegral_rpow_enorm (by norm_num : (2 : ℝ≥0∞) ≠ 0)
        (by norm_num : (2 : ℝ≥0∞) ≠ ⊤)] at hlt
    simp only [ENNReal.toReal_ofNat, one_div, enorm_eq_nnnorm] at hlt
    by_contra habs
    push_neg at habs
    rw [eq_top_iff.mpr habs, ENNReal.top_rpow_of_pos (by norm_num : (0 : ℝ) < 2⁻¹)] at hlt
    exact (lt_irrefl ⊤) hlt

  -- Apply dominated convergence via eLpNorm characterization
  -- Define the integrand functions
  let F : ℝ → E n → ℝ≥0∞ := fun R x => (‖f x * (1 - smoothCutoffR R x)‖₊ : ℝ≥0∞) ^ (2 : ℝ)
  let bound : E n → ℝ≥0∞ := fun x => (‖f x‖₊ : ℝ≥0∞) ^ (2 : ℝ)

  -- Use the strongly measurable representative of f
  let f' := hf.aestronglyMeasurable.mk f
  have hf'_meas : StronglyMeasurable f' := hf.aestronglyMeasurable.stronglyMeasurable_mk
  have hf'_eq : f =ᵐ[stdGaussianE n] f' := hf.aestronglyMeasurable.ae_eq_mk

  -- Define F' using the measurable representative
  let F' : ℝ → E n → ℝ≥0∞ := fun R x => (‖f' x * (1 - smoothCutoffR R x)‖₊ : ℝ≥0∞) ^ (2 : ℝ)

  -- Measurability of F' R
  have hF'_meas : ∀ R, Measurable (F' R) := by
    intro R
    apply Measurable.pow_const
    apply Measurable.coe_nnreal_ennreal
    apply Measurable.nnnorm
    apply hf'_meas.measurable.mul
    apply Measurable.sub measurable_const
    -- smoothCutoffR R is continuous for any R (composition of continuous functions)
    have hχR_cont : Continuous (smoothCutoffR (n := n) R) := by
      unfold smoothCutoffR
      exact smoothCutoff_contDiff.continuous.comp (continuous_norm.div_const R)
    exact hχR_cont.measurable

  -- F = F' ae
  have hFF'_ae : ∀ R, F R =ᵐ[stdGaussianE n] F' R := by
    intro R
    filter_upwards [hf'_eq] with x hx
    simp only [F, F']
    rw [hx]

  -- lintegral F R = lintegral F' R (by ae equality)
  have hlintegral_eq : ∀ R, ∫⁻ x, F R x ∂(stdGaussianE n) = ∫⁻ x, F' R x ∂(stdGaussianE n) := by
    intro R
    exact MeasureTheory.lintegral_congr_ae (hFF'_ae R)

  -- bound' using f' instead of f (for DCT)
  let bound' : E n → ℝ≥0∞ := fun x => (‖f' x‖₊ : ℝ≥0∞) ^ (2 : ℝ)

  -- bound = bound' ae
  have hbound_ae : bound =ᵐ[stdGaussianE n] bound' := by
    filter_upwards [hf'_eq] with x hx
    simp only [bound, bound']
    rw [hx]

  -- Domination: F' R x ≤ bound' x (pointwise for all x)
  have hF'_le : ∀ R, ∀ x, F' R x ≤ bound' x := by
    intro R x
    apply ENNReal.rpow_le_rpow _ (by norm_num : (0 : ℝ) ≤ 2)
    simp only [ENNReal.coe_le_coe]
    have h1sub := h_one_sub_bound R x
    rw [← NNReal.coe_le_coe, coe_nnnorm, coe_nnnorm, Real.norm_eq_abs, Real.norm_eq_abs]
    calc |f' x * (1 - smoothCutoffR R x)| = |f' x| * |1 - smoothCutoffR R x| := abs_mul _ _
      _ ≤ |f' x| * 1 := by apply mul_le_mul_of_nonneg_left h1sub (abs_nonneg _)
      _ = |f' x| := mul_one _

  -- Bound' is integrable
  have hbound'_int : ∫⁻ x, bound' x ∂(stdGaussianE n) ≠ ⊤ := by
    rw [← MeasureTheory.lintegral_congr_ae hbound_ae]
    exact ne_top_of_lt hf_sq_int

  -- Pointwise convergence: F' R x → 0
  have hF'_tendsto : ∀ x, Filter.Tendsto (fun R => F' R x) Filter.atTop (nhds 0) := by
    intro x
    simp only [F']
    -- f' x * (1 - smoothCutoffR R x) → 0 because (1 - smoothCutoffR R x) → 0
    have h1 : Filter.Tendsto (fun R => f' x * (1 - smoothCutoffR R x)) Filter.atTop (nhds 0) := by
      rw [← mul_zero (f' x)]
      exact Filter.Tendsto.const_mul (f' x) (h_ptwise x)
    have h2 : Filter.Tendsto (fun R => ‖f' x * (1 - smoothCutoffR R x)‖₊) Filter.atTop (nhds (0 : ℝ≥0)) := by
      rw [← @nnnorm_zero ℝ _]
      exact Filter.Tendsto.nnnorm h1
    have h3 : Filter.Tendsto (fun R => (‖f' x * (1 - smoothCutoffR R x)‖₊ : ℝ≥0∞)) Filter.atTop (nhds 0) := by
      exact ENNReal.tendsto_coe.mpr h2
    -- (‖·‖₊ : ℝ≥0∞) → 0 implies (‖·‖₊)^2 → 0
    have h0_pow : (0 : ℝ≥0∞) ^ (2 : ℝ) = 0 := ENNReal.zero_rpow_of_pos (by norm_num : (0 : ℝ) < 2)
    rw [← h0_pow]
    exact (ENNReal.continuous_rpow_const.tendsto 0).comp h3

  -- Apply DCT to F' to get lintegral F' → 0
  have hlintegral'_tendsto : Filter.Tendsto (fun R => ∫⁻ x, F' R x ∂(stdGaussianE n))
      Filter.atTop (nhds 0) := by
    have hDCT := MeasureTheory.tendsto_lintegral_filter_of_dominated_convergence bound'
        (Filter.Eventually.of_forall hF'_meas)
        (Filter.Eventually.of_forall fun R => Filter.Eventually.of_forall (hF'_le R))
        hbound'_int
        (Filter.Eventually.of_forall hF'_tendsto)
    simp only [MeasureTheory.lintegral_zero] at hDCT
    exact hDCT

  -- lintegral F → 0 (via lintegral F = lintegral F')
  have hlintegral_tendsto : Filter.Tendsto (fun R => ∫⁻ x, F R x ∂(stdGaussianE n))
      Filter.atTop (nhds 0) := by
    simp only [hlintegral_eq]
    exact hlintegral'_tendsto

  -- Convert lintegral → 0 to eLpNorm → 0 using eLpNorm = (∫⁻ |·|²)^(1/2)
  -- eLpNorm g 2 μ = (∫⁻ |g|²)^(1/2), so eLpNorm → 0 iff lintegral → 0
  have heLpNorm_eq : ∀ R, eLpNorm (fun x => f x * (1 - smoothCutoffR R x)) 2 (stdGaussianE n) =
      (∫⁻ x, F R x ∂(stdGaussianE n)) ^ (2⁻¹ : ℝ) := by
    intro R
    rw [MeasureTheory.eLpNorm_eq_lintegral_rpow_enorm (by norm_num : (2 : ℝ≥0∞) ≠ 0)
        (by norm_num : (2 : ℝ≥0∞) ≠ ⊤)]
    simp only [ENNReal.toReal_ofNat, one_div, enorm_eq_nnnorm, F]
  simp only [heLpNorm_eq]
  -- rpow (1/2) is continuous, so if lintegral → 0 then lintegral^(1/2) → 0
  have h_rpow_tendsto : Filter.Tendsto (fun R => (∫⁻ x, F R x ∂(stdGaussianE n)) ^ (2⁻¹ : ℝ))
      Filter.atTop (nhds 0) := by
    have h0 : (0 : ℝ≥0∞) ^ (2⁻¹ : ℝ) = 0 := ENNReal.zero_rpow_of_pos (by norm_num : (0 : ℝ) < 2⁻¹)
    have h_cont : Continuous (fun x : ℝ≥0∞ => x ^ (2⁻¹ : ℝ)) := ENNReal.continuous_rpow_const
    rw [← h0]
    exact h_cont.tendsto 0 |>.comp hlintegral_tendsto
  exact h_rpow_tendsto

/-- The product rule for the gradient of f·χ_R at a point. -/
lemma cutoff_product_rule (f : E n → ℝ) (hf : Differentiable ℝ f) (R : ℝ) (hR : 0 < R) (x : E n) :
    fderiv ℝ (f * smoothCutoffR R) x =
      f x • fderiv ℝ (smoothCutoffR R) x + smoothCutoffR R x • fderiv ℝ f x := by
  have hf_at : DifferentiableAt ℝ f x := hf x
  have hχ_at : DifferentiableAt ℝ (smoothCutoffR R) x :=
    (smoothCutoffR_contDiff hR).differentiable (WithTop.coe_ne_zero.mpr WithTop.top_ne_zero) x
  exact fderiv_mul hf_at hχ_at

/-- The gradient error term from (1-χ_R)·∇f converges to 0 as R → ∞. -/
lemma cutoff_gradient_error_bound (f : E n → ℝ)
    (hf_grad : MemLp (fun x => fderiv ℝ f x) 2 (stdGaussianE n)) :
    Filter.Tendsto (fun R =>
        eLpNorm (fun x => (1 - smoothCutoffR R x) • fderiv ℝ f x) 2 (stdGaussianE n))
      Filter.atTop (nhds 0) := by

  -- Key fact: |1 - χ_R(x)| ≤ 1
  have h_one_sub_bound : ∀ R, ∀ x : E n, |1 - smoothCutoffR R x| ≤ 1 := by
    intro R x
    have h0 : 0 ≤ smoothCutoffR R x := smoothCutoffR_nonneg R x
    have h1 : smoothCutoffR R x ≤ 1 := smoothCutoffR_le_one R x
    rw [abs_le]
    constructor <;> linarith

  -- Pointwise convergence: (1 - χ_R)(x) → 0 for all x
  have h_ptwise : ∀ x : E n, Filter.Tendsto (fun R => 1 - smoothCutoffR (n := n) R x) Filter.atTop (nhds 0) := by
    intro x
    have htends : Filter.Tendsto (fun R => smoothCutoffR R x) Filter.atTop (nhds 1) :=
      smoothCutoffR_tendsto_one x
    have hsub := Filter.Tendsto.sub (tendsto_const_nhds (x := (1 : ℝ))) htends
    simp only [sub_self] at hsub
    exact hsub

  -- Apply dominated convergence (similar structure to cutoff_L2_convergence)

  -- Define integrand and bound
  let g := fun x => fderiv ℝ f x
  let F : ℝ → E n → ℝ≥0∞ := fun R x => (‖(1 - smoothCutoffR R x) • g x‖₊ : ℝ≥0∞) ^ (2 : ℝ)
  let bound : E n → ℝ≥0∞ := fun x => (‖g x‖₊ : ℝ≥0∞) ^ (2 : ℝ)

  -- Use measurable representative of g
  let g' := hf_grad.aestronglyMeasurable.mk g
  have hg'_meas : StronglyMeasurable g' := hf_grad.aestronglyMeasurable.stronglyMeasurable_mk
  have hg'_eq : g =ᵐ[stdGaussianE n] g' := hf_grad.aestronglyMeasurable.ae_eq_mk

  let F' : ℝ → E n → ℝ≥0∞ := fun R x => (‖(1 - smoothCutoffR R x) • g' x‖₊ : ℝ≥0∞) ^ (2 : ℝ)
  let bound' : E n → ℝ≥0∞ := fun x => (‖g' x‖₊ : ℝ≥0∞) ^ (2 : ℝ)

  -- F' R is measurable
  have hF'_meas : ∀ R, Measurable (F' R) := by
    intro R
    apply Measurable.pow_const
    apply Measurable.coe_nnreal_ennreal
    apply Measurable.nnnorm
    apply Measurable.smul
    · apply Measurable.sub measurable_const
      have hχR_cont : Continuous (smoothCutoffR (n := n) R) := by
        unfold smoothCutoffR
        exact smoothCutoff_contDiff.continuous.comp (continuous_norm.div_const R)
      exact hχR_cont.measurable
    · exact hg'_meas.measurable

  -- F = F' ae and lintegral equality
  have hFF'_ae : ∀ R, F R =ᵐ[stdGaussianE n] F' R := by
    intro R
    filter_upwards [hg'_eq] with x hx
    show (‖(1 - smoothCutoffR R x) • g x‖₊ : ℝ≥0∞) ^ (2 : ℝ) =
         (‖(1 - smoothCutoffR R x) • g' x‖₊ : ℝ≥0∞) ^ (2 : ℝ)
    rw [hx]

  have hlintegral_eq : ∀ R, ∫⁻ x, F R x ∂(stdGaussianE n) = ∫⁻ x, F' R x ∂(stdGaussianE n) := by
    intro R
    exact MeasureTheory.lintegral_congr_ae (hFF'_ae R)

  -- Bound' is integrable
  have hbound_ae : bound =ᵐ[stdGaussianE n] bound' := by
    filter_upwards [hg'_eq] with x hx
    show (‖g x‖₊ : ℝ≥0∞) ^ (2 : ℝ) = (‖g' x‖₊ : ℝ≥0∞) ^ (2 : ℝ)
    rw [hx]

  have hg_sq_int : ∫⁻ x, (‖g x‖₊ : ℝ≥0∞) ^ (2 : ℝ) ∂(stdGaussianE n) < ⊤ := by
    have hlt := hf_grad.eLpNorm_lt_top
    rw [MeasureTheory.eLpNorm_eq_lintegral_rpow_enorm (by norm_num : (2 : ℝ≥0∞) ≠ 0)
        (by norm_num : (2 : ℝ≥0∞) ≠ ⊤)] at hlt
    simp only [ENNReal.toReal_ofNat, one_div, enorm_eq_nnnorm, g] at hlt ⊢
    by_contra habs
    push_neg at habs
    rw [eq_top_iff.mpr habs, ENNReal.top_rpow_of_pos (by norm_num : (0 : ℝ) < 2⁻¹)] at hlt
    exact (lt_irrefl ⊤) hlt

  have hbound'_int : ∫⁻ x, bound' x ∂(stdGaussianE n) ≠ ⊤ := by
    rw [← MeasureTheory.lintegral_congr_ae hbound_ae]
    exact ne_top_of_lt hg_sq_int

  -- Domination: F' R x ≤ bound' x
  have hF'_le : ∀ R, ∀ x, F' R x ≤ bound' x := by
    intro R x
    apply ENNReal.rpow_le_rpow _ (by norm_num : (0 : ℝ) ≤ 2)
    simp only [ENNReal.coe_le_coe]
    rw [← NNReal.coe_le_coe, coe_nnnorm, coe_nnnorm]
    rw [norm_smul, Real.norm_eq_abs]
    calc |1 - smoothCutoffR R x| * ‖g' x‖
        ≤ 1 * ‖g' x‖ := by apply mul_le_mul_of_nonneg_right (h_one_sub_bound R x) (norm_nonneg _)
      _ = ‖g' x‖ := one_mul _

  -- Pointwise convergence: F' R x → 0
  have hF'_tendsto : ∀ x, Filter.Tendsto (fun R => F' R x) Filter.atTop (nhds 0) := by
    intro x
    simp only [F']
    have h1 : Filter.Tendsto (fun R => (1 - smoothCutoffR R x) • g' x) Filter.atTop (nhds 0) := by
      rw [← zero_smul ℝ (g' x)]
      exact Filter.Tendsto.smul (h_ptwise x) tendsto_const_nhds
    have h2 : Filter.Tendsto (fun R => ‖(1 - smoothCutoffR R x) • g' x‖₊) Filter.atTop (nhds (0 : ℝ≥0)) := by
      rw [← @nnnorm_zero (E n →L[ℝ] ℝ) _]
      exact Filter.Tendsto.nnnorm h1
    have h3 : Filter.Tendsto (fun R => (‖(1 - smoothCutoffR R x) • g' x‖₊ : ℝ≥0∞)) Filter.atTop (nhds 0) := by
      exact ENNReal.tendsto_coe.mpr h2
    have h0_pow : (0 : ℝ≥0∞) ^ (2 : ℝ) = 0 := ENNReal.zero_rpow_of_pos (by norm_num : (0 : ℝ) < 2)
    rw [← h0_pow]
    exact (ENNReal.continuous_rpow_const.tendsto 0).comp h3

  -- Apply DCT to F' to get lintegral F' → 0
  have hlintegral'_tendsto : Filter.Tendsto (fun R => ∫⁻ x, F' R x ∂(stdGaussianE n))
      Filter.atTop (nhds 0) := by
    have hDCT := MeasureTheory.tendsto_lintegral_filter_of_dominated_convergence bound'
        (Filter.Eventually.of_forall hF'_meas)
        (Filter.Eventually.of_forall fun R => Filter.Eventually.of_forall (hF'_le R))
        hbound'_int
        (Filter.Eventually.of_forall hF'_tendsto)
    simp only [MeasureTheory.lintegral_zero] at hDCT
    exact hDCT

  -- lintegral F → 0 (via lintegral F = lintegral F')
  have hlintegral_tendsto : Filter.Tendsto (fun R => ∫⁻ x, F R x ∂(stdGaussianE n))
      Filter.atTop (nhds 0) := by
    simp only [hlintegral_eq]
    exact hlintegral'_tendsto

  -- Convert lintegral → 0 to eLpNorm → 0
  have heLpNorm_eq : ∀ R, eLpNorm (fun x => (1 - smoothCutoffR R x) • fderiv ℝ f x) 2 (stdGaussianE n) =
      (∫⁻ x, F R x ∂(stdGaussianE n)) ^ (2⁻¹ : ℝ) := by
    intro R
    rw [MeasureTheory.eLpNorm_eq_lintegral_rpow_enorm (by norm_num : (2 : ℝ≥0∞) ≠ 0)
        (by norm_num : (2 : ℝ≥0∞) ≠ ⊤)]
    simp only [ENNReal.toReal_ofNat, one_div, enorm_eq_nnnorm, F, g]
  simp only [heLpNorm_eq]
  have h_rpow_tendsto : Filter.Tendsto (fun R => (∫⁻ x, F R x ∂(stdGaussianE n)) ^ (2⁻¹ : ℝ))
      Filter.atTop (nhds 0) := by
    have h0 : (0 : ℝ≥0∞) ^ (2⁻¹ : ℝ) = 0 := ENNReal.zero_rpow_of_pos (by norm_num : (0 : ℝ) < 2⁻¹)
    have h_cont : Continuous (fun x : ℝ≥0∞ => x ^ (2⁻¹ : ℝ)) := ENNReal.continuous_rpow_const
    rw [← h0]
    exact h_cont.tendsto 0 |>.comp hlintegral_tendsto
  exact h_rpow_tendsto

/-- The extra gradient term f·∇χ_R converges to 0 as R → ∞. -/
lemma cutoff_gradient_extra_term (f : E n → ℝ) (hf : MemLp f 2 (stdGaussianE n)) :
    Filter.Tendsto (fun R =>
        eLpNorm (fun x => f x • fderiv ℝ (smoothCutoffR R) x) 2 (stdGaussianE n))
      Filter.atTop (nhds 0) := by
  -- Use squeeze theorem: 0 ≤ ||f·∇χ_R||_2 ≤ (C/R) ||f||_2 → 0
  -- Get the constant C from smoothCutoff_deriv_bounded (using choose directly)
  let C := smoothCutoff_deriv_bounded.choose
  have hC_pos : 0 < C := smoothCutoff_deriv_bounded.choose_spec.1
  have hC_bound : ∀ x : ℝ, ‖deriv smoothCutoff x‖ ≤ C := smoothCutoff_deriv_bounded.choose_spec.2
  -- For R > 0, derive the bound for smoothCutoffR (inline the key steps from smoothCutoffR_fderiv_bound)
  have hbound : ∀ R : ℝ, 0 < R → ∀ x : E n, ‖fderiv ℝ (smoothCutoffR (n := n) R) x‖ ≤ C / R := by
    intro R hR x
    by_cases hxR : ‖x‖ < R
    · -- Case: ‖x‖ < R, smoothCutoffR R is locally constant = 1 near x
      have h_eq : ∀ᶠ y in nhds x, smoothCutoffR (n := n) R y = 1 := by
        have hradius : 0 < R - ‖x‖ := by linarith
        refine Metric.eventually_nhds_iff.mpr ⟨R - ‖x‖, hradius, ?_⟩
        intro y hy
        apply smoothCutoffR_eq_one_of_norm_le hR
        rw [dist_eq_norm] at hy
        have hcalc : ‖y‖ < R := calc ‖y‖ ≤ ‖x‖ + ‖y - x‖ := norm_le_insert' y x
          _ < ‖x‖ + (R - ‖x‖) := add_lt_add_right hy ‖x‖
          _ = R := by ring
        exact le_of_lt hcalc
      have hfderiv_eq : fderiv ℝ (smoothCutoffR (n := n) R) x = 0 := by
        have hconst : fderiv ℝ (fun _ : E n => (1 : ℝ)) x = 0 := by simp
        exact Filter.EventuallyEq.fderiv_eq (h_eq.mono fun y hy => hy) |>.trans hconst
      rw [hfderiv_eq, norm_zero]
      exact div_nonneg (le_of_lt hC_pos) (le_of_lt hR)
    · -- Case: ‖x‖ ≥ R, use chain rule
      push_neg at hxR
      have hx_ne : x ≠ 0 := by intro habs; rw [habs, norm_zero] at hxR; linarith
      have h_norm_diff : DifferentiableAt ℝ (fun y : E n => ‖y‖ / R) x := by
        have h1 : DifferentiableAt ℝ (fun y : E n => ‖y‖) x :=
          (contDiffAt_norm ℝ hx_ne).differentiableAt WithTop.top_ne_zero
        have h2 : DifferentiableAt ℝ (fun y : E n => ‖y‖ * R⁻¹) x := h1.mul_const R⁻¹
        convert h2 using 1
      have h_cutoff_diff : DifferentiableAt ℝ smoothCutoff (‖x‖ / R) :=
        smoothCutoff_contDiff.differentiable (WithTop.coe_ne_zero.mpr WithTop.top_ne_zero) (‖x‖ / R)
      have hchain : fderiv ℝ (smoothCutoffR (n := n) R) x =
          fderiv ℝ smoothCutoff (‖x‖ / R) ∘L fderiv ℝ (fun y : E n => ‖y‖ / R) x := by
        unfold smoothCutoffR
        exact fderiv_comp x h_cutoff_diff h_norm_diff
      rw [hchain]
      calc ‖fderiv ℝ smoothCutoff (‖x‖ / R) ∘L fderiv ℝ (fun y : E n => ‖y‖ / R) x‖
          ≤ ‖fderiv ℝ smoothCutoff (‖x‖ / R)‖ * ‖fderiv ℝ (fun y : E n => ‖y‖ / R) x‖ :=
            ContinuousLinearMap.opNorm_comp_le _ _
        _ ≤ C * (1 / R) := by
            apply mul_le_mul
            · have heq : fderiv ℝ smoothCutoff (‖x‖ / R) = (deriv smoothCutoff (‖x‖ / R)) • (1 : ℝ →L[ℝ] ℝ) := by
                ext
                simp only [ContinuousLinearMap.smul_apply, ContinuousLinearMap.one_apply, smul_eq_mul]
                rw [fderiv_eq_smul_deriv, smul_eq_mul, mul_comm]
              rw [heq, norm_smul, norm_one, mul_one, Real.norm_eq_abs]
              calc |deriv smoothCutoff (‖x‖ / R)| = ‖deriv smoothCutoff (‖x‖ / R)‖ := (Real.norm_eq_abs _).symm
                _ ≤ C := hC_bound (‖x‖ / R)
            · exact fderiv_norm_div_bound hR x
            · exact norm_nonneg _
            · exact le_of_lt hC_pos
        _ = C / R := by ring
  -- Filter approach: show eLpNorm converges to 0 using squeeze
  rw [ENNReal.tendsto_atTop_zero]
  intro ε hε
  -- We need eLpNorm ≤ ε for R large enough
  -- Since eLpNorm (f·∇χ_R) ≤ (C/R) * eLpNorm f, we need C/R * ||f||_2 ≤ ε
  -- i.e., R ≥ C * ||f||_2 / ε
  by_cases hf_zero : eLpNorm f 2 (stdGaussianE n) = 0
  · -- If ||f||_2 = 0, then f = 0 a.e., so f·∇χ_R = 0 a.e.
    use 1
    intro R hR
    have hf_ae : f =ᵐ[stdGaussianE n] (fun _ => (0 : ℝ)) :=
        (eLpNorm_eq_zero_iff hf.aestronglyMeasurable (by norm_num : (2 : ℝ≥0∞) ≠ 0)).mp hf_zero
    have hgoal_ae : (fun x => f x • fderiv ℝ (smoothCutoffR R) x) =ᵐ[stdGaussianE n]
        (fun _ : E n => (0 : E n →L[ℝ] ℝ)) := by
      filter_upwards [hf_ae] with x hx
      rw [hx, zero_smul]
    have h1 : eLpNorm (fun x => f x • fderiv ℝ (smoothCutoffR R) x) 2 (stdGaussianE n) =
        eLpNorm (fun _ : E n => (0 : E n →L[ℝ] ℝ)) 2 (stdGaussianE n) := eLpNorm_congr_ae hgoal_ae
    have h2 : eLpNorm (fun _ : E n => (0 : E n →L[ℝ] ℝ)) 2 (stdGaussianE n) = 0 :=
      eLpNorm_zero' (α := E n) (ε := E n →L[ℝ] ℝ) (p := 2) (μ := stdGaussianE n)
    rw [h1, h2]
    exact le_of_lt hε
  · -- If ||f||_2 ≠ 0
    have hf_ne_top : eLpNorm f 2 (stdGaussianE n) ≠ ⊤ := hf.eLpNorm_lt_top.ne
    -- For R > C * ||f||_2 / ε, we have (C/R) * ||f||_2 < ε
    -- We use: eLpNorm (f·∇χ_R) ≤ (C/R) * eLpNorm f
    set M := C.toNNReal
    -- We need R such that C/R * ||f|| ≤ ε
    -- i.e., C * ||f|| ≤ ε * R, i.e., R ≥ C * ||f|| / ε
    use max (1 : ℝ) ((C * (eLpNorm f 2 (stdGaussianE n)).toReal) / ε.toReal + 1)
    intro R hR
    have hR_pos : 0 < R := by
      calc (0 : ℝ) < 1 := by norm_num
        _ ≤ max (1 : ℝ) _ := le_max_left _ _
        _ ≤ R := hR
    -- Bound eLpNorm (f·∇χ_R) ≤ (C/R) * eLpNorm f using ENNReal.ofReal
    have hCR_nneg : 0 ≤ C / R := div_nonneg (le_of_lt hC_pos) (le_of_lt hR_pos)
    have hfact : ∀ x : E n, ‖f x • fderiv ℝ (smoothCutoffR R) x‖ ≤ (C / R) * ‖f x‖ := by
      intro x
      rw [norm_smul, Real.norm_eq_abs, mul_comm]
      calc ‖fderiv ℝ (smoothCutoffR R) x‖ * |f x|
          ≤ (C / R) * |f x| := mul_le_mul_of_nonneg_right (hbound R hR_pos x) (abs_nonneg _)
        _ = (C / R) * ‖f x‖ := by rw [Real.norm_eq_abs]
    -- Key bound: (C/R) * ||f||.toReal < ε.toReal for R large enough
    have hR_bound : R > C * (eLpNorm f 2 (stdGaussianE n)).toReal / ε.toReal := by
      calc R ≥ max (1 : ℝ) ((C * (eLpNorm f 2 (stdGaussianE n)).toReal) / ε.toReal + 1) := hR
        _ ≥ (C * (eLpNorm f 2 (stdGaussianE n)).toReal) / ε.toReal + 1 := le_max_right _ _
        _ > (C * (eLpNorm f 2 (stdGaussianE n)).toReal) / ε.toReal := by linarith
    by_cases hε_top : ε = ⊤
    · simp only [hε_top, le_top]
    · have hε_pos : 0 < ε.toReal := ENNReal.toReal_pos (ne_of_gt hε) hε_top
      have key : C / R * (eLpNorm f 2 (stdGaussianE n)).toReal < ε.toReal := by
        have hε_ne : ε.toReal ≠ 0 := ne_of_gt hε_pos
        -- From hR_bound: R > C * ||f|| / ε, we get C * ||f|| / R < ε
        calc C / R * (eLpNorm f 2 (stdGaussianE n)).toReal
            = C * (eLpNorm f 2 (stdGaussianE n)).toReal / R := by ring
          _ < ε.toReal := by
              rw [div_lt_iff₀ hR_pos]
              -- From R > C * ||f|| / ε, multiply by ε to get R * ε > C * ||f||
              have h1 : R * ε.toReal > C * (eLpNorm f 2 (stdGaussianE n)).toReal := by
                have := mul_lt_mul_of_pos_right hR_bound hε_pos
                rwa [div_mul_cancel₀ _ hε_ne] at this
              linarith
      -- Use eLpNorm_mono and the pointwise bound
      have heLpNorm_le : eLpNorm (fun x => f x • fderiv ℝ (smoothCutoffR R) x) 2 (stdGaussianE n)
          ≤ ENNReal.ofReal (C / R) * eLpNorm f 2 (stdGaussianE n) := by
        calc eLpNorm (fun x => f x • fderiv ℝ (smoothCutoffR R) x) 2 (stdGaussianE n)
            ≤ eLpNorm (fun x => (C / R) * ‖f x‖) 2 (stdGaussianE n) := by
              apply MeasureTheory.eLpNorm_mono_real
              intro x
              exact hfact x
          _ = ENNReal.ofReal (C / R) * eLpNorm (fun x => ‖f x‖) 2 (stdGaussianE n) := by
              -- Use eLpNorm_const_smul: ||c • f||_p = ||c||ₑ * ||f||_p
              have h1 : (fun x => (C / R) * ‖f x‖) = (C / R) • (fun x => ‖f x‖) := by
                ext x; simp [smul_eq_mul]
              rw [h1, eLpNorm_const_smul]
              congr 1
              -- Show ||C/R||ₑ = ENNReal.ofReal (C / R)
              exact Real.enorm_eq_ofReal hCR_nneg
          _ = ENNReal.ofReal (C / R) * eLpNorm f 2 (stdGaussianE n) := by
              congr 1
              exact eLpNorm_norm (f := f)
      calc eLpNorm (fun x => f x • fderiv ℝ (smoothCutoffR R) x) 2 (stdGaussianE n)
          ≤ ENNReal.ofReal (C / R) * eLpNorm f 2 (stdGaussianE n) := heLpNorm_le
        _ = ENNReal.ofReal (C / R) * ENNReal.ofReal (eLpNorm f 2 (stdGaussianE n)).toReal := by
            rw [ENNReal.ofReal_toReal hf_ne_top]
        _ = ENNReal.ofReal ((C / R) * (eLpNorm f 2 (stdGaussianE n)).toReal) := by
            rw [← ENNReal.ofReal_mul hCR_nneg]
        _ ≤ ENNReal.ofReal ε.toReal := ENNReal.ofReal_le_ofReal (le_of_lt key)
        _ = ε := ENNReal.ofReal_toReal hε_top

/-! ### Helper Lemmas for Main Theorem -/

/-- For x on the sphere ‖x‖ = R and w ⊥ x, a convex combination moving inward stays inside.

    Key calculation: ‖(1-t)x + tw‖² = (1-t)²R² + t²‖w‖² < R² when t is small enough.
    The condition t ≤ R²/(R² + ‖w‖² + 1) ensures t(R² + ‖w‖²) < R² which gives the bound. -/
lemma ball_containment_perp {R t : ℝ} {x w : E n}
    (hR : 0 < R) (hnorm_eq : ‖x‖ = R) (hw : @inner ℝ (E n) _ x w = 0)
    (ht_pos : 0 < t) (ht_le : t ≤ 1/2)
    (ht_bound : t ≤ R^2 / (R^2 + ‖w‖^2 + 1)) :
    ‖(1 - t) • x + t • w‖ < R := by
  have h1 : ‖(1 - t) • x + t • w‖^2 = (1 - t)^2 * R^2 + t^2 * ‖w‖^2 := by
    rw [norm_add_pow_two_real]
    simp only [norm_smul, Real.norm_of_nonneg (by linarith : 0 ≤ 1 - t),
      Real.norm_of_nonneg ht_pos.le, inner_smul_left, inner_smul_right, hw,
      mul_zero, hnorm_eq, add_zero]
    ring
  have h2 : (1 - t)^2 * R^2 + t^2 * ‖w‖^2 < R^2 := by
    have hdenom_pos : 0 < R^2 + ‖w‖^2 + 1 := by linarith [sq_nonneg R, sq_nonneg ‖w‖]
    have hkey : t * (R^2 + ‖w‖^2) < R^2 := by
      have h1' : t * (R^2 + ‖w‖^2 + 1) ≤ R^2 := by
        have ht_ineq_eq : (R^2 / (R^2 + ‖w‖^2 + 1)) * (R^2 + ‖w‖^2 + 1) = R^2 := by field_simp
        calc t * (R^2 + ‖w‖^2 + 1) ≤ (R^2 / (R^2 + ‖w‖^2 + 1)) * (R^2 + ‖w‖^2 + 1) :=
            mul_le_mul_of_nonneg_right ht_bound hdenom_pos.le
          _ = R^2 := ht_ineq_eq
      linarith [mul_pos ht_pos (by linarith : (0:ℝ) < 1)]
    nlinarith [sq_nonneg (1 - t), sq_nonneg ‖w‖, sq_nonneg R, sq_nonneg t]
  have hnorm_nonneg : 0 ≤ ‖(1 - t) • x + t • w‖ := norm_nonneg _
  have hsq_lt : ‖(1 - t) • x + t • w‖^2 < R^2 := by linarith [h1, h2]
  exact (sq_lt_sq₀ hnorm_nonneg (le_of_lt hR)).mp hsq_lt

/-- A continuous linear map E n →L[ℝ] ℝ is zero if it vanishes on x and all w ⊥ x.

    Proof: decompose any v = ax + w where w ⊥ x, then L(v) = aL(x) + L(w) = 0. -/
lemma clm_zero_of_vanishes_inward {x : E n} (hx_ne : x ≠ 0)
    (L : E n →L[ℝ] ℝ) (hL_x : L x = 0)
    (hL_perp : ∀ w, @inner ℝ (E n) _ x w = 0 → L w = 0) :
    L = 0 := by
  ext v
  -- Decompose v = ax + w where w ⊥ x
  let a : ℝ := @inner ℝ (E n) _ x v / ‖x‖^2
  let w : E n := v - a • x
  have hw_perp : @inner ℝ (E n) _ x w = (0 : ℝ) := by
    simp only [w, a, inner_sub_right, inner_smul_right]
    have h : @inner ℝ (E n) _ x x = ‖x‖^2 := real_inner_self_eq_norm_sq x
    rw [h]; field_simp; ring
  have hL_w : L w = 0 := hL_perp w hw_perp
  have hv_decomp : v = a • x + w := by simp only [w]; module
  calc L v = L (a • x + w) := by rw [hv_decomp]
    _ = a • L x + L w := by simp only [map_add, map_smul]
    _ = a • 0 + 0 := by rw [hL_x, hL_w]
    _ = 0 := by simp

/-- At a point x on the sphere ‖x‖ = R, if f·g is differentiable and g = 0 on the closed ball,
    then fderiv ℝ (f * g) x = 0.

    The key insight is that the function is identically 0 on the closed ball {y : ‖y‖ ≤ R},
    and x is on the boundary. For any direction pointing "inward" (toward the ball's interior),
    the function values are all 0, so the directional derivative is 0. Since these directions
    span the space, the full fderiv must be 0. -/
lemma fderiv_zero_at_ball_boundary {R : ℝ} {f g : E n → ℝ} {x : E n}
    (hR : 0 < R) (hnorm_eq : ‖x‖ = R) (hx_ne : x ≠ 0)
    (h_zero_ball : ∀ y, ‖y‖ ≤ R → (f * g) y = 0)
    (hdiff_prod : DifferentiableAt ℝ (f * g) x) :
    fderiv ℝ (f * g) x = 0 := by
  have hxpos : 0 < ‖x‖ := by rw [hnorm_eq]; exact hR
  let L := fderiv ℝ (f * g) x
  have h_fderiv_at := hdiff_prod.hasFDerivAt
  -- Step 1: Show L(x) = 0 by approaching from direction -x (toward center)
  have hL_x : L x = 0 := by
    by_contra hne
    have hpos : 0 < ‖L x‖ := norm_pos_iff.mpr hne
    let ε : ℝ := ‖L x‖ / (2 * ‖x‖)
    have hε : 0 < ε := div_pos hpos (mul_pos (by norm_num) hxpos)
    obtain ⟨δ, hδ_pos, hδ_prop⟩ := Metric.eventually_nhds_iff.mp (h_fderiv_at.isLittleO.def hε)
    let t := min (δ / (2 * ‖x‖)) (1/2)
    have ht_pos : 0 < t := lt_min (div_pos hδ_pos (mul_pos (by norm_num) hxpos)) (by norm_num)
    have ht_le : t ≤ 1/2 := min_le_right _ _
    have ht_small : t * ‖x‖ < δ := by
      calc t * ‖x‖ ≤ (δ / (2 * ‖x‖)) * ‖x‖ := mul_le_mul_of_nonneg_right (min_le_left _ _) hxpos.le
        _ = δ / 2 := by field_simp
        _ < δ := by linarith
    have h_in_ball : ‖(1 - t) • x‖ ≤ R := by
      have h_one_sub_t_nonneg : 0 ≤ 1 - t := by linarith
      simp only [norm_smul, Real.norm_of_nonneg h_one_sub_t_nonneg, hnorm_eq]
      have : 1 - t ≤ 1 := by linarith [ht_pos]
      calc (1 - t) * R ≤ 1 * R := mul_le_mul_of_nonneg_right this hR.le
        _ = R := one_mul R
    have h_zero : (f * g) ((1 - t) • x) = 0 := h_zero_ball _ h_in_ball
    have hdist : dist (x + (-(t • x))) x < δ := by
      rw [dist_eq_norm, add_sub_cancel_left, norm_neg, norm_smul, Real.norm_of_nonneg ht_pos.le]
      exact ht_small
    have h1 : x + (-(t • x)) = (1 - t) • x := by module
    rw [h1] at hdist
    specialize hδ_prop hdist
    have h2 : (1 - t) • x - x = -(t • x) := by module
    have h3 : (f * g) ((1 - t) • x) - (f * g) x = 0 := by
      rw [h_zero, h_zero_ball x (by rw [hnorm_eq])]; ring
    have h4 : ‖(1 - t) • x - x‖ = t * ‖x‖ := by
      rw [h2, norm_neg, norm_smul, Real.norm_of_nonneg ht_pos.le]
    rw [h3, h4, h2, zero_sub, norm_neg] at hδ_prop
    have h5 : L (-(t • x)) = -(t * L x) := by simp only [map_neg, map_smul, smul_eq_mul]
    rw [h5, norm_neg, Real.norm_eq_abs, abs_mul, abs_of_pos ht_pos, ← Real.norm_eq_abs (L x)] at hδ_prop
    have h6 : ε * (t * ‖x‖) = t * ‖L x‖ / 2 := by simp only [ε]; field_simp
    rw [h6] at hδ_prop
    linarith [mul_pos ht_pos hpos]
  -- Step 2: Show L(w) = 0 for any w ⊥ x
  have hL_perp : ∀ w : E n, @inner ℝ (E n) _ x w = 0 → L w = 0 := by
    intro w hw
    by_contra hLw_ne
    have hLw_pos : 0 < |L w| := abs_pos.mpr hLw_ne
    -- Use ε = |L w| / (4(‖x‖ + ‖w‖)) to get contradiction
    have hε : 0 < |L w| / (4 * (‖x‖ + ‖w‖ + 1)) := div_pos hLw_pos (by linarith [norm_nonneg x, norm_nonneg w])
    obtain ⟨δ, hδ_pos, hδ_prop⟩ := Metric.eventually_nhds_iff.mp (h_fderiv_at.isLittleO.def hε)
    let t_ineq := R^2 / (R^2 + ‖w‖^2 + 1)
    have ht_ineq_pos : 0 < t_ineq := div_pos (sq_pos_of_pos hR) (by linarith [sq_nonneg R, sq_nonneg ‖w‖])
    let t := min (min (δ / (2 * (‖x‖ + ‖w‖ + 1))) (1/2)) t_ineq
    have ht_pos : 0 < t := lt_min (lt_min (div_pos hδ_pos (mul_pos (by norm_num)
      (by linarith [norm_nonneg x, norm_nonneg w]))) (by norm_num)) ht_ineq_pos
    have ht_le : t ≤ 1/2 := le_trans (min_le_left _ _) (min_le_right _ _)
    have ht_le_ineq : t ≤ t_ineq := min_le_right _ _
    have ht_bound : t ≤ δ / (2 * (‖x‖ + ‖w‖ + 1)) := le_trans (min_le_left _ _) (min_le_left _ _)
    have h_neg_bound : ‖-x + w‖ ≤ ‖x‖ + ‖w‖ := by
      calc ‖-x + w‖ ≤ ‖-x‖ + ‖w‖ := norm_add_le _ _
        _ = ‖x‖ + ‖w‖ := by rw [norm_neg]
    have h_norm_bound : ‖t • (-x + w)‖ ≤ t * (‖x‖ + ‖w‖) := by
      rw [norm_smul, Real.norm_of_nonneg ht_pos.le]
      exact mul_le_mul_of_nonneg_left h_neg_bound ht_pos.le
    have h_prod_lt : t * (‖x‖ + ‖w‖) < δ := by
      have h4 : ‖x‖ + ‖w‖ + 1 > 0 := by linarith [norm_nonneg x, norm_nonneg w]
      have h5 : ‖x‖ + ‖w‖ < ‖x‖ + ‖w‖ + 1 := by linarith
      have hstep1 : t * (‖x‖ + ‖w‖) ≤ (δ / (2 * (‖x‖ + ‖w‖ + 1))) * (‖x‖ + ‖w‖) := by
        apply mul_le_mul_of_nonneg_right ht_bound (by linarith [norm_nonneg x, norm_nonneg w])
      have hstep2 : (δ / (2 * (‖x‖ + ‖w‖ + 1))) * (‖x‖ + ‖w‖) < δ := by
        calc (δ / (2 * (‖x‖ + ‖w‖ + 1))) * (‖x‖ + ‖w‖)
            = δ * (‖x‖ + ‖w‖) / (2 * (‖x‖ + ‖w‖ + 1)) := by ring
          _ < δ * (‖x‖ + ‖w‖ + 1) / (2 * (‖x‖ + ‖w‖ + 1)) := by
            apply div_lt_div_of_pos_right _ (mul_pos (by norm_num) h4)
            apply mul_lt_mul_of_pos_left h5 hδ_pos
          _ = δ / 2 := by field_simp
          _ < δ := by linarith
      linarith
    have h_norm_lt : ‖t • (-x + w)‖ < δ := by linarith
    have h_inside : ‖(1 - t) • x + t • w‖ < R := by
      have hw' : @inner ℝ (E n) _ x w = 0 := hw
      exact ball_containment_perp hR hnorm_eq hw' ht_pos ht_le ht_le_ineq
    have h_zero' : (f * g) ((1 - t) • x + t • w) = 0 := h_zero_ball _ (le_of_lt h_inside)
    have h_eq : x + t • (-x + w) = (1 - t) • x + t • w := by
      simp only [smul_add, smul_neg, sub_smul, one_smul]; module
    have hdist' : dist (x + t • (-x + w)) x < δ := by rwa [dist_eq_norm, add_sub_cancel_left]
    specialize hδ_prop hdist'
    rw [h_eq] at hδ_prop
    simp only [h_zero', h_zero_ball x (by rw [hnorm_eq]), sub_zero] at hδ_prop
    have h_arg_eq : (1 - t) • x + t • w - x = t • (-x + w) := by module
    rw [h_arg_eq] at hδ_prop
    have hLh : L (t • (-x + w)) = t • L w := by
      simp only [map_smul, map_add, map_neg, hL_x, neg_zero, zero_add]
    rw [hLh] at hδ_prop
    simp only [smul_eq_mul, zero_sub, Real.norm_eq_abs, abs_neg, abs_mul,
      abs_of_pos ht_pos, norm_smul, Real.norm_of_nonneg ht_pos.le] at hδ_prop
    -- t * |L(w)| ≤ (|L(w)|/(4(‖x‖+‖w‖+1))) * t(‖x‖+‖w‖) ≤ t|L(w)|/4
    have h_bound : t * |L w| ≤ t * |L w| / 4 := by
      calc t * |L w| ≤ (|L w| / (4 * (‖x‖ + ‖w‖ + 1))) * (t * ‖-x + w‖) := hδ_prop
        _ ≤ (|L w| / (4 * (‖x‖ + ‖w‖ + 1))) * (t * (‖x‖ + ‖w‖ + 1)) := by
          apply mul_le_mul_of_nonneg_left _ (by linarith)
          apply mul_le_mul_of_nonneg_left _ ht_pos.le
          calc ‖-x + w‖ ≤ ‖x‖ + ‖w‖ := h_neg_bound
            _ ≤ ‖x‖ + ‖w‖ + 1 := by linarith
        _ = t * |L w| / 4 := by field_simp
    nlinarith [mul_pos ht_pos hLw_pos]
  -- Step 3: Apply the decomposition lemma
  exact clm_zero_of_vanishes_inward hx_ne L hL_x hL_perp

/-! ### Main Cutoff Theorem -/

set_option maxHeartbeats 2000000 in
/-- Helper for triangle inequality with norm composition. -/
lemma eLpNorm_norm_add_le {α : Type*} [MeasurableSpace α] {μ : Measure α}
    {E : Type*} [NormedAddCommGroup E] {f g : α → E}
    (hf : AEStronglyMeasurable f μ) (hg : AEStronglyMeasurable g μ) :
    eLpNorm (fun x => ‖f x‖ + ‖g x‖) 2 μ ≤ eLpNorm f 2 μ + eLpNorm g 2 μ := by
  -- Pre-compute norm measurability to avoid repeated elaboration
  have hfn : AEStronglyMeasurable (fun x => ‖f x‖) μ := hf.norm
  have hgn : AEStronglyMeasurable (fun x => ‖g x‖) μ := hg.norm
  have h1 : (fun x => ‖f x‖ + ‖g x‖) = (fun x => ‖f x‖) + (fun x => ‖g x‖) := rfl
  rw [h1]
  have hadd := eLpNorm_add_le hfn hgn (by norm_num : (1 : ℝ≥0∞) ≤ 2)
  simp only [eLpNorm_norm] at hadd
  exact hadd

set_option maxHeartbeats 8000000 in
/-- The cutoff f^(R) = f·χ_R converges to f in the W^{1,2}(γ) Sobolev norm as R → ∞. -/
theorem tendsto_cutoff_W12 (f : E n → ℝ) (hf : MemW12Gaussian n f (stdGaussianE n)) :
    Filter.Tendsto (fun R =>
        GaussianSobolevNormSq n (f * smoothCutoffR R - f) (stdGaussianE n))
      Filter.atTop (nhds 0) := by
  -- Extract hypotheses
  obtain ⟨hf_L2, hf_grad⟩ := hf

  -- GaussianSobolevNormSq = ||f||² + ||∇f||²
  simp only [GaussianSobolevNormSq]

  -- The sum of two terms both tending to 0 tends to 0
  have h0 : (0 : ℝ≥0∞) = 0 + 0 := by simp
  rw [h0]
  apply Filter.Tendsto.add

  -- Part 1: ||f * χ_R - f||_2² → 0
  · -- Note: f * χ_R - f = -(f - f * χ_R), so ||f * χ_R - f||_2 = ||f - f * χ_R||_2
    have heq : ∀ R : ℝ, eLpNorm (f * smoothCutoffR R - f) 2 (stdGaussianE n)
        = eLpNorm (f - f * smoothCutoffR R) 2 (stdGaussianE n) := by
      intro R
      have h1 : (f * smoothCutoffR R - f) = -(f - f * smoothCutoffR R) := by
        ext x
        simp only [Pi.mul_apply, Pi.sub_apply, Pi.neg_apply]
        ring
      rw [h1]
      rw [eLpNorm_neg]
    simp_rw [heq]
    -- Now use cutoff_L2_convergence
    have hL2 := cutoff_L2_convergence f hf_L2
    -- Use ENNReal.Tendsto.pow: if a → 0, then a^n → 0^n = 0
    have hsq := ENNReal.Tendsto.pow (n := 2) hL2
    simp only [ne_eq, OfNat.ofNat_ne_zero, not_false_eq_true, zero_pow] at hsq
    exact hsq

  -- Part 2: ||∇(f * χ_R - f)||_2² → 0
  · -- We need to bound ||∇(f * χ_R - f)|| ≤ ||(1-χ_R)∇f|| + ||f∇χ_R||

    -- Get the convergence of the two components
    have hterm1 := cutoff_gradient_error_bound f hf_grad
    have hterm2 := cutoff_gradient_extra_term f hf_L2

    -- The sum of two terms both tending to 0 tends to 0
    have hsum_tendsto : Filter.Tendsto (fun R =>
        eLpNorm (fun x => (1 - smoothCutoffR R x) • fderiv ℝ f x) 2 (stdGaussianE n) +
        eLpNorm (fun x => f x • fderiv ℝ (smoothCutoffR R) x) 2 (stdGaussianE n))
      Filter.atTop (nhds 0) := by
      have h0 : (0 : ℝ≥0∞) = 0 + 0 := by simp
      rw [h0]
      exact Filter.Tendsto.add hterm1 hterm2

    -- The eLpNorm of the gradient is bounded by this sum (by triangle inequality on fderiv)
    have hgrad_tendsto : Filter.Tendsto (fun R =>
        eLpNorm (fun x => ‖fderiv ℝ (f * smoothCutoffR R - f) x‖) 2 (stdGaussianE n))
      Filter.atTop (nhds 0) := by
      -- Use squeeze theorem with eventual bounds (only need R > 0)
      refine tendsto_of_tendsto_of_tendsto_of_le_of_le' tendsto_const_nhds hsum_tendsto ?_ ?_
      · -- Eventually 0 ≤ LHS (always true for eLpNorm)
        filter_upwards with R
        exact zero_le _
      · -- Eventually LHS ≤ RHS (only need for R > 0)
        filter_upwards [Filter.eventually_gt_atTop (0 : ℝ)] with R (hR_pos : 0 < R)
        -- Need: ||∇(f * χ_R - f)|| ≤ ||(1-χ_R)∇f|| + ||f∇χ_R||
        rw [eLpNorm_norm (f := fun x => fderiv ℝ (f * smoothCutoffR R - f) x)]
        have hnorm_bound : ∀ x, ‖fderiv ℝ (f * smoothCutoffR R - f) x‖ ≤
            ‖f x • fderiv ℝ (smoothCutoffR R) x‖ + ‖(1 - smoothCutoffR R x) • fderiv ℝ f x‖ := by
          intro x
          -- Now we have hR_pos : 0 < R from the filter
          by_cases hf_diff : DifferentiableAt ℝ f x
          · -- f differentiable: use product rule and triangle inequality
            have hχ_diff : DifferentiableAt ℝ (smoothCutoffR R) x :=
              (smoothCutoffR_contDiff hR_pos).differentiable (WithTop.coe_ne_zero.mpr WithTop.top_ne_zero) x
            have h1 : fderiv ℝ (f * smoothCutoffR R - f) x =
                fderiv ℝ (f * smoothCutoffR R) x - fderiv ℝ f x :=
              fderiv_sub (hf_diff.mul hχ_diff) hf_diff
            rw [h1, fderiv_mul hf_diff hχ_diff]
            have heq : f x • fderiv ℝ (smoothCutoffR R) x + smoothCutoffR R x • fderiv ℝ f x - fderiv ℝ f x =
                f x • fderiv ℝ (smoothCutoffR R) x - (1 - smoothCutoffR R x) • fderiv ℝ f x := by
              ext v
              simp only [ContinuousLinearMap.sub_apply, ContinuousLinearMap.add_apply,
                ContinuousLinearMap.smul_apply, sub_smul, one_smul]
              ring
            rw [heq]
            exact norm_sub_le _ _
          · -- f not differentiable at x: fderiv f x = 0
            have hdf : fderiv ℝ f x = 0 := fderiv_zero_of_not_differentiableAt hf_diff
            simp only [hdf, smul_zero, norm_zero, add_zero]
            -- Need: ‖fderiv (f * χ_R - f) x‖ ≤ ‖f x • fderiv χ_R x‖
            -- Case analysis on whether (f * χ_R - f) is differentiable:
            by_cases hdiff_prod : DifferentiableAt ℝ (f * smoothCutoffR R - f) x
            · -- Product differentiable but f not differentiable at x.
              have hχ_smooth := smoothCutoffR_contDiff (n := n) hR_pos
              have hχ_diff : DifferentiableAt ℝ (smoothCutoffR (n := n) R) x :=
                hχ_smooth.differentiable (WithTop.coe_ne_zero.mpr WithTop.top_ne_zero) x
              have hχ_eq_one : smoothCutoffR R x = 1 := by
                by_contra hne
                have h_nonzero : smoothCutoffR R x - 1 ≠ 0 := sub_ne_zero.mpr hne
                have heq : f * smoothCutoffR R - f = f * (smoothCutoffR R - 1) := by
                  ext y; simp only [Pi.mul_apply, Pi.sub_apply, Pi.one_apply]; ring
                have hdiff_prod' := hdiff_prod
                rw [heq] at hdiff_prod'
                have hf_diff' : DifferentiableAt ℝ f x := by
                  -- Define the functions explicitly
                  let num : E n → ℝ := fun y => f y * (smoothCutoffR R y - 1)
                  let den : E n → ℝ := fun y => smoothCutoffR R y - 1
                  have hnum : DifferentiableAt ℝ num x := by
                    have heq' : num = (f * (smoothCutoffR R - 1)) := by
                      ext y; simp only [Pi.mul_apply, Pi.sub_apply, Pi.one_apply, num]
                    rw [heq']; exact hdiff_prod'
                  have hden : DifferentiableAt ℝ den x :=
                    hχ_diff.sub (differentiableAt_const 1)
                  have hden_ne : den x ≠ 0 := h_nonzero
                  have hden_inv : DifferentiableAt ℝ (fun y => (den y)⁻¹) x :=
                    hden.inv hden_ne
                  have h_div : DifferentiableAt ℝ (num / den) x := by
                    have heq : num / den = fun y => num y * (den y)⁻¹ := by
                      ext y; simp [div_eq_mul_inv, num, den]
                    rw [heq]
                    exact hnum.mul hden_inv
                  -- num / den = f near x (since den is continuous and nonzero at x)
                  have h_ratio_near : f =ᶠ[nhds x] (num / den) := by
                    have h_cont : ContinuousAt den x := hden.continuousAt
                    have h_nhds : ∀ᶠ y in nhds x, den y ≠ 0 :=
                      h_cont.eventually_ne hden_ne
                    filter_upwards [h_nhds] with y hy
                    simp only [Pi.div_apply, num, den]
                    exact (mul_div_cancel_right₀ (f y) hy).symm
                  exact h_div.congr_of_eventuallyEq h_ratio_near
                exact hf_diff hf_diff'
              -- χ_R(x) = 1 means ‖x‖ ≤ R. Case split on strict inequality.
              by_cases hnorm_lt : ‖x‖ < R
              · -- Case ‖x‖ < R: χ_R = 1 in a neighborhood, so f * χ_R - f = 0 locally
                have hball := Metric.ball_mem_nhds x (by linarith : 0 < R - ‖x‖)
                have h_local_zero : ∀ᶠ y in nhds x, (f * smoothCutoffR (n := n) R - f) y = 0 := by
                  filter_upwards [hball] with y hy
                  simp only [Metric.mem_ball, dist_eq_norm] at hy
                  have hy_norm : ‖y‖ < R := by
                    have h1 : ‖y‖ ≤ ‖x‖ + ‖y - x‖ := norm_le_insert' y x
                    linarith
                  have hχ_y : smoothCutoffR R y = 1 := smoothCutoffR_eq_one_of_norm_le hR_pos (le_of_lt hy_norm)
                  simp only [Pi.mul_apply, Pi.sub_apply, hχ_y, mul_one, sub_self]
                have hfderiv_zero : fderiv ℝ (f * smoothCutoffR R - f) x = 0 := by
                  have h_eq : (f * smoothCutoffR (n := n) R - f) =ᶠ[nhds x] (fun _ : E n => (0 : ℝ)) := by
                    filter_upwards [h_local_zero] with y hy; exact hy
                  rw [Filter.EventuallyEq.fderiv_eq (𝕜 := ℝ) h_eq]
                  exact fderiv_const_apply (0 : ℝ)
                simp only [hfderiv_zero, norm_zero]
                exact norm_nonneg _
              · -- Case ‖x‖ ≥ R: Since χ_R(x) = 1, we have ‖x‖ ≤ R, so ‖x‖ = R
                push_neg at hnorm_lt
                have hnorm_le : ‖x‖ ≤ R := by
                  by_contra hgt; push_neg at hgt
                  -- ‖x‖ > R, so ‖x‖/R > 1
                  have hgt' : ‖x‖ / R > 1 := (one_lt_div hR_pos).mpr hgt
                  -- When ‖x‖/R > 1, smoothCutoff (‖x‖/R) < 1, contradicting χ_R(x) = 1
                  have hlt1 : smoothCutoff (‖x‖ / R) < 1 := by
                    by_cases hge2 : ‖x‖ / R ≥ 2
                    · have h0 := smoothCutoff_eq_zero_of_ge (by
                        rw [abs_of_nonneg (div_nonneg (norm_nonneg x) hR_pos.le)]; exact hge2)
                      simp only [h0]; norm_num
                    · push_neg at hge2
                      -- 1 < ‖x‖/R, so smoothCutoff < 1 by the lemma
                      have habs1 : 1 < |‖x‖ / R| := by
                        rw [abs_of_nonneg (div_nonneg (norm_nonneg _) hR_pos.le)]; exact hgt'
                      exact smoothCutoff_lt_one_of_abs_gt_one habs1
                  have hχ_eq : smoothCutoff (‖x‖ / R) = 1 := hχ_eq_one
                  linarith [hlt1, hχ_eq]
                have hfderiv_prod_zero : fderiv ℝ (f * smoothCutoffR R - f) x = 0 := by
                  -- Define g = χ_R - 1 as an explicit function
                  let g : E n → ℝ := fun y => smoothCutoffR R y - 1
                  have heq' : f * smoothCutoffR R - f = f * g := by
                    ext y; simp only [Pi.mul_apply, Pi.sub_apply]; ring
                  rw [heq'] at hdiff_prod ⊢
                  have hnorm_eq : ‖x‖ = R := le_antisymm hnorm_le hnorm_lt
                  have hx_ne : x ≠ 0 := by
                    intro hxz; rw [hxz, norm_zero] at hnorm_eq; linarith
                  -- The function is 0 on the closed ball (not just interior)
                  have h_zero_ball : ∀ y, ‖y‖ ≤ R → (f * g) y = 0 := by
                    intro y hy
                    simp only [Pi.mul_apply]
                    have : smoothCutoffR R y = 1 := smoothCutoffR_eq_one_of_norm_le hR_pos hy
                    simp only [g, this, sub_self, mul_zero]
                  -- Apply the helper lemma for fderiv at ball boundary
                  exact fderiv_zero_at_ball_boundary hR_pos hnorm_eq hx_ne h_zero_ball hdiff_prod
                simp only [hfderiv_prod_zero, norm_zero]
                exact norm_nonneg _
            · have h0 : fderiv ℝ (f * smoothCutoffR R - f) x = 0 :=
                fderiv_zero_of_not_differentiableAt hdiff_prod
              simp only [h0, norm_zero]
              exact norm_nonneg _
        -- Lift pointwise bound to eLpNorm bound via triangle inequality
        -- Pre-compute continuity for fderiv of cutoff to avoid repeated elaboration
        have hne : ((⊤ : ℕ∞) : WithTop ℕ∞) ≠ 0 := WithTop.coe_ne_zero.mpr ENat.top_ne_zero
        have hcont_fderiv : Continuous (fun x : E n => fderiv ℝ (smoothCutoffR (n := n) R) x) :=
          (smoothCutoffR_contDiff (n := n) hR_pos).continuous_fderiv hne
        have hcont_cutoff : Continuous (smoothCutoffR (n := n) R) :=
          (smoothCutoffR_contDiff (n := n) hR_pos).continuous
        -- Define intermediate terms to avoid repeated elaboration
        let term1 := fun x : E n => (1 - smoothCutoffR R x) • fderiv ℝ f x
        let term2 := fun x : E n => f x • fderiv ℝ (smoothCutoffR R) x
        -- Step 1: Use pointwise bound
        have hstep1 : eLpNorm (fun x => fderiv ℝ (f * smoothCutoffR R - f) x) 2 (stdGaussianE n)
            ≤ eLpNorm (fun x => ‖term2 x‖ + ‖term1 x‖) 2 (stdGaussianE n) := by
          apply eLpNorm_mono_real; intro x; exact hnorm_bound x
        -- Step 2: Triangle inequality for eLpNorm using helper
        have hmeas1 : AEStronglyMeasurable term2 (stdGaussianE n) :=
          hf_L2.aestronglyMeasurable.smul hcont_fderiv.aestronglyMeasurable
        have hmeas2 : AEStronglyMeasurable term1 (stdGaussianE n) :=
          ((continuous_const.sub hcont_cutoff).aestronglyMeasurable).smul hf_grad.aestronglyMeasurable
        have hstep2 := eLpNorm_norm_add_le hmeas1 hmeas2
        -- Combine and reorder
        have hreorder : eLpNorm term2 2 (stdGaussianE n) + eLpNorm term1 2 (stdGaussianE n) =
            eLpNorm term1 2 (stdGaussianE n) + eLpNorm term2 2 (stdGaussianE n) := add_comm _ _
        exact le_trans hstep1 (hreorder ▸ hstep2)

    -- Then square the limit using ENNReal.Tendsto.pow
    have hsq := ENNReal.Tendsto.pow (n := 2) hgrad_tendsto
    simp only [zero_pow (by norm_num : (2 : ℕ) ≠ 0)] at hsq
    exact hsq

end GaussianSobolev

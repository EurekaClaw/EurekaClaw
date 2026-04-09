/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.LeastSquares.LinearRegression.EuclideanReduction
import SLT.LeastSquares.LinearRegression.IntegralBounds
import SLT.MetricEntropy

/-!
# Entropy Integral Bounds for Linear Regression

This file proves the entropy integral bound for linear regression.

## Main Definitions

* `linearEntropyIntegral`: The entropy integral for the linear regression localized ball

## Main Results

* `linearLocalizedBallImage_totallyBounded`: The localized ball image is totally bounded
* `metricEntropy_linearLocalizedBall_le`: Metric entropy is bounded by d * log(1 + 2δ/ε)
* `linearEntropyIntegral_le`: The entropy integral is bounded by 4δ√d
* `linearEntropyIntegralENNReal_ne_top`: The ENNReal entropy integral is finite

-/

open MeasureTheory Finset BigOperators Real ProbabilityTheory Metric Set
open scoped NNReal ENNReal

namespace LeastSquares

variable {n d : ℕ}

/-! ## Linear Entropy Integral Bound

The entropy integral for linear regression:
∫₀^D √(log N(ε, B_n(δ), ‖·‖_n)) dε ≤ 2δ√(d/n)

This bound is key for applying Dudley's theorem to get Rademacher complexity bounds.
-/

/-- The entropy integral for the linear regression localized ball.
    This is ∫₀^D √(log N(ε, linearLocalizedBallImage)) dε -/
noncomputable def linearEntropyIntegral (n d : ℕ) (δ D : ℝ)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) : ℝ :=
  entropyIntegral (linearLocalizedBallImage n d δ x) D

/-- The linearLocalizedBallImage is totally bounded (as a finite-dimensional compact set image). -/
lemma linearLocalizedBallImage_totallyBounded (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) (δ : ℝ) :
    TotallyBounded (linearLocalizedBallImage n d δ x) := by
  -- The image under empiricalToEuclidean is the euclideanLocalizedBall, which is totally bounded
  -- (since it's a closed and bounded set in finite dimension)
  -- Then pull back via the uniformly continuous map empiricalToEuclidean
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have hsqrt_pos : 0 < Real.sqrt n := Real.sqrt_pos.mpr hn_pos
  -- Show that empiricalToEuclidean '' linearLocalizedBallImage is totally bounded
  have himage_eq := empiricalToEuclidean_image_eq hn x δ
  have htb_euc : TotallyBounded (euclideanLocalizedBall n d δ x) := by
    -- euclideanLocalizedBall is contained in a ball of radius δ√n
    apply TotallyBounded.subset (s₂ := Metric.closedBall 0 (δ * Real.sqrt n))
    · intro v hv
      unfold euclideanLocalizedBall euclideanBallOrigin at hv
      simp only [Set.mem_inter_iff, Metric.mem_closedBall, dist_zero_right] at hv ⊢
      exact hv.1
    · exact (ProperSpace.isCompact_closedBall 0 _).totallyBounded
  rw [← himage_eq] at htb_euc
  -- Use that the inverse map euclideanToEmpirical is Lipschitz
  -- Pull back totally bounded via the bijection
  -- The map empiricalToEuclidean scales distances by √n, so euclideanToEmpirical divides by √n
  apply Metric.totallyBounded_iff.mpr
  intro ε hε
  -- Get a finite cover for the image
  have hε_scaled : 0 < ε * Real.sqrt n := mul_pos hε hsqrt_pos
  obtain ⟨t, ht_finite, ht_cover⟩ := Metric.totallyBounded_iff.mp htb_euc (ε * Real.sqrt n) hε_scaled
  -- Map back to EmpiricalSpace
  use t.image (euclideanToEmpirical n)
  constructor
  · exact ht_finite.image _
  · intro y hy
    -- y is in linearLocalizedBallImage
    -- empiricalToEuclidean y is in the image, so covered by some ball
    have hy_euc : empiricalToEuclidean n y ∈ empiricalToEuclidean n '' linearLocalizedBallImage n d δ x :=
      Set.mem_image_of_mem _ hy
    have hy_cover := ht_cover hy_euc
    rw [Set.mem_iUnion₂] at hy_cover
    obtain ⟨z, hz_mem, hz_ball⟩ := hy_cover
    rw [Set.mem_iUnion₂]
    refine ⟨euclideanToEmpirical n z, Set.mem_image_of_mem _ hz_mem, ?_⟩
    rw [Metric.mem_ball]
    -- dist y (euclideanToEmpirical z) = dist(empiricalToEuclidean y, z) / √n
    have hdist := dist_euclidean_eq_sqrt_n_mul_dist_empirical hn y (euclideanToEmpirical n z)
    simp only [empiricalToEuclidean_euclideanToEmpirical] at hdist
    have hdist' : dist y (euclideanToEmpirical n z) = dist (empiricalToEuclidean n y) z / Real.sqrt n := by
      have hne : Real.sqrt n ≠ 0 := ne_of_gt hsqrt_pos
      field_simp at hdist ⊢
      linarith
    rw [hdist']
    rw [Metric.mem_ball] at hz_ball
    calc dist (empiricalToEuclidean n y) z / Real.sqrt n
        < (ε * Real.sqrt n) / Real.sqrt n := by
          apply div_lt_div_of_pos_right hz_ball hsqrt_pos
      _ = ε := by field_simp

/-- Helper: metricEntropyOfNat n ≤ log N when n ≤ N as reals. -/
lemma metricEntropyOfNat_le_log {m : ℕ} {N : ℝ} (hN_pos : 1 < N) (hm_le : (m : ℝ) ≤ N) :
    metricEntropyOfNat m ≤ Real.log N := by
  unfold metricEntropyOfNat
  split_ifs with h
  · exact Real.log_nonneg (le_of_lt hN_pos)
  · push_neg at h
    apply Real.log_le_log (Nat.cast_pos.mpr (by omega : 0 < m)) hm_le

/-- The metric entropy of the linear localized ball is bounded by d * log(1 + 2δ/ε).
    This follows from the covering number bound N(ε, s) ≤ (1 + 2δ/ε)^d. -/
lemma metricEntropy_linearLocalizedBall_le (hn : 0 < n) (hd : 0 < d)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {ε δ : ℝ} (hε : 0 < ε) (hδ : 0 < δ)
    (hinj : Function.Injective (designMatrixMul x)) :
    metricEntropy ε (linearLocalizedBallImage n d δ x) ≤ d * Real.log (1 + 2 * δ / ε) := by
  -- Step 1: Get bounds on the covering number
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have hsqrt_pos : 0 < Real.sqrt n := Real.sqrt_pos.mpr hn_pos
  have hε_scaled : 0 < ε * Real.sqrt n := mul_pos hε hsqrt_pos
  have hδ_nonneg : 0 ≤ δ := le_of_lt hδ
  -- Step 2: Use linearCoveringNumber_le_euclideanBall_d
  have hcov_lin := linearCoveringNumber_le_euclideanBall_d (s := ε) (δ := δ) hn hd x hinj
  -- Step 3: Get the Euclidean ball covering number bound (need Nonempty Fin d)
  haveI : Nonempty (Fin d) := Fin.pos_iff_nonempty.mp hd
  have hball_bound := coveringNumber_euclideanBall_le (ι := Fin d)
    (mul_nonneg hδ_nonneg (le_of_lt hsqrt_pos)) hε_scaled
  -- Step 4: The RHS simplifies because (δ√n)/(ε√n) = δ/ε
  have h_simp : 1 + 2 * (δ * Real.sqrt n) / (ε * Real.sqrt n) = 1 + 2 * δ / ε := by
    have hsqrt_ne : Real.sqrt n ≠ 0 := ne_of_gt hsqrt_pos
    field_simp
  simp only [Fintype.card_fin] at hball_bound
  rw [h_simp] at hball_bound
  -- Step 5: Extract natural numbers from covering numbers and apply log bound
  unfold metricEntropy linearCoveringNumber at *
  have htb : TotallyBounded (linearLocalizedBallImage n d δ x) :=
    linearLocalizedBallImage_totallyBounded hn x δ
  have hfin : coveringNumber ε (linearLocalizedBallImage n d δ x) < ⊤ :=
    coveringNumber_lt_top_of_totallyBounded hε htb
  -- Get the natural number value
  split
  · -- Case: coveringNumber = ⊤ (contradicts hfin)
    rename_i heq
    rw [heq] at hfin
    exact absurd rfl (ne_of_lt hfin)
  · rename_i m hm
    -- m = coveringNumber ε (linearLocalizedBallImage)
    -- Need to show: metricEntropyOfNat m ≤ d * log(1 + 2δ/ε)
    -- The covering number of euclideanBall is finite
    have htb_ball : TotallyBounded (euclideanBall (δ * Real.sqrt n) : Set (EuclideanSpace ℝ (Fin d))) :=
      euclideanBall_totallyBounded _
    have hfin_ball : coveringNumber (ε * Real.sqrt n) (euclideanBall (δ * Real.sqrt n) : Set (EuclideanSpace ℝ (Fin d))) < ⊤ :=
      coveringNumber_lt_top_of_totallyBounded hε_scaled htb_ball
    have hne_ball : coveringNumber (ε * Real.sqrt n) (euclideanBall (δ * Real.sqrt n) : Set (EuclideanSpace ℝ (Fin d))) ≠ ⊤ :=
      ne_top_of_lt hfin_ball
    -- Extract natural number from ball covering number
    let m_ball := (coveringNumber (ε * Real.sqrt n) (euclideanBall (δ * Real.sqrt n) : Set (EuclideanSpace ℝ (Fin d)))).untop hne_ball
    have hm_ball_eq : coveringNumber (ε * Real.sqrt n) (euclideanBall (δ * Real.sqrt n) : Set (EuclideanSpace ℝ (Fin d))) = m_ball :=
      (WithTop.coe_untop _ hne_ball).symm
    -- m ≤ m_ball (using that euclideanBall = Metric.closedBall 0)
    have hm_le_ball : m ≤ m_ball := by
      rw [hm, hm_ball_eq] at hcov_lin
      exact WithTop.coe_le_coe.mp hcov_lin
    -- m_ball ≤ (1 + 2δ/ε)^d from hball_bound
    -- The untop values are the same since the covering numbers are definitionally equal
    have hball_le : (m_ball : ℝ) ≤ (1 + 2 * δ / ε) ^ d := by
      convert hball_bound using 2
    -- m ≤ (1 + 2δ/ε)^d
    have hm_le : (m : ℝ) ≤ (1 + 2 * δ / ε) ^ d := le_trans (Nat.cast_le.mpr hm_le_ball) hball_le
    -- Use metricEntropyOfNat_le_log
    have hN_pos : 1 < (1 + 2 * δ / ε) ^ d := by
      have hbase : 1 < 1 + 2 * δ / ε := by
        have : 0 < 2 * δ / ε := by positivity
        linarith
      have hd_ne : d ≠ 0 := Nat.pos_iff_ne_zero.mp hd
      exact one_lt_pow₀ hbase hd_ne
    calc metricEntropyOfNat m
        ≤ Real.log ((1 + 2 * δ / ε) ^ d) := metricEntropyOfNat_le_log hN_pos hm_le
      _ = d * Real.log (1 + 2 * δ / ε) := by
          rw [Real.log_pow]

/-- The square root entropy of the linear localized ball is bounded by √(d · log(1 + 2δ/ε)). -/
lemma sqrtEntropy_linearLocalizedBall_le (hn : 0 < n) (hd : 0 < d)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {ε δ : ℝ} (hε : 0 < ε) (hδ : 0 < δ)
    (hinj : Function.Injective (designMatrixMul x)) :
    sqrtEntropy ε (linearLocalizedBallImage n d δ x) ≤ Real.sqrt (d * Real.log (1 + 2 * δ / ε)) := by
  unfold sqrtEntropy
  apply Real.sqrt_le_sqrt
  exact metricEntropy_linearLocalizedBall_le hn hd x hε hδ hinj

/-- The dudleyIntegrand for linear regression is bounded by the explicit entropy bound. -/
lemma dudleyIntegrand_linearLocalizedBall_le (hn : 0 < n) (hd : 0 < d)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {ε δ : ℝ} (hε : 0 < ε) (hδ : 0 < δ)
    (hinj : Function.Injective (designMatrixMul x)) :
    dudleyIntegrand ε (linearLocalizedBallImage n d δ x) ≤
    ENNReal.ofReal (Real.sqrt (d * Real.log (1 + 2 * δ / ε))) := by
  unfold dudleyIntegrand
  apply ENNReal.ofReal_le_ofReal
  exact sqrtEntropy_linearLocalizedBall_le hn hd x hε hδ hinj

/-- The entropy integral for linear regression is bounded by the integral of the explicit bound.

    linearEntropyIntegral n d δ D x ≤ ∫₀^D √(d · log(1 + 2δ/ε)) dε

    This follows from bounding the sqrtEntropy integrand pointwise. -/
theorem linearEntropyIntegral_le_explicit (hn : 0 < n) (hd : 0 < d)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ D : ℝ} (hδ : 0 < δ) (hDδ : D ≤ 2 * δ)
    (hinj : Function.Injective (designMatrixMul x)) :
    linearEntropyIntegral n d δ D x ≤
    ∫ ε in Set.Ioc 0 D, Real.sqrt (d * Real.log (1 + 2 * δ / ε)) := by
  unfold linearEntropyIntegral entropyIntegral entropyIntegralENNReal
  -- Bound the integrand pointwise (for a.e. ε in (0, D])
  have hbound : ∀ ε ∈ Set.Ioc (0 : ℝ) D,
      dudleyIntegrand ε (linearLocalizedBallImage n d δ x) ≤
      ENNReal.ofReal (Real.sqrt (d * Real.log (1 + 2 * δ / ε))) := fun ε hε =>
    dudleyIntegrand_linearLocalizedBall_le hn hd x hε.1 hδ hinj
  -- The explicit integrand is nonnegative
  have hnn : ∀ ε ∈ Set.Ioc (0 : ℝ) D, 0 ≤ Real.sqrt (d * Real.log (1 + 2 * δ / ε)) := by
    intro ε hε
    exact Real.sqrt_nonneg _
  -- Measurability of the explicit bound function
  have hmeas : Measurable (fun ε : ℝ => ENNReal.ofReal (Real.sqrt (d * Real.log (1 + 2 * δ / ε)))) := by
    apply ENNReal.measurable_ofReal.comp
    apply Measurable.sqrt
    apply Measurable.mul measurable_const
    apply Real.measurable_log.comp
    apply Measurable.add measurable_const
    apply Measurable.div measurable_const measurable_id
  -- Use lintegral_mono to bound the LHS
  have hmono : ∫⁻ ε in Set.Ioc (0 : ℝ) D, dudleyIntegrand ε (linearLocalizedBallImage n d δ x) ≤
      ∫⁻ ε in Set.Ioc (0 : ℝ) D, ENNReal.ofReal (Real.sqrt (d * Real.log (1 + 2 * δ / ε))) := by
    apply MeasureTheory.setLIntegral_mono hmeas
    intro ε hε
    exact hbound ε hε
  -- The integrability of the explicit bound on (0, D]
  -- This follows from the fact that √(log(1+c/ε)) is integrable near 0 (Gamma function argument)
  -- and continuous away from 0
  have hint : MeasureTheory.IntegrableOn
      (fun ε => Real.sqrt (d * Real.log (1 + 2 * δ / ε))) (Set.Ioc 0 D) := by
    -- Split into two parts: (0, min D 1] and (min D 1, D]
    -- On the compact part away from 0, the function is continuous hence integrable
    -- Near 0, we bound by √d * (√(log 3) + √(-log ε)) which is integrable
    by_cases hD1 : D ≤ 1
    · -- Case D ≤ 1: bound by integrable function on (0, 1)
      apply MeasureTheory.IntegrableOn.mono_set _ (Set.Ioc_subset_Ioc_right hD1)
      rw [integrableOn_Ioc_iff_integrableOn_Ioo]
      -- Pointwise bound: √(d * log(1 + 2δ/ε)) ≤ √d * (√(log(1+2δ)) + √(-log ε))
      have h_pointwise : ∀ ε ∈ Set.Ioo (0 : ℝ) 1,
          Real.sqrt (d * Real.log (1 + 2 * δ / ε)) ≤
          Real.sqrt d * (Real.sqrt (Real.log (1 + 2 * δ)) + Real.sqrt (-Real.log ε)) := by
        intro ε ⟨hε_pos, hε_lt⟩
        have h_log_bound := log_one_plus_two_delta_div_eps_bound hδ hε_pos hε_lt
        have h_log12δ_nonneg : 0 ≤ Real.log (1 + 2 * δ) := Real.log_nonneg (by linarith)
        have h_neglog_nonneg : 0 ≤ -Real.log ε := by
          rw [neg_nonneg]; exact Real.log_nonpos (le_of_lt hε_pos) (le_of_lt hε_lt)
        calc Real.sqrt (d * Real.log (1 + 2 * δ / ε))
            ≤ Real.sqrt (d * (Real.log (1 + 2 * δ) - Real.log ε)) := by
              apply Real.sqrt_le_sqrt
              apply mul_le_mul_of_nonneg_left h_log_bound (Nat.cast_nonneg d)
            _ = Real.sqrt (d * (Real.log (1 + 2 * δ) + (-Real.log ε))) := by ring_nf
            _ ≤ Real.sqrt (d * Real.log (1 + 2 * δ)) + Real.sqrt (d * (-Real.log ε)) := by
              rw [mul_add]
              exact sqrt_add_le (by positivity) (by positivity)
            _ = Real.sqrt d * Real.sqrt (Real.log (1 + 2 * δ)) +
                Real.sqrt d * Real.sqrt (-Real.log ε) := by
              rw [Real.sqrt_mul (Nat.cast_nonneg d), Real.sqrt_mul (Nat.cast_nonneg d)]
            _ = Real.sqrt d * (Real.sqrt (Real.log (1 + 2 * δ)) + Real.sqrt (-Real.log ε)) := by ring
      -- Establish integrability of the bounding function
      have h_Ioo_finite : volume (Set.Ioo (0 : ℝ) 1) ≠ ⊤ := by
        rw [Real.volume_Ioo]; exact ENNReal.ofReal_ne_top
      have h_const_int : MeasureTheory.IntegrableOn
          (fun _ : ℝ => Real.sqrt d * Real.sqrt (Real.log (1 + 2 * δ)))
          (Set.Ioo (0 : ℝ) 1) volume :=
        MeasureTheory.integrableOn_const h_Ioo_finite
      have h_sqrt_int : MeasureTheory.IntegrableOn
          (fun ε => Real.sqrt d * Real.sqrt (-Real.log ε)) (Set.Ioo (0 : ℝ) 1) volume := by
        apply MeasureTheory.Integrable.const_mul
        exact integrableOn_sqrt_neg_log
      have h_rhs_int : MeasureTheory.IntegrableOn
          (fun ε => Real.sqrt d * (Real.sqrt (Real.log (1 + 2 * δ)) + Real.sqrt (-Real.log ε)))
          (Set.Ioo (0 : ℝ) 1) volume := by
        simp_rw [mul_add]
        exact MeasureTheory.Integrable.add h_const_int h_sqrt_int
      apply MeasureTheory.Integrable.mono' h_rhs_int
      · exact (measurable_sqrt_d_log_one_plus_c_div d (2 * δ)).aestronglyMeasurable
      · filter_upwards [MeasureTheory.ae_restrict_mem measurableSet_Ioo] with ε hε
        rw [Real.norm_eq_abs, abs_of_nonneg (Real.sqrt_nonneg _)]
        exact h_pointwise ε hε
    · -- Case D > 1: split into (0, 1] and [1, D]
      push_neg at hD1
      rw [← Set.Ioc_union_Ioc_eq_Ioc (by linarith : (0 : ℝ) ≤ 1) (le_of_lt hD1)]
      apply MeasureTheory.IntegrableOn.union
      · -- Integrable on (0, 1]: same argument as above
        rw [integrableOn_Ioc_iff_integrableOn_Ioo]
        -- Pointwise bound: √(d * log(1 + 2δ/ε)) ≤ √d * (√(log(1+2δ)) + √(-log ε))
        have h_pointwise : ∀ ε ∈ Set.Ioo (0 : ℝ) 1,
            Real.sqrt (d * Real.log (1 + 2 * δ / ε)) ≤
            Real.sqrt d * (Real.sqrt (Real.log (1 + 2 * δ)) + Real.sqrt (-Real.log ε)) := by
          intro ε ⟨hε_pos, hε_lt⟩
          have h_log_bound := log_one_plus_two_delta_div_eps_bound hδ hε_pos hε_lt
          have h_log12δ_nonneg : 0 ≤ Real.log (1 + 2 * δ) := Real.log_nonneg (by linarith)
          have h_neglog_nonneg : 0 ≤ -Real.log ε := by
            rw [neg_nonneg]; exact Real.log_nonpos (le_of_lt hε_pos) (le_of_lt hε_lt)
          calc Real.sqrt (d * Real.log (1 + 2 * δ / ε))
              ≤ Real.sqrt (d * (Real.log (1 + 2 * δ) - Real.log ε)) := by
                apply Real.sqrt_le_sqrt
                apply mul_le_mul_of_nonneg_left h_log_bound (Nat.cast_nonneg d)
              _ = Real.sqrt (d * (Real.log (1 + 2 * δ) + (-Real.log ε))) := by ring_nf
              _ ≤ Real.sqrt (d * Real.log (1 + 2 * δ)) + Real.sqrt (d * (-Real.log ε)) := by
                rw [mul_add]
                exact sqrt_add_le (by positivity) (by positivity)
              _ = Real.sqrt d * Real.sqrt (Real.log (1 + 2 * δ)) +
                  Real.sqrt d * Real.sqrt (-Real.log ε) := by
                rw [Real.sqrt_mul (Nat.cast_nonneg d), Real.sqrt_mul (Nat.cast_nonneg d)]
              _ = Real.sqrt d * (Real.sqrt (Real.log (1 + 2 * δ)) + Real.sqrt (-Real.log ε)) := by ring
        -- Establish integrability of the bounding function
        have h_Ioo_finite : volume (Set.Ioo (0 : ℝ) 1) ≠ ⊤ := by
          rw [Real.volume_Ioo]; exact ENNReal.ofReal_ne_top
        have h_const_int : MeasureTheory.IntegrableOn
            (fun _ : ℝ => Real.sqrt d * Real.sqrt (Real.log (1 + 2 * δ)))
            (Set.Ioo (0 : ℝ) 1) volume :=
          MeasureTheory.integrableOn_const h_Ioo_finite
        have h_sqrt_int : MeasureTheory.IntegrableOn
            (fun ε => Real.sqrt d * Real.sqrt (-Real.log ε)) (Set.Ioo (0 : ℝ) 1) volume := by
          apply MeasureTheory.Integrable.const_mul
          exact integrableOn_sqrt_neg_log
        have h_rhs_int : MeasureTheory.IntegrableOn
            (fun ε => Real.sqrt d * (Real.sqrt (Real.log (1 + 2 * δ)) + Real.sqrt (-Real.log ε)))
            (Set.Ioo (0 : ℝ) 1) volume := by
          simp_rw [mul_add]
          exact MeasureTheory.Integrable.add h_const_int h_sqrt_int
        apply MeasureTheory.Integrable.mono' h_rhs_int
        · exact (measurable_sqrt_d_log_one_plus_c_div d (2 * δ)).aestronglyMeasurable
        · filter_upwards [MeasureTheory.ae_restrict_mem measurableSet_Ioo] with ε hε
          rw [Real.norm_eq_abs, abs_of_nonneg (Real.sqrt_nonneg _)]
          exact h_pointwise ε hε
      · -- Integrable on (1, D]: continuous on compact [1, D] implies integrable on Ioc 1 D
        apply MeasureTheory.IntegrableOn.mono_set
        · -- Show continuous on [1, D] hence integrable on [1, D]
          have hcont_1D : ContinuousOn (fun ε : ℝ => Real.sqrt (d * Real.log (1 + 2 * δ / ε)))
              (Set.Icc 1 D) := by
            apply ContinuousOn.sqrt
            apply ContinuousOn.mul continuousOn_const
            apply Real.continuousOn_log.comp
            · apply ContinuousOn.add continuousOn_const
              apply ContinuousOn.div continuousOn_const continuousOn_id
              intro ε hε
              have h1 : 1 ≤ ε := hε.1
              simp only [id, ne_eq]
              linarith
            · intro ε hε
              have h1 : 1 ≤ ε := hε.1
              have h2 : 0 < 2 * δ / ε := by positivity
              simp only [Set.mem_compl_iff, Set.mem_singleton_iff]
              linarith
          exact hcont_1D.integrableOn_Icc
        · exact Set.Ioc_subset_Icc_self
  -- Convert ENNReal.toReal of lintegral
  apply ENNReal.toReal_le_of_le_ofReal
  · apply MeasureTheory.setIntegral_nonneg measurableSet_Ioc
    intro ε hε
    exact hnn ε hε
  calc (∫⁻ ε in Set.Ioc (0 : ℝ) D, dudleyIntegrand ε (linearLocalizedBallImage n d δ x))
      ≤ ∫⁻ ε in Set.Ioc (0 : ℝ) D, ENNReal.ofReal (Real.sqrt (d * Real.log (1 + 2 * δ / ε))) := hmono
    _ = ENNReal.ofReal (∫ ε in Set.Ioc (0 : ℝ) D, Real.sqrt (d * Real.log (1 + 2 * δ / ε))) := by
        rw [← MeasureTheory.ofReal_integral_eq_lintegral_ofReal]
        · exact hint
        · apply MeasureTheory.ae_of_all
          intro ε
          exact Real.sqrt_nonneg _

/-- The main entropy integral bound for linear regression.
    Using D = 2δ (diameter bound from diam_linearLocalizedBallImage_le),
    the entropy integral is bounded by a constant times δ√d.

    This bound follows from:
    1. linearEntropyIntegral_le_explicit: bound by ∫₀^{2δ} √(d·log(1+2δ/ε)) dε
    2. Change of variables ε = 2δu: = 2δ · ∫₀^1 √(d·log(1+1/u)) du
    3. Comparison with ∫₀^1 √(d·log(1+2/u)) du (since log(1+1/u) ≤ log(1+2/u))
    4. Factor out √d and use integral_constant_lt_two -/
theorem linearEntropyIntegral_le (hn : 0 < n) (hd : 0 < d)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ : ℝ} (hδ : 0 < δ)
    (hinj : Function.Injective (designMatrixMul x)) :
    linearEntropyIntegral n d δ (2*δ) x < 4 * δ * Real.sqrt d := by
  have hD : 0 < 2 * δ := by linarith
  have hDδ : 2 * δ ≤ 2 * δ := le_refl _
  -- Step 1: Apply linearEntropyIntegral_le_explicit
  have h1 := linearEntropyIntegral_le_explicit hn hd x hδ hDδ hinj
  -- Step 2: Convert set integral to interval integral
  have h2 : ∫ ε in Set.Ioc 0 (2*δ), Real.sqrt (d * Real.log (1 + 2 * δ / ε)) =
      ∫ ε in (0 : ℝ)..(2*δ), Real.sqrt (d * Real.log (1 + 2 * δ / ε)) := by
    rw [intervalIntegral.integral_of_le (by linarith : (0 : ℝ) ≤ 2 * δ)]
  -- Step 3: Change of variables ε = 2δu
  have h3 : ∫ ε in (0 : ℝ)..(2*δ), Real.sqrt (d * Real.log (1 + 2 * δ / ε)) =
      (2*δ) * ∫ u in (0 : ℝ)..1, Real.sqrt (d * Real.log (1 + 2 * δ / ((2*δ) * u))) := by
    have := @intervalIntegral.mul_integral_comp_mul_left 0 1
        (fun ε => Real.sqrt (d * Real.log (1 + 2 * δ / ε))) (2*δ)
    simp only [mul_zero, mul_one] at this
    exact this.symm
  -- Step 4: Simplify 2δ/(2δu) = 1/u for u > 0
  have h4 : ∀ u ∈ Set.Ioo (0 : ℝ) 1,
      Real.sqrt (d * Real.log (1 + 2 * δ / ((2*δ) * u))) =
      Real.sqrt (d * Real.log (1 + 1 / u)) := by
    intro u ⟨hu_pos, _⟩
    have h2δ_ne : (2 : ℝ) * δ ≠ 0 := by linarith
    congr 2
    rw [div_mul_eq_div_div, div_self h2δ_ne, one_div]
  have h4' : ∫ u in (0 : ℝ)..1, Real.sqrt (d * Real.log (1 + 2 * δ / ((2*δ) * u))) =
      ∫ u in (0 : ℝ)..1, Real.sqrt (d * Real.log (1 + 1 / u)) := by
    rw [intervalIntegral.integral_of_le (by norm_num : (0 : ℝ) ≤ 1)]
    rw [intervalIntegral.integral_of_le (by norm_num : (0 : ℝ) ≤ 1)]
    apply MeasureTheory.setIntegral_congr_fun measurableSet_Ioc
    intro u hu
    cases' (lt_or_eq_of_le hu.2) with h h
    · -- Case u < 1: use h4
      exact h4 u ⟨hu.1, h⟩
    · -- Case u = 1: prove directly that both sides equal √(d * log 2)
      subst h
      simp only [mul_one, div_one]
      have h2δ_ne : (2 : ℝ) * δ ≠ 0 := by linarith
      rw [div_self h2δ_ne]
  -- Step 5: Bound log(1+1/u) ≤ log(1+2/u)
  have h5 : ∀ u ∈ Set.Ioo (0 : ℝ) 1,
      Real.sqrt (d * Real.log (1 + 1 / u)) ≤ Real.sqrt (d * Real.log (1 + 2 / u)) := by
    intro u ⟨hu_pos, hu_lt⟩
    apply Real.sqrt_le_sqrt
    apply mul_le_mul_of_nonneg_left _ (Nat.cast_nonneg d)
    apply Real.log_le_log
    · have : 0 < 1 / u := by positivity
      linarith
    · have h1 : 1 / u ≤ 2 / u := by
        apply div_le_div_of_nonneg_right _ (le_of_lt hu_pos)
        norm_num
      linarith
  -- Step 6: Bound the integral using integral_constant_lt_two
  have h6 : ∫ u in (0 : ℝ)..1, Real.sqrt (d * Real.log (1 + 2 / u)) =
      Real.sqrt d * ∫ u in (0 : ℝ)..1, Real.sqrt (Real.log (1 + 2 / u)) := by
    rw [← intervalIntegral.integral_const_mul]
    apply intervalIntegral.integral_congr
    intro u _
    show Real.sqrt (d * Real.log (1 + 2 / u)) = Real.sqrt d * Real.sqrt (Real.log (1 + 2 / u))
    rw [Real.sqrt_mul (Nat.cast_nonneg d)]
  have h7 : ∫ u in (0 : ℝ)..1, Real.sqrt (Real.log (1 + 2 / u)) < 2 := integral_constant_lt_two
  -- Combine all the bounds
  calc linearEntropyIntegral n d δ (2*δ) x
      ≤ ∫ ε in Set.Ioc 0 (2*δ), Real.sqrt (d * Real.log (1 + 2 * δ / ε)) := h1
    _ = ∫ ε in (0 : ℝ)..(2*δ), Real.sqrt (d * Real.log (1 + 2 * δ / ε)) := h2
    _ = (2*δ) * ∫ u in (0 : ℝ)..1, Real.sqrt (d * Real.log (1 + 2 * δ / ((2*δ) * u))) := h3
    _ = (2*δ) * ∫ u in (0 : ℝ)..1, Real.sqrt (d * Real.log (1 + 1 / u)) := by rw [h4']
    _ ≤ (2*δ) * ∫ u in (0 : ℝ)..1, Real.sqrt (d * Real.log (1 + 2 / u)) := by
        apply mul_le_mul_of_nonneg_left _ (by linarith)
        rw [intervalIntegral.integral_of_le (by norm_num : (0 : ℝ) ≤ 1)]
        rw [intervalIntegral.integral_of_le (by norm_num : (0 : ℝ) ≤ 1)]
        apply MeasureTheory.setIntegral_mono_on
        · -- Integrability of √(d·log(1+1/u)) on (0,1]
          rw [integrableOn_Ioc_iff_integrableOn_Ioo]
          apply MeasureTheory.Integrable.mono' (integrableOn_sqrt_d_times_bound d)
          · exact (measurable_sqrt_d_log_one_plus_c_div d 1).aestronglyMeasurable
          · filter_upwards [MeasureTheory.ae_restrict_mem measurableSet_Ioo] with u hu
            rw [Real.norm_eq_abs, abs_of_nonneg (Real.sqrt_nonneg _)]
            calc Real.sqrt (d * Real.log (1 + 1 / u))
                ≤ Real.sqrt (d * Real.log (1 + 2 / u)) := h5 u hu
              _ ≤ Real.sqrt d * (Real.sqrt (Real.log 3) + Real.sqrt (-Real.log u)) := by
                  rw [Real.sqrt_mul (Nat.cast_nonneg d)]
                  exact mul_le_mul_of_nonneg_left (sqrt_log_one_plus_two_div_bound hu)
                    (Real.sqrt_nonneg d)
        · -- Integrability of √(d·log(1+2/u)) on (0,1]
          rw [integrableOn_Ioc_iff_integrableOn_Ioo]
          apply MeasureTheory.Integrable.mono' (integrableOn_sqrt_d_times_bound d)
          · exact (measurable_sqrt_d_log_one_plus_c_div d 2).aestronglyMeasurable
          · filter_upwards [MeasureTheory.ae_restrict_mem measurableSet_Ioo] with u hu
            rw [Real.norm_eq_abs, abs_of_nonneg (Real.sqrt_nonneg _),
                Real.sqrt_mul (Nat.cast_nonneg d)]
            exact mul_le_mul_of_nonneg_left (sqrt_log_one_plus_two_div_bound hu)
              (Real.sqrt_nonneg d)
        · exact measurableSet_Ioc
        · intro u hu
          cases' (lt_or_eq_of_le hu.2) with h h
          · -- Case u < 1: use h5
            exact h5 u ⟨hu.1, h⟩
          · -- Case u = 1: prove directly √(d * log 2) ≤ √(d * log 3)
            subst h
            simp only [div_one]
            norm_num only
            apply Real.sqrt_le_sqrt
            apply mul_le_mul_of_nonneg_left _ (Nat.cast_nonneg d)
            apply Real.log_le_log (by norm_num : (0 : ℝ) < 2) (by norm_num : (2 : ℝ) ≤ 3)
    _ = (2*δ) * (Real.sqrt d * ∫ u in (0 : ℝ)..1, Real.sqrt (Real.log (1 + 2 / u))) := by rw [h6]
    _ < (2*δ) * (Real.sqrt d * 2) := by
        apply mul_lt_mul_of_pos_left _ hD
        apply mul_lt_mul_of_pos_left h7 (Real.sqrt_pos.mpr (Nat.cast_pos.mpr hd))
    _ = 4 * δ * Real.sqrt d := by ring

/-- The linearLocalizedBallImage equals the empiricalMetricImage of the localizedBall
    for the linear predictor class. This is the key lemma connecting the two formulations. -/
lemma linearLocalizedBallImage_eq_empiricalImage (x : Fin n → EuclideanSpace ℝ (Fin d)) (δ : ℝ) :
    linearLocalizedBallImage n d δ x =
    empiricalMetricImage n x '' localizedBall (linearPredictorClass d) δ x := by
  unfold linearLocalizedBallImage linearLocalizedBall
  rfl

/-- Integrability of the explicit entropy bound function. -/
lemma linearEntropyIntegral_integrableOn {δ D : ℝ} (hδ : 0 < δ) (hDδ : D ≤ 2 * δ) :
    MeasureTheory.IntegrableOn
      (fun ε => Real.sqrt (d * Real.log (1 + 2 * δ / ε))) (Set.Ioc 0 D) := by
  -- Handle degenerate case D ≤ 0
  by_cases hD_pos : 0 < D
  case neg =>
    push_neg at hD_pos
    have hempty : Set.Ioc 0 D = ∅ := Set.Ioc_eq_empty (not_lt.mpr hD_pos)
    rw [hempty]
    exact MeasureTheory.integrableOn_empty
  case pos =>
    -- Split into cases based on whether D ≤ 1
    by_cases hD_le_one : D ≤ 1
    · -- Case D ≤ 1: bound by √d * (√(log(1+2δ)) + √(-log u)), which is integrable
      rw [integrableOn_Ioc_iff_integrableOn_Ioo]
      -- The constant part and √(-log u) part are both integrable on (0, D]
      have hlog_1_2d_nonneg : 0 ≤ Real.log (1 + 2 * δ) := Real.log_nonneg (by linarith)
      have hfin : volume (Set.Ioo 0 D) ≠ ⊤ := by rw [Real.volume_Ioo]; exact ENNReal.ofReal_ne_top
      have hint_const : MeasureTheory.IntegrableOn
          (fun _ : ℝ => Real.sqrt d * Real.sqrt (Real.log (1 + 2 * δ)))
          (Set.Ioo 0 D) volume :=
        MeasureTheory.integrableOn_const hfin
      have hint_sqrt : MeasureTheory.IntegrableOn
          (fun u => Real.sqrt d * Real.sqrt (-Real.log u)) (Set.Ioo 0 D) volume := by
        apply MeasureTheory.IntegrableOn.mono_set _ (Set.Ioo_subset_Ioo_right hD_le_one)
        exact (MeasureTheory.Integrable.const_mul integrableOn_sqrt_neg_log (Real.sqrt d))
      have hint_sum : MeasureTheory.IntegrableOn
          (fun u => Real.sqrt d * (Real.sqrt (Real.log (1 + 2 * δ)) + Real.sqrt (-Real.log u)))
          (Set.Ioo 0 D) volume := by
        simp_rw [mul_add]
        exact MeasureTheory.Integrable.add hint_const hint_sqrt
      apply MeasureTheory.Integrable.mono' hint_sum
      · exact (measurable_sqrt_d_log_one_plus_c_div d (2 * δ)).aestronglyMeasurable
      · filter_upwards [MeasureTheory.ae_restrict_mem measurableSet_Ioo] with u hu
        rw [Real.norm_eq_abs, abs_of_nonneg (Real.sqrt_nonneg _),
            Real.sqrt_mul (Nat.cast_nonneg d)]
        apply mul_le_mul_of_nonneg_left _ (Real.sqrt_nonneg d)
        have hu_pos : 0 < u := hu.1
        have hu_lt : u < D := hu.2
        have hu_lt_one : u < 1 := lt_of_lt_of_le hu_lt hD_le_one
        have h_term_pos : 0 < 1 + 2 * δ / u := by
          have : 0 < 2 * δ / u := div_pos (by linarith) hu_pos
          linarith
        have hlog_bound : Real.log (1 + 2 * δ / u) ≤ Real.log (1 + 2 * δ) + (-Real.log u) := by
          have h1 : Real.log (1 + 2 * δ / u) ≤ Real.log ((1 + 2 * δ) / u) := by
            apply Real.log_le_log h_term_pos
            rw [add_div]
            have h_one_le : 1 ≤ 1 / u := one_le_one_div hu_pos (le_of_lt hu_lt_one)
            linarith
          rw [Real.log_div (by linarith : (1 : ℝ) + 2 * δ ≠ 0) (ne_of_gt hu_pos)] at h1
          linarith
        have hneg_log_nonneg : 0 ≤ -Real.log u := by
          rw [neg_nonneg]; exact Real.log_nonpos (le_of_lt hu_pos) (le_of_lt hu_lt_one)
        calc Real.sqrt (Real.log (1 + 2 * δ / u))
            ≤ Real.sqrt (Real.log (1 + 2 * δ) + (-Real.log u)) := Real.sqrt_le_sqrt hlog_bound
          _ ≤ Real.sqrt (Real.log (1 + 2 * δ)) + Real.sqrt (-Real.log u) :=
              sqrt_add_le hlog_1_2d_nonneg hneg_log_nonneg
    · -- Case D > 1: Split into (0, 1] and (1, D]
      push_neg at hD_le_one
      rw [← Set.Ioc_union_Ioc_eq_Ioc (by linarith : (0 : ℝ) ≤ 1) (le_of_lt hD_le_one)]
      apply MeasureTheory.IntegrableOn.union
      · -- (0, 1]: same bound as D ≤ 1 case
        rw [integrableOn_Ioc_iff_integrableOn_Ioo]
        have hlog_1_2d_nonneg : 0 ≤ Real.log (1 + 2 * δ) := Real.log_nonneg (by linarith)
        have hfin : volume (Set.Ioo (0:ℝ) 1) ≠ ⊤ := by rw [Real.volume_Ioo]; exact ENNReal.ofReal_ne_top
        have hint_const : MeasureTheory.IntegrableOn
            (fun _ : ℝ => Real.sqrt d * Real.sqrt (Real.log (1 + 2 * δ)))
            (Set.Ioo 0 1) volume :=
          MeasureTheory.integrableOn_const hfin
        have hint_sqrt : MeasureTheory.IntegrableOn
            (fun u => Real.sqrt d * Real.sqrt (-Real.log u)) (Set.Ioo 0 1) volume :=
          (MeasureTheory.Integrable.const_mul integrableOn_sqrt_neg_log (Real.sqrt d))
        have hint_sum : MeasureTheory.IntegrableOn
            (fun u => Real.sqrt d * (Real.sqrt (Real.log (1 + 2 * δ)) + Real.sqrt (-Real.log u)))
            (Set.Ioo 0 1) volume := by
          simp_rw [mul_add]
          exact MeasureTheory.Integrable.add hint_const hint_sqrt
        apply MeasureTheory.Integrable.mono' hint_sum
        · exact (measurable_sqrt_d_log_one_plus_c_div d (2 * δ)).aestronglyMeasurable
        · filter_upwards [MeasureTheory.ae_restrict_mem measurableSet_Ioo] with u hu
          rw [Real.norm_eq_abs, abs_of_nonneg (Real.sqrt_nonneg _),
              Real.sqrt_mul (Nat.cast_nonneg d)]
          apply mul_le_mul_of_nonneg_left _ (Real.sqrt_nonneg d)
          have hu_pos : 0 < u := hu.1
          have hu_lt : u < 1 := hu.2
          have h_term_pos : 0 < 1 + 2 * δ / u := by
            have : 0 < 2 * δ / u := div_pos (by linarith) hu_pos
            linarith
          have hlog_bound : Real.log (1 + 2 * δ / u) ≤ Real.log (1 + 2 * δ) + (-Real.log u) := by
            have h1 : Real.log (1 + 2 * δ / u) ≤ Real.log ((1 + 2 * δ) / u) := by
              apply Real.log_le_log h_term_pos
              rw [add_div]
              have h_one_le : 1 ≤ 1 / u := one_le_one_div hu_pos (le_of_lt hu_lt)
              linarith
            rw [Real.log_div (by linarith : (1 : ℝ) + 2 * δ ≠ 0) (ne_of_gt hu_pos)] at h1
            linarith
          have hneg_log_nonneg : 0 ≤ -Real.log u := by
            rw [neg_nonneg]; exact Real.log_nonpos (le_of_lt hu_pos) (le_of_lt hu_lt)
          calc Real.sqrt (Real.log (1 + 2 * δ / u))
              ≤ Real.sqrt (Real.log (1 + 2 * δ) + (-Real.log u)) := Real.sqrt_le_sqrt hlog_bound
            _ ≤ Real.sqrt (Real.log (1 + 2 * δ)) + Real.sqrt (-Real.log u) :=
                sqrt_add_le hlog_1_2d_nonneg hneg_log_nonneg
      · -- (1, D]: bounded by constant √(d * log(1 + 2δ))
        have hD_finite : volume (Set.Ioc 1 D) ≠ ⊤ := by
          rw [Real.volume_Ioc]; exact ENNReal.ofReal_ne_top
        have hint_const : MeasureTheory.IntegrableOn
            (fun _ : ℝ => Real.sqrt (d * Real.log (1 + 2 * δ)))
            (Set.Ioc 1 D) volume :=
          MeasureTheory.integrableOn_const hD_finite
        apply MeasureTheory.Integrable.mono' hint_const
        · exact (measurable_sqrt_d_log_one_plus_c_div d (2 * δ)).aestronglyMeasurable
        · filter_upwards [MeasureTheory.ae_restrict_mem measurableSet_Ioc] with u hu
          rw [Real.norm_eq_abs, abs_of_nonneg (Real.sqrt_nonneg _)]
          have hu_ge : 1 ≤ u := le_of_lt hu.1
          have h_term_pos : 0 < 1 + 2 * δ / u := by
            have : 0 < 2 * δ / u := div_pos (by linarith) (lt_of_lt_of_le (by linarith : (0:ℝ) < 1) hu_ge)
            linarith
          apply Real.sqrt_le_sqrt
          apply mul_le_mul_of_nonneg_left _ (Nat.cast_nonneg d)
          apply Real.log_le_log h_term_pos
          have : 2 * δ / u ≤ 2 * δ := div_le_self (by linarith) hu_ge
          linarith

/-- The entropy integral ENNReal for linear regression is finite.
    This uses the fact that linearEntropyIntegral has an explicit finite bound. -/
lemma linearEntropyIntegralENNReal_ne_top (hn : 0 < n) (hd : 0 < d)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ : ℝ} (hδ : 0 < δ)
    (hinj : Function.Injective (designMatrixMul x)) :
    entropyIntegralENNReal (linearLocalizedBallImage n d δ x) (2*δ) ≠ ⊤ := by
  -- The dudleyIntegrand is bounded pointwise
  have hbound_dudley : ∀ ε ∈ Set.Ioc (0 : ℝ) (2*δ),
      dudleyIntegrand ε (linearLocalizedBallImage n d δ x) ≤
      ENNReal.ofReal (Real.sqrt (d * Real.log (1 + 2 * δ / ε))) := fun ε hε =>
    dudleyIntegrand_linearLocalizedBall_le hn hd x hε.1 hδ hinj
  -- The explicit bound function is integrable (from linearEntropyIntegral_le_explicit proof)
  have hDδ : 2 * δ ≤ 2 * δ := le_refl _
  have hint := linearEntropyIntegral_integrableOn (d := d) hδ hDδ
  -- Bound the lintegral
  have hlt : ∫⁻ ε in Set.Ioc (0 : ℝ) (2*δ),
      dudleyIntegrand ε (linearLocalizedBallImage n d δ x) < ⊤ := by
    calc ∫⁻ ε in Set.Ioc (0 : ℝ) (2*δ), dudleyIntegrand ε (linearLocalizedBallImage n d δ x)
        ≤ ∫⁻ ε in Set.Ioc (0 : ℝ) (2*δ),
            ENNReal.ofReal (Real.sqrt (d * Real.log (1 + 2 * δ / ε))) := by
          apply MeasureTheory.setLIntegral_mono
          · exact (ENNReal.measurable_ofReal.comp (measurable_sqrt_d_log_one_plus_c_div d (2*δ)))
          · intro ε hε
            exact hbound_dudley ε hε
      _ = ENNReal.ofReal (∫ ε in Set.Ioc (0 : ℝ) (2*δ),
            Real.sqrt (d * Real.log (1 + 2 * δ / ε))) := by
          rw [← MeasureTheory.ofReal_integral_eq_lintegral_ofReal hint]
          exact MeasureTheory.ae_of_all _ (fun _ => Real.sqrt_nonneg _)
      _ < ⊤ := ENNReal.ofReal_lt_top
  exact ne_top_of_lt hlt

/-! ### Rank-based Entropy Bounds

These lemmas generalize the entropy bounds from requiring full rank (hinj) to only requiring
that the design matrix has positive rank. The bounds use `designMatrixRank x` instead of `d`. -/

/-- The metric entropy of the linear localized ball is bounded by r * log(1 + 2δ/ε)
    where r = designMatrixRank x. This follows from the covering number bound N(ε, s) ≤ (1 + 2δ/ε)^r. -/
lemma metricEntropy_linearLocalizedBall_rank_le (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {ε δ : ℝ} (hε : 0 < ε) (hδ : 0 < δ)
    (hr : 0 < designMatrixRank x) :
    metricEntropy ε (linearLocalizedBallImage n d δ x) ≤
    (designMatrixRank x) * Real.log (1 + 2 * δ / ε) := by
  -- Step 1: Get bounds on the covering number
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have hsqrt_pos : 0 < Real.sqrt n := Real.sqrt_pos.mpr hn_pos
  have hε_scaled : 0 < ε * Real.sqrt n := mul_pos hε hsqrt_pos
  have hδ_nonneg : 0 ≤ δ := le_of_lt hδ
  -- Step 2: Use linearCoveringNumber_le_euclideanBall_rank
  have hcov_lin := linearCoveringNumber_le_euclideanBall_rank (s := ε) (δ := δ) hn x hr
  -- Step 3: Get the Euclidean ball covering number bound (need Nonempty Fin r)
  haveI : Nonempty (Fin (designMatrixRank x)) := Fin.pos_iff_nonempty.mp hr
  have hball_bound := coveringNumber_euclideanBall_le (ι := Fin (designMatrixRank x))
    (mul_nonneg hδ_nonneg (le_of_lt hsqrt_pos)) hε_scaled
  -- Step 4: The RHS simplifies because (δ√n)/(ε√n) = δ/ε
  have h_simp : 1 + 2 * (δ * Real.sqrt n) / (ε * Real.sqrt n) = 1 + 2 * δ / ε := by
    have hsqrt_ne : Real.sqrt n ≠ 0 := ne_of_gt hsqrt_pos
    field_simp
  simp only [Fintype.card_fin] at hball_bound
  rw [h_simp] at hball_bound
  -- Step 5: Extract natural numbers from covering numbers and apply log bound
  unfold metricEntropy linearCoveringNumber at *
  have htb : TotallyBounded (linearLocalizedBallImage n d δ x) :=
    linearLocalizedBallImage_totallyBounded hn x δ
  have hfin : coveringNumber ε (linearLocalizedBallImage n d δ x) < ⊤ :=
    coveringNumber_lt_top_of_totallyBounded hε htb
  -- Get the natural number value
  split
  · -- Case: coveringNumber = ⊤ (contradicts hfin)
    rename_i heq
    rw [heq] at hfin
    exact absurd rfl (ne_of_lt hfin)
  · rename_i m hm
    -- m = coveringNumber ε (linearLocalizedBallImage)
    -- Need to show: metricEntropyOfNat m ≤ r * log(1 + 2δ/ε)
    -- The covering number of euclideanBall is finite
    have htb_ball : TotallyBounded (euclideanBall (δ * Real.sqrt n) : Set (EuclideanSpace ℝ (Fin (designMatrixRank x)))) :=
      euclideanBall_totallyBounded _
    have hfin_ball : coveringNumber (ε * Real.sqrt n) (euclideanBall (δ * Real.sqrt n) : Set (EuclideanSpace ℝ (Fin (designMatrixRank x)))) < ⊤ :=
      coveringNumber_lt_top_of_totallyBounded hε_scaled htb_ball
    have hne_ball : coveringNumber (ε * Real.sqrt n) (euclideanBall (δ * Real.sqrt n) : Set (EuclideanSpace ℝ (Fin (designMatrixRank x)))) ≠ ⊤ :=
      ne_top_of_lt hfin_ball
    -- Extract natural number from ball covering number
    let m_ball := (coveringNumber (ε * Real.sqrt n) (euclideanBall (δ * Real.sqrt n) : Set (EuclideanSpace ℝ (Fin (designMatrixRank x))))).untop hne_ball
    have hm_ball_eq : coveringNumber (ε * Real.sqrt n) (euclideanBall (δ * Real.sqrt n) : Set (EuclideanSpace ℝ (Fin (designMatrixRank x)))) = m_ball :=
      (WithTop.coe_untop _ hne_ball).symm
    -- m ≤ m_ball (using that euclideanBall = Metric.closedBall 0)
    have hm_le_ball : m ≤ m_ball := by
      rw [hm, hm_ball_eq] at hcov_lin
      exact WithTop.coe_le_coe.mp hcov_lin
    -- m_ball ≤ (1 + 2δ/ε)^r from hball_bound
    have hball_le : (m_ball : ℝ) ≤ (1 + 2 * δ / ε) ^ (designMatrixRank x) := by
      convert hball_bound using 2
    -- m ≤ (1 + 2δ/ε)^r
    have hm_le : (m : ℝ) ≤ (1 + 2 * δ / ε) ^ (designMatrixRank x) := le_trans (Nat.cast_le.mpr hm_le_ball) hball_le
    -- Use metricEntropyOfNat_le_log
    have hN_pos : 1 < (1 + 2 * δ / ε) ^ (designMatrixRank x) := by
      have hbase : 1 < 1 + 2 * δ / ε := by
        have : 0 < 2 * δ / ε := by positivity
        linarith
      have hr_ne : designMatrixRank x ≠ 0 := Nat.pos_iff_ne_zero.mp hr
      exact one_lt_pow₀ hbase hr_ne
    calc metricEntropyOfNat m
        ≤ Real.log ((1 + 2 * δ / ε) ^ (designMatrixRank x)) := metricEntropyOfNat_le_log hN_pos hm_le
      _ = (designMatrixRank x) * Real.log (1 + 2 * δ / ε) := by rw [Real.log_pow]

/-- The square root entropy bound using rank. -/
lemma sqrtEntropy_linearLocalizedBall_rank_le (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {ε δ : ℝ} (hε : 0 < ε) (hδ : 0 < δ)
    (hr : 0 < designMatrixRank x) :
    sqrtEntropy ε (linearLocalizedBallImage n d δ x) ≤
    Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε)) := by
  unfold sqrtEntropy
  apply Real.sqrt_le_sqrt
  exact metricEntropy_linearLocalizedBall_rank_le hn x hε hδ hr

/-- The dudleyIntegrand bound using rank. -/
lemma dudleyIntegrand_linearLocalizedBall_rank_le (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {ε δ : ℝ} (hε : 0 < ε) (hδ : 0 < δ)
    (hr : 0 < designMatrixRank x) :
    dudleyIntegrand ε (linearLocalizedBallImage n d δ x) ≤
    ENNReal.ofReal (Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε))) := by
  unfold dudleyIntegrand
  apply ENNReal.ofReal_le_ofReal
  exact sqrtEntropy_linearLocalizedBall_rank_le hn x hε hδ hr

/-- The main entropy integral bound using rank: ∫₀^{2δ} √(log N) < 4δ√r where r = rank(X).

    This generalizes linearEntropyIntegral_le by replacing hinj (full rank d) with
    the weaker assumption hr : 0 < designMatrixRank x, giving a tighter bound when rank < d. -/
theorem linearEntropyIntegral_rank_le (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ : ℝ} (hδ : 0 < δ)
    (hr : 0 < designMatrixRank x) :
    linearEntropyIntegral n d δ (2*δ) x < 4 * δ * Real.sqrt (designMatrixRank x) := by
  have hD : 0 < 2 * δ := by linarith
  have hDδ : 2 * δ ≤ 2 * δ := le_refl _
  -- Step 1: Apply linearEntropyIntegral_le_explicit analog
  have h1 : linearEntropyIntegral n d δ (2*δ) x ≤
      ∫ ε in Set.Ioc 0 (2*δ), Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε)) := by
    unfold linearEntropyIntegral entropyIntegral entropyIntegralENNReal
    have hbound : ∀ ε ∈ Set.Ioc (0 : ℝ) (2*δ),
        dudleyIntegrand ε (linearLocalizedBallImage n d δ x) ≤
        ENNReal.ofReal (Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε))) := fun ε hε =>
      dudleyIntegrand_linearLocalizedBall_rank_le hn x hε.1 hδ hr
    have hnn : ∀ ε ∈ Set.Ioc (0 : ℝ) (2*δ), 0 ≤ Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε)) :=
      fun _ _ => Real.sqrt_nonneg _
    have hmeas : Measurable (fun ε : ℝ => ENNReal.ofReal (Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε)))) := by
      apply ENNReal.measurable_ofReal.comp
      apply Measurable.sqrt
      apply Measurable.mul measurable_const
      apply Real.measurable_log.comp
      apply Measurable.add measurable_const
      apply Measurable.div measurable_const measurable_id
    have hmono : ∫⁻ ε in Set.Ioc (0 : ℝ) (2*δ), dudleyIntegrand ε (linearLocalizedBallImage n d δ x) ≤
        ∫⁻ ε in Set.Ioc (0 : ℝ) (2*δ), ENNReal.ofReal (Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε))) := by
      apply MeasureTheory.setLIntegral_mono hmeas
      intro ε hε
      exact hbound ε hε
    have hint : MeasureTheory.IntegrableOn
        (fun ε => Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε))) (Set.Ioc 0 (2*δ)) :=
      linearEntropyIntegral_integrableOn (d := designMatrixRank x) hδ hDδ
    apply ENNReal.toReal_le_of_le_ofReal
    · apply MeasureTheory.setIntegral_nonneg measurableSet_Ioc
      intro ε hε
      exact hnn ε hε
    calc (∫⁻ ε in Set.Ioc (0 : ℝ) (2*δ), dudleyIntegrand ε (linearLocalizedBallImage n d δ x))
        ≤ ∫⁻ ε in Set.Ioc (0 : ℝ) (2*δ), ENNReal.ofReal (Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε))) := hmono
      _ = ENNReal.ofReal (∫ ε in Set.Ioc (0 : ℝ) (2*δ), Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε))) := by
          rw [← MeasureTheory.ofReal_integral_eq_lintegral_ofReal]
          · exact hint
          · apply MeasureTheory.ae_of_all
            intro ε
            exact Real.sqrt_nonneg _
  -- Step 2: Convert set integral to interval integral and simplify
  have h2 : ∫ ε in Set.Ioc 0 (2*δ), Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε)) =
      ∫ ε in (0 : ℝ)..(2*δ), Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε)) := by
    rw [intervalIntegral.integral_of_le (by linarith : (0 : ℝ) ≤ 2 * δ)]
  -- Step 3: Change of variables ε = 2δu
  have h3 : ∫ ε in (0 : ℝ)..(2*δ), Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε)) =
      (2*δ) * ∫ u in (0 : ℝ)..1, Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ((2*δ) * u))) := by
    have := @intervalIntegral.mul_integral_comp_mul_left 0 1
        (fun ε => Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε))) (2*δ)
    simp only [mul_zero, mul_one] at this
    exact this.symm
  -- Step 4: Helper lemma for simplification 2δ/(2δu) = 1/u for u > 0
  have h4 : ∀ u ∈ Set.Ioo (0 : ℝ) 1, (fun u => Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ((2*δ) * u)))) u =
      (fun u => Real.sqrt ((designMatrixRank x) * Real.log (1 + 1 / u))) u := by
    intro u ⟨hu_pos, _⟩
    have h2δ_ne : (2 : ℝ) * δ ≠ 0 := by linarith
    simp only
    congr 2
    rw [div_mul_eq_div_div, div_self h2δ_ne, one_div]
  have h4' : ∫ u in (0 : ℝ)..1, Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ((2*δ) * u))) =
      ∫ u in (0 : ℝ)..1, Real.sqrt ((designMatrixRank x) * Real.log (1 + 1 / u)) := by
    rw [intervalIntegral.integral_of_le (by norm_num : (0 : ℝ) ≤ 1)]
    rw [intervalIntegral.integral_of_le (by norm_num : (0 : ℝ) ≤ 1)]
    apply MeasureTheory.setIntegral_congr_fun measurableSet_Ioc
    intro u hu
    cases' (lt_or_eq_of_le hu.2) with h h
    · -- Case u < 1: use h4
      exact h4 u ⟨hu.1, h⟩
    · -- Case u = 1: prove directly that both sides equal √(r * log 2)
      subst h
      simp only [mul_one, div_one]
      have h2δ_ne : (2 : ℝ) * δ ≠ 0 := by linarith
      rw [div_self h2δ_ne]
  -- Step 5: Bound log(1+1/u) ≤ log(1+2/u)
  have h5 : ∀ u ∈ Set.Ioo (0 : ℝ) 1,
      Real.sqrt ((designMatrixRank x) * Real.log (1 + 1 / u)) ≤
      Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 / u)) := by
    intro u ⟨hu_pos, hu_lt⟩
    apply Real.sqrt_le_sqrt
    apply mul_le_mul_of_nonneg_left _ (Nat.cast_nonneg (designMatrixRank x))
    apply Real.log_le_log
    · have : 0 < 1 / u := by positivity
      linarith
    · have h1 : 1 / u ≤ 2 / u := by
        apply div_le_div_of_nonneg_right _ (le_of_lt hu_pos)
        norm_num
      linarith
  -- Step 6: Bound the integral using integral_constant_lt_two
  have h6 : ∫ u in (0 : ℝ)..1, Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 / u)) =
      Real.sqrt (designMatrixRank x) * ∫ u in (0 : ℝ)..1, Real.sqrt (Real.log (1 + 2 / u)) := by
    rw [← intervalIntegral.integral_const_mul]
    apply intervalIntegral.integral_congr
    intro u _
    show Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 / u)) =
        Real.sqrt (designMatrixRank x) * Real.sqrt (Real.log (1 + 2 / u))
    rw [Real.sqrt_mul (Nat.cast_nonneg (designMatrixRank x))]
  have h7 : ∫ u in (0 : ℝ)..1, Real.sqrt (Real.log (1 + 2 / u)) < 2 := integral_constant_lt_two
  -- Step 7: Bound ∫ √(r·log(1+1/u)) ≤ ∫ √(r·log(1+2/u)) = √r · ∫ √(log(1+2/u))
  have h5_bound : ∫ u in (0 : ℝ)..1, Real.sqrt ((designMatrixRank x) * Real.log (1 + 1 / u)) ≤
      ∫ u in (0 : ℝ)..1, Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 / u)) := by
    rw [intervalIntegral.integral_of_le (by norm_num : (0 : ℝ) ≤ 1)]
    rw [intervalIntegral.integral_of_le (by norm_num : (0 : ℝ) ≤ 1)]
    apply MeasureTheory.setIntegral_mono_on
    · -- Integrability of √(r·log(1+1/u)) on (0,1]
      rw [integrableOn_Ioc_iff_integrableOn_Ioo]
      apply MeasureTheory.Integrable.mono' (integrableOn_sqrt_d_times_bound (designMatrixRank x))
      · exact (measurable_sqrt_d_log_one_plus_c_div (designMatrixRank x) 1).aestronglyMeasurable
      · filter_upwards [MeasureTheory.ae_restrict_mem measurableSet_Ioo] with u hu
        rw [Real.norm_eq_abs, abs_of_nonneg (Real.sqrt_nonneg _)]
        calc Real.sqrt ((designMatrixRank x) * Real.log (1 + 1 / u))
            ≤ Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 / u)) := h5 u hu
          _ ≤ Real.sqrt (designMatrixRank x) * (Real.sqrt (Real.log 3) + Real.sqrt (-Real.log u)) := by
              rw [Real.sqrt_mul (Nat.cast_nonneg (designMatrixRank x))]
              exact mul_le_mul_of_nonneg_left (sqrt_log_one_plus_two_div_bound hu)
                (Real.sqrt_nonneg (designMatrixRank x))
    · -- Integrability of √(r·log(1+2/u)) on (0,1]
      rw [integrableOn_Ioc_iff_integrableOn_Ioo]
      apply MeasureTheory.Integrable.mono' (integrableOn_sqrt_d_times_bound (designMatrixRank x))
      · exact (measurable_sqrt_d_log_one_plus_c_div (designMatrixRank x) 2).aestronglyMeasurable
      · filter_upwards [MeasureTheory.ae_restrict_mem measurableSet_Ioo] with u hu
        rw [Real.norm_eq_abs, abs_of_nonneg (Real.sqrt_nonneg _),
            Real.sqrt_mul (Nat.cast_nonneg (designMatrixRank x))]
        exact mul_le_mul_of_nonneg_left (sqrt_log_one_plus_two_div_bound hu)
            (Real.sqrt_nonneg (designMatrixRank x))
    · exact measurableSet_Ioc
    · intro u hu
      cases' (lt_or_eq_of_le hu.2) with h h
      · -- Case u < 1: use h5
        exact h5 u ⟨hu.1, h⟩
      · -- Case u = 1: prove directly √(r * log 2) ≤ √(r * log 3)
        subst h
        simp only [div_one]
        norm_num only
        apply Real.sqrt_le_sqrt
        apply mul_le_mul_of_nonneg_left _ (Nat.cast_nonneg (designMatrixRank x))
        apply Real.log_le_log (by norm_num : (0 : ℝ) < 2) (by norm_num : (2 : ℝ) ≤ 3)
  -- Combine all the bounds
  calc linearEntropyIntegral n d δ (2*δ) x
      ≤ ∫ ε in Set.Ioc 0 (2*δ), Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε)) := h1
    _ = ∫ ε in (0 : ℝ)..(2*δ), Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε)) := h2
    _ = (2*δ) * ∫ u in (0 : ℝ)..1, Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ((2*δ) * u))) := h3
    _ = (2*δ) * ∫ u in (0 : ℝ)..1, Real.sqrt ((designMatrixRank x) * Real.log (1 + 1 / u)) := by rw [h4']
    _ ≤ (2*δ) * ∫ u in (0 : ℝ)..1, Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 / u)) := by
        apply mul_le_mul_of_nonneg_left h5_bound (by linarith)
    _ = (2*δ) * (Real.sqrt (designMatrixRank x) * ∫ u in (0 : ℝ)..1, Real.sqrt (Real.log (1 + 2 / u))) := by rw [h6]
    _ < (2*δ) * (Real.sqrt (designMatrixRank x) * 2) := by
        apply mul_lt_mul_of_pos_left _ hD
        apply mul_lt_mul_of_pos_left h7 (Real.sqrt_pos.mpr (Nat.cast_pos.mpr hr))
    _ = 4 * δ * Real.sqrt (designMatrixRank x) := by ring

/-- The entropy integral ENNReal using rank is finite. -/
lemma linearEntropyIntegralENNReal_rank_ne_top (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ : ℝ} (hδ : 0 < δ)
    (hr : 0 < designMatrixRank x) :
    entropyIntegralENNReal (linearLocalizedBallImage n d δ x) (2*δ) ≠ ⊤ := by
  have hbound_dudley : ∀ ε ∈ Set.Ioc (0 : ℝ) (2*δ),
      dudleyIntegrand ε (linearLocalizedBallImage n d δ x) ≤
      ENNReal.ofReal (Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε))) := fun ε hε =>
    dudleyIntegrand_linearLocalizedBall_rank_le hn x hε.1 hδ hr
  have hDδ : 2 * δ ≤ 2 * δ := le_refl _
  have hint := linearEntropyIntegral_integrableOn (d := designMatrixRank x) hδ hDδ
  have hlt : ∫⁻ ε in Set.Ioc (0 : ℝ) (2*δ),
      dudleyIntegrand ε (linearLocalizedBallImage n d δ x) < ⊤ := by
    calc ∫⁻ ε in Set.Ioc (0 : ℝ) (2*δ), dudleyIntegrand ε (linearLocalizedBallImage n d δ x)
        ≤ ∫⁻ ε in Set.Ioc (0 : ℝ) (2*δ),
            ENNReal.ofReal (Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε))) := by
          apply MeasureTheory.setLIntegral_mono
          · exact (ENNReal.measurable_ofReal.comp (measurable_sqrt_d_log_one_plus_c_div (designMatrixRank x) (2*δ)))
          · intro ε hε
            exact hbound_dudley ε hε
      _ = ENNReal.ofReal (∫ ε in Set.Ioc (0 : ℝ) (2*δ),
            Real.sqrt ((designMatrixRank x) * Real.log (1 + 2 * δ / ε))) := by
          rw [← MeasureTheory.ofReal_integral_eq_lintegral_ofReal hint]
          exact MeasureTheory.ae_of_all _ (fun _ => Real.sqrt_nonneg _)
      _ < ⊤ := ENNReal.ofReal_lt_top
  exact ne_top_of_lt hlt

end LeastSquares

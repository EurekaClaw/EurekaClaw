/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import Mathlib.MeasureTheory.Function.ConvergenceInMeasure

open Filter

namespace MeasureTheory

variable {α E : Type*} {m : MeasurableSpace α} {mu : Measure α}

/-- Convergence in L^1 yields an a.e.-convergent subsequence. -/
theorem exists_seq_tendsto_ae_of_tendsto_eLpNorm_one
    [NormedAddCommGroup E] {f : ℕ → α → E} {g : α → E}
    (hf : ∀ n, AEStronglyMeasurable (f n) mu)
    (hg : AEStronglyMeasurable g mu)
    (hfg : Tendsto (fun n => eLpNorm (f n - g) (1 : ENNReal) mu) atTop (nhds 0)) :
    ∃ ns : ℕ → ℕ, StrictMono ns ∧
      ∀ᵐ x ∂mu, Tendsto (fun i => f (ns i) x) atTop (nhds (g x)) := by
  have h_in_measure : TendstoInMeasure mu f atTop g :=
    tendstoInMeasure_of_tendsto_eLpNorm (p := (1 : ENNReal)) (by simp) hf hg hfg
  exact h_in_measure.exists_seq_tendsto_ae

end MeasureTheory

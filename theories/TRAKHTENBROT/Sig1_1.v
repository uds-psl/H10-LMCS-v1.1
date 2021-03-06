(**************************************************************)
(*   Copyright Dominique Larchey-Wendling [*]                 *)
(*                                                            *)
(*                             [*] Affiliation LORIA -- CNRS  *)
(**************************************************************)
(*      This file is distributed under the terms of the       *)
(*         CeCILL v2 FREE SOFTWARE LICENSE AGREEMENT          *)
(**************************************************************)

Require Import List Arith Bool Lia Eqdep_dec.

From Undecidability.Shared.Libs.DLW.Utils
  Require Import utils_tac utils_list utils_nat finite.

From Undecidability.Shared.Libs.DLW.Vec 
  Require Import pos vec.

From Undecidability.TRAKHTENBROT
  Require Import notations utils fol_ops fo_sig fo_terms fo_logic fo_sat Sig_no_syms.

Import fol_notations.

Set Implicit Arguments.

Local Infix "β" := In (at level 70, no associativity).
Local Infix "β" := incl (at level 70, no associativity). 

(* * Removal of function symbols from full monadic signatures *)

Fixpoint find_non_empty_word X (l : list (list X)) : 
           { s & { w | s::w β l } } 
         + { concat l = nil }.
Proof.
  destruct l as [ | [ | s w ] l ].
  + right; auto.
  + destruct (find_non_empty_word X l) as [ (s & w & H) | H ].
    * left; exists s, w; right; auto.
    * right; simpl; auto.
  + left; exists s, w; left; auto.
Qed.

Local Notation ΓΈ := vec_nil.

Section fot_word_var.

  (* when arity of symbols is 1, terms have the shape s1(s2(...sn(i)...)) 
     where [s1,...,sn] is a list of symbols and i is a variable *)

  Variable (X : Type).

  Implicit Type t : fo_term (fun _ : X => 1).

  Fixpoint fot_var t :=
    match t with
      | in_var i   => i
      | in_fot s v => fot_var (vec_pos v pos0)
    end.

  Fixpoint fot_word t :=
    match t with
      | in_var i   => nil
      | in_fot s v => s::fot_word (vec_pos v pos0)
    end.

  Fixpoint fot_word_var w i : fo_term (fun _ : X => 1) :=
    match w with
      | nil  => in_var i
      | s::w => in_fot s (fot_word_var w i##ΓΈ)
    end.

  Fact fot_word_var_eq t : t = fot_word_var (fot_word t) (fot_var t).
  Proof.
    induction t as [ | s v IH ]; simpl in *; auto; f_equal.
    generalize (IH pos0); clear IH; vec split v with t; vec nil v; clear v; simpl.
    intros; f_equal; auto.
  Qed.

  Fact fot_word_eq w i : fot_word (fot_word_var w i) = w.
  Proof. induction w; simpl; f_equal; auto. Qed.

  Fact fot_var_eq w i : fot_var (fot_word_var w i) = i.
  Proof. induction w; simpl; f_equal; auto. Qed.

End fot_word_var.

Section Ξ£11_words.

  Variable (X Y : Type).

  (* Signatures with arity always 1 for both syms and rels *)

  Definition Ξ£11 : fo_signature.
  Proof.
    exists X Y; intros _.
    + exact 1.
    + exact 1.
  Defined.

  Fixpoint Ξ£11_words (A : fol_form Ξ£11) : list (list X) :=
    match A with 
      | β₯              => nil
      | fol_atom r v   => (fot_word (vec_pos v pos0))::nil
      | fol_bin _ A B  => Ξ£11_words A++Ξ£11_words B
      | fol_quant _ A  => Ξ£11_words A
    end.

End Ξ£11_words.

Section Ξ£full_mon_rem.

  (* The proof of Proposition 6.2.7 (Gradel) of pp 251 in
        "The Classical Decision Problem" 

     cannot be impleted as is. The individual step is ok 
     but the induction does not work because 
          SAT (A /\ C) <-> SAT (B /\ C) 
     is NOT implied by SAT A <-> SAT B !! 

     At least I do not see how the implement the iterative
     process in a sound way ... termination is OK but
     invariants pose problems
  *)

  (* Hence we do the conversion in a single pass !! *)

  Variable (Y : Type) (HY : finite_t Y)
           (n m : nat).

  Notation X := (pos n).

  (* Bounded lists *)

  Let Yw := { w : list X | length w < S m }.

  Let YwY_fin : finite_t (Yw*Y).
  Proof. 
    apply finite_t_prod; auto. 
    apply finite_t_list, finite_t_pos.
  Qed.

  Let lwY := proj1_sig YwY_fin.
  Let HlwY p : p β lwY.
  Proof. apply (proj2_sig YwY_fin). Qed.

  (* The new signature is not finite (list X !!)
      but this of no impact on decidability. However,
      the signature is discrete, if Y is discrete *)

  Notation Ξ£ := (Ξ£11 X Y).
  Notation Ξ£' := (Ξ£11 X (list X*Y + Y)).

  Let f s v := @in_fot _ (ar_syms Ξ£') s v##ΓΈ.
  Let P r v : fol_form Ξ£' := @fol_atom Ξ£' (inr r) v.
  Let Q w r v : fol_form Ξ£' :=  @fol_atom Ξ£' (inl (w,r)) v.

  Arguments f : clear implicits.
  Arguments P : clear implicits.
  Arguments Q : clear implicits.

  (* An atomic formula of Ξ£ as the form r(s1(...(sn(x))))
     and we encode it as the monadic Q_([sn;...;s1],r) (x) 

     To ensure correctness, we have to add the non-simply 
     monadic equations:
     
                  P_r x <-> Q_(nil,r) x 
         and Q_(s::w,r) <-> Q_(w,r) (s x)

     In these, there is still Q_* (s x) which is not
     simply monodic. Later, we skolemize those equations
     to get rid of the compound term (s x)

     Notice that we have to bound n above to ensure that 
     those equations are finitely many
   *)

  Local Fixpoint encode (A : fol_form Ξ£) : fol_form Ξ£' :=
    match A with
      | β₯              => β₯
      | fol_atom r v   => 
        let t := vec_head v in
        let w := fot_word t in
        let x := fot_var  t 
        in  Q (rev w) r (Β£x##ΓΈ)
      | fol_bin b A B => fol_bin b (encode A) (encode B)
      | fol_quant q A => fol_quant q (encode A)
    end.

  Notation Ξ£full_mon_rec := encode.

  (* The reduction function does not map to a signature void of
     functions to simplify the above expression. However, the
     obtained formula is void of any function symbols *)

  Fact Ξ£full_mon_rec_syms A : fol_syms (Ξ£full_mon_rec A) = nil.
  Proof.
    induction A as [ | r v | b A HA B HB | q A HA ].
    1,2,4: simpl; tauto.
    simpl; rewrite HA, HB; auto.
  Qed.

  Variable (A : fol_form Ξ£) (HwA : forall w, w β Ξ£11_words A -> length w < S m).

  (* Equations P_r (Β£0) <-> Q_(nil,r) (Β£0) 
           and Q_(s::w,r) (Β£0) <-> Q_(w,r) (s(Β£0)) *)

  Let Eq (p : Yw * Y) : fol_form Ξ£' :=
    let v := Β£0##ΓΈ in 
    let (w,r) := p in
    let (w,_) := w in
    match w with
      | nil   => Q nil r v β P r v
      | s::w' => Q w' r (f s v) β Q w r v
    end.

  (* The previous equations but skolemized by s(Β£0) <-> Β£(s) *) 

  Let Eq' (p : Yw * Y) := 
    let m := Β£n##ΓΈ  in
    let (w,r) := p  in
    let (w,_) := w  in
    match w with
      | nil   => Q nil r m β P r m
      | s::w' => Q w' r (Β£(pos2nat s)##ΓΈ) β Q w r m
    end.

  (* We first deals with the non-skolemized reduction *)

  Definition Ξ£full_mon_red : fol_form Ξ£' :=
    Ξ£full_mon_rec A β β fol_lconj (map Eq lwY).

  Variable (K : Type).

  (* Interpretation of a list of functions mapped on a value *)

  Let Fixpoint g (M : fo_model Ξ£ K) w x :=
    match w with
      | nil  => x
      | s::w => g M w (fom_syms M s (x##ΓΈ))
    end.

  Let g_app M w1 w2 x : g M (w1++w2) x = g M w2 (g M w1 x).
  Proof. revert x; induction w1; simpl; auto. Qed.

  Let g_snoc M w s x : g M (w++s::nil) x = fom_syms M s (g M w x##ΓΈ).
  Proof. rewrite g_app; auto. Qed.

  Section soundness.

    Variable (M : fo_model Ξ£ K).

    Let M' : fo_model Ξ£' K.
    Proof.
      split.
      + exact (fom_syms M).
      + intros [ (w,r) | r ]; simpl in r |- *.
        * exact (fun v  => fom_rels M r (g M w (vec_head v)##ΓΈ)).
        * exact (fom_rels M r).
    Defined.

    Fact Ξ£full_mon_rec_sound Ο : 
         fol_sem M' Ο (Ξ£full_mon_rec A) <-> fol_sem M Ο A.
    Proof.
      revert Ο HwA; induction A as [ | r v | b B HB C HC | q B HB ]; intros Ο HA.
      + simpl; tauto.
      + simpl in v; unfold Ξ£full_mon_rec.
        revert HA; vec split v with t; vec nil v; clear v; simpl vec_head; simpl syms; intros HA.
        specialize (HA _ (or_introl eq_refl)); simpl in HA |- *.
        replace (fo_term_sem M Ο t) 
        with    (fo_term_sem M Ο (fot_word_var (fot_word t) (fot_var t))).
        * simpl; apply fol_equiv_ext; do 2 f_equal.
          generalize (fot_word t) (fot_var t); clear t HA; intros w.
          induction w as [ | s w IHw ]; simpl; auto; intros i.
          rewrite g_snoc; simpl; do 2 f_equal; auto.
        * f_equal; symmetry; apply fot_word_var_eq.
      + simpl; apply fol_bin_sem_ext.
        * apply HB; intros ? ?; apply HA, in_app_iff; auto.
        * apply HC; intros ? ?; apply HA, in_app_iff; auto.
      + simpl; apply fol_quant_sem_ext; intro; apply HB; auto.
    Qed.

    Variable (Kfin : finite_t K)
             (Mdec : fo_model_dec M)
             (Ο : nat -> K)
             (HA : fol_sem M Ο A).

    Theorem Ξ£full_mon_rem_sound : fo_form_fin_dec_SAT_in Ξ£full_mon_red K.
    Proof.
      exists M', Kfin.
      exists.
      { intros [ (w,r) | r ]; simpl in r |- *; intro; apply Mdec. } 
      exists Ο; simpl; split.
      + apply Ξ£full_mon_rec_sound; auto.
      + intro x; rewrite fol_sem_lconj.
        intros ?; rewrite in_map_iff.
        intros ((([|s w]&Hw),r) & <- & Hr); unfold Eq.
        * simpl; auto.
        * simpl; auto.
    Qed.

  End soundness.

  Section completeness.

    Variable (M' : fo_model Ξ£' K).

    Let M : fo_model Ξ£ K.
    Proof.
      split.
      + exact (fom_syms M').
      + exact (fun r => fom_rels M' (inr r)).
    Defined.

    Section Ξ£full_mon_rec_complete.

      Hypothesis HM1' : forall s w r x, length (s::w) < S m 
                                 -> fom_rels M' (inl (s::w, r)) (x##ΓΈ)
                                <-> fom_rels M' (inl (w, r)) (fom_syms M s (x##ΓΈ)##ΓΈ).
 
      Hypothesis HM2' : forall r x, fom_rels M' (inr r) (x##ΓΈ)
                                <-> fom_rels M' (inl (nil,r)) (x##ΓΈ).

      Let Hf Ο w i : g M (rev w) (Ο i) = fo_term_sem M Ο (fot_word_var w i).
      Proof.
        induction w; simpl; auto.
        rewrite g_snoc; simpl in *; rewrite IHw; auto.
      Qed.

      Fact Ξ£full_mon_rec_complete Ο : 
        fol_sem M' Ο (Ξ£full_mon_rec A) <-> fol_sem M Ο A.
      Proof.
        revert Ο HwA; induction A as [ | r v | b B HB C HC | q B HB ]; intros Ο HwA.
        + simpl; tauto.
        + simpl in v; unfold Ξ£full_mon_rec.
          revert HwA; vec split v with t; vec nil v; clear v; simpl vec_head; simpl syms; intros HwA.
          specialize (HwA _ (or_introl eq_refl)); simpl in HwA |- *.
          replace (fo_term_sem M Ο t) 
          with    (fo_term_sem M Ο (fot_word_var (fot_word t) (fot_var t))).
          * revert HwA; generalize (fot_word t) (fot_var t); intros w i.
            rewrite <- (rev_length w), <- Hf. 
            simpl; generalize (rev w) (Ο i); clear w; intros w.
            induction w as [ | s w IHw ]; simpl; auto; intros Hw x.
            - rewrite HM2'; tauto.
            - rewrite HM1', IHw; simpl; try tauto; lia.
          * f_equal; symmetry; apply fot_word_var_eq.
        + apply fol_bin_sem_ext.
          * apply HB; intros ? ?; apply HwA, in_app_iff; auto.
          * apply HC; intros ? ?; apply HwA, in_app_iff; auto.
        + simpl; apply fol_quant_sem_ext; intro; apply HB; auto.
      Qed.

    End Ξ£full_mon_rec_complete.

    Variable (Kfin : finite_t K)
             (M'dec : fo_model_dec M')
             (Ο : nat -> K)
             (HA : fol_sem M' Ο Ξ£full_mon_red).

    Theorem Ξ£full_mon_rem_complete : fo_form_fin_dec_SAT_in A K.
    Proof.
      exists M, Kfin.
      exists.
      { intros r'; simpl in r'; intros v; apply M'dec. }
      exists Ο; simpl.
      destruct HA as [ H1 H2 ].
      revert H1; apply Ξ£full_mon_rec_complete.
      + intros s w r x Hw.
        simpl in H2; specialize (H2 x).
        rewrite fol_sem_lconj in H2.
        symmetry; apply (H2 (Eq (exist _ (s::w) Hw,r))), in_map_iff.
        exists (exist _ (s::w) Hw,r); split; auto.
      + intros r x.
        simpl in H2; specialize (H2 x).
        rewrite fol_sem_lconj in H2.
        symmetry; apply (H2 (Eq (exist _ nil (lt_0_Sn _),r))), in_map_iff.
        exists (exist _ nil (lt_0_Sn _),r); split; auto.
    Qed.

  End completeness.

  (* The non-skolemized reduction is correct *)

  Theorem Ξ£full_mon_red_correct : fo_form_fin_dec_SAT_in A K 
                              <-> fo_form_fin_dec_SAT_in Ξ£full_mon_red K.
  Proof.
    split.
    + intros (M & H1 & H2 & phi & H3).
      apply Ξ£full_mon_rem_sound with M phi; auto.
    + intros (M' & H1 & H2 & phi & H3).
      apply Ξ£full_mon_rem_complete with M' phi; auto.
  Qed.

  (* Now we skolemize the right part (equations) and show correctness *)

  Definition Ξ£full_mon_red' : fol_form Ξ£' :=
    Ξ£full_mon_rec A β β fol_mquant fol_ex n (fol_lconj (map Eq' lwY)).

  Local Lemma Ξ£full_mon_red'_sound : 
          fo_form_fin_dec_SAT_in Ξ£full_mon_red K
       -> fo_form_fin_dec_SAT_in Ξ£full_mon_red' K.
  Proof.
    intros (M & Kfin & Mdec & Ο & H1 & H2); simpl in H1, H2.
    exists M, Kfin, Mdec, Ο; simpl; split; auto.
    intros x; specialize (H2 x).
    rewrite fol_sem_mexists.
    exists (vec_set_pos (fun p => fom_syms M p (x##ΓΈ))).
    rewrite fol_sem_lconj; intros ?; rewrite in_map_iff.
    intros (c & <- & H).
    rewrite fol_sem_lconj in H2.
    specialize (H2 (Eq c) (in_map _ _ _ H)).
    clear H; revert H2.
    destruct c as (([ | s w ],?),r); simpl.
    + rewrite env_vlift_fix1 with (k := 0); simpl; auto.
    + rewrite env_vlift_fix1 with (k := 0).
      rewrite env_vlift_fix0; simpl; rew vec.
  Qed.

  Section Ξ£full_mon_red'_complete.

    Variable (M : fo_model Ξ£' K)
             (Kfin : finite_t K)
             (Mdec : fo_model_dec M)
             (Ο : nat -> K)
             (HA : fol_sem M Ο Ξ£full_mon_red').

    Let R x (v : vec _ n) := fol_sem M (env_vlift xΒ·Ο v) (fol_lconj (map Eq' lwY)).

    Let Rreif : { r : K -> vec K n | forall x, R x (r x) }.
    Proof.
      apply finite_t_dec_choice.
      + apply finite_t_vec; auto.
      + intros x v; apply fol_sem_dec; auto.
      + simpl in HA; apply proj2 in HA.
        intros x; generalize (HA x).
        rewrite fol_sem_mexists; auto.
    Qed.

    Let r := proj1_sig Rreif.
    Let Hg x : fol_sem M (env_vlift xΒ·Ο (r x)) (fol_lconj (map Eq' lwY)).
    Proof. apply (proj2_sig Rreif). Qed.

    Let M' : fo_model Ξ£' K.
    Proof.
      split.
      + simpl; intros p v.
        exact (vec_pos (r (vec_head v)) p).
      + exact (fom_rels M).
    Defined.

    Local Lemma Ξ£full_mon_red'_complete : fo_form_fin_dec_SAT_in Ξ£full_mon_red K.
    Proof.
      exists M', Kfin, Mdec, Ο.
      simpl; split.
      + simpl in HA; generalize (proj1 HA).
        apply fo_model_nosyms.
        * apply Ξ£full_mon_rec_syms.
        * intros; simpl; tauto.
      + intros x.
        specialize (Hg x).
        rewrite fol_sem_lconj in Hg.
        rewrite fol_sem_lconj.
        intros u; rewrite in_map_iff.
        intros (c & <- & Hc).
        specialize (Hg (Eq' c) (in_map _ _ _ Hc)).
        revert Hg.
        destruct c as (([|s w]&?),?); simpl.
        * rewrite env_vlift_fix1 with (k := 0); simpl; auto.
        * rewrite env_vlift_fix1 with (k := 0).
          rewrite env_vlift_fix0; simpl; rew vec.
    Qed.

  End Ξ£full_mon_red'_complete.

  (* The non-skolemized reduction is correct *)

  Theorem Ξ£full_mon_red'_correct : 
          fo_form_fin_dec_SAT_in A K
      <-> fo_form_fin_dec_SAT_in Ξ£full_mon_red' K.
  Proof.
    rewrite Ξ£full_mon_red_correct. 
    split.
    + apply Ξ£full_mon_red'_sound.
    + intros (M & H1 & H2 & phi & H3). 
      apply Ξ£full_mon_red'_complete with M phi; auto.
  Qed.

  (* And produce a syms-free formula *)

  Theorem Ξ£full_mon_red'_no_syms : fol_syms Ξ£full_mon_red' = nil.
  Proof.
    cut (incl (fol_syms Ξ£full_mon_red') nil).
    + generalize (fol_syms Ξ£full_mon_red').
      intros [ | x l ] H; auto.
      destruct (H x); simpl; auto.
    + simpl.
      rewrite Ξ£full_mon_rec_syms, fol_syms_mquant.
      rewrite fol_syms_bigop, <- app_nil_end; simpl.
      intros x; rewrite in_flat_map.
      intros (u & H & Hu); revert H.
      rewrite in_map_iff.
      intros (c & <- & Hc).
      revert Hu.
      destruct c as (([|s w]&?),r); simpl; auto.
  Qed.

End Ξ£full_mon_rem.

Section Ξ£11_reduction.

  (* We can lower the hypotheses now by computing m from A *)

  Variable (n : nat) (Y : Type) (HY : finite_t Y) (A : fol_form (Ξ£11 (pos n) Y)) (K : Type).

  Local Definition max_depth := lmax (map (@length _) (Ξ£11_words A)).

  Notation m := max_depth.

  Let Hmd w : w β Ξ£11_words A -> length w < S m.
  Proof.
    intros Hw; apply le_n_S, lmax_prop, in_map_iff.
    exists w; auto.
  Qed.

  Definition Ξ£11_red := Ξ£full_mon_red' HY m A.

  Theorem Ξ£11_red_correct : fo_form_fin_dec_SAT_in A K <-> fo_form_fin_dec_SAT_in Ξ£11_red K.
  Proof. apply Ξ£full_mon_red'_correct; auto. Qed.

  Theorem Ξ£11_red_no_syms : fol_syms Ξ£11_red = nil.
  Proof. apply Ξ£full_mon_red'_no_syms. Qed.

End Ξ£11_reduction.

(* We get the elimination of symbols *)

Section Ξ£11_Ξ£1.

  Variable (n : nat) (P : Type) (HY : finite_t P) (A : fol_form (Ξ£11 (pos n) P)).

  Theorem Ξ£11_Ξ£1_reduction : { B : fol_form (Ξ£11 Empty_set (list (pos n)*P + P)) 
                                 | fo_form_fin_dec_SAT A <-> fo_form_fin_dec_SAT B }.
  Proof.
    destruct Ξ£_no_sym_correct with (A := Ξ£11_red HY A) as (B & HB).
    { rewrite Ξ£11_red_no_syms; apply incl_refl. }
    exists B; rewrite <- HB; split; intros (X & H); exists X; revert H; apply Ξ£11_red_correct.
  Qed.

End Ξ£11_Ξ£1.



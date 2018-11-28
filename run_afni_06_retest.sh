#!/bin/tcsh -xef

echo "auto-generated by afni_proc.py, Tue Oct 23 20:53:53 2018"
echo "(version 6.19, September 18, 2018)"
echo "execution started: `date`"

# execute via : 
#   tcsh -xef run_afni_06_retest.sh |& tee output.run_afni_06_retest.sh

# =========================== auto block: setup ============================
# script setup

# take note of the AFNI version
afni -ver

# check that the current AFNI version is recent enough
afni_history -check_date  3 May 2018
if ( $status ) then
    echo "** this script requires newer AFNI binaries (than  3 May 2018)"
    echo "   (consider: @update.afni.binaries -defaults)"
    exit
endif

# the user may specify a single subject to run with
if ( $#argv > 0 ) then
    set subj = $argv[1]
else
    set subj = 06-retest
endif

# assign output directory name
set output_dir = $subj.results

# verify that the results directory does not yet exist
if ( -d $output_dir ) then
    echo output dir "$subj.results" already exists
    exit
endif

# set list of runs
set runs = (`count -digits 2 1 1`)

# create results and stimuli directories
mkdir $output_dir
mkdir $output_dir/stimuli

# copy stim files into stimulus directory
cp /scratch/psyc5171/sua13001/hw7/Finger.txt \
    /scratch/psyc5171/sua13001/hw7/Foot.txt  \
    /scratch/psyc5171/sua13001/hw7/Lips.txt $output_dir/stimuli

# copy anatomy to results dir
3dcopy                                                                             \
    /scratch/psyc5171/dataset1/sub-06/ses-retest/anat/sub-06_ses-retest_T1w.nii.gz \
    $output_dir/sub-06_ses-retest_T1w

# ============================ auto block: tcat ============================
# apply 3dTcat to copy input dsets to results dir,
# while removing the first 2 TRs
3dTcat -prefix $output_dir/pb00.$subj.r01.tcat \
    /scratch/psyc5171/dataset1/sub-06/ses-retest/func/sub-06_ses-retest_task-fingerfootlips_bold.nii.gz'[2..$]'

# and make note of repetitions (TRs) per run
set tr_counts = ( 182 )

# -------------------------------------------------------
# enter the results directory (can begin processing data)
cd $output_dir


# ========================== auto block: outcount ==========================
# data check: compute outlier fraction for each volume
touch out.pre_ss_warn.txt
foreach run ( $runs )
    3dToutcount -automask -fraction -polort 4 -legendre                     \
                pb00.$subj.r$run.tcat+orig > outcount.r$run.1D

    # outliers at TR 0 might suggest pre-steady state TRs
    if ( `1deval -a outcount.r$run.1D"{0}" -expr "step(a-0.4)"` ) then
        echo "** TR #0 outliers: possible pre-steady state TRs in run $run" \
            >> out.pre_ss_warn.txt
    endif
end

# catenate outlier counts into a single time series
cat outcount.r*.1D > outcount_rall.1D

# ================================= tshift =================================
# time shift data so all slice timing is the same 
foreach run ( $runs )
    3dTshift -tzero 0 -quintic -prefix pb01.$subj.r$run.tshift \
             -tpattern alt+z                                   \
             pb00.$subj.r$run.tcat+orig
end

# --------------------------------
# extract volreg registration base
3dbucket -prefix vr_base pb01.$subj.r01.tshift+orig"[0]"

# ================================= align ==================================
# for e2a: compute anat alignment transformation to EPI registration base
# (new anat will be intermediate, stripped, sub-06_ses-retest_T1w_ns+orig)
align_epi_anat.py -anat2epi -anat sub-06_ses-retest_T1w+orig \
       -save_skullstrip -suffix _al_junk                     \
       -epi vr_base+orig -epi_base 0                         \
       -epi_strip 3dAutomask                                 \
       -volreg off -tshift off

# ================================== tlrc ==================================
# warp anatomy to standard space
@auto_tlrc -base MNI_avg152T1+tlrc -input sub-06_ses-retest_T1w_ns+orig -no_ss

# store forward transformation matrix in a text file
cat_matvec sub-06_ses-retest_T1w_ns+tlrc::WARP_DATA -I > warp.anat.Xat.1D

# ================================= volreg =================================
# align each dset to base volume, align to anat, warp to tlrc space

# verify that we have a +tlrc warp dataset
if ( ! -f sub-06_ses-retest_T1w_ns+tlrc.HEAD ) then
    echo "** missing +tlrc warp dataset: sub-06_ses-retest_T1w_ns+tlrc.HEAD" 
    exit
endif

# register and warp
foreach run ( $runs )
    # register each volume to the base image
    3dvolreg -verbose -zpad 1 -base vr_base+orig                \
             -1Dfile dfile.r$run.1D -prefix rm.epi.volreg.r$run \
             -cubic                                             \
             -1Dmatrix_save mat.r$run.vr.aff12.1D               \
             pb01.$subj.r$run.tshift+orig

    # create an all-1 dataset to mask the extents of the warp
    3dcalc -overwrite -a pb01.$subj.r$run.tshift+orig -expr 1   \
           -prefix rm.epi.all1

    # catenate volreg/epi2anat/tlrc xforms
    cat_matvec -ONELINE                                         \
               sub-06_ses-retest_T1w_ns+tlrc::WARP_DATA -I      \
               sub-06_ses-retest_T1w_al_junk_mat.aff12.1D -I    \
               mat.r$run.vr.aff12.1D > mat.r$run.warp.aff12.1D

    # apply catenated xform: volreg/epi2anat/tlrc
    3dAllineate -base sub-06_ses-retest_T1w_ns+tlrc             \
                -input pb01.$subj.r$run.tshift+orig             \
                -1Dmatrix_apply mat.r$run.warp.aff12.1D         \
                -mast_dxyz 4                                    \
                -prefix rm.epi.nomask.r$run

    # warp the all-1 dataset for extents masking 
    3dAllineate -base sub-06_ses-retest_T1w_ns+tlrc             \
                -input rm.epi.all1+orig                         \
                -1Dmatrix_apply mat.r$run.warp.aff12.1D         \
                -mast_dxyz 4 -final NN -quiet                   \
                -prefix rm.epi.1.r$run

    # make an extents intersection mask of this run
    3dTstat -min -prefix rm.epi.min.r$run rm.epi.1.r$run+tlrc
end

# make a single file of registration params
cat dfile.r*.1D > dfile_rall.1D

# ----------------------------------------
# create the extents mask: mask_epi_extents+tlrc
# (this is a mask of voxels that have valid data at every TR)
# (only 1 run, so just use 3dcopy to keep naming straight)
3dcopy rm.epi.min.r01+tlrc mask_epi_extents

# and apply the extents mask to the EPI data 
# (delete any time series with missing data)
foreach run ( $runs )
    3dcalc -a rm.epi.nomask.r$run+tlrc -b mask_epi_extents+tlrc \
           -expr 'a*b' -prefix pb02.$subj.r$run.volreg
end

# warp the volreg base EPI dataset to make a final version
cat_matvec -ONELINE                                             \
           sub-06_ses-retest_T1w_ns+tlrc::WARP_DATA -I          \
           sub-06_ses-retest_T1w_al_junk_mat.aff12.1D -I  >     \
           mat.basewarp.aff12.1D

3dAllineate -base sub-06_ses-retest_T1w_ns+tlrc                 \
            -input vr_base+orig                                 \
            -1Dmatrix_apply mat.basewarp.aff12.1D               \
            -mast_dxyz 4                                        \
            -prefix final_epi_vr_base

# create an anat_final dataset, aligned with stats
3dcopy sub-06_ses-retest_T1w_ns+tlrc anat_final.$subj

# record final registration costs
3dAllineate -base final_epi_vr_base+tlrc -allcostX              \
            -input anat_final.$subj+tlrc |& tee out.allcostX.txt

# -----------------------------------------
# warp anat follower datasets (affine)
3dAllineate -source sub-06_ses-retest_T1w+orig                  \
            -master anat_final.$subj+tlrc                       \
            -final wsinc5 -1Dmatrix_apply warp.anat.Xat.1D      \
            -prefix anat_w_skull_warped

# ================================== blur ==================================
# blur each volume of each run
foreach run ( $runs )
    3dmerge -1blur_fwhm 6.0 -doall -prefix pb03.$subj.r$run.blur \
            pb02.$subj.r$run.volreg+tlrc
end

# ================================== mask ==================================
# create 'full_mask' dataset (union mask)
foreach run ( $runs )
    3dAutomask -prefix rm.mask_r$run pb03.$subj.r$run.blur+tlrc
end

# create union of inputs, output type is byte
3dmask_tool -inputs rm.mask_r*+tlrc.HEAD -union -prefix full_mask.$subj

# ---- create subject anatomy mask, mask_anat.$subj+tlrc ----
#      (resampled from tlrc anat)
3dresample -master full_mask.$subj+tlrc -input sub-06_ses-retest_T1w_ns+tlrc \
           -prefix rm.resam.anat

# convert to binary anat mask; fill gaps and holes
3dmask_tool -dilate_input 5 -5 -fill_holes -input rm.resam.anat+tlrc         \
            -prefix mask_anat.$subj

# compute tighter EPI mask by intersecting with anat mask
3dmask_tool -input full_mask.$subj+tlrc mask_anat.$subj+tlrc                 \
            -inter -prefix mask_epi_anat.$subj

# compute overlaps between anat and EPI masks
3dABoverlap -no_automask full_mask.$subj+tlrc mask_anat.$subj+tlrc           \
            |& tee out.mask_ae_overlap.txt

# note Dice coefficient of masks, as well
3ddot -dodice full_mask.$subj+tlrc mask_anat.$subj+tlrc                      \
      |& tee out.mask_ae_dice.txt

# ---- create group anatomy mask, mask_group+tlrc ----
#      (resampled from tlrc base anat, MNI_avg152T1+tlrc)
3dresample -master full_mask.$subj+tlrc -prefix ./rm.resam.group             \
           -input /usr/local/afni/MNI_avg152T1+tlrc

# convert to binary group mask; fill gaps and holes
3dmask_tool -dilate_input 5 -5 -fill_holes -input rm.resam.group+tlrc        \
            -prefix mask_group

# ================================= scale ==================================
# scale each voxel time series to have a mean of 100
# (be sure no negatives creep in)
# (subject to a range of [0,200])
foreach run ( $runs )
    3dTstat -prefix rm.mean_r$run pb03.$subj.r$run.blur+tlrc
    3dcalc -a pb03.$subj.r$run.blur+tlrc -b rm.mean_r$run+tlrc \
           -c mask_epi_extents+tlrc                            \
           -expr 'c * min(200, a/b*100)*step(a)*step(b)'       \
           -prefix pb04.$subj.r$run.scale
end

# ================================ regress =================================

# compute de-meaned motion parameters (for use in regression)
1d_tool.py -infile dfile_rall.1D -set_nruns 1                                 \
           -demean -write motion_demean.1D

# compute motion parameter derivatives (for use in regression)
1d_tool.py -infile dfile_rall.1D -set_nruns 1                                 \
           -derivative -demean -write motion_deriv.1D

# convert motion parameters for per-run regression
1d_tool.py -infile motion_demean.1D -set_nruns 1                              \
           -split_into_pad_runs mot_demean

1d_tool.py -infile motion_deriv.1D -set_nruns 1                               \
           -split_into_pad_runs mot_deriv

# create censor file motion_${subj}_censor.1D, for censoring motion 
1d_tool.py -infile dfile_rall.1D -set_nruns 1                                 \
    -show_censor_count -censor_prev_TR                                        \
    -censor_motion 0.5 motion_${subj}

# note TRs that were not censored
set ktrs = `1d_tool.py -infile motion_${subj}_censor.1D                       \
                       -show_trs_uncensored encoded`

# ------------------------------
# run the regression analysis
3dDeconvolve -input pb04.$subj.r*.scale+tlrc.HEAD                             \
    -censor motion_${subj}_censor.1D                                          \
    -polort 4                                                                 \
    -num_stimts 15                                                            \
    -stim_times 1 stimuli/Finger.txt 'BLOCK(15)'                              \
    -stim_label 1 Finger                                                      \
    -stim_times 2 stimuli/Foot.txt 'BLOCK(15)'                                \
    -stim_label 2 Foot                                                        \
    -stim_times 3 stimuli/Lips.txt 'BLOCK(15)'                                \
    -stim_label 3 Lips                                                        \
    -stim_file 4 mot_demean.r01.1D'[0]' -stim_base 4 -stim_label 4 roll_01    \
    -stim_file 5 mot_demean.r01.1D'[1]' -stim_base 5 -stim_label 5 pitch_01   \
    -stim_file 6 mot_demean.r01.1D'[2]' -stim_base 6 -stim_label 6 yaw_01     \
    -stim_file 7 mot_demean.r01.1D'[3]' -stim_base 7 -stim_label 7 dS_01      \
    -stim_file 8 mot_demean.r01.1D'[4]' -stim_base 8 -stim_label 8 dL_01      \
    -stim_file 9 mot_demean.r01.1D'[5]' -stim_base 9 -stim_label 9 dP_01      \
    -stim_file 10 mot_deriv.r01.1D'[0]' -stim_base 10 -stim_label 10 roll_02  \
    -stim_file 11 mot_deriv.r01.1D'[1]' -stim_base 11 -stim_label 11 pitch_02 \
    -stim_file 12 mot_deriv.r01.1D'[2]' -stim_base 12 -stim_label 12 yaw_02   \
    -stim_file 13 mot_deriv.r01.1D'[3]' -stim_base 13 -stim_label 13 dS_02    \
    -stim_file 14 mot_deriv.r01.1D'[4]' -stim_base 14 -stim_label 14 dL_02    \
    -stim_file 15 mot_deriv.r01.1D'[5]' -stim_base 15 -stim_label 15 dP_02    \
    -gltsym 'SYM: Finger -Foot'                                               \
    -glt_label 1 Finger-Foot                                                  \
    -gltsym 'SYM: Finger -Lips'                                               \
    -glt_label 2 Finger-Lips                                                  \
    -gltsym 'SYM: Foot -Lips'                                                 \
    -glt_label 3 Foot-Lips                                                    \
    -fout -tout -x1D X.xmat.1D -xjpeg X.jpg                                   \
    -x1D_uncensored X.nocensor.xmat.1D                                        \
    -fitts fitts.$subj                                                        \
    -errts errts.${subj}                                                      \
    -bucket stats.$subj


# if 3dDeconvolve fails, terminate the script
if ( $status != 0 ) then
    echo '---------------------------------------'
    echo '** 3dDeconvolve error, failing...'
    echo '   (consider the file 3dDeconvolve.err)'
    exit
endif


# display any large pairwise correlations from the X-matrix
1d_tool.py -show_cormat_warnings -infile X.xmat.1D |& tee out.cormat_warn.txt

# create an all_runs dataset to match the fitts, errts, etc.
3dTcat -prefix all_runs.$subj pb04.$subj.r*.scale+tlrc.HEAD

# --------------------------------------------------
# create a temporal signal to noise ratio dataset 
#    signal: if 'scale' block, mean should be 100
#    noise : compute standard deviation of errts
3dTstat -mean -prefix rm.signal.all all_runs.$subj+tlrc"[$ktrs]"
3dTstat -stdev -prefix rm.noise.all errts.${subj}+tlrc"[$ktrs]"
3dcalc -a rm.signal.all+tlrc                                                  \
       -b rm.noise.all+tlrc                                                   \
       -c full_mask.$subj+tlrc                                                \
       -expr 'c*a/b' -prefix TSNR.$subj 

# ---------------------------------------------------
# compute and store GCOR (global correlation average)
# (sum of squares of global mean of unit errts)
3dTnorm -norm2 -prefix rm.errts.unit errts.${subj}+tlrc
3dmaskave -quiet -mask full_mask.$subj+tlrc rm.errts.unit+tlrc                \
          > gmean.errts.unit.1D
3dTstat -sos -prefix - gmean.errts.unit.1D\' > out.gcor.1D
echo "-- GCOR = `cat out.gcor.1D`"

# ---------------------------------------------------
# compute correlation volume
# (per voxel: average correlation across masked brain)
# (now just dot product with average unit time series)
3dcalc -a rm.errts.unit+tlrc -b gmean.errts.unit.1D -expr 'a*b' -prefix rm.DP
3dTstat -sum -prefix corr_brain rm.DP+tlrc

# create ideal files for fixed response stim types
1dcat X.nocensor.xmat.1D'[5]' > ideal_Finger.1D
1dcat X.nocensor.xmat.1D'[6]' > ideal_Foot.1D
1dcat X.nocensor.xmat.1D'[7]' > ideal_Lips.1D

# --------------------------------------------------------
# compute sum of non-baseline regressors from the X-matrix
# (use 1d_tool.py to get list of regressor colums)
set reg_cols = `1d_tool.py -infile X.nocensor.xmat.1D -show_indices_interest`
3dTstat -sum -prefix sum_ideal.1D X.nocensor.xmat.1D"[$reg_cols]"

# also, create a stimulus-only X-matrix, for easy review
1dcat X.nocensor.xmat.1D"[$reg_cols]" > X.stim.xmat.1D

# ============================ blur estimation =============================
# compute blur estimates
touch blur_est.$subj.1D   # start with empty file

# create directory for ACF curve files
mkdir files_ACF

# -- estimate blur for each run in epits --
touch blur.epits.1D

# restrict to uncensored TRs, per run
foreach run ( $runs )
    set trs = `1d_tool.py -infile X.xmat.1D -show_trs_uncensored encoded      \
                          -show_trs_run $run`
    if ( $trs == "" ) continue
    3dFWHMx -detrend -mask full_mask.$subj+tlrc                               \
            -ACF files_ACF/out.3dFWHMx.ACF.epits.r$run.1D                     \
            all_runs.$subj+tlrc"[$trs]" >> blur.epits.1D
end

# compute average FWHM blur (from every other row) and append
set blurs = ( `3dTstat -mean -prefix - blur.epits.1D'{0..$(2)}'\'` )
echo average epits FWHM blurs: $blurs
echo "$blurs   # epits FWHM blur estimates" >> blur_est.$subj.1D

# compute average ACF blur (from every other row) and append
set blurs = ( `3dTstat -mean -prefix - blur.epits.1D'{1..$(2)}'\'` )
echo average epits ACF blurs: $blurs
echo "$blurs   # epits ACF blur estimates" >> blur_est.$subj.1D

# -- estimate blur for each run in errts --
touch blur.errts.1D

# restrict to uncensored TRs, per run
foreach run ( $runs )
    set trs = `1d_tool.py -infile X.xmat.1D -show_trs_uncensored encoded      \
                          -show_trs_run $run`
    if ( $trs == "" ) continue
    3dFWHMx -detrend -mask full_mask.$subj+tlrc                               \
            -ACF files_ACF/out.3dFWHMx.ACF.errts.r$run.1D                     \
            errts.${subj}+tlrc"[$trs]" >> blur.errts.1D
end

# compute average FWHM blur (from every other row) and append
set blurs = ( `3dTstat -mean -prefix - blur.errts.1D'{0..$(2)}'\'` )
echo average errts FWHM blurs: $blurs
echo "$blurs   # errts FWHM blur estimates" >> blur_est.$subj.1D

# compute average ACF blur (from every other row) and append
set blurs = ( `3dTstat -mean -prefix - blur.errts.1D'{1..$(2)}'\'` )
echo average errts ACF blurs: $blurs
echo "$blurs   # errts ACF blur estimates" >> blur_est.$subj.1D


# ================== auto block: generate review scripts ===================

# generate a review script for the unprocessed EPI data
gen_epi_review.py -script @epi_review.$subj \
    -dsets pb00.$subj.r*.tcat+orig.HEAD

# generate scripts to review single subject results
# (try with defaults, but do not allow bad exit status)
gen_ss_review_scripts.py -mot_limit 0.5 -exit0

# ========================== auto block: finalize ==========================

# remove temporary files
\rm -f rm.*

# if the basic subject review script is here, run it
# (want this to be the last text output)
if ( -e @ss_review_basic ) ./@ss_review_basic |& tee out.ss_review.$subj.txt

# return to parent directory
cd ..

echo "execution finished: `date`"




# ==========================================================================
# script generated by the command:
#
# afni_proc.py -subj_id 06-retest -script run_afni_06_retest.sh                                           \
#     -scr_overwrite -blocks tshift align tlrc volreg blur mask scale regress                             \
#     -copy_anat                                                                                          \
#     /scratch/psyc5171/dataset1/sub-06/ses-retest/anat/sub-06_ses-retest_T1w.nii.gz                      \
#     -dsets                                                                                              \
#     /scratch/psyc5171/dataset1/sub-06/ses-retest/func/sub-06_ses-retest_task-fingerfootlips_bold.nii.gz \
#     -tcat_remove_first_trs 2 -tshift_opts_ts -tpattern alt+z -tlrc_base                                 \
#     MNI_avg152T1+tlrc -volreg_align_to first -volreg_align_e2a                                          \
#     -volreg_tlrc_warp -blur_size 6.0 -regress_stim_times                                                \
#     /scratch/psyc5171/sua13001/hw7/Finger.txt                                                           \
#     /scratch/psyc5171/sua13001/hw7/Foot.txt                                                             \
#     /scratch/psyc5171/sua13001/hw7/Lips.txt -regress_stim_labels Finger                                 \
#     Foot Lips -regress_basis 'BLOCK(15)' -regress_censor_motion 0.5                                     \
#     -regress_apply_mot_types demean deriv -regress_motion_per_run                                       \
#     -regress_opts_3dD -gltsym 'SYM: Finger -Foot' -glt_label 1 Finger-Foot                              \
#     -gltsym 'SYM: Finger -Lips' -glt_label 2 Finger-Lips -gltsym 'SYM: Foot                             \
#     -Lips' -glt_label 3 Foot-Lips -regress_make_ideal_sum sum_ideal.1D                                  \
#     -regress_est_blur_epits -regress_est_blur_errts -regress_run_clustsim no

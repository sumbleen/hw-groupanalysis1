#!/usr/bin/env tcsh


#quick quality check
gen_ss_review_table.py -tablefile group_results/retest_qa.tsv -infiles subjects/*-retest.results/out.ss_review*

#make group mask
3dmask_tool \
-input subjects/*-retest.results/mask_group+tlrc.HEAD \
-frac 1.0 \
-prefix group_results/mask

#t-test one sample
3dttest++ -mask group_results/mask+tlrc \
-prefix group_results/Foot-Lips \
-setA 'subjects/*-retest.results/stats.*-retest+tlrc.HEAD[Foot-Lips_GLT#0_Coef]'

#average blur estimates
scripts/average_blur.py subjects/*-retest.results/blur.errts.1D

#Clustering
3dClustSim \
-mask group_results/mask+tlrc \
-acf `scripts/average_blur.py subjects/*-retest.results/blur.errts.1D` \
-both -pthr .05 .01 .001 \
-athr .1 .05 .025 .01 \
-iter 10000 \
-prefix group_results/cluster \
-cmd group_results/refit.cmd

#add cluster table
`cat group_results/refit.cmd` \
group_results/Foot-Lips+tlrc


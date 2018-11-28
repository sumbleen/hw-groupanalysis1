#!/usr/bin/env tcsh

#link a copy of anat to group_results
cp /usr/local/afni/MNI152_T1_2009c+tlrc* group_results/

#mask stat image
cd group_results

3dcalc -a Foot-Lips+tlrc \
-b mask+tlrc \
-expr 'a*b' \
-prefix Foot-Lips_masked

#convert to z-scores
3dmerge -1zscore -prefix Foot-Lips_zstat \
'Foot-Lips_masked+tlrc[SetA_Tstat]'

#find clusters 
3dAttribute AFNI_CLUSTSIM_NN3_1sided Foot-Lips+tlrc

#threshold clusters, at alpha threshold<.05
3dclust -1Dformat -nosum \
-prefix Foot-Lips_clusters \
-savemask Foot-Lips_cluster_mask \
-inmask -1noneg \
-1clip 3 \
-dxyz=1 \
1.74 18 \
Foot-Lips_zstat+tlrc 


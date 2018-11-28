#!/usr/bin/env python
import numpy as np # numerical/array module
import glob # shell style widlcards
import argparse # command line arguments
argparser = argparse.ArgumentParser()
argparser.add_argument('files', nargs='+', type=str)
args = argparser.parse_args()
#files = glob.glob('*.results/blur.errts.1D')

blurs = np.array([])

for f in args.files:
	# take the second row of the 2x4 array
	blur = np.loadtxt(f)[1,::]
	blurs = np.vstack([blurs,blur]) if blurs.size else blur

# mean of first 3 columns
mean_blur = np.mean(blurs[::,0:3],0)
print(' '.join(map(str,mean_blur)))

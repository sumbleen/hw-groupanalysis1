#!/bin/bash
#SBATCH --mail-type=ALL 			# Mail events (NONE, BEGIN, END, FAIL, ALL)
#SBATCH --mail-user=emily.yearling@uconn.edu	# Your email address
#SBATCH --ntasks=10				# Run a single serial task
#SBATCH --cpus-per-task=1     # Number of cores to use
#SBATCH --mem=4096mb				# Memory limit
#SBATCH --time=0:20:00				# Time limit hh:mm:ss
#SBATCH -e error_stats.log				# Standard error
#SBATCH -o output_stats.log				# Standard output
#SBATCH --job-name=clustering			# Descriptive job name
#SBATCH --partition=serial
module load singularity


# run the generated script
cd /scratch/psyc5171/sua13001/hw7/results_retest
singularity run /scratch/psyc5171/containers/burc-lite.img /scratch/psyc5171/sua13001/hw7/results_retest/results.sh


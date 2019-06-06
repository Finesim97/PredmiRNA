#!/usr/bin/env Rscript

#
# Converts a .csv dataframe into a Weka usable .arff
#

library(foreign)
set.seed(1)
infile="test.csv"
outfile="file.arff"
if(exists("snakemake")){
	infile=snakemake@input[[1]]
	outfile=snakemake@output[[1]]
}
data = read.csv(infile,stringsAsFactors = FALSE)
data <- data[data$realmiRNA==-1]
write.arff(x=data, file=outfile, eol = "\n", relation = deparse(substitute(x)))
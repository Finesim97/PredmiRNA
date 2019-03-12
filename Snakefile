# This is the main file for Snakemake, it defines the workflow steps, which need to be executed.https://snakemake.readthedocs.io/

# The configuration file to load
configfile: "config.yaml"

# In how many chunks should each input sequence file be split
noofsplits=4

# Paths
basedir = config["datadir"] # Where to store the generated datafiles

# Randfold Shuffling options
shufflelist=[20,100,500,1000] # Number of permutations to try 
shufflemethods=["m","d","z","f"] # Method to generate the permutations
# m, mononucleotide shuffling; d, dinucleotide shuffling; z, zero-order markov model; f, first-order markov model


# Please use unix style line endings (dos2unix)
inputgroups=["real_izmir","pseudo_izmir"]
# Real miRNA has to contain "real"


# These rules will be run locally
localrules: presentation, arff, splitfasta, mergecsv, mergefinalcsv, fasta2csv, joincsv, buildJar, models, 
 derviedcsv, parsernafold, parsestnlyfeatures, parsestnlyRandfeatures, parseRNAspectral, snuffleshuffel
# Limit the index to a numerical value
wildcard_constraints:
    index="\d+"




##
##
## Util rules
##
##

#
# Split fasta file using fastasplit
#
splitindices=['%07d'%i for i in range(0,noofsplits)];
rule splitfasta:
	input:
		basedir+"/{inputgroup}.fasta"
	output:
		expand(basedir+"/{{inputgroup}}/split/{{inputgroup}}.fasta_chunk_{index}",index=splitindices)
	params:
		splits=noofsplits,
		outputdir=directory(basedir+"/{inputgroup}/split/")
	shell:
		"fastasplit -f {input} -o {params.outputdir} -c {params.splits}"
#
# Join the calculated .csv files
#
rule joincsv:
	input:
		expand(basedir+"/{{inputgroup}}/datasplit/{{index}}.{type}.csv",type=["fold","seq","derived","stnley","spectral"]),
		expand(basedir+"/{{inputgroup}}/stanley/{{index}}-{method}-{shuffles}.csv",method=shufflemethods,shuffles=shufflelist) 
	output:
		basedir+"/{inputgroup}/split-{index}.csv"
	script:
		"scripts/csvmerge/csvmerge.R"

#
# Merge the .csv files from the sets
#
rule mergecsv:
	input:
		csvs=expand(basedir+"/{{inputgroup}}/split-{index}.csv",index=splitindices)
	output:
		csv=basedir+"/{inputgroup}/combined.csv"
	script:
		"scripts/concatenateCsvs/concatenateCsvs.R"
#
# Merge the generated .csv files
#
rule mergefinalcsv:
        input:
                csvs=expand(rules.mergecsv.output.csv,inputgroup=inputgroups)
        output:
                csv=basedir+"/all.csv"
        script:
                "scripts/concatenateCsvs/concatenateCsvs.R"



##
##
## Feature rules
##
##

#
# Run rnafold
#
rule fold:
	input:
		basedir+"/{inputgroup}/split/{inputgroup}.fasta_chunk_{index}"
	output:
		basedir+"/{inputgroup}/fold/{index}.fold"
	conda: 
		"envs/rnafold.yaml"
	shadow:
		"shallow" # Run it in an isolated enviroment, spams postscript files
	shell:
		"RNAfold --noPS -p < {input} > {output}"
#
# Parse rnafold
#
rule parsernafold:
	input:
		rules.fold.output
	output:
		basedir+"/{inputgroup}/datasplit/{index}.fold.csv"
	script:
		"scripts/rnafold2csv/rnafold2csv.py"
fastachunk=basedir+"/{inputgroup}/split/{inputgroup}.fasta_chunk_{index}"
#
# Run stanley genRNAStats.pl
#
rule stanleyRNAstats:
	input:
		fastachunk
	output:
		stats=basedir+"/{inputgroup}/stanley/{index}.stats"
	shell:
		"perl scripts/shuffle/genRNAStats.pl -i {input} -o {output.stats}"
#
# Parse the stanley features
#
rule parsestnlyfeatures:
	input:
		shuffledstatfiles=rules.stanleyRNAstats.output.stats
	output:
		basedir+"/{inputgroup}/datasplit/{index}.stnley.csv"
	script:
		"scripts/shuffle/parseRNAStats.R"
#
# Shuffle the sequences
#
rule snuffleshuffel:
	input:
		fastachunk
	output:
		basedir+"/{inputgroup}/stanley/shuffled/{index}-{method}-{shuffles}.fasta"
	params:
		method="{method}",
		shuffles="{shuffles}"
	shell:
		"perl scripts/shuffle/genRandomRNA.pl -n {params.shuffles} -m {params.method} < {input} > {output}"
#
# Fold the shuffled sequences
#
rule foldshuffled:
	input:
		rules.snuffleshuffel.output
	output:
		basedir+"/{inputgroup}/stanley/shuffled/{index}-{method}-{shuffles}.fold"
	shell:
		"RNAfold --noPS < {input} > {output}"
#
# Compute Stanleys features from the shuffled sequences
#	
rule stnlyRandfeatures:
	input:
		unshuffled=rules.fold.output,
		shuffled=rules.foldshuffled.output,
	output:
		stats=basedir+"/{inputgroup}/stanley/{index}-{method}-{shuffles}.stats"
	params:
		shuffles="{shuffles}"
	shell:
		"perl scripts/shuffle/genRNARandomStats.pl -n {params.shuffles} -i {input.shuffled} -m {input.unshuffled} -o {output.stats}"

#
# Parse the stanley randfold features
#
rule parsestnlyRandfeatures:
	input:
		shuffledstatfiles=rules.stnlyRandfeatures.output.stats
	output:
		stats=basedir+"/{inputgroup}/stanley/{index}-{method}-{shuffles}.csv"
	script:
		"scripts/shuffle/parseRNARandom.R"

#
# Run RNAspectral
#
rule RNAspectral:
	input:
		rules.fold.output
	output:
		basedir+"/{inputgroup}/stanley/{index}.spectral"
	shell:
		# Clean the additional information
		"grep --invert-match '[]}}]$\| frequ' {input} | scripts/shuffle/RNAspectral.exe > {output}"
#
# Parse RNAspectral output
#
rule parseRNAspectral:
	input:
		shuffledstatfiles=rules.RNAspectral.output,
		fastasource=rules.fold.input
	output:
		basedir+"/{inputgroup}/datasplit/{index}.spectral.csv"
	script:
		"scripts/shuffle/parseRNAspectral.R"

#
# Calculates features from the fold csv file
#
rule derviedcsv:
	input:
		rules.parsernafold.output
	output:
		basedir+"/{inputgroup}/datasplit/{index}.derived.csv"
	script:
		"scripts/features_derived/features_derived.R"
#
# Runs dustmasker on the chunk
#
rule dustmasker:
	input:
		fastachunk
	output:
		fastachunk+"_dm"
	shell:
		"dustmasker -in {input} -outfmt fasta -out {output} -level 15"
#
# Convert the given fasta chunk into a csv file
#
rule fasta2csv:
	input:
		rules.dustmasker.output
	output:
		basedir+"/{inputgroup}/datasplit/{index}.seq.csv"
	params:
		realmarker="real"
	script:
		"scripts/fasta2csv/fasta2csv.R"

#rule installPerlShuffle:
#	output: runshuffleinstall
#	shell: "PERL_MM_USE_DEFAULT=1 cpan Algorithm::Numerical::Shuffle > {output}"
#

##
##
## Learning Rules
##
##

algs = {"j48":"weka.classifiers.trees.J48","bayes":"weka.classifiers.bayes.NaiveBayes","perceptron":"weka.classifiers.functions.MultilayerPerceptron",
	"randomforest":"weka.classifiers.trees.RandomForest","randomtree":"weka.classifiers.trees.RandomTree","libsvm":"weka.classifiers.functions.LibSVM"}

#
# Generate .arff for Weka
#
rule arff:
	input:
		rules.mergefinalcsv.output.csv
	output:
		basedir+"/all.arff"
	script:
		"scripts/csv2arff/csv2arff.R"

#
# This rule builds the Java programs in the eclipseprojects folder
#
rule buildJar:
	input:
		"eclipseprojects/{program}"  # Project directory
	output:
		"bins/{program}.jar" # The jar file
	shell:
		"mvn -f {input}/pom.xml clean compile package 2>&1 && mv {input}/target/{wildcards.program}-0.0.1-SNAPSHOT-jar-with-dependencies.jar {output} && sleep 1"
		# Use Maven to build the project to a fat jar
def algtoclass(wildcards):
	return algs[wildcards["alg"]]

#
# This rule trains the models
#
rule trainModel:
	input:
		program="bins/WekaTrainer.jar",
		arff=rules.arff.output
	output:
		model= basedir+"/models/{alg}.ser",
		thfile=basedir+"/models/threshold/{alg}.csv",
		stdout=basedir+"/models/{alg}.log"
	params:
		alg=algtoclass
	shell:
		"java -jar {input.program} --input {input.arff} --classatt realmiRNA --seed 1 --folds 10 --outputclassifier {output.model} --thresholdfile {output.thfile} {params.alg} > {output.stdout}"
#
# This rule requests all models
#
rule models:
	input: expand(rules.trainModel.output.model,alg=algs.keys())






##
##
## Report Rules
##
##

#
# Generate the project presentation
#
rule presentation:
	input:
		template="presentation/template.pptx",
		finalcsv=rules.mergefinalcsv.output.csv
	output:
		presentation=basedir+"/presentation.pptx"
	script:
		"presentation/projectpresentation.Rmd"


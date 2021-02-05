#!/usr/bin/env -S gnuplot --persist -c
#
# This script box plots the result generated by script
# summarize_all_platforms.sh in the format of SVG.
#
# Prerequisites:
#   GNU Coreutils >= 8.30
#     env supports the -S/--split-string=S option to split a single
#     argument string into multiple arguments.
#     https://github.com/coreutils/coreutils/blob/master/NEWS
#   gnuplot >= 5.2
#     1. support passing parameters to a gnuplot script (ie. ARGC)
#     http://www.gnuplot.info/ReleaseNotes_5_0_7.html
#
#     2. GPVAL_SYSTEM_ERRNO
#     http://www.gnuplot.info/docs_5.2/Gnuplot_5.2.pdf, p201

if (ARGC != 1) {
  print sprintf("Usage:    %s DATAFILE\n",ARG0)
  print \
    "DATAFILE:\n", \
    "    a datafile summarizes z-score per stressor class for all\n", \
    "    platforms, typically ending with '.platforms_summary.per_class'."
  exit
}

datafile = ARG1
file_ext = system(sprintf("echo '%s' | rev | cut -d'.' -f1-2 | rev", datafile))
if (file_ext ne "platforms_summary.per_class") {
  printerr sprintf("[ERROR] Unsupport datafile: %s", datafile)
  exit status 1
}

system("test -f ".datafile)
if (GPVAL_SYSTEM_ERRNO != 0) {
  printerr sprintf("[ERROR] Cannot find datafile: %s", datafile)
  exit status GPVAL_SYSTEM_ERRNO
}


output_filepath = datafile.".svg"
set output output_filepath

# Mark the first row to be the column header
#   https://stackoverflow.com/a/35528422
set key autotitle columnheader
set key at screen 0.5,1 center top vertical Left noenhanced \
  reverse width -3 font ",14" maxrows 4
set tmargin 7

data_header = system("grep --max-count=1 '^[^#]' ".datafile)
NF = words(data_header)
SKIP_COLUMNS = 2
num_platforms = NF - SKIP_COLUMNS

set terminal svg enhanced font "arial,12" fontscale 1.0 size num_platforms*12*13,800

set border 3 front linetype black linewidth 1.000 dashtype solid
set style fill solid 1.00 noborder

GAPSIZE = 7
# gapsize does not support to be specified by a variable
set style histogram clustered gap 7

boxwidth = 1.0 / (num_platforms + GAPSIZE)

set xtics border in scale 0,0 nomirror norotate autojustify noenhanced
set ytics border in scale 1.0,0.5 nomirror norotate autojustify
set mytics 2
set grid ytics mytics

set xlabel "stressor class" font ",15"
set ylabel "normalized z-score" font ",15"

avg_zscore(strval) = real(system(sprintf( \
  "echo %s | cut --delimiter='/' --fields=1", strval)))
min_zscore(strval) = real(system(sprintf( \
  "echo %s | cut --delimiter='/' --fields=2", strval)))
max_zscore(strval) = real(system(sprintf( \
  "echo %s | cut --delimiter='/' --fields=3", strval)))

PLATFORM_START_COLUMN = 1 + SKIP_COLUMNS
plot for [i=PLATFORM_START_COLUMN:NF] \
        datafile using \
          (column(0)-(num_platforms/2.0)*boxwidth+(i-PLATFORM_START_COLUMN)*boxwidth+boxwidth/2):(min_zscore(strcol(i))):(min_zscore(strcol(i))):(max_zscore(strcol(i))) \
          with yerrorbars linecolor rgbcolor "light-gray" pointtype -1, \
     for [i=PLATFORM_START_COLUMN:NF] \
        datafile using (avg_zscore(strcol(i))):xtic(strcol(1)." (".strcol(2).")") \
          with histograms title columnheader(i)

print "Written to output file: ".output_filepath

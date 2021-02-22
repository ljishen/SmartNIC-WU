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
    "    a datafile summarizes performance statistics per stressor class\n", \
    "    for each platform, typically ending with '.platforms_summary.per_class'."
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
set key at screen 0.51,1 center top vertical Left noenhanced \
  reverse width -7 font ",16" maxrows 4

data_header = system("grep --max-count=1 '^[^#]' ".datafile)
NF = words(data_header)
SKIP_COLUMNS = 2
num_platforms = NF - SKIP_COLUMNS

set terminal svg enhanced font "arial,14" fontscale 1.0 size num_platforms*12*13,1100
set multiplot layout 2,1 margins char 10,1,1,7

GAPSIZE = 7
# gapsize does not support to be specified by a variable
set style histogram clustered gap 7 # =GAPSIZE

boxwidth = 1.0 / (num_platforms + GAPSIZE)

set style fill solid 1.00 noborder
set format y "%.1f"
set ytics border in scale 1.0,0.5 nomirror norotate autojustify
set mytics 2
set grid ytics mytics

set border 1+2 front linetype black linewidth 1.000 dashtype solid
set xrange [ -1 : * ]
set xtics border in scale 0,0 nomirror norotate autojustify noenhanced
set bmargin at screen 0.24

REFERENCE_PLATFORM = system(sprintf( \
  "grep --perl-regexp --only-matching \
  '^# Reference platform : \\K.*' %s", datafile))
set ylabel "Average Performance (vs. ".REFERENCE_PLATFORM.")" font ",17"

avg_val(strval) = real(system(sprintf( \
  "echo %s | cut --delimiter='/' --fields=5", strval)))
stdev(strval) = real(system(sprintf( \
  "echo %s | cut --delimiter='/' --fields=6", strval)))
min_val(strval) = real(system(sprintf( \
  "echo %s | cut --delimiter='/' --fields=7", strval)))
max_val(strval) = real(system(sprintf( \
  "echo %s | cut --delimiter='/' --fields=8", strval)))

PLATFORM_START_COLUMN = 1 + SKIP_COLUMNS
# plot for [i=PLATFORM_START_COLUMN:NF] \
#         datafile using \
#           (column(0)-(num_platforms/2.0)*boxwidth+(i-PLATFORM_START_COLUMN)*boxwidth+boxwidth/2):(min_val(strcol(i))):(min_val(strcol(i))):(max_val(strcol(i))) \
#           with yerrorbars linecolor rgbcolor "light-gray" pointtype -1, \
#      for [i=PLATFORM_START_COLUMN:NF] \
#         datafile using (avg_val(strcol(i))):xtic(strcol(1)." (".strcol(2).")") \
#           with histograms title columnheader(i)
plot for [i=PLATFORM_START_COLUMN:NF] \
        datafile using (avg_val(strcol(i))):xtic(strcol(1)." (".strcol(2).")") \
          with histograms title columnheader(i)


unset key
unset xtics
set border 2+4
set x2range [ -1 : * ]
set x2tics border in scale 0,0 nomirror norotate autojustify noenhanced
set format x2 ""
set tmargin at screen 0.2
set yrange [ * : * ] reverse
set ylabel "Standard Deviation"

plot for [i=PLATFORM_START_COLUMN:NF] \
        datafile using (stdev(strcol(i))) \
          with histograms title columnheader(i) axes x2y1

print "Written to output file: ".output_filepath

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
#
#     3. use data type array[size]
#     http://www.gnuplot.info/ReleaseNotes_5_2_8.html

if (ARGC != 1) {
  print sprintf("Usage:    %s DATAFILE\n",ARG0)
  print \
    "DATAFILE:\n", \
    "    a datafile summarizes results from all platforms,\n", \
    "    typically ending with '.platforms_summary'."
  exit
}

datafile = ARG1
file_ext = system(sprintf("echo '%s' | rev | cut -d'.' -f1 | rev", datafile))
if (file_ext ne "platforms_summary") {
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

# Skip the column header so it won't be used as data
#   https://stackoverflow.com/a/35528422
set key autotitle columnheader
set key at graph 0.8,1.025 left top Left noenhanced reverse font ",10"

set border 2 front linetype black linewidth 1.000 dashtype solid
set boxwidth 0.5 absolute
set pointsize 0.8
set style fill solid 0.70 border lt -1

RANGE_FACTOR = 1.5
set style boxplot range RANGE_FACTOR nooutliers pointtype 7 candlesticks

# Use a preset RGB full-spectrum color gradient. See
#   gnuplot> help set palette defined
set palette defined
unset colorbox

set xtics border nomirror in scale 0,0 rotate autojustify rangelimited
set ytics border nomirror in scale 1.0,0.5 norotate autojustify
set grid xtics ytics

set ylabel "z-score" font ",15"

data_header = system("grep --max-count=1 '^[^#]' ".datafile)
NF = words(data_header)

SKIP_COLUMNS = 1
STRESSORS_PER_PLOT=32
num_stressors = NF - SKIP_COLUMNS
num_plots = ceil(num_stressors * 1.0 / STRESSORS_PER_PLOT)

set terminal svg enhanced font "arial,12" fontscale 1.0 size 1000,400*num_plots
set multiplot layout num_plots,1 title \
  "Performnace variability of different stressors on different platforms\n" \
  font ",15"

zscore(strval) = strstrt(strval, "nan") != 0 \
  ? 0 : real(substr(strval, strstrt(strval, "/")+1, -1))

BLUEFIELD_IDX = system(sprintf( \
    "sed '/^[[:blank:]]*\\(#\\|$\\)/d' %s \
    | cut --fields=1 \
    | tail --lines=+2 \
    | grep --line-number 'MBF' \
    | cut --fields=1 --delimiter=':'", datafile)) - 1

# platform_idx starts from 0
should_highlight(platform_idx) = \
  platform_idx == BLUEFIELD_IDX
highlight(platform_idx, strval) = \
  should_highlight(platform_idx) && strstrt(strval, "nan") == 0 \
  ? zscore(strval) : 1/0
POINTTYPE_HIGHLIGHT = 9
POINTTYPE_NORMAL = 7

outlier(zscore, upper, lower) = \
  (zscore > upper || zscore < lower) ? zscore : 1/0

num_platforms = system(sprintf( \
    "sed '/^[[:blank:]]*\\(#\\|$\\)/d' %s \
    | tail --lines=+2 \
    | wc --lines", datafile))

# idx start from 1
platform_name(idx) = system(sprintf( \
    "sed '/^[[:blank:]]*\\(#\\|$\\)/d' %s \
    | cut --fields=1 \
    | tail --lines=+2 \
    | sed --quiet '%dp'", datafile, idx))

do for [p=1:num_plots] {
  start_col_cur_plot = (p - 1) * STRESSORS_PER_PLOT + SKIP_COLUMNS + 1
  end_col_cur_plot = STRESSORS_PER_PLOT * p > num_stressors \
    ? NF : start_col_cur_plot + STRESSORS_PER_PLOT - 1

  num_stressors_cur_plot = end_col_cur_plot - start_col_cur_plot + 1

  array Upperwhisker[num_stressors_cur_plot]
  array Lowerwhisker[num_stressors_cur_plot]
  plot_min = 0
  plot_max = 0

  # Remove range limit on the y axis. See "gnuplot> help stats".
  set autoscale y

  do for [i=start_col_cur_plot:end_col_cur_plot] {
    stats datafile using (zscore(strcol(i))) nooutput
    if (STATS_min<plot_min) {
      plot_min=STATS_min
    }
    if (STATS_max>plot_max) {
      plot_max=STATS_max
    }

    irq = STATS_up_quartile - STATS_lo_quartile
    Upperwhisker[i-start_col_cur_plot+1] = STATS_up_quartile + irq * RANGE_FACTOR
    Lowerwhisker[i-start_col_cur_plot+1] = STATS_lo_quartile - irq * RANGE_FACTOR
  }

  # Restore the default behavior, we can then add tic labels
  set xtic ("" 1)

  # Extend the xrange to the right by 10 to contain the legend
  set xrange [0:num_stressors_cur_plot+10] noreverse writeback
  set yrange [floor(plot_min):ceil(plot_max)] noreverse nowriteback

  set for [i=1:num_stressors_cur_plot] \
    xtics add (word(data_header, start_col_cur_plot+(i-1)) i)

  plot for [i=1:num_stressors_cur_plot] \
          datafile using (i):(zscore(strcol(start_col_cur_plot+(i-1)))) with boxplot, \
       for [i=1:num_stressors_cur_plot] \
          datafile using (i):(outlier( \
            zscore(strcol(start_col_cur_plot+(i-1))), \
            Upperwhisker[i], Lowerwhisker[i])):0 \
            with points pointtype POINTTYPE_NORMAL palette, \
       for [i=1:num_stressors_cur_plot] \
          datafile using (i):(highlight(column(0), \
            strcol(start_col_cur_plot+(i-1)))):0 \
            with points pointtype POINTTYPE_HIGHLIGHT palette, \
       for [i=1:num_platforms] \
          datafile using (num_stressors_cur_plot+10):(floor(plot_min)):(i-1)  \
            with points \
            pointtype should_highlight(i-1)?POINTTYPE_HIGHLIGHT:POINTTYPE_NORMAL \
            palette title platform_name(i)
}

print "Written to output file: ".output_filepath

#!/usr/bin/perl

use Graphics::GnuplotIF qw(GnuplotIF);

  my  @x  = ( -2, -1.50, -1, -0.50,  0,  0.50,  1, 1.50, 2 ); # x values
  my  @y1 = (  4,  2.25,  1,  0.25,  0,  0.25,  1, 2.25, 4 ); # function 1
  my  @y2 = (  2,  0.25, -1, -1.75, -2, -1.75, -1, 0.25, 2 ); # function 2

  my  $plot1 = Graphics::GnuplotIF->new(title => "line", style => "points");

  $plot1->gnuplot_plot_y( \@x );                # plot 9 points over 0..8

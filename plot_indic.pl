#!/usr/bin/perl -I/Users/tdall/copyExecs
#
# idea: plot indicators against each other to map out where they work and where they don't,
# i.e. where the trade was profitable and where it wasn't. Could grade color according to 
# size of gain.
#
use GD::Graph::points;
require "utils.pl";

#($filename, $xidx, $yidx) = @ARGV;
#$num = @ARGV;
$filename = shift;

$path = "/Users/tdall/geniustrader/";
$dbfile = "/Users/tdall/geniustrader/traderThomas";
$btdir = "/Users/tdall/geniustrader/Backtests/";
@what = ("ADX", "ADX 2day slope", "ADX 5day slope",
    "ATR", "ATR 2day slope", "ATR 5day slope",
    "MACD", "MACD 2day slope", "MACD 5day slope");
# make the plot of indicators according to gain or loss:
#
open TRADE, "<${btdir}$filename" or die "readttr52r";
$in = <TRADE>;
@trade = <TRADE>;
close TRADE;

for ($i=0; $i<=8; $i++) {
    $xidx = $i;
    for ($j=$xidx+1; $j <=8; $j++) {
        $yidx = $j;
        @wins = (); @loss = (); @x = (); @all = (); @data = ();
        foreach $in (@trade) {
            @in = split /\s+/, $in;
            push @x, $in[$xidx];
            if ($in[17] =~ /-\d/) {  # a loss...
                push @loss, $in[$yidx];
                push @wins, undef;
            } else {  # a positive gain    
                push @loss, undef;
                push @wins, $in[$yidx];
            }
            push @all, $in[$yidx];
        }
#        $nx = @x; $nl = @loss; $nw = @wins; print "elem before: $nx, $nl, $nw\n";
        ($ymin, $ymax) = low_and_high(@all);
        ($newx, $newy) = sort2arrays(\@x, \@wins);
        @wins = @$newy;
        ($newx, $newy) = sort2arrays(\@x, \@loss);
        @loss = @$newy;
        @x = @$newx;  
#        $nx = @x; $nl = @loss; $nw = @wins; print "elem: $nx, $nl, $nw\n";
        @data = (\@x, \@loss, \@wins);
        $grp = GD::Graph::points->new(600,600);
        $grp->set( 
              x_label           => "$what[$xidx]",
              y_label           => "$what[$yidx]",
              title             => "Backtest $filename",
              y_max_value       => $ymax*1.02,
              y_min_value       => $ymin*0.98,
              y_tick_number     => 8,
              y_label_skip      => 2 
          ) or die $graph->error;
        my $grpl = $grp->plot(\@data) or die $grp->error;
        open(IMG, ">plot_${xidx}_${yidx}.png") or die $!;
        binmode IMG;
        print IMG $grpl->png;
        close IMG;
    }
}
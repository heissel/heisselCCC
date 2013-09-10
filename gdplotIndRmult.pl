#!/usr/bin/perl -I/Users/tdall/copyExecs
# 
# takes data from file and makes a plot of the 2D landscpe for two indicators
#
# arg 0: file (a trade_* file)
# arg 1: indicator on x-axis
#   can be GT indicator, OR Candle-<type>, where <type> = 
#                               ocATR;  (o-c)/ATR,
#                               hlATR;  (h-l)/ATR, 
#                               ochl;   (o-c)/(h-l),
#                               oc01;   (o-c)/(o-c)1   [1 == day -1, i.e. prev. day] 
#                               ochl1;  (o-c)/(h-l)1,
#                               hl01;   (h-l)/(h-l)1
#                               hl10;   (h-l)1/(h-l)
#                               wrat;   uw/lw  (or lw/uw;  0 < wrat < 1)
# arg 2: which position: 0 (indicator), 1 (2-day slope), 2 (5/<N>-day slope) [ignored unless a GT indicator]
# arg 3: indicator on y-axis
# arg 4: which position: 0 (indicator), 1 (2-day slope), 2 (5/<N>-day slope)
# [-p] make PNG instead of on-screen plot
# [-l] use only long trades
# [-s] use only short trades
# [-r] normalize/make percentages of the slope if that's what we asked for; only applies to y-axis indicator
# [-a] normalize the y-axis with the ATR
# [-n <N>] use for the long slope, default is 5
# [-x "x1 x2 x3 ..."] plot vertical lines at these x-positions
# [-y "y1 y2 y3 ..."] plot horizontal lines at these y-positions

#
# ***DONE: get ohlc for today and previous days to check sizes and ratios
# TODO: get scatter on the linfit slope as a parameter
# TODO; allow Kaufman market efficiency, then check if it correlates with slope/ATR
#use strict;
use Getopt::Std;
#use GD::Graph::points;
use Graphics::GnuplotIF qw(GnuplotIF);
require "utils.pl";
require "pg_utils.pl";

getopts('plsran:x:y:');
if ($opt_n) {
    $dura = $opt_n;
} else {
    $dura = 5;
}
if ($opt_x) {
    @xlines = split /\s+/, $opt_x;
}
if ($opt_y) {
    @ylines = split /\s+/, $opt_y;
}

my $btdir = "/Users/tdall/geniustrader/Backtests/";
my $dbfile = "/Users/tdall/geniustrader/traderThomas";
my ($file, $ind1, $idx1, $ind2, $idx2) = @ARGV;
my $numarg = @ARGV;
die "??? found $numarg arguments, should be 5\n" unless ($numarg == 5);
my (@in, $in, $sym, $device);
my @rmult = (); my @day = (); my @col = (); my @sym = (); my @ind1 = (); my @ind2 = ();

$file =~ /_(\d{8}T\d{6})_\d/;
my $unique = $1;

open IN, "<$file" or die "3djfgss8";
print "Processing trade # ";
while (chomp($in = <IN>)) {
    # each trade will result in one value of the indicators
    #
    next unless ($in =~ /^\d/);
    @in = split /\s+/, $in;
    next if ( ($opt_l && $in[2] eq "short") || ($opt_s && $in[2] eq "long") );
    # TODO: test each value for criteria before populating array
    push @rmult, $in[8];
    push @day, $in[4];
    if ($in[8] <= 0) {
        push @col, 2;
    } else {
        push @col, 3;
    }
    if ($in[8] > 8.0) {
        $sym = 10;
    } elsif ($in[8] > 6.0) {
        $sym = 8;
    } elsif ($in[8] > 4.0) {
        $sym = 6;
    } elsif ($in[8] > 3.0) {
        $sym = 5;
    } elsif ($in[8] > 2.0) {
        $sym = 4;
    } elsif ($in[8] > 1.0 || $in[8] < -1.0) {
        $sym = 3;
    } else {
        $sym = 2;
    }
    push @sym, $sym;
    if ($ind1 && $ind2) {
        # populate the two arrays @ind1 and @ind2 with indicator values
        # each trade produces one value for each (for the entry date)
        #
        @atr = getIndicator($in[1], "ATR14", 0, $in[4]) if ($ind1 =~ /Candle/ || $opt_a); # here we use ATR(14)
        print "got $atr[0] from $in[1] at $in[4]\n" if ( ! $atr[0] && ($ind1 =~ /Candle/ || $opt_a));
        if ($ind1 =~ /Candle-(.*)/) {
            $ctype = $1; 
            #                               ocATR;  (c-o)/ATR,
            #                               hlATR;  (h-l)/ATR, 
            #                               ochl;   (c-o)/(h-l),
            #                               oc01;   (c-o)/(c-o)1   [1 == day -1, i.e. prev. day] 
            #                               ochl1;  (c-o)/(h-l)1,
            #                               hl01;   (h-l)/(h-l)1
            #                               hl10;   (h-l)1/(h-l)
            #                               wrat;   uw/lw  (or lw/uw;  0 < wrat < 1)
        # ideas: ( (h-l)-body )/ATR,  body/( (h-l)-body ) , uw/lw
            chomp(@pdat = `sqlite3 "$dbfile" "SELECT day_open, day_high, day_low, day_close \\
								   FROM stockprices \\
								   WHERE symbol = '$in[1]' \\
								   AND date <= '$in[4]' \\
								   ORDER BY date \\
								   DESC LIMIT 2"`);
            @pd = split /\|/, $pdat[0]; 
            @py = split /\|/, $pdat[1];  # yesterdays prices
            my ($po, $ph, $pl, $pc) = @pd;  my ($yo, $yh, $yl, $yc) = @py;
            # renaming for easier access...
            if ($po < $pc) {    # white candle today
                $uw = $ph - $pc;
                $lw = $po - $pl;
                $cdir = 1;  # candle direction
                $body = $pc - $po;
                $maxb = $pc; $minb = $po; 
            } else {   # black candle today
                $uw = $ph - $po;
                $lw = $pc - $pl;
                $cdir = -1;
                $body = $po - $pc;
                $maxb = $po; $minb = $pc; 
            }
            # wick ratio, 0 < wrat < 1, is smaller divided by larger
            if ($uw == 0 || $lw == 0) {
                $wrat = 0;
            } elsif ($uw > $lw) {
                $wrat = $lw/$uw;
            } else {
                $wrat = $uw/$lw;
            }
            if ($ctype eq "ocATR") {
                push @ind1, ($pd[3]-$pd[0])/$atr[0];
            } elsif ($ctype eq "wrat") {
                push @ind1, $wrat;
            } elsif ($ctype eq "hlATR") {
                push @ind1, ($pd[1]-$pd[2])/$atr[0];
            } elsif ($ctype eq "ochl") {
                push @ind1, ($pd[3]-$pd[0])/($pd[1]-$pd[2]);
            } elsif ($ctype eq "oc01") {
                push @ind1, ($pd[3]-$pd[0])/($py[3]-$py[0]);
            } elsif ($ctype eq "ochl1") {
                push @ind1, ($pd[3]-$pd[0])/($py[1]-$py[2]);
            } elsif ($ctype eq "hl01") {
                push @ind1, ($pd[1]-$pd[2])/($py[1]-$py[2]);
            } elsif ($ctype eq "hl10") {
                push @ind1, ($py[1]-$py[2])/($pd[1]-$pd[2]);
            } else {
                die "no such type as $ctype\n";
            }
        } elsif ($ind1 =~ /Ext-(.*)/) {
            # 'external' indicators like BPI, MACD, etc.
            $ctype = $1;
            #                   BPI;    NYSE BPI
            #                   BPIsig; which signal is the BPI on?
            #                   MACD;   Weekly MACD of S&P500
            ($bpi, $bpisig, $macd) = marketStance($in[4]);
            if ($ctype eq "BPI") {
                $ind = 1 if $bpi =~ /[xX]/;
                $ind = -1 if $bpi =~ /[oO]/;
                push @ind1, $ind;
            } elsif ($ctype eq "BPIsig") {
                $ind = 0.5 if $bpisig =~ /b/;
                $ind = 1.5 if $bpisig =~ /B/;
                $ind = -0.5 if $bpisig =~ /s/;
                $ind = -1.5 if $bpisig =~ /S/;
                push @ind1, $ind;
            } elsif ($ctype eq "MACD") {
                push @ind1, $macd;
            } else {
                die "no such type as $ctype\n";
            }
        } else {
            my @my1 = getIndicator($in[1], $ind1, $dura, $in[4]);
            if ($idx1 >= 3) {
                push @ind1, $my1[0]-$my1[1]; # the indicator the day before
            } else {
                push @ind1, $my1[$idx1];
            }
        }
        my @my2 = getIndicator($in[1], $ind2, $dura, $in[4]);
            if ($idx2 == 3) {
                $my2 = $my2[0]-$my2[1]; # the indicator the day before
            } elsif ($idx2 == 4) {
                $my2 = $my2[1]/$my2[0];  # change-in-ADX/ADX (e.g.)
            } else {
                $my2 = $my2[$idx2];
            }
        if ($opt_r && $idx2 > 0) {  # we want relative i.e. percentage slopes
            push @ind2, $my2*100.0/$my2[0];
        } elsif ($opt_a) {  # we normalize by the ATR
            push @ind2, $my2/$atr[0];
        } else {
            push @ind2, $my2;
        }
    }
    $tick = $in[1]; print " .. $in[0]";
}
close IN;
print "\n";
$nr = @rmult;
$meanr = sum(@rmult)/$nr;
$sig = sigma($meanr, @rmult);
$ann = sprintf "$nr trades. <R> = %.2f+/-%.2f, SQ = %.2f", $meanr, $sig, $meanr/$sig;
$outfile = "${btdir}plot_${ind1}_${ind2}_${unique}_RwInd";
$outfile .= "-L" if ($opt_l);
$outfile .= "-S" if ($opt_s);

#&plotRvsIndicators();

#### ------ #####

#   $my_graph = GD::Graph::points->new(600,400);
my  $plot1 = Graphics::GnuplotIF->new();

my $num = @sym;
($yplot_low, $yplot_hig) = low_and_high(@ind2); 
($xplot_low, $xplot_hig) = low_and_high(@ind1);
$mean = ( $yplot_hig - $yplot_low ) * 0.05;
$yplot_hig += $mean; $yplot_low -= $mean;
$mean = ( $xplot_hig - $xplot_low ) * 0.05;
$xplot_hig += $mean; $xplot_low -= $mean;

$plot1 -> gnuplot_set_xrange($xplot_low, $xplot_hig);
$plot1 -> gnuplot_set_yrange($yplot_low, $yplot_hig);

$xtxt = "$ind1"; 
$xtxt .= "($idx1)" unless $ind1 =~ /Candle/;
$ytxt = "$ind2 ($idx2)";
$ytxt .= " /ATR" if ($opt_a);

$plot1->gnuplot_set_title( "$tick - $unique, N=$dura" );
$plot1->gnuplot_set_xlabel( "$xtxt" );
$plot1->gnuplot_set_ylabel( "$ytxt" );

#pgmtext('T', 1, 0.02, 0, "Note: only long trades!") if ($opt_l);
#pgmtext('T', 1, 0.02, 0, "Note: only short trades!") if ($opt_s);
#pgmtext('T', -1.1, 0.02, 0, "$ann");

$plot1->gnuplot_set_style( "lines" );
foreach $xline (@xlines) {
    $plot1 -> gnuplot_plot_xy( [$xline,$xline], [$yplot_low, $yplot_hig] );
}
foreach $yline (@ylines) {
    $plot1 -> gnuplot_plot_xy( [$xplot_low, $xplot_hig], [$yline,$yline] );
}
$plot1->gnuplot_set_style( "points" );
for ($i = 0; $i < $num; $i++) {
#    pgsci($col[$i]);
#    pgpoint(1, $ind1[$i], $ind2[$i], $sym[$i]);
    @x1 = ($ind1[$i]); @y1 = ($ind2[$i]);
    %y1 = ( 'y_values' => \@y1, 'style_spec' => "points pointtype 4 pointsize $syn[$i]");
    $plot1 -> gnuplot_plot_xy_style( \@x1, \%y1);
}

#$plot1->gnuplot_plot_xy( \@ind1, \@ind2 );

exit;
# below the GD plotting commands
#
@data = ( \@ind1, \@ind2 );

$my_graph -> set(
    x_label => $xtxt,
    y_label => $ytxt,
    x_tick_number => 'auto',
    title => "$tick - $unique, N=$dura",
    y_max_value => $yplot_hig,
    y_min_value => $yplot_low,
    x_max_value => 0.8,
    x_min_value => -0.1,
    legend_placement => 'TC',
    long_ticks => 1,
    marker_size => 6,
    markers => [ 8 ],
);

my $gd = $my_graph->plot(\@data) or die $graph->error;
  
if ($opt_p) {
    open(IMG, ">${outfile}.png") or die $!;
    binmode IMG;
    print IMG $gd->png;
    close IMG;
} 

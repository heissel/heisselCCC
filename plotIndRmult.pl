#!/usr/bin/perl -I/Users/tdall/copyExecs
# 
# takes data from file and makes a plot of the 2D landscpe for two indicators
#
# arg 0: file (a trade_* file)
# arg 1: indicator on x-axis
#   can be coded indicators, OR Candle-<type>, where <type> = 
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
# [-L] use only long trades
# [-S] use only short trades
# [-r] normalize/make percentages of the slope if that's what we asked for; only applies to y-axis indicator
# [-a] normalize the y-axis with the ATR
# [-E] exclude the current day, i.e. for previous day (in case of stop-buy order type of trades)
# [-n <N>] use for the long slope, default is 5
# [-x "x1 x2 x3 ..."] plot vertical lines at these x-positions
# [-y "y1 y2 y3 ..."] plot horizontal lines at these y-positions
# [-o "x1 y1 x2 y2"] plot a line through these coordinates
# [-l ind:val] only use trades for which indicator <ind> is less than <val>.
# [-g ind:val] only use trades for which indicator <ind> is greater than <val>.
#
# ***DONE: get ohlc for today and previous days to check sizes and ratios
# TODO: get scatter on the linfit slope as a parameter
# TODO; allow Kaufman market efficiency, then check if it correlates with slope/ATR
#use strict;
use Getopt::Std;
use PGPLOT;
require "utils.pl";
require "pg_utils.pl";
require "trader_utilsOLD.pl";

getopts('pLSran:x:y:Eo:g:l:');
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
if ($opt_o) {
    ($xlin[0], $ylin[0],$xlin[1], $ylin[1]) = split /\s+/, $opt_o;
}

my $btdir = "/Users/tdall/geniustrader/Backtests/";
my $dbfile = "/Users/tdall/geniustrader/traderThomas";
my ($file, $ind1, $idx1, $ind2, $idx2) = @ARGV;
my $numarg = @ARGV;
die "??? found $numarg arguments, should be 5\n" unless ($numarg == 5);
my (@in, $in, $sym, $device);
my @rmult = (); my @day = (); my @col = (); my @sym = (); my @ind1 = (); my @ind2 = ();

$file =~ /(.*)trades_.*_(\d{8}[TLS]\d{6})_\d/;  # grep and pipe to renamed files to get only long/short trades
$path = $1;
my $unique = $2;
$pfile = $path . "par_" . $unique . ".txt";

open IN, "<$file" or die "3djfgss8";
$readok = 0;
if (-e $pfile) {
    $readok = readpfile($pfile);
    $nind1 = @ind1;  $nind2 = @ind2;
}
while (chomp($in = <IN>)) {
    # each trade will result in one value of the indicators
    #
    last if ($in =~ /-1$/);
    next unless ($in =~ /\d:\t/);
    @in = split /\s+/, $in; #$nn = 0; foreach (@in) { print "pos$_\n"; $nn++; };  print "in = $in ::: pos 4 = $in[4]\n";
    next if ( ($opt_L && $in[2] eq "short") || ($opt_S && $in[2] eq "long") );
    # TODO: test each value for criteria before populating array
    if ($opt_E) {
        chomp( $day = `sqlite3 "$dbfile" "SELECT date \\
                               FROM stockprices \\
                               WHERE symbol = '$in[1]' \\
                               AND date < '$in[4]' \\
                               ORDER BY date \\
                               DESC LIMIT 1"` );
        $in[4] = $day;
    }
    push @rmult, $in[8] unless $readok;
    push @day, $in[4]; #print "day is $in[4] ---  "; exit;
}
$nr = @rmult;
$meanr = sum(@rmult)/$nr;
$sig = sigma($meanr, @rmult);
$tick = $in[1]; 
close IN;
&popColorSymbol();

print "There are $nr trades. Processing trade # ";
$count = 0;
foreach $day (@day) {
    $in[4] = $day;  # ...don't want to change all right now.
    $count++;     print " .. $count";
    if ($ind1 && $ind2 && $nind1*$nind2 == 0) {
        # populate the two arrays @ind1 and @ind2 with indicator values
        # each trade produces one value for each (for the entry date)
        #
        $atr[0] = atr($in[1], $dbfile, 14, $in[4]) if ($ind1 =~ /Candle/ || $opt_a); # here we use ATR(14)
        print "got $atr[0] from $in[1] at $in[4]\n" if ( ! $atr[0] && ($ind1 =~ /Candle/ || $opt_a));
        if ($ind1 =~ /Candle-(.*)/ && $nind1 == 0) {
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
        } elsif ($ind1 =~ /Ext-(.*)/ && $nind1 == 0) {
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
            } elsif ($ctype eq "p10wk") {
                ($column, $p10val, $p10s) = p10week($in[4]); #print "$in[4]: col = $column "; exit;
                $ind = 1 if $column =~ /[xX]/;
                $ind = -1 if $column =~ /[oO]/;
                if ($idx1 == 0) {
                    push @ind1, $p10s; #print "ind = $ind";
                } elsif ($idx1 == 1) {
                    push @ind1, $ind;
                } elsif ($idx1 == 2) {
                    push @ind1, $p10val;
                }
            } else {
                die "no such type as $ctype\n";
            }
        } elsif ($nind1 == 0) {
            my @my1 = getIndicator($in[1], $dbfile, $ind1, $dura, $in[4]);
            if ($idx1 >= 3) {
                push @ind1, $my1[0]-$my1[1]; # the indicator the day before
            } else {
                push @ind1, $my1[$idx1];
            }
        }
        if ($nind2 == 0) {
            my @my2 = getIndicator($in[1], $dbfile, $ind2, $dura, $in[4]);
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
    }
}
print "\n";
$ann = sprintf "$nr trades. <R> = %.2f+/-%.2f, SQ = %.2f", $meanr, $sig, $meanr/$sig;
$outfile = "${btdir}plot_${ind1}_${ind2}_${unique}_RwInd";
$outfile .= "-L" if ($opt_L);
$outfile .= "-S" if ($opt_S);
if ($opt_l || $opt_g) {
    # calc revised expectancy
    @newr = ();
    ($lind, $lval) = split /:/, $opt_l;
    ($gind, $gval) = split /:/, $opt_g;
    for ($i=0; $i < $nr; $i++) {
        if ( ($lind == 1 && $ind1[$i] > $lval)  ||  ($lind == 2 && $ind2[$i] > $lval) ) {
            next;
        }
        if ( ($gind == 1 && $ind1[$i] < $gval)  ||  ($gind == 2 && $ind2[$i] < $gval) ) {
            next;
        }
        push @newr, $rmult[$i];
    }
    $newn = @newr;
    $nmean = sum(@newr)/$newn unless $newn < 2;
    $nsig = sigma($nmean, @newr);
    $newt = sprintf "Restricted ($newn trades): <R> = %.2f, SQ = %.2f", $nmean, $nmean/$nsig;
}
&plotRvsIndicators();

if ($nind1*$nind2 == 0) {   # at least one of them is newly calculated, so update par-file
    open PF, ">$pfile" || die "ahkkd8923zz6";
    if ($readok) {
        print PF @phead;
    } else {
        $numinfile++;
        print PF "# 1: R 0\n";
    }
    if ($nind1 == 0 || !$readok) {
        $numinfile++;
        print PF "# $numinfile: $ind1 $idx1\n";
    }
    if ($nind2 == 0 || !$readok) {
        $numinfile++;
        print PF "# $numinfile: $ind2 $idx2\n";
    }
    $i = 0;
    if ($readok) {
        foreach $line (@pfile) {
            chomp($line);
            $add = "";
            $add .= " $ind1[$i]" if ($nind1 == 0);
            $add .= " $ind2[$i]" if ($nind2 == 0);
            print PF "$line $add\n";
            $i++;
        }
    } else {
        foreach $r (@rmult) {
            print PF "$r  $ind1[$i] $ind2[$i]\n";
            $i++;
        }
    }
    close PF;
}

#### ------ #####

sub popColorSymbol {
    my $r;
    foreach $r (@rmult) {    
        if ($r <= 0) {
            push @col, 2;
        } else {
            push @col, 3;
        }
        if ($r > 8.0) {
            $sym = 27;
        } elsif ($r > 6.0) {
            $sym = 26;
        } elsif ($r > 4.0) {
            $sym = 26;
        } elsif ($r > 3.0) {
            $sym = 25;
        } elsif ($r > 2.0) {
            $sym = 24;
        } elsif ($r > 1.0 || $r < -1.0) {
            $sym = 23;
        } else {
            $sym = 21;
        }
        push @sym, $sym;
    }
}

sub readpfile {
    my $pfile = shift;
    my ($i1, $i2, $ok);
    open PF, "<$pfile" || die "ah737sapzz6";
    $ok = 0;  $i1 = 0; $i2 = 0;
    while ($in = <PF>) {
        if ($in =~ /^#\s+(\d+):\s+(\w+)\s+(\d)/) {
            push @phead, $in;
            $indic{$1} = $2;
            $deriv{$2} = $3;
            $i1 = $1 if ($2 eq $ind1 && $3 == $idx1);
            ##if ($2 eq $ind1 && $3 == $idx1) {
            $i2 = $1 if ($2 eq $ind2 && $3 == $idx2);
            $ok = 1 if ($indic{1} eq "R");  # first col is always the R-multiples
            next;
        }
        last unless $ok; 
        push @pfile, $in; 
        @row = split /\s+/, $in;
        push @rmult, $row[0];
        if ($i1) {
            push @ind1, $row[$i1-1];
        }
        if ($i2) {
            push @ind2, $row[$i2-1];
        }
    }
    close PF;
    $numinfile = @row;
    return $ok;   
}


sub plotRvsIndicators{
    # not using strict; sharing variables with main program
    if ($opt_p) {
        $device = "${outfile}.png/PNG";
    } else {
        $device = "/XSERVE";
    }
    &myInitGraph();
    my $num = @sym;
    ($yplot_low, $yplot_hig) = low_and_high(@ind2); 
    ($xplot_low, $xplot_hig) = low_and_high(@ind1); #$nn=@ind1; print "$nn elements btw ($xplot_low, $xplot_hig)";exit;
    $mean = ( $yplot_hig - $yplot_low ) * 0.05;
    $yplot_hig += $mean; $yplot_low -= $mean;
    $mean = ( $xplot_hig - $xplot_low ) * 0.05;
    $xplot_hig += $mean; $xplot_low -= $mean;
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, 0) || warn "pgenv says $!\n";
    $xtxt = "$ind1"; 
    $xtxt .= "($idx1)" unless $ind1 =~ /Candle/;
    $ytxt = "$ind2 ($idx2)";
    $ytxt .= " /ATR" if ($opt_a);
    pglabel("$xtxt", "$ytxt", "$tick - $unique, N=$dura");
    pgmtext('T', 1, 0.02, 0, "Note: only long trades!") if ($opt_L);
    pgmtext('T', 1, 0.02, 0, "Note: only short trades!") if ($opt_S);
    pgsci(15);
    pgsch($charheight*0.7); # Set character height 
    pgmtext('T', -1.1, 0.02, 0, "$ann");
    pgmtext('T', -2.1, 0.02, 0, "$newt") if ($opt_l || $opt_g);
    foreach $xline (@xlines) {
        pg_plot_vertical_line($xline, 4, 14);
    }
    foreach $yline (@ylines) {
        pg_plot_horizontal_line($yline, 4, 14);
    }
    if ($opt_o) {
        pgsls(4);
        pgline(2, \@xlin, \@ylin);
        pgsls(1);
    }
    pgsci(1);  # default colour
    for ($i = 0; $i < $num; $i++) {
        pgsci($col[$i]);
        pgpoint(1, $ind1[$i], $ind2[$i], $sym[$i]);
    }
    pgsch($charheight); # Set character height 
    pgend || warn "pgend says $!\n";
    #sleep 2 unless ($opt_p);
}

sub myInitGraph {    
    $font = 2;
    $linewidth = 2;
    $charheight = 1.2;
    pgbeg(0,$device,1,1) || warn "pgbeg says $!\n"; # Open plot device 
    pgscf($font); # Set character font 
    pgslw($linewidth); # Set line width 
    pgsch($charheight); # Set character height 
    pgsci(1);  # default colour
}


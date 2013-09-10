#!/usr/bin/perl -I/Users/tdall/copyExecs
#
### [-F] use the predefined filter - setup applied retrospecively... TODO
# [-p] plot the total drawn distribution to PNG file. If not given, plots on screen
# [-n] no simulations, just print stats
# [-l] stats only for the long trades
# [-s] stats only for the short trades
# [-a <date>] only trades on or after this date
# [-b <date>] only trades on or before this date
# [-V] non-verbose; only report the system numbers
# [-N <ntrades>] number of trades in simul series (otherwise hardcoded default = 10)
# [-r <ruinP>] drawdown considered ruin in % (otherwise hardcoded default = 10)
# [-o <objectiveGain>] objective to make this many % return in ntrades (otherwise hardcoded defalult = 30)
# [-m <maxRiskP>] max percentage risk for the simulation (otherwise hardcoded defalult = 2.0)
# [-i <minRiskP>] min percentage risk for simulation (otherwise use as default the step size (of 0.1))
# [-R <fac>] risk management; adjust risk percentage with drawdown as risk = risk0 * (1 - dd*fac)
# [-M <mmp>] markets-money position sizing; above base-equity risk mmp %. Set base equity to 1.5*eq when eq > 2*base-eq
# [-X] remove highest-R trade

use Carp;
use Getopt::Std;
use PGPLOT;
#use GD::Graph::points;
require "utils.pl";
require "pg_utils.pl";
require "trader_utils.pl";

$|=1;
getopts('pnFlsa:b:VN:R:o:r:m:XM:i:');
srand();

$havefiles = @ARGV;
unless ($havefiles) {
    print "# [-p] plot the total drawn distribution to PNG file. If not given, plots on screen
# [-n] no simulations, just print stats
# [-l] stats only for the long trades
# [-s] stats only for the short trades
# [-a <date>] only trades on or after this date
# [-b <date>] only trades on or before this date
# [-V] non-verbose; only report the system numbers
# [-N <ntrades>] number of trades in simul series (otherwise hardcoded default = 10)
# [-r <ruinP>] drawdown considered ruin in % (otherwise hardcoded default = 10)
# [-o <objectiveGain>] objective to make this many % return in ntrades (otherwise hardcoded defalult = 30)
# [-m <maxRiskP>] max percentage risk for the simulation (otherwise hardcoded defalult = 2.0)
# [-i <minRiskP>] min percentage risk for simulation (otherwise use as default the step size (of 0.1))
# [-R <fac>] risk management; adjust risk percentage with drawdown as risk = risk0 * (1 - dd*fac)
# [-M <mmp>] markets-money position sizing; above base-equity risk mmp %. Set base equity to 1.5*eq when eq > 2*base-eq
# [-X] remove highest-R trade
";
    exit();
}
# input values
#
# slippage per trade - transaction costs are already taken into account
if ($opt_r) {
    $ruinP = $opt_r;
} else {
    $ruinP = 10.0;  # ruin, or max drawdown, percentage
}
if ($opt_m) {
    $maxrisk = $opt_m;
} else {
    $maxrisk = 2.0;  # max percentage risk for the simulation
}
if ($opt_o) {
    $objective = $opt_o;
} else {
    $objective = 30.0;  # objective to make this many % return in $ntrades
}
if ($opt_R) {
    $ddfac = $opt_R;
}
if ($opt_N) {
    $ntrades = $opt_N;
} else {
    $ntrades = 10;  # number of trades for which we want results
}
$rMM = $opt_M if ($opt_M);
$nsim = 10000;  # number of simulations at each risk %
$pincr = 0.1;  # increment in percent risk, also the starting risk in the simulation
if ($opt_i) {
    $minRisk = $opt_i;
} else {
    $minRisk = $pincr;
}

# run for each file on the command line
#
foreach $file (@ARGV) {   # automatic glob...
    # initializing variables
    #
    @rmult = (); @rpos = (); @rneg = ();
    @bigr2 = (); @bigr3 = (); @bigr5 = (); @bigr10 = (); @bigr15 = (); @bigr20 = ();
    @equity = (); @dd = (); @lstreak = (); @meanr = (); @xr = ();
    # read the distribution and prepare the basic statistics
    #
    $file =~ /(.*)trades_.*_(\d{8}T\d{6})_\d/;
    $path = $1;
    $unique = $2;
    $pfile = $path . "par_" . $unique . ".txt";
    if ($unique) {
        $outfile = "simul_$unique.txt";
    } else {
        $outfile = "simul.txt";
    }
    if ($opt_F && -e "$pfile") {
        open PF, "<$pfile" || die "x284nsfrp89w";
    }
    open OUT, ">$outfile" or die "fail open output";
    open IN, "<$file" or die "cannot open file=$file\n";
    $maxr = 0.0;
    while (chomp($in = <IN>)) {
        if ($in =~ /^System = (.*), Initial stop method = (.*), Exit\/Stop = (.*)$/) {
            print OUT "# $in\n";
            print "# $in\n";
            $o_sys = $1; $o_istop = $2; $o_stop = $3;
        }
        if ($in =~ /Comment:/) {
            print OUT "$in\n";
            print "$in\n"; 
        }
        next unless ($in =~ /\d:\t/);
        @in = split /\s+/, $in;
        if ($opt_F  && -e "$pfile") {
            # missing... 
        }
        next if ($opt_l && $in[2] eq "short");
        next if ($opt_s && $in[2] eq "long");
        next if ($opt_a && $in[4] lt $opt_a);
        next if ($opt_b && $in[4] gt $opt_b);
        push @rmult, $in[8];
        $maxr = $in[8] if ($in[8]>$maxr);
    }
    close IN;
    if ($opt_X) {
        @tmpr = ();
        foreach $in (@rmult) {
            push @tmpr, $in unless ($in == $maxr);
        }
        @rmult = @tmpr;
    }
    foreach $in (@rmult) {
        if ($in > 0.0) {
            push @rpos, $in;
        } else {
            push @rneg, $in;
        }
        if ($in >= 2.0) {
            push @bigr2, $in;
        }
        if ($in >= 3.0) {
            push @bigr3, $in;
        }
        if ($in >= 5.0) {
            push @bigr5, $in;
        }
        if ($in >= 10.0) {
            push @bigr10, $in;
        }
        if ($in >= 15.0) {
            push @bigr15, $in;
        }
        if ($in >= 20.0) {
            push @bigr20, $in;
        }
    }
    @big = (2, 3, 5, 10, 15, 20);
    $n = @rmult;   # number of R values in the distribution
    if ($n < 3) {
        warn "Error; $n trades taken.\n";
        next;
    }
    $meanr = sum(@rmult) / $n;
    $sigr = sigma($meanr, @rmult);
    $npos = @rpos;  $nneg = @rneg;
    $meanpos = sum(@rpos)/$npos;
    $sigpos = sigma($meanpos,@rpos);
    $meanneg = sum(@rneg)/$nneg;
    $signeg = sigma($meanneg,@rneg);
    $stderr = 0.0; $stderr = 100.0*sqrt($n+1)/$n if ($n>0) ;
    print OUT "# Based on $file\n";
    if ($opt_V) {
        printf OUT "<R> = %.2f, SQ = %.2f, N = $n, W/L = %d/%d, <R_pos> = %.2f +/- %.2f, <R_neg> = %.2f +/- %.2f. $unique\n", 
            $meanr, $meanr/$sigr, int(100*$npos/$n), 100-int(100*$npos/$n), $meanpos, $sigpos, $meanneg, $signeg;
        printf "<R> = %.2f, SQ = %.2f, N = $n, W/L = %d/%d, <R_pos> = %.2f +/- %.2f, <R_neg> = %.2f +/- %.2f. $unique, $o_sys $o_istop $o_stop\n", 
            $meanr, $meanr/$sigr, int(100*$npos/$n), 100-int(100*$npos/$n), $meanpos, $sigpos, $meanneg, $signeg;
    } else {
        printf OUT "# System Expectancy = %.2fR, SQ = %.2f. Sample size = $n\n", $meanr, $meanr/$sigr;
        printf OUT "# W/L = %d/%d, W/L-ratio = %d/%d. <R_pos> = %.2f +/- %.2f, <R_neg> = %.2f +/- %.2f\n",
            $npos, $nneg, int(100*$npos/$n), 100-int(100*$npos/$n), $meanpos, $sigpos, $meanneg, $signeg;
        print "# Based on $file\n";
        printf "# System Expectancy = %.2fR, SQ = %.2f. Sample size = $n\n", $meanr, $meanr/$sigr;
        printf "# W/L = %d/%d, W/L-ratio = %d/%d. <R_pos> = %.2f +/- %.2f, <R_neg> = %.2f +/- %.2f\n",
            $npos, $nneg, int(100*$npos/$n), 100-int(100*$npos/$n), $meanpos, $sigpos, $meanneg, $signeg;
        $ibig = 0;
        if (@bigr2) {
            $nbig = @bigr2;
            $meanb = sum(@bigr2) / $nbig;
            printf "$nbig/$n trades (%.2f%) above $big[$ibig]R. <R(r>$big[$ibig])> = %.2f\n", 100.0*$nbig/$n, $meanb;
            printf OUT "# $nbig/$n trades (%.2f%) above $big[$ibig]R. <R(r>$big[$ibig])> = %.2f\n", 100.0*$nbig/$n, $meanb;
            $ibig++;
        }
        if (@bigr3) {
            $nbig = @bigr3;
            $meanb = sum(@bigr3) / $nbig;
            printf "$nbig/$n trades (%.2f%) above $big[$ibig]R. <R(r>$big[$ibig])> = %.2f\n", 100.0*$nbig/$n, $meanb;
            printf OUT "# $nbig/$n trades (%.2f%) above $big[$ibig]R. <R(r>$big[$ibig])> = %.2f\n", 100.0*$nbig/$n, $meanb;
            $ibig++;
        }
        if (@bigr5) {
            $nbig = @bigr5;
            $meanb = sum(@bigr5) / $nbig;
            printf "$nbig/$n trades (%.2f%) above $big[$ibig]R. <R(r>$big[$ibig])> = %.2f\n", 100.0*$nbig/$n, $meanb;
            printf OUT "# $nbig/$n trades (%.2f%) above $big[$ibig]R. <R(r>$big[$ibig])> = %.2f\n", 100.0*$nbig/$n, $meanb;
            $ibig++;
        }
        if (@bigr10) {
            $nbig = @bigr10;
            $meanb = sum(@bigr10) / $nbig;
            printf "$nbig/$n trades (%.2f%) above $big[$ibig]R. <R(r>$big[$ibig])> = %.2f\n", 100.0*$nbig/$n, $meanb;
            printf OUT "# $nbig/$n trades (%.2f%) above $big[$ibig]R. <R(r>$big[$ibig])> = %.2f\n", 100.0*$nbig/$n, $meanb;
            $ibig++;
        }
        if (@bigr15) {
            $nbig = @bigr15;
            $meanb = sum(@bigr15) / $nbig;
            printf "$nbig/$n trades (%.2f%) above $big[$ibig]R. <R(r>$big[$ibig])> = %.2f\n", 100.0*$nbig/$n, $meanb;
            printf OUT "# $nbig/$n trades (%.2f%) above $big[$ibig]R. <R(r>$big[$ibig])> = %.2f\n", 100.0*$nbig/$n, $meanb;
            $ibig++;
        }
        if (@bigr20) {
            $nbig = @bigr20;
            $meanb = sum(@bigr20) / $nbig;
            printf "$nbig/$n trades (%.2f%) above $big[$ibig]R. <R(r>$big[$ibig])> = %.2f\n", 100.0*$nbig/$n, $meanb;
            printf OUT "# $nbig/$n trades (%.2f%) above $big[$ibig]R. <R(r>$big[$ibig])> = %.2f\n", 100.0*$nbig/$n, $meanb;
            $ibig++;
        }
    }
    
    # for each risk value make $nsim trades, each with $ntrades trades and store the resulting equity (0 if less than ruin%)
    #
    unless ($opt_n) {
        print OUT "# Ruin = $ruinP% drawdown, Objective = $objective%\n";
        print OUT "# $ntrades trades in $nsim simulations at each risk % up to $maxrisk%."; printf OUT " StdErr = %.2f",$stderr; print OUT "%\n";
        print "# Ruin = $ruinP% drawdown, Objective = $objective%\n";
        print "# $ntrades trades in $nsim simulations at each risk % up to $maxrisk%."; printf " StdErr = %.2f",$stderr; print "%\n";
        print     "risk%\t%objec\t%ruin\tav.gain%\tmin.g%\tmed.g%\tmax.g%\t%loss\tav.dd%\tmax.dd%\tdd.p1%\tdd.p2%\tdd.p5%\tdd.p10%\tdd.p25%\tdd.p50%\tdd.p75%\tdd.p90%\tdd.p95%\tmin.dd%\tav.lst\tmax.lst\tmin.lst\n";
        print OUT "risk%\t%objec\t%ruin\tav.gain%\tmin.g%\tmed.g%\tmax.g%\t%loss\tav.dd%\tmax.dd%\tdd.p1%\tdd.p2%\tdd.p5%\tdd.p10%\tdd.p25%\tdd.p50%\tdd.p75%\tdd.p90%\tdd.p95%\tmin.dd%\tav.lst\tmax.lst\tmin.lst\n";
        ### for each risk % do this:
        ###
        @meanr = ();
        for ($rr = $minRisk; $rr <= $maxrisk; $rr+=$pincr) {
            @equity = ();
            @dd = ();
            @lstreak = ();
            ### do a large number (nsim) of runs, each ntrades long
            ###
            for ($s = 1; $s <= $nsim; $s++) {
                $eq = 100.0;  #print "doing sim #$s .. ";
                $dd = 0.0; $maxdd = 0.0;
                $eqhigh = 100.0;
                $eqbase = 100.0;
                $nloser = 0; $lloser = 0; # length of losing streaks
                $meanr = 0;
                $r0 = $rr;   # the standard risk % for this run
                $r = $rr;   # the (perhaps variable) risk for this run
                ### do a sequence of trades
                ###
                for ($t = 1; $t <= $ntrades; $t++) {
                    if ($opt_M) {
                        if ($eq > $eqbase) {
                            $r = $rMM - ($eqbase/$eq)*($rMM-$r0);
                        }
                        if ($eq > 2*$eqbase) {
                            $eqbase = 1.5*$eqbase;
                        }
                    }
                    $itrade = int(rand $n); 
                    $gain = ($eq * $r / 100.0) * $rmult[$itrade];
                    $meanr += $rmult[$itrade];
                    if ($gain > 0) {
                        $nloser = 0;
                    } else {
                        $nloser++;
                    }
                    if ($nloser > $lloser) {
                        $lloser = $nloser;
                    }
                    $eq += $gain;
                    if ($eq > $eqhigh) {
                        if ($opt_R) {
                            $r = $r0 * (1.0 + ($eq-$eqhigh)/$eqhigh);
                            $r = $maxrisk if ($r > $maxrisk && !$opt_M);
                        }
                        $eqhigh = $eq;
                        $dd = 0.0;
                    }
                    if (($eqhigh - $eq)/$eqhigh > $dd) {
                        $dd = ($eqhigh - $eq)/$eqhigh;
                        if ($opt_R) {
                            $r = $r0 * (1.0 - $dd*$ddfac);
                        }
                    }
                    if ($dd > $maxdd) {
                        $maxdd = $dd;
                    }
                    #if ($eq < (100.0 - $ruinP) ) {
                    #    $eq = 0.0; #print "got a ruin...";
                    #    # could consider setting $maxdd = 100.0;
                    #    last;
                    #}
                    if ($eq < 0.0) {
                        $eq = 0.0;
                        last;
                    }
                }
                push @equity, $eq;
                push @dd, $maxdd;
                push @lstreak, $lloser;
                push @meanr, $meanr/$ntrades;   
                ### TODO; measure of eq-peak/maxdd, either one number for the total simulation or number +/- rms for the given N
            }
            $r = $r0;   # resetting
            $avl = sum(@lstreak);
            $avl /= $nsim;
            ($minl, $maxl) = low_and_high(@lstreak);
            $mdd = sum(@dd);
            $mdd /= $nsim;
            ($mindd, $maxdd) = low_and_high(@dd);
            @sdd = reverse sort { $a <=> $b } @dd;
    #         printf "Drawdowns at 5% = %.1f, 10% = %.1f, 25% = %.1f, 50% = %.1f, 75% = %.1f, 90% = %.1f, 95% = %.1f\n",
    #             $sdd[int($nsim*0.05)]*100, $sdd[int($nsim*0.10)]*100, $sdd[int($nsim*0.25)]*100, $sdd[int($nsim*0.50)]*100, 
    #             $sdd[int($nsim*0.75)]*100, $sdd[int($nsim*0.90)]*100, $sdd[int($nsim*0.95)]*100; 
            ($min, $max) = low_and_high(@equity);
            $mean = sum(@equity); 
            $mean /= $nsim;
            $median = median(\@equity);
            $objok = 0;  $nruin = 0; $nloss = 0;
            foreach $eq (@equity) {
                if ($eq > $objective + 100.0) {
                    $objok++;
                } elsif ($eq < (100.0 - $ruinP) ) { #### == 0.0) {
                    $nruin++;
                }
                if ($eq < 100.0) {
                    $nloss++;
                }
    
            }
            for ($i = 0; $i < $nsim; $i++) {
                $equity[$i] -= 100.0;
            }
            $sig = sigma($mean-100.0, @equity);
            printf     "%4.1f:\t%.1f\t%.1f\t%.1f+/-%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t>%.1f\t>%.1f\t>%.1f\t>%.1f\t>%.1f\t>%.1f\t>%.1f\t>%.1f\t>%.1f\t%.1f\t%.1f\t${maxl}\t${minl}\n", 
                $r, $objok*100.0/$nsim, $nruin*100.0/$nsim, $mean-100.0, $sig, $min-100.0, $median-100.0, $max-100.0, $nloss*100.0/$nsim,
                $mdd*100, $maxdd*100, $sdd[int($nsim*0.01)]*100, $sdd[int($nsim*0.02)]*100, $sdd[int($nsim*0.05)]*100, $sdd[int($nsim*0.10)]*100, $sdd[int($nsim*0.25)]*100, $sdd[int($nsim*0.50)]*100, 
                $sdd[int($nsim*0.75)]*100, $sdd[int($nsim*0.90)]*100, $sdd[int($nsim*0.95)]*100, $mindd*100, $avl;
            printf OUT "%4.1f:\t%.1f\t%.1f\t%.1f+/-%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t>%.1f\t>%.1f\t>%.1f\t>%.1f\t>%.1f\t>%.1f\t>%.1f\t>%.1f\t>%.1f\t%.1f\t%.1f\t${maxl}\t${minl}\n", 
                $r, $objok*100.0/$nsim, $nruin*100.0/$nsim, $mean-100.0, $sig, $min-100.0, $median-100.0, $max-100.0, $nloss*100.0/$nsim,
                $mdd*100, $maxdd*100, $sdd[int($nsim*0.01)]*100, $sdd[int($nsim*0.02)]*100, $sdd[int($nsim*0.05)]*100, $sdd[int($nsim*0.10)]*100, $sdd[int($nsim*0.25)]*100, $sdd[int($nsim*0.50)]*100, 
                $sdd[int($nsim*0.75)]*100, $sdd[int($nsim*0.90)]*100, $sdd[int($nsim*0.95)]*100, $mindd*100, $avl;
        }
    }
    close OUT;
    &plotDist() unless $opt_n;
}

######

sub plotDist {
    if ($opt_p) {
        $device = "stat_${unique}.png/PNG";
    } else {
        $device = "/XSERVE";
    }
    myInitGraph();
    $numTrades = @meanr;
    ($xplot_low, $xplot_hig) = low_and_high(@meanr);
    $step = ($xplot_hig - $xplot_low)/14.0;
    @txr = (0 .. 14); @xr = ();
    %count = ();
    RMUL:foreach $r (@meanr) {
        foreach $xr (@txr) {
            push @xr, $xplot_low + $xr * $step;
        }
        foreach $xr (@xr) {
            if ($r >= $xr && $r < $xr+$step) {
                $count{$xr}++;  next RMUL;
            } elsif ($r >= $xr[-1]+$step) {
                $count{$xr[-1]}++;  next RMUL;
            } elsif ($r < $xr[0]) {
                $count{$xr[0]}++;  next RMUL;
            }
        }
    }
    @yr = values %count;
    @xr = keys %count;
    $numx = @xr;
    @yr = div_array(\@yr, $numTrades);
    ($yplot_low, $yplot_hig) = low_and_high(@yr); 
    ($xplot_low, $xplot_hig) = low_and_high(@xr);
    $xplot_low -= $step; $xplot_hig += $step;
    $mean = ( $yplot_hig - $yplot_low ) * 0.05;
    $yplot_hig += $mean;
    pgenv($xplot_low, $xplot_hig, 0.0, $yplot_hig, 0, 0) || warn "pgenv-plotRdist says $!\n";
    $meanR = sum(@meanr)/$numTrades; 
    $txt = sprintf "<R> = %.2f", $meanR;
    $ytxt = "N = $numTrades";
    pglabel("$txt", "$ytxt", "tradeStatSimul - $unique");
    pgslw(1);
    pgsci(12);
    pgsfs(1); # fill is true
    for ($i = 0; $i < $numx; $i++) {
        if ($yr[$i] > 0) {
            pgrect($xr[$i]+0.1*$step, $xr[$i]+0.9*$step, 0.0, $yr[$i]);
        }
    }
    pgslw($linewidth);
    pg_plot_vertical_line($meanR, 2, 15);
    pgend;

}
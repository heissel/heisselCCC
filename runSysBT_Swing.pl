#!/usr/bin/perl -I/Users/tdall/copyExecs
# 
# 
# -r : reprocess all the summary_ files in Backtests/
use Getopt::Std;
getopts('r');
@tstart = times;
$tstart = time;
($tick, $day1, $day2) = @ARGV;
die "sasasa" unless $day2;
if ($tick =~ /tick/) {
    open IN, "<../$tick" or die "bs481jazpt885";
    chomp(@tick = <IN>);
} else {
    @tick = ($tick);
}
$| = 1;
my $btdir = "/Users/tdall/geniustrader/Backtests/";
# parameters
#
&paramsSwing();
open OUT, ">$btdir/oub_${stem}${longshort}_${istop}_${stop}.txt" || die "239db32laa390";
print OUT "#TICK\tSMA\tFAC\tTR%\tATRP\tIS\tSTOP\tSTOP2\n";
unless ($softtarget) {
    push @soft, ""; push @soft2, "";
}
unless ($hardtarget) {
    push @hard, "";
}
unless ($rsecure) {
    push @rsec, "";
}
$totnum = @tick * @smaper * @f * @aval * @atrper * @trfac * @istop * @stop * @stop2 * @rsec * @hard * @soft * @soft2;
if ($opt_r) {
    &reprocessSummary();
} else {
#print "tick: @tick\nsoft: @soft\nsoft2: @soft2\nsmaper: @smaper\nf: @f\ntrfac: @trfac\natrper: @atrper\nstop: @stop\nstop2: @stop2\nistop: @istop";
# looping...
#
printf "Starting processing $totnum tests - could take up to %d minutes...\n", 1.5*$totnum;
foreach $tick (@tick) {
foreach $soft (@soft) {
    foreach $soft2 (@soft2) {
        foreach $smaper (@smaper) {
        foreach $f (@f) {
        $f .= ".0" if (int($f) == $f && $f !~ /\./);
        foreach $trfac (@trfac) {
        $trfac .= ".0" if (int($trfac) == $trfac && $trfac !~ /\./);
        foreach $aval (@aval) {
            foreach $atrper (@atrper) {
#            next if ($atrper >= $trfac);  # for Luxor/ cross system
            foreach $vstop (@stop) {
#                next if ($vstop > 2*$trfac);
                foreach $vstop2 (@stop2) {
                $vstop2 .= ".0" if (int($vstop2) == $vstop2 && $vstop2 !~ /\./);
                foreach $vistop (@istop) {
                    $vistop .= ".0" if (int($vistop) == $vistop && $vistop !~ /\./);
#                    next if ($vistop > 2*$trfac);
                    foreach $rsec (@rsec) {
                        foreach $hard (@hard) {
                            if ($softtarget) {
                                $optT = " -T${soft}${softtarget}${soft2}";
                            }
                            if ($hardtarget) {
                                $sys = $system . "${hardtarget}${hard}${longshort}";
                            } else {
                                $sys = $system . $longshort;
                            }
                            if ($comment) {
                            #    $optC = " -C \"$comment, NOT using %10wk, NOT very-conservative-test\"";
                            #    $optC = " -C \"$comment sequence of soft stop (c)\"";
                                $optC = " -C \"$comment\"";
                            }
                            if ($setup) {
                                $optS = "-U -S${setup}${smaper}$prefix$f ";
                                #$optS = "-U -S${setup}${atrper}$prefix$f ";
                                $optS = "-U -S${setup}$smaper " if $setup =~ /HiLo/;
                            }
                            #$trailstop = "${stop}_${vstop}_0.1p";
                            #$trailstop = "${stop}_${atrper}_${vstop}";
                            #$trailstop = "${stop}_${atrper}_${vistop}"; # same as istop!!
                            $trailstop = "${stop}_${vstop}_${vstop2}p";
                            if ($rsecure) {
                                $trailstop .= "_${rsecure}_$rsec";
                            }
#                            $myi = $trfac - 1;
#                            $initstop = "${istop}_${myi}_${vistop}px";
                            $initstop = "${istop}_${atrper}_${vistop}" if ($istop =~ /Vola/);
                            $initstop = "${istop}_${vistop}$pct" if ($istop =~ /Percent/);
                            #$initstop = "Local_${vstop}_0.3p";  # for initial runs to see which are profitable or not
                            $system = "${stem}${when}${trfac}A${aval}";  
                            $sys = $system . $longshort;        # comment if using $hardtarget!!!
                            $fixed = "./backtest.pl -R -k$atrper:$smaper -f$fee -u$slip ${optS}-n -p${optC}";
                            #$com = "$fixed$optT $tick $day1 $day2 $sys ${istop}_${atrper}_${vistop} $trailstop";
                            #$com = "$fixed$optT $tick $day1 $day2 $sys $initstop $trailstop"; # Candle
                            $com = "$fixed$optT $tick $day1 $day2 $sys $initstop $trailstop"; # VolBC
                            print "$com\n";
                            `$com`;
                            &processUnique();
    } } } } } } } } } } } } }
close OUT;
}
@tend = times;
$tend = time;
printf "Time: %.2f CPU seconds, %.2f minutes for $totnum runs\n", ($tend[0]-$tstart[0]), ($tend-$tstart)/60.0;

sub paramsSwing {
# backtest.pl -R -f5.9 -k7:60 -s12:60 -SSMA60r0.0:0.5ATRS7f0.0 -xn -p BMW.DE 2004-01-17 2012-07-20 SwingE4A7Long Percent_1.5c Local_4_0.3p
# First test:
#   one SMA period. Only vary trfac, use two Local_N stops (e.g. 3,7) as istop = stop.
#   From this, decide on good range of TR% and fix the M-param (col -x12)
# Second test:
#   Decide on decent istop, either Percent or Vola
# Third test:
#   with the selected TR%, vary SMA
#   decide on which SMA to test with f/r (col -x13)
    $stem = "Swing";  
    $when = "E";    # E=exit on a swing change, S=exit only on stop
    $fee = 5.90;  $slip = 0.0;
    $file = "";
    $setup = "SMA";   # SMA, ....
    @smaper = (95);
    $prefix = "f";
    @f = (0);
    $longshort = "Short";  # set to Long or Short to test only that 
    $comment = ""; 
#    @trfac is swing period in percent
    @trfac = (17);  # Swing filter size in %
#    @trfac = (15);
    @aval = (0);  # modifyer for the Swing filter, set to 0 to have no effect
    @atrper = (10); # only for istop and the -S option
    $istop = "Percent";  # Vola, Percent Local
    $pct = "c";  # if Percent, set to 'c' to take from the close.
    @istop = (2.6);
    $stop = "Local";
    @stop = (3,4);
#    @stop2 = (0.1);
    @stop2 = (0.2,0.3,0.4,0.6,0.9,1.5);
    $softtarget = "";  # empty, x, c, o
    @soft = ();
    @soft2 = ();
    $hardtarget = "";
    @hard = ();
    $rsecure = "";
    @rsec = ();
#    $rsecure = "Rmult_rstop";
#    @rsec = ("0.5_0.3", "0.7_0.5", "0.7_0.7", "0.9_0.5", "0.9_0.7", "1.0_0.8", "1.0_1.0");
}

sub processUnique {
    open UNIQ, "<$btdir/unique.txt" or die "nzt238dHW44";
    chomp($unique = <UNIQ>);
    close UNIQ;
    print "unique = $unique\n";
    $list = "";
    $sfile = "$btdir/summary_${sys}_${tick}_${unique}_${day1}_${day2}.txt";
    if (-e $sfile) {
        print "processing $sfile ...\n";
        open IN, "<$sfile" or die "zz846dhhns on $sfile\n";
        while ($in = <IN>) {
            if ($in =~ /toread: (.*)/) {
                $list = $1; chomp $list;
            }
        }
        close IN;
        print OUT "$tick\t$smaper\t$f\t$trfac\t$aval\t$atrper\t$vistop\t$vstop\t${vstop2}\t$list\t$unique\n";
    } else {
        warn "WARN: no such file $sfile...\n";
    }
}

sub reprocessSummary {
#    open OUT, ">$btdir/oub_${stem}${longshort}_${istop}_${stop}.txt" || die "239db32laa390";
#    print OUT "#TICK\tTR\tATR\tIS\tSTOP\n";
    @g = `ls -1tr $btdir/summary_*.txt`; #<$btdir/summary_*.txt>;
    chomp @g;
    foreach $sfile (@g) {
        print "processing $sfile ...\n";
        open IN, "<$sfile" or die "zz846dhhns on $sfile\n";
        while ($in = <IN>) {
            if ($in =~ /toread: (.*)/) {
                $list = $1; chomp $list;
            }
            if ($in =~ /^Comment.*-SSMA(\d+)f(\d+.?\d*)/) {
                $smaper = $1; $f = $2;
            }
            if ($in =~ /System = VolEOD(\d+)C(\d+)\w*, Initial stop method = Vola \d+ (\d+.?\d*), Exit\/Stop = Local (\d+) (\d+.?\d*)/) {
                $trfac = $1; $atrper = $2; $vistop = $3; $vstop = $4;  $vstop2 = $5;
            }
        }
        close IN;
        print OUT "$tick\t$smaper\t$f\t$trfac\t$atrper\t$vistop\t$vstop\t${vstop2}\t$list\n";
    }
    close OUT;
}
# ./systemBacktest.pl -p -x13 -X8 -T2.0x2 -f ../Backtests_volbreak1/trades_goodMoves.txt 
#       BMW.DE 2012-03-17 2012-06-15 VolBC70A5R50l900 
#       TrueRange_105 TrueRange_140_Rmult_rstop_0.6_0.4_0.8_0.5_1.1_0.8
# System = VolBC100A5Short, Initial stop method = Vola 5 2.4x, Exit/Stop = Percent 3

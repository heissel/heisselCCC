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
&paramsCandle();
open OUT, ">$btdir/oub_${stem}${longshort}_${istop}_${stop}.txt" || die "239db32laa390";
print OUT "#TICK\tSMA\tFAC\tTR%\tATRP\tIS\tSTOP\tSTOP2\tPALT\n";
unless ($softtarget || @soft) {
    push @soft, ""; push @soft2, "";
}
unless ($hardtarget || @hard) {
    push @hard, "";
}
unless ($rsecure) {
    push @rsec, "";
}
$totnum = @smaper * @f * @atrper * @trper * @istop * @stop * @stop2 * @rsec * @hard * @soft * @soft2;
if ($opt_r) {
    &reprocessSummary();
} else {
#print "tick: @tick\nsoft: @soft\nsoft2: @soft2\nsmaper: @smaper\nf: @f\ntrfac: @trfac\natrper: @atrper\nstop: @stop\nstop2: @stop2\nistop: @istop";
# looping...
#
if ($totnum*1.5 > 90) {
    printf "Starting processing $totnum tests - could take up to %d hours...\n", 1.5*$totnum/60;
} else {
    printf "Starting processing $totnum tests - could take up to %d minutes...\n", 1.5*$totnum;
}
$nn = 1;
foreach $tick (@tick) {
foreach $soft (@soft) {
    foreach $soft2 (@soft2) {
        foreach $smaper (@smaper) {
        foreach $f (@f) {
        $f .= ".0" if (int($f) == $f && $f !~ /\./ && ($setup !~ /sma/ && $setup !~ /HiLo/));
            foreach $atrper (@atrper) {
            foreach $trper (@trper) {
#            next if ($atrper >= $trfac);  # for Luxor/ cross system
            next if ($trper >= $smaper);
            foreach $vstop (@stop) {
#                next if ($vstop > 2*$trfac);
                foreach $vstop2 (@stop2) {
                $vstop2 .= ".0" if (int($vstop2) == $vstop2 && $vstop2 !~ /\./);
                foreach $vistop (@istop) {
                    $vistop .= ".0" if (int($vistop) == $vistop && $vistop !~ /\./);
#                    next if ($vistop > 2*$trfac);
                    foreach $rsec (@rsec) {
                        foreach $hard (@hard) {
                            $addstop = "";
                            if ($softtarget =~ /^M/) {
                                $addstop = "${softtarget}-${soft}-${soft2}-${hard}";
                                next if ($hard > $vstop);
                            } elsif ($softtarget) {
                                $optT = " -T${soft}${softtarget}${soft2}";
                            }
                            if ($hardtarget) {
                                $sys = $system . "${hardtarget}${hard}${longshort}";
                            } else {
                                $sys = $system . $longshort;
                            }
                            if ($comment) {
                                $optC = " -C \"$comment\"";
                            }
                            if ($setup && $f != -1) {
                                #$optS = "-U -S${setup}${smaper}$prefix$f ";
                                #$optS = "-U -S${setup}${atrper}$prefix$f ";
                                $optS = "-U -S${setup}$f$prefix$smaper ";  # 
                                $optS = "-U -S${setup}${atrper}$prefix$f " if $setup =~ /SMA/;
                                $optS = "-U -S${setup}${atrper} " if $setup =~ /HiLo/;
                            }
                            #$trailstop = "${stop}_${vstop}_0.1p";
                            #$trailstop = "${stop}_${atrper}_${vstop}";
                            #$trailstop = "${stop}_${atrper}_${vistop}"; # same as istop!!
                            $trailstop = "${stop}_${vstop}_${vstop2}$stopadd$addstop"; # SMA_12_0";
                            if ($rsecure) {
                                $trailstop .= "_${rsecure}_$rsec";
                            }
#                            $myi = $trfac - 1;
#                            $initstop = "${istop}_${myi}_${vistop}px";
                            #$initstop = "${istop}_${atrper}_${vistop}";
                            $initstop = "${istop}_${vistop}$isuff";
                            #$initstop = "Local_${vstop}_0.3p";  # for initial runs to see which are profitable or not
                            $system = "${stem}${trper}x$smaper"; 
                            $sys = $system . $longshort;        # comment if using $hardtarget!!!
                            $fixed = "./backtest.pl -R -k10:$atrper -f$fee -u$slip ${optS}-n -p${optC}";
                            $com = "$fixed$optT $tick $day1 $day2 $sys $initstop $trailstop";
                            print "[$nn of $totnum] $com\n"; $nn++;
                            `$com`;
                            &processUnique();
    } } } } } } } } } } } }
close OUT;
}
@tend = times;
$tend = time;
printf "Time: %.2f CPU minutes, %.2f minutes for $totnum runs\n", ($tend[0]-$tstart[0])/60.0, ($tend-$tstart)/60.0;

sub paramsCandle {
    $file = ""; $setup = "";
    $fee = 5.90;  $slip = 0.175; # BAS.DE
    $setup = "HiLo";
    $prefix = "f";
#    @atrper = (60,65,70,75,80,85,90,100,110,120,130,140);  # 'atrperiod' is used for the setup in this case!!
    @atrper = (52);
    @f = (-1);
    @trper = (5);   # fast SMA
    @smaper = (10); # slow SMA
    $stem = "Candle";
    $longshort = "Short";  # set to Long or Short to test only that 
    $comment = "testing";
    #$istop = "Percent"; 
    #$istop = "Local_2";
    $istop = "Vola_10";
    @istop = (1.2);
    $isuff = ""; # suffix for istop 'Percent'
    #$stop = "TrueRange";
    #@stop = (50, 90, 120);
    $stop = "Locan"; #_3_0.1pSMA";
    @stop = (3);
    #@stop2 = (0.5);
    @stop2 = (0.3);
    $stopadd = "pTimLim_1_0.1_0.05";
    $softtarget = "";  # empty, x, c, o or MACD fast, e.g. "M12"
    @soft = (26);     # MACD slow
    @soft2 = (9);    # MACD smooth
    $hardtarget = "";
    @hard = (1);     # MACD-induced Local period
    $rsecure = "";
    @rsec = ();
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
        print OUT "$tick\t$smaper\t$f\t$trfac\t$atrper\t$vistop\t$vstop\t${vstop2}\t${hard}\t$list\t$unique\n";
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

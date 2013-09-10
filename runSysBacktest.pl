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
#&paramsDaybreak();
&paramsVolBC();
#&paramsLuxor();
#&paramsCandle();
#&paramsAllTime();
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
$totnum = @tick * @smaper * @f * @atrper * @trfac * @istop * @stop * @stop2 * @rsec * @hard * @soft * @soft2;
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
$setup0 = $setup;
foreach $tick (@tick) {
foreach $soft (@soft) {
    foreach $soft2 (@soft2) {
        foreach $smaper (@smaper) {
        foreach $f (@f) {
        if ($f == -1) { $setup=""; } else { $setup=$setup0;}  
        $f .= ".0" if (int($f) == $f && $f !~ /\./ && $setup !~ /sma/);
        foreach $trfac (@trfac) {
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
                                $optS = "-U -S${setup}$smaper " if $setup eq 'HiLo';
                                $optS = "-U -S${setup} " if $setup =~ /:/;
                            } else { $optS = "" }
                            #$trailstop = "${stop}_${vstop}_0.1p";
                            #$trailstop = "${stop}_${atrper}_${vstop}";
                            #$trailstop = "${stop}_${atrper}_${vistop}"; # same as istop!!
                            $trailstop = "${stop}_${vstop}_${vstop2}$trailext";
                            if ($rsecure) {
                                $trailstop .= "_${rsecure}_$rsec";
                            }
#                            $myi = $trfac - 1;
#                            $initstop = "${istop}_${myi}_${vistop}px";
                            $initstop = "${istop}_${atrper}_${vistop}";
                            #$initstop = "Local_${vstop}_0.3p";  # for initial runs to see which are profitable or not
                            $system = "${stem}${trfac}${when}${atrper}";  # VolEOD
                            #$system = "${stem}${trfac}";  # AllTime
                            $sys = $system . $longshort;        # comment if using $hardtarget!!!
                            $fixed = "./backtest.pl -R -k$atrper:$smaper -f$fee ${optS}-n -p${optC}";
                            $fixed .= " -u$slip" if ($slip);  #  -u$slip
                            #$com = "$fixed$optT $tick $day1 $day2 $sys ${istop}_${atrper}_${vistop} $trailstop";
                            #$com = "$fixed$optT $tick $day1 $day2 $sys $initstop $trailstop"; # Candle
                            $com = "$fixed$optT $tick $day1 $day2 $sys $initstop $trailstop"; # VolBC
                            print "[$nn of $totnum] $com\n"; $nn++;
                            `$com`;
                            &processUnique();
    } } } } } } } } } } } }
close OUT;
}
@tend = times;
$tend = time;
printf "Time: %.2f CPU minutes, %.2f minutes for $totnum runs\n", ($tend[0]-$tstart[0])/60.0, ($tend-$tstart)/60.0;

sub paramsDaybreak {
    $stem = "DaybreakG3Exit";
    $comment = ""; 
    $file = "";
    $when = "";
    $fee = 0.0;  $slip = 0.03;
    $setup = "CandleSMA";
    $longshort = "Short";
    @smaper = (75);
    @f = (0.0,0.1,0.2,0.3,0.4,0.5);
    @trfac = (0);   # Exit-period
    @atrper = (5);
    $istop = "Vola";
    @istop = (1.4);
    $stop = "Local";
    @stop = (1);
    @stop2 = (2);
    $softtarget = "";  # empty, x, c, o
    @soft = ();
    @soft2 = ();
    $hardtarget = "";
    @hard = ();
    $rsecure = "";
    @rsec = ();
}

sub paramsVolBC {
# First test:
#   one SMA period. Only vary trfac, use two Local_N stops (e.g. 3,7) as istop = stop.
#   From this, decide on good range of TR% and fix the M-param (col -x12)
# Second test:
#   with the selected TR%, vary SMA
#   decide on which SMA to test with f/r (col -x13)
    $stem = "VolEOD";  $when = "C";
    $fee = 5.9;  $slip = 0.25; # ALV.DE
    $comment = ""; 
    $file = "";
#    $setup = "HiLo";
    $setup = "ATR10f2.0Volu14f1.0:5.0";  
    $prefix = "f";
    @smaper = (180);
#    @smaper = (30,40,50,60,70,80,90,100,110,120,140,160,180,200);
    @f = (0);
    $longshort = "M0Short";  # set to Long or Short to test only that 
#    @trfac = (45,50,55,60,70,80,90,100,120,140); 
    @trfac = (100);   # "best" 
    $istop = "Vola";
    @atrper = (10);
    @istop = (0.8,0.9,1.1,1.2,1.4); #,0.9);
#    @istop = (0.8,0.9,1.0,1.1,1.2,1.3,1.4,1.5,1.6); 
    $stop = "Locan"; #_13_0.3pTimLim";
    @stop = (13); #,4,5); 
    @stop2 = (0.3);
#    @stop2 = (0.1,0.2,0.4,0.8,1.2,2.0);
    $trailext = "pTimLim_6_0.2_0.05";
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

sub paramsLuxor {
    $stem = "cross";
    $file = "";
    #$setup = "sR45ATR1.05";
    $setup = "";
    $longshort = "Long";  # set to Long or Short to test only that 
    $comment = "No additional setup conditions - testing"; 
    @atrper = (5, 8, 10, 15, 25);  # fast SMA
    @trfac = (100, 110, 120, 130, 150);  # slow SMA
    $istop = "Vola";
#    $istop = "Vola_5";
    @istop = (0.65, 1.0, 1.6); 
#    $stop = "Local";
    $stop = "Vola";
    @stop = (0);
    $softtarget = "";  # empty, x, c, o
    @soft = ();
    @soft2 = ();
    $hardtarget = "";
    @hard = ();
    $rsecure = "";
    @rsec = ();

}

sub paramsCandle {
    $file = "";
    $setup = "sma";
    $stem = "Candle";
    #$longshort = "Short";  # set to Long or Short to test only that 
    $comment = "testing";
    @trfac = ("Short");
    #@trfac = ("Long", "Short");
    @atrper = (8,9,10,11,12,13,14,15,18,20);
    $istop = "Percent";
    #$istop = "Local_2";
    @istop = (0.5);
    #$stop = "TrueRange";
    #@stop = (50, 90, 120);
    $stop = "Local"; #_3_0.1pSMA";
    @stop = (2);
    $softtarget = "";  # empty, x, c, o
    #@soft = (1.2);
    #@soft2 = (5);
    @soft = ();
    @soft2 = ();
    $hardtarget = "";
    @hard = ();
    $rsecure = "";
    @rsec = ();
}

sub paramsAllTime {
# BMW.DE  n               AllTime90Long       Local_3_0.1p        Local_5_0.1p            n   eod     1.0     0.02    flatex  0.35/0.10   0.00/4          no stats
    $file = "";
    $fee = 5.9;  $slip = 0.0;
    $setup = "";
    @smaper = (60);
    $prefix = "f";
    @f = (0.0);
    $stem = "AllTime";  $when = "";
    @trfac = (35,80);
    $longshort = "Long";  # set to Long or Short to test only that 
    $comment = "testing";
    @atrper = (10);
    $istop = "Vola";
    @istop = (1,2,4);
    $stop = "Local";
    @stop = (4,7,9);
    @stop2 = (0.3);
    $softtarget = "";  # empty, x, c, o
    @soft = ();
    @soft2 = ();
    $hardtarget = "";
    @hard = ();
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
        print OUT "$tick\t$smaper\t$f\t$trfac\t$atrper\t$vistop\t$vstop\t${vstop2}\t$list\t$unique\n";
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

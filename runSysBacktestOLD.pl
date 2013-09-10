#!/usr/bin/perl -I/Users/tdall/copyExecs
# 
# 
# -r : reprocess all the summary_ files in Backtests/
use Getopt::Std;
getopts('r');
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
&paramsVolBC();
#&paramsLuxor();
#&paramsCandle();
#&paramsAllTime();
open OUT, ">$btdir/oub_${stem}${longshort}_${istop}_${stop}.txt" || die "239db32laa390";
print OUT "#TICK\tSLOW\tFAST\tIS\tSTOP\n";
unless ($softtarget) {
    push @soft, ""; push @soft2, "";
}
unless ($hardtarget) {
    push @hard, "";
}
unless ($rsecure) {
    push @rsec, "";
}
if ($opt_r) {
    &reprocessSummary();
} else {
# looping...
#
foreach $tick (@tick) {
foreach $soft (@soft) {
    foreach $soft2 (@soft2) {
        foreach $trfac (@trfac) {
            foreach $atrper (@atrper) {
#            next if ($atrper >= $trfac);  # for Luxor/ cross system
            foreach $vstop (@stop) {
                #$vstop .= ".0" if (int($vstop) == $vstop && $vstop !~ /\./);
#                next if ($vstop > 2*$trfac);
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
                                $optS = "-S${setup}${atrper}f0.5 ";
                            }
                            #$trailstop = "${stop}_${vstop}_0.1p";
                            #$trailstop = "${stop}_${atrper}_${vstop}";
                            #$trailstop = "${stop}_${atrper}_${vistop}"; # same as istop!!
                            $trailstop = "${stop}_${vstop}_0.1p";
                            if ($rsecure) {
                                $trailstop .= "_${rsecure}_$rsec";
                            }
                            $myi = $trfac - 1;
                            $initstop = "${istop}_${myi}_${vistop}px";
                            $system = "${stem}${trfac}${when}10";
#                            $system = "${stem}${trfac}${when}${atrper}";
                            #$system = "${stem}80${when}${atrper}";
                            #$system = "cross${atrper}x${trfac}";
                            #$system = "Candle$trfac";
                            #$system = "AllTimeC$trfac";
                            #$fixed = "./systemBacktestCross.pl -n -p -x13 -X8${optC}${optf}";
                            #$fixed = "./systemBacktestIntra.pl -w -S$setup -n -p -x13 -X8${optC}${optf}";
                            #$fixed = "./systemBacktestIntra.pl -n -p -x13 -X8${optC}${optf}";
                            $sys = $system . $longshort;        # comment if using $hardtarget!!!
                            $fixed = "./backtest.pl ${optS}-n -p${optC}";
                            #$com = "$fixed$optT $tick $day1 $day2 $sys ${istop}_${atrper}_${vistop} $trailstop";
                            #$com = "$fixed$optT $tick $day1 $day2 $sys $initstop $trailstop"; # Candle
                            $com = "$fixed$optT $tick $day1 $day2 $sys ${istop}_${vistop} $trailstop"; # VolBC
                            print "$com\n";
                            `$com`;
                            &processUnique();
                        }
                    }
                }
                }
            }
        }
    }
}
}
close OUT;
}


sub paramsVolBC {
    $stem = "VolEOD";  $when = "C";
    $file = "";
    #$setup = "AllT120";
    $setup = "SMA";
    #$setup = "";
    $longshort = "Long";  # set to Long or Short to test only that 
    $comment = ""; 
    @atrper = (80,100,120,150);
    @trfac = (70,80,90,100); #100,110,120,130,140,150);
#    @trfac = (80);   # "best" 
    $istop = "Vola_10";
#    @istop = (0.6,0.7,0.8,0.9,1.0); #, 1.4, 1.6); #, 2.2, 2.4);
#    @istop = (0.8, 0.9, 1, 1.5);  # "best" to check out range in Percent/stop
    @istop = (0.8); 
    $stop = "Local";
    @stop = (3);
#    @stop = (0.05);
    $softtarget = "";  # empty, x, c, o
    #@soft = (1.2);
    #@soft2 = (5);
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
    #$file = "../Backtests_volbreak1/trades_goodMoves.txt";
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
    #$file = "../Backtests_volbreak1/trades_goodMoves.txt";
    $file = "";
    $setup = "";
    $stem = "AllTime";
    $longshort = "Short";  # set to Long or Short to test only that 
    $comment = "testing";
    @trfac = (2,3,4,5,6,7,8);
    #@trfac = (90);
    #@trfac = ("Long", "Short");
    @atrper = (10);
    #$istop = "Vola";
    #$istop = "Percent";
    $istop = "Local";
    @istop = (0.05);
    #$stop = "TrueRange";
    #@stop = (50, 90, 120);
    #$stop = "Vola";
    $stop = "Local";
    #@stop = (2, 3, 4, 5, 6, 7, 8, 9, 10);
    @stop = (0.05);
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

sub processUnique {
    open UNIQ, "<$btdir/unique.txt" or die "nzt238dHW44";
    chomp($unique = <UNIQ>);
    close UNIQ;
    print "unique = $unique\n";
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
        print OUT "$tick\t$trfac\t$atrper\t$vistop\t$vstop\t$list\n";
    } else {
        warn "WARN: no such file $sfile...\n";
    }
}

sub reprocessSummary {
    open OUT, ">$btdir/oub_${stem}${longshort}_${istop}_${stop}.txt" || die "239db32laa390";
    print OUT "#TICK\tTR\tATR\tIS\tSTOP\n";
    @g = `ls -1tr $btdir/summary_*.txt`; #<$btdir/summary_*.txt>;
    chomp @g;
    foreach $sfile (@g) {
        print "processing $sfile ...\n";
        open IN, "<$sfile" or die "zz846dhhns on $sfile\n";
        while ($in = <IN>) {
            if ($in =~ /toread: (.*)/) {
                $list = $1; chomp $list;
            }
            if ($in =~ /System = VolBC(\d+)A(\d+)\w*, Initial stop method = Vola 5 (\d+.?\d*)x, Exit\/Stop = Percent (\d+.?\d*)/) {
                $trfac = $1; $atrper = $2; $vistop = $3; $vstop = $4;
            }
        }
        close IN;
        print OUT "$tick\t$trfac\t$atrper\t$vistop\t$vstop\t$list\n";
    }
    close OUT;
}
# ./systemBacktest.pl -p -x13 -X8 -T2.0x2 -f ../Backtests_volbreak1/trades_goodMoves.txt 
#       BMW.DE 2012-03-17 2012-06-15 VolBC70A5R50l900 
#       TrueRange_105 TrueRange_140_Rmult_rstop_0.6_0.4_0.8_0.5_1.1_0.8
# System = VolBC100A5Short, Initial stop method = Vola 5 2.4x, Exit/Stop = Percent 3

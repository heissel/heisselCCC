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
    open IN, "<$tick" or die "bs481jazpt885";
    chomp(@tick = <IN>);
} else {
    @tick = ($tick);
}
$| = 1;
my $btdir = "/Users/tdall/geniustrader/Backtests/";
# parameters
#
&paramsAllTime();
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
        $f .= ".0" if (int($f) == $f && $f !~ /\./);
        foreach $trfac (@trfac) {
            foreach $atrper (@atrper) {
#            next if ($atrper >= $trfac);  # for Luxor/ cross system
            foreach $vstop (@stop) {
#                next if ($vstop > 2*$trfac);
                foreach $vstop2 (@stop2) {
                $vstop2 .= ".0" if (int($vstop2) == $vstop2 && $vstop2 !~ /\./);
                foreach $vistop (@istop) {
                    $vistop .= ".0" if (int($vistop) == $vistop && $vistop !~ /\./ && $istop !~ /Local/);
#                    next if ($vistop > 2*$trfac);
                    foreach $rsec (@rsec) {
                        foreach $hard (@hard) {
                            $addstop = "";
                            if ($softtarget =~ /^M/) {
                                $addstop = "${softtarget}-${soft}-${soft2}-${hard}";
                                next if ($hard >= $vstop);
                            } elsif ($softtarget) {
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
                                $smaper = $trfac if $setup =~ /AllT[nw]/;
                                $optS = "-U -S${setup}${smaper}$prefix$f ";
                                #$optS = "-U -S${setup}${atrper}$prefix$f ";
                                $optS = "-U -S${setup}$smaper " if $setup =~ /HiLo/;
                            } else { $optS = "" }
                            #$trailstop = "${stop}_${vstop}_0.1p";
                            #$trailstop = "${stop}_${atrper}_${vstop}";
                            $trailstop = "${stop}_${vstop}_${vstop2}p" if $stop =~ /Loca/;
                            $trailstop = "${stop}_${vstop}" if $stop =~ /Percent/;
                            $trailstop = "${stop}_${vstop2}" if $stop =~ /Vola/;
                            if ($rsecure) {
                                $trailstop .= "_${rsecure}_$rsec";
                            }
#                            $myi = $trfac - 1;
                            $initstop = "${istop}${vistop}";
                            #$initstop = "${istop}_${atrper}_${vistop}$icomp";
                            #$initstop = "${istop}_${vistop}_0.1$icomp";  # for initial runs to see which are profitable or not
                            $system = "${stem}${when}$comp";  # 
                            $sys = $system . $longshort;        # comment if using $hardtarget!!!
                            $fixed = "./backtest.pl -R -U -k$atrper:$smaper -f$fee -u$slip ${optS}-n -p${optC}";
                            #$com = "$fixed$optT $tick $day1 $day2 $sys ${istop}_${atrper}_${vistop} $trailstop";
                            #$com = "$fixed$optT $tick $day1 $day2 $sys $initstop $trailstop"; # Candle
                            $com = "$fixed$optT $tick $day1 $day2 $sys $initstop $trailstop$stopadd"; # 
                            print "[$nn of $totnum] $com\n"; $nn++;
                            `$com`;
                            &processUnique();
    } } } } } } } } } } } }
close OUT;
}
@tend = times;
$tend = time;
printf "Time: %.2f CPU minutes, %.2f minutes for $totnum runs\n", ($tend[0]-$tstart[0])/60.0, ($tend-$tstart)/60.0;

sub paramsAllTime {
# BMW.DE  n               AllTime90Long       Local_3_0.1p        Local_5_0.1p            n   eod     1.0     0.02    flatex  0.35/0.10   0.00/4          no stats
    $file = "";
    $fee = 5.90;  $slip = 0.1; # some average...
    #$slip = 0.28; # TKA.DE
    $setup = "SMA";
    @smaper = (20);
#    @smaper = (5,15,27,42,63,96);
#    @smaper = (4,6,7,9,12,15,21,35,47,55,63,72,85,95); # HiLo set
    $prefix = "f";
    @f = (-1);
    $stem = "InsideDay";  $when = "G";    $comp = "Short"; # c or x
#    @trfac = (10,13,17,25,30,35,40,45,50,55,60,65,70,75,80,85,90,95,100,105,110,115,135,180);  # standard first test set
#    @trfac = (9,13,25,35,45,55,65,75,95,115,135,180);  # standard first test set
#    @trfac = (13,28,42,55,65,75,85,95,105,115,130,150,180); # ,140,150,160,170,180,200); #    
    @trfac = (135); #,130);
    $longshort = "";  # set to Long or Short to test only that 
    $comment = "testing";
    @atrper = (10);
    #$istop = "Local";
    $istop = "";
#    @istop = ('Vola_10_0.6x','Vola_10_0.7x','Vola_10_0.9x','Vola_10_1.0x');
    @istop = ('Vola_10_0.6x','Vola_10_1.0x');
#    @istop = (1); $icomp = 'px';
#    $stop = "Percent"; $stopadd = "c";
#    $stop = "Vola_10";
    $stop = "Local";
    $stopadd = "Rmult_rstop_0.05_0.05";
    @stop = (1,5);
    @stop2 = (0.1);
#    @stop2 = (0.6,0.8,1.0,1.5); 
    $softtarget = "";  # empty, x, c, o or MACD fast, e.g. "M12"
    @soft = (26);     # MACD slow
    @soft2 = (9);    # MACD smooth
    $hardtarget = "";
    @hard = ();     # MACD-induced Local period
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

#!/usr/bin/perl -I/Users/tdall/copyExecs
($arg1, $arg2) = @ARGV;

# arg1 = name of csv file with setup parameters
# arg2 = name of file with the copied trades (from MT4-testers 'Results' tab)
$lot = 100000.0;    # size of a full lot
$path = 'MT4testerDir/';

open MT, "<$arg2" or die "No such file $arg2\n";
@lines = <MT>;
close MT;

open CSV, "<${path}files/$arg1" or die "No file ${path}files/$arg1\n";
$info = <CSV>; # the top line with info on the system
$csv[0] = <CSV>; # header line
$icsv = 1;
while ($in = <CSV>) {
    if ($in =~ /^(\d+);.*MAE/) {
        $iii = $1;
        $mm[$iii] = $in; 
    } else {
        $csv[$icsv] = $in; #print "$in";
        $icsv++;
#        push @csv, $in;
    }
}
#@csv = <CSV>;
close CSV;

chomp( $unique = `date "+%Y%m%dT%H%M%S"` );
($tick,$system,$d1,$sysistop,$is1,$is2,$d2,$syststop,$ts1,$ts2,$extra) = split /;/, $info;
$outfile = "trades_${system}_${tick}_${unique}_MT4.txt";
$outl = "tr_long_${system}_${tick}_${unique}_MT4.txt";
$outs = "tr_short_${system}_${tick}_${unique}_MT4.txt";
open OUT, ">$outfile" or die "cannot open $outfile!\n";
print OUT "System = $system, Initial stop method = $sysistop $is1 $is2, Exit/Stop = $syststop $ts1 $ts2\n";
open OUTL, ">$outl" or die "cannot open $outl!\n";
open OUTS, ">$outs" or die "cannot open $outs!\n";
$icsv = 1;  # starting at first position, after the header line
$nowreadstop = 0;

open PAR, "<${path}$system.ini" or die "No file ${path}$system.ini\n";
@pars = <PAR>;
close PAR;

foreach $line (@lines) {
    if ($line =~ /buy/ || $line =~ /sell/) {
        ($dum, $dayo, $time, $bs, $ntrade, $size, $inprice, @dum) = split /\s+/, $line; 
        $trade[$ntrade] = $line;
        $bs[$ntrade] = $bs;
        $size[$ntrade] = $size;
        $inprice[$ntrade] = $inprice;
        $dayo[$ntrade] = $dayo;
        $nowreadstop = 1;
#     } elsif ($line =~ /sell/) {
#         ($dum, $dayoS, $timeS, $bsS, $ntradeS, $sizeS, $inpriceS, @dum) = split /\s+/, $line; 
#         $nowreadstop = 1;
    } elsif ($line =~ /s\/l/ || $line =~ /close/ || $line =~ /t\/p/) {
        next if ($line =~ /close at stop/); # last trade, not to be counted
        # means we're closing a current trade
        ($dum, $dayc, $time, $d1, $csvidx, $d3, $exitp, $d4, $d5, $gain, @dum) = split /\s+/, $line;
        # identify the trade we're closing
        ($nt, $dir, $dayconf, $hour, $d1, $spread, @params) = split /;/, $csv[$csvidx];
        if ($nt != $csvidx) {
            print "LINE = $line\n";
            print "CSV = $csv[$csvidx]\n";
            die "Error!  $nt and $csvidx does not match...\n";
        }
        $gg = $exitp - $inprice[$nt] if $dir eq 'long';
        $gg = $inprice[$nt] - $exitp if $dir eq 'short';  
        $rmult = sprintf "%.3f", $gg/abs($inprice[$nt]-$istop[$nt]);
        # get the MAE/MPE
    #    ($d1,$d2,$d3,$mae,$miae,$m1ae,$mpe,$numbars,$constExit,$constMPE,$nBreakEven,$n0p5,$n1p0,$n1p5,$n2p0,$n3p0,$n5p0,$d4) = split /;/, $mm[$nt];
        ($d1,$d2,$d3,$mae,$miae,$m1ae,$mpe,$numbars,$nBreakEven,$n0p5,$n1p0,$n1p5,$n2p0,$n3p0,$n5p0,$d4) = split /;/, $mm[$nt];
        $pfgiveback = $mpe-$rmult;
        $mpe += 0.0;
        $dura = 0.01;  # for now...
        if ($constExit =~ /end/) {
            $constExit = 0.0;
            $constMPE = 0.0;
        }
#        print OUT "$nt:\tForex $dir\t$size[$nt] $dayo[$nt] $inprice[$nt] $dayc $exitp $rmult $dura $spread $hour $mae $miae $m1ae $mpe $pfgiveback $numbars $nBreakEven $n0p5 $n1p0 $n1p5 $n2p0 $n3p0 $n5p0 $constExit $constMPE @params";
        print OUT "$nt:\tForex $dir\t$size[$nt] $dayo[$nt] $inprice[$nt] $dayc $exitp $rmult $dura $spread $hour $mae $miae $m1ae $mpe $pfgiveback $numbars $nBreakEven $n0p5 $n1p0 $n1p5 $n2p0 $n3p0 $n5p0 @params";
        if ($dir =~ /long/) {
#            print OUTL "$nt:\tForex $dir\t$size[$nt] $dayo[$nt] $inprice[$nt] $dayc $exitp $rmult $dura $spread $hour $mae $miae $m1ae $mpe $pfgiveback $numbars $nBreakEven $n0p5 $n1p0 $n1p5 $n2p0 $n3p0 $n5p0 $constExit $constMPE @params";
            print OUTL "$nt:\tForex $dir\t$size[$nt] $dayo[$nt] $inprice[$nt] $dayc $exitp $rmult $dura $spread $hour $mae $miae $m1ae $mpe $pfgiveback $numbars $nBreakEven $n0p5 $n1p0 $n1p5 $n2p0 $n3p0 $n5p0 @params";
        } elsif ($dir =~ /short/) {
#            print OUTS "$nt:\tForex $dir\t$size[$nt] $dayo[$nt] $inprice[$nt] $dayc $exitp $rmult $dura $spread $hour $mae $miae $m1ae $mpe $pfgiveback $numbars $nBreakEven $n0p5 $n1p0 $n1p5 $n2p0 $n3p0 $n5p0 $constExit $constMPE @params";
            print OUTS "$nt:\tForex $dir\t$size[$nt] $dayo[$nt] $inprice[$nt] $dayc $exitp $rmult $dura $spread $hour $mae $miae $m1ae $mpe $pfgiveback $numbars $nBreakEven $n0p5 $n1p0 $n1p5 $n2p0 $n3p0 $n5p0 @params";
        }
    } elsif ($nowreadstop) {
        # the trade was just opened, so this line contains the initial stop
        ($dum, $d5, $d6, $d1, $d2, $d3, $d4, $istop, @dum) = split /\s+/, $line;
        $istop[$ntrade] = $istop;
        $nowreadstop = 0;
    } else {
        next;
    }
    
}

close OUT;
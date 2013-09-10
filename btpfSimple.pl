#!/usr/bin/perl -I/Users/tdall/copyExecs
# 
# 
use Getopt::Std;
use PGPLOT;
#use strict;
require "utils.pl";
require "pg_utils.pl";
require "trader_utils.pl";
getopts('w:ub:e:a:lm:');
# -u : print the proper -u values for each and then exit.
# -b : begin date (default is day1)
# -e : end date (defaultis day2)
# -a : initial account size (default = 10000)
# -l : log plot
# -m : assumed monthly mistake cost in terms of R
# -w : withdrawal every 21 days of percentage of gains on starting capital

require "utils.pl";
#require "pg_utils.pl";
require "trader_utils.pl";
($day1, $day2) = @ARGV;
$dbfile = "/Users/tdall/geniustrader/traderThomas";

if ($opt_b) {
    $bday = $opt_b;
} else {
    $bday = $day1;
}
if ($opt_e) {
    $eday = $opt_e;
} else {
    $eday = $day2;
}
if ($opt_a) {
    $cash0 = $opt_a;
} else {
    $cash0 = 10000.00;  # fees and slippage already included in results
}

$extot = 0.0;
$ddwarn = 0;
@res = ();
@trades = ();
$lastday = $eday;
open PF, "</Users/tdall/geniustrader/sysportf.gtsys" || die "ssj44d";
LOOP:while ($in = <PF>) {
    next LOOP if $in =~ /^#/;
    ($tick, $setup, $sys, $istop, $stop, $targ, $d1, $pct, $ddd, $d2, $rrr, $d3) = split /\s+/, $in;
    # save the percentage risk for each strategy
    if ($sys =~ /Long/) {
        $val = "${tick}-long";
    } else {
        $val = "${tick}-short";
    }
    $risks{$val} = $pct/100.0;
    # find the current spread ...
    @sp = split m|/|, $ddd;
    if ($sp[0] eq "-") {
        $spr = $sp[1];
    } elsif ($sp[1] eq "-") {
        $spr = $sp[0];
    } else {
        $spr = min($sp[0]+1-1,$sp[1]+1-1); #print "$ddd -> $spr\n"; exit;
    }
    # ... then translate it to a percentage
    chomp($today = `date -v -5d "+%Y-%m-%d"`); #print "Today is $today\n";
    $data = `sqlite3 "$dbfile" "SELECT day_close \\
                               FROM stockprices \\
                               WHERE symbol = '$tick' AND date>='$today' limit 1"`; 
    $spr = 100.0*$spr/$data;
    if ($opt_u) {
        # just print the spread percentage
        printf "$tick: -u %.3f\n", $spr;
        next LOOP;
    }
    ($sq0,$ex0) = split m|/|, $rrr;
    if ($setup ne "n") {
        $sopt = "-S$setup ";
    } else { $sopt = ""; }
    $com = "backtest.pl -R -u$spr $sopt-f5.90 -n -p -C\"test for btpfSimple\" $tick $day1 $day2 $sys $istop $stop";
    print "$com "; 
    $isfile = `ls -1tr /Users/tdall/geniustrader/Backtests4pf/summary_${sys}_${tick}_*${day1}_${day2}.txt | tail -1`; chomp($isfile); #print "$isfile\n"; exit;
    if (-e "$isfile") {
        open OLD, "<$isfile" || die "38sntylo3274";
        @tmp = <OLD>;
        close OLD;
        $dum = $tmp[-6].$tmp[-5].$tmp[-4].$tmp[-3].$tmp[-2];  #print "old: $dum"; exit;
    } else {
#        print "new..."; exit;
        $dum = `$com`;
        $isfile = "";
    }
    $ok = 1;
    if ($dum =~ /Expectancy = (.*)\+\/-\d+.\d{2}, System Quality = (.*), Max drawdown = (\d+.\d{2})\%. L/) { #.*L-ratio = (.*). <R_pos> =/) {
        $meanr = $1; 
        $sq = $2; $maxdd = $3;
    } else { $ok = 0; }
    if ($dum =~ /L-ratio = (.*). <R_pos> = (.*) \+\/- .*, <R_neg> = (.*) \+\/- .*, R\/R = (\d+.\d{2})/) {
        $wl = $1; $rpos = $2; $rneg = $3; $ror = $4;
    } else { $ok = 0; }
    if ($dum =~ /R. Month = (\d+.\d{3})R/) {
        $ex = $1;    
    }  else { $ok = 0; }
    if ($dum =~ /stamp = (\d+T\d+)/) {
        $unique = $1;
    } elsif ($isfile =~ /${tick}_(.*)_$day1/) {
        $unique = $1;    
    } else { $ok = 0; }
    if ($ok) {
        print "... ok\n";
        push @res, "$tick-$sys: <R> = $meanr, SQ = $sq (was $sq0), Expectunity = $ex (was $ex0) R/md. MaxDD = $maxdd%. stamp = $unique\n";
        $extot += $ex;
        $ddwarn++ if ($maxdd > 10.0);
        # now look for the individual trades...
        open TR, "</Users/tdall/geniustrader/Backtests4pf/trades_${sys}_${tick}_${unique}_${day1}_${day2}.txt" || die "ss93jnfnss03";
        TRFILE:while ($tr = <TR>) {
            next TRFILE if ($tr =~ /^System/ || $tr =~ /#/); # || $tr =~ /%/);
            @tmp = split /\s+/, $tr;
            next TRFILE if ($tmp[4] lt $bday);
            last TRFILE if ($tmp[4] gt $eday);
            if ($tr =~ /%/) {
                $lastday = $tmp[4] if ($tmp[4] lt $lastday);
                next TRFILE;
            }
            push @trades, "$tick $tmp[2] in:$tmp[4] out:$tmp[6] $tmp[8]";
        }
        close TR;
    } else {
        print "... warning!\n";
        push @res, "$tick-$sys: warning! stamp = $unique\n";
    }
#    print $dum;
    
}
close PF;
open LOG, ">>btpf.log" || die "cannot open log file\n";
print "@res\nTotal E_R = $extot R/mth.  $ddwarn strategies exceed max DD\n" unless $opt_u;
print LOG "@res\nTotal E_R = $extot R/mth.  $ddwarn strategies exceed max DD\n" unless $opt_u;
$ntr = @trades; print "Total of $ntr trades.\n"; #print @trades; exit;
exit if $opt_u;

# get sequence of dates
@data = `sqlite3 "$dbfile" "SELECT date \\
                               FROM stockprices \\
                               WHERE symbol = 'LHA.DE' AND date>='$bday' and date<='$eday' order by date DESC"`;  
@days = reverse @data;
#@days = @data;
chomp(@days);
$nday = 0;
$pvalue = $cash0;
$pval[$nday] = $cash0;
my $eqhigh = $cash0;  #### initial eq-high; 
my $maxRisklim = 9.0;   #### hard limit on max open risk
my $risklim = 6.0;  #### max open risk for the portfolio. Is also adjusted by the $riskFactor, but can be no more than the $maxRisklim
my $maxRisk = 2.0;  #### hard limit on max risk on an open trade
my $riskFactor = 1.0;   ##### this factor depends on losing/winning streak and result in max the largest allowed risk%. Default is 1; adjusted below
$ddmax = 0.0;
$yd = 0; @day = ();
$nopen = 0; @nopen = ();    @wdraw = ();
# To test if all dates are actually present:
#         LINE:foreach $line (@trades) {
#             @tmp = split /\s+/, $line;
#             $ok = 0;
#             foreach $day (@days) {
#                 if ($tmp[2] =~ /$day/) {
#                     $ok = 1;
#                     next LINE;
#                 }
#             }
#             print "did not match $tmp[2] on $line\n" unless $ok;
#         }
#         exit;

foreach $day (@days) {
    last if ($day ge $lastday);
#    next if ($day gt $eday || $day lt $bday);
    $nday++;    #print "$day day #$nday:\t";
    $pval{$day} = $pvalue;
    if (($eqhigh - $pvalue)/$eqhigh > 0.0) {
        $dd = ($eqhigh - $pvalue)/$eqhigh;
        $riskfac{$day} = (1.0 - $dd);
        if ($dd > $ddmax) {
            $ddmax = $dd;
        }
    } elsif ($yd) {
        $riskfac{$day} = $riskfac{$yd};
    } else {
        $riskfac{$day} = 1.0;
    }
    $risklim *= $riskFactor;
    if ($risklim > $maxRisklim) {   # making sure hard limit is respected
        $risklim = $maxRisklim;
    }
    if ($opt_m) {
        # mistake every 21 days
        unless ($nday % 21) {
            $pvalue -= $riskfac{$day}*$opt_m*$pval{$day}/100.0;
        }
    }
    if ($opt_w) {
        # withdrawal every 21 days of percentage of gains on starting capital
        unless( ($nday+10) % 21) {
            $wdraw = $opt_w*($pval{$day}-$cash0)/100.0;
            if ($wdraw > 0) {
                $pvalue -= $wdraw;
                push @wdraw, $wdraw;
            }
        }
    }
    foreach $line (@trades) {
        if ($line =~ /in:(.*) out:$day/) {
            $dayr = $1;
            @tmp = split /\s+/, $line;
            #print "$tmp[0] $tmp[1] at R=$tmp[4]. ";
            $val = "$tmp[0]" . "-" . "$tmp[1]";
               #print $riskfac{$dayr}, " ... ", $risks{$val}, " ... ", $pval{$dayr}; exit;
            $pvalue += $tmp[4] * $riskfac{$dayr}*$risks{$val}*$pval{$dayr};
            $nopen--;
        }
        if ($line =~ /in:$day out/) {
            $nopen++;
        }
    }
    if ($pvalue > $eqhigh) {
        $eqhigh = $pvalue;
        $dd = 0.0;
    }
    $nopen[$nday] = $nopen;
    $pval[$nday] = $pvalue;
    $dd[$nday] = $dd;
    $day[$nday] = $day;
    $nday[$nday] = $nday;
    #printf "$nopen open pos. PF-value = %.2f, current DD = %.2f", $pvalue, $dd*100.0; print "%.\n";
    #exit if $nday > 200;
    $yd = $day;
}
printf "Result after $nday days: PF-value = %.2f, max DD = %.2f",$pvalue, $ddmax*100.0; print "%"; printf ", peak/DD = %.2f\n", (($eqhigh-$cash0)/$cash0)/$ddmax;
printf LOG "Result after $nday days: PF-value = %.2f, max DD = %.2f",$pvalue, $ddmax*100.0; print "%"; printf ", peak/DD = %.2f\n", (($eqhigh-$cash0)/$cash0)/$ddmax;
if ($opt_w) {
    $sumwd = sum(@wdraw);
    $mean = $sumwd/($nday/21);
    printf "Profits taken out: Total = %.2f, corresponding to %.2f per month on average, ranging from %.2f to %.2f\n", 
        $sumwd, $mean, $wdraw[0], $wdraw[-1];
}
close LOG;

# plot of results
$device = "/XSERVE";
#$device = "pf-plot.png/PNG";
    my $font = 2;
    my $linewidth = 2;
    my $charheight = 1.0;
    pgbeg(0,$device,1,1); # || warn "pgbeg on $device says: $!\n"; # Open plot device 
    pgscf($font); # Set character font 
    pgslw($linewidth); # Set line width 
    pgsch($charheight); # Set character height 
    pgsci(1);  # default colour
    my $symbol = 17;
    
    $nx = @nday;
    if ($opt_l) {
        for ($i = 0; $i < $nx; $i++) {
            $pval[$i] = log($pval[$i])/log(10);
        }
    }
    $xplot_hig = @days + 1;
    $xplot_low = 0;
    my ($yplot_low, $yplot_hig) = low_and_high(@pval);  $yplot_low = -0.2*$yplot_hig;
    $mean = ( $yplot_hig - $yplot_low ) * 0.05;
    $yplot_hig += $mean;  $yplot_hig = sprintf "%.2f", $yplot_hig;
    $yplot_low -= $mean;  $yplot_low = sprintf "%.2f", $yplot_low; 
    $numposzero = $yplot_low + $mean;
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, 0);# || warn "pgenv here says: $!\n";
    pglabel("Day of period", "PF value", "");
    
    $xtxt = sprintf("PF@end = %.2f, MaxDD = %.1f", $pvalue, $ddmax*100.0) . "%";
    pgsch(0.8); pgmtext('LV', -0.5, 0.85, 0, "$xtxt"); # 

    pgline(2, [$xplot_low,$xplot_hig], [0,0]);  # zero-line
    pgsci(12); pgslw(3);
    pgline($nx, \@nday, \@pval);
    pgslw($linewidth); # Set line width 
    pgsci(7);
    pgline(2, [$xplot_low,$xplot_hig], [$numposzero,$numposzero]);
    pgsls(4);
    pgslw(1); # Set line width 
    pgline(2, [$xplot_low,$xplot_hig], [$numposzero+0.25*abs($numposzero),$numposzero+0.25*abs($numposzero)]);
    pgline(2, [$xplot_low,$xplot_hig], [$numposzero+0.5*abs($numposzero),$numposzero+0.5*abs($numposzero)]);
    pgline(2, [$xplot_low,$xplot_hig], [$numposzero+0.75*abs($numposzero),$numposzero+0.75*abs($numposzero)]);
    pgline(2, [$xplot_low,$xplot_hig], [$numposzero+1.25*abs($numposzero),$numposzero+1.25*abs($numposzero)]);
    pgslw($linewidth); # Set line width 
    pgsci(8);
    for ($i = 0; $i < $nx; $i++) {
        $nopenmod[$i] = $nopen[$i] * abs($numposzero)/10.0 - abs($numposzero);  # hard-coded distance poszero to 0 on main chart = 10
    }
#    pgpoint($nx, \@nday, \@nopenmod, 20);
    pgsls(1); pgline($nx, \@nday, \@nopenmod);
    
    pgsci(15);
    $year = substr $day[1], 0, 4;
    for ($i = 1; $i < $nx; $i++) {
        $nyear = substr $day[$i], 0, 4;
        if ($nyear gt $year) {
            pgsls(2);
            pgline(2, [$nday[$i],$nday[$i]], [$yplot_low,$yplot_hig]);
            pgsls(1);
            pgmtext('T', -1, ($nday[$i]-$xplot_low)/($xplot_hig-$xplot_low), 1, "$year"); # change wrt Backtest.pl
            $year = $nyear;
        }
    }
    
    pgend; # || warn "pgend on $device says: $!\n";


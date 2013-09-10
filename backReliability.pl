#!/usr/bin/perl -w -I/Users/tdall/copyExecs
# 
# generate reliability tests - new version (Feb.2013)
# currently focused on Darvas-AllTime
#
#
# arg 1 = ticker symbol
# arg 2 = starting date
# arg 3 = end date
# arg 4 = system name; entry strategy/setup/signal
# arg 5 = max number of days forward in reliability

# [-q] print info on the data and exit.
# [-p] make PNG plots for summary plots
# [-C <comment>] comment to include in output files
# [-S <setup-name>] use this setup
# [-k kkperi:smaperi] record KSO<peri> and SMA<peri> slopes in trel_ file
# [-w per] using swing numbers so mark on plots. per = swingfilter in percent. If strategy =~ Swing, then take that percentage
# [-O txt:txt:...] if txt returned from getSignal matches, then cancel the signal (e.g. to disregard certain candle patterns)
# [-r] reverse the signal, i.e., turn a 'long' signal into 'short' and vice versa
# [-e] use the latest existing output file instead of calculating again.

use Carp;
use Getopt::Std;
use PGPLOT;
#use strict;
require "utils.pl";
require "pg_utils.pl";
require "trader_utils.pl";


$|=1;
getopts('qp:C:S:k:w:O:re');
#my ($opt_q,$opt_r,$opt_p, $opt_C, $opt_e, $opt_S, $opt_R, $opt_k, $opt_w, $opt_O);
print "$opt_r $opt_q $opt_p $opt_e" if 0;
#
# variable declarations
#
    my $numa = @ARGV;
    die "Not enough args\n" unless ($numa == 5);
    my ($tick, $dayBegin, $dayEnd, $system, $maxd) = @ARGV;
    my $path = "/Users/tdall/geniustrader/";
    my $dbfile = "/Users/tdall/geniustrader/traderThomas";
    my $btdir = "/Users/tdall/geniustrader/Backtests/";
#    my @days = (5,10,15,20,30,40,60); #,80,100);   # forward-looking set of days for the MAE, MPE calcs
    @days = (5);
    #@days = (15,30,50);
    my @alldays = (1 .. $maxd);  # look-back, as in AllTime[N]. Ignored if not AllTime-type...
    my $npdays = @days;
    my $nalldays = @alldays;    my $numdays = 0;
    my ($device, $unique, $intraday, $comment, $in, @tmp, $day, @price, $price, $i, $j, $n, $duratrades, $rr, $atr);
    my ($pc, $d1, $d2, $d3, $d4, $realday, $cnt, @otxt, $hiloper, %ex, $mpe_c, $mpe_ex, $mae, $miae, $font, $linewidth, $charheight);
    $|=1;
    my $norw = "n";  # narrowest stop if several options are given
    my $whichway = "";   # long or short
    my $opentrade = "";  # long or short
    my $donotenter = "";
    my $nbothlim = 0;
    my %volume = (); 
    my %inprice = (); my %direction = (); my @dayTrade = (); my %trendh = (); my %trendl = ();   my %hilo = ();
    my %exitp = (); my %daysintrade = (); my %sma = (); my @hilo = (); my @datehl = (); my @ishigh = (); my %swdir = (); my @reli = ();
    my $numtrades = 0;  my $dypast = 0;
    my %hday = (); my %dayindex = (); my %openp = (); my %maxp = (); my %minp = (); my %closep = ();  # the price hashes, taking date as key$numdays = 0;
    my $indexday = 0; my $ii = 0; my @date = (); my $dayoftrade = 0;
    my $setupOK = "";  # set to 'long' or 'short' or 'longshort' if we're accepting signals
    my $oldsetupOK = "long";
    my ($setupcond, $maBlue, $maGreen, $yday, $yyday, $reenter, $kkper, $ssper, $kperi, $otxt, $priceb, $pricer);
    my ($min, $max, $openp, $closep, $upper, $lower, $daydir, $dayTrade, $stop, $exitp, $stopBuyL, $stopBuyS, @data, $p1, $p2);
    my (@data0, @datein, @open, @low, @high, $subday, $dura, $prevDura, $relevantPrice,$swfiltfac, @swing, $swa, $idx);
    my ($entrySig, $exitSig, $outtext, $txt, $ptxt, $xprice, $curprice, $inprice, $nex, $inp, $istop, $vol, $volyd);
    my (@mpe, @miae, @x, $iplot, $reli, $xplot_low, $xplot_hig, $yplot_low, $yplot_hig, $mean, $dvoln, $m1, $ma, $nu, $nd);
    my ($ni, @xline, @pos1, @pos2, @neg1, @neg2, @files, @miaep, @rr);

#
# unique stamp for all files created in this run
#
chomp( $unique = `date "+%Y%m%dT%H%M%S"` );
open UNIQ, ">$btdir/unique.txt" or die "nzt238dHW44";
print UNIQ $unique;
close UNIQ;

#
# processng the command-line options
#
if ($system =~ /Day/) {
    $intraday = 1;
} else {
    $intraday = 0;
}
if ($opt_O) {
    @otxt = split /:/, $opt_O;
}
if ($opt_p) {
    $iplot = $opt_p;
    $iplot = 0 if $opt_p !~ /\d/;
} else {
    $iplot = 0;
    $device = "/XSERVE";
}
if ($system =~ /Swing[SE](\d+)/) {
    $swfiltfac = $1;
    if ($system =~ /A(\d+)/) {
        $swa = $1;
    } else {
        $swa = 0;
    }
} elsif ($opt_w) {
    $swfiltfac = $opt_w;
} else {
    $swfiltfac = 0;
}
if ($opt_C) {
    $comment = $opt_C;
} else {
    $comment = "";
}
if ($opt_k) {
    ($kkper, $ssper) = split /:/, $opt_k;
}
if ($opt_S) {
    $setupcond = $opt_S;
    $comment .= "## -S${opt_S}";
    if ($opt_S =~ /KSO(\d+)[fl]/) {
        $kkper = $1;
    }
    if ($opt_S =~ /SMA(\d+)f/) {
        $ssper = $1;
    }
} else {
    $setupcond = "";
}
if ($system =~ /cross(\d+)x(\d+)/) {
    $maBlue = $1;  $maGreen = $2;
} else {
    $maBlue = 0; $maGreen = 0;
}
if ($system =~ /VolEOD\d+[CX](\d+)M\d+/) {
    $kperi = $1;
} elsif ($opt_k) {
    $kperi = $kkper;
}
$swa = $kkper unless $swa;

#
# get the dates and price data for this stock
#
if ($tick =~ /\.csv/) {
    open DIN, "$path/data/$tick" or die "ERROR, no such file $tick\n";
    while ($in = <DIN>) {
        next if $in =~ /^\D/;
        chomp($in);
        @data0 = split /,/, $in;
        # check for proper format of date/time
        if ($data0[0] =~ /(\d{2}).(\d{2}).(\d{4})\s(.*)/) {
            $data0[0] = "$3-$2-$1T$4"; #print "$data0[0]\n"; exit;
        }
        push @date, $data0[0];
        $openp{$data0[0]} = $data0[1];
        $closep{$data0[0]} = $data0[4];
        $maxp{$data0[0]} = $data0[2];
        $minp{$data0[0]} = $data0[3];
        if ($data0[0] ge $dayEnd) {
            $p2 = $data0[4]; 
        } elsif ($data0[0] ge $dayBegin) {
            $p1 = $data0[4];
        }
    }
    close DIN;
} else {
    @data = `sqlite3 "$dbfile" "SELECT date, day_open, day_high, day_low, day_close, volume \\
									   FROM stockprices \\
									   WHERE symbol = '$tick' \\
									   ORDER BY date \\
									   DESC"`;
    chomp(@data); # contains the dates with most recent first
    $p1 = 0; 
    $p2 = 0;
    #
    # populate price hashes and date arrays
    #
    foreach $in (@data) {
        @data0 = split /\|/, $in;
        push @date, $data0[0];
        $openp{$data0[0]} = $data0[1];
        $maxp{$data0[0]} = $data0[2];
        $minp{$data0[0]} = $data0[3];
        $closep{$data0[0]} = $data0[4];
        $volume{$data0[0]} = $data0[5];
        if ($data0[0] ge $dayEnd) {
            $p2 = $data0[4]; 
        } elsif ($data0[0] ge $dayBegin) {
            $p1 = $data0[4];
        }
    }
}
if ($date[0] gt $date[-1]) {
    @datein = reverse @date;
} else {
    @datein = @date;
    @date = reverse @datein; 
}
#
# the day as function of the index of the day (good for calling indicators with day-before)
# day before: $hday{$dayindex{$day}-1}
#
$ii = 0;  
foreach $in (@datein) {
    $ii++;
    $hday{$ii} = $in;  
    $dayindex{$in} = $ii;  
}
if ($opt_q) {
    print "$ii candles read from $datein[-1] to $datein[0]...";
    exit();
}

#
# check for sufficient number of days before start of backtesting period
#
if ($dayBegin lt $date[-12]) {
    print "ERROR: $dayBegin given, but first allowed date is $date[-12]\n";
    exit();
}

# special case of SMA highs and lows
if ($setupcond =~ /HiLo(\d+)/) {
    $hiloper = $1;
    %sma = smaHash($tick, \%hday, \%dayindex, \%closep, $hiloper, $date[-$hiloper], $dayEnd);
    my ($hilo, $datehl, $ishigh, $th, $tl) = getHiLo(\%sma);
    @hilo = @$hilo; @datehl = @$datehl; @ishigh = @$ishigh; %trendh = %$th; %trendl = %$tl;
    @hilo{@datehl} = @hilo;
    $nex = @hilo;
}

#
# open the bookkeeping files:
#
# RELI : 	Overview for each assumed trade
#			tick l/s day-in price-in price-break range n i volN DvolN N-touch_up N-touch_low n_past MPE(close)_i MPE(ex)_i MAE_i MIAE_i MIAE% MIAEv RR
#   where...
#           price-in = entry price, for EOD equals close
#           price-break = the breakout level if the system is of such sort, otherwise equals price-in
#           range = delta, i.e, range of the box of which we're breaking out; high_n - low_n
#           n = number of candles going back, not including today, i.e. the AllTime-range
#           i = number of days looking forward for reliability (@days). For each n, we'll have all values of i
#           volN = normalized relative volume for current day, i.e. vol/<vol>_N
#           DvolN = slope (two-point) of volN
#           N-touch_up = number of touches of the upper box limit during last n days
#           N-touch_low = number of touches of the lower box limit during last n days
#           n_past = number of days since the last signal
#           MPE(close)_i = MPE in the i days looking forward, absolute difference of close prices to price-in
#           MPE(ex)_i = MPE in the i days looking forward, absolute difference of high/low prices to price-in
#           MAE_i = MAE in the i days looking forward, absolute difference of high/low prices to price-in
#           MIAE_i = MAE of the days prior to the day of MPE(close)_i
#           MIAE% = MIAE_i in % of price-in
#           MIAE% = MIAE_i in terms of ATR(14)
#           RR = MPE(close)_i / MIAE_i; a rough reward-risk-ratio
#

# Either use an existing output file or start the calcuulations
#
if ($opt_e && $opt_p) {
    @files = glob("${btdir}reli_${system}_${tick}*"); chomp(@files); $ii = @files; print "There are $ii files...\n";
    $ii = -1;
    while (-z $files[$ii]) {
        $ii--;
    }
    print "Using file = $files[$ii]\n";
    open RELI, "<$files[$ii]" || die "zm,.w37fba9";
    while ($in = <RELI>) {
        next unless $in =~ /^\d/;
        chomp($in);
#               if this changes further down, then change here as well!
#                push @reli, [$inprice, $priceb, $pricer, $n, $numdays, $volume{$day}/$vol, 100*($vol-$volyd)/$vol, 
#                        $mpe_c, $mpe_ex, $mae, $miae, 100*$miae/$inprice, $miae/$atr, $rr, $dypast] if ($i == $iplot);
#                printf RELI "$numtrades:\t%7.7s %-5.5s $day $numdays %7.2f %7.2f %7.2f $n $i %7.2f %7.2f Nu Nd $dypast %7.2f %7.2f %7.2f %7.2f %7.2f %7.2f %7.2f\n", 
#                        $tick, $opentrade, $inprice, $priceb, $pricer, $volume{$day}/$vol, 100*($vol-$volyd)/$vol, 
#                        $mpe_c, $mpe_ex, $mae, $miae, 100*$miae/$inprice, $miae/$atr, $rr;
        ($numtrades, $tick, $opentrade, $day, $numdays, $inprice, $priceb, $pricer, $n, $i, $vol, $dvoln, $nu, $nd, $dypast, $mpe_c, $mpe_ex, $mae, $miae, $m1, $ma, $rr) = split /\s+/, $in;
        push @reli, [$inprice, $priceb, $pricer, $n, $numdays, $vol, $dvoln, $mpe_c, $mpe_ex, $mae, $miae, $m1, $ma, $rr, $dypast] if ($i == $iplot);
    }
} else {
    open RELI, ">${btdir}reli_${system}_${tick}_${unique}_${dayBegin}_${dayEnd}.txt" or die "msttr52r";
    print RELI "System = $system, Max look-back = $maxd\n";
    print RELI "# Comment: $comment\n" if ($opt_C || $opt_S);
    print RELI "# tick l/s shares day-in price-in price-break range n i volN DvolN N-touch_up N-touch_low MPE(close)_i MPE(ex)_i MAE_i MIAE_i\n";
    
    ###
    ###  MAIN LOOP; walk-forward day by day
    ###
    MAIN:foreach $day (@datein) {
    
        $indexday++;    # counting all days in the full range of the database
        if ($day lt $dayBegin) { 
            # save the dates as yesterday for tomorrow...
            $yyday = $yday;
            $yday = $day;
            next;
        }
        last if ($day gt $dayEnd);
        #print "$day .. ";
        $numdays++;     # counting the days in the testing range
        $dypast++;      # counting the days since the last signal
        $duratrades = 0;    # initialize the book keeping for cross strategies
        
        if ($numdays == 1 && $swfiltfac) {  # first time through; get initial swing parameters for _yesterday_
            @swing = getSwing($swa, \%hday, \%dayindex, \%maxp, \%minp, \%closep, $yday, 0, 0, 0, $swfiltfac);
        }
        
        #
        # the daily parameters
        #
        $min = $minp{$day};  $max = $maxp{$day}; $openp = $openp{$day}; $closep = $closep{$day}; 
        if ($openp < $closep) { # white candle
            $upper = $closep;
            $lower = $openp;
            $daydir = 1;
        } else {                # black candle
            $upper = $openp;
            $lower = $closep;
            $daydir = -1;
        }
    
    
        #
        # 1.    Testing the setup conditions (using yesterday if appropriate, i.e. stop-buy)
        #
        if ($intraday) {
            $subday = $yday;
            $ysubday = $yyday;
        } else {
            $subday = $day;
            $ysubday = $yday;
        }
        if ($setupcond =~ /HiLo/) {
            $oldsetupOK = $trendh{$day} . ":" . $trendl{$day};
        }
        ($setupOK, $donotenter, $stopBuyL, $stopBuyS) = getSetupCondition($tick, $system, $setupcond, \%hday, \%dayindex, \%openp, \%maxp, \%minp, \%closep, \%volume, $subday, $oldsetupOK); 
        # tracking the duration of the setup condition... NOTE; some logic for cross missing about the duration...
        if ($setupOK ne $oldsetupOK) {
            $prevDura = $dura;
            $dura = 1;
            $duratrades = 0;    # any trades taken yet in this cycle?
        } else {
            $dura++;
        }
        $oldsetupOK = $setupOK;
        #printf "%7.7s: not = %5.5s, setupOK = %-9.9s. ", $tick, $donotenter, $setupOK;
        
        #
        # 2.    getting entry and exit signals
        #
        if ( ($stopBuyL || $stopBuyS) && ! ($stopBuyL && $stopBuyS) ) {
            $relevantPrice = $stopBuyL + $stopBuyS; # one of them is zero...
        } elsif ($swfiltfac) {
            $relevantPrice = \@swing;   # is an array pointer for swing strategies
        } elsif ($system =~ /HiLo/) {
            $reenter = 0;
            $relevantPrice = [$trendh{$day}-$trendh{$yday}, $trendl{$day}-$trendl{$yday}, $reenter];
        } else {
            $relevantPrice = $closep;
        }
        $opentrade = 0; # every day is a new day...
        $inp = 0;
        $istop = 0;
        ($entrySig, $exitSig, $outtext, $ptxt, $xprice) = getSignal($tick, $system, \%hday, \%dayindex, \%openp, \%maxp, \%minp, \%closep, $day, $opentrade, $numdays - $dayoftrade, $inp, $istop, $relevantPrice, $setupOK);    # $entrySig and $exitSig is either "long", "short", or ""
        # if the setup was not OK, then cancel the entry signal
        if ($donotenter eq $entrySig) {
            $entrySig = "";
        }
        if ($swfiltfac) {
            # $outtext is array ref; first element is the current swing direction
            @swing = @$outtext;
            $outtext = '';
            $swdir{$day} = $swing[0];
        } elsif ($setupcond =~ /HiLo/) {  # using the same arrays for plotting
            $swdir{$day} = ($trendh{$day}+$trendl{$day})/2;
        }
        if ($opt_O) {
            # we may want to cancel certain candle patterns...
            foreach $otxt (@otxt) {
                if ($outtext =~ /$otxt/) {
                    $entrySig = ""; print " Cancel signal for $outtext (matched $otxt) ";
                }
            }
        }
        if ($opt_r) {
            # reverse the signals!
            if ($entrySig eq 'long') {
                $entrySig = 'short';
            } elsif ($entrySig eq 'short') {
                $entrySig = 'long';
            }
            if ($exitSig eq 'long') {
                $exitSig = 'short';
            } elsif ($exitSig eq 'short') {
                $exitSig = 'long';
            }
        }
    
        #
        # 3.    we have an entry signal, so open a position using the appropriate price
        #       and do the stats (walk-forward) on the entry
        #
        if ($setupOK =~ /$entrySig/ && $entrySig) {	
            $opentrade = $entrySig;
            $dayTrade = $day;
            push @dayTrade, $dayTrade;
            if ($intraday) {
                $inprice = $openp;
            } else {
                $inprice = $closep;
            }
            $inprice{$dayTrade} = $inprice;
            $direction{$dayTrade} = $opentrade;
    
            $numtrades++;
            $dayoftrade = $numdays;
            print " $day: $opentrade signal .. \n";
            if ($system =~ /AllTime[CXS]*(\d+)[xc]/) {
                $n = $1;
                $priceb = $outtext;
                $pricer = $ptxt;
            } elsif ($system =~ /Spike/) {
                $n = 1;
                $priceb = $outtext;
                $pricer = $ptxt;
            } else {
                $n = 1;
                $priceb = $inprice;
                $pricer = $inprice;
            }
            if ($opentrade eq 'long') {
                %ex = %minp;
            } elsif ($opentrade eq 'short') {
                %ex = %maxp;
            }
            foreach $i (@days) {
                # MAE, MPE always positive numbers!
                # first calc MPE and MAE for the day after entry...
                if ($opentrade eq 'long') {
                    $mae = ($inprice - $minp{$hday{$dayindex{$day}+1}});
                    $mpe_ex = ($maxp{$hday{$dayindex{$day}+1}} - $inprice);
                    $mpe_c = ($closep{$hday{$dayindex{$day}+1}} - $inprice);
                } elsif ($opentrade eq 'short') {
                    $mae = ($maxp{$hday{$dayindex{$day}+1}} - $inprice);
                    $mpe_ex = ($inprice - $minp{$hday{$dayindex{$day}+1}});
                    $mpe_c = ($inprice - $closep{$hday{$dayindex{$day}+1}});
                }
                $mpe_ex = 0.0 if $mpe_ex < 0;
                $mpe_c = 0.0 if $mpe_c < 0;
                $mae = 0.0 if $mae < 0;
                $miae = $mae;
                $idx = 2;
                # ... then find the extremes for the full forward period
                for ($j = 2; $j <= $i; $j++) {
                    if ($opentrade eq 'long') {
                        if ($mpe_c < $closep{$hday{$dayindex{$day}+$j}} - $inprice) {
                            $mpe_c = $closep{$hday{$dayindex{$day}+$j}} - $inprice;
                        }
                        if ($mpe_ex < $ex{$hday{$dayindex{$day}+$j}} - $inprice) {
                            $mpe_ex = $ex{$hday{$dayindex{$day}+$j}} - $inprice;
                            $idx = $j;
                        }
                        if ($mae < $inprice - $ex{$hday{$dayindex{$day}+$j}}) {
                            $mae = $inprice - $ex{$hday{$dayindex{$day}+$j}};
                        }
                    } elsif ($opentrade eq 'short') {
                        if ($mpe_c < $inprice - $closep{$hday{$dayindex{$day}+$j}}) {
                            $mpe_c = $inprice - $closep{$hday{$dayindex{$day}+$j}};
                        }
                        if ($mpe_ex < $inprice - $ex{$hday{$dayindex{$day}+$j}}) {
                            $mpe_ex = $inprice - $ex{$hday{$dayindex{$day}+$j}};
                            $idx = $j;
                        }
                        if ($mae < $ex{$hday{$dayindex{$day}+$j}} - $inprice) {
                            $mae = $ex{$hday{$dayindex{$day}+$j}} - $inprice;
                        }
                    }
                }
                # ... and the MIAE
                for ($j = 2; $j <= $idx; $j++) {
                    if ($opentrade eq 'long') {
                        if ($miae < $inprice - $ex{$hday{$dayindex{$day}+$j}}) {
                            $miae = $inprice - $ex{$hday{$dayindex{$day}+$j}};
                        }
                    } elsif ($opentrade eq 'short') {
                        if ($miae < $ex{$hday{$dayindex{$day}+$j}} - $inprice) {
                            $miae = $ex{$hday{$dayindex{$day}+$j}} - $inprice;
                        }
                    }
                }
                $mpe_ex = 0.0 if $mpe_ex < 0;
                $mpe_c = 0.0 if $mpe_c < 0;
                $mae = 0.0 if $mae < 0;
                $miae = 0.0 if $miae < 0;
    
                #	tick l/s day-in price-in price-break range n i volN DvolN N-touch_up N-touch_low n_past MPE(close)_i MPE(ex)_i MAE_i MIAE_i MIAE% MIAEv RR
                $atr = atr($tick, \%hday, \%dayindex, \%maxp, \%minp, \%closep, 14, $subday);
                $vol = sma($tick, \%hday, \%dayindex, \%volume, 14, $subday);
                $volyd = sma($tick, \%hday, \%dayindex, \%volume, 14, $ysubday);
                if ($miae > 0) {
                    $rr = $mpe_c / $miae;
                } else {
                    $rr = 99.99;    # funny value to signal a zero MIAE
                }
                printf RELI "$numtrades:\t%7.7s %-5.5s $day $numdays %7.2f %7.2f %7.2f $n $i %7.2f %7.2f Nu Nd $dypast %7.2f %7.2f %7.2f %7.2f %7.2f %7.2f %7.2f\n", 
                        $tick, $opentrade, $inprice, $priceb, $pricer, $volume{$day}/$vol, 100*($vol-$volyd)/$vol, 
                        $mpe_c, $mpe_ex, $mae, $miae, 100*$miae/$inprice, $miae/$atr, $rr;
                push @reli, [$inprice, $priceb, $pricer, $n, $numdays, $volume{$day}/$vol, 100*($vol-$volyd)/$vol, 
                        $mpe_c, $mpe_ex, $mae, $miae, 100*$miae/$inprice, $miae/$atr, $rr, $dypast] if ($i == $iplot);
            }
            $dypast = 0;    # resetting the number of days since last signal
        }
        
        #
        # save the dates as yesterday for tomorrow...
        $yyday = $yday;
        $yday = $day;
    
    }
    ###
    ### END of MAIN LOOP
    ###
}
close RELI;
print "done! stamp = $unique\n";

if ($opt_p) {
    # plotting of a particular look-forward period
    $font = 2;
    $linewidth = 1;
    $charheight = 1.2;
    foreach $reli (@reli) {
        @tmp = @$reli; #print "inprice = $tmp[0] -- OK???\n"; exit;
        push @x, $tmp[4];
        push @miae, -$tmp[12]; # MIAE in units of ATR (below zero line)
        push @miaep, -$tmp[11]; # MIAE in % of in-price
        push @mpe, $tmp[7] *100.0/$tmp[0]; # MPE in % of in-price
        $tmp[13] = 5.0 if ($tmp[13] > 5.0);
        push @rr, $tmp[13]; # the ~ R/R ratio
        if ($tmp[14] > $iplot) {
            push @xline, $tmp[4];
            push @pos1, $tmp[7] *100.0/$tmp[0];
            push @pos2, $tmp[13];
            push @neg1, -$tmp[11];
            push @neg2, -$tmp[12];
        }
    }
    $ii = @x;
    $ni = @xline;
    $device = "${btdir}relp_${tick}_${unique}-1.png/PNG"; #print "plotting to PNG";
    pgbeg(0,$device,1,1); # || warn "pgbeg on $device says: $!\n"; # Open plot device 
    pgscf($font); # Set character font 
    pgslw($linewidth); # Set line width 
    pgsch($charheight); # Set character height 
    pgsci(1);  # default colour
    $yplot_low = min(@miaep); 
    $yplot_hig = max(@mpe); 
    ($xplot_low, $xplot_hig) = low_and_high(@x);
    $xplot_low=0; $xplot_hig++;
    $mean = ( $yplot_hig - $yplot_low ) * 0.05;
    $yplot_hig += $mean; $yplot_low -= $mean;
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, 0);
    pglabel("day #", "Max Excursion", "$tick - $unique");
    pgsls(2);
    pgline(2, [$xplot_low,$xplot_hig], [0,0]);  # zero-line
    pgsls(1);
    pgslw(1); # Set line width 
    pgsci(2); # red
    pgpoint($ii, \@x, \@miaep, 31);
    pgsci(3); # green
    pgpoint($ii, \@x, \@mpe, 30);
    pgslw($linewidth);
    for ($i = 0; $i < $ni; $i++) {
        pgsci(3); # green
        pgline(2, [$xline[$i],$xline[$i]+$iplot], [$pos1[$i],$pos1[$i]]);
        pgsci(2); # red
        pgline(2, [$xline[$i],$xline[$i]+$iplot], [$neg1[$i],$neg1[$i]]);
    }
    pgend;

    $device = "${btdir}relp_${tick}_${unique}-2.png/PNG"; #print "plotting to PNG";
    pgbeg(0,$device,1,1); # || warn "pgbeg on $device says: $!\n"; # Open plot device 
    $yplot_low = min(@miae); 
    $yplot_hig = max(@rr); 
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, 0);
    pglabel("day #", "MIAE/ATR --- MPE/MIAE", "$tick - $unique");
    pgsls(2);
    pgline(2, [$xplot_low,$xplot_hig], [0,0]);  # zero-line
    pgsls(1);
    pgslw(1); # Set line width 
    pgsci(2); # red
    pgpoint($ii, \@x, \@miae, 31);
    pgsci(3); # green
    pgpoint($ii, \@x, \@rr, 30);
    pgsls(4); pgsci(9);
    for ($i = 0; $i < $ii; $i++) {
        if ($miae[$i] > 0.0) {
            $frac = $rr[$i]/$miae[$i];
        } else {
            $frac = $rr[$i];
        }
        if ($frac >= 3.0) {
            pgline(2,[$x[$i],$x[$i]], [$rr[$i],$miae[$i]]);
        }
    }
    pgsls(1);
    for ($i = 0; $i < $ni; $i++) {
        pgsci(3); # green
        pgline(2, [$xline[$i],$xline[$i]+$iplot], [$pos2[$i],$pos2[$i]]);
        pgsci(2); # red
        pgline(2, [$xline[$i],$xline[$i]+$iplot], [$neg2[$i],$neg2[$i]]);
    }
    pgend;
}

#########################
#####   END   ###########


#!/usr/bin/perl -w -I/Users/tdall/copyExecs
# 
# generate backtests - new version (Sep.2012)
#
# TODO (someday/maybe): allow adding to positions, but only if not entering additional risk.
#
# arg 1 = ticker symbol
# arg 2 = starting date
# arg 3 = end date
# arg 4 = system name; entry strategy/setup/signal
# arg 5 = initial stop strategy
# arg 6 = running stop/exit strategy
# arg 7 = alternative stop/exit strategy used if some condition is fulfilled
# [-q] print info on the data and exit.
# [-p] make PNG plots for each trade and for summary plots
# [-n] do not plot the individual trades - overrides -p. Still makes summary plots if -p.
# [-x <range>] extend x-range of plots so many days into the past, defaults to 5
# [-X <range>] extend x-range of plots so many days into the future, defaults to 10
# [-C <comment>] comment to include in output files
# [-T <mult>{o|x|c}<fac>] first price target for parabolic stop at mult*R, once that's hit, it moves to fac*mult*R, use open, extreme or close price as given
# [-S <setup-name>] use this setup
# [-s <sma1>:<sma2>] plot these two SMAs as well
# [-e <ema1>:<ema2>] plot these two EMAs as well
# [-U] stop out same day if stop is within max-min range. Default is stop-out if stop is within real body.
# [-u slip] slippage and spread as a percentage of the current price, default is 0.0
# [-a slip] slippage in absolute values, defaullt is 0.0
# [-f fee] one-way fee, default is 5.90
# [-c cash] intial account size. default is 10000.
# [-R q:x_0.25:mm] risk management; adjust risk percentage with drawdown (1-dd)^q; consequtive losses 1/(3*N_cl/x_0.25 + 1);
#       markets-money...
# [-k kkperi:smaperi] record KSO<peri> and SMA<peri> slopes in trade_ file
# [-w per] using swing numbers so mark on plots. per = swingfilter in percent. If strategy =~ Swing, then take that percentage
# [-O txt:txt:...] if txt returned from getSignal matches, then cancel the signal (e.g. to disregard certain candle patterns)
# [-r] reverse the signal, i.e., turn a 'long' signal into 'short' and vice versa
# [-E <ReEntryR>] re-entry allowed with R = ReEntryR as the divider between 'losers' and 'winners'
# [-L <limitR>] Do a Local_1 stop after entry until R > limitR, then use normal stop until then.
# [-i] initial tight stop if position goes against me from the onset

use Carp;
use Getopt::Std;
use PGPLOT;
#use strict;
require "utils.pl";
require "pg_utils.pl";
require "trader_utils.pl";

$|=1;
#my ($opt_r,$opt_q,$opt_p, $opt_x, $opt_X, $opt_C, $opt_n, $opt_T, $opt_S, $opt_s, $opt_U, $opt_u, $opt_a, $opt_f, $opt_R, $opt_k, $opt_w, $opt_O);
getopts('c:rqpx:X:C:nT:S:s:e:Uu:a:f:R:k:w:O:E:L:');
print "$opt_U $opt_R $opt_q $opt_r" if 0;
#
# variable declarations
#
my $numa = @ARGV;
die "Not enough args\n" unless ($numa == 7);
my $path = "/Users/tdall/geniustrader/";
my $dbfile = "/Users/tdall/geniustrader/traderThomas";
my $btdir = "/Users/tdall/geniustrader/Backtests/";
my $norw = "n";  # [n]arrowest or [w]idest stop if several options are given
my $whichway = "";   # long or short
my $opentrade = "";  # long or short
my $cash = 10000.0;
if ($opt_c) { $cash = $opt_c; }
my $cash0 = $cash;
my $riskPinit = 0.01;  # risk fraction (initial)
my $riskMax = 0.03; # absolute max risk fraction
my $riskP = $riskPinit;
my $pvalue = $cash;  
my $fee1way = 5.90;    my $slippage = 0.0; # default values. Slippage is a PERCENTAGE of the current price.
my %possize = ();   my %stop = ();  my %istop = (); my %inprice = ();   my %direction = (); my @dayTrade = ();
my %exitp = (); my %daysintrade = ();   my %maxPE = (); my %maxAE = (); my %relPE = (); my %relAE = ();
my $maxdd = 0.0; my $dd = 0.0; my $lloser = 0;  my $nloser = 0;
my $numdays = 0; my $numdd = 0; my $phigh = $pvalue;
my $numtrades = 0; my %pvalue = (); my %rmult = (); my %swdir = ();
my %ntrade = ();  my %runPval = (); my %hday = (); my %dayindex = ();
my %openp = (); my %maxp = (); my %minp = (); my %closep = ();  # the price hashes, taking date as key
my $indexday = 0; my $ii = 0; my @date = (); my $dayoftrade = 0;
my $setupOK = "";  # set to 'long' or 'short' or 'longshort' if we're accepting signals
my $oldsetupOK = "long";
# @rMult visualized as colored (@col) symbols (@sym)
my @rMult = (); my @col = (); my @sym = ();
my %sym = ();   my %col = ();
my @maeFull = ();  my @mpeFull = ();
my @maBlue = ();    my @maGreen = ();
my @hilo = (); my @datehl = (); my @ishigh = ();    my %trendh = (); my %trendl = ();   my %hilo = (); my %ishigh = ();
my ($tick, $dayBegin, $dayEnd, $system, $sysInitStop, $sysStop, $sysExitStop) = @ARGV;
my ($comment, $xbefore, $xafter, $setupcond, $maBlue, $maGreen, $unique, $day, $yday, $yyday, $intraday, $slip, $i, $reenter);
my ($min, $max, $openp, $closep, $upper, $lower, $daydir, $dayTrade, $stop, $exitp, $stopBuyL, $stopBuyS, $donotenter, @data, $p1, $p2);
my ($in, @data0, $juststoppedout, @addall, @xx, @xs, @yy, @ss, @open, @low, @high, $subday, $dura, $prevDura, $relevantPrice);
my ($entrySig, $exitSig, $outtext, $txt, $ptxt, $xprice, $curprice, $inprice, $posprice, $risk, $whichPriceT, $targFac);
my ($pltext, $iTarget, $targetPrice, $targMul, $inp, $istop, $smax, $smin, $adx0, $tnote, $device, $dum, @dum, $trfac, $tr);
my ($vbfac, @price, $tot, $gain, $sym, $col, $nd, $myin, $good1, $good2, $dc, $ssper, $swfiltfac, @swing, $swa, @otxt, $nex, $idx);
my ($npos, $nneg, $meanpos, $sigpos, $meanneg, $signeg, $mae0, $mpe0, $numTrades, $meanR, $sigma, $sq, $rewrisk, @datein);
my ($datr, %swcol,%swsym);
#
# cleanup and init variables
#
$pvalue{$numtrades} = $cash;  # zero'th entry is the starting account size
$sysInitStop =~ s/_/ /g;
$sysStop =~ s/_/ /g;
$sysExitStop =~ s/_/ /g;
$sysOrigTrailStop = $sysStop;
#
# 'intraday' == buying during day, not on close
# add more as more intraday/stop-buy systems are added
if ($system =~ /VolB/ || $system =~ /LUXcross/ || $system =~ /Daybreak/ || $system =~ /InsideDay/) {    
    $intraday = 1;
} else {
    $intraday = 0;
}

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
if ($opt_u) {
    $slippage = $opt_u;
} elsif ($opt_a) {
    $slippage = $opt_a;
}
if ($opt_f) {
    $fee1way = $opt_f;
}
if ($opt_O) {
    @otxt = split /:/, $opt_O;
}
if ($opt_E) {
    $reentryR = $opt_E;
    $reLong = 0; $reShort = 0;
    $reTrending = 0; $reSideways = 0;
}
if ($opt_L) {
    $limitR = $opt_L;
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
if ($opt_T) {
    # splits into an initial target and a multiplier. Second target is then initial*multiplier and so on.
    # target is to be claculated using [o]pen, e[x]treme (i.e. high/low), or [c]lose prices
    $opt_T =~ /([oxc])/;
    $whichPriceT = $1;
    ($iTarget, $targMul) = split /$whichPriceT/, $opt_T;
    $targMul = 1.0 unless $targMul;
    warn "Error? Found price=$whichPriceT and target parameters $iTarget,$targMul... " unless ($whichPriceT =~ /[oxc]/);
}
if ($opt_x) {
    $xbefore = $opt_x;
} else {
    $xbefore = 5;
}
if ($opt_X) {
    $xafter = $opt_X;
} else {
    $xafter = 10;
}
if ($opt_C) {
    $comment = $opt_C;
    $comment .= "## -T${opt_T}" if $opt_T;
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
    if ($opt_s) {
        ($maBlue, $maGreen) = split /:/, $opt_s;
    } elsif ($opt_e) {
        ($maBlue, $maGreen) = split /:/, $opt_e;
    } else {
        $maBlue = 0; $maGreen = 0;
    }
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
    #print "hday = $in, index = $ii\n"; exit if $ii > 10;
}
if ($opt_q) {
    print "$ii candles read from $datein[-1] to $datein[0]...";
    exit();
}
#
# buy-and-hold results, plus 10% risk invested result
#
my $resBHfull = int ($cash / $p1) * ($p2 - $p1) + $cash - 2*$fee1way;
my $resBHrisk = int ($cash * 0.1 / $p1) * ($p2 - $p1) + $cash - 2*$fee1way; # assuming 10% of funds invested, no risk consideration

#
# check for sufficient number of days before start of backtesting period
#
if ($dayBegin lt $date[-12]) {
    print "ERROR: $dayBegin given, but first allowed date is $date[-12]\n";
    exit();
}

# special case of SMA highs and lows
if ($setupcond =~ /HiLo(\d+)/ || $system =~ /^SMA(\d+)/) {
    $hiloper = $1; print "Calculating HiLo for P = $hiloper... ";
    %sma = smaHash($tick, \%hday, \%dayindex, \%closep, $hiloper, $date[-$hiloper], $dayEnd);
    my ($hilo, $datehl, $ishigh, $th, $tl) = getHiLo(\%sma);
    @hilo = @$hilo; @datehl = @$datehl; @ishigh = @$ishigh; %trendh = %$th; %trendl = %$tl;
    @hilo{@datehl} = @hilo;
    @ishigh{@datehl} = @ishigh;
    $nex = @hilo;
}

#
# open the bookkeeping files:
#
# TRADE : 	Overview for each trade
#			Trade#  tick  l/s  shares  day-in  price-in  day-out  price-out  R-multiple  duration  extra_note
#
# OUT : 	Summary file with info on the total statistics.
#
open TRADE, ">${btdir}trades_${system}_${tick}_${unique}_${dayBegin}_${dayEnd}.txt" or die "msttr52r";
print TRADE "System = $system, Initial stop method = $sysInitStop, Exit/Stop = $sysStop\n";
print TRADE "# Comment: $comment\n" if ($opt_C || $opt_S);
print TRADE "# Trade#  tick  l/s  shares   day-in     price  day-out     price  R-mult  duration\n";
open OUT, ">${btdir}summary_${system}_${tick}_${unique}_${dayBegin}_${dayEnd}.txt" or die "a83mnmn0112";
print OUT "System $system, Portfolio = $pvalue, risk% = "; printf OUT "%.2f\n", $riskP*100;

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
	# print "$day .. ";
    $runPval{$indexday} = $pvalue;  # running portfoliovalue day for day
	$numdays++;     # counting the days in the testing range
    $juststoppedout = "";   # reset the just-stopped-out flag
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
	if ($opt_u) {
        $slip = $slippage * $closep / 100.0;
    } elsif ($opt_a) {
        $slip = $slippage;
    } else {
        $slip = 0.0;
    }

    #
    # test parameters in case of a price target
    #
    if ($opt_T && $opentrade) {
        if ($whichPriceT eq "o") {
            $curprice = $openp;
        } elsif ($whichPriceT eq "x") {
            if ($opentrade eq "long") {
                $curprice = $max;
            } elsif ($opentrade eq "short") {
                $curprice = $min;
            } else {
                $curprice = 0;  # will be assigned if a trade is opened on this day
            }
        } elsif ($whichPriceT eq "c") {
            $curprice = $closep;
        } else {
            die "Error: cannot assign price '$whichPriceT'\n";
        }
    } elsif ($intraday && $opentrade) {
        if ($opentrade eq "long") {
            $curprice = $max;
        } elsif ($opentrade eq "short") {
            $curprice = $min;
        } else {
            $curprice = 0;  # will be assigned later if a trade is opened on this day
        }
    } else {
        $curprice = $closep;
    }

    #
    # 1.    if we have open position, check first if we've been stopped out during the day 
    #       with the stop level carried over from yesterday... 
    #
	if ($opentrade) {  
		push @xx, $dayindex{$day};
		push @yy, $closep; push @open, $openp; push @low, $min; push @high, $max;
		push @xs, $dayindex{$day};  push @ss, $stop{$dayTrade}; 
		if ( ($direction{$dayTrade} eq "long" && $min-$slip <= $stop{$dayTrade}) || ($direction{$dayTrade} eq "short" && $max+$slip >= $stop{$dayTrade}) ) {
		    # we're being stopped out ...
		    #
			printf " $day: stopped out at %.2f - ", $stop{$dayTrade};
			if ( ($stop{$dayTrade} > $openp && $direction{$dayTrade} eq "long") || ($stop{$dayTrade} < $openp && $direction{$dayTrade} eq "short") ) {
			    $stop = $openp;
			} else {
			    $stop = $stop{$dayTrade};
			}
            # flag to indicate that we got stopped out today. Later we can deceide if it should have an effect
            # Will be reset at the beginning of next day.
            $juststoppedout = $opentrade;
            $daysintrade{$dayTrade} = $numdays - $dayoftrade;
            &stopMeOut();
            $pvalue{$numtrades} = $pvalue;
            $exitp{$dayTrade} = $stop;
            printf TRADE "$day %7.2f %6.3f %3.3s %-5.5s $outpars\n", $stop{$dayTrade}, $rmult{$dayTrade}, $daysintrade{$dayTrade}, $tnote;
            # check if re-entry is allowed and if we need to set some parametrs for that...
            if ($opt_E) {
                if ($rmult{$dayTrade} < $reentryR) {    # could be a sideways market...
                    $reSideways = 1;
                    $reTrending = 0;
                    # setting re-entry price at the extreme of the trade
                    if ($direction{$dayTrade} eq "long") {
                        $reLong = max(@high);
                    } elsif ($direction{$dayTrade} eq "short") {
                        $reShort = min(@low);
                    }
                } elsif ($rmult{$dayTrade} > $reentryR) {   # could be a trending market...
                    $reTrending = 1;
                    $reSideways = 0;
                    if ($direction{$dayTrade} eq 'long') {
                        $reLong = $exitp{$dayTrade};
                        $reShort = 0;
                    } elsif ($direction{$dayTrade} eq 'short') {
                        $reShort = $exitp{$dayTrade};
                        $reLong = 0;
                    }
                }
            }
		}
	}

    #
    # 2.    Testing the setup conditions (using yesterday if appropriate, i.e. stop-buy)
    #
	if ($intraday) {
	    $subday = $yday;
	} else {
	    $subday = $day;
	}
	if ($setupcond =~ /HiLo/) {
	    $oldsetupOK = $trendh{$day} . ":" . $trendl{$day};
	}
	if ($setupcond =~ /ADX/) {
	    $oldsetupOK = $stopBuyL;
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
    # 3.    getting entry and exit signals
    #
	if ( ($stopBuyL || $stopBuyS) && ! ($stopBuyL && $stopBuyS) ) {
        $relevantPrice = $stopBuyL + $stopBuyS; # one of them is zero...
    } elsif ($swfiltfac) {
        $relevantPrice = \@swing;   # is an array pointer for swing strategies
    } elsif ($system =~ /HiLo[LS]/) {
        $reenter = 0;
        $relevantPrice = [$trendh{$day}-$trendh{$yday}, $trendl{$day}-$trendl{$yday}, $reenter];
    } elsif ($system =~ /^SMA/) {
        if (exists $hilo{$yday}) {
            $relevantPrice = [$hilo{$yday}, $ishigh{$yday}]; # signal that yesterday was a high/low
        } else {
            $relevantPrice = [0,0];
        }
    } else {
        $relevantPrice = $closep;
    }
    if ($opentrade) {
        $inp = $inprice{$dayTrade};
        $istop = $istop{$dayTrade};
    } else {
        $inp = 0;
        $istop = 0;
    }
    # if the strategy does not incluse exit signals then no need to call when we have an open position
    if (!$opentrade || $system =~ /xyz/) {
        ($entrySig, $exitSig, $outtext, $ptxt, $xprice) = getSignal($tick, $system, \%hday, \%dayindex, \%openp, \%maxp, \%minp, \%closep, $day, $opentrade, $numdays - $dayoftrade, $inp, $istop, $relevantPrice, $setupOK);    # $entrySig and $exitSig is either "long", "short", or ""
        # if the setup was not OK, then cancel the entry signal
        if ($donotenter eq $entrySig) {
            $entrySig = "";
        }
        $breaklevel = $outtext if ($system =~ /AllTime/ && $entrySig);
    }  #### check following code logic... may not be consistent
    if ($swfiltfac) {
        # $outtext is array ref; first element is the current swing direction
        @swing = @$outtext;
        $outtext = '';
        $swdir{$day} = $swing[0];
    } elsif ($setupcond =~ /HiLo/) {  # using the same arrays for plotting
        $swdir{$day} = ($trendh{$day}+$trendl{$day})/2;
    }
    if ($system =~ /Simcross/ && $entrySig) {
        # re-entry only allowed if close > FAST > SLOW. Delayed entry of more than 3 days count as re-entry
        ($fast,$slow) = @$outtext;  # The SMA's are returnd as array ref in $outtext
        $outtext = '';
        if ($duratrades > 0 || $dura > 3) {     # NOTE: this is a hard-coded parameter, which is generally not a good idea...
            if ($entrySig eq 'long' && $closep > $fast) {
                1;  $slow += 0.0; # just to mention it to avoid warning
            } elsif ($entrySig eq 'short' && $closep < $fast) {
                1;
            } else {
                $entrySig = '';
            }
        } else {
            $duratrades = 1;    # that's the first trade of the cycle
        }
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
    # 4.    if open position, exit if we got an exit signal
    #
	if ($exitSig && $opentrade eq $exitSig) {
		# if an open trade exists and we get an exit signal...
		#
		$whichway = $exitSig;
		if ($xprice) {
		    $stop = $xprice;
		} else {
		    $stop = $closep;
		}
        $daysintrade{$dayTrade} = $numdays - $dayoftrade;
        &stopMeOut();
        $pvalue{$numtrades} = $pvalue;
        $exitp{$dayTrade} = $stop;
        printf TRADE "$day %7.2f %6.3f %3.3s %-5.5s $outpars\n", $stop{$dayTrade}, $rmult{$dayTrade}, $daysintrade{$dayTrade}, $tnote;
	}
    
    #
    # 5.    no open position, AND we have an entry signal, so open a position using the appropriate price
    #       Check immediately if we get stopped out on the same day (only if stop-buy)
    #
	if ($setupOK =~ /$entrySig/ && $entrySig && ! $opentrade) {	
        $entryNow = 1;
        $reTrending = 0;
        $reLong = 0;
        $reShort = 0;
    } elsif (!$opentrade && $opt_E) {
        if ($closep > $reLong && ($closep{$yday} < $reLong || $openp{$day} < $reLong)) {
            $entrySig = 'long'; $entryNow = 1;
        } elsif ($closep < $reShort && ($closep{$yday} > $reShort || $openp{$day} > $reShort)) {
            $entrySig = 'short'; $entryNow = 1;
        } else {
            $entryNow = 0;
        }
    } else {
        $entryNow = 0;
    }
	if ($entryNow) {	
		$opentrade = $entrySig;
		$dayTrade = $day;
		push @dayTrade, $dayTrade;
		if ($xprice > 0 && $intraday) {  # careful; this is meant for exit price, but can be used for entry wit strategies without exit signals
		    $inprice = $xprice;
		} else {
            $inprice = $closep;
        }
        $ok2changeStop = 1;
        # extra params for the plotting
        if ($system =~ /VolB/) {
            @dum = split /_/, $outtext;
		    $tr = $dum[1];
		    $vbfac = $dum[2]; # is the VolB percentage expressed as a fraction
		    @addall = ($inprice+$tr*$vbfac, $inprice-$tr*$vbfac);
        } else {
            @addall = ();
        }
        $inprice{$dayTrade} = $inprice;
		$direction{$dayTrade} = $opentrade;
		$risk = $riskP * $cash;
		$stop{$dayTrade} = getStop($sysInitStop, \%hday, \%dayindex, \%openp, \%maxp, \%minp, \%closep, $day, 0.0, 0.0, $tick, $opentrade, $inprice{$dayTrade}, $inprice{$dayTrade}, 0, 0, $norw);   # second-last arg is age of trade
		($possize{$dayTrade}, $posprice) = enterTrade($direction{$dayTrade}, $inprice{$dayTrade}, $stop{$dayTrade}, $risk);
		$possize{$dayTrade}++ if ($possize{$dayTrade} == 0);    # should rather increase account size, but just to avoid div by zero
		$cash -= ($posprice + $fee1way);
		$pvalue -= $fee1way;
		$numtrades++;
		$ntrade{$dayTrade} = $numtrades;
		$dayoftrade = $numdays;
		$istop{$dayTrade} = $stop{$dayTrade};
		print " $day: entering $opentrade trade .. ";  
		$pltext = "$outtext $ptxt";  # text for plot
		if ($outtext =~ /^(.*):/) {
		    $tnote = $1; # extra info contained here for some strategies
		} else {
		    $tnote = "";
		}
		# curprice is meant to check for whether a target price is hit
        $curprice = $max if ($opentrade eq "long");
        $curprice = $min if ($opentrade eq "short");
		if ($opt_T) {
		    $targFac = $iTarget * abs($inprice{$dayTrade} - $istop{$dayTrade});
		    if ($direction{$dayTrade} eq "long") {
		        $targetPrice = $inprice{$dayTrade} + $targFac;
		    } elsif ($direction{$dayTrade} eq "short") {
		        $targetPrice = $inprice{$dayTrade} - $targFac;
		    }
            printf " Target = %.2f ", $targetPrice;
		} else {
            $targetPrice = 0;
        }
        # Prepare for the plotting of the trade.
        # Back fill the plot arrays first with x previous days, then start filling day by day
        @xx = (); @yy = (); @xs = (); @ss = (); @open = (); @low = (); @high = ();  # for the plotting
        if ($xbefore > 0 && ! $opt_n) {
            for ($i = 1; $i <= $xbefore; $i++) {
                unshift @high, $maxp{$hday{$dayindex{$dayTrade}-$i}};
                unshift @low, $minp{$hday{$dayindex{$dayTrade}-$i}};
                unshift @open, $openp{$hday{$dayindex{$dayTrade}-$i}};
                unshift @yy, $closep{$hday{$dayindex{$dayTrade}-$i}};
                unshift @xx, $dayindex{$dayTrade}-$i; 
            }
        }
		push @xx, $dayindex{$dayTrade};
		push @yy, $closep; push @open, $openp; push @low, $min; push @high, $max;
		push @xs, $dayindex{$dayTrade};
		push @ss, $stop{$dayTrade}; 
        if ($opt_p) {
            $device = "${btdir}p_${unique}_${dayTrade}_${tnote}.png/PNG";
        } else {
            $device = "/XSERVE";
        }
		printf TRADE "$numtrades:\t%7.7s %-5.5s %4.4s $day %7.2f ", $tick, $opentrade, $possize{$dayTrade}, $inprice{$dayTrade};
		#
		# check for same-day stop-out if stop-buy
		if ($intraday) {
		    if ($opt_U) {
    		    # A quite conservative stop-out assumption: if stop is within full daily range
    		    $smin = $min - $slip;   # used for long positions
    		    $smax = $max + $slip;   # used for short positions
    		} else {
    		    # Not so strict: we're assumed OK as long as stop is not within real body of the day
    		    $smin = $lower - $slip;
    		    $smax = $upper + $slip;
    		}
		    if ( ($direction{$dayTrade} eq "long" && $smin <= $stop{$dayTrade}) || ($direction{$dayTrade} eq "short" && $smax >= $stop{$dayTrade}) ) {
                # we're being stopped out ...
                #
                if ($opentrade eq 'long') {
                    $stop = $stop{$dayTrade} - $slip;
                } elsif ($opentrade eq 'short') {
                    $stop = $stop{$dayTrade} + $slip;
                }
                printf " SAME-DAY stop-out at %.2f - ", $stop{$dayTrade};
                #$stop = $stop{$dayTrade};
                # flag to indicate that we got stopped out today. Later we can deceide if it should have an effect
                # Will be reset at the beginning of next day.
                $juststoppedout = $opentrade;
                $daysintrade{$dayTrade} = $numdays - $dayoftrade;
                &stopMeOut();
                $pvalue{$numtrades} = $pvalue;
                $exitp{$dayTrade} = $stop;
                printf TRADE "$day %7.2f %6.3f %3.3s %-5.5s $outpars\n", $stop{$dayTrade}, $rmult{$dayTrade}, $daysintrade{$dayTrade}, $tnote;
            }
		}
    }
    
    #
    # 6.    in case we have an exit at the end of the day (opened during day, then closed at market close)
    #
	if ($exitSig && $opentrade eq $exitSig) {
		# if an open trade exists and we get an exit signal...
		#
		$whichway = $exitSig;
        $stop = $closep;
        $daysintrade{$dayTrade} = $numdays - $dayoftrade;
        &stopMeOut();
        $pvalue{$numtrades} = $pvalue;
        $exitp{$dayTrade} = $stop;
        printf TRADE "$day %7.2f %6.3f %3.3s %-5.5s $outpars\n", $stop{$dayTrade}, $rmult{$dayTrade}, $daysintrade{$dayTrade}, $tnote;
	}
    
    #
    # 7.    Adjust stop and target at market close prices if we have an open position, except if it was opened today @close
    #
    if ( (! $intraday && $numdays - $dayoftrade > 0 && $opentrade) || ($intraday && $opentrade) ) {
        # 
        # 7.b. Check for conditions of switching stop
        #
        $sysStop = getWhichStop($day);
        if ($opt_T  &&  (  ($curprice > $targetPrice && $opentrade eq "long")  ||  ($curprice < $targetPrice && $opentrade eq "short")  )  ) {
 		    if ($direction{$dayTrade} eq "long") {
 		        $targetPrice += $targMul * $targFac;
 		    } elsif ($direction{$dayTrade} eq "short") {
 		        $targetPrice -= $targMul * $targFac;
 		    }
            printf " New target = %.2f ", $targetPrice;
		}
		$stop{$dayTrade} = getStop($sysStop, \%hday, \%dayindex, \%openp, \%maxp, \%minp, \%closep, $day, $stop{$dayTrade}, $istop{$dayTrade}, $tick, $opentrade, $inprice{$dayTrade}, $curprice, $targetPrice, $numdays - $dayoftrade, $norw);
		if ($opt_L) {   # do Local_1 stop at beginning of trade
		    $tmpstop = getStop('Local 1 0.1p',\%hday, \%dayindex, \%openp, \%maxp, \%minp, \%closep, $day, $stop{$dayTrade}, $istop{$dayTrade}, $tick, $opentrade, $inprice{$dayTrade}, $curprice, $targetPrice, $numdays - $dayoftrade, $norw);
            $tmpR = ($tmpstop-$inprice{$dayTrade})/($inprice{$dayTrade}-$istop{$dayTrade});
            if ($tmpR < $limitR && $ok2changeStop) {
                $stop{$dayTrade} = $tmpstop;
            } elsif ($tmpR > $limitR && $ok2changeStop) {   # consider change to equal $limitR instead...
                $stop{$dayTrade} = $tmpstop;
                $ok2changeStop = 0;
            }

		}
    }
    #
    # save the dates as yesterday for tomorrow...
    $yyday = $yday;
    $yday = $day;

}
###
### END of MAIN LOOP
###

#
# cancel any remaining open positions
#
if ($opentrade) {
	$pvalue += $fee1way;
	$cash += ($inprice{$dayTrade} * $possize{$dayTrade} + $fee1way);
	printf TRADE "$dayEnd %7.2f %6.3f", $inprice{$dayTrade}, 0.0; 
	print TRADE "%";
	printf TRADE " %3.3s\n", -1;  # -1 means canceled, so filter it out in subsequent analysis
	pop @dayTrade;
}

# calculate the reliability of the system for day 1, 2, 5, 10, 20
#
# random entry will give around 50% (45-55). This should be at least 55%, more is better.
#
@dum = values %daysintrade;
if (@dum > 0) {
($min, $max) = low_and_high(@dum);
my @days = ($min .. $max);
my %prof = ();
my $npdays = @days;
foreach $day (@days) {
    $prof{$day} = 0;
}
foreach $day (@dayTrade) {
	@price = getPriceAfterDays($tick, \%hday, \%dayindex, \%closep, $day, \@days);
	for ($i=0; $i < $npdays; $i++) {	
	    #print "Price on day $day + $days[$i] was $price[$i], entry at $inprice{$day} for $direction{$day} trade.\n";	
		if ( ($price[$i] - $inprice{$day} > 0 && $direction{$day} eq "long") || ($price[$i] - $inprice{$day} < 0 && $direction{$day} eq "short") ){
			# it was profitable, so we count 1
			$prof{$days[$i]}++;
		}
	}
# 	($mae0, $mpe0) = getMAE($tick, \%hday, \%dayindex, \%maxp, \%minp, $inprice{$day}, $istop{$day}, $daysintrade{$day}, $day);
# 	push @maeFull, $mae0;
# 	push @mpeFull, $mpe0; 
}
$tot = @dayTrade;
print "Reliability after ... days:\n";
print OUT "Comment: $comment\n" if ($opt_S || $opt_C);
print OUT "Reliability after ... days:\n";
foreach $day (@days) {
    $txt = sprintf("%3.3s days :: %.2f", $day, 100.0*$prof{$day}/$tot) . "% +/- " . sprintf("%.2f", 100.0*sqrt($prof{$day})/$tot) . "%\n";
	print "$txt";
	print OUT "$txt";
}
print "Comment: $comment\n" if ($opt_S || $opt_C);

# work on the R-multiples
#
$numTrades = @rMult; #print "Total # of trades = $numTrades, ";
$meanR = sum(@rMult) / $numTrades; #print "Exp = $meanR \n";
$sigma = sigma($meanR, @rMult);
if ($sigma) {
    $sq = $meanR/$sigma;
} else {
    $sq = 9.99;
}
# plot the R-distribution
# -> Rdist.png
&plotRdist();
# plot pfvalue as function of trade number for three different risk sizes
# -> Pvalue.png
# TODO:: fix the drawdown calculation based on the simulator code
#&plotPvalue();
# plot of R versus the duration of each trade. Processes MAE and MPE
# -> Rlength.png
&plotRvsLength();
# plots number of R size bins at given trade duration and the average return on trades of given length
# -> RvDays.png
&plotRvsDays();
# plots MAE vs MPE
# -> MAE.png
&plotMAE();
# plot the portfoliovalue as a function of time with the trades marked in green/red symbols
# -> Ptime.png
&plotPvsTime();
} else { print "Warning: No trades!\n"; }
# make a summary
#
# high expectancy is good, but system quality should be determining:
# < 0.17 - very hard to trade
# .17 - .20: average
# .20 - .29: good
# .30 - .49: excellent
# .50 - .69: superb
# .70+ : Holy Grail
# Experimenting with different goodness-of-test measures, based on Kaufman:
#   f = (1 - DDmax% / 100) * <R> * SQ * sqrt(N)
#   Last bit is actually t-value for <R> since t_R = <R>/sig(R) * sqrt(N) = SQ*sqrt(N)
if ($nneg > 0) {
    $rewrisk = ($npos * $meanpos) / abs($nneg * $meanneg);
} else {
    $rewrisk = 99.9;
}
#$good1 = (1.0 - $maxdd)**2 * $meanR * $sq * $rewrisk * sqrt($numTrades);   # putting more emphasis on drawdowns
$good1 = 1.0 - $maxdd;  # drawdown expressed as a positive fraction...
if ($maxdd > 0.0) {
    $good2 = (($phigh-$cash0)/$cash0)/$maxdd;   # ratio gains peak to max drawdown
} else {
    $good2 = 99.9;
}
# check the distribution of wins and losses
$actualSum = 0;
for ($i = 0; $i<$numTrades-1; $i++) {
    if ($rMult[$i] > 0) {
        if ($rMult[$i+1] > 0) {
            $actualSum++;
        }
    }
}
$probNextIsWin = $actualSum*1.0/$npos;
printf "Probability of next trade being a win; actual = %.3f, theoretical = %.3f\n",$probNextIsWin,$npos*1.0/$numTrades;
printf "Buy and hold values: fully invested = %.2f; risk frac invested = %.2f\n", $resBHfull, $resBHrisk;
printf OUT "Buy and hold values: fully invested = %.2f; risk frac invested = %.2f\n", $resBHfull, $resBHrisk;
print "System = $system, Initial stop method = $sysInitStop, Exit/Stop = $sysStop\n";
print OUT "System = $system, Initial stop method = $sysInitStop, Exit/Stop = $sysStop\n";
printf "System result:\n\tPortfolio value at end   = %.2f from $numTrades trades in $numdays trading days.\n", $pvalue;
printf OUT "System result:\n\tPortfolio value at end   = %.2f from $numTrades trades in $numdays trading days.\n", $pvalue;
$txt = sprintf("\tExpectancy = %.2f+/-%.2f, System Quality = %.2f, Max drawdown = %.2f", $meanR, $sigma, $sq, $maxdd*100.0) . 
        "%." . sprintf(" Longest losing streak = %1d trades. Good1 = %.3f, Good2 = %.2f\n", $lloser, ${good1}, ${good2});
print "$txt";   print OUT "$txt";
printf "\tW/L = %d/%d, W/L-ratio = %d/%d. <R_pos> = %.2f +/- %.2f, <R_neg> = %.2f +/- %.2f, R/R = %.2f\n",
    $npos, $nneg, int(100*$npos/$numTrades), 100-int(100*$npos/$numTrades), $meanpos, $sigpos, $meanneg, $signeg, $rewrisk;
printf OUT "\tW/L = %d/%d, W/L-ratio = %d/%d. <R_pos> = %.2f +/- %.2f, <R_neg> = %.2f +/- %.2f, R/R = %.2f\n",
    $npos, $nneg, int(100*$npos/$numTrades), 100-int(100*$npos/$numTrades), $meanpos, $sigpos, $meanneg, $signeg, $rewrisk;
printf "\tOpportunity = %.3f trades/day. Expected profit per day = %.3fR\n", $numTrades/$numdays, $meanR * $numTrades/$numdays;
printf OUT "\tOpportunity = %.3f trades/day. Expected profit per day = %.3fR\n", $numTrades/$numdays, $meanR * $numTrades/$numdays;
printf "\tProjected profit per... Week = %.3fR. Month = %.3fR.\n", 5*$meanR * $numTrades/$numdays, 21.0*$meanR * $numTrades/$numdays;
printf OUT "\tProjected profit per... Week = %.3fR. Month = %.3fR.\n", 5*$meanR * $numTrades/$numdays, 21.0*$meanR * $numTrades/$numdays;
printf OUT "toread: %.2f \t%.2f\t%.2f\t%d\t%d\t%d\t%d\t%.2f\t%.2f\t%.3f\t%.3f\t%.2f\t%.3f\t%.2f\n", 
    $pvalue, $meanR, $sq, $npos, $nneg, $numTrades, $numdays, $meanpos, $meanneg, 
    $rewrisk, $numTrades/$numdays, $meanR * $numTrades * 21/$numdays, ${good1}, ${good2};
close OUT;
close TRADE;
print "done! stamp = $unique\n";

#########################
#####   END   ###########


sub stopMeOut {
    # exit the trade and get the gain. Correct for slippage and comissions
    my ($v1, $v2, $rangeAll, @idx, @hdtmp, $mm1, $mm2, @vals, $targetPrice, $mae, %ex, $rsi);
    my $nthi = 0.0; my $ntlo = 0.0;
    $gain = exitTrade($direction{$dayTrade}, $inprice{$dayTrade}, $possize{$dayTrade}, $stop);
#    $gain -= $slip*$possize{$dayTrade};
    printf "Warning; gap or slippage; should have been %.2f but was %.2f -- ",$stop{$dayTrade},$stop unless ($stop{$dayTrade} == $stop || $exitSig);
    $rmult{$dayTrade} = ($gain)/$risk;  # R-multiple is not taking into account the fees, only slippage
    push @rMult, $rmult{$dayTrade};
    $cash += ($gain + $inprice{$dayTrade} * $possize{$dayTrade} - $fee1way);
    $pvalue += ($gain - $fee1way);
    if ($gain > 0) {
        $nloser = 0;
    } else {
        $nloser++;
    }
    if ($nloser > $lloser) {
        $lloser = $nloser;
    }
    if ($pvalue > $phigh) {
        if ($opt_R) {
            $riskP = $riskPinit * (1.0 + ($pvalue-$phigh)/$phigh);  # increase % if in a winning streak
            $riskP = $riskMax if $riskP > $riskMax;
        }
        $phigh = $pvalue;
        $dd = 0.0;
    } else { 
        # adjust the riskp if we've chosen to do so: Relate to current drawdown:  riskFactor = (100 - 2*DD%)/100 if in a DD.
        if ($opt_R) {
            $riskP = $riskPinit * (1.0 - 2*$dd);
            #print " ==== risk% = "; printf "%.2f ==== ", $riskP*100;
        }
    }
    if (($phigh - $pvalue)/$phigh > $dd) {
        $dd = ($phigh - $pvalue)/$phigh;
    }
    if ($dd > $maxdd) {
        $maxdd = $dd;
    }
    $outpars = "";  # can insert some indicator value for the output file
    if ($opt_k) {
        # $opt_k was kkper:ssper if there is no SMA-filter, kperi is extracted from the strategy name
        #
        #  others to consider:  MACD-params, delta-MACD/sigmaptpt(MACD), Volume/<Volume>, OBV
        #
        if ($intraday) {
            $dy0 = $hday{$dayindex{$dayTrade}-1};
            $dy1 = $hday{$dayindex{$dayTrade}-2};
        } else {
            $dy0 = $dayTrade;
            $dy1 = $hday{$dayindex{$dayTrade}-1};
        }
        # 10. val; MAE
        if ($opentrade eq 'long') {
            $mae = ($inprice{$dayTrade} - $minp{$hday{$dayindex{$dayTrade}+1}});
            %ex = %minp;
        } elsif ($opentrade eq 'short') {
            $mae = ($maxp{$hday{$dayindex{$dayTrade}+1}} - $inprice{$dayTrade});
            %ex = %maxp;
        }
        $mae = 0.0 if $mae < 0;
        for ($j = 2; $j <= $daysintrade{$dayTrade}; $j++) {
            if ($opentrade eq 'long') {
                if ($mae < $inprice{$dayTrade} - $ex{$hday{$dayindex{$dayTrade}+$j}}) {
                    $mae = $inprice{$dayTrade} - $ex{$hday{$dayindex{$dayTrade}+$j}};
                }
            } elsif ($opentrade eq 'short') {
                if ($mae < $ex{$hday{$dayindex{$dayTrade}+$j}} - $inprice{$dayTrade}) {
                    $mae = $ex{$hday{$dayindex{$dayTrade}+$j}} - $inprice{$dayTrade};
                }
            }
        }
        $v2 = kso(\%hday, \%dayindex, \%maxp, \%minp, \%closep, $kkper, $dy0);
        $v1 = kso(\%hday, \%dayindex, \%maxp, \%minp, \%closep, $kkper, $dy1);
        $adx0 = $v2 - $v1;  # 1. value: KSO slope
        $kso0 = $v2;
        $dc = abs($closep{$dy0} - $closep{$dy1});
        $tr = atr($tick, \%hday, \%dayindex, \%maxp, \%minp, \%closep, $kperi, $dy0);
        $tr1 = atr($tick, \%hday, \%dayindex, \%maxp, \%minp, \%closep, $kperi, $dy1);
        $datr = ($tr - $tr1)/$tr;   # 4. val: normalized slope of ATR
        $tr2 = atr($tick, \%hday, \%dayindex, \%maxp, \%minp, \%closep, $kperi*10, $dy0);
        $ratr = $tr/$tr2;   # 5. val: ATR self-normalized (a10/a100)
        if ($system =~ /AllTime.{1}(\d+)/) {
            #find size of the range of the last N days
            $rangeAll = $1;
            @idx = ($dayindex{$dayTrade}-$rangeAll .. $dayindex{$dayTrade}-1);
            @hdtmp = @hday{@idx};
            @vals = @closep{@hdtmp};
            ($mm1,$mm2) = low_and_high(@vals);
            $targetPrice = ($mm2-$mm1)/$mm2;    # 2. val: fractional size of N-day range
            $d1 = ($mm2-$mm1)/$closep{$dayTrade}; # 7. val: range in relation to current price
            for ($i = $dayindex{$dayTrade}-$rangeAll; $i <= $dayindex{$dayTrade}-1; $i++) {
                # calc the number of touches in the interval
                #print "calc on $hday{$i}: ";
                $val = 2*$maxp{$hday{$i}}/($mm2-$mm1) + (1.0 - 2*$mm2/($mm2-$mm1));
                #printf "val(hi) = %.2f ", $val;
                $val = 1.0 if $val > 1.0;
                $val = 0.0 if $val < 0.6;
                #printf "-> %.2f, ", $val;
                $nthi += $val**3;
                $val = 2*$minp{$hday{$i}}/($mm2-$mm1) + (1.0 - 2*$mm2/($mm2-$mm1));
                #printf "val(lo) = %.2f ", $val;
                $val = -1.0 if $val < -1.0;
                $val = 0.0 if $val > -0.6;
                #printf "-> %.2f\n", $val;
                $ntlo += abs($val**3);
            }
            #printf "summed up: %.4f  %.4f\n", $nthi, $ntlo; exit;
            $nthi = $nthi*100.0/$rangeAll;  # 8. val; number of upper touches
            $ntlo = $ntlo*100.0/$rangeAll;  # 9. val; number of lower touches
        } elsif ($system =~ /InsideDay/ || $system =~ /^Vol/) {
            if ($intraday) {
                $dc = $openp{$dayTrade} - $closep{$dy0};    # (using the close-open span if $intraday)
            }
            $targetPrice = $dc * 100.0 / $tr;    # 2. val: percentage move in units of the ATR
            $d1 = 100*$dc/$closep{$dy0};  # 7. val: percentage price move 
            $nthi = 0.0; $ntlo = 0.0;
        } elsif ($system =~ /Spike/) {
            $targetPrice = ($maxp{$dy0}-$minp{$dy0})/$tr;   # 2.val: daily range in units of the ATR
            @my = ($closep{$dy0}, $openp{$dy0});
            ($min,$max) = low_and_high(@my);
            if ($opentrade eq 'long') {
                $d1 = ($min - $minp{$dy0})/($maxp{$dy0}-$minp{$dy0});   # 7.val: spikewick/daily range [>0.5 is the defining crit]
                $nthi = ($maxp{$dy0} - $max)/($min - $minp{$dy0});
                $ntlo = ($max-$min)/($min - $minp{$dy0});
#                $ntlo = ($maxp{$dy0}-$min)/($min - $minp{$dy0});
            } else {
                $d1 = ($maxp{$dy0} - $max)/($maxp{$dy0}-$minp{$dy0});
                $nthi = ($min-$minp{$dy0})/($maxp{$dy0} - $max); # 8.val; smallwick/spikewick
                $ntlo = ($max-$min)/($maxp{$dy0} - $max); # 9.val; body/spikewick
#                $ntlo = ($max-$minp{$dy0})/($maxp{$dy0} - $max); # 9.val; (body+smallwick)/spikewick
            }
        } else {
            $targetPrice = $dc * 100.0 / $tr;    # 2. val: percentage move in units of the ATR
            $d1 = 0.0;
            $nthi = 0.0; $ntlo = 0.0;
        }
        $v2 = sma($tick, \%hday, \%dayindex, \%closep, $ssper, $dy0);
        $v1 = sma($tick, \%hday, \%dayindex, \%closep, $ssper, $dy1);
        # 3. value: SMA slope
#        $svalx = $ssper * ($v2 - $v1) / (10 * atr($tick, \%hday, \%dayindex, \%maxp, \%minp, \%closep, 14, $dayTrade) ); 
        $svalx = $ssper**.5 * ($v2 - $v1)/$v2; #printf "SMA today($dy0) = %.3f, yd($dy1) = %.3f. ssper = $ssper\n", $v2, $v1; exit;
        $v2 = sma($tick, \%hday, \%dayindex, \%volume, 14, $dy0);
        if ($v2 >0.0) {
            $v1 = $volume{$dy0}/$v2;   # 6. val: relative volume vol/<vol>
        } else {
            $v1 = 0.0;
        }
        $rsi = rsi($tick, \%hday, \%dayindex, \%closep, 9, $dayTrade);  # 11.val: RSI(9)
        $outpars = sprintf "%.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f", 
                    $adx0, $targetPrice, $svalx, $datr, $ratr, $v1, $d1, $nthi, 
                    $ntlo, $mae/abs($istop{$dayTrade}-$inprice{$dayTrade}), $rsi, $kso0;
    }
    printf " exit at R = %.2f ", $rmult{$dayTrade};
    # pushing the plotting arrays
    ($sym, $col) = populatePlotArrays($rmult{$dayTrade});
    $sym{$dayTrade} = $sym;
    push @sym, $sym;
    $col{$dayTrade} = $col;
    push @col, $col;
    unless ($opt_n) {
        $nd = $daysintrade{$dayTrade} + 1; 
#        $nd = $daysintrade + 1;
        while (1) {
            if (exists $hday{$dayindex{$dayTrade}+$nd+$xafter}) {
                last;
            } else {
                $xafter--;
            }
        }
        if ($xafter > 0) {
            for ($i = 0; $i < $xafter; $i++) {
                push @high, $maxp{$hday{$dayindex{$dayTrade}+$nd+$i}};
                push @low, $minp{$hday{$dayindex{$dayTrade}+$nd+$i}};
                push @open, $openp{$hday{$dayindex{$dayTrade}+$nd+$i}};
                push @yy, $closep{$hday{$dayindex{$dayTrade}+$nd+$i}};
                push @xx, $dayindex{$dayTrade}+$nd+$i;
            }
        }
        &plotTrade();
    }
    $opentrade = "";
}

sub plotTrade {
    # not using strict; sharing variables with main program
    my ($whenVB);
    my $font = 2;
    my $linewidth = 2;
    my $charheight = 1.2;
    pgbeg(0,$device,1,1); # || warn "pgbeg on $device says: $!\n"; # Open plot device 
    pgscr(0,1.0,1.0,1.0); # set background = white
    pgscr(1,0.0,0.0,0.0); # set foreground = black
    pgscf($font); # Set character font 
    pgslw($linewidth); # Set line width 
    pgsch($charheight); # Set character height 
    pgsci(1);  # default colour
    my $symbol = 17;
    my $nume = @xx; 
    if ($nume < 2) {
        warn "bad: only $nume points in array...\n";
        pgend;
        return;
    }
    my $nums = @xs;        #for ($ii=0; $ii<$nums; $ii++) {printf "$ii: %.2f %.2f\n",$xs[$ii],$ss[$ii]; }; exit;
    my @all = (@yy, @ss, @addall, @low, @high);
    my ($yplot_low, $yplot_hig) = low_and_high(@all); 
    my ($xplot_low, $xplot_hig) = low_and_high(@xx);
    my $mean = ( $xplot_hig - $xplot_low ) * 0.02;
    $xplot_hig += $mean;
    $xplot_low -= $mean;
    $mean = ( $yplot_hig - $yplot_low ) * 0.05;
    $yplot_hig += $mean;  $yplot_hig = sprintf "%.2f", $yplot_hig;
    $yplot_low -= $mean;  $yplot_low = sprintf "%.2f", $yplot_low; 
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, 0);# || warn "pgenv here says: $!\n";
    pglabel("Day of trade", "Price", "$tick - $dayTrade");
    my $text = sprintf "R = %.2f", $gain/$risk;
    pgmtext('B', -1.0, 0.3, 0, "$text");
    if ($pltext) {
        pgsci(11);
        pgsch($charheight*0.7); # Set character height 
        pgmtext('T', -1.1, 0.02, 0, "$pltext");
        pgsci(1);  # default colour
    }
    pgsch(0.8); pgsci(14);
    my $mytxt0 = $sysStop;
    $mytxt0 .= " -T$opt_T" if ($opt_T);
    pgmtext('T', 2.1, 0.98, 1, "$system, $sysInitStop"); # lower right corner
    pgmtext('T', 1.0, 0.98, 1, "$mytxt0"); # lower right corner
    pgslw(1); # Set line width 
    # mark entry and exit dates
    pgsci(14);
    pgsls(4);
    pgline(2, [$xs[0],$xs[0]], [$yplot_low,$yplot_hig]);
    pgline(2, [$xs[-1],$xs[-1]], [$yplot_low,$yplot_hig]);
    pgsci(1);  # default colour
    pgsls(1);
    my $candlew = 0.31; # old: int(300.0 / $nume / 2.0) + 1;
    pgsfs(1); # fill is true
    for ($i = 0; $i < $nume; $i++) {
        pgsci(14);                          # color 15 = light gray
        pgslw(2); # Set line width 
        pgline(2, [$xx[$i],$xx[$i]], [$low[$i],$high[$i]]);
        if ($open[$i] > $yy[$i]) {
#            pgsci(2); # red
            pgsci(1); # down day
        } else {
#            pgsci(3); # green
            pgsci(0); # up day
        }
        pgslw(1); # Set line width 
        pgrect($xx[$i]-$candlew, $xx[$i]+$candlew, $open[$i], $yy[$i]); 
    }
    # plot the stop level 
    pgsci(14);                            # color 15 = light gray
    pgslw($linewidth);
    pgline($nums,\@xs,\@ss);                   # plot the stop
    if ($intraday) {
        pgsci(6);                            # color 6 = pink
        pgsls(4);
        if ($system =~ /VolB([CO])/) {
            $whenVB = $1;
            if ($whenVB eq "O") {
                $myin = $openp{$dayTrade};
            } elsif ($whenVB eq "C") {
                $myin = $closep{$hday{$dayindex{$dayTrade}-1}};
            } else {
                $myin = "";
            }
            die "no value in $whenVB\n" unless $myin;
            pgline(2, [$xs[0]-0.9,$xs[0]+0.3], [$myin+$vbfac*$tr,$myin+$vbfac*$tr]);
            pgline(2, [$xs[0]-0.3,$xs[0]+0.9], [$myin-$vbfac*$tr,$myin-$vbfac*$tr]);
        }
    }
    if ($maBlue && $maGreen) {
        pgslw(1); # Set line width 
        pgsls(1);
        @maBlue = (); @maGreen = ();
        # ($dum, $maxi) = low_and_high(@xs);
        @xsma = ($xx[0]-1 .. int($xplot_hig)); # $maxi+1); #-1);
        $ntest = @xsma; 
        for ($i = 0; $i < $ntest; $i++) {
            $sday = $hday{$xsma[$i]};
            if ($opt_e) {
                push @maGreen, ema($tick, \%hday, \%dayindex, \%closep, $maGreen, $sday);
                push @maBlue, ema($tick, \%hday, \%dayindex, \%closep, $maBlue, $sday);
            } elsif ($opt_s) {
                push @maGreen, sma($tick, \%hday, \%dayindex, \%closep, $maGreen, $sday);
                push @maBlue, sma($tick, \%hday, \%dayindex, \%closep, $maBlue, $sday);
            }
        }
        $nma = @maBlue;  #print "SMA$maGreen $nma ($ntest) points from $xsma[0] to $xsma[-1] ($maGreen[0] to $maGreen[-1])...";
        pgsci(10); # green
        pgline($nma, \@xsma, \@maGreen);
        pgmtext('RV', 0.2, 0.5, 0, "SMA${maGreen}");
        pgsci(4); # blue
        pgline($nma, \@xsma, \@maBlue);
        pgmtext('RV', 0.2, 0.4, 0, "SMA${maBlue}");
        pgslw($linewidth);
    }
    if ($swfiltfac || $setupcond =~ /HiLo/) {
        $m1 = -1; $p1 = 1;  $hl1 = 0;
        %swcol = (); %swsym = ();    
        $swcol{$m1} = 2; $swsym{$m1} = 31; $swcol{$p1} = 3; $swsym{$p1} = 30; $swcol{$hl1} = 11; $swsym{$hl1} = 2;
        $xtmp = int($xplot_low); 
        if ($xtmp < $dayindex{$dayBegin}) {
            $xtmp = $dayindex{$dayBegin};
        }
        @xxx = ($xtmp .. int($xplot_hig)); #$xs[-1]-1);
        foreach $xxx (@xxx) {
            $swd = ($trendh{$hday{$xxx}}+$trendl{$hday{$xxx}})/2;
#            pgsci($swcol{$swdir{$hday{$xxx}}});
#            pgpoint(1, [$xxx], [$yplot_hig], $swsym{$swdir{$hday{$xxx}}});
            pgsci($swcol{$swd});
            pgpoint(1, [$xxx], [$yplot_hig], $swsym{$swd});
        }
    }
    if ($setupcond =~ /HiLo/) {
        $offst = ($yplot_hig-$yplot_low)*0.02;  # offset from upper edge
        foreach $xxx (@xxx) {
            if ($trendh{$hday{$xxx}} == -1) {
                $swct = 2;  # red
            } elsif ($trendh{$hday{$xxx}} == 1) {
                $swct = 3;  # green
            } else { $swct = 7; }  # yellow, meaning values were not defined
            pgsci($swct);
            pgpoint(1, [$xxx], [$yplot_hig-1.0*$offst], 16);
            if ($trendl{$hday{$xxx}} == -1) {
                $swct = 2;  # red
            } elsif ($trendl{$hday{$xxx}} == 1) {
                $swct = 3;  # green
            } else { $swct = 7; }  # yellow, meaning values were not defined
            pgsci($swct);
            pgpoint(1, [$xxx], [$yplot_hig-2.0*$offst], 16);
        }
        $nhilo = @hilo;
        for ($i = 0; $i < $nhilo; $i++) {
            next if ($datehl[$i] lt $hday{int($xplot_low)} || $datehl[$i] gt $hday{int($xplot_hig)});
            pgsci(8);
            if ($ishigh[$i]) {
                $symhl = 30;
            } else {
                $symhl = 31;
            }
            pgpoint(1, [$dayindex{$datehl[$i]}], $hilo[$i], $symhl);
        }
    }
    pgsci(11); # light blue
    pgsls(1);
    pgline(2, [$xs[0]-0.5,$xs[0]+0.5], [$inprice{$dayTrade},$inprice{$dayTrade}]);  # entry level 
    pgsci(11); # light blue
    pgline(2, [$xs[-1]-0.5,$xs[-1]+0.5], [$stop,$stop]);
    pgsci(12);
    pgpoint(1, [$xs[0]], [$ss[0]], 29);    
#    pgslw(3); pgsci(8);
#    pgline(2, \@xfit, \@yfit);  # the linear fit; not implemented
    pgend; # || warn "pgend on $device says: $!\n";
    return;
}

sub plotRdist {
    # not using strict; sharing variables with main program
    my ($xr, $r, $device, @yr, $numx, $i);
    my ($min, $max) = low_and_high(@rMult);
    $min = int($min) - 1;
    $max = int($max) + 1;
    my @xr = ($min .. $max);
    my %count = ();
    if ($opt_p) {
        $device = "${btdir}plot_${tick}_${unique}_Rdist.png/PNG";
    } else {
        $device = "/XSERVE";
    }
    my $font = 2;
    my $linewidth = 2;
    my $charheight = 1.2;
    pgbeg(0,$device,1,1); # || warn "pgbeg on $device says: $!\n"; # Open plot device 
    pgscr(0,1.0,1.0,1.0); # set background = white
    pgscr(1,0.0,0.0,0.0); # set foreground = black
    pgscf($font); # Set character font 
    pgslw($linewidth); # Set line width 
    pgsch($charheight); # Set character height 
    pgsci(1);  # default colour
    RMUL:foreach $r (@rMult) {
        if ($r > 0.0) {
            push @rpos, $r;
        } else {
            push @rneg, $r;
        }
        foreach $xr (@xr) {
            if ($r >= $xr && $r < $xr+1.0) {
                $count{$xr}++;  next RMUL;
            } elsif ($r >= $xr[-1]+1.0) {
                $count{$xr[-1]}++;  next RMUL;
            } elsif ($r < $xr[0]) {
                $count{$xr[0]}++;  next RMUL;
            }
        }
    }
    $npos = @rpos;  $nneg = @rneg;
    if ($npos) {
        $meanpos = sum(@rpos)/$npos;
        $sigpos = sigma($meanpos,@rpos);
    } else {
        $meanpos = 0.0; $sigpos = 0.0;
    }
    if ($nneg) {
        $meanneg = sum(@rneg)/$nneg;
        $signeg = sigma($meanneg,@rneg);
    } else {
        $meanneg = 0.0; $signeg = 0.0;
    }
    @yr = values %count;
    @xr = keys %count;
    $numx = @xr;
    @yr = div_array(\@yr, $numTrades);
    my ($yplot_low, $yplot_hig) = low_and_high(@yr); 
    my ($xplot_low, $xplot_hig) = low_and_high(@xr);
    $xplot_low--; $xplot_hig += 1.5;
    my $mean = ( $yplot_hig - $yplot_low ) * 0.05;
    $yplot_hig += $mean;
    pgenv($xplot_low, $xplot_hig, 0.0, $yplot_hig, 0, 0); # || warn "pgenv-plotRdist says $!\n";
    my $txt = sprintf "<R> = %.2f", $meanR; 
    my $ytxt = "N = $numTrades";
    pglabel("$txt", "$ytxt", "$tick - $unique");
    pgslw(1);
    pgsci(12);
    pgsfs(1); # fill is true
    for ($i = 0; $i < $numx; $i++) {
        if ($yr[$i] > 0) {
            pgrect($xr[$i]+0.1, $xr[$i]+0.9, 0.0, $yr[$i]);
        }
    }
    # mark the mean-R
    pgsci(15);
    pgsls(2);
    pgline(2, [$meanR,$meanR], [$yplot_low,$yplot_hig]);
    pgslw($linewidth);
    pgsci(1);
    pgsls(1);
    pgsch(0.8);
    my $xtxt = sprintf("Exp = %.2f+/-%.2f, SQ = %.2f, MaxDD = %.1f", $meanR, $sigma, $sq, $maxdd*100.0) . "%";
    pgmtext('T', -2.1, 0.98, 1, "$system, $sysInitStop, $sysStop"); # lower right corner
    pgmtext('T', -1.0, 0.98, 1, "$xtxt"); # lower right corner
    pgmtext('T', 1.0, 0.98, 1, "$comment") if ($opt_S || $opt_C); # comment in upper right corner
    sleep 2 unless ($opt_p);
    pgend;
}

sub plotRvsLength {
    # not using strict; sharing variables with main program
    my ($i, $d, $device, $mean);
    my @data;
    if ($opt_p) {
        $device = "${btdir}plot_${tick}_${unique}_Rlength.png/PNG";
    } else {
        $device = "/XSERVE";
    }
    my $font = 2;
    my $linewidth = 2;
    my $charheight = 1.2;
    pgbeg(0,$device,1,1); # || warn "pgbeg on $device says: $!\n"; # Open plot device 
    pgscr(0,1.0,1.0,1.0); # set background = white
    pgscr(1,0.0,0.0,0.0); # set foreground = black
    pgscf($font); # Set character font 
    pgslw($linewidth); # Set line width 
    pgsch($charheight); # Set character height 
    pgsci(1);  # default colour
    my @phl = ();
    my @xd = ();  my @yr = ();
    foreach $i (keys %rmult) {
        push @xd, $daysintrade{$i};
        push @yr, $rmult{$i};
    }
    my $symbol = 19;
    my $numx = @xd;
    ($yplot_low, $yplot_hig) = low_and_high(@yr); 
    ($xplot_low, $xplot_hig) = low_and_high(@xd);
    $xplot_low=0; $xplot_hig++;
    $mean = ( $yplot_hig - $yplot_low ) * 0.05;
    $yplot_hig += $yplot_hig*0.20;  # assume 20% retracement from the highest high of the most profitable trade in sample
    $yplot_hig += $mean; $yplot_low -= $mean;
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, 0);
    my $xtxt = "# days in trade"; 
    pglabel("$xtxt", "R", "$tick - $unique");
    pg_plot_horizontal_line(0.0, 4, 15);  # zero-line
    pgsls(2);
    pgslw(1); # Set line width 
    $avehold = 0; $maxhold = 0; $minhold = 3000;
    $aveholdp = 0; $maxholdp = 0; $minholdp = 3000; $numprof = 0;
    open R, ">${btdir}crit_${tick}_${unique}.txt" or die "error 82864\n";
    open MAE, ">${btdir}adv_${tick}_${unique}.txt" or die "error nas39r2js;a3"; # Max adverse excursion; max negative before turning positive
    open MPE, ">${btdir}mpe_${tick}_${unique}.txt" or die "error ss495734"; # Max positive excursion of a trade that eventually turns out negative
    open DELR, ">${btdir}delr_${tick}_${unique}.txt" or die "error del03842jsa6723"; # max retracement for positives
    my $xmax = max(values %daysintrade);
    foreach $i (@dayTrade) {
        $avehold += $daysintrade{$i};
        if ($rmult{$i} > 0.0) {
            $aveholdp += $daysintrade{$i};
            $maxholdp = $daysintrade{$i} if ($daysintrade{$i} > $maxholdp);
            $minholdp = $daysintrade{$i} if ($daysintrade{$i} < $minholdp);
            $numprof++;
        }
        $maxhold = $daysintrade{$i} if ($daysintrade{$i} > $maxhold);
        $minhold = $daysintrade{$i} if ($daysintrade{$i} < $minhold);
        $posRs = 0; $negRs = 0;
        $maxR = 0.0;  $minR = 0.0;  $maxAE = 0.0; $maxPE = 0.0;
        $relAE = 0.0;  $relPE = 0.0;
        @data = ();  @low_tmp = (); @high_tmp = ();
        for ($j = 0; $j <= $xmax; $j++) {
#        for ($j = 0; $j <= $daysintrade{$i}; $j++) {
            push @data, $closep{$hday{$dayindex{$i}+$j}};
            push @high_tmp, $maxp{$hday{$dayindex{$i}+$j}};
            push @low_tmp, $minp{$hday{$dayindex{$i}+$j}};
        }
		if ($direction{$i} eq "long") {
		    @phl = @low_tmp;
		    @pmpe = @high_tmp;
		} elsif ($direction{$i} eq "short") {
		    @phl = @high_tmp;
		    @pmpe = @low_tmp;
		} else {
		    print "WARNING:  direction not fund...\n";
		}
        for ($j = 0; $j <= $xmax; $j++) {
#		for ($j=0; $j<=$daysintrade{$i}; $j++) {
		    $ylin[$j] = (($data[$j]-$inprice{$i})*$possize{$i}-2*$fee1way)/(($inprice{$i}-$istop{$i})*$possize{$i}); #print "day=$data2[$j], x=$xlin[$j], ylin = $ylin[$j]\n";
            $rFromX = (($phl[$j]-$inprice{$i})*$possize{$i}-2*$fee1way)/(($inprice{$i}-$istop{$i})*$possize{$i});
            $r4mpe = (($pmpe[$j]-$inprice{$i})*$possize{$i}-2*$fee1way)/(($inprice{$i}-$istop{$i})*$possize{$i});
            if ($ylin[$j] > 0.01 && $j >= 1 && $j <= $daysintrade{$i}) {
                $posRs++;
                $maxR = $ylin[$j] if ($ylin[$j] > $maxR && $j < $daysintrade{$i});
            } elsif ($ylin[$j] < -0.01 && $j >= 1 && $j <= $daysintrade{$i}) {
                $negRs++;
                $minR = $ylin[$j] if ($ylin[$j] < $minR && $j < $daysintrade{$i});
            } elsif ($j == 0 && $intraday) {
                $maxAE = $rFromX;   $relAE = $rFromX;   # or should rather be based on close price?
                $maxPE = $r4mpe;    $relPE = $r4mpe;
            }
            if ($rFromX < -0.001 && $j >= 1) {
                $maxAE = $rFromX if ($rFromX < $maxAE && $j < $daysintrade{$i});  ### <= or < btw $j and $daysintrade{$i}
                $relAE = $rFromX if ($rFromX < $relAE);
            }
            if ($r4mpe > 0.001 && $j >= 1) {
                $maxPE = $r4mpe if ($r4mpe > $maxPE && $j < $daysintrade{$i});
                $relPE = $r4mpe if ($r4mpe > $relPE);
            }
		}
		$maxPE{$i} = $maxPE;    $maxAE{$i} = $maxAE;
		$relPE{$i} = $relPE;    $relAE{$i} = $relAE;
		if ($rmult{$i} > 0.0) {
		    if ($negRs > 0) {
    		    pgsci(11); # blue
    		    if ($daysintrade{$i} > 1) {
                    printf R "$i: $daysintrade{$i} days; $negRs days negative (min. %.2fR), ends in %.2fR\n", $minR, $rmult{$i};
                    printf MAE "$i  $daysintrade{$i}  $negRs  %.3f  %.3f\n", $maxAE, $rmult{$i};
                }
		    } else {
		        pgsci(3);  # green
    		}
    		printf DELR "$i  $daysintrade{$i}  %.3f  %.3f  %.3f\n", $rmult{$i}, $maxR, $maxR-$rmult{$i};
		} else {
		    if ($posRs > 0) {
		        pgsci(8);  # orange
    		    if ($daysintrade{$i} > 1) {
                    printf R "$i: $daysintrade{$i} days; $posRs days positive (max. %.2fR), ends in %.2fR\n", $maxR, $rmult{$i};
                    printf MPE "$i  $daysintrade{$i}  $posRs  %.3f  %.3f\n", $maxPE, $rmult{$i};
                }
		    } else {
		        pgsci(2);  # red
		    }
		} 
#		$nny = @ylin; $nnx = @xlin; #print "nx = $nnx, ny = $nny - days in trade = $daysintrade{$i}\n";
        @xlin = (0 .. $daysintrade{$i});       # original
		$ylin[$daysintrade{$i}] = $rmult{$i};   # original line
		pgline($daysintrade{$i}+1, \@xlin, \@ylin); # original line
#        $ylin[$daysintrade{$i}] = (($data[$daysintrade{$i}]-$inprice{$i})*$possize{$i}-2*$fee1way)/(($inprice{$i}-$istop{$i})*$possize{$i});
#        push @ylin, $rmult{$i};
#        push @xlin, $daysintrade{$i};
#        pgline($daysintrade{$i}+2, \@xlin, \@ylin);
    }
    close R;
    close MAE;
    close MPE;
    close DELR;
    $avehold /= $numx;
    $aveholdp /= $numprof;
    $win = int( $numprof *100.0 / $numx);
    $loss = 100 - $win;
    printf "Holding times\tN\tAverage\tmax\tmin\n";
    printf "-all trades  \t$numx\t%.1f\t$maxhold\t$minhold\n", $avehold;
    printf "-profitables \t$numprof\t%.1f\t$maxholdp\t$minholdp\n", $aveholdp;
    print "Win/Loss = $win/$loss\n";
    printf OUT "Holding times\tN\tAverage\tmax\tmin\n";
    printf OUT "-all trades  \t$numx\t%.1f\t$maxhold\t$minhold\n", $avehold;
    printf OUT "-profitables \t$numprof\t%.1f\t$maxholdp\t$minholdp\n", $aveholdp;
    print OUT "Win/Loss = $win/$loss\n";
    pgslw($linewidth); # Set line width 
    pgsch(0.8); pgsci(15);
    $xtxt = sprintf("Exp = %.2f+/-%.2f, SQ = %.2f, MaxDD = %.1f", $meanR, $sigma, $sq, $maxdd*100.0) . "%";
    pgmtext('B', -2.1, 0.98, 1, "$system, $sysInitStop, $sysStop"); # lower right corner
    pgmtext('B', -1.0, 0.98, 1, "$xtxt"); # lower right corner
    pgsci(12);
    pgpoint($numx, \@xd, \@yr, $symbol);
    pgmtext('T', 1.0, 0.98, 1, "$comment") if ($opt_S || $opt_C); # comment in upper right corner
    pgend;
    sleep 2 unless ($opt_p);
}

sub plotRvsDays {
    # not using strict; sharing variables with main program
    my ($i, $d, $device);
    my @data;
    if ($opt_p) {
        $device = "${btdir}plot_${tick}_${unique}_RvDays.png/PNG";
    } else {
        $device = "/XSERVE";
    }
    my $font = 2;
    my $linewidth = 2;
    my $charheight = 1.2;
    pgbeg(0,$device,1,1); # || warn "pgbeg on $device says: $!\n"; # Open plot device 
    pgscr(0,1.0,1.0,1.0); # set background = white
    pgscr(1,0.0,0.0,0.0); # set foreground = black
    pgscf($font); # Set character font 
    pgslw($linewidth); # Set line width 
    pgsch($charheight); # Set character height 
    pgsci(1);  # default colour
    my @xd = sort { $a <=> $b } values %daysintrade;
    my @ny = (); my @rmean = ();
    foreach $d (@xd) {
        $rm = 0.0; $n = 0;
        foreach $i (keys %rmult) {
            if ($daysintrade{$i} == $d) {
                $rm += $rmult{$i};
                $n++;
            }
        }
        push @ny, $n;
        push @rmean, $rm/$n;
    }
    my $symbol = 11;
    my $numx = @xd;
    my ($nmin, $nmax) = low_and_high(@ny);
    ($yplot_low, $yplot_hig) = low_and_high(@rmean); 
    ($xplot_low, $xplot_hig) = low_and_high(@xd);
    $xplot_low=0; $xplot_hig++;
    my $mean = ( $yplot_hig - $yplot_low ) * 0.05;
    $yplot_hig += $mean; $yplot_low -= $mean;
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, 0);
    my $xtxt = "# days in trade"; 
    pglabel("$xtxt", "", "$tick - $unique");
    pg_plot_horizontal_line(0.0, 4, 15);  # zero-line
    pgsls(2);
    pgslw(1); # Set line width 
    pgsci(12);
    pgsfs(1); # fill is true
    for ($i = 0; $i < $numx; $i++) {
        if ($ny[$i] > 0) {
            pgrect($xd[$i]-0.4, $xd[$i]+0.4, $yplot_low, $yplot_low+$ny[$i]*($yplot_hig - $yplot_low)/$nmax);
#            pgline(2, [$xr[$i],$xr[$i]], [0,$yr[$i]]); #print "[$xr[$i],$xr[$i]], [0,$yr[$i]]\n";
        }
    }
    pgslw($linewidth);
    pgsci(7);
    pgline($numx, \@xd, \@rmean);
    pgmtext('RV', 1.0, 0.0, 1, "<R>");
    pgsci(8);
    pgpoint($numx, \@xd, \@rmean, $symbol);
    pgmtext('LV', 1.0, 0.0, 1, "N");
    pgsch(0.8); pgsci(15);
    $xtxt = sprintf("Exp = %.2f+/-%.2f, SQ = %.2f, MaxDD = %.1f", $meanR, $sigma, $sq, $maxdd*100.0) . "%";
    pgmtext('T', -2.1, 0.98, 1, "$system, $sysInitStop, $sysStop"); # lower right corner
    pgmtext('T', -1.0, 0.98, 1, "$xtxt"); # lower right corner
    pgmtext('T', 1.0, 0.98, 1, "$comment") if ($opt_S || $opt_C); # comment in upper right corner
    pgend;
    sleep 2 unless ($opt_p);
}

sub plotMAE {
    # not using strict; sharing variables with main program
    my ($i, $d, $device);
    my @data;
    if ($opt_p) {
        $device = "${btdir}plot_${tick}_${unique}_MAE.png/PNG";
    } else {
        $device = "/XSERVE";
    }
    my $font = 2;
    my $linewidth = 2;
    my $charheight = 1.2;
    my @relMAE = values %relAE;
    my @relMPE = values %relPE;
    my $relx = @relMAE; 
    pgbeg(0,$device,1,1); # || warn "pgbeg on $device says: $!\n"; # Open plot device 
    pgscr(0,1.0,1.0,1.0); # set background = white
    pgscr(1,0.0,0.0,0.0); # set foreground = black
    pgscf($font); # Set character font 
    pgslw($linewidth); # Set line width 
    pgsch($charheight); # Set character height 
    pgsci(1);  # default colour
    @maeFull = values %maxAE;
    @mpeFull = values %maxPE;
    #$numx = @maeFull; 
    my ($xplot_low, $xplot_hig) = low_and_high(@relMAE); #(@maeFull);  
    $xplot_low = -2.5 if ($xplot_low < -2.5);
    my $mean = ( $xplot_hig - $xplot_low ) * 0.02;
#    $xplot_hig += $mean;
    $xplot_hig = 0.0 + $mean;
    $xplot_low -= $mean;
    my ($yplot_low, $yplot_hig) = low_and_high(@relMPE); #(@mpeFull);  
    $mean = ( $yplot_hig - $yplot_low ) * 0.02;
    $yplot_hig += $mean;
    $yplot_low = 0.0 - $mean;
    my $symbol = 17;
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, 0);
    pglabel("MAE (up to close of stop-out-day)", "MPE", "$tick - $unique");
    pgsci(15);
    pgline(2, [$xplot_hig,$xplot_low], [0.0,0.0]);
    pgline(2, [-1.0,-1.0], [$yplot_low,$yplot_hig]);
    pgsci(1);
    pgsch(0.7);
    $xtxt = sprintf("Exp = %.2f+/-%.2f, SQ = %.2f, MaxDD = %.1f", $meanR, $sigma, $sq, $maxdd*100.0) . "%";
    pgmtext('T', -2.1, 0.45, 1, "$system, $sysInitStop, $sysStop"); # lower right corner
    pgmtext('T', -1.0, 0.45, 1, "$xtxt"); # lower right corner
    pgsci(4);
    pgpoint($relx, \@relMAE, \@relMPE, 19);
    pgsci(12);
    #pgpoint($numx, \@maeFull, \@mpeFull, $symbol); ## numx defined and commented out somehwere above...
    foreach $i (keys %maxAE) {
        if ($rmult{$i} >= 0.0) {
            pgsci(3); # green
            pgline(2, [$maxAE{$i},$maxAE{$i}], [$maxPE{$i},$rmult{$i}]);
            pgpoint(1, [$maxAE{$i}], [$rmult{$i}], $symbol);
        } else {
            pgsci(2); # red
            #pgline(2, [$maxAE{$i},$rmult{$i}], [$maxPE{$i},$maxPE{$i}]);
            pgpoint(1, [$rmult{$i}], [$maxPE{$i}], $symbol);
        }
    }
    pgsci(1);
    pgmtext('T', 1.0, 0.98, 1, "$comment") if ($opt_S || $opt_C); # comment in upper right corner
    pgend;
    sleep 2 unless ($opt_p);
}

sub plotPvsTime {
    my ($day, $device);
    # not using strict; sharing variables with main program
    if ($opt_p) {
        $device = "${btdir}plot_${tick}_${unique}_Ptime.png/PNG";
    } else {
        $device = "/XSERVE";
    }
    my $font = 2;
    my $linewidth = 2;
    my $charheight = 1.2;
    pgbeg(0,$device,1,1); # || warn "pgbeg on $device says: $!\n"; # Open plot device 
    pgscr(0,1.0,1.0,1.0); # set background = white
    pgscr(1,0.0,0.0,0.0); # set foreground = black
    pgscf($font); # Set character font 
    pgslw($linewidth); # Set line width 
    pgsch($charheight); # Set character height 
    pgsci(1);  # default colour
    my @yy = values %runPval;
    my @xx = keys %runPval;
    my ($nx, $ny) = sort2arrays(\@xx, \@yy);
    @xx = @$nx; @yy = @$ny;
    my $numx = @xx; 
    my $symbol = 17;
    ($yplot_low, $yplot_hig) = low_and_high(@yy); 
    ($xplot_low, $xplot_hig) = low_and_high(@xx);
    $xplot_low--; $xplot_hig++;  
    $mean = ( $yplot_hig - $yplot_low ) * 0.05;
    $yplot_hig += $mean; $yplot_low -= $mean;
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, 0);
    my $xtxt = "Day #"; 
    pglabel("$xtxt", "portfolio value", "$tick - $unique");
    pg_plot_horizontal_line($cash0, 2, 15);
    pg_plot_horizontal_line($cash0*1.10, 4, 14);
    pg_plot_horizontal_line($cash0*0.90, 4, 14);
    pgsch(0.7);
    pgsci(12);
#    $xtxt = sprintf "risk = 1.0%, MaxDD = %.2fR", $maxdd;
#    pgmtext('B', -2, 0.02, 0, "$xtxt"); # lower right corner
    pgpoint($numx, \@xx, \@yy, $symbol);
    pgline($numx, \@xx, \@yy);
    pgsci(15);
    $year = substr $hday{$xx[0]}, 0, 4;
    for ($i = 1; $i < $numx; $i++) {
        $nyear = substr $hday{$xx[$i]}, 0, 4;
        if ($nyear gt $year) {
            pg_plot_vertical_line($xx[$i], 2, 15);
            pgmtext('T', -1, ($xx[$i]-$xplot_low)/($xplot_hig-$xplot_low), 1, "$year"); # change wrt Backtest.pl
            $year = $nyear;
        }
    }
    $xtxt = sprintf("Exp = %.2f+/-%.2f, SQ = %.2f, MaxDD = %.1f", $meanR, $sigma, $sq, $maxdd*100.0) . "%";
    pgmtext('B', -2.1, 0.98, 1, "$system, $sysInitStop, $sysStop"); # lower right corner
    pgmtext('B', -1.0, 0.98, 1, "$xtxt"); # lower right corner
    pgmtext('T', 1.0, 0.98, 1, "$comment") if ($opt_S || $opt_C); # comment in upper right corner
    my $num = @sym;
    foreach $day (keys %rmult) {
        $i = $dayindex{$day};
        pgsci($col{$day});
        pgpoint(1, $i, $yplot_hig-2.0*$mean, $sym{$day}); 
    }

    pgend;
    sleep 2 unless ($opt_p);

}


sub plotMPEvsTime {

}

sub getWhichStop {
    my $myday = shift;
    # returns either $sysOrigTrailStop or $sysExitStop
    if (    ($breaklevel > $closep{$myday} && $direction{$dayTrade} eq 'long') || 
            ($breaklevel < $closep{$myday} && $direction{$dayTrade} eq 'short') ) {
#        return $sysOrigTrailStop;
        return $sysExitStop;
    } else {
        return $sysOrigTrailStop;
    }
}

#### additional code snippets

            # cancel the OK for the setup in case we're looking at Short/Long separately
#             $donotenter = $opentrade;  # do not enter in same direction if we've been stopped out today # TODO :: should be an option
#             if ($system =~ /Short/) {
#                 $oldsetupOK = "";
#             } elsif ($system =~ /Long/) {
#                 $oldsetupOK = "";
#             }

#        # testing reentry: ok if yd was higher low (go long) or lower high (go short)
#         $reenter = 0;   # the default
#         if (exists $hilo{$yday}) {
#             $idx = -1;
#             TESTDATE:for ($i=0; $i<$nex; $i++) {
#                 if ($datehl[$i] eq $yday) {
#                     $idx = $i-2;
#                     last TESTDATE;
#                 }
#             }
#             if ($idx >= 0) {
#                 if ($ishigh[$i]) {  # a high; must be a lower high to be a short signal...
#                     $reenter = -1 if ($hilo[$i] < $hilo[$idx]);
#                 } else {    # a low; must be a higher low to be long signal
#                     $reenter = 1 if ($hilo[$i] > $hilo[$idx]);
#                 }
#             }
#         } 
#         $relevantPrice = [$trendh{$day}-$trendh{$yday}, $trendl{$day}-$trendl{$yday}, $reenter];

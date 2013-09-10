#!/usr/bin/perl -I/Users/tdall/copyExecs
# 
### INTRADAY version #####
#
# define trading system and generate backtest
#
# TODO: How to enter on the next day under some condition... 'save' the signal?

# arg 1 = ticker symbol
# arg 2 = starting date
# arg 3 = end date
# arg 4 = system name; entry strategy/setup/signal
# arg 5 = initial stop strategy
# arg 6 = running stop/exit strategy
# [-p] make PNG plots for each trade
# [-n] do not plot the individual trades - overrides -p
# [-i] interactive to ask for whether to take the trade or not, plus pause and inspect each plot
# [-x <range>] extend x-range of plots so many days into the past
# [-X <range>] extend x-range of plots so many days into the future
# [-l] take supp/res levels into account
# [-f <trades-file>] take only trades in file and apply the stop/exit strategy
# [-F <trades-file>] take trades from file and do statistics, no strategy application
# [-c] prompt for a comment to be included in output files
# [-C <comment>] comment to include in output files
# [-s <strategy-file>] only first three arguments, all system description from file
# [-t] prompt for target price for each trade
# [-T <mult>{o|x|c}<fac>] first price target for parabolic stop at mult*R, once that's hit, it moves to fac*mult*R, use open, extreme or close price as given
# [-R] use the very conservative test (only makes sense for intraday)
# [-w] only take trades with setup given in -S <setup-name>
# [-S <setup-name>] use this setup - only used if -w is given

use Carp;
use Getopt::Std;
use PGPLOT;
#use GD::Graph::points;
require "utils.pl";
require "pg_utils.pl";
require "trader_utilsOLD.pl";

$tperc = 0;   # percentage for target price from entry
$|=1;
getopts('Ppix:X:lf:F:cC:ns:tT:RwS:');
@arg = @ARGV;
$numa = @arg;
if ($opt_P) {
	$plots = "-P";
} else {
	$plots = "";
}
if ($opt_T) {
    $opt_T =~ /([oxc])/;
    $whichPriceT = $1;
    ($iTarget, $targMul) = split /$whichPriceT/, $opt_T;
    $targMul = 1.0 unless $targMul;
    #print "splits into $iTarget and $targMul\n"; exit;
    warn "Error? Found price=$whichPriceT and target parameters $iTarget,$targetMul... " unless ($whichPriceT =~ /[oxc]/);
}
if ($opt_x) {
    $xbefore = $opt_x;
} else {
    $xbefore = 0;
}
if ($opt_X) {
    $xafter = $opt_X;
} else {
    $xafter = 0;
}
if ($opt_c) {
    print "Enter description: ";
    chomp( $comment = <STDIN> );
}
if ($opt_C) {
    $comment = $opt_C;
    $comment .= "## -T$opt_T" if $opt_T;
}
$tick = $arg[0];
$dayBegin = $arg[1];
$dayEnd = $arg[2];
if ($opt_s) {
    # take systems from file
    $sysfile = $opt_s;
    open SYST, "<$sysfile" || die "cannot open $sysfile: $!\n";
    while ($syst = <SYST>) {
        next if $syst =~ /^#/;
        chomp($syst);
    }
    close SYST;
} else {
    die "Not enough args\n" unless ($numa == 6);
    $system = $arg[3];
    $sysInitStop = $arg[4]; $sysInitStop =~ s/_/ /g;
    $sysStop = $arg[5]; $sysStop =~ s/_/ /g;
}
$intraday = 1;       # this is entering intraday, i.e. via stop-buy orders?
$adjIntraDay = 0;    # we're adjusting stops during the day?
$adjDayZero = 0;     # are we adjusting intraday on day 0 as well?
%p10wk = ();
if (-e "/Users/tdall/geniustrader/all4percentWk.p10wk") {
    open WK, "/Users/tdall/geniustrader/all4percentWk.p10wk" || die "n3483zo003m";
    while ($in = <WK>) {
        chomp($in);
        @tmp = split /\s+/, $in;
        next unless $tmp[0] ge $dayBegin;
        $p10wk{$tmp[0]} = $tmp[3];
    }
    close WK;
    $n10 = values %p10wk;
    #warn "using $n10 values of %10wk\n";
}
#### TODO: make a parameter to be read
$norw = "n";  # narrowest stop if several options are given

$path = "/Users/tdall/geniustrader/";
$dbfile = "/Users/tdall/geniustrader/traderThomas";
$btdir = "/Users/tdall/geniustrader/Backtests/";
chomp( $unique = `date "+%Y%m%dT%H%M%S"` );
open UNIQ, ">$btdir/unique.txt" or die "nzt238dHW44";
print UNIQ $unique;
close UNIQ;
$levfile = $path . "Levels/${tick}_lev.txt";
$whichway = "";   # long or short
$opentrade = "";  # long or short
$whichIndicator = "ATR5";   # should be read from strategy file... or on command line
$cash = 10000.0;
$riskP = 0.01;  # risk fraction
$pvalue = $cash;  
$fee1way = 5.90;
%possize = (); %stop = (); %istop = (); %inprice = (); %direction = (); @dayTrade = ();
@rMult = (); %exitp = (); %daysintrade = ();
$maxdd = 0.0; $dd = 0.0; 
$numdays = 0; $numdd = 0; $dd = 0.0;
$numtrades = 0; %pvalue = (); $cash0 = $cash; $pvalue{$numtrades} = $cash;
%ntrade = ();  %runPval = (); %hday = (); %dayindex = ();
$indexday = 0;
# @rMult visualized as colored (@col) symbols (@sym) plotted as a function of two indicators
@col = (); @sym = (); @ind1 = (); @ind2 = (); 
# $nameInd1 = "RSI"; $nameInd2 = "ATR";

# get the range of valid dates - ugly hack, but it works...
@date = `sqlite3 "$dbfile" "SELECT date \\
									   FROM stockprices \\
									   WHERE symbol = '$tick' \\
									   ORDER BY date \\
									   DESC"`;
chomp(@date); # contains the dates with most recent first
if ($dayBegin lt $date[-12]) {
    print "ERROR: $dayBegin given, but first allowed date is $date[-12]\n";
    exit();
}

# buy & hold result
#
$p1 = `sqlite3 "$dbfile" "SELECT day_close \\
									   FROM stockprices \\
									   WHERE symbol = '$tick' \\
									   AND date <= '$dayBegin' \\
									   ORDER BY date \\
									   DESC LIMIT 1"`;
$p2 = `sqlite3 "$dbfile" "SELECT day_close \\
									   FROM stockprices \\
									   WHERE symbol = '$tick' \\
									   AND date <= '$dayEnd' \\
									   ORDER BY date \\
									   DESC LIMIT 1"`;
$resBHfull = int ($cash / $p1) * ($p2 - $p1) + $cash - 2*$fee1way;
$resBHrisk = int ($cash * 0.1 / $p1) * ($p2 - $p1) + $cash - 2*$fee1way; # assuming 10% of funds invested, no risk consideration
if ($opt_l) {
    # ---- this needs testing ----  is the offset constant?? sudden jumps or smooth change?
    $loffset = 999;
    open LEV, "<$levfile" or die "no $levfile...\n";
    while ($in = <LEV>) {
        next if $in =~ /^#/;
        chomp($in);
        # first non-comment line must be a single value, the offset, so that real_price = yahoo_price + loffset
        if ($loffset == 999) {
            $loffset = $in;
            next;
        }
        @dum = split /\s+/, $in;
        if ($dum[0] =~ /-/) {
            ($min,$max) = split /-/, $dum[0];
        } else {
            $min = $dum[0];  $max = $dum[0];
        }
        $lday = $dum[1];
        push @levels, ($min, $max);
        $levels{$lday} = [$min, $max];
    }
    close LEV;
}
if ($opt_f) {
    open TRF, "<$opt_f" or die "no file $opt_f\n";
    while ($trf = <TRF>) {
        next unless $trf =~ /^\d/;
        @dum = split /\s+/, $trf;
        $direction{$dum[4]} = $dum[2];
        push @trf, $dum[4];
    }
    close TRF;
} elsif ($opt_F) {
    open TRF, "<$opt_F" or die "no file $opt_F\n";
    while ($trf = <TRF>) {
        next unless $trf =~ /^\d/;
        @dum = split /\s+/, $trf;
        $direction{$dum[4]} = $dum[2];
        $possize{$dum[4]} = $dum[3]; #print "$dum[4]: N = $possize{$dum[4]}, ";
        $inprice{$dum[4]} = $dum[5]; #print "in = $inprice{$dum[4]}, ";
        $exitp{$dum[4]} = $dum[7]; #print "out = $exitp{$dum[4]}, "; 
        push @dayTrade, $dum[4];
        push @rMult, $dum[8];
        $rmult{$dum[4]} = $dum[8];
        $daysintrade{$dum[4]} = $dum[9];
        $dum[0] =~ s/://g;
		$ntrade{$dum[4]} = $dum[0];
		if ($direction{$dum[4]} eq "long") {
		    $istop{$dum[4]} = $inprice{$dum[4]} - $pvalue * $riskP / $possize{$dum[4]};
		    $gain = ($exitp{$dum[4]} - $inprice{$dum[4]})*$possize{$dum[4]}; 
		    $pvalue += $gain;
		} else {
		    $istop{$dum[4]} = $inprice{$dum[4]} + $pvalue * $riskP / $possize{$dum[4]};
		    $gain = ($inprice{$dum[4]} - $exitp{$dum[4]})*$possize{$dum[4]};
		    $pvalue += $gain;
		}
		$pvalue{$dum[4]} = $pvalue; #printf "gain = %.2f, so pvalue = %.2f\n", $gain, $pvalue;
    }
    close TRF;
}

# open the bookkeeping files:
#
# DATA : 	Trade#  stop  indicators-at-entry
#			First line starts with comment telling which indicators are being recorded
#			Records new line whenever the stop is being moved
#
# TRADE : 	Overview for each trade
#			Trade#  tick  l/s  shares  day-in  price-in  day-out  price-out  R-multiple  duration  extra_note
#
# OUT : 	Summary file with info on the total statistics.
#
#
open DATA, ">${btdir}data_${system}_${tick}_${unique}_${dayBegin}_${dayEnd}.txt" or die "daw48";
print DATA "System = $system, Initial stop method = $sysInitStop, Exit/Stop = $sysStop\n";
print DATA "Price; O  H  L  C -- indicator RSI; rsi14  slope2  slope5\n";
open TRADE, ">${btdir}trades_${system}_${tick}_${unique}_${dayBegin}_${dayEnd}.txt" or die "msttr52r";
print TRADE "System = $system, Initial stop method = $sysInitStop, Exit/Stop = $sysStop\n";
print TRADE "# Comment: $comment\n" if ($opt_c || $opt_C);
print TRADE "# Trade#  tick  l/s  shares  day-in  price  day-out  price  R-mult  duration\n";
open OUT, ">${btdir}summary_${system}_${tick}_${unique}_${dayBegin}_${dayEnd}.txt" or die "a83mnmn0112";
print OUT "System $system, Portfolio = $pvalue, risk% = ";
printf OUT "%.2f\n", $riskP*100;

@datein = reverse @date;

#
# MAIN LOOP, day by day, look for signals
#
MAIN:foreach $day (@datein) {

    $indexday++;
	next if ($day lt $dayBegin); 
	last if ($day gt $dayEnd);
	print "$day .. " unless $opt_F;
    $runPval{$indexday} = $pvalue;  # running portfoliovalue
    $hday{$indexday} = $day;  # the day as function of the index of the day (good for calling indicators with day-before)
    $dayindex{$day} = $indexday;  # day before: $hday{$dayindex{$day}-1}
	$numdays++;
	next if ($opt_F);
	if ($opt_f) {
	    # only these days are good for trades; only proceed if we have a trade on, or if the date matches
	    $continue = 0;
	    foreach $trf (@trf) {
	        if ($trf eq $day) {
	            $continue = 1;
	            last;
	        }
	    }
	} else {
	    $continue = 1;
	}
	next unless ($opentrade || $continue);
	    
	$price = `sqlite3 "$dbfile" "SELECT day_open, day_high, day_low, day_close \\
									   FROM stockprices \\
									   WHERE symbol = '$tick' \\
									   AND date = '$day' \\
									   ORDER BY date \\
									   DESC"`;
	chomp($price);
	@p = split /\|/, $price;  # close price in p[3]
	$min = $p[2];  $max = $p[1]; $openp = $p[0]; #print "before: $openp\n";
	if ($openp < $p[3]) { # white candle
	    $upperBar = $p[3];
	    $lowerBar = $openp;
	    $cc = 1;
	} else { # black candle
	    $upperBar = $openp;
	    $lowerBar = $p[3];
	    $cc = -1;
	}
	#($min, $max) = low_and_high(@p);  
    if ($opt_T) {
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
            $curprice = $p[3];
        } else {
            die "Error: cannot assign price '$whichPriceT'\n";
        }
    } elsif ($intraday) {
        if ($opentrade eq "long") {
            $curprice = $max;
        } elsif ($opentrade eq "short") {
            $curprice = $min;
        } else {
            $curprice = 0;  # will be assigned later if a trade is opened on this day
        }
    } else {
        $curprice = $p[3];
    }

    #
	# 1. checking first if we've been stopped out with the stop level carried over from yesterday... 
	#
	if ($opentrade) {  
		push @xx, $numdays;
		push @yy, $p[3]; push @open, $openp; push @low, $min; push @high, $max;
		push @xs, $numdays;
		push @ss, $stop{$dayTrade};  # adding values here, plot after selling...
#		printf "min / max of day = %.2f / %.2f\n", $min, $max;
		if ( ($direction{$dayTrade} eq "long" && $min < $stop{$dayTrade}) || ($direction{$dayTrade} eq "short" && $max > $stop{$dayTrade}) ) {
		    # we're being stopped out ...
		    #
			printf "\n Stopped out on $day at %.2f - ", $stop{$dayTrade};
			#printf OUT "$day:\nStopped out of $direction{$dayTrade} position in $tick at %.2f - ", $stop{$dayTrade};
			if ( ($stop{$dayTrade} > $openp && $direction{$dayTrade} eq "long") || ($stop{$dayTrade} < $openp && $direction{$dayTrade} eq "short") ) {
			    $stop = $openp;
			} else {
			    $stop = $stop{$dayTrade};
			}
            $donotenter = $opentrade;  # not enter in same direction if we've been stopped out today
            &stopMeOut();
		}
	}

	# 2. any new signals? If we have a position, we check for exit first before adjusting stop, this includes the hard stops
	#
	($entrySig, $exitSig, $outtext, $ptxt, $xprice) = getSignal($tick, $system, $dbfile, $day, $opentrade, $numdays - $dayoftrade, $inprice{$dayTrade}, $istop{$dayTrade}, $curprice);    # $entrySig and $exitSig is either "long", "short", or ""
    #print "opentrade is = $opentrade... signal = $entrySig ...";
    if ($donotenter eq $entrySig) {
        $entrySig = "";
    }
    $donotenter = "";

    # defining the setup conditions
    #
    if ($opt_w) {
        # using the value of today for tomorrow since we do stop-buy...
        ## the short setups, starting with a 's'
        if ($opt_S =~ /^s/) {
            # prepending an 's' means valid for shorts
            if ($opt_S =~ /ATR(\d+.\d+)/) {
                $aPar = $1;
                $a5 = atr($tick, $dbfile, 5, $day);
                $a50 = atr($tick, $dbfile, 50, $day);
                if ($a5/$a50 > $aPar) { 
                    $donotenter = "short"; 
                } 
            }
            elsif ($opt_S =~ /R(\d+)/) {
                $rPar = $1;
                $rsi9 = rsi($tick, $dbfile, 9, $day);
                if ($rsi9 < $rPar) {
                    $donotenter = "short";
                }
            }
        } ## end of short setups
        ## the long setups, which are not starting with 's'...
        else {
            if ($opt_S =~ /ATR(\d+.\d+)/) {
                $aPar = $1;
                $a5 = atr($tick, $dbfile, 5, $day);
                $a50 = atr($tick, $dbfile, 50, $day);
                if ($a5/$a50 > $aPar) { 
                    $donotenter = "long"; 
                } 
            }
            elsif ($opt_S =~ /R(\d+)/) {
                $rPar = $1;
                $rsi9 = rsi($tick, $dbfile, 9, $day);
                if ($rsi9 > $rPar) { 
                    $donotenter = "long"; 
                } 
            }
        } ## end of long setups
    }
    
    ### code for later consideration:
    #    $whatisOK = getSetupCondition($tick, $opt_S, $dbfile, );  # no, do this for the eod version, but not here right now...
#         if ($opt_S =~ /p10wShort/) { 
#             ($column, $p10val, $p10s) = p10week($day);
#             $rs1 = rsi($tick, $dbfile, 14, $day);
#             $rs0 = rsi($tick, $dbfile, 14, $hday{$dayindex{$day}-1});
#             $delrs = $rs1 - $rs0;
#            # %10wk slope setup
#     #        if ($p10s > 5.0 || $rsi9 < 30.0 || $delrs < -5.0) { 
#         } 

    if ($opt_f) {
        # we're reading from file so if we're here then we'll have a trade...
        $entrySig = $direction{$day};
    }
	if ($exitSig && $opentrade eq $exitSig) {
		# if an open trade exists and we get an exit signal...
		#
		$whichway = $exitSig;
#		print "Will exit a $whichway trade.";
		#print OUT "$day: Will exit a $whichway trade. ";
        if ($xprice > 0) {
            ($gain, $exitp) = exitTrade($tick, $dbfile, $opentrade, $cash, $margin, $inprice{$dayTrade}, $possize{$dayTrade}, $day, $xprice);
        } else {
    		($gain, $exitp) = exitTrade($tick, $dbfile, $opentrade, $cash, $margin, $inprice{$dayTrade}, $possize{$dayTrade}, $day);
        }
		$cash += ($gain + $inprice{$dayTrade} * $possize{$dayTrade} - $fee1way);
		$oldpvalue = $pvalue;
		$pvalue += ($gain - $fee1way);
		$daysintrade{$dayTrade} = $numdays - $dayoftrade;
		$rmult{$dayTrade} = $gain/$risk;  # change?? to include transaction costs...
        $exitp{$dayTrade} = $exitp;
		$adx0 = indicatorValue($whichIndicator);
		$targetPrice = indicatorValue("ATR50") unless ($opt_t || $opt_T);
		printf TRADE "$day %7.2f %6.3f %3.3s %-5.5s %.2f %.2f\n", $exitp, $gain/$risk, $daysintrade{$dayTrade}, $tnote, $adx0, $targetPrice;
		printf "exit $tnote at R = %.2f .. ", $rmult{$dayTrade};
        push @rMult, $gain/$risk;
        # recording the indicator values:
        &populatePlotArrays();
        unless ($opt_n) {
            &forwardpopulate4plot($xafter);
            &plotTrade();
        }
        $pvalue{$numtrades} = $pvalue;
		$opentrade = "";
	}
	if ($entrySig && ! $opentrade) {	
		# we don't have an open trade and we got an entry signal...
		#
        #print " and $entrySig\n"; #exit;
		if ($system =~ /VolB(\w{1})\d/) {
		    # entering during the day, so not at the close but at a pre-set stop-buy
		    # assume we're not stopped out during the day, excaept when two trades would be
		    # entered, in which case we assume one full -1R and one open position at the close.
		    #print "\nout: $outtext --\n";
		    if ($outtext =~ /X/) {
		        @dum2 = split /X/, $outtext;
		        $outtext = $dum2[1];
		        $extratxt = $dum2[0];
		    } else {
		        $extratxt = "";
		    }
		    $whenVB = $1;  #print "\n -- output: $outtext --  txt: $extratxt --\n";
		    @dum = split /_/, $outtext;
		    $inprice = $dum[0];
		    $tr = $dum[1];
		    $vbfac = $dum[2]; #print "extracted:-- $inprice -- $tr -- $vbfac --\n";
		    @addall = ($inprice+$tr*$vbfac, $inprice-$tr*$vbfac);
		    chomp( @mytmp = `sqlite3 "$dbfile" "SELECT day_open, day_high, day_low, day_close \\
								   FROM stockprices \\
								   WHERE symbol = '$tick' \\
								   AND date <= '$day' \\
								   ORDER BY date \\
								   DESC LIMIT 2"` );
			@ohlc0 = split /\|/, $mytmp[0];  # today
			@ohlc1 = split /\|/, $mytmp[1];  # yesterday
		    if ($dum[3] =~ /(\D+)(\d+.?\d*)/) {
		        printf TRADE "-1:\t%7.7s %-5.5s %4.4s $day %7.2f $day %7.2f %6.3f %3.3s %-5.5s -1.00\n", $tick, $1, -1, $2, $inprice, -1.0, 0, " ";
		        push @rMult, -1.00;
		        print "(ugh.. a 1R loss today) ";
		    }
		    print "entering $entrySig at $inprice\n";
		} else {
            $inprice = $p[3];
            @addall = ();
        }
		if ($opt_i) {
		    print "\n$day - $tick: $entrySig entry signal to enter at $inprice - OK? [Y/n] "; $svar = <STDIN>;
		    if ($svar =~ /[nN]/) {
		        next MAIN;
		    }
		}
		$whichway = $entrySig;
		$dayTrade = $day;
		$pltext = "$outtext $ptxt";  # text for plot
		$outtext =~ /^(.*):/;  $tnote = $1;
		push @dayTrade, $dayTrade;
		print "entering $whichway trade .. ";  
        $curprice = $max if ($whichway eq "long");
        $curprice = $min if ($whichway eq "short");
		#printf OUT "$day: $whichway trade. "; 
        @xx = (); @yy = (); @xs = (); @ss = (); @open = (); @low = (); @high = (); # for the plotting
        &backpopulate4plot($xbefore);  # fill first with x previous days
        $save4vb = $yy[-1];  # close price yesterday for VolBreak-C
		$opentrade = $whichway;  $direction{$dayTrade} = $whichway;
		$risk = $riskP * $cash;
        $inprice{$dayTrade} = $inprice;
		$stop{$dayTrade} = getStop($sysInitStop, $dbfile, $day, 0.0, 0.0, $tick, $opentrade, $inprice{$dayTrade}, $inprice{$dayTrade}, $targetPrice, 0, $norw);   # last arg is age of trade
		($possize{$dayTrade}, $posprice) = enterTrade($direction{$dayTrade}, $inprice{$dayTrade}, $stop{$dayTrade}, $risk);
		$cash -= ($posprice + $fee1way);
		$pvalue -= $fee1way;
		$numtrades++;
		$ntrade{$dayTrade} = $numtrades;
		$dayoftrade = $numdays;
		$istop{$dayTrade} = $stop{$dayTrade};
		if ($opt_t) {   # either prompt, use the 'typical' value, or the provided R-mult
		    print "Target? "; chomp($dum = <STDIN>); 
		    if ($dum) { 
		        $targetPrice = $dum; 
		    } else {
		        $targetPrice=0;
		    }
		} elsif ($opt_T) {
		    $targFac = $iTarget * abs($inprice{$dayTrade} - $istop{$dayTrade});
		    if ($direction{$dayTrade} eq "long") {
		        $targetPrice = $inprice{$dayTrade} + $targFac;
		    } elsif ($direction{$dayTrade} eq "short") {
		        $targetPrice = $inprice{$dayTrade} - $targFac;
		    }
            printf " Target = %.2f ", $targetPrice;
		} elsif ($tperc > 0.0) {
            if ($whichway eq "long") {
                $targetPrice = (1.0 + $tperc/100.0)*$p[3];   # rough estimate of typical target price...
            } else {
                $targetPrice = (1.0 - $tperc/100.0)*$p[3];
            }
        } else {
            $targetPrice = 0;
        }
		push @xx, $numdays;
		push @yy, $p[3]; push @open, $openp; push @low, $min; push @high, $max;
		push @xs, $numdays;
		push @ss, $stop{$dayTrade};  # adding values here, plot after selling...
		@indic = getIndicator($tick, $dbfile, "ATR", 5, $day);  ### pass also $strategy to determine which ones to return?
		printf DATA "%.3f %.3f %.3f ", @indic;
		printf TRADE "$numtrades:\t%7.7s %-5.5s %4.4s $day %7.2f ", $tick, $opentrade, $possize{$dayTrade}, $inprice{$dayTrade}
	}
	# 3. adjust stop if we have open position
	#
	if ($opentrade) {  # && ($intraday || $numdays - $dayoftrade > 0) ) { 
#	if ($opentrade && ($intraday && $numdays - $dayoftrade > 0) ) {  # NOT adjusting stop on day 0 - seee also point 4.
		if ($opt_t &&  (  ($curprice > $targetPrice && $opentrade eq "long")  ||  ($curprice < $targetPrice && $opentrade eq "short")  )  ) {   # either prompt or use the 'typical' value
		    print "Target has been reached! New target? "; chomp($dum = <STDIN>); 
		    if ($dum) { 
		        $targetPrice = $dum; 
		    } else {
		        $targetPrice=0;
		    }
		} elsif ($opt_T  &&  (  ($curprice > $targetPrice && $opentrade eq "long")  ||  ($curprice < $targetPrice && $opentrade eq "short")  )  ) {
 		    if ($direction{$dayTrade} eq "long") {
 		        $targetPrice += $targMul * $targFac;
 		    } elsif ($direction{$dayTrade} eq "short") {
 		        $targetPrice -= $targMul * $targFac;
 		    }
            printf " New target = %.2f ", $targetPrice;
		}
		printf ".. $opentrade position day %d; stop before = %.2f, stop ", $numdays - $dayoftrade, $stop{$dayTrade}; printf "(curprice=%.2f) ", $curprice;
		$stop{$dayTrade} = getStop($sysStop, $dbfile, $day, $stop{$dayTrade}, $istop{$dayTrade}, $tick, $opentrade, $inprice{$dayTrade}, $curprice, $targetPrice, $numdays - $dayoftrade, $norw);
	    printf "after = %.2f (on $day)\n", $stop{$dayTrade};
	}
	# 4. check if we exit because of intraday stop-adjustments
	#
	if ($opentrade && $intraday && $adjIntraDay && (  ($adjDayZero && $numdays - $dayoftrade == 0) || ($numdays - $dayoftrade > 0)  ) ) {
        push @xs, $numdays+0.3; 
		push @ss, $stop{$dayTrade};  # adding values here, plot after selling...
	    #### this is for very conservative test ####
        if ($numdays - $dayoftrade == 0 && $opt_R) {
            if ( ($opentrade eq "long" && ( ($istop{$dayTrade} > $openp && $cc == 1) || ($istop{$dayTrade} > $min && $cc == -1) ) ) ||
               $opentrade eq "short" &&   ( ($istop{$dayTrade} < $openp && $cc == -1) || ($istop{$dayTrade} < $max && $cc == 1) ) ) {
                $stop = $istop{$dayTrade};
                &stopMeOut();            
            }
        }
	    elsif ( $max > $stop{$dayTrade} && $stop{$dayTrade} > $min ) {
	        # if long + black candle OR long + newstop > close
	        if (  ($opentrade eq "long" && $stop{$dayTrade} > $p[3]) || ($opentrade eq "short" && $stop{$dayTrade} < $p[3]) ) {
#	        if (  ($opentrade eq "long" && ($openp >= $p[3] || $stop{$dayTrade} > $p[3])) || ($opentrade eq "short" && ($openp <= $p[3] || $stop{$dayTrade} < $p[3])) ) {	        
                printf "\n Stopped out after adjusting on $day at %.2f - ", $stop{$dayTrade};
			    $stop = $istop{$dayTrade};
                &stopMeOut();
	        }
	    }
	}
#	exit;
#	print "\n";
#	printf "Cash = %.2f; Portfolio value = %.2f\n", $cash, $pvalue;
	if ($opentrade) {
	    #print "-2- $opentrade --\n";
        #printf OUT "Cash = %.2f; Portfolio value = %.2f\n", $cash, $pvalue;
        printf DATA "$numtrades:\t$opentrade\t$possize{$dayTrade} x $inprice{$dayTrade} stop=%.2f  OHLC: %.2f %.2f %.2f %.2f\n", $stop{$dayTrade},@p;
 #       print "$numtrades: $opentrade -- $dayTrade $possize{$dayTrade}, $inprice{$dayTrade}, $stop{$dayTrade}, $openp, $p[1], $p[2], $p[3]\n";# exit;
    }

} 	# end of MAIN LOOP
	#
	#
	
# cancel any remaining open positions
#
if ($opentrade) {
	$pvalue += $fee1way;
	$cash += ($inprice{$dayTrade} * $possize{$dayTrade} + $fee1way);
	printf TRADE "$dayEnd %7.2f %6.3f%", $inprice{$dayTrade}, 0.0; 
	printf TRADE " %3.3s\n", -1;  # -1 means canceled, so filter it out in subsequent analysis
	pop @dayTrade;
}
print "done!\n";

# calculate the reliability of the system for day 1, 2, 5, 10, 20
#
# random entry will give around 50% (45-55). This should be at least 55%, more is better.
#
@days = (0, 1, 2, 3, 4, 5, 10, 20);
%prof = ();
$npdays = @days;
foreach $days (@days) {
    $prof{$days} = 0;
}
@maeFull = ();  @mpeFull = ();
foreach $day (@dayTrade) {
	@price = getPriceAfterDays($tick, $dbfile, $day, \@days);
	for ($i=0; $i < $npdays; $i++) {	
	    #print "Price on day $day + $days[$i] was $price[$i], entry at $inprice{$day} for $direction{$day} trade.\n";	
		if ( ($price[$i] - $inprice{$day} > 0 && $direction{$day} eq "long") || ($price[$i] - $inprice{$day} < 0 && $direction{$day} eq "short") ){
			# it was profitable, so we count 1
			$prof{$days[$i]}++;
		}
	}
	($mae0, $mpe0) = getMAE($tick, $dbfile, $inprice{$day}, $istop{$day}, $daysintrade{$day}, $day);
	push @maeFull, $mae0;
	push @mpeFull, $mpe0; 
}
$tot = @dayTrade;
print "Reliability after ... days:\n";
print OUT "Comment: $comment\n" if ($opt_c || $opt_C);
print OUT "Reliability after ... days:\n";
foreach $days (@days) {
	printf "%3.3s days :: %.2f% +/- %.2f%\n", $days, 100.0*$prof{$days}/$tot, 100.0*sqrt($prof{$days})/$tot; 
	printf OUT "%3.3s days :: %.2f% +/- %.2f%\n", $days, 100.0*$prof{$days}/$tot, 100.0*sqrt($prof{$days})/$tot; 
}
print "Comment: $comment\n" if ($opt_c || $opt_C);

# work on the R-multiples
#
$numTrades = @rMult; #print "Total # of trades = $numTrades, ";
$meanR = sum(@rMult) / $numTrades; #print "Exp = $meanR \n";
$sigma = sigma($meanR, @rMult);
$sq = $meanR/$sigma;

# plot the R-distribution in various ways
#
&plotRdist();
&plotPvalue();
&plotRvsLength();
&plotRvsDays();
&plotMAE();
&plotRvsIndicators() if ($nameInd1 && $nameInd2);

# plot the portfoliovalue as a function of time with the trades marked
#
&plotPvsTime() unless $opt_F;

# make a summary
#
# high expectancy is good, but system quality should be determining:
# < 0.17 - very hard to trade
# .17 - .20: average
# .20 - .29: good
# .30 - .49: excellent
# .50 - .69: superb
# .70+ : Holy Grail
printf "Buy and hold values: fully invested = %.2f; risk frac invested = %.2f\n", $resBHfull, $resBHrisk;
print "System = $system, Initial stop method = $sysInitStop, Exit/Stop = $sysStop\n";
printf "System result:\n\tPortfolio value at end   = %.2f from $numTrades trades in $numdays trading days.\n", $pvalue;
printf "\tExpectancy = %.2f+/-%.2f, System Quality = %.2f, Max drawdown = %.2f%. Longest losing streak = %1d trades\n", $meanR, $sigma, $sq, $maxdd*100.0, $maxnumdd; 
printf "\tW/L = %d/%d, W/L-ratio = %d/%d. <R_pos> = %.2f +/- %.2f, <R_neg> = %.2f +/- %.2f\n",
    $npos, $nneg, int(100*$npos/$numTrades), 100-int(100*$npos/$numTrades), $meanpos, $sigpos, $meanneg, $signeg;
printf "\tOpportunity = %.3f trades/day. Expected profit per day = %.3fR\n", $numTrades/$numdays, $meanR * $numTrades/$numdays;
printf "\tProjected profit per... Week = %.3fR. Month = %.3fR.\n", 5*$meanR * $numTrades/$numdays, 20.0*$meanR * $numTrades/$numdays;
printf OUT "Buy and hold values: fully invested = %.2f; risk frac invested = %.2f\n", $resBHfull, $resBHrisk;
print OUT "System = $system, Initial stop method = $sysInitStop, Exit/Stop = $sysStop\n";
printf OUT "System result:\n\tPortfolio value at end   = %.2f from $numTrades trades in $numdays trading days.\n", $pvalue;
printf OUT "\tExpectancy = %.2f+/-%.2f, System Quality = %.2f, Max drawdown = %.2f%. Longest losing streak = %1d trades\n", $meanR, $sigma, $sq, $maxdd*100.0, $maxnumdd; 
printf OUT "\tW/L = %d/%d, W/L-ratio = %d/%d. <R_pos> = %.2f +/- %.2f, <R_neg> = %.2f +/- %.2f\n",
    $npos, $nneg, int(100*$npos/$numTrades), 100-int(100*$npos/$numTrades), $meanpos, $sigpos, $meanneg, $signeg;
printf OUT "\tOpportunity = %.3f trades/day. Expected profit per day = %.3fR\n", $numTrades/$numdays, $meanR * $numTrades/$numdays;
printf OUT "\tProjected profit per... Week = %.3fR. Month = %.3fR.\n", 5*$meanR * $numTrades/$numdays, 20.0*$meanR * $numTrades/$numdays;
printf OUT "toread: %.2f\t%.2f\t%.2f\t%d\t%d\t%d\t%d\t%.2f\t%.2f\t%.3f\t%.3f\n", $pvalue, $meanR, $sq, $npos, $nneg, $numTrades, $numdays, $meanpos, $meanneg, $numTrades/$numdays, $meanR * $numTrades/$numdays;
close OUT;
close DATA;
close TRADE;

# ####
# subroutines
# ####

sub stopMeOut {
    ($gain, $stop) = exitTrade($tick, $dbfile, $direction{$dayTrade}, $cash, $margin, $inprice{$dayTrade}, $possize{$dayTrade}, $day, $stop);
    carp "Error in stop, or a gap?? $stop{$dayTrade} vs $stop\n" unless ($stop{$dayTrade} == $stop);
    $daysintrade{$dayTrade} = $numdays - $dayoftrade;
    $rmult{$dayTrade} = $gain/$risk;
    printf "$tnote stopped out at R = %.2f .. ", $rmult{$dayTrade};
    #printf OUT "Gain = %.2f at reward/risk (R-mult) of %.2f\n", $gain, $rmult{$dayTrade};
    push @rMult, $rmult{$dayTrade};
    # recording the indicator values:
    &populatePlotArrays();
    $adx0 = indicatorValue($whichIndicator);
    printf TRADE "$day %7.2f %6.3f %3.3s %-5.5s %.2f %.2f\n", $stop{$dayTrade}, $rmult{$dayTrade}, $daysintrade{$dayTrade}, $tnote, $adx0, $targetPrice;
    $cash += ($gain + $inprice{$dayTrade} * $possize{$dayTrade} - $fee1way);
    $pvalue += ($gain - $fee1way);
    $opentrade = "";
    $exitp = $stop;
    $exitp{$dayTrade} = $exitp;
    unless ($opt_n) {
        &forwardpopulate4plot($xafter);
        &plotTrade();
    }
    $pvalue{$numtrades} = $pvalue;
    #printf OUT "Cash = %.2f; Portfolio value = %.2f\n", $cash, $pvalue;
}

sub indicatorValue {
    my $in = shift;
    $in =~ /(\D+)(\d+)/;
    my $ind = $1; my $peri = $2;
    if ($ind =~ /ATR/) {
        print "ATR of $peri periods = ";
        $in = atr($tick, $dbfile, $peri, $dayTrade);
        printf "%.2f ", $in;
    } elsif ($ind =~ /ADX/) {
        $in = adx($tick, $dbfile, $peri, $dayTrade);
    }
    return $in;
}

sub plotRvsDays {
    # not using strict; sharing variables with main program
    my ($i, $d);
    my @data;
    if ($opt_p) {
        $device = "${btdir}plot_${tick}_${unique}_RvDays.png/PNG";
    } else {
        $device = "/XSERVE";
    }
    &myInitGraph();
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
    $xtxt = sprintf "Exp = %.2f+/-%.2f, SQ = %.2f, MaxDD = %.1f%", $meanR, $sigma, $sq, $maxdd*100.0;
    pgmtext('T', -2.1, 0.98, 1, "$system, $sysInitStop, $sysStop"); # lower right corner
    pgmtext('T', -1.0, 0.98, 1, "$xtxt"); # lower right corner
    pgmtext('T', 1.0, 0.98, 1, "$comment") if ($opt_c || $opt_C); # comment in upper right corner
    pgend;
    sleep 2 unless ($opt_p);
}

sub plotMAE {
    # not using strict; sharing variables with main program
    my ($i, $d);
    my @data;
    if ($opt_p) {
        $device = "${btdir}plot_${tick}_${unique}_MAE.png/PNG";
    } else {
        $device = "/XSERVE";
    }
    &myInitGraph();
    $numx = @maeFull;
    my ($xplot_low, $xplot_hig) = low_and_high(@maeFull);  # dereferences the array pointer
    my $mean = ( $xplot_hig - $xplot_low ) * 0.02;
    $xplot_hig += $mean;
    $xplot_low -= $mean;
    my ($yplot_low, $yplot_hig) = low_and_high(@mpeFull);  # dereferences the array pointer
    $mean = ( $yplot_hig - $yplot_low ) * 0.02;
    $yplot_hig += $mean;
    $yplot_low -= $mean;
    my $symbol = 17;
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, 0);
    pgsci(15);
    pgline(2, [$xplot_hig,$xplot_low], [0.0,0.0]);
    pgline(2, [-1.0,-1.0], [$yplot_low,$yplot_hig]);
    pgsci(1);
    pgsch(0.8);
    $xtxt = sprintf "Exp = %.2f+/-%.2f, SQ = %.2f, MaxDD = %.1f%", $meanR, $sigma, $sq, $maxdd*100.0;
    pgmtext('B', -2.1, 0.98, 1, "$system, $sysInitStop, $sysStop"); # lower right corner
    pgmtext('B', -1.0, 0.98, 1, "$xtxt"); # lower right corner
    pgsci(12);
    pgpoint($numx, \@maeFull, \@mpeFull, $symbol);
    pgmtext('T', 1.0, 0.98, 1, "$comment") if ($opt_c || $opt_C); # comment in upper right corner
    pgend;
    sleep 2 unless ($opt_p);
}

sub plotRvsLength {
    # not using strict; sharing variables with main program
    my ($i, $d);
    my @data;
    if ($opt_p) {
        $device = "${btdir}plot_${tick}_${unique}_Rlength.png/PNG";
    } else {
        $device = "/XSERVE";
    }
    &myInitGraph();
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
#    $xplot_low--; $xplot_hig++;
    my $mean = ( $yplot_hig - $yplot_low ) * 0.05;
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
    foreach $i (sort keys %ntrade) {
        @xlin = (0 .. $daysintrade{$i});
        $numtail = $daysintrade{$i} + 1;
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
        chomp( @data = reverse `sqlite3 "$dbfile" "SELECT day_close \\
								   FROM stockprices \\
								   WHERE symbol = '$tick' AND date>='$i'\\
								   ORDER BY date \\
								   DESC" | tail -$numtail`);
		if ($direction{$i} eq "long") {
		    $dirp = "day_low";
		    $dirm = "day_high";
		} elsif ($direction{$i} eq "short") {
		    $dirp = "day_high";
		    $dirm = "day_low";
		} else {
		    print "WARNING:  direction not fund...\n";
		}
        chomp( @phl = reverse `sqlite3 "$dbfile" "SELECT $dirp \\
								   FROM stockprices \\
								   WHERE symbol = '$tick' AND date>='$i'\\
								   ORDER BY date \\
								   DESC" | tail -$numtail`);
        chomp( @pmpe = reverse `sqlite3 "$dbfile" "SELECT $dirm \\
								   FROM stockprices \\
								   WHERE symbol = '$tick' AND date>='$i'\\
								   ORDER BY date \\
								   DESC" | tail -$numtail`);
		for ($j=0; $j<=$daysintrade{$i}; $j++) {
		    $ylin[$j] = (($data[$j]-$inprice{$i})*$possize{$i}-2*$fee1way)/(($inprice{$i}-$istop{$i})*$possize{$i}); #print "day=$data2[$j], x=$xlin[$j], ylin = $ylin[$j]\n";
            $rFromX = (($phl[$j]-$inprice{$i})*$possize{$i}-2*$fee1way)/(($inprice{$i}-$istop{$i})*$possize{$i});
            $r4mpe = (($pmpe[$j]-$inprice{$i})*$possize{$i}-2*$fee1way)/(($inprice{$i}-$istop{$i})*$possize{$i});
            if ($ylin[$j] > 0.01 && $j >= 1) {
                $posRs++;
                $maxR = $ylin[$j] if ($ylin[$j] > $maxR && $j < $daysintrade{$i});
            } elsif ($ylin[$j] < -0.01 && $j >= 1) {
                $negRs++;
                $minR = $ylin[$j] if ($ylin[$j] < $minR && $j < $daysintrade{$i});
            }
            if ($rFromX < -0.01 && $j >= 1) {
                $maxAE = $rFromX if ($rFromX < $maxAE);
            }
            if ($r4mpe > 0.01 && $j >= 1) {
                $maxPE = $r4mpe if ($r4mpe > $maxPE);
            }
		}
		$ylin[$daysintrade{$i}] = $rmult{$i};
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
		$nny = @ylin; $nnx = @xlin; #print "nx = $nnx, ny = $nny - days in trade = $daysintrade{$i}\n";
		pgline($daysintrade{$i}+1, \@xlin, \@ylin) unless $opt_F;
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
    $xtxt = sprintf "Exp = %.2f+/-%.2f, SQ = %.2f, MaxDD = %.1f%", $meanR, $sigma, $sq, $maxdd*100.0;
    pgmtext('B', -2.1, 0.98, 1, "$system, $sysInitStop, $sysStop"); # lower right corner
    pgmtext('B', -1.0, 0.98, 1, "$xtxt"); # lower right corner
    pgsci(12);
    pgpoint($numx, \@xd, \@yr, $symbol);
    pgmtext('T', 1.0, 0.98, 1, "$comment") if ($opt_c || $opt_C); # comment in upper right corner
    pgend;
    sleep 2 unless ($opt_p);
}


sub plotPvsTime {
    my $day;
    # not using strict; sharing variables with main program
    if ($opt_p) {
        $device = "${btdir}plot_${tick}_${unique}_Ptime.png/PNG";
    } else {
        $device = "/XSERVE";
    }
    &myInitGraph();
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
    $xtxt = sprintf "Exp = %.2f+/-%.2f, SQ = %.2f, MaxDD = %.1f%", $meanR, $sigma, $sq, $maxdd*100.0;
    pgmtext('B', -2.1, 0.98, 1, "$system, $sysInitStop, $sysStop"); # lower right corner
    pgmtext('B', -1.0, 0.98, 1, "$xtxt"); # lower right corner
    pgmtext('T', 1.0, 0.98, 1, "$comment") if ($opt_c || $opt_C); # comment in upper right corner
    my $num = @sym;
    foreach $day (keys %rmult) {
        $i = $dayindex{$day};
        pgsci($col{$day});
        pgpoint(1, $xx[$i], $yplot_hig-2.0*$mean, $sym{$day});
    }

    pgend;
    sleep 2 unless ($opt_p);

}

sub plotPvalue {
    # not using strict; sharing variables with main program
    if ($opt_p) {
        $device = "${btdir}plot_${tick}_${unique}_Pvalue.png/PNG";
    } else {
        $device = "/XSERVE";
    }
    &myInitGraph();
#     my @yy = values %pvalue;
#     my @xx = keys %pvalue;
#     my ($nx, $ny) = sort2arrays(\@xx, \@yy);
#     @xx = @$nx; @yy = @$ny;
    my $symbol = 17;
    ($nx, $ny, $maxdd, $maxnumdd) = pvalue4risk(0.01);
    @xx = @$nx; @yy = @$ny;
    my $numx = @xx;
    ($nx, $ny, $maxd2, $maxl2) = pvalue4risk(0.02); 
    @xx2 = @$nx; @yy2 = @$ny;
    ($nx, $ny, $maxd5, $maxl5) = pvalue4risk(0.005);
    @xx5 = @$nx; @yy5 = @$ny;
    @all = (@yy, @yy2, @yy5);
    ($yplot_low, $yplot_hig) = low_and_high(@all); 
    ($xplot_low, $xplot_hig) = low_and_high(@xx);
    $xplot_low--; $xplot_hig++;
    $mean = ( $yplot_hig - $yplot_low ) * 0.05;
    $yplot_hig += $mean; $yplot_low -= $mean;
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, 0);
    my $xtxt = "Trade #"; 
    pglabel("$xtxt", "portfolio value", "$tick - $unique");
    pg_plot_horizontal_line($cash0, 2, 15);
    pg_plot_horizontal_line($cash0*1.10, 4, 14);
    pg_plot_horizontal_line($cash0*0.90, 4, 14);
    pgsch(0.7);
    pgsci(12);
    $xtxt = sprintf "risk = 1.0%, MaxDD = %.2fR", $maxdd;
    pgmtext('B', -2, 0.02, 0, "$xtxt"); # lower right corner
    pgpoint($numx, \@xx, \@yy, $symbol);
    pgline($numx, \@xx, \@yy);
    pgsci(13);
    $xtxt = sprintf "risk = 2.0%, MaxDD = %.2fR", $maxd2;
    pgmtext('B', -1, 0.02, 0, "$xtxt"); # lower right corner
    pgpoint($numx, \@xx2, \@yy2, $symbol);
    pgline($numx, \@xx2, \@yy2);
    pgsci(8);
    $xtxt = sprintf "risk = 0.5%, MaxDD = %.2fR", $maxd5;
    pgmtext('B', -3, 0.02, 0, "$xtxt"); # lower right corner
    pgpoint($numx, \@xx5, \@yy5, $symbol);
    pgline($numx, \@xx5, \@yy5);
    pgsci(15);
    $xtxt = sprintf "Exp = %.2f+/-%.2f, SQ = %.2f, MaxDD = %.1f%", $meanR, $sigma, $sq, $maxdd*100.0;
    pgmtext('B', -2.1, 0.98, 1, "$system, $sysInitStop, $sysStop"); # lower right corner
    pgmtext('B', -1.0, 0.98, 1, "$xtxt"); # lower right corner
    pgmtext('T', 1.0, 0.98, 1, "$comment") if ($opt_c || $opt_C); # comment in upper right corner
    pgsch($charheight); # Set character height 
    pgend;
    sleep 2 unless ($opt_p);
}

sub pvalue4risk {
    # not using strict; sharing variables with main program
    my $riskp = shift;
    my ($tgain, $risk, $psize);
    my $dd = 0; my $maxdd = 0.0;
    my @xtnum = (); my @ypval = ();
    $xtnum[0] = 0; $ypval[0] = $cash0;
    my $pval = $cash0; 
    my $pmax = $cash0;  my $pmin = $cash0;  my $lloss = 0; my $absmin = $cash0;
    foreach $d (@dayTrade) {  # @dayTrade have the trade-days in correct order
        $risk = $riskp * $pval;
        $psize = int abs( $risk / ($inprice{$d} - $istop{$d}) );
        if ($direction{$d} eq "long") {
            $tgain = $psize * ($exitp{$d} - $inprice{$d}) - 2*$fee1way;
        } elsif ($direction{$d} eq "short") {
            $tgain = $psize * ($inprice{$d} - $exitp{$d}) - 2*$fee1way;
        } else {
            die "...what!? found direction = $direction{$d}\n";
        }
        $pval += $tgain; 
        # maxdd is from a previous high to the next low. Another in-between high does not count
        # TODO: fix this - it is clearly not correct...
        if ($pval > $pmax) {
            $pmax = $pval;
            $pmin = $pmin;
        } elsif ($pval < $pmin) {
            $pmin = $pval;
            if (($pmax - $pmin)/$pmax > $maxdd) {
                $maxdd = ($pmax - $pmin)/$pmax;
            }
        }
        if ($pval < $absmin) {
            $absmin = $pval;
        }
        if ($tgain < 0.0) {
            $dd++;
            if ($dd > $lloss) {
                $lloss = $dd;
            }
        } elsif ($tgain > 0.0) {
            $dd = 0;
        }
        push @xtnum, $ntrade{$d}; push @ypval, $pval;
    }
        
    return (\@xtnum, \@ypval, $maxdd, $lloss);
}

sub plotRdist {
    # not using strict; sharing variables with main program
    if ($opt_p) {
        $device = "${btdir}plot_${tick}_${unique}_Rdist.png/PNG";
    } else {
        $device = "/XSERVE";
    }
    &myInitGraph();
    @xr = (-3 .. 10);
    %count = ();
    RMUL:foreach $r (@rMult) {
        if ($r > 0.0) {
            push @rpos, $r;
        } else {
            push @rneg, $r;
        }
        foreach $xr (@xr) {
#            if ($r >= $xr-0.5 && $r < $xr+0.5) {
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
    $meanpos = sum(@rpos)/$npos;
    $sigpos = sigma($meanpos,@rpos);
    $meanneg = sum(@rneg)/$nneg;
    $signeg = sigma($meanneg,@rneg);
    @yr = values %count;
    @xr = keys %count;
    $numx = @xr;
    @yr = div_array(\@yr, $numTrades);
    ($yplot_low, $yplot_hig) = low_and_high(@yr); 
    ($xplot_low, $xplot_hig) = low_and_high(@xr);
    $xplot_low--; $xplot_hig += 1.5;
    $mean = ( $yplot_hig - $yplot_low ) * 0.05;
    $yplot_hig += $mean;
    pgenv($xplot_low, $xplot_hig, 0.0, $yplot_hig, 0, 0) || warn "pgenv-plotRdist says $!\n";
    $txt = sprintf "<R> = %.2f", $meanR; 
    $ytxt = "N = $numTrades";
    pglabel("$txt", "$ytxt", "$tick - $unique");
    #pgslw(int(300/$numx)); # Set line width 
    pgslw(1);
    pgsci(12);
    pgsfs(1); # fill is true
    for ($i = 0; $i < $numx; $i++) {
        if ($yr[$i] > 0) {
#            pgrect($xr[$i]-0.4, $xr[$i]+0.4, 0.0, $yr[$i]);
            pgrect($xr[$i]+0.1, $xr[$i]+0.9, 0.0, $yr[$i]);
        }
    }
    pgslw($linewidth);
    pg_plot_vertical_line($meanR, 2, 15);
    pgsch(0.8);
    $xtxt = sprintf "Exp = %.2f+/-%.2f, SQ = %.2f, MaxDD = %.1f%", $meanR, $sigma, $sq, $maxdd*100.0;
    pgmtext('T', -2.1, 0.98, 1, "$system, $sysInitStop, $sysStop"); # lower right corner
    pgmtext('T', -1.0, 0.98, 1, "$xtxt"); # lower right corner
    pgmtext('T', 1.0, 0.98, 1, "$comment") if ($opt_c || $opt_C); # comment in upper right corner
    sleep 2 unless ($opt_p);
    pgend;
}

sub backpopulate4plot {
    # not using strict; sharing variables with main program
    my $xdays = shift;
    my @dum;
    my ($d, $y);
    my @pdays;
    my $nd;

    if ($xdays > 0) {
        @dum = `display_indicator.pl --end $day --nb-item=$xdays I:Prices $tick`;  # get the correct dates
        ($d, $y) = extractIndicatorValues(@dum);
        @pdays = reverse @$d;
#        @pdays = @$d;
        $nd = @pdays;
        for ($i = 0; $i < $nd; $i++) {
            $price = `sqlite3 "$dbfile" "SELECT day_open, day_high, day_low, day_close \\
                                           FROM stockprices \\
                                           WHERE symbol = '$tick' \\
                                           AND date = '$pdays[$i]' \\
                                           ORDER BY date \\
                                           DESC"`;
            chomp($price);
            @pp = split /\|/, $price;  # close price in pp[3]
#            push @xx, $numdays - ($nd - $i); print "pushed ",$numdays - ($nd - $i), " = $pdays[$i]\n";
            push @xx, $numdays - ($i); # print "pushed ",$numdays - ($i), " = $pdays[$i]\n";
            push @yy, $pp[3]; push @open, $pp[0]; push @low, $pp[2]; push @high, $pp[1];
    #		push @ss, undef  # adding values here, plot after selling...
        }
    }

}

sub forwardpopulate4plot {
    # not using strict; sharing variables with main program
    my $xafter = shift;
    my @dum;
    my ($d, $y);
    my @pdays;
    my $nd;

    if ($xafter > 0) {
        $xafter++;
        @dum = `display_indicator.pl --start $day --nb-item=$xafter I:Prices $tick`;  # get the correct dates
        $nd = @dum;
        return if ($nd < 3);
        ($d, $y) = extractIndicatorValues(@dum);
        @pdays = reverse @$d;  # print "day is $numdays\n";
        $nd = @pdays;
        for ($i = 0; $i < $nd-1; $i++) {
            $price = `sqlite3 "$dbfile" "SELECT day_open, day_high, day_low, day_close \\
                                           FROM stockprices \\
                                           WHERE symbol = '$tick' \\
                                           AND date = '$pdays[$i]' \\
                                           ORDER BY date \\
                                           DESC"`;
            chomp($price);
            @pp = split /\|/, $price;  # close price in pp[3]
            push @xx, $numdays + ($nd - $i-1); #print "pushed ",$numdays + ($nd - $i-1), " = $pdays[$i]\n";
            push @yy, $pp[3]; push @open, $pp[0]; push @low, $pp[2]; push @high, $pp[1];
        }
    }

}

sub plotTrade {
    # not using strict; sharing variables with main program
    if ($opt_p) {
        #$device = "${btdir}p_${system}_${tick}_${unique}_${dayTrade}${tnote}.png/PNG";
        $device = "${btdir}p_${unique}_${dayTrade}_${tnote}.png/PNG";
        #print "using file = $device.\n";
    } else {
        $device = "/XSERVE";
    }
        # plot the direction of the market over the past 3-4 days, using OPEN and CLOSE prices
        # TODO: proper time interval. plus... should we rather use high/low?
        #
        chomp( @myf = reverse `sqlite3 "$dbfile" "SELECT day_open, day_close \\
								   FROM stockprices \\
								   WHERE symbol = '$tick' \\
								   AND date <= '$dayTrade' \\
								   ORDER BY date \\
								   DESC LIMIT 5"` );
		pop @myf; # to remove the current day in determining the direction; eliminates some non-star situations
        @mxf = ($xs[0]-4 .. $xs[0]-1); @xxf = (); @yyf = (); 
        for ($i=0; $i < 4; $i++) {
            @pf = split /\|/, $myf[$i];         #print "\n$myf[$i] -- @pf\n";
            push @xxf, ($mxf[$i]-0.2, $mxf[$i]+0.2);         #print "pushed X:", $mxf[$i]-0.2,", ", $mxf[$i]+0.2, "\n";
            push @yyf, ($pf[0], $pf[1]);             #print "pushed Y:", $pf[0], ", ", $pf[1], "\n";
        } 
        $nfit = @mxf;
        ($a, $siga, $b, $sigb) = linfit(\@xxf, \@yyf);  # $b is the slope
        @xfit = ($xs[0]-1, $xs[0]-$nfit);
        @yfit = ($a+$xfit[0]*$b, $a+$xfit[1]*$b);       #print "X: ",$xs[0]-1,",", $xs[0]-$nfit, " Y: ", $a+$xfit[0]*$b,",", $a+$xfit[1]*$b;
    &myInitGraph();
    $symbol = 17;
    $nume = @xx; 
    if ($nume < 2) {
        warn "bad: only $nume points in array...\n";
        pgend;
        return;
    }
    $nums = @xs;        #for ($ii=0; $ii<$nums; $ii++) {printf "$ii: %.2f %.2f\n",$xs[$ii],$ss[$ii]; }; exit;
    @all = (@yy, @ss, @addall);
    ($yplot_low, $yplot_hig) = low_and_high(@all); 
    ($xplot_low, $xplot_hig) = low_and_high(@xx);
    $mean = ( $xplot_hig - $xplot_low ) * 0.02;
    $xplot_hig += $mean;
    $xplot_low -= $mean;
    $mean = ( $yplot_hig - $yplot_low ) * 0.05;
    $yplot_hig += $mean;  $yplot_hig = sprintf "%.2f", $yplot_hig;
    $yplot_low -= $mean;  $yplot_low = sprintf "%.2f", $yplot_low; #print "$xplot_low, $xplot_hig, $yplot_low, $yplot_hig\n";
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, 0) || warn "pgenv here says: $!\n";
    $text = sprintf "R = %.2f", $gain/$risk;
    pglabel("Day of trade", "Price", "$tick - $dayTrade");
    pgmtext('B', -1.0, 0.3, 0, "$text");
    if ($pltext) {
        pgsci(11);
        pgsch($charheight*0.7); # Set character height 
        pgmtext('T', -1.1, 0.02, 0, "$pltext");
        pgsci(1);  # default colour
    }
    pgsch(0.8); pgsci(15);
    pgmtext('T', 2.1, 0.98, 1, "$system, $sysInitStop"); # lower right corner
    pgmtext('T', 1.0, 0.98, 1, "$sysStop"); # lower right corner
    pgsci(1);  # default colour
    pgslw(1); # Set line width 
    pg_plot_vertical_line($xs[0], 4, 15); 
    pg_plot_vertical_line($xs[-1], 4, 15); 
    $candlew = 0.31; # old: int(300.0 / $nume / 2.0) + 1;
    pgsfs(1); # fill is true
    for ($i = 0; $i < $nume; $i++) {
        pgsci(14);                          # color 15 = light gray
        pgslw(2); # Set line width 
        pgline(2, [$xx[$i],$xx[$i]], [$low[$i],$high[$i]]);
        if ($open[$i] > $yy[$i]) {
            pgsci(2); # red
        } else {
            pgsci(3); # green
        }
        pgslw(1); # Set line width 
        pgrect($xx[$i]-$candlew, $xx[$i]+$candlew, $open[$i], $yy[$i]); 
    }
    # plot the stop level 
    pgsci(15);                            # color 15 = light gray
    pgslw($linewidth);
    pgline($nums,\@xs,\@ss);                   # plot the stop
    if ($intraday) {
        pgsci(6);                            # color 15 = light gray
        pgsls(4);
        $myin = "";
        $myin = $ohlc0[0] if $whenVB eq "O";
        $myin = $ohlc1[3] if $whenVB eq "C";
        die "no value in $whenVB\n" unless $myin;
        pgline(2, [$xs[0]-0.9,$xs[0]+0.3], [$myin+$vbfac*$tr,$myin+$vbfac*$tr]);
        pgline(2, [$xs[0]-0.3,$xs[0]+0.9], [$myin-$vbfac*$tr,$myin-$vbfac*$tr]);
    }
    pgsci(11); # light blue
    pgsls(1);
    pgline(2, [$xs[0]-0.5,$xs[0]+0.5], [$inprice{$dayTrade},$inprice{$dayTrade}]);  # entry level 
    pgsci(11); # light blue
    pgline(2, [$xs[-1]-0.5,$xs[-1]+0.5], [$exitp,$exitp]);
    #pgmtxt('r', 1.1, 0.0, 0.0, "(xcol $opt_x, ycol $opt_y)") unless ($opt_f);
    pgslw(3); pgsci(8);
    pgline(2, \@xfit, \@yfit);  # the linear fit
    #print " - plot on $dayTrade done - ";
    &pg_take_x_from_graph() if ($opt_i);  # waits for right mouse click or "a" key
    pgend || warn "pgend on $device says: $!\n";
    return;
#exit;
}

sub plotRvsIndicators{
    # not using strict; sharing variables with main program
    if ($opt_p) {
        $device = "${btdir}plot_${tick}_${unique}_RwInd.png/PNG";
    } else {
        $device = "/XSERVE";
    }
    &myInitGraph();
    my $num = @sym;
    ($yplot_low, $yplot_hig) = low_and_high(@ind2); 
    ($xplot_low, $xplot_hig) = low_and_high(@ind1);
    $mean = ( $yplot_hig - $yplot_low ) * 0.05;
    $yplot_hig += $mean; $yplot_low -= $mean;
    $mean = ( $xplot_hig - $xplot_low ) * 0.05;
    $xplot_hig += $mean; $xplot_low -= $mean;
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, 0);
    my $xtxt = "$nameInd1"; 
    pglabel("$xtxt", "$nameInd2", "$tick - $unique");
    for ($i = 0; $i < $num; $i++) {
        pgsci($col[$i]);
        pgpoint(1, $ind1[$i], $ind2[$i], $sym[$i]);
    }
    pgsch(0.8); pgmtext('T', 1.0, 0.98, 1, "$comment") if ($opt_c || $opt_C); # comment in upper right corner
    pgsch($charheight); # Set character height 
    pgend;
    sleep 2 unless ($opt_p);
}

sub populatePlotArrays {
    # for the plotting of R color and size coded as function of two indicator values
    my ($sym, $col);
    if ($rmult{$dayTrade} <= 0) {
        $col = 2;
    } else {
        $col = 3;
    }
    $col{$dayTrade} = $col;
    push @col, $col;
    if ($rmult{$dayTrade} > 8.0) {
        $sym = 27;
    } elsif ($rmult{$dayTrade} > 6.0) {
        $sym = 26;
    } elsif ($rmult{$dayTrade} > 4.0) {
        $sym = 25;
    } elsif ($rmult{$dayTrade} > 3.0) {
        $sym = 24;
    } elsif ($rmult{$dayTrade} > 2.0) {
        $sym = 23;
    } elsif ($rmult{$dayTrade} > 1.0 || $rmult{$dayTrade} < -1.0) {
        $sym = 22;
    } else {
        $sym = 21;
    }
    $sym{$dayTrade} = $sym;
    push @sym, $sym;
    if ($nameInd1 && $nameInd2) {
        # populate the two arrays @ind1 and @ind2 with indicator values
        @my1 = getIndicator($tick, $dbfile, $nameInd1, 0, $dayTrade);
        @my2 = getIndicator($tick, $dbfile, $nameInd2, 0, $dayTrade);
        push @ind1, $my1[0];
        push @ind2, $my2[0];
    }
}

# ----

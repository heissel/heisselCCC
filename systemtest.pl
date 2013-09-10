#!/usr/bin/perl -I/Users/tdall/copyExecs
# 
# generate backtest using a stepping procedure trhough calls to scan.pl
#
# TODO:  make $margin work (for CFD trading)
# TODO:  calc value of portfolio each day + calc value of buy&hold each day

# arg 1 = system file (without .gtsys)
# arg 2 = ticker file
# arg 3 = starting date
# arg 4 = end date
# [-P] do NOT make plots for each signal

use Carp;
use Getopt::Std;
use GD::Graph::points;
require "utils.pl";

getopts(P);
@arg = @ARGV;
if ($opt_P) {
	$plots = "-P";
} else {
	$plots = "";
}

$path = "/Users/tdall/geniustrader/";
$dbfile = "/Users/tdall/geniustrader/traderThomas";
$btdir = "/Users/tdall/geniustrader/Backtests/";
$whichway = "";
$opentrade = "";
%possize = (); %stop = (); %inprice = (); %direction = ();
$cash = 10000.0; $margin = 1.0; 
$riskP = 0.01; $stopDays = 3; $pvalue = $cash;  $fee1way = 5.90;
open SYS, "<${path}$arg[0].gtsys";
while ($in = <SYS>) {
	next unless $in =~ /stop days: (\d+)$/;
	$stopDays = $1;
}
close SYS;

# get the range of valid dates - ugly hack, but it works...
@date = `sqlite3 "$dbfile" "SELECT date \\
									   FROM stockprices \\
									   WHERE symbol = 'BMW.DE' \\
									   ORDER BY date \\
									   DESC"`;
chomp(@date); # contains the dates with most recent first

# only one ticker symbol for now...
open TICK, "<${path}$arg[1].tick";
$tick = <TICK>;
chomp($tick);
close TICK;

# buy & hold result
$p1 = `sqlite3 "$dbfile" "SELECT day_close \\
									   FROM stockprices \\
									   WHERE symbol = '$tick' \\
									   AND date = '$date[-1]' \\
									   ORDER BY date \\
									   DESC"`;
$p2 = `sqlite3 "$dbfile" "SELECT day_close \\
									   FROM stockprices \\
									   WHERE symbol = '$tick' \\
									   AND date = '$date[0]' \\
									   ORDER BY date \\
									   DESC"`;
$resBHfull = int ($cash / $p1) * ($p2 - $p1) + $cash - 2*$fee1way;
$resBHrisk = int ($cash * $riskP / $p1) * ($p2 - $p1) + $cash - 2*$fee1way;

# main loop, day by day, look for signals
#
$numdays = 0;
$numtrades = 0;
$indexday = 0;
open DATA, ">${btdir}data_$arg[0]_$arg[1]_$arg[2]_$arg[3].txt" or die "daw48";
open TRADE, ">${btdir}trades_$arg[0]_$arg[1]_$arg[2]_$arg[3].txt" or die "msttr52r";
print TRADE "ADX <2> <5>  ATR <2> <5>  MACD <2> <5>  Trade#  tick  l/s  shares  day-in price-in day-out price-out gain%  duration\n";
open OUT, ">${btdir}summary_$arg[0]_$arg[1]_$arg[2]_$arg[3].txt" or die "a83mnmn0112";
print OUT "System $arg[0] with stopDays=$stopDays, Portfolio = $pvalue, risk% = ";
printf OUT "%3d\n", $riskP*100;
@datein = reverse @date;
foreach $day (@datein) {
    $indexday++;
	next if ($day lt $arg[2] || $day gt $arg[3]);
	print "$day: ";
	$numdays++;
	$price = `sqlite3 "$dbfile" "SELECT day_open, day_high, day_low, day_close \\
									   FROM stockprices \\
									   WHERE symbol = '$tick' \\
									   AND date = '$day' \\
									   ORDER BY date \\
									   DESC"`;
	@p = split /\|/, $price;
	($min, $max) = low_and_high(@p);  
	printf DATA "$day %4.4s %5.2f ", $numdays, $p[3]; 
	if ($opentrade) {  # use $direction{$tick} to allow for more open positrions/ticks
		# checking first if we've been stopped out... need to modify if more than one tick...
		printf "min / max of day = %.2f / %.2f\n", $min, $max;
		if ( ($direction{$tick} eq "long" && $min < $stop{$tick}) || ($direction{$tick} eq "short" && $max > $stop{$tick}) ) {
			printf "Stopped out of $direction{$tick} position in $tick at %.2f - ", $stop{$tick};
			printf OUT "$day:\nStopped out of $direction{$tick} position in $tick at %.2f - ", $stop{$tick};
			($gain, $stop) = exitTrade($tick, $dbfile, $direction{$tick}, $cash, $margin, $inprice{$tick}, $possize{$tick}, $day, $stop{$tick});
			die "Error in stop: $stop{$tick} vs $stop\n" unless ($stop{$tick} == $stop);
			printf "Gain = %.2f at reward/risk of %.2f", $gain, $gain/$risk;
			printf OUT "Gain = %.2f at reward/risk of %.2f\n", $gain, $gain/$risk;
			# recording the indicator values:
			($adx, $adx2, $adx5, $atr, $atr2, $atr5, $macd, $macd2, $macd5) = getIndicators($tick, $day, $datein[$indexday-5]);
			$dum = $numdays - $dayoftrade;
			printf TRADE "$day %7.2f %5.2f%", $stop{$tick}, $gain*100.0/$pvalue;
			printf TRADE " %3.3s\n", $numdays - $dayoftrade;
			$cash += ($gain + $inprice{$tick} * $possize{$tick} * $margin - $fee1way);
			$pvalue += ($gain - $fee1way);
			$possize{$tick} = "";  $stop{$tick} = "";  $inprice{$tick} = "";  $opentrade = "";
			printf OUT "Cash = %.2f; Portfolio value = %.2f\n", $cash, $pvalue;
		}
	}
	system "/Users/tdall/geniustrader/Scripts/scan_daily.pl -b $plots $arg[0] $arg[1] $arg[1] $day >/dev/null 2>&1";
	# now check the file...
	open IN, "<${btdir}signals_$arg[0]_$day.outscan" or carp "Warning: File for $day is missing!\n";
	$what = "";
	while ($in = <IN>) {
		if ($in =~ /^Entry/) {
			$what = "entry";
		} elsif ($in =~ /^Exit/) {
			$what = "exit";
		} elsif ($in =~ /Signals/ && $what) {
		    next unless $in =~ /$tick/;  # ok to use file with more ticks...
			$in =~ /$what signal (\w+)/;
			$whichway = $1;   # long or short
			#print "Seeing a $whichway $what signal. ";
			if ($opentrade eq $whichway && $what =~ /exit/) {   # opentrad is either "long" or "short" or "".
				print "Will exit a $whichway trade.";
				print OUT "$day: Will exit a $whichway trade. ";
				($gain, $exitp) = exitTrade($tick, $dbfile, $opentrade, $cash, $margin, $inprice{$tick}, $possize{$tick}, $day);
				$cash += ($gain + $inprice{$tick} * $possize{$tick} * $margin - $fee1way);
				$oldpvalue = $pvalue;
				$pvalue += ($gain - $fee1way);
				printf TRADE "$day %7.2f %6.3f%", $exitp, $gain*100.0/$oldpvalue;
				printf TRADE " %3.3s\n", $numdays - $dayoftrade;
                printf "Gain = %.2f at reward/risk of %.2f\n", $gain, $gain/$risk;
				$opentrade = "";
				$possize{$tick} = "";  $stop{$tick} = ""; $direction{$tick} = "";
			} elsif (! $opentrade && $what =~ /entry/) {
				print "Will enter a $whichway trade. ";
				printf OUT "$day: Will enter a $whichway trade. ";
				$opentrade = $whichway;  $direction{$tick} = $whichway;
				$risk = $riskP * $cash;
				($inprice{$tick}, $possize{$tick}, $stop{$tick}, $posprice) = enterTrade($tick, $dbfile, $opentrade, $cash, $margin, $risk, $stopDays, $day);
				$cash -= ($posprice + $fee1way);
				$pvalue -= $fee1way;
				$numtrades++;
				$dayoftrade = $numdays;
				($adx, $adx2, $adx5, $atr, $atr2, $atr5, $macd, $macd2, $macd5) = getIndicators($tick, $day, $datein[$indexday-5]);
				printf TRADE "%.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f ", $adx, $adx2, $adx5, $atr, $atr2, $atr5, $macd, $macd2, $macd5;
				printf TRADE "$numtrades:\t%7.7s %-5.5s %4.4s $day %7.2f ", $tick, $opentrade, $possize{$tick}, $inprice{$tick};
			}
		}
	}
	close IN;
	if ($opentrade) {  # use $direction{$tick} to allow for more open positrions/ticks
		printf "Is $possize{$tick} $opentrade in $tick. Entry = %.2f, stop at %.2f", $inprice{$tick}, $stop{$tick};
		printf OUT "\n$day: Is $possize{$tick} $opentrade in $tick. Entry = %.2f, stop at %.2f\n", $inprice{$tick}, $stop{$tick};
	}
	print "\n";
	printf "Cash = %.2f; Portfolio value = %.2f\n", $cash, $pvalue;
	printf OUT "Cash = %.2f; Portfolio value = %.2f\n", $cash, $pvalue if ($opentrade);
	printf DATA "%9.2f %9.2f\n", $cash, $pvalue;
} # end of main loop
# exit any remaining positions for comparison
if ($opentrade) {
	($gain,$exitp) = exitTrade($tick, $dbfile, $opentrade, $cash, $margin, $inprice{$tick}, $possize{$tick}, $arg[3]);
	$cash += ($gain + $inprice{$tick} * $possize{$tick} * $margin);
	printf TRADE "$arg[3] %7.2f %6.3f%", $exitp, $gain*100.0/$pvalue;  # here we don't put margin, but maybe we should...
	printf TRADE " %3.3s\n", $numdays - $dayoftrade;
	$pvalue += $gain;
}

# make a summary
printf "Buy and hold values: fully invested = %.2f; risk frac invested = %.2f\n", $resBHfull, $resBHrisk;
printf "System result: Portfolio value at end   = %.2f\n", $pvalue;
printf OUT "Buy and hold values: fully invested = %.2f; risk frac invested = %.2f\n", $resBHfull, $resBHrisk;
printf OUT "System result:       value at end   = %.2f\n", $pvalue;
close OUT;
close DATA;
close TRADE;

# make the plot of indicators according to gain or loss:
#
open TRADE, "<${btdir}trades_$arg[0]_$arg[1]_$arg[2]_$arg[3].txt" or die "readttr52r";
$in = <TRADE>;
@wins = (); @loss = (); @x = ();
$xidx = 3; $yidx = 0;  # sets which to use for x and y axis 
while ($in = <TRADE>) {
    @in = split /\s+/, $in;
    push @x, $in[$xidx];
    if ($in[17] =~ /-\d/) {  # a loss...
        push @loss, $in[$yidx];
        push @wins, -9999.99;
    } else {  # a positive gain    
        push @loss, -9999.99;
        push @wins, $in[$yidx];
    }
}
@data = (\@x, \@loss, \@wins);
$grp = GD::Graph::points->new(600,600);
my $grpl = $grp->plot(\@data) or die $grp->error;
open(IMG, '>file2.png') or die $!;
binmode IMG;
print IMG $grpl->png;
close IMG;

#exit();
# making the overall plot for the entire period
#
($system, $arrowIn1, $exit, $stop, $mm, $tradefilter) = getSystemAndArrow("/Users/tdall/geniustrader/$arg[0].gtsys");
$graph_std = initMyVar();
$graph = "graphic.pl --file /Users/tdall/geniustrader/Backtests/backtest_$tick.gconf --out '/Users/tdall/geniustrader/Backtests/chart_$tick.png' $tick";

open GCONF, ">/Users/tdall/geniustrader/Backtests/backtest_$tick.gconf";
print GCONF "# file for graphics.pl made by systemtest.pl, covering full period\n#\n";
print GCONF "# $graph\n";

print GCONF "--start=$arg[2]
--end=$arg[3]
--timeframe=day
--title=$arg[0]: %c
--type=candle
#--logarithmic
--volume
--volume-height=80
--add=BuySellArrows($arrowIn1)
$graph_std";
close GCONF;

#print "$graph\n";
$outg = system $graph;


# ----

sub getIndicators {
    # ($adx, $adx2, $adx5, $atr, $atr2, $atr5, $macd, $macd2, $macd5) = getIndicators($tick, $day2, $date[$indexday-5])
    #  note:  display_indicator.pl --start 2012-04-15 --end 2012-04-23 I:RSI BMW.DE '9 {I:Prices CLOSE}'
    use strict;
    my ($tick, $day2, $day1) = @_;
    my @res;
    my @x = (1, 2, 3, 4, 5); # x-axis for linear fit
    my @y = ();
    my ($adx, $adx2, $adx5, $atr, $atr2, $atr5, $macd, $macd2, $macd5);
    my ($i, $in, $a, $siga, $sigb);

    # ADX: (4 lines per day; ADX, +DMI, -DMI, DMI)
    # 
    @res = `display_indicator.pl --start $day1 --end $day2 I:ADX $tick`;
    shift @res;
    for ($i = 0; $i <= 4; $i++) {
        $in = shift @res;
        $in =~ /.* = (\d+.\d+)/; push @y, $1;
        shift @res; shift @res; shift @res; 
    }
#    print "x-arr: @x\ny-arr: @y\n"; exit;
    ($a, $siga, $adx5, $sigb) = linfit( \@x, \@y );
    $adx = $y[4];
    $adx2 = ($y[4] - $y[3]);
    @y = ();
    # ATR:
    #
    @res = `display_indicator.pl --start $day1 --end $day2 I:ATR $tick`;
    shift @res;
    for ($i = 0; $i <= 4; $i++) {
        $in = shift @res;
        $in =~ /.* = (\d+.\d+)/; push @y, $1;
    }
    ($a, $siga, $atr5, $sigb) = linfit( \@x, \@y );
    $atr = $y[4];
    $atr2 = ($y[4] - $y[3]);
    @y = ();
    # MACD: (3 lines per day; MACD, MACD-Signal, MACD-Diff.)
    #
    @res = `display_indicator.pl --start $day1 --end $day2 I:MACD $tick`;
    shift @res;
    for ($i = 0; $i <= 4; $i++) {
        $in = shift @res;
        $in =~ /.* = (-*\d+.\d+)/; push @y, $1;  # remember the -* for indicators that could be negative
        shift @res; shift @res; 
    }
    ($a, $siga, $macd5, $sigb) = linfit( \@x, \@y );
    $macd = $y[4]; $i = @y; 
    $macd2 = ($y[4] - $y[3]);
    @y = ();
    
    return ($adx, $adx2, $adx5, $atr, $atr2, $atr5, $macd, $macd2, $macd5);
}



sub exitTrade {
	# ($gain, $price) = exitTrade($tick, $db, $whichway, $cash, $margin, $inprice, $psize, $date, $stop);
	# $stop is optional; if given it will be used as exit price
	use strict;
	my ($tick, $db, $whichway, $cash, $margin, $inprice, $psize, $date, $stop) = @_;
	my ($price, $gain);

	if ($stop) {
		$price = $stop;
	} else {
		$price = `sqlite3 "$db" "SELECT day_close \\
										   FROM stockprices \\
										   WHERE symbol = '$tick' \\
										   AND date = '$date' \\
										   ORDER BY date \\
										   DESC"`;
		chomp($price);  #print "-- $tick -- $date -- $db -- ";
	}
	if ($whichway eq "long") {
		$gain = ($price - $inprice) * $psize;
	} elsif ($whichway eq "short") {
		$gain = ($inprice - $price) * $psize;
	} else {	
		print "ERROR: must call with either 'long' or 'short'\n";
		exit();
	}
	#print "\n-- gain = $gain, IN = $inprice, OUT = $price; $psize stk.\n";
	return ($gain, $price);
}

sub enterTrade {
	# ($inprice, $possize, $stop, $posprice) = enterTrade($tick, $db, $whichway, $cash, $margin, $risk, $stop_days, $date);
	# e.g. enterTrade('BMW.DE', 'traderThomas', 'long', 9850.0, 0.05, 110.0, 5, "2011-04-06")
	# later could have other prices, e.g., 'last' or 'open' - for now only 'close' price
	use strict;
	my ($tick, $db, $whichway, $cash, $margin, $risk, $stop_days, $date) = @_;
	my ($psize, $stop, $pprice, $price, $in, $min, $max, $np, $num, $d);
	my @all;
	my @p; 
	my @prices;

	my $price = `sqlite3 "$db" "SELECT day_close \\
									   FROM stockprices \\
									   WHERE symbol = '$tick' \\
									   AND date = '$date' \\
									   ORDER BY date \\
									   DESC"`;
	chomp($price);
	my @all = `sqlite3 "$db" "SELECT day_open, day_high, day_low, day_close, date \\
									   FROM stockprices \\
									   WHERE symbol = '$tick' \\
									   ORDER BY date \\
									   DESC"`;
	@prices = ();
	$num = 0;
	foreach $in (@all) {
		@p = split /\|/, $in;
		$d = pop @p; chomp($d);
		next if ($d gt $date);
		push @prices, @p;
		$num++;
		last if ($num >= $stop_days);
	}
	$np = @prices;
	($min, $max) = low_and_high(@prices); #print " $num price days, from $d to $date\n";
	
	if ($whichway eq "long") {
		$psize = int ($risk / ($price - $min));
		$stop = $min;
	} elsif ($whichway eq "short") {
		$psize = int ($risk / ($max - $price));
		$stop = $max;
	} else {
		print "ERROR: must call with either 'long' or 'short'\n";
		exit();
	}
	$pprice = $psize * $price * $margin;
	return ($price, $psize, $stop, $pprice);
}

#!/usr/bin/perl -I/Users/tdall/copyExecs
# 
# generate backtest and graphical plots of the test

# arg 1 = system file (without .gtsys)
# arg 2 = ticker
# arg 3 = starting date
# arg 4 = end date
require "utils.pl";
@arg = @ARGV;

$graph_std = initMyVar();

($system, $arrowIn1, $exit, $stop, $mm, $tradefilter) = getSystemAndArrow("/Users/tdall/geniustrader/$arg[0].gtsys");



$backtest = "backtest.pl \\
	--broker=SelfTrade \\
	--start=$arg[2] \\
	--end=$arg[3] \\
	--graph=\"/Users/tdall/geniustrader/Backtests/$arg[1].png\" \\
	--display-trades \\
	--html \\
	--system=\"$system\" \\
	--close-strategy=\"$exit\" \\
	--close-strategy=\"$stop\" \\
	--trade-filter=\"$tradefilter\" \\
	--money-management=\"$mm\" \\
	--order-factory=\"SignalClosingPrice\" \\
	$arg[1] > /Users/tdall/geniustrader/Backtests/$arg[1].html
";
$backtestTxt = "backtest.pl \\
	--broker=SelfTrade \\
	--start=$arg[2] \\
	--end=$arg[3] \\
	--display-trades \\
	--system=\"$system\" \\
	--close-strategy=\"$exit\" \\
	--close-strategy=\"$stop\" \\
	--trade-filter=\"$tradefilter\" \\
	--money-management=\"$mm\" \\
	--order-factory=\"SignalClosingPrice\" \\
	$arg[1] > /Users/tdall/geniustrader/Backtests/$arg[1].txt
";

print "$backtest\n";
$doit = system $backtest;
$doit2 = system $backtestTxt;

# use the backtest .txt-file to plot entry and exit for each of the trades
#
open BT, "</Users/tdall/geniustrader/Backtests/$arg[1].txt";
$stillRunning = 1;
while ($stillRunning) {
	$in = <BT>;
	next unless $in =~ /^History of the port/;
	$in = <BT>;  #  the --- line
	while ($in = <BT>) {
		if ($in =~ /^Long .* \((\d+)\) on/) {
			$num = $1; $whichway = "long";
		} elsif ($in =~ /^Short .* \((\d+)\) on/) {
			$num = $1; $whichway = "short";
		} else {
			#print "IN is: $in ::Done - I think...\n";
			$stillRunning = 0;
			last;
		}
		$entry = <BT>; $exit = <BT>;
		$entry =~ s/^\s+//g;
		@entry = split /\s+/, $entry;
		$exit =~ s/^\s+//g;
		@exit = split /\s+/, $exit;
		print "Trade number $num - $whichway\n";		
		$graph = "graphic.pl --file /Users/tdall/geniustrader/Backtests/$arg[1]_$arg[0]_$entry[0].gconf --out '/Users/tdall/geniustrader/Backtests/chart_$arg[1]_$arg[0]_$entry[0].png' $arg[1]";
		open GCONF, ">/Users/tdall/geniustrader/Backtests/$arg[1]_$arg[0]_$entry[0].gconf";
		print GCONF "# file for graphics.pl made by systemtest.pl, covering full period\n#\n";
		print GCONF "# $graph\n";
#		print GCONF "--start=$entry[0]
		print GCONF "--nb-item=100
--end=$exit[0]
--timeframe=day
--title=$arg[0], trade $num, $whichway: %c
--type=candle
#--logarithmic
--volume
--volume-height=80
--add=BuySellArrows($arrowIn1)
$graph_std";
		close GCONF;
		$outg = system $graph;
#		print "$graph\n";

		# now do the backtest again, but with proper entry and exit
		# $opt_p gives number of past days to evaluate the high/low for initial stop
		#  ... no.... will not work, no way to follow the trades that are 'saved' and not stoppped oput early...
		# will have to do it with scan.pl -style
	}
}

# making the overall plot for the entire period
#
$graph = "graphic.pl --file /Users/tdall/geniustrader/Backtests/$arg[1].gconf --out '/Users/tdall/geniustrader/Backtests/chart_$arg[1].png' $arg[1]";

open GCONF, ">/Users/tdall/geniustrader/Backtests/$arg[1].gconf";
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


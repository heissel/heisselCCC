#!/usr/bin/perl -I/Users/tdall/copyExecs
#
# scans all stocks in database by selecting the .tick file. Reads the .gtsys file
# and generates a temporary scan-file that it uses.  It outputs plots of all the potential
# new positions, and generates exit signals for existing positions from the appropriate 
# .tick file (right now: myOpen.tick)
#
# -b : backtesting mode; don't wait for the daily update
# -P : do NOT make plots for each signal
#
# scan_daily.pl <system>  <market/tick>  <open-tick>  <YYYY-MM-DD>

use Getopt::Std;
require "utils.pl";

getopts(bP);

if ($opt_P) {
	$makeplot = 0;
} else {
	$makeplot = 1;
}

@arg = @ARGV;
$narg = @arg;
if ($narg == 3) {
	$arg[3] = `date "+%Y-%m-%d"`;
	chomp($arg[3]);
} elsif ($narg < 3) {
	print "scan_daily.pl <system>  <market/tick>  <open-tick>  <YYYY-MM-DD>\n";
	exit();
}

$path = "/Users/tdall/geniustrader/";
$working = $path . "Scripts/";
if ($opt_b) {
	$daily = $path . "Backtests/";
} else {
	$daily = $path . "DailyScan/";
}
$tickfile = $path . $arg[1] . ".tick";
$portfile = $path . $arg[2] . ".tick";
chdir $working;  # needed for the cronjob to work properly


# only run if the database update was successful, otherwise wait...
# skip this check if we're doing backtesting.
unless ($opt_b) {
	$niter = 0;
	while ($niter < 30) {
		if (-e "${daily}ok.$arg[3]") {
			#print "yep...\n";
			#unlink "${daily}ok.$arg[3]";
			last;
		} else {
			$niter++;
			sleep 120;
			$dum = system "touch ${daily}warning_scan.$arg[3]" if $niter == 29;
		}
	}
	exit if (-e "${daily}warning_scan.$arg[3]");   # somthing went wrong...
}

# generate the temporary .scan file
#
$sysfile = "$path" . "$arg[0].gtsys";
&makeScanFile($sysfile, $arg[0], "${working}tmpscan.scan");

# Now call scan.pl with this file and the supplied market/tick file
#
$outfile = $working . "out_" . $arg[3] . ".scanout";
$result = system "scan.pl $tickfile --nb-item=150 $arg[3] ${working}tmpscan.scan > $outfile";
print "Done scanning. Extracting relevant signals...\n";


# Now analyze the output and extract:
# 1. entry signals
# 2. exit signals for open positions
$outscan = $daily . "signals_$arg[0]_$arg[3].outscan";  #print "will write to $outscan\n";
&parseScanOutput($sysfile, $arg[0], $arg[3], $tickfile, $portfile, $outfile, $outscan, $daily, $makeplot);
`touch ${daily}done.$arg[3]` unless ($opt_b);

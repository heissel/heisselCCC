#!/usr/bin/perl 
#
# called by cron every day to update the stock database. Will wait until after XETRA close
# before exiting the script.  Afterwards, scan_daily.pl can be run.
#
use Getopt::Std;
getopts(n);

$path = "/Users/tdall/geniustrader/";
$working = $path . "Scripts/";
$daily = $path . "DailyScan/";
$db = "/Users/tdall/geniustrader/traderThomas";
chdir $working;  # needed for the cronjob to work properly
$tick = "BMW.DE";

$today = `date "+%Y-%m-%d"`;
chomp($today);
$niter = 0;
$waiting = 1;
$okfile = "${daily}ok.$today";
$waitfile = "${daily}wait.${today}";
`touch $waitfile`;

$q0 = `sqlite3 "$db" "SELECT * \\
						   FROM stockprices \\
						   WHERE symbol = '$tick' \\
						   AND date = '$today' \\
						   ORDER BY date \\
						   DESC LIMIT 1"`;
chomp($q0);

if ($opt_n) {
	while ($waiting) {
		# compare with current result - if changed, then we're still waiting
		sleep 120;
		`beancounter --dbsystem SQLite --dbname /Users/tdall/geniustrader/traderThomas update >/dev/null 2>&1`;
		$q1 = `sqlite3 "$db" "SELECT * \\
							   FROM stockprices \\
							   WHERE symbol = '$tick' \\
							   AND date = '$today' \\
							   ORDER BY date \\
							   DESC LIMIT 1"`;
		chomp($q1);
		if ($q1 ne $q0) {
			#print "should be different:\nq0 = $q0\nq1 = $q1\n";
			$niter++;
			$q0 = $q1;
			next;
		} else {
			#print "should be equal:\nq0 = $q0\nq1 = $q1\n";
			`rm $waitfile`;
			`touch $okfile`;
			$waiting = 0;
			last;
		}
	}
} else {
	# this is deprecated - use always with -n
	#
	$msg = system "beancounter --dbsystem SQLite --dbname /Users/tdall/geniustrader/traderThomas update";
	$timestamp1 = getTime("BMW.DE");
	while ($waiting) {
		sleep 120;
		$msg = system "beancounter --dbsystem SQLite --dbname /Users/tdall/geniustrader/traderThomas update";
		$timestamp2 = getTime("BMW.DE");
		if ($niter > 5) {
			$waiting = 0;
			$ok = system "touch ${daily}okNOT.$today";
		} elsif ($timestamp1 ne $timestamp2) {
			$timestamp1 = $timestamp2;
			$niter++;
		} else {
			$waiting = 0;
			$ok = system "touch ${daily}ok.$today";
		}
	}
}

# ------

sub getTime {
	my $t = shift;
	my @msg;
	my ($d, $time);
	
	@msg = `beancounter --dbsystem SQLite --dbname /Users/tdall/geniustrader/traderThomas quote $t`;
	($d, $time) = split /\s+/, $msg[4];
	#print "Found: $time\n";
	return $time;
}


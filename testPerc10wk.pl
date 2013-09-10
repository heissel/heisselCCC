#!/usr/bin/perl -I/Users/tdall/copyExecs
# give name of file with ticks on the command line
# should per default be 'all4percentWk.tick' (all German stocks)

require "utils.pl";
require "pg_utils.pl";
require "trader_utils.pl";
$dbfile = "/Users/tdall/geniustrader/traderThomas";
$path = "/Users/tdall/geniustrader/";

($tfile, $today) = @ARGV;
# $tfile is stem of filename (without .tick)
open IN, "<$path${tfile}.tick" || die "sabb337789s";
chomp( @ticks = <IN> );
close IN;

if (-e "$path${tfile}.p10wk") {
	open P10, "<$path${tfile}.p10wk" || die "nsiz94havw344";
	chomp( @in = <P10> );
	($lim, $prev, $del, $sym, $box) = split /\s+/, $in[-1];
	close P10;
} else {
	$sym = 'x';
	$box = 100;
	$prev =100;
	$lim = "1990-01-01";
}

@date = reverse `sqlite3 "$dbfile" "SELECT date \\
                               FROM stockprices \\
                               WHERE symbol = 'BMW.DE' AND date<='$today' AND date>'$lim' \\
                               ORDER BY date DESC"`; 
chomp(@date);
open P10, ">>$path${tfile}.p10wk" || die "mw62aazkr70023vhy";

foreach $day (@date) {
	$total = 0;
	$above = 0;
	foreach $tick (@ticks) {  
		# find SMA(50) which corresponds to 10 weeks SMA
		# print "processing $tick\n";
		$pc = 0; $sma = 0;
		chomp( $pc = `sqlite3 "$dbfile" "SELECT day_close \\
								   FROM stockprices \\
								   WHERE symbol = '$tick' AND date<='$day' \\
								   ORDER BY date DESC LIMIT 1"` );
		$sma = sma($tick, $dbfile, 50, $day);
		next unless ($pc && $sma);
		$total++;
		if ($pc > $sma) {
			$above++;
		}
	}
	$perc = $above*100.0/$total;
	# now check if we're adding another x/o or changing column  (later see if we exceed prev local max/min for a signal)
	if ($perc >= $box+2 && $sym eq 'x') {
		$box = int( $perc / 2.0) * 2;
	} elsif ($perc < $box-2 && $sym eq 'o') {
		$box = int( $perc / 2.0) * 2;
	} elsif ($perc >= $box+6 && $sym eq 'o') {
		$box = int( $perc / 2.0) * 2;
		$sym = 'x';
	} elsif ($perc <= $box-6 && $sym eq 'x') {
		$box = int( $perc / 2.0) * 2;
		$sym = 'o';
	}
	printf "$day: Perc10wk = %.1f, delta10wk = %.2f -- col=$sym box=$box\n", $perc, $perc-$prev;
	printf P10 "$day  %.1f  %.2f  $sym  $box\n", $perc, $perc-$prev;
	$prev = $perc;
}

close P10;
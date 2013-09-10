#!/usr/bin/perl
# example from http://souptonuts.sourceforge.net/readme_sqlite_tutorial.html
#

$dbfile = "/Users/tdall/geniustrader/traderThomas";
$tick = 'BAYN.DE';

$dum = `sqlite3 "$dbfile" "SELECT day_open, day_high, day_low, day_close, volume, date \\
									   FROM stockprices \\
									   WHERE symbol = '$tick' \\
									   AND date = '2012-04-05' \\
									   ORDER BY date \\
									   DESC LIMIT 30"`;

print $dum;


#!/usr/bin/perl
# example from http://souptonuts.sourceforge.net/readme_sqlite_tutorial.html
#

use DBI;
$dbfile = "/Users/tdall/geniustrader/traderThomas";
$tick = 'BAYN.DE';

$dbh = DBI->connect( "dbi:SQLite:$dbfile" ) || die "Cannot connect: $DBI::errstr";

$res = $dbh->selectall_arrayref( q( SELECT day_open, day_high, day_low, day_close, volume, date
									   FROM stockprices
									   WHERE symbol = '$tick'
									   ORDER BY date
									   DESC LIMIT 30 ) );

print @$res;

foreach( @$res ) {
foreach $i (0..$#$_) {
   print "$_->[$i] "
   }
print "\n";

}

$dbh->disconnect;

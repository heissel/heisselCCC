#!/usr/bin/perl 
#
# takes the ticker symbols from the file metioned on the command line (must have .tick extension)
# and pouplates the database for each ticker symbol using beancounter. 
#

my $tfile = shift;
$tickfile = $tfile . ".tick";
open TICK, "<$tickfile" or die "wu773";

while ($tick = <TICK>) {
	chomp($tick);
	$dum = system "beancounter --dbsystem SQLite --dbname /Users/tdall/geniustrader/traderThomas addstock $tick";
	$dum = system "beancounter --dbsystem SQLite --dbname /Users/tdall/geniustrader/traderThomas backpopulate --prevdate '8 years ago' --date 'today' $tick";
}

close, TICK;
#!/usr/bin/perl
#
$|=1;
$file = shift;
$db = "/Users/tdall/geniustrader/traderThomas";
$path = "/Users/tdall/geniustrader/";
chomp( $date = `date "+%Y-%m-%d"` );
chomp( $date1 = `date -v-1d "+%Y-%m-%d"` );

open TICK, "<${path}$file.tick";
@tick = <TICK>;
chomp(@tick);
close TICK;
$n = @tick;
print "$n entries...\n";

foreach $tick (@tick) {
    @q = `sqlite3 "$db" "SELECT date \\
                           FROM stockprices \\
                           WHERE symbol = '$tick' \\
                           ORDER BY date \\
                           DESC"`;
    $n = @q;
    chomp(@q);
	if ($n >= 2) {   # there is something in the database
        $last = pop @q;
        print "$tick: $n -- from $last to $q[0]\n"; # unless ($n > 1000 && ($q[0] eq $date || $q[0] eq $date1));
    } else { # nothing in the database - add the symbol and backpopulate
        `beancounter --dbsystem SQLite --dbname $db addstock $tick`;
        $out = `beancounter --dbsystem SQLite --dbname $db backpopulate --prevdate '13 years ago' --date 'today' $tick`;
        print "Added $tick.  Output from command: $out\n";
    }
}
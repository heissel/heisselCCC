#!/usr/bin/perl -I/Users/tdall/copyExecs
# give name of file with ticks on the command line

require "utils.pl";
require "pg_utils.pl";
require "trader_utils.pl";
$dbfile = "/Users/tdall/geniustrader/traderThomas";

if ($ARGV[0] =~ /tick/) {
    @ticks = <>;
} else {
    @ticks = ($ARGV[0]);
}

@dref = `sqlite3 "$dbfile" "SELECT date \\
                           FROM stockprices \\
                           WHERE symbol = 'IFX.DE' \\
                           ORDER BY date"`;
chomp(@dref);
@dref{@dref} = @dref;
print "$dref[0] is first day\n";
foreach $tick (@ticks) {
    @curr = ();
    %curr = ();
    chomp($tick);   
    print "processing $tick - ";
    @data = `sqlite3 "$dbfile" "SELECT date, day_open, day_high, day_low, day_close \\
                               FROM stockprices \\
                               WHERE symbol = '$tick' \\
                               ORDER BY date"`;
    $n = @data;
    print "$n entries\n";
    chomp(@data);
    @curr = `sqlite3 "$dbfile" "SELECT date \\
                               FROM stockprices \\
                               WHERE symbol = '$tick' \\
                               ORDER BY date"`;
#    if ($tick eq 'VOW3.DE') { print @curr; exit; }
    chomp(@curr);
    @curr{@curr} = @curr;
    foreach $day (@dref) {
#             if ($day eq '2012-08-24' && $tick eq 'VOW3.DE') {
#                 print "*** curr($day) = $curr{$day} - ";
#             }
        unless (exists $curr{$day}) {
            print "$tick on $day is missing!\n" if ($day gt '2004-04-08'); #$dref[0]);
        }
    }
    foreach $in (@data) {
        ($day, $po, $ph, $pl, $pc) = split /\|/, $in;
        @prices = ($po, $ph, $pl, $pc);
        unless (exists $dref{$day}) {
            print "$tick on $day but not in reference!\n";
        }
        if (  ($po == $pc && $po == $ph && $pc == $yc)  || $pc =~ /NULL/) {
            print "\t$day: $po - $ph - $pl - $pc no trading?\n";
            #`sqlite3 "$dbfile" "DELETE FROM stockprices WHERE date='$day' AND symbol='$tick'"`;
        }
        $max = max(@prices);
        $min = min(@prices);
        if ($max == $ph && $min == $pl) { 
            1;
        } else {
            print "\t$day: $po - $ph - $pl - $pc mismatch...\n";
        }
        $yc = $pc;
    }

}
#!/usr/bin/perl  -I/Users/tdall/copyExecs
use PGPLOT;
use Getopt::Std;
require "utils.pl";
#require "pg_utils.pl";
require "trader_utils.pl";
getopts('d:n:');
# -d delta
# -n bins

my $nbins = 2000;
my $tick = $ARGV[0];
my $day = $ARGV[1];
my %hday = (); my %dayindex = (); my %openp = (); my %closep = (); my %maxp = (); my %minp = (); my %volume = ();
if ($opt_n) {
    $nbins = $opt_n;
}
unless ($day) {
    chomp( $day = `date "+%Y-%m-%d"` );
}
$path = "/Users/tdall/geniustrader/";
$dbfile = "/Users/tdall/geniustrader/traderThomas";

($d, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $h_v) = readStockData($tick, $dbfile, $day);
@date = @$d;  %hday = %$h_d;  %dayindex = %$h_i;  %openp = %$h_o; %maxp = %$h_h;  %minp = %$h_l; %closep = %$h_c; %volume = %$h_v;
@p = (0,1,2);
$val0 = min(values %minp);
$valmax = max(values %maxp);
if ($opt_d) {
    $delta = $opt_d;
    $nbins = int(($valmax-$val0)/$delta);
} else {
    $delta = ($valmax-$val0)/$nbins;
}
$val0 =- $delta;
@binvalue = (); @bincount = ();
for ($i=0; $i<=$nbins; $i++) {
    push @binvalue, $val0 + $delta*$i;
    push @bincount, 0;
}

foreach $p (@p) {
    if ($p == 0) {
        %price = %closep;
    } elsif ($p == 1) {
        %price = %maxp;
    } elsif ($p == 2) {
        %price = %minp;
    }
    foreach $dy (@date) {
        $nlower = int(($minp{$dy}-$val0)/$delta - 1.0);
        $nupper = int(($maxp{$dy}-$val0)/$delta + 2.0);
        for ($i=$nlower; $i<=$nupper; $i++) {
            $val1 = $val0 + $delta * $i;
            $val2 = $val0 + $delta * ($i+1);
            if ($val1 < $price{$dy} && $price{$dy} <= $val2) {
                $bincount[$i]++; $bincount[$i+1]++;
            }
        }
    }
}
$mean = sum(@bincount)/$nbins;
$yplot_hig = max(@bincount);
$nume = @binvalue;
    my $font = 2;
    my $linewidth = 2;
    my $charheight = 1.0;
    pgbeg(0,$device,1,1); # || warn "pgbeg on $device says: $!\n"; # Open plot device 
    pgscf($font); # Set character font 
    pgslw($linewidth); # Set line width 
    pgsch($charheight); # Set character height 
    pgsci(1);  # default colour
    my $symbol = 17;
    pgenv($val0-$delta, $valmax+$delta, 0.0, $yplot_hig, 0, 0);# || warn "pgenv here says: $!\n";
    pglabel("Price", "Counts", "$tick level significance");
    pgmtext('T', 1.0, 0.98, 1, "Av = $mean, delta = $delta, Nbins = $nbins");
#    pgpoint($nume,\@binvalue,\@bincount,$symbol);
    pgline($nume,\@binvalue,\@bincount);
    pgend;

print "Threshold for significant level? ::: "; $lvcut = <STDIN>;
chomp($lvcut);

    $ntot = @date;  $nbars = $ntot;
    @open = (); @high = (); @low = (); @close = (); @xx = (); @pmove = (); @day = ();
    for ($i=1; $i<=$nbars; $i++) {
        push @open, $openp{$date[-$i]};
        push @high, $maxp{$date[-$i]};
        push @low, $minp{$date[-$i]};
        push @close, $closep{$date[-$i]};
        push @day, $date[-$i];
        unshift @xx, $i;
        next if ($openp{$date[-$i]} <= 0);
        push @pmove, ($maxp{$date[-$i]}-$minp{$date[-$i]})*100.0/$openp{$date[-$i]};
    }
    $nume = @open;
    @all = (@low, @high);
    ($yplot_low, $yplot_hig) = low_and_high(@all); 
    $xplot_low = -1; $xplot_hig = $nbars + 1;
    $avmove = sum(@pmove)/$nume;
    $sigmove = sigma($avmove,@pmove);
    $rangep = ($yplot_hig - $yplot_low)*100.0/(($yplot_hig + $yplot_low)/2.0);
    $trend = $avmove*$nbars/$rangep;

    pgbeg(0,$device,1,1); # || warn "pgbeg on $device says: $!\n"; # Open plot device 
    pgscf($font); # Set character font 
    pgslw($linewidth); # Set line width 
    pgsch($charheight); # Set character height 
    pgsci(1);  # default colour

    my $candlew = 0.31;
    pgsfs(1); # fill is true
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, 0);# || warn "pgenv here says: $!\n";
    pglabel("Day of trade", "Price", "$tick - $day");
    my $text = "<%" . sprintf("move> = %.1f +/- %.1f, sig/Av = %.2f, ${nbars}day-range = %.1f",$avmove,$sigmove,$sigmove/$avmove,$rangep) . "%, " . sprintf("Tscore = %.1f",$trend);
    pgmtext('T', 1.0, 0.3, 0, "$text");
    for ($i=0; $i<=$nbins;$i++) {
        if ($bincount[$i] >= $lvcut) {
            pgline(2,[$xplot_low, $xplot_hig],[$binvalue[$i],$binvalue[$i]]);
        }
    }
    for ($i = 0; $i < $nume; $i++) {
        pgsci(14);                          # color 15 = light gray
        pgslw(2); # Set line width 
        pgline(2, [$xx[$i],$xx[$i]], [$low[$i],$high[$i]]);
        if ($open[$i] > $close[$i]) {
#            pgsci(2); # red
            pgsci(14); # down day
        } else {
#            pgsci(3); # green
            pgsci(1); # up day
        }
        pgslw(1); # Set line width 
        pgrect($xx[$i]-$candlew, $xx[$i]+$candlew, $open[$i], $close[$i]); 
    }
    print "Chart of $tick [RET]"; $dum = <STDIN>;
    pgend;


# --------- subroutines ----------


sub readStockData {
    use strict;
    my ($tick, $dbfile, $day) = @_;
    my $c = @_; die "only $c elements to readStockData(), should be 3\n" unless ($c == 3);
    my %hday = (); my %dayindex = (); my %openp = (); my %closep = (); my %maxp = (); my %minp = (); my %volume = ();
    my (@data0, $i, @datein, $in, $tmax, $tmin, @tmpp); my @date = ();
#     my ($day, $po, $ph, $pl, $pc, $vol, @prices, $max, $min, $yc);
    my @data = `sqlite3 "$dbfile" "SELECT date, day_open, day_high, day_low, day_close, volume \\
                                           FROM stockprices \\
                                           WHERE symbol = '$tick' \\
                                           AND date <= '$day' \\
                                           ORDER BY date"`; # \\
                                           #DESC LIMIT 240"`;
    chomp(@data); # contains the dates with most recent first
    foreach $in (@data) {
        @data0 = split /\|/, $in;
        push @date, $data0[0];
        $openp{$data0[0]} = $data0[1];
        $maxp{$data0[0]} = $data0[2];
        $minp{$data0[0]} = $data0[3];
        $closep{$data0[0]} = $data0[4];
        $volume{$data0[0]} = $data0[5];
        @tmpp = ($data0[1], $data0[2], $data0[3], $data0[4]);
        $tmax = max(@tmpp);
        $tmin = min(@tmpp);
        if ($tmax == $data0[2] && $tmin == $data0[3]) { 
            1;
        } elsif ($data0[0] gt '2012-03-01') {
#        } else {
            print "  ***$tick*** $data0[0]: $data0[1] - $data0[2] - $data0[3] - $data0[4] mismatch...\n";
        }
    }
#    @datein = reverse @date;
    @datein = @date;
    $i = 0;  
    foreach $in (@datein) {
        $i++;
        $hday{$i} = $in;  # the day as function of the index of the day (good for calling indicators with day-before)
        $dayindex{$in} = $i;  # day before: $hday{$dayindex{$day}-1}
    }
    return (\@datein, \%hday, \%dayindex, \%openp, \%maxp, \%minp, \%closep, \%volume);
}

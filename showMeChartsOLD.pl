#!/usr/bin/perl -I/Users/tdall/copyExecs
#
#   showMeCharts.pl [yyyy-mm-dd]

use Carp;
use Getopt::Std;
use PGPLOT;

use DBI;    # see http://search.cpan.org/perldoc?DBI for how-to
#use strict;

require "utils.pl";
#require "pg_utils.pl";
require "trader_utils.pl";
#my ($opt_l, $opt_a,$opt_D);  # comment out for running!!!
getopts('SD');
# -S : show the SMAs  (slow!)
# -D : only show the DAX stocks

my $day = shift; 
my %hday = (); my %dayindex = (); my %openp = (); my %closep = (); my %maxp = (); my %minp = (); my %volume = ();
my $nbars = 250;
$|=1;

&readGlobalParams();
if ($opt_D) {
    open TI, "<${path}/tick4test.tick" or die "sefrr3432";
    @ticks = <TI>;
    close TI;
    print "... using only DAX values\n";
}

my $font = 2;
my $linewidth = 2;
my $charheight = 1.2;

$nticks = @ticks;
$count = 0;
print "Displaying $nticks stock charts for $day...\n";
foreach $tick (@ticks) {
    chomp($tick);
    #     return (\@datein, \%hday, \%dayindex, \%openp, \%maxp, \%minp, \%closep, \%volume);
    ($din, $hd, $di, $op, $hp, $lp, $cp, $v, $badbars) = readStockData($tick, $dbfile, $day);
    @date = @$din; %hday = %$hd; %dayindex = %$di; %openp = %$op; %maxp = %$hp; %minp = %$lp; %closep = %$cp; %volume = %$v;
    $ntot = @date;
    print "for $tick: $badbars bad bars...\n";
    next if ($ntot < $nbars || $badbars/$nbars > 0.03);
    $count++;
    if ($opt_S) {
        @maGreen = (); @maBlue = (); @maRed = ();
        @maG = smaArray(\%closep,50);
#         for ($i = 0; $i < $nume; $i++) {
#             $sday = $day[$i];
#             push @maGreen, sma($tick, \%hday, \%dayindex, \%closep, 50, $sday);
#             push @maBlue, sma($tick, \%hday, \%dayindex, \%closep, 21, $sday);
#             push @maRed, sma($tick, \%hday, \%dayindex, \%closep, 200, $sday);
#         }
    }
    @open = (); @high = (); @low = (); @close = (); @xx = (); @pmove = (); @day = (); @x = ();
    for ($i=1; $i<=$nbars; $i++) {
        push @open, $openp{$date[-$i]}; #print "$date[-$i]\n"; exit();
        push @high, $maxp{$date[-$i]};
        push @low, $minp{$date[-$i]};
        push @close, $closep{$date[-$i]};
#         unshift @open, $openp{$date[-$i]}; #print "$date[-$i]\n"; exit();
#         unshift @high, $maxp{$date[-$i]};
#         unshift @low, $minp{$date[-$i]};
#         unshift @close, $closep{$date[-$i]};
        push @day, $date[-$i];
        push @x, $i;
        if ($opt_S) {push @maGreen, $maG[$i]};
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

    pgbeg(0,$device,1,2); # || warn "pgbeg on $device says: $!\n"; # Open plot device 
    pgscr(0,1.0,1.0,1.0); # set background = white
    pgscr(1,0.0,0.0,0.0); # set foreground = black
    pgscf($font); # Set character font 
    pgslw($linewidth); # Set line width 
    pgsch($charheight); # Set character height 
    pgsci(1);  # default colour

    my $candlew = 0.31;
    pgsfs(1); # fill is true
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, -2);# || warn "pgenv here says: $!\n";
    pgsvp(0.02,1,-0.5,0.98);
    pgbox('BCMST',0,0,'BCNST',0,0);
#     pglabel("Day of trade", "Price", "$tick - $day");
    my $text = "<%" . sprintf("move> = %.1f +/- %.1f, sig/Av = %.2f, ${nbars}day-range = %.1f",$avmove,$sigmove,$sigmove/$avmove,$rangep) . "%, " . sprintf("Tscore = %.1f",$trend);
#    pgmtext('T', 1.0, 0.3, 0, "$text");
    pgmtext('T', -1.0, 0.01, 0, "$tick - $day");
    if ($opt_S) {
#         pgsci(2); # red
#         pgline($nume, \@xx, \@maRed);
#         pgmtext('RV', 0.2, 0.6, 0, "SMA200");
        pgsci(10); # green
        pgline($nume, \@xx, \@maGreen);
#         pgmtext('RV', 0.2, 0.5, 0, "SMA50");
#         pgsci(4); # blue
#         pgline($nume, \@xx, \@maBlue);
#         pgmtext('RV', 0.2, 0.4, 0, "SMA21");
        pgslw($linewidth);
    }
    for ($i = 0; $i < $nume; $i++) {
        pgsci(14);                          # color 15 = light gray
        pgslw(2); # Set line width 
        pgline(2, [$xx[$i],$xx[$i]], [$low[$i],$high[$i]]);
        pgslw(1); # Set line width 
        if ($open[$i] > $close[$i]) {
            pgsfs(1); # fill is true
            pgsci(1); # red
#            pgsci(14); # down day
        } else {
            pgsci(0); # white: up day
            pgsfs(1); # fill is true
            pgrect($xx[$i]-$candlew, $xx[$i]+$candlew, $open[$i], $close[$i]);
            pgsci(14); # gray
            pgsfs(2); # fill is false
        }
        pgrect($xx[$i]-$candlew, $xx[$i]+$candlew, $open[$i], $close[$i]); 
    }
    pgsci(1);  # default colour
    pgenv($xplot_low, $xplot_hig, 0, 2.0, 0, -2);# || warn "pgenv here says: $!\n";
    pgsvp(0,1,0,0.2);
    @atr = atrArray(\%maxp,\%minp,\%closep,14);
    pgsci(5);
    pgline($nume,\@xx,\@atr);
    print "Chart of $tick [RET]"; $dum = <STDIN>;
    pgend;
}
print "Done! Displayed a total of $count charts. Well done!\n";

&myexit();
#### END of program

##  ----------------

####  subroutines

sub myexit {
    exit;
}


sub readGlobalParams {
    unless ($day) {
        chomp( $day = `date "+%Y-%m-%d"` );
    }
    $path = "/Users/tdall/geniustrader/";
    $dbfile = "/Users/tdall/geniustrader/traderThomas";
    @ticks = `sqlite3 "$dbfile" "SELECT symbol FROM stockinfo"`; # \\
}

sub readStockData {
    use strict;
    my ($tick, $dbfile, $day) = @_;
    my $c = @_; die "only $c elements to readStockData(), should be 3\n" unless ($c == 3);
    my %hday = (); my %dayindex = (); my %openp = (); my %closep = (); my %maxp = (); my %minp = (); my %volume = ();
    my (@data0, $i, @datein, $in, $tmax, $tmin, @tmpp); my @date = ();
    my $mismatch = 0;
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
        if (($tmax != $data0[2] || $tmin != $data0[3] || $tmax == $tmin) && $data0[0] gt '2012-03-01') {
            print "  ***$tick*** $data0[0]: $data0[1] - $data0[2] - $data0[3] - $data0[4] mismatch...\n";
            $mismatch++;
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
    return (\@datein, \%hday, \%dayindex, \%openp, \%maxp, \%minp, \%closep, \%volume, $mismatch);
}

#  $mystamp = getStamp();
#

#!/usr/bin/perl -I/Users/tdall/copyExecs
#
#   showMeCharts.pl [yyyy-mm-dd]

use Carp;
use Getopt::Std;
use PGPLOT;

use DBI;    # see http://search.cpan.org/perldoc?DBI for how-to
use strict;

require "utils.pl";
#require "pg_utils.pl";
require "trader_utils.pl";

my %opt;
getopts('SDEp', \%opt);
# -S : show the SMAs (not with -E)
# -E : show the EMAs (not with -S)
# -D : only show the DAX stocks
# -p : plot to file

my (%openp,%maxp,%minp,%closep,%volume, %tmp,%data);
my $nbars = 250; # number of bars we want to see in the plot
my $font = 2;
my $linewidth = 2;
my $charheight = 1.5;
my $path = "/Users/tdall/geniustrader/";
my $dbfile = "/Users/tdall/geniustrader/traderThomas";
my ($i,$j,$in,$p1,$p2,@data0,@data,@date,@datein,$tick,@maG,@maR,@maB,@open,@high,@low,@close,@maGreen,@maRed,@maBlue,@xx,@pmove,@day,@x,@a,@b,@atrr,@r,@rsi);
my ($nume,$xplot_low,$xplot_hig,$yplot_low,$yplot_hig,@all,$avmove,$trend,$rangep,$sigmove,@atr,$dum,$device,$q1,$q2,$q3,$q4,@tx,@adx,$radx,$rdadx);
my (@rsiw,@rw);
$|=1;

my $day = shift; 
unless ($day) {
    chomp( $day = `date "+%Y-%m-%d"` );
}
if ($opt{'p'}) {
    $device = "${path}chart_${tick}_${day}.png/PNG";
} else {
    $device = "/XSERVE";
}
if ($opt{'E'} && $opt{'S'}) {
    print "Options -E and -S not allowed together.\n"; exit();
}

my @ticks = `sqlite3 "$dbfile" "SELECT symbol FROM stockinfo"`; # \\
if ($opt{'D'}) {
    open TI, "<${path}/test.tick" or die "sefrr3432";
    @ticks = <TI>;
    close TI;
    print "... using only DAX values\n";
}

####
#@ticks = ('SDF.DE');
my $nticks = @ticks;
my $count = 0;
print "Displaying $nticks stock charts for $day...\n";

# read the data for each stock
foreach $tick (@ticks) {
    chomp $tick;
    print "Reading data for $tick ... ";
    @data = `sqlite3 "$dbfile" "SELECT date, day_open, day_high, day_low, day_close, volume \\
									   FROM stockprices \\
									   WHERE symbol = '$tick' \\
									   ORDER BY date \\
									   DESC"`;
    chomp(@data); # contains the dates with most recent first
    #
    # populate price hashes and date arrays
    #
    %openp = (); %maxp = (); %minp = (); %closep = (); %volume = (); @date = ();
    foreach $in (@data) {
        @data0 = split /\|/, $in;
        push @date, $data0[0];
        $openp{$data0[0]} = $data0[1];
        $maxp{$data0[0]} = $data0[2];
        $minp{$data0[0]} = $data0[3];
        $closep{$data0[0]} = $data0[4];
        $volume{$data0[0]} = $data0[5];
    }
    $tmp{'closep'} = { %closep };
    $tmp{'openp'} = { %openp };
    $tmp{'maxp'} = { %maxp };
    $tmp{'minp'} = { %minp };
    $tmp{'volume'} = { %volume };
    $data{$tick} = { %tmp };
    print "Done.\n";
    #   appending new data - make sure the dates are correct!:
    #       $tmp{'ATR10'} = { %atr };
}
if ($date[0] gt $date[-1]) {
    @datein = reverse @date;
} else {
    @datein = @date;
    @date = reverse @datein; 
}

foreach $tick (@ticks) {
    chomp($tick);
    # add some sanity check to not show stocks with error-filled data
    # TODO
    #
    $count++;
    @maR = (); @maB = (); @maG = ();
    %closep = (); %maxp = (); %minp = (); %openp = (); %volume = ();
    
    # make temporary price hashes
    @maxp{ keys %{$data{$tick}{maxp}} } = values %{$data{$tick}{maxp}};
    @minp{ keys %{$data{$tick}{minp}} } = values %{$data{$tick}{minp}};
    @closep{ keys %{$data{$tick}{closep}} } = values %{$data{$tick}{closep}};
    @openp{ keys %{$data{$tick}{openp}} } = values %{$data{$tick}{openp}};
    @date = sort keys %{$data{$tick}{closep}}; 
    
    if ($opt{'S'}) {
        @maG = smaArray(\%closep,50); 
        @maB = smaArray(\%closep,20); 
        @maR = smaArray(\%closep,200);
    } elsif ($opt{'E'}) {
        @maG = emaArray(\%closep,50); 
        @maB = emaArray(\%closep,20); 
        @maR = emaArray(\%closep,200);
    }

    @open = (); @high = (); @low = (); @close = (); @xx = (); @pmove = (); @day = (); @x = ();
    @maGreen = (); @maRed = (); @maBlue = ();
    # get the ATR10
    @atr = ();
    @a = atrArray(\%maxp,\%minp,\%closep,10);
    #get ATRR
    @atrr = ();
    @b = atrArray(\%maxp,\%minp,\%closep,100);
    # get RSI
    @rsi = (); @rsiw = ();
    @r = rsiArray(\%closep,9);
    @rw = rsiArrayW(\%closep,9);
    # get ADX
    @adx = (); @tx = ();
    ($radx, $rdadx) = adxArray(\%maxp,\%minp,\%closep,10);
    @tx = @$radx;
    for ($i=1; $i<=$nbars; $i++) {
        push @open, $openp{$date[-$i]}; #print "for $i: $date[-$i]\n"; exit();
        push @high, $maxp{$date[-$i]};
        push @low, $minp{$date[-$i]};
        push @close, $closep{$date[-$i]};
        push @day, $date[-$i];
        push @x, $i;
        if ($opt{'S'} || $opt{'E'}) {
            push @maGreen, $maG[-$i];
            push @maBlue, $maB[-$i];
            push @maRed, $maR[-$i];
        }
        push @atr, $a[-$i];
        push @atrr, $a[-$i]/$b[-$i];
        push @rsi, $r[-$i];
        push @rsiw, $rw[-$i];
        push @adx, $tx[-$i];
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

    # start the plotting
    #
    pgbeg(0,$device,1,4); # || warn "pgbeg on $device says: $!\n"; # Open plot device
    pgpap(17.0,0.55);
    pgscr(0,1.0,1.0,1.0); # set background = white
    pgscr(1,0.0,0.0,0.0); # set foreground = black
    pgscf($font); # Set character font 
    pgslw($linewidth); # Set line width 
    pgsch($charheight); # Set character height 
    pgsci(1);  # default colour

    # main plot - candle chart
    #
    my $candlew = 0.31;
    pgsfs(1); # fill is true
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, -2);# || warn "pgenv here says: $!\n";
    pgsvp(0.02,1,-1.0,0.95);
    pgbox('BCMST',0,0,'BCNST',0,0);
#     pglabel("Day of trade", "Price", "$tick - $day");
    my $text = "<%" . sprintf("move> = %.1f +/- %.1f, sig/Av = %.2f, ${nbars}day-range = %.1f",$avmove,$sigmove,$sigmove/$avmove,$rangep) . "%, " . sprintf("Tscore = %.1f",$trend);
#    pgmtext('T', 1.0, 0.3, 0, "$text");
    pgmtext('T', -1.0, 0.01, 0, "$tick - $day");
    if ($opt{'S'} || $opt{'E'}) {
        pgsci(2); # red
        pgline($nume, \@xx, \@maRed);
        pgsci(10); # green
        pgline($nume, \@xx, \@maGreen);
        pgsci(4); # blue
        pgline($nume, \@xx, \@maBlue);
        #pgpoint($nume,\@xx, \@maBlue,17);
        pgslw($linewidth);
    }
    for ($i = 0; $i < $nume; $i++) {
        pgsci(14);                          # color 15 = light gray
        pgslw(2); # Set line width 
        pgline(2, [$xx[$i],$xx[$i]], [$low[$i],$high[$i]]);
        pgslw(1); # Set line width 
        if ($open[$i] > $close[$i]) {
            pgsfs(1); # fill is true
            pgsci(1); # black
        } else {
            pgsci(0); # white: up day
            pgsfs(1); # fill is true
            pgrect($xx[$i]-$candlew, $xx[$i]+$candlew, $open[$i], $close[$i]);
            pgsci(14); # gray for outline
            pgsfs(2); # fill is false
        }
        pgrect($xx[$i]-$candlew, $xx[$i]+$candlew, $open[$i], $close[$i]); 
    }
    
    # second plot: ADX10
    #
    ($yplot_low, $yplot_hig) = low_and_high(@adx);
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, -2);# || warn "pgenv here says: $!\n";
    pgsvp(0.02,1,-0.66,0.0);
    pgsci(1);  # default colour
    pgbox('BCST',0,0,'BCNST',0,0);
    pgsls(4);
    pgsci(15);
    pgline(2, [$xx[0],$xx[-1]], [30,30]);
    pgline(2, [$xx[0],$xx[-1]], [50,50]);
    pgsls(1);
    pgsci(5);
    pgline($nume,\@xx,\@adx);
    pgmtext('T', -1.0, 0.01, 0, "ADX(10)");
    
    # third plot: ATRR10-5
    #
    ($yplot_low, $yplot_hig) = low_and_high(@atrr);
    pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, -2);# || warn "pgenv here says: $!\n";
    pgsvp(0.02,1,-0.33,0.33);
    pgsci(1);  # default colour
    pgbox('BCST',0,0,'BCNST',0,0);
    pgsls(4);
    pgline(2, [$xx[0],$xx[-1]], [1,1]);
    pgsls(1);
    pgsci(13);
    pgline($nume,\@xx,\@atrr);
    pgmtext('T', -1.0, 0.01, 0, "ATRR(10,100)");
    
    # fourth plot: RSI
    #
    pgenv($xplot_low, $xplot_hig, 0, 100, 0, -2);# || warn "pgenv here says: $!\n";
    pgsvp(0.02,1,0.0,0.66);
    pgsci(1);  # default colour
    pgbox('BCST',0,0,'BCNST',0,0);
    pgsls(4);
    pgsci(15);
    pgline(2, [$xx[0],$xx[-1]], [35,35]);
    pgline(2, [$xx[0],$xx[-1]], [65,65]);
    pgsci(14);
    pgline(2, [$xx[0],$xx[-1]], [50,50]);
    pgsls(1);
    pgsci(4);
    pgline($nume,\@xx,\@rsi);
    pgmtext('T', -1.0, 0.01, 0, "RSI(9)");
 
    print "Chart of $tick [RET]"; $dum = <STDIN>;
    #pgqvsz(3,$q1,$q2,$q3,$q4);
    #print "returning $q1,$q2,$q3,$q4 or @q\n";
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

### TMP code
    ### TMP third plot
    pgenv($xplot_low, $xplot_hig, 0, 100, 0, -2);# || warn "pgenv here says: $!\n";
    pgsvp(0.02,1,-0.33,0.33);
    pgsci(1);  # default colour
    pgbox('BCST',0,0,'BCNST',0,0);
    pgsls(4);
    pgsci(15);
    pgline(2, [$xx[0],$xx[-1]], [35,35]);
    pgline(2, [$xx[0],$xx[-1]], [65,65]);
    pgsci(14);
    pgline(2, [$xx[0],$xx[-1]], [50,50]);
    pgsls(1);
    pgsci(4);
    pgline($nume,\@xx,\@rsiw);
    pgmtext('T', -1.0, 0.01, 0, "RSIW(9)");



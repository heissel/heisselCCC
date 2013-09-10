#!/usr/bin/perl -w -I/Users/tdall/copyExecs
# 
# generate backtests - new version (Aug.2013) for AllTime/breakout trading
#

use strict;
use DBI;
use Getopt::Std;
require "utils.pl";
require "trader_utils.pl";

my %opt;
getopts('p', \%opt);
=pod

=head1 Options

=head2 [-p] 

make PNG plots for each trade and for summary plots, otherwise plot on screen only

=head1 Data Structure

=head2 %data

Data hash with the price and indicator values:

 $data{
        BMW.DE => {
                    closep => {
                                2012-05-23 => 54.34,
                                2012-05-24 => 55.66,
                                ...
                            },
                    openp => {
                                ...
                            },
                    RSI9 => {
                                ...
                            },
                    ...
                    },
        LHA.DE => {
                    ...
                    },
        ...
        }

Example of how to access the data: print "close = $data{BMW.DE}{closep}{$day}, ATR10 = $data{BMW.DE}{'ATR10'}{$day}\n".

=head2 %trade

Hash containing all the trades made, indexed by the trade-ID. Is being updated continously when trades are active.

 $trade{
        23 => {
                tick        => BMW.DE,
                status      => pend|active|closed,
                dir         => long|short,
                dorder      => 2012-05-23,  (date of order in case of pending, else same as dentry),
                dentry      => 2012-05-23,
                dexit       => 2013-01-12,
                pentry      => 34.51,
                pexit       => 43.91,
                istop       => 33.12,
                stop        => 43.92,       (updated throughout trade),
                fee1way     => 5.90,
                target      => 0,           (set to zero if no target),
                nsubtrades  => 1|2|...,     (number of sub-trades)
                thistraden  => 1|2|...,     (used when calculating afterwards)
                thisfrac    => 0.30,        (fraction of full trade represented by this ID)
                },
        25 => {
                ...
                }
        }

Example: 
    foreach $id (keys %trade) {
        print "Trade number $id entered on $trade{$id}{dentry}\n";
    }

=head2 %opentrade

Contains information on the currently open trades, i.e. where $trade{$id}{status} equals 'active'.

 $opentrade{
            BMW.DE => {
                        id          => 23,      (if trade is split, the id's are separated by ':', e.g., 23:24:25)
                        }
            ...
            }

All actual information on the trade is kept in %trade.

=head2 %pendingOrders

Contains the ID's of the orders (or trades) that are currently pending, i.e., have $trade{$id}{status} = 'pend'.

 $pendingOrders{
                23 =>  {
                        tick    => BMW.DE,
                        when    => price|open
                        },
                24 =>   {
                        ...
                        },
                ...
                }


=head2 %strategy

Description of the strategy components of every equity.

 $strategy{
            BMW.DE  => {
                        long    => {
                                    active      => 0|1,         (set to zero to deactivate)
                                    ordertype   => close|open|price,
                                    sysEntry    => AllTimeC20c,
                                    setup       => SMA50f0.0,
                                    initStop    => Vola_10_1.5,
                                    trailStop   => Local_3_0.3p,
                                    sysExit     => n,           (condition to shift exit strategy to exitStop)
                                    exitStop    => n,           (ignored if sysExit == n)
                                    nsubtrades  => 2,           (how many partial trades; here first one is with target, second to trail)
                                    parts       => {
                                                    1   => {
                                                            frac    => 0.35,
                                                            target  => Vola_10_2.2c
                                                            },
                                                    2   => {
                                                            frac    => 0.65,
                                                            target  => n
                                                            }
                                                    }
                                    },
                        short   => {
                                    ...
                                    nsubtrades  => 1,
                                    parts       => {
                                                    1   => {
                                                            frac    => 1.0,
                                                            target  => n
                                                            }
                                                    }
                                    }
                        },
            ...
            }
=cut
        # make two output files; one where it's treated as a single trade and one where they're recorded separately.
        
my $path = "/Users/tdall/geniustrader/";
my $dbfile = "/Users/tdall/geniustrader/traderThomas";
my $btdir = "/Users/tdall/geniustrader/Backtests/";
my $extradb = "/Users/tdall/geniustrader/traderExtra";
my ($stgyfile, $dayBegin, $dayEnd) = @ARGV;
my $c = @ARGV; die "Found $c arguments, should be 3\n" unless ($c == 3);
my @strategy = ();

my ($k,$ndays,$day,$yday,$yyday,$stgy,$i,$j,$in,$in2,$dum,$frac,$targ,$p1,$p2,@data0,@data,@date,@datein,$tick,$key,$dir);
my ($setupLong,$setupShort,$enterLong,$enterShort,$exitLong,$exitShort,$tradeID,$exitType,$exitPrice);
my %opentrade = (); # holds the trade ID and other info for the particular asset if a trade is on, else is zero.,
                    # e.g, $opentrade{'TKA.DE'}{id} = 34;
                    # If split trades (for partial profits), it will be $opentrade{'TKA.DE'}{id} = "34:35";
my (%openp,%maxp,%minp,%closep,%volume, %tmp,%sg,%data,%strategy);
my $numtrades = 0; my %pvalue = (); 
my (%pendingOrders,$oid,$tid,@ids);
my %rmult = (); my %trade = (); my $entrySig = ''; my %ticks = ();
my @indicators = (); my @ticks = ();
my ($ind,$dbh,$par,$rec,@arr,@day,@tmp);

#
# read the strategy descriptions
#
open SY, "<${path}/${stgyfile}.gtsys" or die "mdhh28fanaodgrt7";
while ($in = <SY>) {
    next if $in =~ /^[#0c]/;
    %tmp = ();
    %sg = ();
    chomp($in);
    @tmp = split /\s+/, $in;  # 1   BMW.DE  long    AllTimeC20c     EMA50f0.0       Vola_10_1.5     Local_3_0.3p    n   n   2
    $sg{active} = $tmp[0];  # for now, not including the inactivated strategies in hash, so this might be redundant...
    $sg{sysEntry} = $tmp[3];
    if ($tmp[3] =~ /([COXS])\d+/) {
        $sg{ordertype} = 'close' if $1 == 'C';
        $sg{ordertype} = 'open' if $1 == 'O';
        $sg{ordertype} = 'price' if $1 == 'S';
    } else {
        print "Warning: setting ordertype for $tmp[1]-$tmp[2] to default (close)\n";
        $sg{ordertype} = 'close';
    }
    $sg{setup} = $tmp[4];
    $sg{initStop} = $tmp[5];
    $sg{trailStop} = $tmp[6];
    $sg{sysExit} = $tmp[7];
    $sg{exitStop} = $tmp[8];
    $sg{nsubtrades} = $tmp[9];
    for ($i = 1; $i <= $tmp[-1]; $i++) {
        chomp($in2 = <SY>);
        die "Error: reading $in2 is not making sense\n" unless $in2 =~ /^c/;
        ($dum, $frac, $targ) = split /\s+/, $in2;
        $tmp{$i} = {
                        frac => $frac,
                        target => $targ
                    };
    }
    $sg{parts} = { %tmp };
    $strategy{$tmp[1]}{$tmp[2]} = { %sg };
    $ticks{$tmp[1]} = $tmp[1];
}
@ticks = keys %ticks;
#
# read the data for each stock
#
foreach $tick (@ticks) {
    @date = ();
    print "Reading data for $tick ... ";
    @data = `sqlite3 "$dbfile" "SELECT date, day_open, day_high, day_low, day_close, volume \\
									   FROM stockprices \\
									   WHERE symbol = '$tick' \\
									   ORDER BY date \\
									   DESC"`;
    chomp(@data); # contains the dates with most recent first
    $p1 = 0; 
    $p2 = 0;
    #
    # populate price hashes and date arrays
    #
    %openp = (); %maxp = (); %minp = (); %closep = (); %volume = ();
    foreach $in (@data) {
        @data0 = split /\|/, $in;
        push @date, $data0[0];
        $openp{$data0[0]} = $data0[1];
        $maxp{$data0[0]} = $data0[2];
        $minp{$data0[0]} = $data0[3];
        $closep{$data0[0]} = $data0[4];
        $volume{$data0[0]} = $data0[5];
        if ($data0[0] ge $dayEnd && !$p2) {
            $p2 = $data0[4]; 
        } elsif ($data0[0] ge $dayBegin && !$p1) {
            $p1 = $data0[4];
        }
    }
    $tmp{'closep'} = { %closep };
    $tmp{'openp'} = { %openp };
    $tmp{'maxp'} = { %maxp };
    $tmp{'minp'} = { %minp };
    $tmp{'volume'} = { %volume };
    $data{$tick} = { %tmp };
    $ndays = @date;
    print "Read $ndays records. Done.\n";
}
if ($date[0] gt $date[-1]) {
    @datein = reverse @date;
} else {
    @datein = @date;
    @date = reverse @datein; 
}

# NOTE: the DB needs to be updated daily with new numbers for all existing tables... TODO
if (-e $extradb) {
    $dbh = DBI->connect("dbi:SQLite:$extradb", undef, undef, {
        AutoCommit => 1,
        RaiseError => 1,
        sqlite_see_if_its_a_number => 1,
      });
} else {
    die "no such file: $extradb\n";
}
# find out which additional numbers (indicators) are needed for the stocks, then add these to the data hash,
# test each of the strategy components for whether we need indicators
@tmp = qw/sysEntry setup initStop trailStop sysExit exitStop/;
foreach $tick (@ticks) {
    @strategy = ();
    %tmp = ();
    foreach $dir ('long', 'short') {
        next unless (exists $strategy{$tick}{$dir});
        foreach $key (@tmp) {
            push @strategy, $strategy{$tick}{$dir}{$key};
        }
        foreach $key (keys %{ $strategy{$tick}{$dir}{parts} } ) {
            push @strategy, $strategy{$tick}{$dir}{parts}{$key}{target};
        }
    }
    foreach $stgy (@strategy) {
        if ($stgy =~ /ADX(\d+)/) {
            $par = $1;
            $ind = "ADX$par";
            $tmp{$ind} = $ind;
        }
        if ($stgy =~ /SMAprice(\d+)/) {
            $par = $1;
            # TODO...
        }
        if ($stgy =~ /SMA(\d+)/) {
            $par = $1;
            $ind = "SMA$par";
            $tmp{$ind} = $ind;
        }
        if ($stgy =~ /EMA(\d+)/) {
            $par = $1;
            $ind = "EMA$par";
            $tmp{$ind} = $ind;
        }
        if ($stgy =~ /RSI(\d+)/) {
            $par = $1;
            $ind = "RSI$par";
            $tmp{$ind} = $ind;
        }
        if ($stgy =~ /Vola_(\d+)/) {
            $par = $1;
            $ind = "ATR$par";
            $tmp{$ind} = $ind;
        }
    
    }
    # uniqueness of indicator names
    @indicators = keys %tmp;

    # getting indicators from the extra-DB if they exist -- else exit with error
    foreach $ind (@indicators) {
        $rec = $data{$tick};    # tmp pointer
        @arr = @{$dbh->selectcol_arrayref("SELECT value FROM indicators WHERE symbol = '$tick' AND indicator='$ind' ORDER BY date DESC")};
        @day = @{$dbh->selectcol_arrayref("SELECT date FROM indicators WHERE symbol = '$tick' AND indicator='$ind' ORDER BY date DESC")};
        if ($arr[0]) {
            @tmp{@day} = @arr;
            $rec->{$ind} = { %tmp };
            print "Adding $ind to the data hash for $tick\n";
        } else {
            print "Missing $ind for $tick. Please add with calcIndicator.pl\n";
            $dbh->disconnect;
            exit();
        }
    }
}
$dbh->disconnect;
        # print "BMW-long-trailStop: $strategy{'BMW.DE'}{long}{trailStop} and frac = $strategy{'BMW.DE'}{long}{parts}{1}{frac}\n"; exit;

#
# MAIN LOOP ($k)
$ndays = @datein;
for ($k = 0; $k < $ndays; $k++) {

    $day = $datein[$k];
	if ($day lt $dayBegin) { 
	    # save the dates as yesterday for tomorrow...
        $yyday = $yday;
        $yday = $day;
        next;
    }
	last if ($day gt $dayEnd);

    foreach $tick (@ticks) {
        
        #
        # Pending orders: was something opened during the day (stop-entry)
        #
        foreach $tid (keys %pendingOrders) {
            if ($pendingOrders{$tid}{tick} eq $tick) {
                # check if this order ID is getting filled today
                # if filled, then delete the hash key
                # if not filled, check if it should be deleted anyway...
                
            }
        } # end foreach Pending Order
    
        #
        # Check open trades: were they stopped out today? Did they hit the target today?
        #
        if (exists $opentrade{$tick}) {
            @ids = split /:/, $opentrade{$tick}{id};
            foreach $tid (@ids) {
                # check for stop-out
                if ($trade{$tid}{dir} eq 'long' && $data{$tick}{minp}{$day} < $trade{$tid}{stop}) {
                
                } elsif ($trade{$tid}{dir} eq 'short' && $data{$tick}{maxp}{$day} > $trade{$tid}{stop}) {
                    # should prbl combine these two segments...
                }
                # check for target
                if ($trade{$tid}{target} > 0) {
                
                }
            }
        }
        
        #
        # at this point, if we don't have an open trade, check for signals. Then open trade.
        #
        if ( ! exists $opentrade{$tick}) {
            # get setup conditions -> $setupLong, $setupShort = 0|1
            
            # get entry signals -> $entrySig = long|short|NULL
            
        }
        if ($entrySig) {
        
        }
        
        #
        # check if we just opened a trade, if it might have been stopped out during the day
        #
        $tid = $opentrade{$tick}{id};
        if (exists $opentrade{$tick} && ($trade{$tid}{dentry} eq $day && $trade{$tid}{method} eq 'pend') ) {

        }
        
        #
        # if we now have an open trade, we might want to adjust the stop
        #
        if (exists $opentrade{$tick} && ($trade{$tid}{dentry} ne $day || $trade{$tid}{method} eq 'pend') ) {
        
        }
        
    } # end foreach $tick

} # end foreach $day ($k)

# END MAIN LOOP
#




###### END OF PROGRAM

#        print "$tick, $day: close = $data{$tick}{closep}{$day}, ATR10 = $data{$tick}{'ATR10'}{$day}\n"


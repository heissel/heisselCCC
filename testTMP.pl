#!/usr/bin/perl -I/Users/tdall/copyExecs
# 
#   still not sure how to extract a hash from within the big data structure
#        %closep = $data->{$tick}{'closep'};
#        print "Close extracted on $day is $closep{$day}\n" if $day gt '2012-07-10';
#
# $i=0;
# my %DATA;
# while ($i<3) {
#   $i++; print "going through, setting i = $i\n";
#   my $sequence = 10+$i;
#   my $length   = 20+$i;
#   my $gc_content = 40+$i;
#   $id = $i;  # imagine this is $tick....
# 
#   $DATA{$id} = { sequence   => $sequence,
# 		 length     => $length,
# 		 gc_content => sprintf("%3.2f",$gc_content)
# 	       };
# 	$pc{$id} = { }; 
# }
# 
# my @ids = sort {  $DATA{$a}->{gc_content} <=> $DATA{$b}->{gc_content}
# 		} keys %DATA;
# 
# foreach my $id (@ids) {
#   print "$id\n";
#   print "\tgc content = $DATA{$id}->{gc_content}\n";
#   print "\tlength     = $DATA{$id}->{length}\n";
#   print "\n";
# }
# 
# exit;
require "utils.pl";
require "trader_utils.pl";

my $path = "/Users/tdall/geniustrader/";
my $dbfile = "/Users/tdall/geniustrader/traderThomas";
my $btdir = "/Users/tdall/geniustrader/Backtests/";
my ($tickfile, $dayBegin, $dayEnd, $system, $sysInitStop, $sysStop, $sysExitStop) = @ARGV;

my ($day,$yday,$yyday,$i,$j,$in,$p1,$p2,@data0,@data,@date,@datein,$tick,@ticks);
my ($setupLong,$setupShort,$enterLong,$enterShort,$exitLong,$exitShort,$tradeID,$exitType,$exitPrice);
my %opentrade = (); # holds the trade ID for the particular asset if a trade is on, else is zero. e.g, $opentrade{'TKA.DE'} = 34;
my %pcTick = ();    # has close price for the particular asset; $pcTick{'LHA.DE'} = \%closep;
my (%openp,%maxp,%minp,%closep,%volume, %tmp,%data);
my $numtrades = 0; my %pvalue = (); 
my %rmult = (); 

my %ttt;

# read the stock ticker symbols to use
open TI, "<${path}/${tickfile}.tick" or die "sefrr3432";
@ticks = <TI>;
close TI;
chomp(@ticks);

# read the data for each stock
foreach $tick (@ticks) {
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
        next if ($data0[0] lt '2010-07-10'); # || $data0[0] gt '2012-07-25');
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
    $tmp{closep} = { %closep };
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
# the day as function of the index of the day (good for calling indicators with day-before)
# day before: $hday{$dayindex{$day}-1}
#
$ii = 0;  
foreach $in (@datein) {
    $ii++;
    $hday{$ii} = $in;  
    $dayindex{$in} = $ii;  
    #print "hday = $in, index = $ii\n"; exit if $ii > 10;
}
print "$ii was last and is $hday{$ii}\n";
# find out which additional numbers (indicators) are needed for the stocks, then add these to the data hash.
#foreach $tick (@ticks) {


#}


$which = 'CON.DE'; $tick=$which; $par = 20;
$tid = 12;
$trade{$tid} = {
    tick => $tick,
    stop => 23.44,
    status => 'p'
    };
print "Testing status = $trade{$tid}{status}\n";
exit;
$testvar = ema($tick, \%hday, \%dayindex, \%closep, $par, '2013-08-30');
@sma = emaArray(\%closep, $par);
$nnn = @sma;
print "$nnn values in sma-arr. old = $testvar, new = $sma[$ii-1]\n";
exit;

if (exists $data{$tick}{closep}) {
    print "Yes, ";
    if (exists $data{$tick}{'ATR10'}) {
    } else {
        print "and No!\n";
    }
}


print "new: $data{$which}{closep}{'2012-07-11'}\n";
#%ttt = { $data{$which}{'closep'} };
@k = sort keys %{ $data{$tick}{closep} };
foreach $a (@k) {
    $ttt{$a} = $data{$tick}{closep}{$a};
}
# @ttt{@k} = @v;
# @ttt{keys %{ $data{$tick}{closep} }} = values %{ $data{$tick}{closep} };
print "deref: $ttt{'2012-07-11'}\n";
%t = ();
$i = 0;
foreach $d (@k) {
    print "$d = $k[$i] -> $v[$i] = $ttt{$d}\n";
    $t{$d} = abs($data{$tick}{minp}{$d} - $data{$tick}{maxp}{$d});
    $i++;
}
$data{$tick}{ATR} = { %t };
print "ATR: $data{$which}{ATR}{'2012-07-11'}\n";

exit;


$rec = $data{$which}; # tmp pointer
$cp = %{ $rec->{'closep'} };
print "new2: $rec{'closep'}{'2012-07-11'} -- and: ",$cp->{'2012-07-11'},"\n";

            %TV = (
               flintstones => {
                   series   => "flintstones",
                   nights   => [ qw(monday thursday friday) ],
                   members  => [
                       { name => "fred",    role => "lead", age  => 36, },
                       { name => "wilma",   role => "wife", age  => 31, },
                       { name => "pebbles", role => "kid",  age  =>  4, },
                   ],
               },

               jetsons     => {
                   series   => "jetsons",
                   nights   => [ qw(wednesday saturday) ],
                   members  => [
                       { name => "george",  role => "lead", age  => 41, },
                       { name => "jane",    role => "wife", age  => 39, },
                       { name => "elroy",   role => "kid",  age  =>  9, },
                   ],
                },

               simpsons    => {
                   series   => "simpsons",
                   nights   => [ qw(monday) ],
                   members  => [
                       { name => "homer", role => "lead", age  => 34, },
                       { name => "marge", role => "wife", age => 37, },
                       { name => "bart",  role => "kid",  age  =>  11, },
                   ],
                },
             );

            # print the whole thing
            foreach $family ( keys %TV ) {
                print "the $family";
                print " is on during @{ $TV{$family}{nights} }\n";
                print "its members are:\n";
                for $who ( @{ $TV{$family}{members} } ) {
                    print " $who->{name} ($who->{role}), age $who->{age}\n";
                }
                print "it turns out that $TV{$family}{lead} has ";
                print scalar ( @{ $TV{$family}{kids} } ), " kids named ";
                print join (", ", map { $_->{name} } @{ $TV{$family}{kids} } );
                print "\n";
            }

foreach $tick (keys %data) {
    print "stock is $tick: ";
    print "has close prices:\n";
    for $dato ( values %{ $data{$tick}{'closep'} } ) {
        print "$dato\n";
    }
    print "\n";
}

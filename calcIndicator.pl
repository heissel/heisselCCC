#!/usr/bin/perl -I/Users/tdall/copyExecs
#
# calculate an indicator for a given stock, populate the DB traderExtra
# If it already exists, missing entries will be appended.
# accepted indicator names and examples:
#   ATR     ATR10
#   ATRR    ATRR14-5 for a/a5 using ATR14 as basis, i.e. ATR14/ATR70
#   SMA     SMA50
#   EMA     EMA22

# -D : remove all previous values of this indicator and calculate it all anew
use strict;
use DBI;
use Getopt::Std;
require "utils.pl";
require "trader_utils.pl";

my %opt;
getopts('D', \%opt);


my $path = "/Users/tdall/geniustrader/";
my $dbfile = "/Users/tdall/geniustrader/traderThomas";
my $btdir = "/Users/tdall/geniustrader/Backtests/";
my $extradb = "/Users/tdall/geniustrader/traderExtra";

my ($tick, $indname) = @ARGV;
my ($day,$yday,$yyday,$stgy,$i,$j,$in,$p1,$p2,$p3,@data0,@data,@date,@datein);
my (%openp,%maxp,%minp,%closep,%volume, %tmp,%data);
my ($dbh,@ind,$par,$ind,$inserted,$oldentry,@oldval,@tmp);
my ($ii,%hday,%dayindex,$atr,@i1,@i2,$ntmp);
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
%openp = (); %maxp = (); %minp = (); %closep = (); %volume = ();
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
if ($date[0] gt $date[-1]) {
    @datein = reverse @date;
} else {
    @datein = @date;
    @date = reverse @datein; 
}
%tmp = ();

if (-e $extradb) {
    $dbh = DBI->connect("dbi:SQLite:$extradb", undef, undef, {
        AutoCommit => 1,
        RaiseError => 1,
        sqlite_see_if_its_a_number => 1,
      });
} else {
    die "no such file: $extradb\n";
}

if ($indname =~ /(\D+)(\d+)-(\d+)-(\d+)/) {
    $ind = $1;  $p1 = $2;   $p2 = $3;   $p3 = $4;
} elsif ($indname =~ /(\D+)(\d+)-(\d+)/) {
    $ind = $1;  $p1 = $2;   $p2 = $3;
} elsif ($indname =~ /(\D+)(\d+)/) {
    $ind = $1;  $par = $2;
} else {
    $dbh->disconnect;
    print "Warning: No action taken, could not resolve $indname\n";
    exit();
}

# remove all previous entries if it is a full update (-D)
if ($opt{'D'}) {
    print "Removing old instance of $indname for $tick.\n";
    $dbh -> do(qq{DELETE FROM indicators WHERE symbol = '$tick' AND indicator = '$indname'});
}

@maxp{ keys %{$data{$tick}{maxp}} } = values %{$data{$tick}{maxp}};
@minp{ keys %{$data{$tick}{minp}} } = values %{$data{$tick}{minp}};
@closep{ keys %{$data{$tick}{closep}} } = values %{$data{$tick}{closep}};

# resolve the indicator name. It should be one of the following:
# ATR, ATRR, ADX, SMA, EMA, RSI, OBV, KSO, MACD, ...more to follow
#
if ($ind eq 'ATR') {    # Average True Range
    @ind = atrArray(\%maxp, \%minp, \%closep, $par);
} elsif ($ind eq 'ATRR') {  # ATR ratio, giving the period of the lower one, and the ratio larger/smaller. Standard is A/A10
    @i1 = atrArray(\%maxp, \%minp, \%closep, $p1);
    @i2 = atrArray(\%maxp, \%minp, \%closep, $p1*$p2);
    $ntmp = @i1;
    for ($i = 0; $i < $ntmp; $i++) {
        $ind[$i] = $i1[$i]/$i2[$i];
    }
#} elsif ($ind eq 'ADX') {
    @tmp = adxArray(\%closep, $par);
    @ind = @{$tmp[0]};
} elsif ($ind eq 'SMA') {
    @ind = smaArray(\%closep, $par);
} elsif ($ind eq 'EMA') {
    @ind = emaArray(\%closep, $par);
} elsif ($ind eq 'RSI') {
    @ind = rsiArray(\%closep, $par);
#} elsif ($ind eq 'OBV') {

#} elsif ($ind eq 'KSO') {

#} elsif ($ind eq 'MACD') {

} else {
    $dbh->disconnect;
    print "Warning: No action taken, $ind is not an allowed indicator\n";
    exit();
}

# insert new indicator into database
$inserted = 0;
@tmp{ sort keys %{$data{$tick}{closep}} } = @ind;
$data{$tick}{$indname} = { %tmp };
foreach $day ( sort keys %{$data{$tick}{closep}} ) {
    # test if this entry exists already
    $oldentry = $dbh->selectcol_arrayref("SELECT value FROM indicators WHERE symbol='$tick' AND indicator='$indname' AND date='$day'");
    @oldval = @$oldentry;
    if ($oldval[0]) {
        if ($oldval[0] ne $data{$tick}{$indname}{$day}) {
            print "Warning: value of $indname on $day does not correspond to new: $oldval[0] vs $data{$tick}{$indname}{$day}";
            print " Consider replacing (using -D) if price data has improved\n";
        }
    } else {
        $dbh -> do(qq{INSERT into indicators (symbol, indicator, value, date) VALUES('$tick','$indname',$data{$tick}{$indname}{$day},'$day')});
        $inserted++;
    }
}
print "Inserted $inserted entries in database.\n";

# clean up
#
$dbh->disconnect;
print "Done!\n";

##### END #####


# TMP TMP .... remove later!
# $ii = 0;  
# foreach $in (@datein) {
#     $ii++;
#     $hday{$ii} = $in;  
#     $dayindex{$in} = $ii;  
#     #print "hday = $in, index = $ii\n"; exit if $ii > 10;
# }
# end of TMP TMP .... remove later!
# 

# $atr = atr($tick,\%hday,\%dayindex,\%maxp,\%minp,\%closep,$par,'2012-07-11');
# print "ATR: $data{$tick}{ATR10}{'2012-07-11'}  and simple: $atr\n";


#!/usr/bin/perl -I/Users/tdall/copyExecs
# 

require "utils.pl";
require "trader_utils.pl";
$|=1;
$start = '2012-01-31';
#$end = '2012-01-31';
$end = shift @ARGV;
die "3225ge" unless $end;
chomp $end;
$timeframe = 'day';
$tick = 'BMW.DE';
$peri = 14;
$path = "/Users/tdall/geniustrader/";
$dbfile = "/Users/tdall/geniustrader/traderThomas";
@date = `sqlite3 "$dbfile" "SELECT date \\
                       FROM stockprices \\
                       WHERE symbol = '$tick' AND date<='$end'\\
                       ORDER BY date \\
                       DESC LIMIT 8"`; #print @data, "\n";
chomp @date;
@obv = doOBV($tick, $dbfile, 8, $end); 
$i = 0;
foreach $day (reverse @date) {
    #@test = dmi($tick, $dbfile, 14, $day);
#    @adx = adx($tick, $dbfile, 14, $day);
#    $tr14 = rsi($tick, $dbfile, 14, $day);
#    $au = aroonUp($tick, $dbfile, 25, $day);
#    $ad = aroonDown($tick, $dbfile, 25, $day);
#    $sma5 = sma($tick, $dbfile, 5, $day);
#    $sma26 = sma($tick, $dbfile, 26, $day);
    $obvs = OBVs($tick, $dbfile, 14, $day);
    #$watr = atrW($tick, $dbfile, 14, $day);
#    printf "$day: simple ATR = %.3f, Wilder ATR = %3.f\n", $tr14, $watr;
#    printf "$day: RSI = %.3f, ADX = %.3f, SMA5 = %.2f, SMA26 = %.2f\n", $tr14, $adx[0],$sma5,$sma26;
    #exit;
    printf "$day: OBV = $obv[$i], slope = %.3f\n", $obvs;
    $i++;
}
#exit;


exit();

$day = shift @datel;  # take the seed value
($dmi0, $dip0, $dim0, $atr0) = dmi($tick, $dbfile, 14, $day);
$adx0 = adx($tick, $dbfile, 14, $day);
$numd = @datel;
for ($i=0; $i < $numd; $i++) {
    #print "$datel[$i] .. ";
    ($dmi1, $dip1, $dim1, $atr1) = dmi($tick, $dbfile, 1, $datel[$i]);  # values for today only 
    $atr = $atr0 - $atr0/14.0 + $atr1/14.0;
    $dip = $dip0 - $dip0/14.0 + $dip1/14.0;
    $dim = $dim0 - $dim0/14.0 + $dim1/14.0;
    $atr0 = $atr;  
    $dip0 = $dip;  $dim0 = $dim;
    $adx = $adx0 - $adx0/14.0 + $dmi1/14.0;
    #$adx = ()
    $adx0 = $adx;
}
printf "$end: Wilder ATR = %.3f, ADX = %.3f\n", $atr, $adx;
$atrnew = atr($tick, $dbfile, 14.0, $end);
printf "new subroutine ATR = %.3f\n", $atrnew; 

# ($dmi, $dip, $dim, $atr) = dmi($tick, $dbfile, $peri, $date)
sub dmiOLD {
    # ($dmi, $dip, $dim, $atr) = dmi($tick, $dbfile, $peri, $date)
    use strict;
    my ($tick, $dbfile, $peri, $end) = @_;    
    my ($m, $i, $dip, $dim, $dmi);
    my $qperi = $peri + 1;
    
    my @ph = `sqlite3 "$dbfile" "SELECT day_high \\
                           FROM stockprices \\
                           WHERE symbol = '$tick' AND date<='$end'\\
                           ORDER BY date \\
                           DESC LIMIT $qperi"`; #print @data, "\n";
    my @pl = `sqlite3 "$dbfile" "SELECT day_low \\
                           FROM stockprices \\
                           WHERE symbol = '$tick' AND date<='$end'\\
                           ORDER BY date \\
                           DESC LIMIT $qperi"`; #print @data, "\n";
    my @pc = `sqlite3 "$dbfile" "SELECT day_close \\
                           FROM stockprices \\
                           WHERE symbol = '$tick' AND date<='$end'\\
                           ORDER BY date \\
                           DESC LIMIT $qperi"`; #print @data, "\n";
    chomp @ph; chomp @pl; chomp @pc;
    # directional movement (DM) is the largest part of the current trading range that is outside the previous trading range.
    # di = max (dh-yh, yl-dl)
    my $admp = 0.0; my $admm = 0.0; my $atr = 0.0;
    for ($i = 0; $i < $peri; $i++) {   # $peri  or $peri-1 ????
        if ($ph[$i]-$ph[$i+1] > $pl[$i+1]-$pl[$i]  &&  $ph[$i]-$ph[$i+1] > 0.0) {
            $admp += $ph[$i]-$ph[$i+1];
        } elsif ($pl[$i+1]-$pl[$i] > $ph[$i]-$ph[$i+1]  &&  $pl[$i+1]-$pl[$i] > 0.0) {
            $admm += $pl[$i+1]-$pl[$i];
        } else {
            $admm = 0.0;  $admp = 0.0;
        }
        $m = max( ($ph[$i]-$pl[$i], $ph[$i]-$pc[$i+1], $pc[$i+1]-$pl[$i]) );
        $atr += $m;
    }
    $atr /= $peri;
    $admp /= $peri;  $dip = $admp *100.0 / $atr; 
    $admm /= $peri;  $dim = $admm *100.0 / $atr; #printf "+:%.3f -:%.3f ", $dip, $dim;
    if ($dip + $dim == 0.0) {
        $dmi = 0.0;
    } else {
        $dmi = abs( $dip - $dim ) * 100.0 / ($dip + $dim);
    }
    return ($dmi, $dip, $dim, $atr);
}

# $adx = adx($tick, $dbfile, $peri, $date)
sub adxOLD {
    # $adx = adx($tick, $dbfile, $peri, $date)
    #get the dates we're going to use in the averageing
    use strict;
    my ($tick, $dbfile, $peri, $end) = @_;   
    my (@dmi, $day); 
    my @date = `sqlite3 "$dbfile" "SELECT date \\
                       FROM stockprices \\
                       WHERE symbol = '$tick' AND date<='$end'\\
                       ORDER BY date \\
                       DESC LIMIT $peri"`; #print @data, "\n";
    chomp @date;
    my $adx = 0.0;
    foreach $day (@date) {
        @dmi = dmi($tick, $dbfile, $peri, $day);
        $adx += $dmi[0];
    }
    $adx /= $peri;
    return $adx;
}
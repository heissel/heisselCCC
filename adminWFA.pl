#!/usr/bin/perl -I/Users/tdall/copyExecs

# run with an end date, length of optimization interval (months), and length of 'live' interval
# e.g.:     adminWFA.pl 2013.05.01 5 1
# 
# from the params, calc the start dates of the optimization trade_* files and list the date params to use
# as well as the 'live' intervals.
# The idea is then, while this program pauses, to run the tester in MT4 in the prescribed order 
# and to process the outputs.  Then, upon continuation, this program takes the trade* files and 
# calculates the performance data.

require "utils.pl";
require "trader_utils.pl";

$cycles = 4;
($endDay, $intervalOpt, $intervalLive) = @ARGV;

($yr, $monthLast, $dayPivot) = split /\./, $endDay;
if ($dayPivot > 28) {
    $dayPivot = 28;
}
$dayPivot = sprintf "%2.2d", $dayPivot;
if ($intervalOpt > 12) {
    die "Cannot accommodate intervals > 12 months...\n";
}

# standard is to use 15 cycles
$yrLive = $yr; $monthLive = $monthLast;
$i = 0;
while ($i < $cycles) {
    $monthEnd = $monthLive; $yrEnd = $yrLive;
    $monthLive = $monthEnd-$intervalLive;
    if ($monthLive < 1) {
        $monthLive += 12;
        $yrLive--;
    }
    $monthThis = $monthLive-$intervalOpt; $yrThis=$yrLive;
    if ($monthThis < 1) {
        $monthThis += 12;
        $yrThis--;
    }
    printf "start Opt = %4.4d.%2.2d.%2.2d, start Live = %4.4d.%2.2d.%2.2d, end = %4.4d.%2.2d.%2.2d\n",$yrThis,$monthThis,$dayPivot,$yrLive,$monthLive,$dayPivot,$yrEnd,$monthEnd,$dayPivot;
    unshift @dateEnd, sprintf("%4.4d.%2.2d.%2.2d",$yrEnd,$monthEnd,$dayPivot);
    unshift @dateLive, sprintf("%4.4d.%2.2d.%2.2d",$yrLive,$monthLive,$dayPivot);
    unshift @dateOpt, sprintf("%4.4d.%2.2d.%2.2d",$yrThis,$monthThis,$dayPivot);
    $i++;
}

print "Cycle\tStartOpt    StartLive   EndLive\n------------------------------------------------\n";
for ($i=0;$i<$cycles;$i++) {
    $j=$i+1;
    print "$j\t$dateOpt[$i]  $dateLive[$i]  $dateEnd[$i]\n";
}

# save unique stamp for the time we are pausing the execution
chomp( $unique = `date "+%Y%m%dT%H%M%S"` );
print "------------------------------------------------\n";
print "Now execute the backtest optimizations in this order. When best parameters have been found,
run the tester without optimization, then run mkMT4tradefile.pl.  Then go back to the tester
and run it with the period from StartLive -- EndLive, come back, run mkMT4tradefile.pl again.
Then go on with the next cycle.  When done, hit return to continue... "; $dum=<STDIN>;

# get the list of trade* files crreated since the unique stamp
@list = ();
while (defined($name=<trades_*>)) {
    $name =~ /_(\d{8}T\d{6})_MT4/;
    $pattern = $1;
        push @list, $name;
#     if ($pattern gt $unique) {
#         push @list, $name;
#         print "$name comes after $unique\n";
#     } else {
#         print "$name is before: $pattern < $unique\n";
#     }
}
$nlist = @list;
if ($nlist != 2*$cycles) {
    print "WARNING! not the right nnumber of trade-files.\n";
}

@rOpt = (); @sqOpt = (); @rLive = (); @sqLive = (); @rtotOpt = (); @rtotLive = ();
for ($i=0; $i<$cycles; $i++) {
    $optFile = $list[$i*2];
    $liveFile = $list[$i*2+1];
    ($rmult,$sq,$n,$stderr,$npos,$nneg,$meanpos,$sigpos,$meanneg,$signeg,$maxr,$rpointer) = getTradeStats($optFile);
    push @rOpt, $rmult;
    push @sqOpt, $sq;
    push @rtotOpt, @$rpointer;
    ($rmult,$sq,$n,$stderr,$npos,$nneg,$meanpos,$sigpos,$meanneg,$signeg,$maxr,$rpointer) = getTradeStats($liveFile);
    push @rLive, $rmult;
    push @sqLive, $sq;
    push @rtotLive, @$rpointer;
    printf "eta_r(%2.2d) = %.3f\n",$i+1,$rLive[$i]/$rOpt[$i];
}

printf "eta_r(sum) = %.3f\n",sum(@rLive)/sum(@rOpt);

printf "eta_r(isum) = %.3f\n",(sum(@rtotLive)/@rtotLive)/(sum(@rtotOpt)/@rtotOpt);
printf "<R>_live = %.2f, <R>_opt = %.2f\n",(sum(@rtotLive)/@rtotLive),(sum(@rtotOpt)/@rtotOpt);



sub getTradeStats {
    use strict;
    my $file = shift;
    my ($in, $n, $meanr, $sigr,$npos,$nneg,$meanpos,$meanneg,$sigpos,$signeg,$stderr,$maxr,$rp);
    my @in; my @rpos; my @rneg; 
    my @rmult = ();    
    
    open IN, "<$file" or die "cannot open file=$file\n";
    $maxr = 0.0;
    while (chomp($in = <IN>)) {
        next unless ($in =~ /\d:\t/);
        @in = split /\s+/, $in;
        push @rmult, $in[8];
        $maxr = $in[8] if ($in[8]>$maxr);
    }
    close IN;
    foreach $in (@rmult) {
        if ($in > 0.0) {
            push @rpos, $in;
        } else {
            push @rneg, $in;
        }
    }
    $n = @rmult;   # number of R values in the distribution
    if ($n < 3) {
        warn "Error; $n trades taken.\n";
    }
    $meanr = sum(@rmult) / $n;
    $sigr = sigma($meanr, @rmult);
    $npos = @rpos;  $nneg = @rneg;
    $meanpos = sum(@rpos)/$npos;
    $sigpos = sigma($meanpos,@rpos);
    $meanneg = sum(@rneg)/$nneg;
    $signeg = sigma($meanneg,@rneg);
    $stderr = 0.0; $stderr = 100.0*sqrt($n+1)/$n if ($n>0);
    $rp = \@rmult;
    return ($meanr,$meanr/$sigr,$n,$stderr,$npos,$nneg,$meanpos,$sigpos,$meanneg,$signeg,$maxr,$rp);
}
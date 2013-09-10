#!/usr/bin/perl -I/Users/tdall/copyExecs
#
# generate reliability tests - new version (Feb.2013)
# currently focused on Darvas-AllTime
#
#
# arg 1 = ticker symbol
# arg 2 = starting date
# arg 3 = end date
# arg 4 = system name; entry strategy/setup/signal
# arg 5 = max number of days forward in reliability

use Getopt::Std;
use PGPLOT;
use strict;
require "utils.pl";
require "pg_utils.pl";
require "trader_utils.pl";
getopts('wpC:');
#my ($opt_w, $opt_p);
###
### setting variables and options
###
###################################
    my $numa = @ARGV;
    die "Not enough args\n" unless ($numa == 5);
    my ($tick, $dayBegin, $dayEnd, $system, $maxd) = @ARGV;
    my $path = "/Users/tdall/geniustrader/";
    my $dbfile = "/Users/tdall/geniustrader/traderThomas";
    my $btdir = "/Users/tdall/geniustrader/Backtests/";
    my @days = (3,5,10,15,20,40,80);   # if adjusting, also set $maxd
    my @alldays = (1 .. $maxd);  # for the MAE, MPE calcs.
    my $npdays = @days;
    my $nalldays = @alldays;
    my ($device, $unique, $intraday, $comment, $in, $inprice, @tmp, $day, @price, $price, $i, $outtext);
    my ($openp, $max, $min, $pc, $entrySig, $d1, $d2, $d3, $d4, $realday, $cnt);
    my (@winx, @winy, @lossx, @lossy);
    my %prof = (); # number of profitables at the close
    my %rmax = (); # max positive excursion for the day
    my %rmin = (); # max adverse excursion of the day
    my @rmax = (), my @rmin = ();
    my %rclose = (); # R at the close
    my %rpos = ();  my %rneg = ();   # summing positive and negative R's using close prices
    foreach $day (@days) {
        $prof{$day} = 0;
    }
    chomp( $unique = `date "+%Y%m%dT%H%M%S"` );
    open UNIQ, ">$btdir/unique.txt" or die "nzt238dHW44";
    print UNIQ $unique;
    close UNIQ;
    $|=1;
    $intraday = 0;
    if ($opt_C) {
        $comment = $opt_C . "\n";
    } else {
        $comment = "";
    }
    if ($opt_p) {
        $device = "${btdir}relp_${tick}_${unique}.png/PNG"; print "plotting to PNG";
    } else {
        $device = "/XSERVE";
    }
    my $norw = "n";  # narrowest stop if several options are given
    my $whichway = "";   # long or short
    my $opentrade = "";  # long or short
    my $donotenter = "";
    my $nbothlim = 0;
    my %stop = (); 
    my %inprice = (); my %direction = (); my @dayTrade = ();
    $numdays = 0;
    my $indexday = 0;
    # get the range of valid dates - ugly hack, but it works...
    my @date = `sqlite3 "$dbfile" "SELECT date \\
                                           FROM stockprices \\
                                           WHERE symbol = '$tick' \\
                                           ORDER BY date \\
                                           DESC"`;
    chomp(@date); # contains the dates with most recent first
    if ($dayBegin lt $date[-12]) {
        print "ERROR: $dayBegin given, but first allowed date is $date[-12]\n";
        exit();
    }
    if ($dayEnd gt $date[$maxd]) {
        print "ERROR: $dayEnd given, but last allowed date is $date[$maxd]\n";
        exit();
    }
    my @datein = reverse @date;
##############################
### 
### end of variables and options definitions
###

######
## 
## start of main program
##
######

# opening files and preparing
my $ofile = "${btdir}rel_${tick}_${unique}.txt";
open OUT, ">$ofile" || die "cannot create $ofile";
my $dfile = "${btdir}d_${tick}_${unique}.txt";
open DATE, ">$dfile" || die "cannot create $dfile";
#
# MAIN LOOP, day by day, look for signals
#
MAIN:foreach $day (@datein) {

    $indexday++;
	next if ($day lt $dayBegin); 
	last if ($day gt $dayEnd);
	$numdays++;
	$price = `sqlite3 "$dbfile" "SELECT day_open, day_high, day_low, day_close \\
               FROM stockprices WHERE symbol = '$tick' AND date = '$day' \\
               ORDER BY date DESC"`;
	chomp($price);
	($openp, $max, $min, $pc) = split /\|/, $price; 

	# 1. any new signals? We only care about the entry signals here
	#
	($entrySig, $d1, $outtext, $d3, $d4) = getSignal($tick, $system, $dbfile, $day, $opentrade, 0, 0, 0, 0);    # $entrySig is either "long", "short", or ""
    if ($donotenter eq $entrySig) {
        $entrySig = "";
    }
    $donotenter = "";
    if ($p10wk{$day} && $opt_w) {
        # using the value of today for tomorrow since we do stop-buy...
        if ($p10wk{$day} eq "x") {
            $donotenter = "short";
        } else {
            $donotenter = "long";
        }
    }
	if ($entrySig) {	
        $d4 = "";
		if ($system =~ /VolB\w{1}\d/) {
		    # entering during the day, so not at the close but at a pre-set stop-buy
		    # In case both long+short signal given, then record both.
		    # $txt = sprintf "%.4f_%.4f_%.4f_short%.4f", $p+$fac*$tr,$tr,$fac,$p-$fac*$tr;
		    if ($outtext =~ /X/) {
		        ($d1, $outtext) = split /X/, $outtext;
		    }
		    ($inprice, $d2, $d3, $d4) = split /_/, $outtext;
		    if ($d4) {
		        #print "d4 = $d4 -- out = $outtext --";
		        $nbothlim++;
		        $d4 =~ /(\D+)(\d+.?\d*)/;
		        $whichway = $1; $in = $2;
		        push @dayTrade, "$day.0";
		        $inprice{"$day.0"} = $in;
		        $direction{"$day.0"} = $whichway;
		        $stop{"$day.0"} = getStop($sysInitStop, $dbfile, $day, 0.0, 0.0, $tick, $whichway, $in, $in, 0, 0, $norw);
		        #printf "$day.0\t$whichway\t%.2f  %.2f\n", $in, $stop{"$day.0"};
		        print ".";
		    }
		} else {
            $inprice = $pc;
        }
        push @dayTrade, $day;
        $inprice{$day} = $inprice;
        $direction{$day} = $entrySig;
        $stop{$day} = getStop($sysInitStop, $dbfile, $day, 0.0, 0.0, $tick, $entrySig, $inprice, $inprice, 0, 0, $norw);
#        printf "$day\t$entrySig\t%.2f  %.2f\n", $inprice, $stop{$day};
        print ".";
    }

}
# end of MAIN LOOP
#
#

print ".";
# calculate the reliability of the system for day 1, 2, etc...
#
# random entry will give around 50% (45-55). This should be at least 55%, more is better.
#
foreach $day (@dayTrade) {
    print DATE "$day\t$direction{$day}\n";
    print "\b"; if ($cnt) { print "-"; $cnt=0; } else { print "|"; $cnt=1;}
    if ($day =~ /(\d{4}-\d{2}-\d{2}).0/) {
        $realday = $1;
    } else {
        $realday = $day;
    }
	@price = getPriceAfterDays($tick, $dbfile, $realday, \@days);
	@prH = getOHLCAfterDays("high", $tick, $dbfile, $realday, \@alldays);
	@prL = getOHLCAfterDays("low", $tick, $dbfile, $realday, \@alldays);
	for ($i=0; $i < $npdays; $i++) {	
		if ($direction{$day} eq "long") {
		    if ($price[$i] - $inprice{$day} > 0) {
		        $prof{$days[$i]}++;  # it was profitable, so we count 1
		        $rpos{$days[$i]} += ($price[$i] - $inprice{$day})/($inprice{$day} - $stop{$day});
		    } else {
		        $rneg{$days[$i]} += ($price[$i] - $inprice{$day})/($inprice{$day} - $stop{$day});
		    }
		} else {  # if "short"
		    if ($price[$i] - $inprice{$day} < 0) {
		        $prof{$days[$i]}++;  # it was profitable, so we count 1
		        $rpos{$days[$i]} += ($price[$i] - $inprice{$day})/($inprice{$day} - $stop{$day});
		    } else {
		        $rneg{$days[$i]} += ($price[$i] - $inprice{$day})/($inprice{$day} - $stop{$day});
		    }
		}
	}
	($d1,$rmax) = low_and_high(@prH);
	($rmin,$d1) = low_and_high(@prL);
	if ($direction{$day} eq "long") {
        push @rmax, ($rmax - $inprice{$day})/($inprice{$day} - $stop{$day});
        push @rmin, ($rmin - $inprice{$day})/($inprice{$day} - $stop{$day});
    } elsif ($direction{$day} eq "short") {
        push @rmax, ($rmin - $inprice{$day})/($inprice{$day} - $stop{$day});
        push @rmin, ($rmax - $inprice{$day})/($inprice{$day} - $stop{$day});
    } else {
        die "error in direction: $direction{$day}\n";
    }
}
print "\n"; 	
my $tot = @dayTrade;
my $stdevp = sqrt($tot + 1)/$tot;  # standard percentage error on the derived numbers, just from number statistics
printf "$tot trades in $numdays days, %.2f trades/day. Std percentage error = %.1f\n", $tot/$numdays, $stdevp*100.0;
print "Reliability after ... days:\t<R>pos\t<R>neg\n";
printf OUT "$tot trades in $numdays days, %.2f trades/day. Std percentage error = %.1f\n", $tot/$numdays, $stdevp*100.0;
printf OUT "$comment";
print OUT "Reliability after ... days:\t<R>pos\t<R>neg\n";
foreach $day (@days) {
    next unless $prof{$day} > 0;
    if ($tot-$prof{$day} > 0) {
        $nprof = $rneg{$day}/($tot-$prof{$day});
    } else {
        $nprof = 0;
    } 
	printf "%3.3s days :: %.2f% +/- %.2f%\t%.2f\t%.2f\n", $day, 
	    100.0*$prof{$day}/$tot, 100.0*sqrt($prof{$day})/$tot, 
	    $rpos{$day}/$prof{$day}, $nprof; 
	printf OUT "%3.3s days :: %.2f% +/- %.2f%\t%.2f\t%.2f\n", $day, 
	    100.0*$prof{$day}/$tot, 100.0*sqrt($prof{$day})/$tot, 
	    $rpos{$day}/$prof{$day}, $nprof; 
}

# preparing stats and plots of MAE and MPE
#
my $nume = @rmax;
for ($i=0; $i < $nume; $i++) {
    # sort into stopped out and non-stopped outs
    if ($rmin[$i] > -1.0) {
        push @winx, $rmin[$i];
        push @winy, $rmax[$i];
    } else {
        push @lossx, $rmin[$i];
        push @lossy, $rmax[$i];
    }
}
$sumw = sum(@winy);  # sum of all max-R in the positive range
$nw = @winy;
$suml = @lossy;  # only the number here, assuming they all stop out at -1R.
$rexp = ($sumw - $suml)/$nume;  # raw "R" per trade
$rdiff = $sumw - $suml;
$twin = sprintf "sum(MPE) = %.2f R (# = $nw)", $sumw;  # text for upper right corner
$twin2 = sprintf "rawR/trade = %.2f R", $rexp;
$twin3 = sprintf "diffR(MPE-MAE) = %.2f R", $rdiff;
$twin4 = sprintf "rawR/day = %.2f R", ($sumw - $suml)/$numdays;
$tloss = sprintf "sum(MAE=-1R) = %.1f R", $suml;
if ($nbothlim) {
    $extra = sprintf "-- $nbothlim double-entries --";
}
printf "sum(MPE) = %.2fR (# = $nw), sum(MAE=-1R) = %.1fR (# = $suml). DiffR = %.2fR ($nume trades, $numdays days), rawR/trade = %.2fR /day = %.2fR\n", 
    $sumw, $suml, $rdiff, $rexp, ($sumw - $suml)/$numdays;
print OUT "$tick: $system, $sysInitStop, $dayBegin--$dayEnd, <=$maxd days ($nbothlim double-entry days)\n";
printf OUT "sum(MPE) = %.2fR (# = $nw), sum(MAE=-1R) = %.1fR (# = $suml). DiffR = %.2fR ($nume trades, $numdays days), rawR/trade = %.2fR /day = %.2fR\n", 
    $sumw, $suml, $rdiff, $rexp, ($sumw - $suml)/$numdays;
printf OUT "toread: %.2f\t$nw\t%.1f\t$suml\t%.2f\t$nume\t$numdays\t%.2f\t%.2f\n", 
    $sumw, $suml, $rdiff, $rexp, ($sumw - $suml)/$numdays;
close OUT;
close DATE;

# making the plot
#
    $font = 2;
    $linewidth = 2;
    $charheight = 1.2;
    pgbeg(0,$device,1,1) || warn "pgbeg on $device says: $!\n"; # Open plot device 
    pgscf($font); # Set character font 
    pgslw($linewidth); # Set line width 
    pgsch($charheight); # Set character height 
    pgsci(1);  # default colour
my ($xplot_low, $xplot_hig) = low_and_high(@rmin);  # dereferences the array pointer
my $mean = ( $xplot_hig - $xplot_low ) * 0.02;
$xplot_hig += $mean;
$xplot_low -= $mean;
my ($yplot_low, $yplot_hig) = low_and_high(@rmax);  # dereferences the array pointer
$mean = ( $yplot_hig - $yplot_low ) * 0.02;
$yplot_hig += $mean;
$yplot_low -= $mean;
my $symbol = 17;
pgenv($xplot_low, $xplot_hig, $yplot_low, $yplot_hig, 0, 0);
pgsci(15);
pgline(2, [$xplot_hig,$xplot_low], [0.0,0.0]);
pgsci(5);
pgpoint($nume,\@rmin,\@rmax,$symbol);    # plot the points    
pgsci(11);
pgline(2, [-1.0,-1.0], [$yplot_low,$yplot_hig]);
pgsch(0.8);
pgmtext('T', -1.0, 0.98, 1, "$twin");
pgsci(1);
pglabel("MAE", "MPE", "$tick: $system, $sysInitStop, $dayBegin--$dayEnd, <=$maxd days");
pgsci(13);
pgmtext('T', -1.0, 0.02, 0, "$tloss");
pgsci(1);
pgmtext('LV', -1.0, 0.65, 0, "total # = $nume in $numdays days");
pgmtext('LV', -1.0, 0.6, 0, "$twin2");
pgmtext('LV', -1.0, 0.55, 0, "$twin4");
pgmtext('LV', -1.0, 0.5, 0, "$twin3");
if ($nbothlim) {
    pgmtext('LV', -1.0, 0.45, 0, "$extra");
}
pgsls(2);
pgline(2, [-30,30], [-30,30]);
pgsls(1);
pgend;



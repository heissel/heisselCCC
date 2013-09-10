#!/usr/bin/perl -I/Users/tdall/copyExecs
#
#   tradeManager.pl [yyyy-mm-dd]
##### [-i] runs only on the intra-day/stop-buy trades. 
# [-r risk] is the risk size used for this day
#           for open trade management, run with previous date (that's when the trades were defined).
# [-c tick] some change (entry/exit) is required, but only for this tick
# [-s tick] give new stop levels for an open trade in this tick
use Carp;
use Getopt::Std;
use PGPLOT;
#use GD::Graph::points;
require "utils.pl";
require "pg_utils.pl";
require "trader_utilsOLD.pl";
getopts('i:c:s:r:');
$day = shift;
$skip = "";
$|=1;
$didsomething = 0;

# getting the global varaibles etc.
&readGlobalParams();
if ($opt_c) {
    &updateDone("${dailydir}tradMan_$day.log",$tickOpenI);
} elsif ($opt_s) {
    &updateStop($opt_s, $tickOpenI);
} else {
    # The first run, after closing of the markets.  Calculates EOD trades, and
    # lists entry points for intraday stop-buy orders for next day.
    unless (-e "${dailydir}tradMan_$day.log") {
        open LOG, ">${dailydir}tradMan_$day.log" or die "cannot open log on $day\n";
        
        # first task: any new signals from the watch list?
        open W, "<$tickWatch" or die "cannot open $tickWatch";
        while ($in = <W>) {
            chomp $in;
            next if $in =~ /^#/;
            ($sysname, @ticks) = split /\s+/, $in;
            $sysFile = "${path}Scripts/${sysname}.gtsys";
            print "Applying $sysname to following stocks: ", @ticks, "\n";
            print LOG "$day: Applying $sysname to following stocks:\n";
            open SYS, "<$sysFile" or die "no can open $sysFile";
            open ID, ">newtradeposs.log" or die "fsdfsfsf ";
            print ID "$day\tTICK\tDIR\tINP\tLIM\tISTOP\tPOS\tcomment\n--------------------------------------------\n";
            while ($line = <SYS>) {
                next if $line =~ /^#/;
                if ($line =~ /^risk size/) {
                    chomp($riskP = <SYS>);
                } elsif ($line =~ /system type/) {
                    chomp($stype = <SYS>);
                } elsif ($line =~ /entry signal long/) {
                    chomp($system = <SYS>);
                } elsif ($line =~ /entry signal short/) {  # so far always the same...
                } elsif ($line =~ /initial stop long/) {
                    chomp($sysInitStop = <SYS>);
                } elsif ($line =~ /initial stop short/) {  # so far always the same...
                } elsif ($line =~ /target/) {
                    chomp($dum = <SYS>);
                    @dum = split /\s+/, $dum;
                    if ($dum[0] eq "yes") {
                        $optT = $dum[1];
                        $optT =~ /([oxc])/;
                        $whichPriceT = $1;
                        ($iTarget, $targMul) = split /$whichPriceT/, $optT;
                        $targMul = 1.0 unless $targMul;
                        #print "splits into $iTarget and $targMul\n"; exit;
                        warn "Error? Found price=$whichPriceT and target parameters $iTarget,$targetMul... " unless ($whichPriceT =~ /[oxc]/);

                    } else {
                        $optT = "";
                    }
                } elsif ($line =~ /trail stop long/) {
                    chomp($sysStop = <SYS>);
                } elsif ($line =~ /trail stop short/) {  # so far always the same...
                } elsif ($line =~ /exit signal long/) {
                    chomp( $dum = <SYS> );
                    @dum = split /\s+/, $dum;
                    $sysExit = $dum[0];
                    if ($dum[1] eq "warn") {
                        $warn = 1;
                    } else {
                        $warn = 0;
                    }
                } elsif ($line =~ /exit signal short/) {  # so far always the same...
                }
            }
            foreach $tick (@ticks) {
                chomp( $dbday = `sqlite3 "$dbfile" "SELECT date \\
                                           FROM stockprices \\
                                           WHERE symbol = '$tick' \\
                                           AND date <= '$day' \\
                                           ORDER BY date \\
                                           DESC LIMIT 1"` );
                if ($dbday ne $day) {
                    print "Skipping $tick - no data for $day\n";
                    $skip .= $tick;
                    next;
                }
                $didsomething = 1;
                if ($stype =~ /endofday/) {
                    ($entrySig, $exitSig, $outtext, $outtx2, $exitp) = getSignal($tick, $system, $dbfile, $day, "", 0);
                    if ($entrySig) {
                        chomp( $inprice = `sqlite3 "$dbfile" "SELECT day_close \\
                                               FROM stockprices \\
                                               WHERE symbol = '$tick' \\
                                               AND date = '$day' \\
                                               ORDER BY date \\
                                               DESC LIMIT 1"` );
                        $istop = getStop($sysInitStop, $dbfile, $day, 0.0, 0.0, $tick, $entrySig, $inprice, $inprice, 0, 0);   # last arg is age of trade
                        printf "$day: $system says $entrySig entry in $tick ($outtext $outtx2); Entry = %.2f, istop = %.2f\n", $inprice, $istop;
                        print LOG "$day\t$tick\t$entrySig\n";
                    }
                    if ($sysExit ne $system && $sysExit) {
                        ($dum, $exitSig, $outtext2, $outtx2, $exitp) = getSignal($tick, $sysExit, $dbfile, $day, "", 0);
                    }
                    if ($exitSig) {
                        print "$day: $sysExit gives exit signal for $exitSig positions in $tick\n";
                        print LOG "$day\t$tick\tEXIT:$exitSig\n";
                    }
                } elsif ($stype =~ /intraday/) {
                    # calculates the stop-buy etc to enter for next day
                    ($lentry, $lstop, $sentry, $sstop) = getIntraDayEntry($tick, $dbfile, $system, $sysInitStop, $day);
                    $poszl = int($risk/abs($lentry-$lstop));
                    $poszs = int($risk/abs($sentry-$sstop));
                    chomp( $inprice = `sqlite3 "$dbfile" "SELECT day_close \\
                                               FROM stockprices \\
                                               WHERE symbol = '$tick' \\
                                               AND date = '$day' \\
                                               ORDER BY date \\
                                               DESC LIMIT 1"` );
                    print "(gt close price was $inprice) Real close price for $tick? [return if OK] "; chomp($dum = <STDIN>);
                    if ($dum) {
                        $close = $dum;
                    } else {
                        $close = $inprice;
                    }
                    printf "$day: $system on $tick says: stop-buy LONG = %.3f, istop = %.3f -- size = $poszl\n", $close+$lentry-$inprice,$close+$lstop-$inprice;
                    printf "$day: $system on $tick says: stop-buy SHRT = %.3f, istop = %.3f -- size = $poszs\n", $close-$inprice+$sentry,$close+$sstop-$inprice;
                    printf LOG "i$day\t$tick\tlong\t%.3f\t%.3f\ts=$sysStop\n",$close+$lentry-$inprice,$close+$lstop-$inprice;
                    printf LOG "i$day\t$tick\tshort\t%.3f\t%.3f\ts=$sysStop\n",$close-$inprice+$sentry,$close+$sstop-$inprice;
                    printf ID "$day\t$tick\tLONG\t%.3f\t%.3f\t%.3f\t%d\ts=$sysStop\n",$close+$lentry-$inprice,$close+($lentry-$inprice)*$limf,$close+$lstop-$inprice,$poszl;
                    printf ID "$day\t$tick\tSHORT\t%.3f\t%.3f\t%.3f\t%d\ts=$sysStop\n",$close-$inprice+$sentry,$close-($inprice-$sentry)*$limf,$close+$sstop-$inprice,$poszs;
                    print ID "--------------------------------------------\n";
                }
            }
        }
        close W;
        close ID;
        
        # second task: updates to stops for open positions for the end-of-day trades
        # open the open trades file
        open OP, "<$tickOpen" or die "cannot open $tickOpen\n";
        chomp( @open = <OP> );
        close OP;
        @newopen = ();
        foreach $entry (@open) {    
            ($tick, $direction, $inprice, $istop, $stop, $dayoftrade) = split /\s+/, $entry;
            next if ($skip =~ /$tick/);
            $dayoftrade++;
            if ($optT) {
                $targFac = $iTarget * abs($inprice - $istop);
                if ($direction eq "long") {
                    $targetPrice = $inprice + $targFac;
                } elsif ($direction eq "short") {
                    $targetPrice = $inprice - $targFac;
                }
            }
            chomp( $price = `sqlite3 "$dbfile" "SELECT day_close \\
                                           FROM stockprices \\
                                           WHERE symbol = '$tick' \\
                                           AND date = '$day' \\
                                           ORDER BY date \\
                                           DESC LIMIT 1"` );
###
# somehow enter the adjustment of the target for intraday, using xtreme prices.
#		} elsif ($opt_T  &&  (  ($curprice > $targetPrice && $opentrade eq "long")  ||  ($curprice < $targetPrice && $opentrade eq "short")  )  ) {
# 		    if ($direction{$dayTrade} eq "long") {
# 		        $targetPrice += $targMul * $targFac;
# 		    } elsif ($direction{$dayTrade} eq "short") {
# 		        $targetPrice = $inprice{$dayTrade} - 10.0 * $targFac;
# 		        $targetPrice -= $targMul * $targFac;
# 		    }
###
            $dum = $stop;
            $stop = getStop($sysStop, $dbfile, $day, $stop, $istop, $tick, $direction, $inprice, $price, $targetPrice, $dayoftrade, "n");
            printf "$day: Day $dayoftrade of $direction position in $tick: Previous stop = %.2f, New stop = %.2f\n", $dum, $stop;
            printf LOG "$day: Day $dayoftrade of $direction position in $tick: Previous stop = %.2f, New stop = %.2f\n", $dum, $stop;
            push @newopen, sprintf "$tick\t$direction\t%.2f\t%.2f\t%.2f\t%d\n", $inprice, $istop, $stop, $dayoftrade;
        }
        open OP, ">$tickOpen" or die "cannot open $tickOpen\n";
        print OP @newopen;
        close OP;
        close LOG;
        unlink "${dailydir}tradMan_$day.log" unless $didsomething;
    } else {
        # last tasks - after hours, when EOD trades have been entered: update with whatever was actually done
        &updateDone("${dailydir}tradMan_$day.log",$tickOpen);
    }
}

sub updateStop {
    my ($tick, $opentick) = @_;
    @newopen = ();
    open OP, "<$opentick" or die "cannot open $opentick\n";
    chomp( @open = <OP> );
    close OP;
    foreach $in (@open) {
        if ($in =~ /$tick/) {
            ($t, $dir, $inp, $istop, $stop, $daysin, $sysStop) = split /\t/, $in;
            print "using stop = $sysStop.\n";
            print "$tick: Day $daysin of $dir, entry at $inp, stop = $stop (istop = $istop). Current price? [return to skip] "; chomp($p=<STDIN>);
            if ($p) {
                # TODO: include target price
                # note: updating stop intraday will only have effect if some sort of stop-modifyer is used.
                $ostop = $stop;
                $stop = getStop($sysStop, $dbfile, $day, $stop, $istop, $tick, $dir, $inp, $p, $targetPrice, $daysin, "ni");
                printf "Change stop %.3f -> %.3f? [Y/n] ", $ostop, $stop; chomp($dum=<STDIN>);
                unless ($dum =~ /[nN]/) {
                    push @newopen, sprintf "$tick\t$dir\t%.3f\t%.3f\t%.3f\t%d\t$sysStop\n", $inp, $istop, $stop, $daysin;
                } else {
                    push @newopen, "$in\n";
                }
            } else {
                push @newopen, "$in\n";
            }
        } else {
            push @newopen, "$in\n";
        }
    }
    open OP, ">$opentick" or die "cannot open $opentick\n";
    print OP @newopen;
    close OP;
    close LOG;
}

sub updateDone {
    my ($logfile, $opentick) = @_;
    open LOG, "<$logfile" or die "cannot open log on $day\n";
    chomp(@in = <LOG>);
    close LOG;
    @newopen = ();
    open OP, "<$opentick" or die "cannot open $opentick\n";
    chomp( @open = <OP> );
    close OP;
    @done = ();
    foreach $in (@in) {
        next if ($in !~ /^i/ && $opt_i);
        if ($in =~ /(\w+.?\w*)\s+EXIT:(\w+)/) {
            $tick = $1;  $direction = $2;
            $found = "";
            foreach $entry (@open) {
                if ($entry =~ /^$tick/) {
                    last;
                    $found = $entry;
                }
            }
            if ($found) {
                print "Exit signal for $direction position in $tick. Has position been closed? [Y/n] "; $q = <STDIN>;
                # remove entry if we did exit the position
                if ($q =~ /[nN]/) {
                    push @newopen, $found;
                }
                push @done, $found;
            }
        } elsif ($in =~ /\d+\t(\w+.?\w*)\t([a-z]+)/) {
            $tick = $1;  $direction = $2;
            if ( ($opt_c && $tick eq $opt_c) || ! $opt_c) { 
                $in =~ /s=(.*)$/; $sysStop = $1;
                print "Entry signal for $direction position in $tick. Has position been opened? [Y/n] "; $q = <STDIN>;
                # entry details....
                unless ($q =~ /[nN]/) {
                    print "Entry price = "; chomp($inprice = <STDIN>);
                    print "istop = "; chomp($istop = <STDIN>);
                    push @newopen, sprintf "$tick\t$direction\t%.3f\t%.3f\t%.3f\t0\t$sysStop", $inprice, $istop, $istop;
                }
            }
        }
    }
    # what's left (i.e. not in @done) should still be open
    foreach $entry (@open) {
        $found = "";
        foreach $op (@done) {
            if ($op eq $entry) {
                $found = $op;
                last;
            }
        }
        unless ($found) {
#            if ( ($opt_c && $tick eq $opt_c) || ! $opt_c) {
                print "Is $entry still open? [Y/n] "; $q = <STDIN>;
                unless ($q =~ /[nN]/) {
                    push @newopen, $entry;
                }
#            }
        }
    }
    $n = @newopen;  print "there are $n entries\n";
    # now write to the open ticks file
    open OP, ">$opentick" or die "cannot open $opentick\n";
    print "tick\tdirec.\tinprice\tistop\tstop\tDaysInTrade\n";
    foreach $entry (@newopen) {
        print OP "$entry\n";
        print "$entry\n";
    }
    close OP;
}

sub readGlobalParams {
    unless ($day) {
        chomp( $day = `date "+%Y-%m-%d"` );
    }
    if ($opt_r) {
        $risk = $opt_r;
    } else {
        $risk = 150.00;
    }
    print "Running tradeManager on $day\n";
    chomp( $unique = `date "+%Y%m%dT%H%M%S"` );
    $path = "/Users/tdall/geniustrader/";
    $dbfile = "/Users/tdall/geniustrader/traderThomas";
    $btdir = "/Users/tdall/geniustrader/Backtests/";
    $dailydir = "${path}DailyScan/";
    $whichway = "";   # long or short
    $opentrade = "";  # long or short
    $tickWatch = "${path}watch.tick";
    $tickOpen = "${path}open.tick";
    $tickOpenI = "${path}openi.tick";
    $limf = 1.02;  # max difference from stop-buy order price, e.g. 1.03 -> max 3% difference to
}
#!/usr/bin/perl -I/Users/tdall/copyExecs
#
#   tradeManager.pl [yyyy-mm-dd]

use Carp;
use Getopt::Std;
#use PGPLOT;
#use DBD::SQLite;
use DBI;    # see http://search.cpan.org/perldoc?DBI for how-to
#use strict;

require "utils.pl";
#require "pg_utils.pl";
require "trader_utils.pl";
#my ($opt_l, $opt_a,$opt_D);  # comment out for running!!!
getopts('laD');
# [-l] list the strategies along with their ref number on the list, then exit.
# [-a] allow adding to existing positions
# [-D] don't update the delta value for certificates

# $action can be any of the following:
#   EOD         end-of-day; 
#   Stops       calculate stop adjustment to all 'current' portfolio positions
#   NewOrders   new stop-buy or eod market orders for the given strategies. Orders are initially at 'defined'
my $c = @ARGV;  die "tradeManager.pl YYYY-MM-DD Action strat_num\n" unless ($c == 3);
my $day = shift;  my $action = shift;  my $nact = shift;
my $limf = 1.05;  # factor; limit buy is this many times the spread away from the stop-buy
my ($risk, $i, $in, $ns, @in, @tick, @setup, @strategy, @istop, @stop, @target, @program, @riskp, @spread, @account, @sq, @cq, @notes, @b, $pr);
my ($dbh, $dbfile, $path, $tmfile, @data, @datein, $d, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $h_v, $s, @orderid, $nord, $ok, $account, $donotupdatedb);
my ($ns, $nn, $toter, $toteq, $eq, $dd, $nr, $yday, $pnow);
my ($setupOK, $hilo, $datehl, $ishigh, $th, $tl, $hiloper, %sma, @hilo, @datehl, @ishigh, %trendh, %trendl,$askDelta);
my %hday = (); my %dayindex = (); my %openp = (); my %closep = (); my %maxp = (); my %minp = (); my %volume = ();
my $skip = ""; my %inprice = ();
my $eqhigh = 23000.00;  # as of July2013.  ##60000.00; #39031.42;  #### initial eq-high; this corresponds to a fortune of 100,000 - so we 'play' drawdown until we reach that point!
                        #### when reached:  Implement saving and reading of this value fromm file or from portfolio-calc!!!!
my $expslip = 0.10; #### expected slippage in terms of R; to be subtracted from the closed equity of each position
my $maxRisklim = 9.0;   #### hard limit on max open risk
my $risklim = 6.0;  #### max open risk for the portfolio. Is also adjusted by the $riskFactor, but can be no more than the $maxRisklim
my $maxRisk = 2.0;  #### hard limit on max risk on an open trade
my $riskFactor = 1.0;   ##### this factor depends on losing/winning streak and result in max the largest allowed risk%. Default is 1; adjusted below
my $didsomething = 0;
$|=1;
# read the strategies of the portfolio:
#
&readGlobalParams();
if (-e $tmfile) {
    $dbh = DBI->connect("dbi:SQLite:$tmfile", undef, undef, {
        AutoCommit => 1,
        RaiseError => 1,
        sqlite_see_if_its_a_number => 1,
      });
} else {
    die "no such file: $tmfile\n";
}
$askDelta = 1;
if ($opt_D) {
    $askDelta = 0;
}
# calc the drawdown-adjusted risk
#
($toteq, $eq) = PortfolioSummary($dbh, 'all1', $day);
if (($eqhigh - $eq)/$eqhigh > 0.0) {
    $dd = ($eqhigh - $eq)/$eqhigh;
    $riskFactor = (1.0 - $dd);    printf "Current risk-%1.1s factor = %.3f\n", '%', $riskFactor;
    $nr = @riskp;
    for ($i = 0; $i<$nr; $i++) {
        $riskp[$i] *= $riskFactor;
        if ($riskp[$i] > $maxRisk) {
            $riskp[$i] = $maxRisk;
        }
    }
}
$risklim *= $riskFactor;
if ($risklim > $maxRisklim) {   # making sure hard limit is respected
    $risklim = $maxRisklim;
}

$action =~ /(\d{1})$/;
if ($1) {
    $donotupdatedb = 1;
} else {
    $donotupdatedb = 0;
}

####  tmp params...

if ($action eq "ShowOrders" && $nact =~ /^[adpec]/) {
    OrderSummary($dbh, $nact);
    &myexit();
}
if ($action eq "OrderDelete") {
    $ok = OrderDelete($dbh, $nact);
    if ($ok) {
        print "Order $nact deleted!\n";
    } else {
        warn "couild not delete $nact";
    }
    &myexit();
}
if ($action eq 'PlotPos') {
    PlotPos($dbh, $nact, $day);
    &myexit();
}
if ($action eq "PortfolioSummary") {
    PortfolioSummary($dbh, $nact, $day);
    printf "Max. allowed open risk on portfolio = %.2f %1.1s\n", $risklim, '%';
    $ns = 0;    $nn = @strategy; $toter = 0.0;
    for ($i = 0; $i < $nn; $i++) {
        $ns++ if $strategy[$i] =~ /Long/;
        @in = split '/', $sq[$i];
        $toter += $in[1];
    }
    printf "Portfolio: Long/Short = %d/%d, %.1f%1.1s/%.1f%1.1s, ER = %.2f R/mth\n", $ns, $nn-$ns, $ns*100/$nn, '%', ($nn-$ns)*100/$nn, '%', $toter;
    &myexit();
}
if ($action eq 'Report') {
    PortfolioSummary($dbh,$nact,$day);
    &myexit();
}
if ($action eq "OrderActivate") {
    # if 'all', then all the 'def' orders of that day and which are 'open' type will get activated
    $ok = OrderActivate($dbh, $nact);
    &myexit();
}
if ($action eq "OrderExec") {
    OrderExec($dbh, $nact, $day);
    &myexit();
}
if ($action =~ /DepositCash-(.*)/) {
    $account = $1;
    unless ($account =~ /cfd|cortal|flatex|peace/) {
        die "ERROR: no such account '$account'\n";
    }
    $nact = abs($nact);
    AccountModify($dbh, $account, $nact, 'deposit', '', '', '', $day);
    PortfolioSummary($dbh, 'all', $day);
    &myexit();
}
if ($action =~ /WithdrawCash-(.*)/) {
    $account = $1;
    unless ($account =~ /cfd|cortal|flatex|peace/) {
        die "ERROR: no such account '$account'\n";
    }
    $nact = -abs($nact);
    AccountModify($dbh, $account, $nact, 'withdrawal', '', '', '', $day);
    PortfolioSummary($dbh, 'all', $day);
    &myexit();
}
if ($action =~ /NewStop/) {
    @b = @{$dbh->selectcol_arrayref(qq{SELECT symbol FROM myportfolio WHERE stamp='$nact'})};
    ($d, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c) = readStockData($b[0], $dbfile, $day);
    CalcStop($dbh, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $day, $nact, $donotupdatedb,$askDelta);
    &myexit();
}

# main loop; go through each strategy and act according to given action
for ($s = 0; $s < $ns; $s++) {
    next unless ($nact == $s+1 || $nact eq "all");
    # if we already have an open position for this strategy, then look for exit signals
    @b = @{$dbh->selectcol_arrayref(qq{SELECT symbol FROM myportfolio WHERE pos_status='current' AND symbol='$tick[$s]' AND stgy_desc='$strategy[$s] $istop[$s]'})}; # AND stgy_stop='$stop[$s]'})};
    if ($b[0] && ! $opt_a) {    # set -a to add to positions
        # TODO.... check for exit signals and don't do the entry-sig checks
        next; # for now...
    }
    # get the price data for this strategy
    ($d, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $h_v) = readStockData($tick[$s], $dbfile, $day);
    @datein = @$d;  %hday = %$h_d;  %dayindex = %$h_i;  %openp = %$h_o; %maxp = %$h_h;  %minp = %$h_l; %closep = %$h_c; %volume = %$h_v;
    $yday = $hday{$dayindex{$day}-1};
    printf "$tick[$s]\t%.3f - ", $closep{$day};
    # special case of SMA highs and lows
    if ($setup[$s] =~ /HiLo(\d+)/) {
        $hiloper = $1;
        %sma = smaHash($tick[$s], \%hday, \%dayindex, \%closep, $hiloper, $datein[$hiloper], $day); 
        ($hilo, $datehl, $ishigh, $th, $tl) = getHiLo(\%sma);
        @hilo = @$hilo; @datehl = @$datehl; @ishigh = @$ishigh; %trendh = %$th; %trendl = %$tl;
        $setupOK = $trendh{$day} . ":" . $trendl{$day};
        $pnow = [$trendh{$day}-$trendh{$yday}, $trendl{$day}-$trendl{$yday}, 0]; # no reentry permitted here... beware hardcode!
    } else {
        $setupOK = "";
    }
    ###print "setup = $setup[$s] so setupOK = $setupOK... ";
    if ($action =~ /NewOrders/) {
        if ($inprice{$tick[$s]}) {
            $pr = $inprice{$tick[$s]};
        } else {
            $pr = 0;
        }
        ($pr, @orderid) = CalcNewTrade($tick[$s], $setupOK, $pnow, $pr, $day, $limf, $dbh, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $h_v, $setup[$s], $strategy[$s], $istop[$s], $stop[$s], $target[$s], $program[$s], $riskp[$s], $spread[$s], $account[$s], $donotupdatedb);
        # save the true price in a hash, eg. $inprice{$tick} = ...;
        if ($pr) {
            $inprice{$tick[$s]} = $pr;
        }
        $nord = @orderid;
        if ($orderid[0]) {
            print "\tcreated $nord new order(s) for $tick[$s]; $strategy[$s] ($setup[$s]) on $day, starting with $orderid[0].\n";
        } else {
            print "\tcreated NO new orders for $tick[$s]; $strategy[$s] ($setup[$s]) on $day.\n";
        }
    }
}
&getOpenRisk($dbh);
&myexit();
#### END of program

##  ----------------

####  subroutines

sub myexit {
    $dbh->disconnect;
    exit;
}

# @order_ids = CalcNewTrade($tick, $setupOK, $pr, $day, $limf, $dbh, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $setup, $system, $istop, $stop, $targ, $stype, $riskp, $spread, $account);
#
sub CalcNewTrade {
    use strict;
    my ($tick, $setupOK, $pnow, $pr, $day, $limf, $dbh, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $h_v, $setup, $system, $istop, $stop, $targ, $stype, $riskp, $spread, $account,  $donotupdatedb) = @_;
    # to be run eod; evaluate signals and prepare parameters for new trades/orders. Enters order with status 'def'.
    # returns array with the order id's for each order.
    #   works on db-tables:
    #   works on files: 
    my $c = @_; die "only $c elements to CalcNewTrade(), should be 24\n" unless ($c == 24);
    my %openp = %$h_o;  my %closep = %$h_c;  my %maxp = %$h_h;  my %minp = %$h_l;
    my %hday = %$h_d;  my %dayindex = %$h_i;    my %volume = %$h_v;
    my ($lentry, $lstop, $sentry, $sstop, $poszl, $poszs, $inprice, $dum, $close, $pricel, $stopl, $stamp2, %test, $ko_marg, $fee, $type, $lim);
    my ($donotenter, $dir, $d1, $d2, $tnum, $entrySig, $t1, $t2, $turb_theory, $turb_real, $spr_turbo, $bzv, $stopz, $delta, $wkn, $riskact);
    my ($stopBuyL, $stopBuyS, $do, @tmp);
    my @orders = ();
    my $stamp = getStamp();
    
    # account and other params 
    if ($account =~ /cfd/) {
        $ko_marg = 0.05;
        $type = "cfd";
        $fee = 6.50;  # dynamically calc.... TODO
    } elsif ($account =~ /cortal/) {
        $fee = 4.95;
        $type = "Turbo";
    } elsif ($account =~ /flatex/) {
        $fee = 5.90;
        $type = "Turbo";    
    }
    if ($system =~ /Long/) {
        $dir = "long";
    } elsif ($system =~ /Short/) {
        $dir = "short";
    } else {
        $dir = "longshort";
        die "Error; system must be for either Long or Short\n";
    }
    my ($total_eq, $equity) = PortfolioSummary($dbh, 'all1', $day);
    my $risk = $riskp*$equity/100.0;
    # check for modifications to the parameters depending on strategy
    # $pnow is as it should be if strategy is HiLo
    if ($system =~ /Swing/) {
        $pnow = [0,0,0];
    } elsif ($system !~ /HiLo/) {
        $pnow = $close;
#        @tmp = split /:/, $setupOK;
#         $pnow = [@tmp, 0]; 
#     } else {
    }
    # checks if the setup conditions are fulfilled
    if ($setup ne "n") { 
        ($setupOK, $donotenter, $stopBuyL, $stopBuyS) = getSetupCondition($tick, $system, $setup, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $h_v, $day, $setupOK);
    } else {
        $donotenter = "";   $setupOK = "longshort";
    }
    printf "%7.7s: dir = %5.5s, not = %5.5s, setupOK = %-9.9s.", $tick, $dir, $donotenter, $setupOK;
    return if ($dir eq $donotenter); 
    return unless ($dir eq $setupOK || $setupOK eq 'longshort' );
    $inprice = $closep{$day};
    if ($pr) {
        $close = $pr;
    } else {
        if ($stype =~ /eod/ && $account !~ /cfd/) {
            # eod-strategies are OK with the yahoo prices, unless they were already entered above
            $close = $inprice;
            print "$tick close price = $inprice\n";
        } else {
            print "($tick close price was $inprice) Real close/current price for $tick? [return if OK] "; chomp($dum = <STDIN>);
            if ($dum) {
                $close = $dum;
            } else {
                $close = $inprice;
            }
        }
    }
    $stamp2 = $stamp . "1";  # using same stamp for the Short and Long - I should never run a system without one of these additions.
    $stamp .= "0";
    if ($stype =~ /eod/) {  
        # Not pre-prepared orders, but EOD. Must be called individually, e.g. "tradeManager.pl 2012-09-15 NewOrders 4" or at EOD...
        ($entrySig, $d1, $t1, $t2, $d2) = getSignal($tick, $system, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $day, "", 0, $close, 0, $pnow, $setupOK);
        print "\teod-type $system on $tick - ";
        if ($dir !~ /$entrySig/ || $entrySig eq '' || $setupOK !~ /$entrySig/) {
            print "no signals!\n";
            return ($close, @orders);
        }
        # two main branches: either certificate/option or a cfd (only for short positions in liquid stocks)
        if ($type eq "Turbo") {
            # calc a preliminary stop to give us an idea of the proper knock-out...
            $stopl = getStop($istop, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $day, 0, 0, $tick, $dir, $close, $close, 0, 0, "n"); # istop for the stock
            printf "$entrySig entry signal! Entry @ %.3f, stop @ %.3f (stock pos.) Set another stop? [y/N] ", $close, $stopl; chomp($dum=<STDIN>);
            if ($dum =~ /[yY]/) {
                print "Please enter new stop: "; chomp($stopl=<STDIN>);
            }
            printf "Please enter the following:\n", $close, $stopl;
            print "\tKnock-out level: "; chomp($ko_marg = <STDIN>); 
            print "\tActual (Brief) price of certificate: "; chomp($turb_real = <STDIN>);
            print "\tSpread on certificate: "; chomp($spr_turbo = <STDIN>);
            print "\tBezugsverh. [default 0.10]: "; chomp($dum = <STDIN>);
            if ($dum) {
                $bzv = $dum;
            } else {
                $bzv = 0.1;
            }
            print "\tWKN [optional]: "; chomp($wkn = <STDIN>);
            # difference btw theoretical and actual price of certificate:
            # turb_real = turb_theory + delta  <=>  delta = turb_real - turb_theory
            $turb_theory = abs($close - $ko_marg) * $bzv;
            $delta = $turb_real - $turb_theory; print "delta = $delta\n";
    #        $stopl = getStop($istop, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $day, 0, 0, $tick, $dir, $close, $close, 0, 0, "n"); # istop for the stock
            $stopz = abs($stopl - $ko_marg) * $bzv + $delta;    # istop for the certificate
            $poszl = int(($risk)/(abs($turb_real-$stopz)+$spr_turbo));
            if ($poszl > 1000) {  # turn into round numbers
                $poszl = 100 * int($poszl/100.0);
            } elsif ($poszl > 100) {
                $poszl = 10 * int($poszl/10.0);
            } ### TODO; turn this into a tweak-option; print "Actual pos size: "; chomp($poszl=<STDIN>); 
            if ( ($ko_marg >= $stopl && $entrySig eq "long") || ($ko_marg <= $stopl && $entrySig eq "short") ) {  ### hm... makes no sense
                warn "Error in KO? - stop=$stopz, while KO=$ko_marg\n";
                return ($close, @orders);
            }
            $stopz -= $spr_turbo; ### TODO; turn this into a tweak-option; print "Actual stop: "; chomp($stopz=<STDIN>);
            $riskact = $poszl * abs($turb_real-$stopz) + 2*$fee;
            $do = 0;
            unless ($system =~ /Short/ || $entrySig eq "short") {
                # these are the LONG trades
                printf "\t$tick Turbo-BULL KO=${ko_marg}. Entry = %.3f, istop = %.3f, -- size = $poszl\n", $turb_real, $stopz;
                $do = 1;
            }
            unless ($system =~ /Long/ || $entrySig eq "long") {
                # these are the SHORT trades
                printf "\t$tick Turbo-BEAR KO=${ko_marg}. Entry = %.3f, istop = %.3f, -- size = $poszl\n", $turb_real, $stopz;
                $do = 1;
            }
        } elsif ($type eq "cfd") {  # this is still eod...
            $stopl = getStop($istop, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $day, 0, 0, $tick, $dir, $close, $close, 0, 0, "n"); # istop for the stock
            printf "$entrySig entry signal! Entry @ %.3f, stop @ %.3f (stock pos.) Set another stop? [y/N] ", $close, $stopl; chomp($dum=<STDIN>);
            if ($dum =~ /[yY]/) {
                print "Please enter new stop: "; chomp($stopl=<STDIN>);
            }
            $poszl = int(($risk)/(abs($close-$stopl)));
            if ($poszl > 1000) {  # turn into round numbers
                $poszl = 100 * int($poszl/100.0);
            } elsif ($poszl > 100) {
                $poszl = 10 * int($poszl/10.0);
            } ### TODO; turn this into a tweak-option; print "Actual pos size: "; chomp($poszl=<STDIN>); 
            $do = 0;
            unless ($system =~ /Short/ || $entrySig eq "short") {
                # these are the LONG trades
                printf "\t$tick LONG CFD. Entry = %.3f, istop = %.3f, -- size = $poszl\n", $close, $stopl;
                $do = 1;
            }
            unless ($system =~ /Long/ || $entrySig eq "long") {
                # these are the SHORT trades
                printf "\t$tick SHORT CFD. Entry = %.3f, istop = %.3f, -- size = $poszl\n", $close, $stopl;
                $do = 1;
            }
            $stopz = $stopl; $spr_turbo = 0.0; $turb_real = $close; $ko_marg = 0.0; $delta = 1.0; $bzv = 1.0;
            $riskact = $poszl * abs($turb_real-$stopz) + 2*$fee;
        }
        if ($do) {
            unless ($donotupdatedb) {
                # entering the stop-buy order, still just 'def'
                $tnum = int(($risk-2*$fee)/abs($close-$stopl));
                $dbh -> do(qq{INSERT into orders VALUES('$tick', '$wkn', 'def', $poszl, 'EUR', $fee, '$type', '', $ko_marg, '$entrySig', '$day', '$stamp', 'flatex', $riskp, $risk, $riskact, 'open', '$stamp', '0', 'auto-create', '$system $istop', '$stop', '$targ', 0.0, 0.0, $turb_real, 0.0, '$stamp2', $spr_turbo, $bzv, $delta, $tnum, $close, $stopl, $stopl, 0.0, 0.0)});
                push @orders, $stamp;
                # entering the linked stop-loss oder which is to become active if first one is exec'ed
                $dbh -> do(qq{INSERT into orders VALUES('$tick', '$wkn', 'def', $poszl, 'EUR', $fee, '$type', '', $ko_marg, '$entrySig', '$day', '$stamp', 'flatex', $riskp, $risk, $riskact, 'close', '$stamp2', '0', 'auto-create', '$system $istop', '$stop', '$targ', 0.0, $stopz, 0.0, 0.0, '$stamp', $spr_turbo, $bzv, $delta, $tnum, $close, $stopl, $stopl, 0.0, 0.0)});
                push @orders, $stamp2;
            }
        }
    } elsif ($stype =~ /int/) {
        # calculates the stop-buy etc to enter for next day
        ($lentry, $lstop, $sentry, $sstop) = getIntraDayEntry($tick, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $system, $istop, $day);
        unless ($system =~ /Short/ || $donotenter eq "long") {
            # these are the LONG trades
            $pricel = $close+$lentry-$inprice;
            $stopl = $close+$lstop-$inprice-$spread*$limf;  # take spread into account; original was $stopl = $close+$lstop-$inprice
            $lim = $pricel+$spread*$limf;  # was originally: $lim = $close+($lentry-$inprice)*$limf;
            $poszl = int($risk/abs($lim-$stopl));
            printf "\t$day: $system on $tick says: stop-buy LONG = %.3f (limit = %.3f), istop = %.3f, -- size = $poszl\n", $pricel, $lim, $stopl;
            unless ($donotupdatedb) {
                # entering the stop-buy order, still just 'def'
                $tnum = int(($risk-2*$fee)/abs($lentry-$lstop));
                $dbh -> do(qq{INSERT into orders VALUES('$tick', '', 'def', $poszl, 'EUR', $fee, '$type', '', $ko_marg, 'long', '$day', '$stamp', 'cfd', $riskp, $riskp, 0, 'open', '$stamp', '0', 'auto-create', '$system $istop', '$stop', '$targ', $lim, $pricel, 0, 0.0, '$stamp2', $spread, 0, 0, $tnum, $lentry, $lstop, $lstop, 0.0, 0.0)});
                push @orders, $stamp;
                # entering the linked stop-loss oder which is to become active if first one is exec'ed
                $dbh -> do(qq{INSERT into orders VALUES('$tick', '', 'def', $poszl, 'EUR', $fee, '$type', '', $ko_marg, 'long', '$day', '$stamp', 'cfd', $riskp, $riskp, 0, 'close', '$stamp2', '0', 'auto-create', '$system $istop', '$stop', '$targ', 0.0, $stopl, 0, 0.0, '$stamp', $spread, 0, 0, $tnum, $lentry, $lstop, $lstop, 0.0, 0.0)});
                push @orders, $stamp2;
            }
        }
        unless ($system =~ /Long/ || $donotenter eq "short") {
            $pricel = $close-$inprice+$sentry;
            $stopl = $close+$sstop-$inprice+$spread*$limf;  # take spread into account
            $lim = $pricel-$spread*$limf;       # was originally: $lim = $close-($inprice-$sentry)*$limf;
            $poszs = int($risk/abs($lim-$stopl));
            printf "\t$day: $system on $tick says: stop-buy SHRT = %.3f (limit = %.3f), istop = %.3f -- size = $poszs\n", $pricel, $lim, $stopl;
            unless ($donotupdatedb) {
                # entering the stop-buy order, still just 'def'
                $tnum = int(($risk-2*$fee)/abs($sentry-$sstop));
                $dbh -> do(qq{INSERT into orders VALUES('$tick', '', 'def', $poszs, 'EUR', $fee, '$type', '', $ko_marg, 'short', '$day', '$stamp', 'cfd', $riskp, $riskp, 0, 'open', '$stamp', '0', 'auto-create', '$system $istop', '$stop', '$targ', $lim, $pricel, 0, 0.0, '$stamp2', $spread, 0, 0, $tnum, $sentry, $sstop, $sstop, 0.0, 0.0)});
                push @orders, $stamp;
                # entering the linked stop-loss oder which is to become active if first one is exec'ed
                $dbh -> do(qq{INSERT into orders VALUES('$tick', '', 'def', $poszs, 'EUR', $fee, '$type', '', $ko_marg, 'short', '$day', '$stamp', 'cfd', $riskp, $riskp, 0, 'close', '$stamp2', '0', 'auto-create', '$system $istop', '$stop', '$targ', 0.0, $stopl, 0, 0.0, '$stamp', $spread, 0, 0, $tnum, $sentry, $sstop, $sstop, 0.0, 0.0)});
                push @orders, $stamp2;
            }
        }
    } else {
        die "Error in strategy type: $stype not understood.\n";
    }
    return ($close, @orders);
}

# CalcStop($dbh, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $day, $pfid, $donotupdatedb);
#
sub CalcStop  {
    # can be called any time; use the latest db price for the given date and the strategy description to calc a new stop. 
    # Only gives output for 'current' portfolio positions. Will list active orders for the strategy.
    use strict;
    my ($dbh, $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $day, $pfid, $donotupdatedb,$askDelta) = @_;
    my $c = @_; die "only $c elements to CalcStop(), should be 11\n" unless ($c == 11);
    my (@b, $stop, $targ, $daysInTrade, $marg, $price, $dayidx, $delta, $turb_theory, $turb_real, $dum);
    my ($oo, $oistop, $ostop, $exitSig, $d1, $t1, $t2, $d2, $th_stop);
    my %closep = %$h_c;
    my %hday = %$h_d;  my %dayindex = %$h_i;

    @b = $dbh->selectrow_array(qq{SELECT * FROM myportfolio WHERE stamp='$pfid'});
    return unless ($b[0]);  # don't treat faulty id's
    if ($b[25] eq 'n') {
        $targ = 0;
    } else {
        # TODO ... target calc
        print "WARN: no target yet...\n";
    }
    # if price db has not yet been updated, then we need to tweak it in order to count correctly the number of days in trade
    if ($closep{$day}) {
        $dayidx = $dayindex{$day};
    } else {
        my @hday = sort values %hday;
        $dayidx = $dayindex{$hday[-1]}+1; #print "I found $hday[-1]\n"; exit;
    }
    print "$b[0] close price on $day is $closep{$day} - [RET] if ok, else enter correct price: "; chomp($price = <STDIN>);
    unless ($price > 0) {
        $price = $closep{$day};
    }
    # check if an EXIT signal came today
    $daysInTrade = $dayidx - $dayindex{$b[26]}; # print "using price = $price \n";
    unless ($b[23] =~ /HiLo/) { # ugly hack: $price should be composed of trend-tops/bottoms, but need to get iti into subroutine
    ($d1, $exitSig, $t1, $t2, $d2) = getSignal($b[0], $b[23], $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $day, $b[9], $daysInTrade, $price, $b[16], $price, $b[9]);
                    ### note: $price, $b[16] to be replaced by original entry price of underlying
                    ### otherwise it cannot be used.  Need to extend database.
    }
    if ($b[6] =~ /Turbo/) {
        $oistop = ($b[16]-$b[32])/$b[31] + $b[8];   # stock_price = (turb_real - delta)/bzv + KO
        $ostop = ($b[17]-$b[32])/$b[31] + $b[8];
        $oo = ($b[11]-$b[32])/$b[31] + $b[8];
        $stop = getStop($b[24], $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $day, $ostop, $oistop, $b[0], $b[9], $oo, $price, $targ, $daysInTrade, 'n');
        $turb_theory = abs($price - $b[8]) * $b[31];
        if ($askDelta) {
            print "\tActual (Brief) price of certificate: "; chomp($turb_real = <STDIN>);
            $delta = $turb_real - $turb_theory;
            if (abs($delta-$b[32])/$b[32] > 0.1) { # too big change maybe...
                print "New delta = $delta (in db: $b[32]). Hit return to continue or ^C to abort...\n"; $dum = <STDIN>;
            }
        } else {
            $delta = $b[32];
        }
        $th_stop = $stop;   # stop for the stock position
        $stop = abs($stop - $b[8]) * $b[31] + $delta;   # stop for the certificate 
        PositionModify($dbh, $pfid, 'delta', $delta);
    } else {
        $stop = getStop($b[24], $h_d, $h_i, $h_o, $h_h, $h_l, $h_c, $day, $b[17], $b[16], $b[0], $b[9], $b[11], $price, $targ, $daysInTrade, 'n');
        $th_stop = $stop;   # save the stop for the stock pos.
    }
    # do not lower the stop!
    if (  ($stop < $b[17] && ($b[9] eq 'long' || $b[6] =~ /Turbo/)) || ($stop > $b[17] && ($b[9] eq 'short' && $b[6] !~ /Turbo/)) ) {
        $stop = $b[17];
        $th_stop = $b[37];
    }
    print "$b[0], sgy = $b[24], istop = $b[16]. stop before = $b[17], after = $stop";
    if ($b[6] =~ /Turbo/) {
        print ", stop($b[0]) = $th_stop\n";
    } else {
        print "\n";
    }
    # update close-order ($b[19]) and the pf position with new stop ($b[17]), plus pf with cl-eq gains ($b[13-14])
    unless ($donotupdatedb) {
        OrderModify($dbh, $b[19], 'price_stop', $stop);
        if ($b[6] eq "cfd") {
            $marg = $b[8];
        } else {
            $marg = 1.0;
        }
        my ($cl_eq, $g) = getPosValue($b[2], $b[11], $stop, $b[4], $marg, $b[9], $b[6]);
        my $r = $g/$b[22];
        PositionModify($dbh, $pfid, 'tstop', $stop);
        PositionModify($dbh, $pfid, 'gain', $g);
        PositionModify($dbh, $pfid, 'r_gain', $r);
        PositionModify($dbh, $pfid, 'th_tstop', $th_stop);
    }
}

# $success = OrderActivate($dbh, $id)
#
sub OrderActivate {
    # changes an order from 'def' to 'pend', meaning that it's lined up for execution
    use strict;
    my ($dbh, $id) = @_;
    my $ok = 1;
    my ($sth, $ary, @arr, $narr);
     # if 'all', then all the 'def' orders of that day and which are 'open' type will get activated
    if ($id eq "all") {
        $sth = $dbh->prepare(qq{UPDATE orders SET status='pend' WHERE order_typ='open' AND status='def'});
        $sth -> execute();
    } else {
        $sth = $dbh->prepare(qq{UPDATE orders SET status='pend' WHERE order_id='$id' AND status='def'});
        $sth -> execute();
        @arr = $dbh->selectrow_array("SELECT order_id FROM orders WHERE order_id='$id' AND status='pend'");
        $narr = @arr;
        if ($narr == 0) {
            warn "Somthing wrong; order_id = $id has wrong status\n";
            $ok = 0;
        }
    }
    # TODO:  enter journal entry...
    return $ok;
}

# OrderModify($dbh, $id, $field, $newval);
#
sub OrderModify {
    # changes the parameters of an open order without changing its status
    use strict;
    my ($dbh, $id, $field, $newval) = @_;
    my ($val);
    if ($newval =~ /\D/) {
        # text fields need the single quotes
        $val = qq{'$newval'};
    } else {
        $val = $newval;
    }
    my $sth = $dbh->prepare(qq{UPDATE orders SET $field=$val WHERE order_id='$id'});
    $sth -> execute();
}

# OrderExec($dbh, $id, $day);
#
sub OrderExec {
    # closes a 'pend' order, setting status to 'exec' and updating portfolio
    use strict;
    my ($dbh, $id, $day) = @_;
    my $c = @_; die "only $c elements to OrderExec(), should be 3 - $!\n" unless ($c == 3);
    my $ok = 1;
    my $off = 0.0;  my $stamp = getStamp();
    my ($sth, @b, $realrisk, $fill, @p, $gain, $rmult, $narr, $ary, $cost, $factor, $val, $r);
    # if order is to open a position, then enter in portfolio, otherwise, modify the existing position
    my @a = $dbh->selectrow_array("SELECT * FROM orders WHERE order_id='$id'");
    if ($a[8] > 0 && $a[6] =~ /cfd/) {
        $factor = $a[8];  # the margin
    } else {
        $factor = 1.0;
    }
    if ($a[16] eq "open") {
        print "Actual fill price: "; chomp($fill = <STDIN>);
        $sth = $dbh->prepare(qq{INSERT into myportfolio values('$a[0]', '$a[1]', $a[3], '$a[4]', $a[5], 0.0, '$a[6]', '$a[7]', $a[8], '$a[9]', 'current', $fill, 0.0, 0.0, 0.0, $off, 0.0, 0.0, '$id', '', '$a[12]', $a[13], $a[15], '$a[20]', '$a[21]', '$a[22]', '$day', '', '$stamp', $a[14], $a[28], $a[29], $a[30], $a[31], $a[32], $a[33], $a[34], $a[35], $a[36])});
        $sth -> execute();
        # if linked to another order by if-done, then update stop level in pf and activate the order
        if ($a[27] =~ /T/) {
            @b = $dbh->selectrow_array("SELECT price_stop FROM orders WHERE order_id='$a[27]'");
            $realrisk = $a[3] * abs($b[0] - $fill) + 2*$a[5];
            ($val, $gain) = getPosValue($a[3], $fill, $b[0], $a[5], $factor, $a[9], $a[6]);
            $r = $gain/$realrisk;
            $sth = $dbh->prepare(qq{UPDATE myportfolio SET gain=$gain, r_gain=$r, istop=$b[0], tstop=$b[0], risk_size_act=$realrisk, order_close='$a[27]' WHERE order_open='$id'});
            $sth -> execute();
            $sth = $dbh->prepare(qq{UPDATE orders SET status='pend', linked_to='$stamp' WHERE order_id='$a[27]'});
            $sth -> execute();
        }
        $cost = $a[3]*$fill*$factor + $a[5];
        AccountModify($dbh, $a[12], -$cost, 'open', "open pos", $stamp, $id, $day);
    } elsif ($a[16] eq "close") {
        print "Actual exit price: "; chomp($fill = <STDIN>);
        @b = $dbh->selectrow_array("SELECT linked_to, fees FROM orders WHERE order_id='$id'");
        @p = $dbh->selectrow_array("SELECT number, direction, fees_open, price_open, risk_size_act, type FROM myportfolio WHERE stamp='$a[27]'");
        # calculate gain
        if ($p[1] eq "long" || $p[5] =~ /Turbo/) {
            $gain = ($fill - $p[3]) * $p[0] - $b[1] - $p[2];
            $cost = $p[0]*$fill*$factor - $b[1];
        } elsif ($p[1] eq "short") {
            $gain = ($p[3] - $fill) * $p[0] - $b[1] - $p[2];
#            $cost = $p[0]*(2*$p[3]-$fill)*$factor - $b[1];
            $cost = ($p[0]*$p[3]*$factor + $p[2]) + $gain;
        }
        $rmult = $gain/$p[4];
        printf "Exiting trade. gain = %.2f EUR, R = %.2f, portfolio ID = $a[27]\n", $gain, $rmult;
        $sth = $dbh->prepare(qq{UPDATE myportfolio SET pos_status='closed', date_close='$day', fees_close=$b[1], price_close=$fill, gain=$gain, r_gain=$rmult WHERE order_close='$id'});
        $sth -> execute();
        AccountModify($dbh, $a[12], $cost, 'close', "pos $a[27]", $stamp, $id, $day);
    } else {
        die "ERROR: no order or wrong order type!\n";
    }
    # update the order status
    $sth = $dbh->prepare(qq{UPDATE orders SET status='exec', price_fill=$fill WHERE order_id='$id' AND status='pend'});
    $sth -> execute();
}

# $success = OrderDelete($dbh, $id);
#
sub OrderDelete {
    # deletes an order from the db regardless of its status, assuming it was entered by error.
    # also able to take 'def' as argument - as when cleaning up after the day   TODO... not sure it's a good idea...
    my ($dbh, $id) = @_;
    my $ok = 1;
    my $sth = $dbh->prepare(qq{DELETE FROM orders WHERE order_id='$id'});
    $sth -> execute();
    my $ary = $dbh->selectcol_arrayref("SELECT order_id FROM orders WHERE order_id='$id'");
    my @arr = @$ary; my $narr = @arr;
    if ($narr > 0) {
        warn "Somthing wrong; still $narr entries with order_id = $id\n";
        $ok = 0;
    }
    return $ok;
}

# OrderSummary($dbh, $status);
#
sub OrderSummary {
    # prints status of orders (all, a subset: today, all def/pend/canc/exec, etc.)
    # if 'all', then 'canc' orders will not show.
    use strict;
    my ($dbh, $status) = @_;
    my $add = "";
    my ($i, $j, $narr, $id, @b);
    if ($status ne 'all') {
        $add = "WHERE status='$status'";
    } else {
        $add = "WHERE status<>'canc'";
    }
    print "tick\tstatus\tpsize\tstop-p\tlimit-p\tactual\tdir\tdate\t\taccount\top/cl\torder_id\t\tstrategy\n";
    my @arr = @{$dbh->selectcol_arrayref("SELECT order_id FROM orders $add")};
    foreach $id (@arr) {
        @b = $dbh->selectrow_array("SELECT * FROM orders WHERE order_id='$id'");
        printf "$b[0]\t$b[2]\t%d\t%.3f\t%.3f\t%.3f\t$b[9]\t$b[10]\t$b[12]\t$b[16]\t$b[17]\t$b[20]\t$b[21]\t$b[22]\n", $b[3],$b[24],$b[23],$b[25];
    }
}

# PlotPos($dbh, $nact, $day);
#
sub PlotPos {

}

# PositionModify($dbh, $id, $field, $newval);
#
sub PositionModify {
    # updates notes, strategy, parameters, etc.  To close a position, use OrderExec.
    use strict;
    my ($dbh, $id, $field, $newval) = @_;
    my ($val);
    if ($newval =~ /\D/) {
        # text fields need the single quotes
        $val = qq{'$newval'};
    } else {
        $val = $newval;
    }
    my $sth = $dbh->prepare(qq{UPDATE myportfolio SET $field=$val WHERE stamp='$id'});
    $sth -> execute();
}

# ($total_eq, $closed_eq) = PortfolioSummary($dbh, $whichacc, $day);
#
sub PortfolioSummary {
    # status: open equity total risk, individual positions and open risk, secured profits, etc.... TBE
    # returns total liquid equity (accounts sum), and closed equity.
    # second argument is either an account (or 'all' accounts), or refers to pf positions ('current', 'closed', or 'full' for all past and present)
    use strict;
    my ($dbh, $whichacc, $day) = @_;
    my (@acc, $sth, $acc, $cl_eq, $g, $marg, @b, $id, $noprint, @pfid, $endday, $closep);
    my $bigsum = 0.0;   my $report = 0;
    my @sumlines = ();
    
    # if day is just a number, it's the month number and we generate the monthly report
    unless ($day =~ /-/) {
        $report = 1;
    }
    # first decide which cash accounts to include - default is all of them
    if ($whichacc =~ /all(1*)/ || $whichacc =~ /current|closed|full/) {
        @acc = ('cfd', 'flatex', 'cortal');  # not including the 'peace' account, only the trading accounts.
        if ($1) {
            $noprint = 1;
        }
    } elsif ($whichacc =~ /tot/) {  # counting total Formue
        @acc = ('cfd', 'flatex', 'cortal', 'peace', 'hvb', 'fond', 'bond');
    } else {
        @acc = ($whichacc);
    }
    # go through the accounts
    foreach $acc (@acc) {
        next unless $acc =~ /flatex/;   # July2013; run the account independently from the rest of the portfolio
        @b = $dbh->selectrow_array(qq{SELECT * FROM mycash WHERE acc_name='$acc' AND type='balance'});
        $bigsum += $b[1];
        #push @sumlines, s
        printf("$acc:\t%11.2f\n",$b[1]) unless $noprint;
    }
    #push @sumlines, s
    printf("total:\t%11.2f\n",$bigsum) unless $noprint;
    my $acc_sum = $bigsum;
    
    # go through portfolio of current positions
    # determine if a specific part of the pf is to be shown/considered - default is 'current' positions only
    if ($whichacc =~ /closed/) {
        @pfid = @{$dbh->selectcol_arrayref(qq{SELECT stamp FROM myportfolio WHERE pos_status='closed' AND date_open>='$day'})};    
    } elsif ($whichacc =~ /full/) {
        @pfid = @{$dbh->selectcol_arrayref(qq{SELECT stamp FROM myportfolio WHERE date_open>='$day'})};
    } elsif ($whichacc =~ /current|all|cfd|flat|cort/) {
        @pfid = @{$dbh->selectcol_arrayref(qq{SELECT stamp FROM myportfolio WHERE pos_status='current'})};
    } else {
        print "No such '$whichacc'\n";
        &myexit();
    }
    foreach $id (@pfid) {
        @b = $dbh->selectrow_array(qq{SELECT * FROM myportfolio WHERE stamp='$id'});
        if ($b[6] eq "cfd") {
            $marg = $b[8];
        } else {
            $marg = 1.0;
        }
        if ($b[27]) {
            $endday = "$b[27]\t";
        } else {
            $endday = "present\t";
        }
        if ($b[12]) {
            $closep = sprintf "%.3f", $b[12];
        } else {
            $closep = "------";
        }
        ($cl_eq, $g) = getPosValue($b[2], $b[11], $b[17], $b[4], $marg, $b[9], $b[6]);
        printf("id=$id: $b[9] %d x $b[0] (typ=$b[6]):\t$b[26]--$endday acc=$b[20].  IN=%.3f, OUT=$closep, istop=%.3f, stop=%.3f. Eq = %.2f sec.gain = %.2f.\tSec.R = %.2f [$b[23], $b[24]]\n", $b[2], $b[11], $b[16], $b[17], $cl_eq, $g, $b[13]/$b[22]) unless $noprint;
        if ($endday =~ /present/) {
            $bigsum += $cl_eq;
            $bigsum -= $expslip*$b[22];    # lower by the expected slippage in terms of R, times the R-size in EUR for this trade
        }
    }
    
    printf("TOTAL (closed equity): %.2f\n", $bigsum) unless $noprint;
    &getOpenRisk($dbh) unless $noprint;
    return ($acc_sum, $bigsum);
}

# AccountModify($dbh, $account, $amount, $type, $text, $stamp, $ordid, $day);
#
sub AccountModify {
    # works on the cash accounts only; deposit, withdrawal.
    use strict;
    my ($dbh, $account, $amount, $type, $text, $stamp, $ordid, $day) = @_;
    #my $ok = 1;
    unless ($stamp) {
        $stamp = getStamp();
    }
    # get current balance on the account and calculate the new balance
    my $ary = $dbh->selectcol_arrayref("SELECT value FROM mycash WHERE acc_name='$account' AND type='balance'");
    my @arr = @$ary;
    my $sum = $arr[0] + $amount;
    # enter the new transaction and update the balance
    my $sth = $dbh->prepare(qq{INSERT into mycash values('$account', $amount, 'EUR', '$type', '$text', '$stamp', '$ordid', '$day')});
    $sth -> execute();
    $sth = $dbh->prepare(qq{UPDATE mycash SET value='$sum' WHERE acc_name='$account' AND type='balance'});
    $sth -> execute();
    $ary = $dbh->selectcol_arrayref("SELECT value FROM mycash WHERE acc_name='$account' AND type='balance'");
    @arr = @$ary;
    print "New balance of $account = $arr[0]\n";
    #return $ok;    
}

sub getOpenRisk {
    use strict;
    my ($dbh) = @_;
    my $orisk = 0.0;
    my ($id, $openrisk, $text);
    my @pfid = @{$dbh->selectcol_arrayref(qq{SELECT stamp FROM myportfolio WHERE pos_status='current'})};
    foreach $id (@pfid) {
        @b = $dbh->selectrow_array(qq{SELECT * FROM myportfolio WHERE stamp='$id'});
        $openrisk = $b[14]*$b[21];  # open risk % = R(at stop) * risk%
        $openrisk -= $expslip*$b[14]*$b[21];    # assume there will be some slippage and take it into the open equity calc.
        if ($openrisk > 0.0) { # for the display; no risk if this gives > 0
            $text = "secured gain =";
        } else {
            $text = "open risk =";
            $orisk += $openrisk;
        }
        printf "Found pos in $b[0]: R(stop) = %.2f, risk-%1.1s = %.2f => $text %.2f %1.1s\n", $b[14], '%', $b[21], $openrisk, '%';
    }
    if ($orisk > 0.0) {
        $orisk = 0.0;
    } else {
        $orisk = abs($orisk);
    }
    printf "Total open risk = %.2f %1.1s\n", $orisk, '%'; 
}

# ($val, $gain) = getPosValue($number, $pin, $pout, $fee, $marg, $dir, $type);
#
sub getPosValue {
    use strict;
    my ($number, $pin, $pout, $fee, $marg, $dir, $type) = @_;
    my ($gain, $val);
    if ($dir eq "long" || $type =~ /Turbo/) {
        $gain = ($pout - $pin) * $number;
    } elsif ($dir eq "short") {
        $gain = ($pin - $pout) * $number;
    } else {
        die "no such direction: $dir\n";
    }
    $val = $number * $pin * $marg + $gain - $fee;
    return ($val, $gain);
}

sub readGlobalParams {
    unless ($day) {
        chomp( $day = `date "+%Y-%m-%d"` );
    }
    unless ($action) {
        die "missing or unknown action: $action\n";
    }
    $path = "/Users/tdall/geniustrader/";
    $dbfile = "/Users/tdall/geniustrader/traderThomas";
    $tmfile = "/Users/tdall/Dropbox/Vigtige_dokumenter/trademanager.db";
#    $tmfile = "trademanager.db";
    my $gtfile = "${path}sysportf.gtsys";
    # reading the system-portfolio file
    open PF, "<$gtfile" || die "cannot open $gtfile\n";
    $i = -1;
    while ($in = <PF>) {
        next if ($in =~ /^#/ || $in =~ /^\s/);
        $i++;
        chomp $in;
        @in = split /\s+/, $in;
 #       $i = shift @in;
        $tick[$i] = $in[0];
        $setup[$i] = $in[1];
        $strategy[$i] = $in[2];  #print "strategy $i: $strategy[$i]\n";
        $istop[$i] = $in[3];
        $istop[$i] =~ s/_/ /g;
        $stop[$i] = $in[4];
        $stop[$i] =~ s/_/ /g;
        $target[$i] = $in[5];
        $program[$i] = $in[6];
        $riskp[$i] = $in[7]; #*$riskFactor;
#         if ($riskp[$i] > $maxRisk) {
#             $riskp[$i] = $maxRisk;
#         }
        $spread[$i] = $in[8];
        $account[$i] = $in[9];
        $sq[$i] = $in[10];
        $cq[$i] = $in[11];
        $notes[$i] = $in[12];
##  tick	setup		    strategy		istop			stop			target	program	risk%	spread	account	SQ_bt/E		CQ/ntrades      notes
#1  MEO.DE  n               VolBC95A5Short  Vola_5_0.8x     Percent_0.1     n       int     1.0     0...    cfd     0.08/0.38   0.38/43/1.2     ok
#2  LHA.DE  n               VolBC100T5Short Vola_5_0.8x     Percent_0.05    n       int     1.0     0...    cfd     0.10/0.23   0.46/31/1.7     ok
    }
    $ns = @tick;
    close PF;
    if ($nact =~ /^\d+$/ && $action !~ /Cash/) {
        die "no such strategy # $nact\n" unless $nact <= $ns;
    } elsif ($nact =~ /\dT\d/ || $nact =~ /^[dpecft]/ || $nact =~ /\d+.*\d+/) {
        1;
    } else {
        $nact = "all";
    }
    if ($opt_l) {
        for ($i = 0; $i < $ns; $i++) {
            $s = $i+1;
            print "$s: $tick[$i]\t$strategy[$i]\t$riskp[$i]\n" if ( $nact eq "all" || $nact == $s );
        }
        exit;
    }
    print "Running tradeManager on $day\n";
}

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

#  $mystamp = getStamp();
#

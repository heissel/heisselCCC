#!/usr/bin/perl -I/Users/tdall/copyExecs
# 
# 

#$g = shift;
#@g = <${g}>;
@g = <Backtests/summary_*>;
print "#SY\tISTOP\tSTOP\tR\tSQ\tOPP\tEXTU\n";
foreach $sfile (@g) {
    open IN, "<$sfile" or die "zz846dhhns on $sfile\n";
    while ($in = <IN>) {
        if ($in =~ /System = /) { #VolBC(\d+)A5.*Vola 5 (.*)x, .*TrueRange (\d+)/) {
            $sy = $1; $is = $2; $st = $3;
        } elsif ($in =~ /Portfolio value.* = (\d+.\d+) from/) {
            $st = $1;
        } elsif ($in =~ /Expectancy = (0.\d+).*System Quality = (.*),/) {
            $r = $1; $sq = $2;
        } elsif ($in =~ /Opportunity = (.*) trades.*profit per day = (.*)R/) {
            $op = $1; $ex = $2;
        }
    }
    close IN;
    print "$sy\t$is\t$st\t$r\t$sq\t$op\t$ex\n";# if $st > 10000.0; 
}
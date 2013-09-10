#!/usr/bin/perl

@files = <Gain*>;
foreach $old (@files) {
    $old =~ /_(\d{8}).csv/;
    $dum = $1;
    $d = substr $dum,0,2;
    $m = substr $dum,2,2;
    $y = substr $dum,4,4;
    #print "$dum -> $y-$m-$d\n"; exit();
    unless (rename $old, "GaC_EURUSD_$y-$m-$d.csv") {
        die "Error! $!\n";
    }
    
}
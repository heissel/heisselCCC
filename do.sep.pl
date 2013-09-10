#!/usr/bin/perl

open IN, "<../germany.tick";
@ticks = <IN>;
close IN;
chomp @ticks;

%ticks = ();
foreach $tick (@ticks) {
    #next unless $tick =~ /DE/;
    $ticks{$tick} = 1;
}

open RM, "<../dax30.tick";
@rm = <RM>;
close RM;
chomp @rm;
foreach $rm (@rm) {
    delete $ticks{$rm};
}

foreach $tick (sort keys %ticks) {
    print "$tick\n";
}
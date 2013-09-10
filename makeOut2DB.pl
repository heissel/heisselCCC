#!/usr/bin/perl -I/Users/tdall/copyExecs
# give name of file with data on the command line
# e.g.:  makeOut2DB.pl ../Backtests/out_VolBC_Vola.txt
# takes a out_*.txt file and creates a unique database file or adds to it if it exists

require "utils.pl";
require "pg_utils.pl";
require "trader_utils.pl";
$ARGV[0] =~ /ou([tb])_(.*).txt/;
if ($1 eq "t") {
    $type = "R";  # reliability
} elsif ($1 eq "b") {
    $type = "B";  # backtest
}
print "type = $type\n";
$infile = $type . $2;
$dbfile = "/Users/tdall/geniustrader/Backtests/dataDB_${infile}.db";

unless (-e $dbfile) {
    if ($type eq "R") {
        `sqlite3 $dbfile "create table backtest ( \\
            symbol  varchar(12) not null default '', \\
            range   numeric default null, \\
            atr     numeric default null, \\
            istop   float4 default null, \\
            sum_mpe float4 default null, \\
            n_pos   int4 default null, \\
            sum_l   float4 default null, \\
            n_neg   int4 default null, \\
            r_diff  float4 default null, \\
            n_trades    int4 default null, \\
            n_days  int4 default null, \\
            r_p_trade   float4 default null, \\
            r_p_day float4 default null)"`;
        @fields = qw(symbol range atr istop sum_mpe n_pos sum_l n_neg r_diff n_trades n_days r_p_trade r_p_day);
    } elsif ($type eq "B") {
        `sqlite3 $dbfile "create table backtest ( \\
            symbol  varchar(12) not null default '', \\
            range   numeric default null, \\
            atr     numeric default null, \\
            istop   float4 default null, \\
            tstop   float4 default null, \\
            pval    float4 default null, \\
            meanr   float4 default null, \\
            sq      float4 default null, \\
            n_win   int4 default null, \\
            n_loss  int4 default null, \\
            n_trades    int4 default null, \\
            n_days  int4 default null, \\
            r_pos   float4 default null, \\
            r_neg   float4 default null, \\
            opp     float4 default null, \\
            r_p_day   float4 default null)"`;
        @fields = qw(symbol range atr istop tstop pval meanr sq n_win n_loss n_trades n_days r_pos r_neg opp r_p_day);
    }
}
$nf = @fields;

@data = <>;

foreach $in (@data) {    
    next if $in =~ /#/;
    chomp $in;
    $in =~ s/^(\w+?.*?\w*?)\t/'$1'\t/g;
    $in =~ s/\t/,/g;
#    print "$in\n";
    `sqlite3 $dbfile "insert into backtest values($in)"`;
}        

# using the database (example):
#
# sqlite3 -separator ' ' dataDB.db "select istop,r_p_trade,r_p_day from backtest where range = 120 and atr = 5" > data_120_5.txt
# sqlite3 -separator ' ' dataDB.db "select istop,tstop,meanr,sq,r_p_day from backtest where range = 120 and atr = 5" > da_120.txt
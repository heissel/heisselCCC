#!/usr/bin/perl -I/Users/tdall/copyExecs

$file = shift;

@x = (11..21);
 
if ($file =~ /MT4/) {  # comes from metatrader4
    if ($file =~ /AllTime/) {
        @txt = qw(spread hour-of-day MAE MPE KSO KSO-slope delta/p_max SMA-slope ATR-slope A/A10 vol/<vol> RSI);
    } elsif ($file =~ /CrossSMA/ || $file =~/Black-n-White/ || $file =~ /KAMA/) {
        @txt = qw(spread hour-of-day MAE MIAE AE_1bar MPE MPE-R Nbars N_breakeven N(R=0.5) N(R=1.0) N(R=1.5) N(R=2.0) N(R=3.0) N(R=5.0) KAMAsc(exit) KAMAsc(MPE) Mom dMom dKAMA KAMAsc MACD dMACD MACDhist dMACDhist KSO dKSO TR1/ATR dSMA dATR A/A10 vol/<vol> dRSI);
    } elsif ($file =~ /TSI/) {
        @txt = qw(spread hour-of-day MAE MIAE AE_1bar MPE MPE-R Nbars N_breakeven N(R=0.5) N(R=1.0) N(R=1.5) N(R=2.0) N(R=3.0) N(R=5.0) Mom dMom TSI TSI-signal dTSI dTSI(smooth) TSI(M15) dTSI(M15) TSI(M30) dTSI(M30) TSI(H1) dTSI(H1) KSO dKSO TR1/ATR dSMA price-SMA20 price-SMA50 price-SMA200 dATR A/A10 vol/<vol> RSI dRSI);
    } else {
        @txt = @x;
    }
} elsif ($file =~ /AllTime/) {
    @txt = qw(KSO-slope delta/p_max SMA-slope ATR-slope A10/A100 vol/<vol> delta/closep N_upper N_lower MIAE RSI9 KSO);
} else {
    @txt = qw(KSO-slope TR_oc SMA-slope ATR-slope A10/A100 vol/<vol> -- -- -- MIAE RSI9 KSO);
}

$ntxt = @txt;
@x = (11 .. 10+$ntxt);
$j = 0;
foreach $i (@x) {
    `plot.pl -s -x$i -y9 -C9 -z -X"$txt[$j]" -Y"R" $file`;
    print "plotting: $txt[$j]"; $dum = <STDIN>;
    $j++;
}
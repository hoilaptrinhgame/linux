#!/usr/bin/perl
use Data::Dumper;
use strict;

my %hostname = (
"ip-172-31-22-13" => "Kamailio",
"ip-172-31-38-182" => "Asterisk1",
"ip-172-31-45-123" => "Asterisk2",
"ip-172-31-45-175" => "Asterisk3",
);
my $sleep = 320 ;
my $interval = 1;


my $captured_sumary_report='captured_sumary';

our ($sec,$min,$hour,$mday,$mon,$year,$wday, $yday,$isdst) = localtime(time);
our $datestamp = sprintf "%4d%02d%02d-%02d%02d%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec;

my $ext = `cat /proc/sys/kernel/hostname`;
$ext =~ s/\n//;
my $ext1 = $hostname{$ext}."_".$datestamp;
my $ext2 = $ext1.".txt";
#clean old files
`sudo rm captured_* *wav`;
my $pcap = 'sudo tcpdump -G 300 -W 1 -i any -w /home/admin/captured_pkt_'.$ext1.'.pcap > /dev/null';
my $cpu = "sar $interval -u > /home/admin/captured_cpu_".$ext2;
my $mem = "sar $interval -r > /home/admin/captured_mem_".$ext2;
my $network = "sar $interval -n DEV > /home/admin/captured_network_".$ext2;
my $disk = "sar $interval -d > /home/admin/captured_disk_".$ext2;
#my $as_console = "sudo asterisk -rvvvvv > /home/admin/captured_console_".$ext2; hight cpu can not use
my $pcap_pid;
my $memory_pid;
print "$pcap"."\n";
`$pcap &`;
`$cpu &`;
`$mem &`;
`$network &`;
`$disk &`;
# if($hostname{$ext} =~ /Asterisk/){
# `$as_console &`;
# }


print "Capture Waitting..."."\n";
sleep($sleep);
my @output = `sudo ps -ef | grep -E captured`;
foreach (@output){
    if($_ =~ /root\s+(\d+)/){
       `sudo kill $1`;
        print "sudo kill $1\n";
    }
}
sumary_report("/home/admin/captured_cpu_$ext2","/home/admin/captured_mem_$ext2","/home/admin/captured_network_$ext2","/home/admin/captured_network_$ext2","/home/admin/captured_disk_$ext2");

`sudo mv /var/spool/asterisk/monitor/*wav /home/admin/`;
print 'Capture success!'."\n";


sub sumary_report{
    my @files = (@_);
    my @cpus;
    my @mems;
    my @networksI; 
    my @networksO;
    my @networks;
    my @disksR;
    my @disksW;
    my @times;
    foreach(@files){
        if($_ =~ /cpu/){
            open(FH, '<', $_) or die $!;
            while(<FH>){
                unless($_ =~ /CPU/){
                    next unless $_ =~ /(\d+:)+/;
                    my @tmp = split(/\s+/,$_);
                    my $use = 100.00 -  $tmp[7];#100 - idle time = used cpu
                    #print "cpu use: $use\n";
                    push (@cpus,$use);
                    push (@times,$tmp[0]);
                }

            }
            close(FH);
        }elsif($_ =~ /mem/){
            open(FH, '<', $_) or die $!;
            while(<FH>){
                unless($_ =~ /mem|CPU/){
                    next unless $_ =~ /(\d+:)+/;
                    my @tmp = split(/\s+/,$_);
                    push (@mems,$tmp[4]);
                }
            }
            close(FH);
        }elsif($_ =~ /network/){
            open(FH, '<', $_) or die $!;
            while(<FH>){
                unless($_ =~ /IFACE|CPU|lo/){
                    next unless $_ =~ /(\d+:)+/;
                    #print "$_\n";
                    my @tmp = split(/\s+/,$_);
                    my $total = $tmp[4] + $tmp[5];
                    push (@networks,$tmp[5]);   
                    
                }    
            }
            close(FH);
        }elsif($_ =~ /disk/){
            open(FH, '<', $_) or die $!;
            while(<FH>){
                unless($_ =~ /DEV|CPU/){
                    next unless $_ =~ /(\d+:)+/;
                    #print "$_\n";
                    my @tmp = split(/\s+/,$_);
                    push (@disksR,$tmp[3]);
                    push (@disksW,$tmp[4]); 
                }
            }
            close(FH);
        }
        #print "times|cpus|mems|networksI|networksO|disksR|disksW\n";
        #print "$times[$_]|$cpus[$_]|$mems[$_]|$networksI[$_]|$networksO[$_]|$disksR[$_]|$disksW[$_]\n";
    }
    my $max=0;
    my $average=0;
    open(FH, '>', $captured_sumary_report.$hostname{$ext}.".txt") or die $!;
    print ("UMAX|UAVG|RMAX|RAVG|NMAX|NAVG|DRMAX|DRAVG|DWMAX|DWAVG\n");
    print FH ("UMAX|UAVG|RMAX|RAVG|NMAX|NAVG|DRMAX|DRAVG|DWMAX|DWAVG\n");
    conclusion(@cpus);
    conclusion(@mems);
    conclusion(@networks);#?networksO+networksI
    conclusion(@disksR);
    conclusion(@disksW);
    print ("\n");
    print FH ("\n");
    close(FH);
}

sub conclusion{
    my (@input)= @_;
    my $max=0;
    my $average=0;
    my $sum;
    foreach (@input){
        #print "$times[$_]|$cpus[$_]|$mems[$_]|$networksI[$_]|$networksO[$_]|$disksR[$_]|$disksW[$_]\n";
        #print "$_\n";
        if($_ > $max){
            $max = $_;
        }
        $sum += $_;     
    }
   
    $average = $sum/(scalar(@input));
    printf ("%0.2f|%0.2f|",$max, $average);
    printf FH ("%0.2f|%0.2f|",$max, $average);

    return ($max, $average);
}
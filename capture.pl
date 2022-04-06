#!/usr/bin/perl
#this file is ultil for getting statistic log on tenant include kamailio, asterisk
use Data::Dumper;
use strict;
my @caputure_commands=();

my $module = "STARTMEA";
my $useami = 0;
sub exeCmd{
	my ($cmd) = @_;
	my $subname = "exeCmd";
	print "[$module][$subname] Executing: $cmd\n";
    my @output = `$cmd`;
    print @output;
	return @output;
}
sub exeCmds{
	my @cmds = @_;
	my @outputs;
	foreach (@cmds){
		push (@outputs, exeCmd ($_));
	}
	return @outputs;
}
sub stopAllCaptureProcess{
	my $subname = "stopAllCaptureProcess";
	my $cmd = "sudo ps -ef | grep -E 'captured|sar|tail|pidstat'";
		
	print "[$module][$subname] stopAllCaptureProcess via $cmd\n";
	my @outputs = exeCmd($cmd);
	foreach (@outputs){
		if($_ =~ /(root|admin)\s+(\d+)/){
			exeCmd("sudo kill $2");
		}
	}
}
sub checkAllResource{
	my $subname = "checkAllResource";
	my $cmd = "sudo ls -ltr /var/spool/asterisk/monitor/;sudo ls -ltr /var/spool/asterisk/recording/ARI-Dial/;pidstat";
	my (@outputs) = exeCmd($cmd);
	print "[$module][$subname] $_", foreach @outputs;
}
my %hostname = (
    "ip-172-31-22-13" => "Kamailio",
    "ip-172-31-38-182" => "Asterisk1",
    "ip-172-31-45-123" => "Asterisk2",
    "ip-172-31-45-175" => "Asterisk3",
);

my $log_dir = "/home/admin/statistic_log";
#my $log_dir = "/home/admin";
my $sleep = 330 ; #should 310
my $interval = 1;
my $interval_stat =10;

my $captured_sumary_report="$log_dir/captured_sumary";

our ($sec,$min,$hour,$mday,$mon,$year,$wday, $yday,$isdst) = localtime(time);
our $datestamp = sprintf "%4d%02d%02d-%02d%02d%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec;

my $ext = `cat /proc/sys/kernel/hostname`;
$ext =~ s/\n//;
my $ext1 = $hostname{$ext}."_".$datestamp;
my $ext2 = $ext1.".txt";


my $pcap = "sudo tcpdump -G 310 -W 1 -i any -w $log_dir/captured_pkt_".$ext1.'.pcap > /dev/null';
my $cpu = "sar $interval -u > $log_dir/captured_cpu_".$ext2;
my $mem = "sar $interval -r > $log_dir/captured_mem_".$ext2;
my $network = "sar $interval -n DEV > $log_dir/captured_network_".$ext2;
my $disk = "sar $interval -d > $log_dir/captured_disk_".$ext2;

my $asterisk_cpu =  "pidstat $interval_stat -u -G asterisk > $log_dir/asterisk_captured_cpu_".$ext2;
my $asterisk_mem =  "pidstat $interval_stat -r -G asterisk > $log_dir/asterisk_captured_mem_".$ext2;
my $asterisk_disk = "pidstat $interval_stat -d -G asterisk > $log_dir/asterisk_captured_disk_".$ext2;

my $nodejs_cpu =  "pidstat $interval_stat -u -G nodejs > $log_dir/nodejs_captured_cpu_".$ext2;
my $nodejs_mem =  "pidstat $interval_stat -r -G nodejs > $log_dir/nodejs_captured_mem_".$ext2;
my $nodejs_disk = "pidstat $interval_stat -d -G nodejs > $log_dir/nodejs_captured_disk_".$ext2;

my $kamailio_cpu =  "pidstat $interval_stat -u -G kamailio > $log_dir/kamailio_captured_cpu_".$ext2;
my $kamailio_mem =  "pidstat $interval_stat -r -G kamailio > $log_dir/kamailio_captured_mem_".$ext2;
my $kamailio_disk = "pidstat $interval_stat -d -G kamailio > $log_dir/kamailio_captured_disk_".$ext2;

my $as_console = "tail -f /home/admin/console_$hostname{$ext}.txt > $log_dir/captured_console_".$ext2; #hight cpu can not use
my $ari_console = "tail -f /home/admin/AriRecording.log > $log_dir/captured_arirecording_".$ext2;
my $pcap_pid;
my $memory_pid;

#check before test
checkAllResource();
#backup old files to /home/admin/backup/
my $backup_dir = "/home/admin/backup/backup_$ext1";
`mkdir -p $backup_dir`;
my $remov_old_file_cmd = "mv -v $log_dir/* $backup_dir";
`$remov_old_file_cmd`;
print "$remov_old_file_cmd\n";

if($hostname{$ext} =~ /Asterisk/){
    #if it's asterisk we should check ARI and Console
    push (@caputure_commands,"$as_console &");
    push (@caputure_commands,"$ari_console &") if $useami;
}


exeCmds (
    @caputure_commands,
    "$pcap &",
    "$cpu &",
    "$mem &",
    "$network &",
    "$disk &",
);

if($hostname{$ext} =~ /Asterisk/){
    exeCmds (
        "$asterisk_cpu &",
        "$asterisk_mem &",
        "$asterisk_disk &"
    );

    if($useami){   
        exeCmds (
        "$nodejs_cpu &",
        "$nodejs_mem &",
        "$nodejs_disk &"
        );
    }
}

if($hostname{$ext} =~ /Kamailio/){
    exeCmds (
        "$kamailio_cpu &",
        "$kamailio_mem &",
        "$kamailio_disk &"
    );

}


print "Capture Waitting $sleep seconds..."."\n";
sleep($sleep);

#stop all capture process
stopAllCaptureProcess();

#sumary all report
sumary_report("$log_dir/captured_cpu_$ext2","$log_dir/captured_mem_$ext2","$log_dir/captured_network_$ext2","$log_dir/captured_network_$ext2","$log_dir/captured_disk_$ext2");

if($hostname{$ext} =~ /Asterisk/){
	my $arch = $hostname{$ext}."_Audio";
	my $audio_dir = "$log_dir/".$arch;
	my $arch_file="$audio_dir.tar.gz";
	`mkdir -p $audio_dir`;
	my $get_record_cmd = "sudo mv -v /var/spool/asterisk/monitor/*wav $audio_dir";
    if($useami){
        my $get_voice_reconition = "sudo mv -v /var/spool/asterisk/recording/ARI-Dial/* $audio_dir";
        `$get_voice_reconition`;
    }
	
    exeCmds (
      "$get_record_cmd",
      "tar -czvf $arch_file $audio_dir",
      "rm -rf $audio_dir"
    );
}
#check after test
checkAllResource();
my $check_all_process = "pidstat > $log_dir/check_all_process".$ext2;
exeCmds($check_all_process);

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
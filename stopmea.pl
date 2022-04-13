#!/usr/bin/perl
use Data::Dumper;
use strict;

my $module = "STOPMEA";

sub exeCmd{
	my ($cmd) = @_;
	my $subname = "exeCmd";
	print "[$module][$subname] Executing: $cmd\n";
	return `$cmd`;
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
	my $subname = "exeCmd";
	my $cmd = "sudo ps -ef | grep -E 'capture|sar|tail|pidstat'";
		
	print "[$module][$subname] stopAllCaptureProcess via $cmd\n";
	my @outputs = exeCmd($cmd);
	foreach (@outputs){
		if($_ =~ /(root|admin)\s+(\d+)/){
			exeCmd("sudo kill $2");
		}
	}
}
sub cleanAllResource{
	my $subname = "cleanAllResource";
	my $cmd = "sudo rm -r /var/spool/asterisk/monitor/*;sudo rm -r  /var/spool/asterisk/recording/ARI-Dial/*";
	my (@outputs) = exeCmd($cmd);
	print "[$module][$subname] $_", foreach @outputs;
}

sub checkAllResource{
	my $subname = "exeCmd";
	my $cmd = "sudo ls -ltr /var/spool/asterisk/monitor/;sudo ls -ltr /var/spool/asterisk/recording/ARI-Dial/;pidstat";
	my (@outputs) = exeCmd($cmd);
	print "[$module][$subname] $_", foreach @outputs;
}
cleanAllResource();
stopAllCaptureProcess();
checkAllResource();